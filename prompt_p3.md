# 新对话提示词：阶段 2 / P3 —— 去 runtime filter（训练计划 + 奖励设计）

> 用法：把本文件**整份**贴进一个新对话的第一条消息。它是一个自包含的任务说明书，
> 假设新 agent 对项目零上下文。
> 写于 2026-09-16，作者 = 上一个对话的 agent（已完成阶段 1a 与验收口径修复）。

---

## 0. 你的角色与边界

你是这个项目的训练侧工程师。你的**唯一**任务是把 **P3（阶段 2 第一轮）**从"计划"
推进到"有数据支撑的结论"。

**范围内**：训练侧代码（`drones/OmniDrones`）、`cfg/profiles/*.yaml`、训练批次、
验收评估、`drones/NAVVEL_VERSION_AND_RETRAIN_PLAN.md` 的更新。

**范围外（用户已明确）**：部署侧一切事情（`navvel_deploy.yaml`、`export_navvel_actor.py`
的部署适配、NUC 上的真机工作、K6 卡点）。真机/部署不由这台服务器负责。**不要去动它们。**

**用户已定的红线**：
- **不能重启服务器**（原因见 §8）。
- **一切 GPU 作业串行**，绝不在训练进行中并发跑 eval（会 OOM 并把训练进程一起杀掉，已发生两次）。
- 单批次训练 `--parallel 2` 上限；`512×1500` 单跑就要 26 GiB，两路必 OOM。

---

## 1. 30 秒背景

Isaac Sim 5.1 + IsaacLab + OmniDrones 的无人机 RL 项目（`/home/lz/lzspace/drones`）。
任务：6×6×3 m 场地里，无人机从一边飞到另一边，躲避方形立柱（球近似 / 球堆）。动作是
速度指令（100 Hz）。有一个 **CBF 安全滤波器**（闭式投影，非 QP 求解）在训练和执行时都
可用。

**项目分两个大阶段**：
- **阶段 1（几何泛化）**：换到柱状世界后仍能安全到达。→ **已完成**（见 §3）。
- **阶段 2（去 runtime filter）**：让**策略自己**内化安全约束，使滤波器退化为恒等映射，
  从而部署时不需要在线滤波器。→ **这就是 P3 要做的，目前差很远**。

---

## 2. 必读（按顺序，不要跳）

1. **`drones/NAVVEL_VERSION_AND_RETRAIN_PLAN.md`** ← **唯一权威执行文档**（2300+ 行）。
   重点：
   - `§3.0` 批次总览（P0–P5 的地图）
   - **`§3.4` P3 的现有计划**（因子 F1/F2/F3、8 配置矩阵、`p_filter` 实现要点、PPO 口径警告）
   - **`§4.3` 阶段 2 的指标与门槛**（P3 的判据）
   - `§4.1` 两阶段验收差异（阶段 1 与阶段 2 用**不同**门槛，同一指标故意不同）
   - `§3.7` 训练侧改动清单（文件级，标注哪些是红线）
   - `§0.5.22`–`§0.5.24` **验收口径修复**（2026-09-16 刚做完，含三个我自己的错误记录）
   - `§0.5.19` **五个"仪器说谎"类 bug**（读它会省你几个小时）
   - `§0.5.7` 卡点 1–14（环境坑与判据教训）
   - `§1.3` 现状与 `NAVVEL_RETRAIN_GUIDE.md` 假设的差异（那份 guide 有多处过时，**plan 优先**）
2. **`drones/MinerU_markdown_Yang_等_-_2026_-_CBF-RL_..._2054593947461390336.md`**
   ← CBF-RL 论文（Yang et al. 2026，Caltech）。**这是本项目的理论依据**，见 §5。
3. **`/memories/repo/navvel.md`**（仓库记忆，含大量已核实事实与踩坑）与
   `/memories/session/` 下的会话笔记。
4. `drones/NAVVEL_RETRAIN_GUIDE.md`（**注意**：多处与现状不符，plan §1.3 已逐条列出差异；
   它的"真机指标表"不要套到 sim 上）。

---

## 3. 当前状态（确凿事实，每条都有证据）

### 3.1 阶段 1a 已收口
阶梯 `A1a → A1b → A2 → A2L3 → A3 → A4` 全部训完并验收（每档两个协议 × ON/OFF）。
**`A4` 是交付冻结档**：5 seed、在收口协议 `384×1500` 下**阶段 1 门槛 6/6 PASS**。

