#!/usr/bin/env python3
"""
评分引擎：将 raw.json 归一化到 0-100，并输出不同用途的加权得分。
"""
import argparse
import json
from datetime import datetime
from pathlib import Path

BEST = {
    "latency_ms": 10,
    "packet_loss_pct": 0.5,
    "bandwidth_mbps": 1000,
    "cpu_bench": 20000,
    "disk_write_MB_s": 500,
}

PROFILE_WEIGHTS = {
    "web_hosting": {
        "latency": 0.25,
        "stability": 0.25,
        "disk": 0.20,
        "cpu": 0.15,
        "bandwidth": 0.15,
    },
    "proxy": {
        "latency": 0.35,
        "bandwidth": 0.30,
        "stability": 0.20,
        "cpu": 0.10,
        "disk": 0.05,
    },
    "compute": {
        "cpu": 0.40,
        "disk": 0.35,
        "stability": 0.15,
        "latency": 0.10,
        "bandwidth": 0.00,
    },
}


def normalize(value: float, best: float, higher_is_better: bool) -> float:
    if value is None or value <= 0 or best <= 0:
        return 0.0
    if higher_is_better:
        return min(100.0, value / best * 100.0)
    return max(0.0, min(100.0, best / value * 100.0))


def route_score(route: dict) -> float:
    hops = route.get("hop_count") or 0
    max_rtt = route.get("max_rtt_ms") or 0
    penalty = 0
    if hops > 15:
        penalty += 10
    if max_rtt > 200:
        penalty += 15
    # “明显绕路 / 跨洲”无可靠自动识别，留给后续版本或人工标注
    return max(0.0, 100.0 - penalty)


def calc_scores(raw: dict) -> dict:
    net = raw.get("network", {})
    sysinfo = raw.get("system", {})
    disk = sysinfo.get("disk", {})
    cpu = sysinfo.get("cpu", {})

    dimensions = {
        "latency": normalize(net.get("latency_ms"), BEST["latency_ms"], False),
        "stability": normalize(net.get("packet_loss_pct"), BEST["packet_loss_pct"], False),
        "bandwidth": normalize(net.get("bandwidth_mbps"), BEST["bandwidth_mbps"], True),
        "cpu": normalize(cpu.get("bench_score"), BEST["cpu_bench"], True),
        "disk": normalize(disk.get("write_MB_s"), BEST["disk_write_MB_s"], True),
        "route": route_score(raw.get("route", {})),
    }

    profiles = {}
    for name, weights in PROFILE_WEIGHTS.items():
        total = 0.0
        for dim, w in weights.items():
            total += dimensions.get(dim, 0.0) * w
        profiles[name] = {"score": round(total, 2), "weights": weights}

    return {
        "dimensions": dimensions,
        "profiles": profiles,
        "meta": {
            "generated_at": datetime.utcnow().isoformat() + "Z",
            "model": "v0.1",
        },
    }


def main():
    parser = argparse.ArgumentParser(description="VPS Benchmark scoring")
    parser.add_argument("--input", required=True, help="raw.json 路径")
    parser.add_argument("--output", required=True, help="score.json 输出路径")
    args = parser.parse_args()

    raw = json.loads(Path(args.input).read_text(encoding="utf-8"))
    scores = calc_scores(raw)
    Path(args.output).write_text(json.dumps(scores, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()

