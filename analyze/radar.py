#!/usr/bin/env python3
"""
根据 score.json 生成雷达图，轴为各核心维度。
"""
import argparse
import json
from math import pi, degrees
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib import font_manager

# 尝试显式加载中文字体，优先使用已安装的 Noto CJK
FONT_CANDIDATES = [
    # Debian/Ubuntu fonts-noto-cjk 常见路径
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Bold.ttc",
    # 其他可能路径
    "/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf",
    "/usr/share/fonts/truetype/noto/NotoSansCJKsc-Regular.otf",
    "/usr/share/fonts/truetype/arphic/ukai.ttc",
]

loaded_font = None
for path in FONT_CANDIDATES:
    p = Path(path)
    if p.exists():
        try:
            font_manager.fontManager.addfont(str(p))
            loaded_font = p
            break
        except Exception:
            continue

# 指定中文字体优先级，若未成功加载则回退
font_family = []
if loaded_font:
    # 使用文件名作为 family（matplotlib 会注册）
    font_family.append(loaded_font.stem)
font_family += [
    "Noto Sans CJK SC",
    "Noto Sans CJK JP",
    "Noto Sans CJK TC",
    "Noto Sans",
    "SimHei",
    "DejaVu Sans",
]

# 强制设置 sans-serif 列表，确保中文可用
plt.rcParams["font.family"] = "sans-serif"
plt.rcParams["font.sans-serif"] = font_family
plt.rcParams["axes.unicode_minus"] = False

DIMENSIONS = ["latency", "stability", "bandwidth", "cpu", "memory", "disk", "route"]
LABELS = {
    "latency": "Latency",
    "stability": "Stability",
    "bandwidth": "Bandwidth",
    "cpu": "CPU",
    "memory": "Memory",
    "disk": "Disk",
    "route": "Route",
}