| profile | M | obs | `arrival@0.2` ON | speed cost | 干预步 ON |
|---|---|---|---|---|---|
| A3 | 48 | 逐柱 | 0.9957 | 1.0751 | 245.7 |
| **A4** | 48 | 逐柱 | **0.9974** | **1.0711** | **238.1** |

- ⚠️ **"A3/A4 优于 A2L3"在统计上不成立**（Welch `p=0.17`，分布重叠）。只能说均值排序，
  不能说优劣。**任何"某档更好"的断言必须配显著性检验**（这是硬纪律）。
- 累计 **4 次 bit-exact 复现**（同机训练确定性 ✓）。
- `A4` 的 ckpt（P3 的 warm-start 候选）：
  `scripts/wandb/run-20260916_081114-vthuxlqw/files/checkpoint_final.pt`（seed 11）
  `…-20260916_081114-guojqlwq/files/checkpoint_final.pt`（seed 12）
  `…-20260916_082206-g85jdjx1/files/checkpoint_final.pt`（seed 13）
  `…-20260916_082211-g3ghp2qr/files/checkpoint_final.pt`（seed 14）
  `…-20260916_083255-s2v4ofox/files/checkpoint_final.pt`（seed 15）
  （seed 11/12/13 与 A3 的 ckpt 逐位相同，所以实际只有 3 个独立权重）

### 3.2 阶段 2 的真实差距（P3 要闭合的东西）
`A4` 在收口协议下的阶段 2 判定是 **6/8 PASS**：

| 门槛 | 结果 |
|---|---|
| 0 碰（ON 与 OFF）、0 OOB | ✅ |
| `arrival@0.2`(OFF) ≥ 0.85 | ✅ 0.9974 |
| filter 依赖度 ≥ 0.95 | ✅ |
| `h_min^train ≥ 0` | ✅ |
| stall ≤ 10% | ✅ |
| **零介入率 ≥ 0.95** | ❌ **0.8412** |
| **等价绝对预算（≤ 75 步）** | ❌ **238.1 步 ⇒ 差 3.2 倍** |

⇒ **唯一实质障碍是"零介入"**：滤波器在约 16% 的步里仍在动手。
`intervened` 的绝对步数与地平线基本无关（~245 步），所以它量的是"近障穿行要多久"。
**注意**：`A4` 的 `min_clearance` 在 ON 与 OFF 下**都** ≈ 0.05（= `collision_margin`）
⇒ 策略自己就是在碰撞边界上飞的，这就是零介入率高的直接原因。详见 `§0.5.24` 与 G22。

### 3.3 已存在的相关代码（**先读再改，绝大部分已经写好了**）
`drones/OmniDrones/omni_drones/utils/cbf.py`：
- `filter_velocity(pos, v_nom, p_obs, r_safe, active, alpha, iterations)` —— 闭式迭代投影
  （对应论文 Eq. 18–20）。**数学已冻结，红线保护，不要改**（改了必须重导 TorchScript + 重对拍）。
- `cbf_violation(...)` —— 滤波前 CBF 违例量 `Σ min(0, n^T v_nom + α h) + Σ min(0, h) ≤ 0`
  （对应论文 Eq. 22 第一项，**外加**一个"已侵入球内"的项）。
- `h_boundary_penalty(dmin, extra, buffer, weight)` = `w·relu(buffer − h)` —— 软墙/裕度势能。
- `CBFVelocityFilter`（torchrl Transform）、`safety_radius_extra`、`cbf_safety_radius`。

`drones/OmniDrones/omni_drones/envs/single/nav_vel.py` 的奖励核心（约 980–1070 行）已实现
四种 `penalty_src`：`nominal | correction | gaussian | dual`，以及独立的 `h_penalty` 项。
**它把 `v_nom` 当作"策略自己的输出"来罚** —— 这正是论文的 soft-CBF/CBF-RL 思路。

### 3.4 环境与工具（不要重新发明）
- Python：`/home/hybrid/miniconda3/envs/lz_env/bin/python`（torch 2.7.0+cu128）
- Hydra：`train.py` / `eval_ckpt.py` **必须从 `drones/OmniDrones/scripts/` 下运行**
  （`hydra.searchpath` 是相对 cwd 的）
