#!/usr/bin/env bash
# 网络质量采集：多目标 ping（均值/分位/抖动/丢包）+ 可选带宽测速
set -euo pipefail

TARGETS=${PING_TARGETS:-"1.1.1.1 8.8.8.8"}
PING_COUNT=${PING_COUNT:-6}

# 收集 ping 结果
rows=()
for host in $TARGETS; do
  if command -v ping >/dev/null 2>&1; then
    result="$(ping -c "$PING_COUNT" -q "$host" 2>/dev/null || true)"
    # 提取 rtt min/avg/max/mdev 与丢包
    avg="$(awk -F'/' '/rtt/ {print $5}' <<<"$result")"
    min="$(awk -F'/' '/rtt/ {print $4}' <<<"$result")"
    max="$(awk -F'/' '/rtt/ {print $6}' <<<"$result")"
    mdev="$(awk -F'/' '/rtt/ {print $7}' <<<"$result")"
    loss="$(awk -F',' '/packet loss/ {gsub(/%/,""); print $3}' <<<"$result" | awk '{print $1}')"
  else
    avg=0; min=0; max=0; mdev=0; loss=100
  fi
  rows+=("${host},${avg:-0},${min:-0},${max:-0},${mdev:-0},${loss:-100}")
done

# 带宽测速（若可用 speedtest 或 speedtest-cli）
bandwidth_mbps=0
bandwidth_source="none"

if command -v speedtest >/dev/null 2>&1; then
  st_json="$(speedtest -f json 2>/dev/null || true)"
  bandwidth_mbps="$(python3 - <<'PY' "$st_json"
import json, sys
data = json.loads(sys.argv[1]) if sys.argv[1] else {}
down = data.get("download", {}).get("bandwidth", 0) * 8 / 1e6  # bytes/s -> Mbps
print(round(down, 2))
PY
  )"
  bandwidth_source="speedtest"
elif command -v speedtest-cli >/dev/null 2>&1; then
  st_json="$(speedtest-cli --json 2>/dev/null || true)"
  bandwidth_mbps="$(python3 - <<'PY' "$st_json"
import json, sys
data = json.loads(sys.argv[1]) if sys.argv[1] else {}
down = data.get("download", 0) / 1e6  # bit/s -> Mbps
print(round(down, 2))
PY
  )"
  bandwidth_source="speedtest-cli"
fi

# 用 Python 汇总统计并输出 JSON
python3 - <<'PY' "${rows[@]}" "$bandwidth_mbps" "$bandwidth_source"
import json, statistics, sys

args = sys.argv[1:]
if len(args) < 2:
    print(json.dumps({"error": "no data"}, ensure_ascii=False))
    sys.exit(0)

bandwidth_mbps = float(args[-2])
bandwidth_source = args[-1]
row_args = args[:-2]

targets = []
lat_avgs = []
losses = []
jitters = []

def pctl(values, pct):
    if not values:
        return 0.0
    values = sorted(values)
    k = (len(values) - 1) * pct / 100.0
    f = int(k)
    c = min(f + 1, len(values) - 1)
    if f == c:
        return values[f]
    return values[f] + (values[c] - values[f]) * (k - f)

def to_float(val):
    import re
    m = re.search(r"[-+]?\d*\.?\d+", val or "")
    return float(m.group()) if m else 0.0

for row in row_args:
    host, avg, min_, max_, mdev, loss = row.split(",")
    avg = to_float(avg)
    min_ = to_float(min_)
    max_ = to_float(max_)
    mdev = to_float(mdev)
    loss = to_float(loss)

    targets.append(
        {
            "target": host,
            "avg_ms": avg,
            "min_ms": min_,
            "max_ms": max_,
            "jitter_ms": mdev,
            "packet_loss_pct": loss,
        }
    )
    if avg > 0:
        lat_avgs.append(avg)
    jitters.append(mdev)
    losses.append(loss)

latency_ms = statistics.mean(lat_avgs) if lat_avgs else 0.0
latency_p90_ms = pctl(lat_avgs, 90) if lat_avgs else 0.0
jitter_ms = statistics.mean(jitters) if jitters else 0.0
packet_loss_pct = statistics.mean(losses) if losses else 0.0

out = {
    "latency_ms": round(latency_ms, 3),
    "latency_p90_ms": round(latency_p90_ms, 3),
    "jitter_ms": round(jitter_ms, 3),
    "packet_loss_pct": round(packet_loss_pct, 3),
    "bandwidth_mbps": float(bandwidth_mbps or 0),
    "bandwidth_source": bandwidth_source,
    "targets": targets,
}

print(json.dumps(out, ensure_ascii=False, indent=2))
PY