def build_radar(scores: dict, output: Path) -> None:
    dims_raw = [scores.get("dimensions", {}).get(dim, 0) for dim in DIMENSIONS]
    dims = dims_raw + dims_raw[:1]
    angles = [n / float(len(DIMENSIONS)) * 2 * pi for n in range(len(DIMENSIONS))]
    angles += angles[:1]

    plt.figure(figsize=(6, 6))
    ax = plt.subplot(111, polar=True)
    ax.set_theta_offset(pi / 2)
    ax.set_theta_direction(-1)
    ax.set_ylim(0, 100)
    ax.set_xticks(angles[:-1])
    ax.set_xticklabels([LABELS[d] for d in DIMENSIONS])
    ax.plot(angles, dims, linewidth=2, color="#2563eb")
    ax.fill(angles, dims, color="#93c5fd", alpha=0.4)
    ax.set_yticks([20, 40, 60, 80])
    ax.set_yticklabels(["20", "40", "60", "80"])
    ax.grid(True, linestyle="--", alpha=0.3)

    # 标注各维度得分，得分很高时略向内缩，避免与标题重叠
    for angle, score, label in zip(angles[:-1], dims_raw, DIMENSIONS):
        radius = score
        if score >= 95:
            radius = score - 8  # 向内缩一点
        ax.text(
            angle,
            radius,
            f"{score:.0f}",
            ha="center",
            va="center",
            fontsize=9,
            color="#111827",
        )
    
    # 获取详细信息
    meta = scores.get("meta", {})
    cpu_info = meta.get("cpu_info") or {}
    memory_info = meta.get("memory_info") or {}
    disk_info = meta.get("disk_info") or {}
    bandwidth_info = meta.get("bandwidth_info") or {}

    # 为每个维度添加详细信息标注（显示在维度标签旁边）
    # 使用英文和数字避免中文乱码问题
    detail_texts = {
        "latency": None,
        "stability": None,
        "bandwidth": None,
        "cpu": None,
        "memory": None,
        "disk": None,
        "route": None,
    }
    
    # Latency 维度：显示延迟值
    if bandwidth_info:
        latency_ms = bandwidth_info.get("latency_ms", 0)
        if latency_ms > 0:
            detail_texts["latency"] = f"{latency_ms:.2f}ms"
    
    # Stability 维度：显示抖动和丢包
    if bandwidth_info:
        jitter = bandwidth_info.get("jitter_ms", 0)
        loss = bandwidth_info.get("packet_loss_pct", 0)
        detail_texts["stability"] = f"jitter={jitter:.2f}ms, loss={loss:.1f}%"
    
    # Bandwidth 维度：显示带宽
    if bandwidth_info:
        bw = bandwidth_info.get("bandwidth_mbps", 0)
        detail_texts["bandwidth"] = f"{bw:.1f}Mbps"
    
    # CPU 维度：显示核心数和跑分
    if cpu_info:
        cores = cpu_info.get("cores", 0)
        single = cpu_info.get("bench_single", 0)
        multi = cpu_info.get("bench_multi", 0)
        detail_texts["cpu"] = f"{cores}cores, s={single:.0f}, m={multi:.0f}"
    
    # Memory 维度：显示容量和速度（带单位）
    if memory_info:
        total_gb = memory_info.get("total_kb", 0) / 1024 / 1024
        read_speed = memory_info.get("speed_read_MiB_s", 0)
        write_speed = memory_info.get("speed_write_MiB_s", 0)
        if read_speed > 0 or write_speed > 0:
            detail_texts["memory"] = f"{total_gb:.1f}GB, r={read_speed:.0f}MiB/s, w={write_speed:.0f}MiB/s"
        else:
            detail_texts["memory"] = f"{total_gb:.1f}GB"
    
    # Disk 维度：显示读写速度
    if disk_info:
        w = disk_info.get("write_MB_s", 0)
        r = disk_info.get("read_MB_s", 0)
        detail_texts["disk"] = f"w={w:.0f}MB/s, r={r:.0f}MB/s"
    
    # 在维度标签外侧显示详细信息
    for i, (angle, dim) in enumerate(zip(angles[:-1], DIMENSIONS)):
        if detail_texts[dim]:
            # 计算标注位置（在标签外侧稍远处）
            label_radius = 118  # 比标签稍远
            
            # 根据角度调整水平对齐方式，避免重叠
            angle_deg = degrees(angle)
            
            # 调整对齐方式：右侧用左对齐，左侧用右对齐，上下用居中
            if -45 <= angle_deg <= 45:  # 右侧
                ha = "left"
                label_radius = 120
            elif 135 <= angle_deg or angle_deg <= -135:  # 左侧
                ha = "right"
                label_radius = 120
            else:  # 上下
                ha = "center"
            
            # 垂直对齐
            if angle_deg > 80 and angle_deg < 100:  # 顶部
                va = "bottom"
            elif angle_deg > -100 and angle_deg < -80:  # 底部
                va = "top"
            else:
                va = "center"
            
            ax.text(
                angle,
                label_radius,
                detail_texts[dim],
                ha=ha,
                va=va,
                fontsize=7,
                color="#6b7280",
                style="italic",
            )
    
    # 在图底部显示CPU型号（使用纯英文数字，避免中文乱码）
    if cpu_info:
        model = cpu_info.get("model", "CPU")
        plt.gcf().text(
            0.5, 0.02, 
            f"CPU: {model}", 
            ha="center", 
            va="bottom", 
            fontsize=8, 
            color="#374151"
        )

    plt.tight_layout()
    output.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(output, dpi=180, bbox_inches='tight', pad_inches=0.3)
    plt.close()


def main():
    parser = argparse.ArgumentParser(description="生成雷达图")
    parser.add_argument("--input", required=True, help="score.json 路径")
    parser.add_argument("--output", required=True, help="输出图片路径 (png)")
    args = parser.parse_args()

    scores = json.loads(Path(args.input).read_text(encoding="utf-8"))
    build_radar(scores, Path(args.output))


if __name__ == "__main__":
    main()

