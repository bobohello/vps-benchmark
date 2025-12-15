#!/usr/bin/env python3
"""
根据 score.json 生成雷达图，轴为各核心维度。
"""
import argparse
import json
from math import pi
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

DIMENSIONS = ["latency", "stability", "bandwidth", "cpu", "disk", "route"]
LABELS = {
    "latency": "延迟",
    "stability": "稳定性",
    "bandwidth": "带宽",
    "cpu": "CPU",
    "disk": "磁盘",
    "route": "路由",
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

    # 标注各维度得分
    for angle, score, label in zip(angles[:-1], dims_raw, DIMENSIONS):
        ax.text(angle, score + 5, f"{score:.0f}", ha="center", va="center", fontsize=9, color="#111827")

    plt.tight_layout()
    output.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(output, dpi=180)
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