- 训练：`scripts/train.py`；批量：`scripts/train_batch.py`（含 `clear_gpu()`，硬限并发 2）
- 验收评估：`scripts/acceptance_eval.py`（批量 runner）+ `scripts/eval_ckpt.py`（单体）
- 汇总与门槛判定：`scripts/aggregate_acceptance_eval.py`
  （**已有 `--baseline <A0 agg.json>` 可判"不劣于 A0"**；阶段 1/阶段 2 门槛**已分表**）
- 相对门槛比较：`scripts/compare_to_baseline.py`（含方向声明 + seed 离散度守卫 + 协议守卫）
- 口径断言测试：`scripts/test_clearance_conventions.py`（**8/8**；改验收口径时先跑它）
- 布局 CPU 门禁：`scripts/pillar_layout_check.py`
- GPU：RTX 5090D 32 GB（31.36 GiB 可用）；训练实测 **≈15 min / 20M frames / run**；
  验收单次 `384×1500` ≈ 40 s、`512×600` ≈ 30 s

### 3.5 验收协议（**已冻结，不许改**）
- **对齐列 `512×600`**（与历史数字同口径，仅用于阶梯对齐）
- **收口列 `384×1500`**（= 1 个完整 episode，**判过/不过**）
  - ⚠️ 收口列是 **384 不是 512**：`512×1500` 在 M=48 下 3 次里 OOM 2 次。
    坑 9d 已证明 `num_envs` 不改变布局（前 384 个 env 与 512 是同一个流），所以 384 是子集。
- **两列的数字永远不许混进同一张对照表**，报告必须标注 `rollout_steps`。
- `set_seed = 1000 + train_seed`，ON/OFF 共用布局，用 `layout_fp` 验证。
- 判定"跑成功"的**唯一**判据是日志里有 `[eval_metrics]` 行，**不是 `exit code == 0`**
  （本机 Isaac 退出时经常 segfault，但产物是好的）。

---

## 4. 你的任务

**先出计划、拿批准、再花 GPU。** 具体分四步：

### 第 1 步：三项前置验证（**纯 CPU / 只读日志，不花 GPU**）
在写方案之前，先把这三件事查清并给出证据。它们决定 P3 该怎么做（见 §6、§7）：
1. `零介入率` 到底是**策略属性**还是**配置属性**？
2. 现有 CBF 奖励项的**实际每步量级**是多少（相对任务奖励）？
3. `p_filter` 的实现落点是否真的只有 §3.4 点的两处文件？

### 第 2 步：给出 P3 方案（写成 plan 的新 §3.4 修订稿，贴给用户看）
必须包含：因子与取值、有效矩阵、每格 seed 数、判据与门槛、显式写出的**失败判据**
（什么结果会让你推翻当前假设）、GPU 时间估算、以及**单变量归因纪律**
（批次内只动一个变量维度；几何 ≠ 口径 ≠ 奖励 ≠ DR ≠ obs 维度）。

### 第 3 步：实现 + smoke test
先实现 `p_filter`（唯一的缺失代码，见 §7.3），跑 **M=48 的 smoke test**（`exit=0`、
0 个 PhysX 错误、正常推进、无 NaN），再跑 **1 个配置 × 1 seed × 少量帧**验证梯度/统计正常。

### 第 4 步：全批次 + 验收 + 结论
`8 配置 × 3 seed = 24 runs ≈ 2 h`（预算充裕：建议 `p0` 组补到 5 seed，因为 `p0` 是
"裸策略"形态的直接来源，最需要统计置信）。然后跑双协议验收，用现成工具出表与门槛判定，
并把结论写回 plan（新开 `§0.5.25`），**包括失败与"无法区分"的结论**。

---

## 5. 论文方法 ↔ 本项目已有实现的映射（**最重要的一节：不要重复发明**）

论文（CBF-RL, Yang et al. 2026）的核心是"**dual**"：训练时**同时**做
(a) CBF 安全滤波 + (b) barrier 启发的奖励整形，从而让策略**内化**约束，部署时**不需要**在线滤波器。

论文的奖励（Eq. 22+23，Table II）：

```
r_cbf = w · [ min(a_k^T v_policy − b_k, 0)  +  ( exp(−||v_policy − v_safe||²/σ²) − 1 ) ]
r     = r_nominal + r_cbf
```

- 第一项 = CBF **条件**残差（`a=∇h`, `b=−α h`）⇒ 罚"这个动作会破坏 barrier"
- 第二项 = 罚"策略与安全动作的距离"，`∈[−1,0)` 有界 ⇒ 论文强调"不会因相对主任务奖励
  无界而失稳"
