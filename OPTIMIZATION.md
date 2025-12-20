# VPS 性能优化指南

本指南介绍如何**合法地**优化VPS性能，提升测试成绩。

## ⚡ 快速优化（推荐）

```bash
# 下载并运行优化脚本
sudo bash optimize.sh

# 重启系统
sudo reboot

# 重启后运行测试
cd ~/vps-benchmark
source .venv/bin/activate
bash run.sh
```

---

## 📊 优化效果预期

| 优化项目 | CPU提升 | 网络提升 | 磁盘提升 |
|---------|---------|----------|----------|
| CPU性能模式 | 5-15% | - | - |
| 内核参数优化 | 2-5% | 10-30% | 5-10% |
| I/O调度器优化 | - | - | 15-25% |
| BBR拥塞控制 | - | 20-50% | - |
| **综合提升** | **8-20%** | **30-80%** | **20-35%** |

---

## 🔧 详细优化方法

### 1. CPU性能优化

#### 1.1 设置CPU性能模式

```bash
# 查看当前CPU调度器
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# 设置为性能模式
sudo bash -c 'echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'

# 或使用cpupower工具
sudo apt install -y linux-tools-generic  # Ubuntu/Debian
sudo cpupower frequency-set -g performance
```

**效果**：CPU主频提升，单核性能提升5-15%

#### 1.2 禁用CPU节能功能

```bash
# 禁用Intel C-States（如果是Intel CPU）
sudo bash -c 'echo 1 > /sys/module/intel_idle/parameters/max_cstate'

# 禁用CPU Turbo Boost节能
sudo bash -c 'echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo'
```

#### 1.3 优化进程优先级

测试时临时提升优先级：

```bash
# 以高优先级运行sysbench
sudo nice -n -20 sysbench cpu --threads=4 --time=15 run
```

---

### 2. 内存优化

#### 2.1 调整Swappiness

```bash
# 查看当前值
cat /proc/sys/vm/swappiness

# 设置为10（减少使用swap）
sudo sysctl vm.swappiness=10
echo "vm.swappiness = 10" | sudo tee -a /etc/sysctl.conf
```

#### 2.2 优化内存缓存策略

```bash
# 优化脏页回写
sudo sysctl vm.dirty_ratio=15
sudo sysctl vm.dirty_background_ratio=5

# 持久化配置
cat << EOF | sudo tee -a /etc/sysctl.conf
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100
EOF
```

#### 2.3 清理缓存（测试前）

```bash
# 释放缓存，确保测试环境一致
sudo sync
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
```

---

### 3. 磁盘I/O优化

#### 3.1 优化I/O调度器

```bash
# 查看当前调度器
cat /sys/block/sda/queue/scheduler

# VPS环境推荐使用none或noop
echo none | sudo tee /sys/block/*/queue/scheduler
# 或
echo noop | sudo tee /sys/block/*/queue/scheduler
```

**调度器选择**：
- `none` - 最适合NVMe SSD和虚拟化环境
- `noop` - 适合SSD和虚拟化
- `deadline` - 适合传统硬盘

#### 3.2 调整预读大小

```bash
# 增加预读缓存（适合顺序读取）
sudo blockdev --setra 8192 /dev/sda
```

#### 3.3 文件系统优化

```bash
# 对于ext4文件系统，禁用atime更新（提升性能）
# 编辑 /etc/fstab，添加 noatime 选项
sudo sed -i 's/errors=remount-ro/noatime,errors=remount-ro/' /etc/fstab
sudo mount -o remount /
```

---

### 4. 网络优化

#### 4.1 启用BBR拥塞控制

```bash
# 检查内核是否支持BBR
lsmod | grep tcp_bbr

# 加载BBR模块
sudo modprobe tcp_bbr
echo "tcp_bbr" | sudo tee -a /etc/modules

# 启用BBR
cat << EOF | sudo tee -a /etc/sysctl.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

sudo sysctl -p
```

**效果**：网络吞吐量提升20-50%，特别是高延迟网络

#### 4.2 优化TCP参数

```bash
cat << EOF | sudo tee -a /etc/sysctl.conf
# TCP接收/发送缓冲区
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# TCP连接优化
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 32768

# 快速回收TIME_WAIT
net.ipv4.tcp_timestamps = 1
EOF

sudo sysctl -p
```

#### 4.3 优化网卡参数

```bash
# 增加网卡接收队列
sudo ethtool -G eth0 rx 4096 tx 4096 2>/dev/null || true

# 启用网卡offload功能
sudo ethtool -K eth0 tso on gso on gro on 2>/dev/null || true
```

