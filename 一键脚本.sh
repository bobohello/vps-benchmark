#!/usr/bin/env bash
# VPS性能测试一键部署脚本
# 支持 Ubuntu/Debian 系统
set -e

echo "========================================"
echo "  VPS 性能测试 - 一键部署脚本"
echo "========================================"
echo ""

# 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "错误：无法检测系统类型"
    exit 1
fi

echo "检测到系统: $OS"
echo ""

# 1) 安装基础依赖
echo "[1/7] 安装基础依赖..."
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    sudo apt update -qq
    sudo apt install -y python3 python3-venv python3-pip curl git \
        iputils-ping traceroute sysbench >/dev/null 2>&1
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    sudo yum install -y python3 python3-pip curl git \
        iputils traceroute sysbench >/dev/null 2>&1
else
    echo "警告：未知系统，尝试使用 apt..."
    sudo apt update -qq && sudo apt install -y python3 python3-venv python3-pip \
        curl git iputils-ping traceroute sysbench >/dev/null 2>&1
fi
echo "✓ 基础依赖安装完成"
echo ""

# 2) 安装 sysbench（如果还没安装）
echo "[2/7] 检查 sysbench..."
if ! command -v sysbench >/dev/null 2>&1; then
    echo "正在安装 sysbench..."
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        sudo apt install -y sysbench >/dev/null 2>&1
    else
        sudo yum install -y sysbench >/dev/null 2>&1
    fi
    echo "✓ sysbench 安装完成"
else
    echo "✓ sysbench 已安装 ($(sysbench --version | head -1))"
fi
echo ""

# 3) 安装测速工具
echo "[3/7] 安装测速工具..."
if ! command -v speedtest >/dev/null 2>&1; then
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
        sudo apt install -y speedtest >/dev/null 2>&1
    else
        echo "警告：请手动安装 speedtest"
    fi
fi
echo "✓ 测速工具安装完成"
echo ""

# 4) 克隆代码
echo "[4/7] 克隆项目代码..."
if [ -d "vps-benchmark" ]; then
    echo "目录已存在，更新代码..."
    cd vps-benchmark
    git pull origin main >/dev/null 2>&1
else
    git clone https://github.com/bobohello/vps-benchmark.git >/dev/null 2>&1
    cd vps-benchmark
fi
echo "✓ 代码准备完成"
echo ""

# 5) 创建虚拟环境
echo "[5/7] 配置 Python 环境..."
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi
source .venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt
echo "✓ Python 环境配置完成"
echo ""

# 6) 接受 speedtest 许可
echo "[6/7] 配置 speedtest..."
if command -v speedtest >/dev/null 2>&1; then
    speedtest --accept-license --accept-gdpr -f json >/dev/null 2>&1 || true
    echo "✓ speedtest 配置完成"
else
    echo "⚠ speedtest 未安装，将跳过网络测速"
fi
echo ""

# 7) 运行测试
echo "[7/7] 开始运行性能测试..."
echo "========================================"
bash run.sh

# 显示结果
echo ""
echo "========================================"
echo "  测试完成！"
echo "========================================"
latest=$(ls -t output/ | head -1)
echo "结果目录: output/$latest"
echo ""
echo "查看雷达图："
echo "  output/$latest/radar.png"
echo ""
echo "查看详细分数："
echo "  cat output/$latest/score.json | python3 -m json.tool"
echo ""