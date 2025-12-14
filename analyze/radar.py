#!/usr/bin/env python3
"""
根据 score.json 生成雷达图，轴为各核心维度。
"""
import argparse
import json
from math import pi
from pathlib import Path

import matplotlib.pyplot as plt

# 指定中文字体优先级，避免缺字警告（需已安装 fonts-noto-cjk 或等价字体）
plt.rcParams["font.family"] = [
    "Noto Sans CJK SC",
    "Noto Sans SC",
    "Noto Sans",
    "SimHei",
    "DejaVu Sans",
]
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
    dims = [scores.get("dimensions", {}).get(dim, 0) for dim in DIMENSIONS]
    angles = [n / float(len(DIMENSIONS)) * 2 * pi for n in range(len(DIMENSIONS))]
    dims += dims[:1]
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
    ax.set_yticklabels([])
    ax.grid(True, linestyle="--", alpha=0.3)
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

