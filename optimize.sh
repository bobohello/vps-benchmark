#!/usr/bin/env bash
# VPS性能优化脚本
# 注意：某些优化可能影响系统稳定性，请谨慎使用

set -e

echo "========================================"
echo "  VPS 性能优化脚本"
echo "========================================"
echo ""

# 检查是否为root
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 root 权限运行此脚本: sudo bash optimize.sh"
    exit 1
fi

# 1. CPU性能优化
echo "[1/6] CPU性能优化..."

# 设置CPU为性能模式（如果支持）
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    echo "设置CPU调度器为性能模式..."
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance > "$cpu" 2>/dev/null || true
    done
    echo "✓ CPU调度器已设置为性能模式"
else
    echo "⚠ 此系统不支持CPU频率调整"
fi

# 禁用CPU节能功能
if command -v cpupower >/dev/null 2>&1; then
    cpupower frequency-set -g performance 2>/dev/null || true
    echo "✓ 已通过cpupower设置性能模式"
fi

echo ""

# 2. 内核参数优化
echo "[2/6] 内核参数优化..."

# 备份原始配置
if [ ! -f /etc/sysctl.conf.bak ]; then
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    echo "✓ 已备份原始配置到 /etc/sysctl.conf.bak"
fi

# 优化内核参数
cat >> /etc/sysctl.conf <<EOF

# VPS性能优化配置
# 网络优化
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# 减少TIME_WAIT状态连接
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# 提高文件描述符限制
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

# 虚拟内存优化
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# 网络连接优化
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 16384
EOF

# 应用配置
sysctl -p >/dev/null 2>&1
echo "✓ 内核参数优化完成"
echo ""

# 3. 禁用不必要的服务
echo "[3/6] 优化系统服务..."

# 停止不必要的服务（谨慎操作）
services_to_disable=(
    "bluetooth"
    "cups"
    "avahi-daemon"
    "ModemManager"
)

for service in "${services_to_disable[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
        echo "✓ 已禁用服务: $service"
    fi
done
echo ""

# 4. 磁盘I/O优化
echo "[4/6] 磁盘I/O优化..."

# 设置I/O调度器为deadline或noop（适合虚拟化环境）
for disk in /sys/block/*/queue/scheduler; do
    if [ -f "$disk" ]; then
        # 优先使用none（内核5.0+），然后noop，最后deadline
        if grep -q "\[none\]" "$disk"; then
            echo "✓ 磁盘已使用none调度器（最佳）"
        elif grep -q "none" "$disk"; then
            echo none > "$disk" 2>/dev/null && echo "✓ 已设置磁盘为none调度器"
        elif grep -q "noop" "$disk"; then
            echo noop > "$disk" 2>/dev/null && echo "✓ 已设置磁盘为noop调度器"
        elif grep -q "deadline" "$disk"; then
            echo deadline > "$disk" 2>/dev/null && echo "✓ 已设置磁盘为deadline调度器"
        fi
    fi
done
echo ""

# 5. 内存优化
echo "[5/6] 内存优化..."

# 清理缓存（提升测试时的一致性）
sync
echo 3 > /proc/sys/vm/drop_caches
echo "✓ 已清理系统缓存"
echo ""

# 6. 网络优化
echo "[6/6] 网络优化..."

# 启用BBR拥塞控制（如果内核支持）
if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    echo "✓ 已启用BBR拥塞控制"
else
    echo "⚠ 内核不支持BBR，跳过"
fi
echo ""

echo "========================================"
echo "  优化完成！"
echo "========================================"
echo ""
echo "建议："
echo "1. 重启系统以确保所有优化生效: reboot"
echo "2. 重启后运行性能测试"
echo "3. 如需恢复原始配置: cp /etc/sysctl.conf.bak /etc/sysctl.conf && sysctl -p"
echo ""
echo "⚠ 注意："
echo "- 某些优化可能不适合生产环境"
echo "- 性能模式会增加功耗"
echo "- 建议在测试环境中先验证效果"
echo ""
