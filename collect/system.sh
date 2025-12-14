#!/usr/bin/env bash
# 采集系统与性能基础信息（轻量化，依赖常见命令）
set -euo pipefail

json_escape() {
  printf '%s' "$1" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"
}

cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //')"
cpu_cores="$(nproc 2>/dev/null || echo 0)"
mem_total_kb="$(grep -m1 MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')"
mem_free_kb="$(grep -m1 MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')"

disk_line="$(df -PB1 / 2>/dev/null | awk 'NR==2')"
disk_total_bytes="$(awk '{print $2}' <<<"${disk_line:-0}")"
disk_used_bytes="$(awk '{print $3}' <<<"${disk_line:-0}")"

# CPU 粗略分值（若无 sysbench 则按核心数估算）
cpu_bench() {
  if command -v sysbench >/dev/null 2>&1; then
    sysbench cpu --cpu-max-prime=2000 run 2>/dev/null | awk '/events per second/ {print int($4)}' | tail -n1
  else
    echo $((cpu_cores * 1000))
  fi
}

# 简单写入测试（小样本，避免对磁盘产生较大压力）
disk_write() {
  local tmp
  tmp="$(mktemp /tmp/vps-bench.XXXX)"
  if dd if=/dev/zero of="$tmp" bs=1M count=16 conv=fsync 2>/tmp/ddlog.$$; then
    awk '/copied/ {print $(NF-1)}' /tmp/ddlog.$$
  else
    echo 0
  fi
  rm -f "$tmp" /tmp/ddlog.$$ 2>/dev/null || true
}

CPU_SCORE="$(cpu_bench)"
DISK_WRITE_MB_S="$(disk_write)"

cat <<EOF
{
  "cpu": {
    "model": $(json_escape "${cpu_model:-unknown}"),
    "cores": ${cpu_cores:-0},
    "bench_score": ${CPU_SCORE:-0}
  },
  "memory": {
    "total_kb": ${mem_total_kb:-0},
    "available_kb": ${mem_free_kb:-0}
  },
  "disk": {
    "total_bytes": ${disk_total_bytes:-0},
    "used_bytes": ${disk_used_bytes:-0},
    "write_MB_s": ${DISK_WRITE_MB_S:-0}
  }
}
EOF

