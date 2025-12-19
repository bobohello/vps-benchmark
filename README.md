# VPS Benchmark

一键可复现的 VPS 测评框架，支持采集、评分、可视化与对比。真实测量CPU性能（基于sysbench）、网络延迟、带宽、磁盘IO等指标，生成直观的雷达图。

## 🚀 一键部署（推荐）

在**全新的VPS**上运行以下命令，自动安装所有依赖并完成测试：

```bash
curl -fsSL https://raw.githubusercontent.com/bobohello/vps-benchmark/main/quickstart.sh | bash
```

**或者下载后执行**：

```bash
wget https://raw.githubusercontent.com/bobohello/vps-benchmark/main/quickstart.sh
bash quickstart.sh
```

## 📦 手动安装

如果已经克隆了仓库：

```bash
# 1. 安装依赖
bash install.sh

# 2. 运行测试
bash run.sh
```

## 🔄 再次运行

如果已经安装过，想再次测试：

```bash
cd ~/vps-benchmark
source .venv/bin/activate
bash run.sh
```

## 📊 查看结果

测试完成后，结果会保存在 `output/` 目录下：

```bash
# 查看最新的测试结果
latest=$(ls -t output/ | head -1)

# 查看雷达图（需要下载到本地查看）
scp user@vps:~/vps-benchmark/output/$latest/radar.png ./

# 查看详细评分
cat output/$latest/score.json | python3 -m json.tool

# 查看原始数据
cat output/$latest/raw.json | python3 -m json.tool
```

## 📁 目录说明

- `quickstart.sh`：一键部署脚本（推荐）
- `install.sh`：安装依赖
- `run.sh`：运行完整测试流程
- `collect/`：数据采集脚本
  - `system_new.sh`：CPU、内存、磁盘性能测试（基于sysbench）
  - `network.sh`：网络延迟、带宽测试
  - `route.sh`：路由跟踪
- `analyze/`：数据分析与可视化
  - `score.py`：评分引擎
  - `radar.py`：生成雷达图
  - `rank.py`：排行榜
  - `compare.py`：对比分析
- `templates/`：HTML 模板
- `output/`：测试结果输出目录

## 🎯 测试指标

### CPU性能
- 使用 sysbench CPU 测试（prime=80000）
- 单核性能（events/s）
- 多核性能（events/s）
- 真实反映不同CPU型号的性能差异

### 网络性能
- 延迟（Latency）
- 抖动（Jitter）
- 丢包率（Packet Loss）
- 带宽（Bandwidth）- 使用 Ookla Speedtest

### 磁盘性能
- 顺序写入速度（MB/s）
- 顺序读取速度（MB/s）

### 路由质量
- 跳数
- 最大延迟
- 路由稳定性

## 🔧 系统要求

- **操作系统**：Ubuntu 18.04+ / Debian 10+ / CentOS 7+ / Rocky Linux 8+
- **Python**：3.6+
- **依赖工具**：sysbench, speedtest, traceroute, git

## ⚠️ 注意事项

1. **网络测试**：speedtest 会消耗较多流量（约100-500MB），如果VPS流量有限请注意
2. **测试时长**：完整测试需要约2-3分钟
3. **权限要求**：某些操作可能需要 sudo 权限

## 🐛 问题排查

### sysbench 未安装
```bash
# Ubuntu/Debian
sudo apt install -y sysbench

# CentOS/RHEL
sudo yum install -y sysbench
```

### speedtest 未安装
```bash
# Ubuntu/Debian
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
sudo apt install -y speedtest
```

### Python 依赖问题
```bash
cd ~/vps-benchmark
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

## 📈 后续计划

- [ ] 支持更多性能指标（内存带宽、网络多点测试）
- [ ] Web界面展示测试结果
- [ ] 数据库存储历史测试数据
- [ ] 多VPS对比分析
- [ ] 自动化定时测试

## 📝 License

MIT