---

### 5. 系统级优化

#### 5.1 提升文件描述符限制

```bash
# 临时设置
ulimit -n 1000000

# 永久设置
cat << EOF | sudo tee -a /etc/security/limits.conf
* soft nofile 1000000
* hard nofile 1000000
* soft nproc 1000000
* hard nproc 1000000
EOF
```

#### 5.2 禁用不必要的服务

```bash
# 查看运行中的服务
systemctl list-units --type=service --state=running

# 禁用不必要的服务（示例）
sudo systemctl disable bluetooth
sudo systemctl disable cups
sudo systemctl disable avahi-daemon
sudo systemctl stop bluetooth cups avahi-daemon
```

#### 5.3 减少系统日志

```bash
# 减少日志写入频率
sudo systemctl stop rsyslog
sudo systemctl disable rsyslog
```

---

## 🎯 针对性优化

### 优化CPU测试分数

```bash
# 1. 确保CPU运行在最高频率
sudo cpupower frequency-set -g performance

# 2. 关闭其他进程
sudo killall -9 snapd packagekitd 2>/dev/null || true

# 3. 清理缓存
sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'

# 4. 高优先级运行测试
cd ~/vps-benchmark
source .venv/bin/activate
sudo nice -n -20 bash run.sh
```

### 优化磁盘测试分数

```bash
# 1. 使用none I/O调度器
echo none | sudo tee /sys/block/*/queue/scheduler

# 2. 禁用磁盘写缓存同步（仅测试用）
echo temporary | sudo tee /sys/block/*/queue/write_cache

# 3. 增加脏页比例
sudo sysctl vm.dirty_ratio=80
sudo sysctl vm.dirty_background_ratio=50
```

### 优化网络测试分数

```bash
# 1. 启用BBR
sudo modprobe tcp_bbr
sudo sysctl net.ipv4.tcp_congestion_control=bbr

# 2. 选择最近的测速服务器
speedtest --servers  # 查看服务器列表
speedtest --server-id=xxxxx  # 使用指定服务器

# 3. 临时增大缓冲区
sudo sysctl net.core.rmem_max=134217728
sudo sysctl net.core.wmem_max=134217728
```

---

## ⚠️ 注意事项

### ✅ 合法优化（推荐）
- 调整内核参数
- 优化I/O调度器
- 启用BBR拥塞控制
- 设置CPU性能模式
- 清理系统缓存
- 禁用不必要的服务

### ⚡ 激进优化（谨慎使用）
- 禁用日志服务
- 调整脏页参数
- 临时提升进程优先级
- 修改文件系统挂载选项

### ❌ 不推荐（可能导致问题）
- 超频CPU（VPS通常不支持）
- 完全禁用swap（可能OOM）
- 禁用防火墙（安全风险）
- 修改虚拟化层设置（可能被商家检测）

---

## 📈 验证优化效果

```bash
# 优化前测试
cd ~/vps-benchmark
source .venv/bin/activate
bash run.sh
mv output/$(ls -t output | head -1) output/before-optimization

# 应用优化
sudo bash optimize.sh
sudo reboot

# 优化后测试
cd ~/vps-benchmark
source .venv/bin/activate
bash run.sh
mv output/$(ls -t output | head -1) output/after-optimization

# 对比结果
cat output/before-optimization/score.json | jq '.dimensions'
cat output/after-optimization/score.json | jq '.dimensions'
```

---

## 🔄 恢复原始配置

```bash
# 恢复sysctl配置
sudo cp /etc/sysctl.conf.bak /etc/sysctl.conf
sudo sysctl -p

# 恢复CPU调度器
echo ondemand | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# 重启系统
sudo reboot
```

---

## 💡 最佳实践

1. **测试前准备**：
   - 清理缓存
   - 关闭不必要的服务
   - 确保系统空闲

2. **多次测试**：
   - 运行3-5次取平均值
   - 避免单次测试的偶然性

3. **记录配置**：
   - 记录每次优化的参数
   - 便于回滚和对比

4. **安全第一**：
   - 优化前备份配置
   - 在测试环境验证
   - 生产环境谨慎使用

---

## 📚 参考资源

- [Linux Performance](http://www.brendangregg.com/linuxperf.html)
- [BBR Congestion Control](https://github.com/google/bbr)
- [Sysctl Configuration](https://www.kernel.org/doc/Documentation/sysctl/)
- [I/O Schedulers](https://www.kernel.org/doc/Documentation/block/switching-sched.txt)
