
# VPS Benchmark 项目说明文档

## 项目目标

VPS Benchmark 是一套 **自动化、可复现、可对比** 的 VPS 测评框架，用于：
- 技术评测（网络 / 性能 / 路由 / 稳定性）
- 博客文章输出
- 视频内容展示
- 长期 VPS 排行榜维护

特点：
- 一键运行（curl | bash）
- 统一评分体系
- 多 VPS 横向对比
- HTML 报告 + 雷达图可视化
- 适合开源与长期运营
- 模块化采集 & 分析，可扩展更多维度

---

## 项目结构

```text
vps-benchmark/
├── install.sh              # 一键安装脚本
├── run.sh                  # 一键执行完整测评
├── collect/
│   ├── system.sh           # CPU / 内存 / 磁盘测试
│   ├── network.sh          # ping / 带宽测试
│   ├── route.sh            # traceroute 路由采集
├── analyze/
│   ├── score.py            # 评分引擎
│   ├── radar.py            # 雷达图生成
│   ├── compare.py          # 多 VPS 对比
│   └── rank.py             # 排行榜生成
├── templates/
│   ├── single.html         # 单 VPS HTML 报告
│   ├── compare.html        # 多 VPS 对比页面
│   └── ranking.html        # VPS 排行榜页面
├── output/
│   ├── vps-001/
│   │   ├── raw.json
│   │   ├── score.json
│   │   ├── radar.png
│   │   └── report.html
│   └── index.html
└── README.md
```

---

## 一键使用方式（对外传播）

```bash
curl -fsSL https://yourdomain.com/install.sh | bash
cd vps-benchmark
./run.sh
```

适合：
- 博客读者
- 视频观众
- VPS 用户复现测试

---

## 测评维度设计

### 核心维度
- 网络延迟（Latency）
- 稳定性 & 丢包（Stability）
- 带宽吞吐（Bandwidth）
- CPU 性能
- 磁盘 IO
- 路由质量（Route）
- 可选扩展：内存延迟、文件系统随机 IO、TCP 连接建立时延、区域带宽（多端点）

---

## 结果归一化规则

### 越小越好
```
score = max(0, min(100, best / value * 100))
```

### 越大越好
```
score = min(100, value / best * 100)
```

统一输出 0–100 分，便于横向对比。

---

## 用途差异化评分模型

### 建站型 VPS
- 网络延迟：25%
- 稳定性：25%
- 磁盘 IO：20%
- CPU：15%
- 带宽：15%

### 中转 / 代理型 VPS
- 网络质量：35%
- 带宽：30%
- 稳定性：20%
- CPU：10%
- 磁盘 IO：5%

### 计算型 VPS
- CPU：40%
- 内存 / 磁盘：35%
- 稳定性：15%
- 网络：10%

---

## 路由质量评分模型

基础分：100 分

惩罚项：
- 跳数 > 15：-10
- RTT > 200ms：-15
- 明显绕路：-15
- 跨洲路由：-20

```
route_score = max(0, 100 - total_penalty)
```

---

## 输出内容

### 单 VPS
- 原始数据（raw.json）
- 评分结果（score.json）
- 雷达图（radar.png）
- HTML 测评报告（report.html）

### 多 VPS
- 横向对比 HTML 页面
- 分类用途评分表

### 排行榜
- 总榜
- 建站榜
- 中转榜
- 计算榜

---

## HTML 报告内容结构

1. VPS 基本信息
2. 三用途评分
3. 雷达图
4. 各维度详细得分
5. 路由分析结论
6. 对比与总结
7. 带宽/稳定性可选分布图（如 ping 抖动箱线图、带宽时间序列）

---

## 可视化与评分改进计划

- 雷达图展示：确保六轴齐全（延迟、稳定性、带宽、CPU、磁盘、路由），已为中文字体设置 Noto CJK；后续可增加刻度标签（20/40/60/80）与边框注释。
- 带宽展示：在报告中追加带宽条形图或时间序列（若使用 speedtest/speedtest-cli/raw log），模板文件 `templates/single.html` 可挂载动态数据。
- 稳定性展示：基于 ping 抖动/丢包生成箱线图或误差棒，突出 jitter 分布，而不仅是均值。
- 数据来源扩展：
  - 网络：增加多端点 ping（国内三网 / 国际多个 CDN），输出 per-target 统计。
  - 带宽：使用 speedtest-cli 的 json 结果；如有 iperf3，可追加上/下行独立指标。
  - 稳定性：统计 ping 标准差、90/95 分位。
- 评分细化：带宽、稳定性由单值改为聚合（均值/分位/抖动），避免被极端值影响。
- 模板渲染：后续用 Jinja2 或前端框架，把 `raw.json`/`score.json` 数据注入 `templates/single.html`，生成 HTML 报告。

---

## 内容创作建议

### 博客
- 强调“统一脚本 + 可复现”
- 雷达图作为核心视觉
- 对比分析优缺点

### 视频
- 演示一键脚本
- 展示跑分 ≠ 体验
- 对比不同 VPS 雷达图

---

## 项目演进方向

- 多地区 Ping（国内三网 / 国际）
- 分时段测试（高峰 / 低谷）
- 数据长期积累
- GitHub 开源 + 社区提交数据
- VPS 排行榜月度更新

---

## 项目定位总结

> VPS Benchmark 不是“跑分脚本”，  
> 而是一套 **公开、统一、可持续的 VPS 测评标准体系**。
