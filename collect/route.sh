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
    # 仅处理以数字开头的行（跳过 "traceroute to ..." 头行）
    first_field="$(awk '{print $1}' <<<"$line")"
    [[ "$first_field" =~ ^[0-9]+$ ]] || continue

    hop="$first_field"
    ip="$(awk '{print $2}' <<<"$line")"
    rtt="$(awk '{for(i=3;i<=NF;i++){if($i ~ /ms/){gsub(/ms/,"",$i); print $i; break}}}' <<<"$line")"
    rtt=${rtt:-0}

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