- 论文 Table II 用的权重：**`w = 100`**，`σ = 0.5`；同表 `r_progress = 20`、`r_alive = 0.01`、
  `r_goal = 1.0`。

**本项目已有的对应物**（`nav_vel.py` 的 reward core）：

| 论文 | 本项目 | 状态 |
|---|---|---|
| `min(a^T v_policy − b, 0)` | `cbf_violation(...)`（+ 额外的 `min(0,h)` 侵入项） | ✅ 已实现 |
| `exp(−‖Δv‖²/σ²) − 1` | `−w2·(1 − exp(−corr²/σ²))`（**只差符号，数学等价**） | ✅ 已实现 |
| `r_nominal + r_cbf` | `penalty_src: dual` = `w1·viol + w2·(1−exp(...))` | ✅ 已实现 |
| 训练时滤波 | `cbf.mode: hybrid`（filter + reward core） | ✅ 已实现 |
| barrier 启发的边界项 | `h_penalty_weight` + `h_penalty_buffer`（`h_boundary_penalty`） | ✅ 已实现，但**默认 0（关）** |
| 训练期 filter **执行**概率 / 退火 | `p_filter` | ❌ **不存在（G2）** |

⇒ **结论：论文的奖励设计不需要"新实现"，A4 里就已经开着**（`penalty_src: dual`、
`w1 = reward_weight = 0.1`、`w2 = correction_weight = 0.1`、`σ = correction_sigma = 0.5`、
`mode = hybrid`、`h_penalty_weight = 0`）。
**P3 要做的是"标定与选择"，不是"发明"。** 任何"新增一个 CBF 奖励项"的提议都要先证明
现有项做不到。

论文的实测结果（Table I，1000 个随机测试环境，含 DR 版本）——**用它来设定你的预期**：

| 方法 | 无 DR | 有 DR |
|---|---|---|
| Dual（带 runtime filter） | 99.0% | 99.0% |
| **Dual（部署时去掉 runtime filter）** | **92.7%** | **91.7%** |
| Reward Only | 91.9% | 87.6% |
| Filter Only（带 filter） | 98.8% | 96.7% |
| **Filter Only（去掉 runtime filter）** | **38.7%** | 36.8% |
| Nominal | 51.4% | 55.0% |

**两个必须记住的读数**：
1. **仅奖励整形（Reward Only）就拿到了 91.9%** ⇒ 论文的内化主要来自奖励项，不是滤波器；
2. 去掉 runtime filter 后 Dual = **92.7%，不是 99%** ⇒ 论文的"内化"也不是完美的。
   而本项目的门槛是 `零介入率 ≥ 0.95`（**逐步**判"滤波器是否出手"），这是一个**比论文的
   成功率严格得多的判据** —— 这一点必须在计划里明说，并核实它是否可达（见 §7.1）。

---

## 6. 核心设计问题：奖励函数要动吗？

**短答：要动，但动的不是"加项"，而是"标定 + 开关 + 一个缺失机制"。** 三个具体问题：

### 6.1 权重是否小了两个数量级？（**待验证的假设，别当成结论**）
从 `A4` 的训练日志可以读到（`scripts/wandb/run-20260916_081114-vthuxlqw/files/wandb-summary.json`）：

- `train/stats.cbf_violation = 0.8173`（这是 `−viol` 的 EMA，量纲 = 速度 m/s）
- `train/stats.return = 2434.46`，`train/stats.episode_len = 1156.77` ⇒ 每步奖励 ≈ **2.1**
- 权重：`reward_fly_weight = 1.5`、`reward_zone_weight = 1.5`、`arrive_bonus = 40`、
  `reward_crash_penalty = 15`、`reward_timeout_penalty = 60`

⇒ 估算：CBF 罚项每步 ≈ `w1 × 0.8173 = 0.082`（+ correction 项 ≤ `w2 = 0.1`）
⇒ **CBF 奖励约是任务奖励的 4–8%**。
而论文里（Table II）：`r_cbf = 100 × [...]`，滤波器出手时括号内约 `−0.5 ~ −2`
（`min(...)` 项是单位外法向上的速度残差，`exp(...)−1 ∈ [−1,0)`）
⇒ **出手时 `r_cbf` 约 `−50 ~ −200`**，而同表任务项 `r_progress` 上限只有 `+20`、
`r_alive = 0.01`、`r_goal = 1.0`。

