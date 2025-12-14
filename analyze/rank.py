#!/usr/bin/env python3
"""
排行榜生成：扫描 output/*/score.json，生成各用途榜单。
"""
import argparse
import json
from pathlib import Path

PROFILE_KEYS = ["web_hosting", "proxy", "compute"]


def collect_scores(root: Path) -> list:
    items = []
    for score_path in root.glob("*/score.json"):
        data = json.loads(score_path.read_text(encoding="utf-8"))
        items.append(
            {
                "id": score_path.parent.name,
                "profiles": data.get("profiles", {}),
            }
        )
    return items


def build_rankings(items: list) -> dict:
    rankings = {}
    for key in PROFILE_KEYS:
        rankings[key] = sorted(
            (
                {
                    "id": item["id"],
                    "score": item["profiles"].get(key, {}).get("score", 0),
                }
                for item in items
            ),
            key=lambda x: x["score"],
            reverse=True,
        )
    return rankings


def main():
    parser = argparse.ArgumentParser(description="生成排行榜")
    parser.add_argument(
        "--input-dir", default="output", help="包含各 VPS 结果的目录 (默认: output)"
    )
    parser.add_argument("--output", required=True, help="输出 ranking.json 路径")
    args = parser.parse_args()

    items = collect_scores(Path(args.input_dir))
    rankings = build_rankings(items)
    Path(args.output).write_text(json.dumps(rankings, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()

