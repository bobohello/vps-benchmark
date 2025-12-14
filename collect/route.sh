#!/usr/bin/env bash
# 路由路径采集：优先 traceroute，缺失时输出空数据
set -euo pipefail

TARGET=${ROUTE_TARGET:-1.1.1.1}

json_escape() {
  printf '%s' "$1" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"
}

hop_entries=""
hop_count=0
max_rtt_ms=0

if command -v traceroute >/dev/null 2>&1; then
  while IFS= read -r line; do
    hop="$(awk '{print $1}' <<<"$line")"
    ip="$(awk '{print $2}' <<<"$line")"
    rtt="$(awk '{for(i=3;i<=NF;i++){if($i ~ /ms/){print $i; break}}}' <<<"$line" | sed 's/ms//')"
    rtt=${rtt:-0}
    [ -z "$hop" ] && continue
    hop_count=$hop
    if (( $(printf "%.0f" "$rtt") > $(printf "%.0f" "$max_rtt_ms") )); then
      max_rtt_ms="$rtt"
    fi
    hop_entries="${hop_entries}{
      \"hop\": ${hop},
      \"ip\": $(json_escape "${ip:-*}"),
      \"rtt_ms\": ${rtt}
    },"
  done < <(traceroute -n -q 1 -w 2 "$TARGET" 2>/dev/null || true)
else
  hop_entries=""
  hop_count=0
  max_rtt_ms=0
fi

cat <<EOF
{
  "target": $(json_escape "$TARGET"),
  "hops": [
    ${hop_entries%,}
  ],
  "hop_count": ${hop_count:-0},
  "max_rtt_ms": ${max_rtt_ms:-0}
}
EOF

