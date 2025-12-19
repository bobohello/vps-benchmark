#!/usr/bin/env bash
# 采集系统与性能基础信息（轻量化，依赖常见命令）
set -euo pipefail
trap 'echo "{\"error\":\"system.sh failed\"}"' EXIT

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

# CPU 基准（若无 sysbench 则回退估算，并标注来源）
cpu_bench_source="sysbench"
SB_TIMEOUT="${SYSBENCH_TIMEOUT:-15}"

run_sysbench() {
  # $1: threads
  local threads="$1"
  local prime="${SYSBENCH_PRIME:-20000}"
  local duration="${SYSBENCH_TIME:-5}"
  local out status
  set +e
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout "${SB_TIMEOUT}s" sysbench cpu --cpu-max-prime="${prime}" --threads="${threads}" --time="${duration}" --events=0 run 2>/dev/null)"
  else
    out="$(sysbench cpu --cpu-max-prime="${prime}" --threads="${threads}" --time="${duration}" --events=0 run 2>/dev/null)"
  fi
  status=$?
  set -e
  if [ $status -ne 0 ] || [ -z "$out" ]; then
    echo ""
    return 1
  fi
  # 解析 events/s，若没有则用 total events / total time
  printf '%s\n' "$out" | python3 - <<'PY'
import sys, re
text = sys.stdin.read()
eps = None
for line in text.splitlines():
    if "events per second" in line:
        m = re.search(r"events per second:\s*([0-9.+-eE]+)", line)
        if m:
            eps = float(m.group(1)); break
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

cpu_bench_parse() {
  # 从 sysbench 输出中解析 events/s，若未直接给出则用 total events / total time
  python3 - "$@" <<'PY'
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
    events = None
    t = None
    m1 = re.search(r"total number of events:\s*([0-9.+-eE]+)", text)
    m2 = re.search(r"total time:\s*([0-9.+-eE]+)s", text)
    if m1:
        events = float(m1.group(1))
    if m2:
        t = float(m2.group(1))
    if events is not None and t and t > 0:
        eps = events / t
print(f"{eps:.2f}" if eps is not None else "0")
PY
}

cpu_bench_single() {
  if command -v sysbench >/dev/null 2>&1; then
    local val
    val="$(run_sysbench 1 || true)"
    if [ -z "$val" ] || [ "$(printf '%.0f' "$val" 2>/dev/null || echo 0)" -le 0 ]; then
      cpu_bench_source="estimate"
      echo 2000
    else
      echo "$val"
    fi
  else
    cpu_bench_source="estimate"
    echo 2000
  fi
}

cpu_bench_multi() {
  local threads="${cpu_cores:-1}"
  if command -v sysbench >/dev/null 2>&1; then
    local val
    val="$(run_sysbench "${threads}" || true)"
    if [ -z "$val" ] || [ "$(printf '%.0f' "$val" 2>/dev/null || echo 0)" -le 0 ]; then
      cpu_bench_source="estimate"
      echo $((cpu_cores * 4000))
    else
      echo "$val"
    fi
  else
    cpu_bench_source="estimate"
    echo $((cpu_cores * 4000))
  fi
}

# 顺序写入测试（小样本，避免过大压力）
disk_write() {
  local tmp
  tmp="$(mktemp /tmp/vps-bench.XXXX)"
  if LANG=C dd if=/dev/zero of="$tmp" bs=1M count=32 conv=fsync 2>/tmp/ddlog.$$; then
    awk '/copied/ {print $(NF-1)}' /tmp/ddlog.$$
  else
    echo 0
  fi
  rm -f "$tmp" /tmp/ddlog.$$ 2>/dev/null || true
}

# 顺序读取测试（复用写入文件，避免额外 I/O）
disk_read() {
  local tmp
  tmp="$(mktemp /tmp/vps-bench.XXXX)"
  if LANG=C dd if=/dev/zero of="$tmp" bs=1M count=32 conv=fsync 2>/tmp/ddlog.$$; then
    # 使用缓存读取（更贴近应用场景），增加样本体积
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
    "bench_source": $(json_escape "${cpu_bench_source}")
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
trap - EXIT

