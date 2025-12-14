#!/usr/bin/env bash
# 网络质量采集：ping 为主，若存在 speedtest-cli 则补充带宽
set -euo pipefail

TARGETS=${PING_TARGETS:-"1.1.1.1 8.8.8.8"}

json_escape() {
  printf '%s' "$1" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"
}

latencies=()
losses=()
detail=""

for host in $TARGETS; do
  if command -v ping >/dev/null 2>&1; then
    result="$(ping -c 4 -q "$host" 2>/dev/null || true)"
    avg="$(awk -F'/' '/rtt/ {print $5}' <<<"$result")"
    loss="$(awk -F',' '/packet loss/ {gsub(/%/,""); print $3}' <<<"$result" | awk '{print $1}')"
    avg=${avg:-0}
    loss=${loss:-100}
  else
    avg=0
    loss=100
  fi
  latencies+=("$avg")
  losses+=("$loss")
  detail="${detail}{
    \"target\": $(json_escape "$host"),
    \"avg_ms\": ${avg},
    \"packet_loss_pct\": ${loss}
  },"
done

avg_latency=0
avg_loss=0
count=${#latencies[@]}
if [ "$count" -gt 0 ]; then
  for v in "${latencies[@]}"; do avg_latency=$(python3 - <<PY "$avg_latency" "$v" "$count"
import sys
cur, val, n = map(float, sys.argv[1:])
print(cur + val / n)
PY
  ); done
  for v in "${losses[@]}"; do avg_loss=$(python3 - <<PY "$avg_loss" "$v" "$count"
import sys
cur, val, n = map(float, sys.argv[1:])
print(cur + val / n)
PY
  ); done
fi

bandwidth_mbps=0
if command -v speedtest >/dev/null 2>&1; then
  json="$(speedtest -f json 2>/dev/null || true)"
  bandwidth_mbps="$(python3 - <<'PY' "$json"
import json, sys
data = json.loads(sys.argv[1]) if sys.argv[1] else {}
down = data.get("download", {}).get("bandwidth", 0) * 8 / 1e6  # bytes/s -> Mbps
print(round(down, 2))
PY
  )"
elif command -v speedtest-cli >/dev/null 2>&1; then
  bandwidth_mbps="$(speedtest-cli --simple 2>/dev/null | awk '/Download/ {print $2}')"
fi

cat <<EOF
{
  "latency_ms": ${avg_latency:-0},
  "packet_loss_pct": ${avg_loss:-0},
  "bandwidth_mbps": ${bandwidth_mbps:-0},
  "targets": [
    ${detail%,}
  ]
}
EOF

