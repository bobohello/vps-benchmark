#!/usr/bin/env python3
"""
多 VPS 对比：汇总多个 score.json，输出排序后的对比结果。
"""
import argparse
import json
from pathlib import Path


def load_score(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    return {
        "id": path.parent.name,
        "dimensions": data.get("dimensions", {}),
        "profiles": data.get("profiles", {}),
    }


def main():
    parser = argparse.ArgumentParser(description="对比分数")
    parser.add_argument("--inputs", nargs="+", required=True, help="多个 score.json 路径")
    parser.add_argument("--output", required=True, help="输出 JSON 路径")
    args = parser.parse_args()

    items = [load_score(Path(p)) for p in args.inputs]
    items.sort(key=lambda x: x["profiles"].get("web_hosting", {}).get("score", 0), reverse=True)

    result = {"items": items}
    Path(args.output).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()