⇒ **论文的 CBF 项在出手时于任务奖励的 3–10 倍；本项目的 CBF 项约为任务奖励的 1/20。**
两者相对量级差约 2 个数量级。这是一个可直接检验的假设（用 `wandb` 的 history 逐项核对，
逐项核对，并把两边的量纲对齐后再比较 —— 不要只比裸数字，论文用的是一套不同的
nominal 奖励）。

**但必须同时读这段历史（plan `§0.5.9`）**：`A0` 时代用更大的 CBF 余量（`r_cbf = r_o+0.30`）
时，出现了"**保守策略学会远离被罚区而不是安全穿过**"，长训后期 `arrival` 停滞；
P0.2 把余量收窄到 `r_o+0.17` 后到达率 +13.2 pt。
⇒ **这个设计空间是"太弱 → 不内化 / 太强 → 过度保守"的双边**，不能单向加权重。
P3 的矩阵必须能**同时**看见两侧（这也是为什么 `p1/pann/p0` × 四种臂是必要的，而不是只扫权重）。

### 6.2 `h_penalty`（F3）要不要开？
plan `§3.4` 已经把 F3 写成"**本轮能否达标的关键开关**"，理由是：论文的
`min(a^T v − b, 0)` 项**只在策略提出的动作会破坏 barrier 时才给梯度**，而 A4 的实测
`corr_p50 = 0`、`zero_intervention_rate = 0.8412`（即 84.12% 的步滤波器根本没动，
`corr_p50 = 0` 只是它的下界）、`h_min^train = 0.0003 ≈ 0`（全程最小值贴过边界）
⇒ 单靠该项的梯度很稀。
`h_boundary_penalty` 的 `buffer > 0` 版本正是为了"在接近边界**之前**就开始罚"而写的
（`E1-v2`），且 A4 里它是**关的**。
⇒ 请**先量化** `h_penalty` 这一项在离线日志里能提供多少有效梯度（例如：
在 A4 的 eval 轨迹上离线复算 `relu(buffer − h)` 的非零步占比与量级），再决定是否把它
当成 P3 的一个因子（不要凭直觉开）。

### 6.3 `p_filter` 是论文机制的**核心**，而它恰好缺失
`a_exec = a_cbf(a)` if `rand < p` else `a`；
但只要该臂的奖励含 correction 项，就**始终**计算 `a_cbf` 与 `‖Δa‖`（否则 `p=0` 时没有梯度）。
⇒ `p = 0` 有明确意义：**策略裸奔执行，却被罚"偏离 CBF 的建议"** = **软蒸馏 / 无 filter 模仿**。
这正是论文"部署时无滤波器"的训练形态，而本项目目前**完全没有这个机制**（G2）。

---

## 7. 前置验证的细则（第 1 步怎么做）

### 7.1 `零介入率` 是策略属性还是配置属性？（**先做这条**）
这是**第 13 号卡点**的原病：曾经有一道门槛（`min d_min ≥ 0.10`）看起来在判策略，
实测发现它的最小值被一个**配置常量**（`cbf_extra`）钉死 ⇒ 判的是配置。
`零介入率` 有同样的嫌疑：`intervened ⟺ h < 0 ⟺ 无人机进入 CBF 决策球`，而决策球半径
`r_cbf = r_o + drone_radius + inflation + r_safety_margin = r_o + 0.17`（口径 A）。
柱半径 0.4243 ⇒ 决策球半径 0.594 m；而 A3/A4 的走廊净宽 1.34 m（柱心距 2.19 m）。

**要做的事**：
1. 用 A4 的验收日志/轨迹（或离线复算）算出：策略在近障穿行时的**实际轨迹**
   与决策球的关系 —— 是"策略主动贴着球边界飞"（⇒ 策略属性，可以通过奖励改变），
   还是"几何上无论怎么飞都必须穿过某个球"（⇒ 配置属性，改奖励没用）？
2. 明确给出验算过程与数字，不要给结论式断言。
3. 如果结论是"部分属于配置"，**把它写进计划并提出替代判据**（例如把门槛改成
   "`h < 0` 的步占比"以外的量，或把 `r_safety_margin` 纳入讨论），但**不要擅自改门槛**
   —— 门槛的修改需要用户裁决（见 §9）。

