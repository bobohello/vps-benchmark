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
    "jitter_ms": 2,
    "packet_loss_pct": 0.5,
    "bandwidth_mbps": 1000,
    # CPU 参考值：基于 sysbench cpu prime=80000 的真实测试结果
    # 高端服务器CPU（如 AMD EPYC 9654/Intel Xeon Platinum）单核约 150-200 events/s
    "cpu_single": 200,
    "cpu_multi_total": 3200,  # 32核高性能CPU的多核总吞吐（约100 events/s per core）
    "cpu_multi_per_core": 150,  # 每核的优秀性能
    "disk_write_MB_s": 800,
    "disk_read_MB_s": 600,
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


def normalize(value: float, best: float, higher_is_better: bool, headroom: float = 1.5) -> float:
    """
    0~100 归一化，增加 headroom 防止高分一律顶格。
    - higher_is_better: 越大越好（带宽、CPU、IO）
    - headroom: 超出 best 的缓冲倍数，在 best~best*headroom 之间平滑到 100
    """
    if value is None or value <= 0 or best <= 0:
        return 0.0

    if higher_is_better:
        if value <= best:
            return min(90.0, value / best * 90.0)
        ceiling = best * headroom
        extra = (value - best) / max(1e-9, ceiling - best)
        return min(100.0, 90.0 + extra * 10.0)
    # 越小越好
    if value >= best:
        # 若表现不如 best，用 0~90 线性
        factor = max(0.0, min(1.0, best / value))
        return factor * 90.0
    # 优于 best，平滑到 100
    floor = max(1e-9, best / headroom)
    extra = (best - value) / max(1e-9, best - floor)
    return min(100.0, 90.0 + extra * 10.0)


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
    cores = cpu.get("cores") or 0
    cpu_source = cpu.get("bench_source") or "unknown"

    jitter_score = normalize(net.get("jitter_ms"), BEST["jitter_ms"], False)
    loss_score = normalize(net.get("packet_loss_pct"), BEST["packet_loss_pct"], False)
    stability = 0.6 * jitter_score + 0.4 * loss_score

    # 带宽缺失时给轻度兜底，避免 0 分
    bandwidth_val = net.get("bandwidth_mbps")
    if not bandwidth_val or bandwidth_val <= 0:
        bandwidth_val = 10.0

    bench_single = cpu.get("bench_single") or 0
    bench_multi = cpu.get("bench_multi") or 0
    
    # 只在真正使用估算值时才做兜底处理，保留sysbench的真实结果
    if cpu_source != "sysbench":
        # 仅当使用估算值（非sysbench）时，才给一个合理的兜底值
        if not bench_single or bench_single <= 0:
            bench_single = cores * 2000 if cores else 2000
        if not bench_multi or bench_multi <= 0:
            bench_multi = cores * 4000 if cores else 4000
    
    per_core = bench_multi / cores if cores else bench_multi

    cpu_single_score = normalize(bench_single, BEST["cpu_single"], True)
    cpu_multi_total_score = normalize(bench_multi, BEST["cpu_multi_total"], True)
    cpu_multi_per_core_score = normalize(per_core, BEST["cpu_multi_per_core"], True)
    # 综合：更强调单线程与每核表现，兼顾总吞吐
    cpu_score = (
        0.5 * cpu_single_score
        + 0.3 * cpu_multi_per_core_score
        + 0.2 * cpu_multi_total_score
    )

    disk_write_score = normalize(disk.get("write_MB_s"), BEST["disk_write_MB_s"], True)
    disk_read_score = normalize(disk.get("read_MB_s"), BEST["disk_read_MB_s"], True)
    disk_score = 0.8 * disk_write_score + 0.2 * disk_read_score

    dimensions = {
        "latency": normalize(net.get("latency_ms"), BEST["latency_ms"], False),
        "stability": stability,
        "bandwidth": normalize(bandwidth_val, BEST["bandwidth_mbps"], True),
        "cpu": cpu_score,
        "disk": disk_score,
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
            "model": "v0.3",
            "cpu_info": {
                "model": cpu.get("model"),
                "cores": cores,
                "bench_single": bench_single,
                "bench_multi": bench_multi,
                "source": cpu_source,
            },
            "disk_info": {
                "write_MB_s": disk.get("write_MB_s"),
                "read_MB_s": disk.get("read_MB_s"),
            },
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

