#!/usr/bin/env bash
# 安装脚本：准备依赖（Python、pip、基础网络工具）并安装 Python 包
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

log() {
  printf '[install] %s\n' "$*"
}

try_pkg_install() {
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y "$@"
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y "$@"
  else
    log "未找到受支持的包管理器，请手动安装: $*"
  fi
}

require_cmd() {
  local cmd="$1"
  local pkg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "缺少依赖 $cmd，尝试安装 $pkg"
    try_pkg_install "$pkg"
  fi
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "依赖 $cmd 未安装成功，请手动安装后重试"
    exit 1
  fi
}

log "检测基础依赖..."
require_cmd curl curl
require_cmd python3 python3
require_cmd pip3 python3-pip
require_cmd ping iputils-ping
require_cmd traceroute traceroute

# sysbench（可选但推荐，提供 CPU 基准更准确）
log "检查/安装 sysbench..."
if ! command -v sysbench >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y sysbench || log "sysbench 安装失败，请手动安装"
  elif command -v yum >/dev/null 2>&1; then
    # 部分发行版需要 epel
    sudo yum install -y epel-release sysbench || sudo yum install -y sysbench || log "sysbench 安装失败，请手动安装"
  else
    log "未找到受支持的包管理器，无法自动安装 sysbench"
  fi
fi
if command -v sysbench >/dev/null 2>&1; then
  log "sysbench 就绪"
else
  log "未检测到 sysbench，将使用核心数估算 CPU 得分"
fi

log "安装 Python 依赖 (requirements.txt)..."
pip3 install -r "${ROOT_DIR}/requirements.txt"

log "安装完成，可运行 ./run.sh 开始测评"