### 7.2 现有 CBF 奖励项的真实每步量级
用 `wandb-summary.json` + `wandb` history 逐项核对 §6.1 的估算，并**把论文的量纲对齐后**
再比较。输出一张表：`任务项 / CBF viol 项 / CBF correction 项 / h_penalty 项` 各自的
每步均值与分位数。

### 7.3 `p_filter` 的落点确认
plan `§3.4` 说是两处：`utils/cbf.py::CBFVelocityFilter` 与 `envs/single/nav_vel.py`。
请**先读代码确认**，并特别确认：
- `v_nom` 是通过 `info.policy_action` 传到奖励核心的（现有注释提到），所以 `p` 的实现
  不能破坏这条链路；
- **`filter_velocity` 的数学不许动**（红线：改了要重导 TorchScript + 离线对拍）；
- `p` 的调度要用**同一个** `env.step` 计数，保证执行与奖励看到同一个 `p`；
- ⚠️ **PPO 口径警告**：`p > 0` 时实际执行的不是策略采样的动作，而 PPO 似然仍对 `a` 计算
  ⇒"梯度-结果不一致"。必须监控 `ratio / KL / entropy` 与 `std(a)` 是否塌缩；
  `pann` 需与 `clip_range` 同步放宽；`p1` 与 `p0` 必须**同 seed 同预算**才可比。

---

## 8. 硬约束与纪律（违反会毁掉数据或别人的工作）

1. **一切 GPU 作业串行**。训练批次进行中绝不跑 eval（已两次把训练进程一起 OOM 杀掉）。
   跑 eval 前先 `nvidia-smi` 确认无 compute app。
2. **判"跑成功"的唯一判据是产物/`[eval_metrics]` 行**，不是 `exit code`。
   本机 Isaac 退出时常 segfault；`rc != 0` 不代表失败，`rc == 0` 也不代表成功。
3. **判"训练卡死"要看三件事**：checkpoint 时间戳、日志字节增量、`ps -o stat=,etime=,%cpu=`
   （`Rl` + ~140% CPU = 在算）。**不要凭感觉估时间**（曾误判慢 15×）。
4. **清场按 PID**：`train.py` 调 `setproctitle`，进程名会变成 wandb run 名 ⇒
   `pkill -f train.py` **匹配不到**。用 `nvidia-smi --query-compute-apps=pid` 拿 PID。
5. **`--parallel 2` 是硬上限**；`512×1500` 单跑 26 GiB，两路必 OOM。
6. **不能重启服务器**。GPU 图形引擎有 Xid 31（`ENGINE GRAPHICS MMU Fault`），
   每个 eval 进程报一次，但 **CUDA 计算引擎健康** —— 这就是"训练正常、eval 会挂"的原因。
   已知绕过办法 = **降低 eval 的 `--num-envs`**（128/256/384/448 可行，512 不行）。
   `nvidia-smi --gpu-reset` 被 `nxnode.bin` 挡住且会打断桌面会话，**不要试**。
7. **数字一律从 `agg.json` / 日志读，不许凭记忆或推断**。我犯过一次：凭印象写
   `arrival@0.2 = 0.8194`（真值 `0.7975`），把一个比较结论写反了。
8. **任何"X 比 Y 好"的断言必须配显著性检验**（至少给 seed 极差；跨档比较用 Welch）。
9. **门槛要下在"被考核对象能改变的量"上**（卡点 13）。对着配置常量设阈值，
   只会得到一个与策略无关的 PASS/FAIL。
10. **"指标没出现在表里"与"指标通过了"必须能区分**（卡点 14）。
    `aggregate_acceptance_eval.py` 的 `METRIC_ORDER` 是**手写白名单**，
    新增指标**必须同步加入**，否则静默变 `None`。
11. **测试要钉住结论，不要钉住实现**。反例：我曾写过一个断言"门槛读的是 `cbf_extra`"
    的测试 —— 它在**错误的修法上也通过**。改成断言结果性质才有意义。
12. **改任何验收口径前先跑 `scripts/test_clearance_conventions.py`**（8/8）。
13. **提交纪律**：两次仓库——外层 `/home/lz/lzspace/drones`（branch `main`）与
    子模块 `drones/OmniDrones`（branch `feat/crazyflie-pidrate`）。**先提交子模块再提外层**。
    用 `git commit -F <file>`，**不要用 `-m` 带反引号**（会打断 shell）。
    每写完一节 plan 就提交一次（旧编辑器缓冲覆盖过 plan 两次）。
