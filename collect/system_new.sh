#!/usr/bin/env bash
# 采集系统信息（CPU/内存/磁盘），关闭 errexit/nounset/pipefail，优先用 sysbench，失败才兜底
set +e
set +u
set +o pipefail

json_escape() {
  python3 - <<'PY' "$1"
import json, sys
print(json.dumps(sys.argv[1]))
PY
}

# 基本信息
cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/^.*model name[ \t]*:[ \t]*//')"
cpu_cores="$(nproc 2>/dev/null || echo 0)"
cpu_bogomips="$(grep -m1 'bogomips' /proc/cpuinfo 2>/dev/null | awk '{print $3}')"
mem_total_kb="$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo)"
mem_free_kb="$(awk '/MemAvailable/ {print $2; exit}' /proc/meminfo)"

line="$(df -PB1 / 2>/dev/null | awk 'NR==2')"
disk_total_bytes="$(awk '{print $2}' <<<"${line:-0}")"
disk_used_bytes="$(awk '{print $3}' <<<"${line:-0}")"

# sysbench 采集
run_sysbench() {
  local threads="$1"
  local prime="${SYSBENCH_PRIME:-80000}"
  local duration="${SYSBENCH_TIME:-15}"
  local out status
  out="$(sysbench cpu --cpu-max-prime="$prime" --threads="$threads" --time="$duration" --events=0 run 2>&1)"
  status=$?
  printf '%s\n' "$out" >"/tmp/vps-bench-sysbench-${threads}.log"
  if [ $status -ne 0 ] || [ -z "$out" ]; then
    echo ""
    return 1
  fi
  printf '%s\n' "$out" | python3 - <<'PY'
import sys, re
text = sys.stdin.read()
eps = None
for line in text.splitlines():
    if "events per second" in line:
        m = re.search(r"events per second:\s*([0-9.+-eE]+)", line)
        if m:
            eps = float(m.group(1))
            break
if eps is None:
    ev = None; tt = None
    m1 = re.search(r"total number of events:\s*([0-9.+-eE]+)", text)
    m2 = re.search(r"total time:\s*([0-9.+-eE]+)s", text)
    if m1: ev = float(m1.group(1))
    if m2: tt = float(m2.group(1))
    if ev is not None and tt and tt > 0:
        eps = ev / tt
print(f"{eps:.2f}" if eps is not None else "")
PY
}

cpu_bench_source="sysbench"

cpu_bench_single() {
  if command -v sysbench >/dev/null 2>&1; then
    local val; val="$(run_sysbench 1 || true)"
    if [ -z "$val" ] || [ "$(printf '%.0f' "$val" 2>/dev/null || echo 0)" -le 0 ]; then
      cpu_bench_source="estimate-bogomips"
      python3 - <<PY "$cpu_bogomips"
import sys
b = float(sys.argv[1]) if sys.argv[1] else 1.0
print(f"{b*800:.2f}")
PY
    else
      echo "$val"
    fi
  else
    cpu_bench_source="estimate-fallback"
    # 使用更智能的估算：基于bogomips，如果没有则给保守值
    if [ -n "$cpu_bogomips" ] && [ "$(printf '%.0f' "$cpu_bogomips" 2>/dev/null || echo 0)" -gt 0 ]; then
      python3 - <<PY "$cpu_bogomips"
import sys
b = float(sys.argv[1]) if sys.argv[1] else 1.0
# bogomips 通常在 4000-8000 范围，转换为 events/s 大约是 bogomips * 0.5
print(f"{b*0.5:.2f}")
PY
    else
      echo 2000
    fi
  fi
}

cpu_bench_multi() {
  local threads="$cpu_cores"
  if [ -z "$threads" ] || [ "$threads" -le 0 ] 2>/dev/null; then threads=1; fi
  if command -v sysbench >/dev/null 2>&1; then
    local val; val="$(run_sysbench "$threads" || true)"
    if [ -z "$val" ] || [ "$(printf '%.0f' "$val" 2>/dev/null || echo 0)" -le 0 ]; then
      cpu_bench_source="estimate-bogomips"
      python3 - <<PY "$cpu_bogomips" "$threads"
import sys
b = float(sys.argv[1]) if sys.argv[1] else 1.0
c = float(sys.argv[2]) if sys.argv[2] else 1.0
print(f"{b*800*c:.2f}")
PY
    else
      echo "$val"
    fi
  else
    cpu_bench_source="estimate-fallback"
    # 使用更智能的估算：基于bogomips和核心数
    if [ -n "$cpu_bogomips" ] && [ "$(printf '%.0f' "$cpu_bogomips" 2>/dev/null || echo 0)" -gt 0 ]; then
      python3 - <<PY "$cpu_bogomips" "$threads"
import sys
b = float(sys.argv[1]) if sys.argv[1] else 1.0
c = float(sys.argv[2]) if sys.argv[2] else 1.0
# 多核性能通常不是线性扩展，使用 0.85 的扩展系数
print(f"{b*0.5*c*0.85:.2f}")
PY
    else
      echo $((threads * 4000))
    fi
  fi
}

# 磁盘顺序读写（轻量）
disk_write() {
  local tmp; tmp="$(mktemp /tmp/vps-bench.XXXX)"
  if LANG=C dd if=/dev/zero of="$tmp" bs=1M count=32 conv=fsync 2>/tmp/ddlog.$$; then
    awk '/copied/ {print $(NF-1)}' /tmp/ddlog.$$
  else
    echo 0
  fi
  rm -f "$tmp" /tmp/ddlog.$$ 2>/dev/null || true
}

disk_read() {
  local tmp; tmp="$(mktemp /tmp/vps-bench.XXXX)"
  if LANG=C dd if=/dev/zero of="$tmp" bs=1M count=32 conv=fsync 2>/tmp/ddlog.$$; then
    if LANG=C dd if="$tmp" of=/dev/null bs=1M count=64 2>/tmp/ddlog_read.$$; then
      awk '/copied/ {print $(NF-1)}' /tmp/ddlog_read.$$
    else
      echo 0
    fi
  else
    echo 0
  fi
  rm -f "$tmp" /tmp/ddlog.$$ /tmp/ddlog_read.$$ 2>/dev/null || true
}

CPU_SINGLE="$(cpu_bench_single)"
CPU_MULTI="$(cpu_bench_multi)"
DISK_WRITE_MB_S="$(disk_write)"
DISK_READ_MB_S="$(disk_read)"

cat <<EOF
{
  "cpu": {
    "model": $(json_escape "${cpu_model:-unknown}"),
    "cores": ${cpu_cores:-0},
    "bench_single": ${CPU_SINGLE:-0},
    "bench_multi": ${CPU_MULTI:-0},
    "bench_source": $(json_escape "${cpu_bench_source}"),
    "bogomips": ${cpu_bogomips:-0}
  },
  "memory": {
    "total_kb": ${mem_total_kb:-0},
    "available_kb": ${mem_free_kb:-0}
  },
  "disk": {
    "total_bytes": ${disk_total_bytes:-0},
    "used_bytes": ${disk_used_bytes:-0},
    "write_MB_s": ${DISK_WRITE_MB_S:-0},
    "read_MB_s": ${DISK_READ_MB_S:-0}
  }
}
EOF
exit 0

