# VPS Benchmark

一键可复现的 VPS 测评框架，支持采集、评分、可视化与对比。

## 快速开始

```bash
curl -fsSL https://yourdomain.com/install.sh | bash
cd vps-benchmark
./run.sh
```

或在本地仓库内：

```bash
bash install.sh
bash run.sh
```

## 目录说明

- `install.sh`：安装依赖
- `run.sh`：一键采集 + 评分 + 雷达图
- `collect/`：数据采集脚本（系统、网络、路由）
- `analyze/`：评分、雷达图、对比、排行
- `templates/`：HTML 模板占位
- `output/`：结果输出目录

## 后续迭代想法

- 丰富采集项（带宽、IO 更精细）
- 完善 HTML 渲染与静态报告
- 增加多地区、多时段测试与持续数据累积