14. **安全白名单（训练期间可跑）**：`pillar_layout_check.py`、`py_compile`、
    `aggregate_acceptance_eval.py`（纯 CPU 读日志）。
    **黑名单**：`train.py` / `eval_ckpt.py` / `export_navvel_actor.py` / 任何 `--cfg job`
    （会 import `omni_drones`，与训练争 GPU）。
15. **动手前先问用户**：凡是要改门槛取值、改验收协议、开新批次、或推翻某个已有结论，
    先给证据 + 选项 + 你的建议，等裁决。**不要自己改判据让它通过。**
16. **不要碰部署侧**（`navvel_deploy.yaml` / 导出适配 / K6 / NUC）—— 用户已明确排除。

---

## 9. 期望交付物

1. **`§3.4` 的修订稿**（P3 的最终计划）：因子与取值、有效矩阵、seed 数、判据与门槛、
   失败判据、GPU 估算、单变量归因说明。
2. **§7 三项前置验证的结论**（含验算过程与数字，允许结论是"无法判定，需要 X 实验"）。
3. **代码**：`p_filter`（+ 必要的 cfg 键 + 单元/集成自检），
   `filter_velocity` 数学**不动**。
4. **训练批次的结果**（8 配置 × ≥3 seed）+ **双协议验收**（`512×600` 与 `384×1500`，
   用现成 runner 与聚合器）+ **门槛判定表**（阶段 2 的 8 个门槛）。
5. **plan 新开 `§0.5.25`**：时间点标注、逐项数字来源、结论、**以及未区分/失败的结论**。
6. **简短汇报**：现在能说"阶段 2 达标 / 未达标"吗？差多少？下一步是什么？
7. 两仓提交并推送（先子模块，后外层），说明用文件而非 `-m`。

**必须诚实写进结果的东西**（这些比"通过"更有价值）：
- 任何看起来"过了"但其实是阶段 1 门槛或配置常量的地方；
- 任何跨协议混比的数字；
- 任何"某配置更好"但检验不显著的结论；
- 任何仪表化本身的问题（例如新指标没进 `METRIC_ORDER`）。

---

## 10. 反模式清单（我犯过的，别重复）

| 反模式 | 后果 | 正确做法 |
|---|---|---|
| 把阶段 2 的指标当阶段 1 的门槛看 | 报出"阶段 1 卡在零介入率"这种错话 | 两阶段门槛分表（§4.1 明说故意不同） |
| 自己"拍"一个阈值（`intervened_steps ≤ 300`） | 把阶段 2 门槛**偷偷放宽 4 倍** | 阈值必须能溯源到 plan 或实测；否则标"无依据" |
| 用一个"单位换算"把 FAIL 变成 PASS | 我在口径没定的时候加回 `drone_radius+inflation` 报 PASS | 口径不明时**并列报全部口径 + 显式标 UNRESOLVED**，让人裁决 |
| 凭记忆写数字 | 比较结论写反 | 一律从 `agg.json` / 日志读 |
| 用均值排序当成"更好"的结论 | 3 seed 看起来干净，5 seed 就散了 | 配显著性检验；落在 seed 离散度内就说"未区分" |
| 新增指标但没加进 `METRIC_ORDER` | 指标静默变 `None`，看起来像"没问题" | 加了新指标就跑一次聚合器确认它出现在表里 |
| 测试钉实现而不是钉结论 | 错误的修法也能通过测试 | 断言结果性质（"任何净空门都不许存在"） |
| 估算过于乐观 | 我给过"≈15 min"，实际 29.4 min | 估时用实测点外推，并注明不确定性 |
| 训练进行中并发跑 eval | OOM，把训练 seed 一起杀掉 | 一切 GPU 作业串行 |

---

## 11. 一句话起点

阶段 1a 已经收口在 `A4`（5 seed、阶段 1 门槛 6/6）。**阶段 2 的唯一障碍是"零介入"：
滤波器仍有 ~16% 的步在动手，需要降 3 倍以上。** 论文的 dual 奖励**已经实现并已开启**，
缺的是 (a) `p_filter` 这个"无 filter 但被罚偏离 CBF"的训练机制，和 (b) 对已有 CBF 奖励项
的**标定**（现在它的量级约为任务奖励的 4–8%，而论文里是任务奖励的 5–10 倍）。

**第一步不要写代码**：先做 §7 的三项验证，给出证据与计划，等用户裁决。
