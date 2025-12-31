
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
- HTML 报告 + 雷达图可视化（7维度：Latency / Stability / Bandwidth / CPU / Memory / Disk / Route）
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

### 依赖与快速跑通（在新 VPS 上）
Debian/Ubuntu：
```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip curl git iputils-ping traceroute
# 任选其一安装带宽测速：
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash && sudo apt install -y speedtest
# 或：sudo apt install -y speedtest-cli
git clone https://github.com/bobohello/vps-benchmark.git
cd vps-benchmark
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# 若使用官方 speedtest，首次需接受许可
speedtest --accept-license --accept-gdpr -f json | head
bash run.sh vps-$(hostname)
```
CentOS/RHEL：将 `apt` 换成 `yum/dnf`，并按需安装 speedtest / speedtest-cli。

环境变量（可选）：
- `PING_TARGETS`：多目标 ping，默认 `"1.1.1.1 8.8.8.8"`
- `PING_COUNT`：每目标 ping 次数，默认 6
- `ROUTE_TARGET`：traceroute 目标，默认 1.1.1.1

清理：
```bash
rm -rf ~/vps-benchmark ~/.cache/matplotlib
```
如需卸载 speedtest：`sudo apt remove -y speedtest speedtest-cli`（或对应包管理命令）。

---

## 测评维度设计

### 核心维度（v0.4+ 已实现7维度）
- 网络延迟（Latency）：显示延迟值（ms）
- 稳定性 & 丢包（Stability）：显示抖动（jitter）和丢包率（loss）
- 带宽吞吐（Bandwidth）：显示带宽值（Mbps）
- CPU 性能（CPU）：显示核心数、单核跑分、多核跑分
- 内存性能（Memory）：显示内存容量、读写速度（MiB/s）**[v0.4新增]**
- 磁盘 IO（Disk）：显示读写速度（MB/s）
- 路由质量（Route）：显示跳数和最大RTT **[v0.4新增参数显示]**
- 可选扩展：文件系统随机 IO、TCP 连接建立时延、区域带宽（多端点）

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

CPU / 内存 / 磁盘评分依据（v0.4+ 调整）：
- CPU：单线程与多线程各测一次 `sysbench cpu --cpu-max-prime=80000`；无 sysbench 时回退估算并标注来源。评分 = 50% 单线程 + 30% 多线程人均 + 20% 多线程总吞吐；参考值 single 200、multi_total 3200、multi_per_core 150，带 headroom 平滑，估算时做温和兜底避免极低分。
- 内存（v0.4新增）：使用 `sysbench memory` 测试读写速度（各2GB）；评分 = 60% 读 + 40% 写；参考值读 20000 MiB/s、写 15000 MiB/s；若测试失败则给50分兜底。
- 磁盘：顺序写（dd 32MB fsync）+ 顺序读（同文件，使用缓存读取，样本加大）；评分 = 80% 写 + 20% 读，参考值写 800MB/s、读 600MB/s，带平滑。

网络稳定性：由 jitter（ping mdev）与丢包加权；带宽依赖 speedtest/speedtest-cli，未安装则为 0。

---

## 用途差异化评分模型（v0.4+ 已含内存维度）

### 建站型 VPS (web_hosting)
- 网络延迟：22%
- 稳定性：22%
- 磁盘 IO：18%
- CPU：15%
- 内存：13% **[v0.4新增]**
- 带宽：10%

### 中转 / 代理型 VPS (proxy)
- 网络延迟：33%
- 带宽：28%
- 稳定性：18%
- CPU：10%
- 内存：6% **[v0.4新增]**
- 磁盘 IO：5%

### 计算型 VPS (compute)
- CPU：35%
- 内存：25% **[v0.4新增]**
- 磁盘：25%
- 稳定性：10%
- 网络延迟：5%
- 带宽：0%

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

## 版本更新记录

### v0.4 (2025-12) - 内存维度与雷达图优化
**新增功能：**
- ✅ 内存性能测试：使用 `sysbench memory` 测试读写速度
- ✅ 雷达图升级为7维度：新增 Memory 轴
- ✅ 参数展示优化：所有维度参数分散显示在对应轴旁边
- ✅ 网络参数完善：Latency显示延迟值、Stability显示抖动和丢包
- ✅ 路由参数显示：Route显示跳数和最大RTT
- ✅ CPU信息优化：显示核心数（避免中文乱码）
- ✅ 标签布局优化：智能定位避免文字重叠

**技术改进：**
- 内存速度数据存储在 `system.json` 的 `memory.speed_read_MiB_s` 和 `memory.speed_write_MiB_s`
- 评分模型更新：调整三种用途的权重配置以包含内存维度
- 雷达图标注算法：根据角度和维度智能调整标签位置和对齐方式
- meta信息扩展：添加 `memory_info` 和 `route_info` 字段

**兼容性：**
- 向后兼容：如果内存速度测试失败，会给50分兜底，不影响整体评分
- 依赖 sysbench：内存测试需要 sysbench 工具，建议使用 sysbench 1.0+

---

## 可视化与评分改进计划

- 雷达图展示：✅ 已实现七轴（延迟、稳定性、带宽、CPU、内存、磁盘、路由），已为中文字体设置 Noto CJK；已增加刻度标签（20/40/60/80）与维度参数注释。
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
