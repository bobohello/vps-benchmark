#!/usr/bin/env bash
# 一键运行完整测评：收集 -> 评分 -> 可视化
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_ID="${1:-vps-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${ROOT_DIR}/output/${RUN_ID}"

mkdir -p "${OUT_DIR}"

log() {
  printf '[run] %s\n' "$*"
}

run_collect() {
  log "开始数据采集 -> ${OUT_DIR}"
  set +e +u +o pipefail
  bash "${ROOT_DIR}/collect/system.sh" >"${OUT_DIR}/system.json"
  sys_status=$?
  bash "${ROOT_DIR}/collect/network.sh" >"${OUT_DIR}/network.json"
  net_status=$?
  bash "${ROOT_DIR}/collect/route.sh" >"${OUT_DIR}/route.json"
  route_status=$?
  set -euo pipefail

  if [ $sys_status -ne 0 ]; then
    log "system.sh failed"
    cat "${OUT_DIR}/system.json" 2>/dev/null || true
    exit 1
  fi
  if [ $net_status -ne 0 ]; then
    log "network.sh failed"
    exit 1
  fi
  if [ $route_status -ne 0 ]; then
    log "route.sh failed"
    exit 1
  fi

  python3 - <<'PY' "${OUT_DIR}"
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
data = {}
for name in ("system", "network", "route"):
    with open(out / f"{name}.json", "r", encoding="utf-8") as f:
        data[name] = json.load(f)
with open(out / "raw.json", "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PY
}

run_analyze() {
  log "开始评分..."
  python3 "${ROOT_DIR}/analyze/score.py" \
    --input "${OUT_DIR}/raw.json" \
    --output "${OUT_DIR}/score.json"

  log "生成雷达图..."
  python3 "${ROOT_DIR}/analyze/radar.py" \
    --input "${OUT_DIR}/score.json" \
    --output "${OUT_DIR}/radar.png"
}

log "运行 ID: ${RUN_ID}"
run_collect
run_analyze
log "完成！结果路径：${OUT_DIR}"

