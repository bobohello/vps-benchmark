#!/usr/bin/env bash
# VPS Benchmark Quick Start Script
# Usage: curl -sSL https://raw.githubusercontent.com/bobohello/vps-benchmark/main/quickstart.sh | bash

set -e

echo "========================================"
echo "  VPS Benchmark Quick Start"
echo "========================================"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    SUDO=""
else 
    SUDO="sudo"
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

echo "Detected OS: $OS"
echo ""

# Install dependencies
echo "[1/6] Installing dependencies..."
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    $SUDO apt-get update -qq
    $SUDO apt-get install -y python3 python3-venv python3-pip curl git \
        iputils-ping traceroute sysbench >/dev/null 2>&1
    
    # Install speedtest
    if ! command -v speedtest >/dev/null 2>&1; then
        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | $SUDO bash
        $SUDO apt-get install -y speedtest >/dev/null 2>&1
    fi
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    $SUDO yum install -y epel-release -y
    $SUDO yum install -y python3 python3-pip curl git \
        iputils traceroute sysbench >/dev/null 2>&1
else
    echo "Warning: Unknown OS, trying apt-get..."
    $SUDO apt-get update -qq
    $SUDO apt-get install -y python3 python3-venv python3-pip curl git \
        iputils-ping traceroute sysbench >/dev/null 2>&1
fi
echo "✓ Dependencies installed"
echo ""

# Clone or update repository
echo "[2/6] Getting code..."
cd ~
if [ -d "vps-benchmark" ]; then
    echo "Directory exists, updating..."
    cd vps-benchmark
    git pull origin main >/dev/null 2>&1
else
    git clone https://github.com/bobohello/vps-benchmark.git
    cd vps-benchmark
fi
echo "✓ Code ready"
echo ""

# Setup Python environment
echo "[3/6] Setting up Python environment..."
python3 -m venv .venv
source .venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt
echo "✓ Python environment ready"
echo ""

# Configure speedtest
echo "[4/6] Configuring speedtest..."
if command -v speedtest >/dev/null 2>&1; then
    speedtest --accept-license --accept-gdpr -f json >/dev/null 2>&1 || true
    echo "✓ Speedtest configured"
else
    echo "⚠ Speedtest not available, network tests will be skipped"
fi
echo ""

# Clean old results
echo "[5/6] Cleaning old results..."
rm -rf output/ __pycache__ analyze/__pycache__ 2>/dev/null || true
echo "✓ Clean complete"
echo ""

# Run benchmark
echo "[6/6] Running benchmark..."
echo "========================================"
bash run.sh

# Show results
echo ""
echo "========================================"
echo "  Benchmark Complete!"
echo "========================================"
latest=$(ls -t output/ | head -1)
echo ""
echo "Results location: ~/vps-benchmark/output/$latest"
echo ""
echo "View radar chart:"
echo "  output/$latest/radar.png"
echo ""
echo "View scores:"
echo "  cat output/$latest/score.json | python3 -m json.tool"
echo ""
echo "To run again:"
echo "  cd ~/vps-benchmark && source .venv/bin/activate && bash run.sh"
echo ""
