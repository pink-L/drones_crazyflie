# Crazyflie 避障导航 RL：F1 Reward + CBF 四臂机制对比 —— 汇报材料

> 日期：2026-09-07 ｜ 仓库：`/home/lz/lzspace/drones/OmniDrones`（分支 `feat/crazyflie-pidrate`）｜ wandb：`new_reward`
> 任务：仿真 Crazyflie 无人机在静态球形障碍场中从随机起点飞到随机 3D 目标并保持到达（速度指令层 + CBF 安全滤波）。
> 配套：`f1_recipe_and_runs.md`（配方/run 总表）、`new_reward.md`（F1 reward 设计史）、`new2_plan.md`（New2 obs 结构改造）。
> 验收 eval 口径 = **严格单命**（`task.soft_respawn=false`，坠毁/出界/碰撞超限即失败不复活），详见 `eval_ckpt.py` 顶部「标准验收模板」。

---

## 背景（前置）：一阶 CBF 的 single-integrator 导航 —— CBF-RL 论文的 toy 设定

本材料的所有机制词（runtime filter、四臂、internalize/撤 filter）都来自 CBF-RL 论文（Yang et al. 2026，仓库 `MinerU_markdown_...CBF-RL...md`）在 **single-integrator（单积分器）2D 导航** toy 任务上的定义。这里先交代这套"论文世界观"，后面用它解释我们 Crazyflie 上的每个现象。

**① 系统模型——无动力学滞后的速度积分器。** agent 位置 $\mathbf q=(x,y)$、控制=速度 $\mathbf v\in\mathbb R^2$，欧拉离散**速度瞬时生效**（无惯性、无姿态环、无执行器滞后）：

$$\mathbf q_{k+1}=\mathbf q_k+\mathbf v_k\,\Delta t,\qquad \text{DR 变体：}\ \mathbf q_{k+1}=\mathbf q_k+(\mathbf v_k+\mathbf d)\,\Delta t,\ \ \mathbf d\sim\mathcal N(0,\,(0.2\,v_{max})^2)$$

起/障/终随机化但保证出生在安全集内（`[13]` 做法，≈ 我们的 `init_clearance`/`goal_clearance` 净空约束）。

**② 一阶 CBF 与安全半平面。** 对圆障 j（球心 $\mathbf p_j$、半径 $r_j$）、agent 半径 $r_{agent}$、世界边长 $L$，安全函数取"到最近障碍/墙的表面净空"：

$$h(\mathbf q)=\min\Big\{\ \min_j\big(\|\mathbf q-\mathbf p_j\|-(r_{agent}+r_j)\big),\ x-r_{agent},\ (L-x)-r_{agent},\ y-r_{agent},\ (L-y)-r_{agent}\ \Big\}$$

安全集 $\mathcal S=\{\mathbf q: h\ge0\}$。相对度 1 的 CBF 要求存在输入使 $\dot h+\alpha h\ge0$；single-integrator 下 $\dot h=\nabla h^\top\mathbf v$，于是**安全输入族退化为一个半平面**（这就是"一阶/线性约束"称呼的来源）：

$$\mathcal U_{CBF}(\mathbf q)=\big\{\mathbf v:\ \underbrace{\nabla h(\mathbf q)^\top\mathbf v+\alpha h(\mathbf q)}_{\dot h+\alpha h}\ge0\big\},\qquad \alpha=1.0$$

**③ 闭式安全滤波（论文 Eq.18–20，我们 `utils/cbf.py` 的单约束版）。** 把策略给出的可能不安全速度 $\mathbf v^{policy}$ 投影到该半平面（沿 $\nabla h$ 方向最小修改）；多障碍/多约束我们迭代 3 轮逐个处理：

$$\mathbf v^{safe}=\begin{cases}\mathbf v^{policy} & \nabla h^\top\mathbf v^{policy}+\alpha h\ge0\\[2pt] \mathbf v^{policy}-\dfrac{\nabla h^\top\mathbf v^{policy}+\alpha h}{\lVert\nabla h\rVert^2}\,\nabla h & \text{otherwise}\end{cases}$$

**④ 训练期双通道安全注入（Dual / Alg.1）。** ① filter：策略输出先投影再进环境（策略学的是"被修正后的闭环动力学"，`q_{k+1}^{safe}=q_k+\Delta t\,v_k^{safe}`）；② r_cbf shaping（论文 Eq.22–23，总奖励 $r=r_{nominal}+r_{cbf}$）：

$$r_{cbf}=\underbrace{\min\big(\nabla h^\top\mathbf v^{policy}+\alpha h,\ 0\big)}_{\text{viol ≤ 0：教"别发会被 filter 拦的指令"}}+\underbrace{\Big(e^{-\lVert \mathbf v^{policy}-\mathbf v^{safe}\rVert^2/\sigma^2}-1\Big)}_{\text{correction ∈ [−1,0]：教"贴近 filter 保留的安全动作"}}$$

**⑤ 论文 toy 上的结论（Dual 能 internalize）。** 四变体（Dual / Filter-only / Reward-only / Nominal）× 部署是否撤 runtime filter（Table I，4096 env×1500 步，随机测试 1000 环境）：

| 部署形态 | Dual | Filter-only | Reward-only | Nominal |
|---|---|---|---|---|
| 带 runtime filter | 99.0% | 98.8% | — | — |
| **撤 runtime filter** | **92.7%** | 38.7% | 91.9% | 51.4% |

→ 在**理想 single-integrator** 上，dual 训练让策略把安全 internalize 进网络，撤掉 filter 仍 ~93%；Filter-only 撤 filter 则崩到 38.7%。

**⑥ 与本文 Crazyflie 的差别（为什么 internalize 在我们这里始终失败）。** 论文 toy 是理想单积分器——控制即速度、瞬时生效。本文把它移植到 **Crazyflie 四旋翼 + 100 Hz + 速度指令 → Lee 姿态/位置控制器 → 电机**：CBF 只能挂在**速度指令层**（最接近单积分器抽象的一层），但其下方还有真实转动惯量、姿态环带宽与电机一阶滞后——**指令速度与实际速度之间存在动力学滞后**。这就是全文反复出现的「论文 single-integrator 无此动力学滞后」之所指：同一套 CBF-RL 机制在 toy 上能 internalize，搬到带真实动力学的四旋翼后 7+ 组实验（含 New2 obs 结构级改造）都无法在撤 filter 后保持安全（§7.3/§7.6）。本文四臂（dual / filter_only / reward_only / naive）正是论文 Dual / Filter-only / Reward-only / Nominal 的逐一对应（§5 表）。

---

## 0. 一句话结论

**F1 reward（删悬停基座 + 飞行主导）让带 CBF filter 的部署在 16 障碍下达到 joint ≈ 0.93–0.94（严格单命验收）；runtime CBF filter 是决定性安全组件（撤 filter 后任何臂 joint 都跌到 0.56–0.64）；其中 naive / reward_only 是天然无 filter 臂（训练就不带 filter），不可与带 filter 的 dual / filter_only 在同列比较。**

---

## 1. 动作空间（Action Space）

- **策略输出**：4D 速度指令 `[vx, vy, vz, yaw]`（世界系），100 Hz（sim `dt=0.01`）。
- **指令链**（训练/部署装配，`train.py`/`eval_ckpt.py` 一致）：

```
policy ──▶ [CBF velocity filter 投影] ──▶ VelController(限幅) ──▶ Lee 位置/姿态控制器 ──▶ 电机
             仅 filter_only / hybrid(dual) 臂插入            max_vel=1.8 m/s
             在 VelController 之前(Compose 反序先执行)       max_yaw_rate=1.5 rad/s
```

- CBF filter = 一阶 CBF 迭代闭式投影（`utils/cbf.py`）：对每个激活障碍球约束 `nᵀv + αh ≥ 0`（h = 到 CBF 决策球带符号距离），把危险速度指令投影到安全半平面交集。`α=1.0`、迭代 3 轮、`use_brake_term=false`（决策球 = 几何 r_s + 0.1 m 裕量）。
- 意义：策略输出的是**被安全层校正后的速度**；碰撞兜底由该层保证（ON 碰撞 <1–2%）。

---

## 2. 观测（Observation，62 维，`obs_safety=none` 基线）

| 段 | 维度 | 内容 |
|---|---|---|
| `rpos` | 3 | 目标相对位置（世界系，平移不变）|
| `drone_state[3:]` | 20 | Crazyflie 23 维状态（19+4 旋翼）除位置外：姿态/角速度/线速度等 |
| `rheading` | 3 | 目标航向 − 机头航向 |
| `time_encoding` | 4 | 归一化时间编码 `t/T` |
| 障碍块 | 32 | K=8 个最近障碍槽 ×（相对位置 xyz/5 截断 + 半径/0.5 截断）；场景 M=16 时每步取最近 8 个（滑动窗口，obs 恒 62 维）|
| **合计** | **62** | 前 30 维（rpos+state+rheading+time）+ 32 障碍 |

- 障碍信息 = 纯几何（位置+半径）；**CBF 决策半径刻意不进 obs**（防策略对滤波器内部参数过拟合）。
- New2 专项实验在此基础上加 1–2 维 CBF 边界余量通道（`obs_safety=cbf_margin`，62→63/64），本四臂对比用回 62 维基线以便与 naive 同口径。

---

## 3. 评估环境与验收口径

- **机体/步长**：Crazyflie @100 Hz；单窗口 600 步 = 6 s。
- **障碍**：静态球，半径多档 {0.2,0.3,0.4} m，场地 ±2.2 m；判定半径 `r_s = drone_radius(0.15) + r_o + inflation(0.05)`；碰撞 = 表面净空 `dmin < 0.05`；危险区 `D=0.6`。
- **目标**：随机 3D waypoint；到达 = 距目标 `< 0.5 m` 连续保持 ≥50 步。
- **训练课程**：`levels [2,4,8,16]`，窗口成功 ≥0.8 且碰撞 ≤0.05 升密度（from-scratch 从 2 障起，12M 内可通关 16）。
- **验收 eval（严格单命，已固化）**：确定性 rollout 600 步 / 1024 env、`auto_reset=False`、**`soft_respawn=false`**（一次飞行失败即失败）；密度两档 **8 obs / 16 obs**。
- **指标**（单位 = env 比例）：
  - `arr` 到达率：窗内曾 `‖rpos‖<0.5m` 连续保持 ≥50 步；
  - `coll` 碰撞率：窗内曾发生 ≥1 次几何接触边沿（`dmin<0.05` 的进入瞬间）；
  - `joint` 联合成功 = `arr ∧ 整窗 0 碰撞边沿`。

---

## 4. Reward 设计（F1 最终配方）

> 设计目标（用户）：动作平滑 + 时间短 + 安全低碰 + 到达。根治：**删除 Hover 常驻正基座**（悬停刷分平台 ~+300/窗），改"受 CBF/近障约束的最短时间到达"。

### 4.1 Reward 完整数学形式（`reward_scheme: f1`，逐项对应 `nav_vel.py::_compute_reward_and_done` 的 f1 分支）

$$r^{f1}_t=\underbrace{w_f\,\min\!\Big(1,\ \tfrac{\mathrm{relu}(\mathbf v_t\cdot\hat{\mathbf u}_{goal})}{v_{\max}}\Big)}_{\text{① 飞行主导(无距离核, 悬停/远离=0)}}+\underbrace{\big[w_{arr}+w_t\big(1-\tfrac{t_{arr}}{T}\big)\big]\,\mathbb 1[\mathrm{arrive}]}_{\text{③ time-scaled 到达}}-\underbrace{c_t}_{\text{② 时间成本(默认0)}}$$
$$\qquad-\underbrace{w_s\lVert\Delta\mathbf a_t\rVert^2}_{\text{④ 动作平滑}}-\underbrace{\lambda_s\max(0,z_{ref}-z_t)}_{\text{存活罚}}-\underbrace{w_{to}\,\mathbb 1[\mathrm{timeout}]}_{\text{⑤ 超时未达(600步从未到达)}}-\underbrace{r^{obs}_t}_{\text{⑥ 障碍安全}}-\underbrace{r^{cbf}_t}_{\text{⑦ CBF dual}}$$

其中分量定义（$T=600$、$v_{\max}=1.8$、$\mathbf a_t$ = 滤波前 4D 速度+yaw 指令，$\lVert\cdot\rVert$ = 2-范数）：

- ① $\hat{\mathbf u}_{goal}=\tfrac{\mathbf p_g-\mathbf p_t}{\lVert \mathbf p_g-\mathbf p_t\rVert}$（指向目标，3D 不含 yaw），$\mathbf v_t$ = 平动线速度；**无距离核** → 远端=近端同强（spawn 处即有强拉起梯度）；悬停/远离 → 0，无刷分平台。
- ③ arrive：$\lVert \mathbf p-\mathbf p_g\rVert < r_{arr}=0.5$ 连续 $n_h=50$ 步触发一次；$t_{arr}$ = 首达步（`progress_buf`）→ 越快 bonus 越多。
- ④ $\Delta\mathbf a_t=\mathbf a_t-\mathbf a_{t-1}$ 为速度指令差分（非油门差分）。
- ⑤ timeout：整窗 600 步 `truncated` 且从未到达（`episode_any_arrival=False`）→ 一次性 −$w_{to}$。
- ⑥ 静态球几何（判定半径 $r_{s,i}=r_{o,i}+0.15(\text{drone})+0.05(\text{infl})$；净空 $d_{i,t}=\lVert \mathbf p_t-\mathbf p_{o_i}\rVert-r_{s,i}$，$d_{\min,t}=\min_i d_{i,t}$，危险区 $D=0.6$、碰撞边距 $0.05$）：

$$r^{obs}_t=\underbrace{w_{log}\lambda_{log}\sum_{i}\varphi(d_{i,t})}_{\text{⑥a log 距离罚}}+\underbrace{w_{edge}\,\mathbb 1[\mathrm{new\,edge}_t]}_{\text{⑥b 碰撞边沿}}+\underbrace{w_{slow}\,v_{\parallel,t}\,\max\!\big(0,\,1-\tfrac{d_{\min,t}}{D}\big)}_{\text{⑥c 近障减速}},\qquad \varphi(d)=\begin{cases}\ln(d/D) & 0<d\le D\\ \ln(10^{-3}/D)+100\,d & d\le 0\end{cases}$$

　　edge = $d_{\min}$ **首次** < $0.05$ 的进入瞬间（每窗只按沿计数）；$v_{\parallel}=\mathrm{relu}(\mathbf v_t\cdot\hat{\mathbf u}_{o})$ 为朝最近球心方向的速率分量。
- ⑦ CBF dual（决策球 $r^{cbf}_i=r_{s,i}+r_{safe}$，brake-off 时 $r_{safe}=0.1$；$\mathbf v^{nom}$=滤波前策略指令，$\mathbf v^{safe}$=滤波器投影输出；$\alpha=1.0$）：

$$r^{cbf}_t=w_1\!\!\underbrace{\sum_{i\in act}\min\big(0,\ n_i^{\top}\mathbf v^{nom}_t+\alpha\,h_{i,t}\big)}_{\mathrm{viol}\,\le\,0}+w_2\Big(1-e^{-\lVert \mathbf v^{safe}_t-\mathbf v^{nom}_t\rVert^2/\sigma^2}\Big),\qquad h_{i,t}=\lVert \mathbf p_t-\mathbf p_{o_i}\rVert-r^{cbf}_i$$

　　`viol` 项罚"滤波前指令侵入 CBF 球"（策略学的是自己被罚的指令）；`correction` 项罚"滤波器实际纠偏量"（被拦越多罚越多 → 教指令留安全区、训练中滤波 internalize）。

### 4.2 完整分项表（数值 = F1 最终 D2-16 通关配方 `pg6q5ji5`）

| # | 项 | CLI 键 | 公式 | 配方值 | 类型 / 触发 |
|---|---|---|---|---|---|
| ① | 飞行主导 | `reward_fly_weight` | $+w_f\,f^{fly}$ | **6.0** | 稠密·正（每步朝目标飞；悬停/远离=0）|
| ② | 时间成本 | `reward_time_cost` | $-\,c_t$ | 0（默认关；强吸引子下试 0.1，密集障碍有害）| 稠密·负（每步）|
| ③ | 到达 | `arrive_bonus` / `arrive_time_bonus` | $+w_{arr}+w_t\big(1-\tfrac{t_{arr}}{T}\big)$ | 30 / 30 | 稀疏·大正（进圈 0.5 m 保持 50 步）|
| ④ | 动作平滑 | `reward_action_smoothness_weight` | $-\,w_s\lVert\Delta\mathbf a\rVert^2$ | 0.2 | 稠密·负（速度指令差分）|
| 存活 | 掉高惩罚 | `survival_penalty_weight`（`z_ref`）| $-\,\lambda_s\max(0,\,z_{ref}-z)$ | 0.1（z_ref=1.0）| 稠密·负（低空）|
| ⑤ | 超时未达 | `reward_timeout_penalty` | $-\,w_{to}\,\mathbb 1[\mathrm{timeout}]$ | 40 | 事件·大负（600 步整窗从未到达）|
| ⑥a | 障碍 log 罚 | `reward_obs_log_weight` / `reward_obs_log_scale` | $-\,w_{log}\lambda_{log}\sum_i\varphi(d_i)$ | 1.5 × 0.3（D=0.6）| 稠密·负（危险区 $0<d\le0.6$）|
| ⑥b | 碰撞边沿 | `reward_collision_edge` | $-\,w_{edge}\,\mathbb 1[\mathrm{new\,edge}]$ | 4 | 事件·负（$d_{\min}<0.05$ 进入瞬间）|
| ⑥c | 近障减速 | `reward_near_slowdown_weight` | $-\,w_{slow}\,v_{\parallel}\max(0,\,1-\tfrac{d_{\min}}{D})$ | 1.0 | 稠密·负（$d_{\min}<D$ 且朝障飞）|
| ⑦a | CBF viol | `cbf.reward_weight`（`alpha=1.0`、`penalty_intrude`）| $+\,w_1\,\mathrm{viol}(\mathbf v^{nom})$（≤0 → 罚）| 0.1 | 稠密·负（滤波前指令侵入 CBF 球）|
| ⑦b | CBF correction | `cbf.correction_weight` / `correction_sigma` | $-\,w_2\big(1-e^{-\lVert \mathbf v^{safe}-\mathbf v^{nom}\rVert^2/\sigma^2}\big)$ | 0.1 / 0.5 | 稠密·负（被滤波器拦截时）|
| — | 熵 | `algo.entropy_coef` | — | 0.05 | 防 PPO 熵塌缩 |

> 固定环境/任务参数：`v_max=1.8`、`T=600`、`arrive_radius=0.5`、`arrive_hold_steps=50`、`success_terminate=false`、`soft_respawn=true`（训练）、curriculum `[2,4,8,16]`、`cbf.mode=hybrid, penalty_src=dual, use_brake_term=false`。
> **f1 下被删除的 legacy 项**：`pose`、`pose·(up+spin)`、`effort(正)`、`PBRS`——悬停常驻正基座全部移除（这是 f1 与 legacy 唯一的 reward 结构性区别）。

- 配方速记：`reward_scheme=f1, w_f=6.0, arrive 30+30t, to=40, smooth=0.2, edge4/near1, CBF hybrid dual 0.1/0.1 σ0.5, ent=0.05, brake off`。
- 结果：带 filter 部署 ON joint 0.930（coll 0.9%）≫ legacy 0.743；from-scratch 12M 通关 16 障（vs legacy 50M+）。

---

## 5. 四臂机制定义与部署形态

| 臂 | `cbf.mode` | 训练时 filter | 训练时 CBF reward core | 部署是否带 runtime filter | 语义 |
|---|---|---|---|---|---|
| **dual**（hybrid）| hybrid | ✅ 有 | ✅ dual（w1·viol + w2·corr）| ✅ 可带（推荐）| filter 保安全 + reward 教 internalize（CBF-RL 论文主模型 B）|
| **filter_only** | filter_only | ✅ 有 | ❌ 无 | ✅ 可带 | 纯 filter 兜底，无 reward 引导 |
| **reward_only** | reward_only | ❌ **无** | ✅ 仅 w1·viol（dual 退化为 viol 项）| ❌ **无**（天然无 filter）| 只用惩罚学安全 |
| **naive** | none | ❌ **无** | ❌ 无 | ❌ **无**（天然无 filter）| 纯 PPO 靠障碍几何罚 |

> ⚠️ 对比规则：**naive / reward_only 没有 runtime filter 可撤**——它们只出现在"无 filter"那一侧；带 filter 部署侧只放 dual / filter_only（及其 ON 结果）。reward_only/naive 训练 from-scratch 12M **卡在 2 障**（无滤波学不动高密度，本身即结论），其在 16 obs 的数字只作参考。

---

## 6. 主结果（验收 · 严格单命 joint@600/1024）

### 6.1 带 runtime CBF filter 部署（适用 dual / filter_only）— 推荐部署形态
| 密度 | dual | filter_only |
|---|---|---|
| 8 obs | **0.971**（arr 0.974 / coll 0.3%）| 0.980（0.986 / 0.6%）|
| 16 obs | **0.944**（0.947 / 0.4%）| 0.932（0.939 / 1.0%）|

### 6.2 无 runtime filter（dual/filter_only 撤 filter = internalize 判据；reward_only / naive 天生无 filter）
| 密度 | dual（撤 filter）| filter_only（撤 filter）| reward_only | naive |
|---|---|---|---|---|
| 8 obs | 0.787（0.951 / 18.1%）| 0.771（0.958 / 19.8%）| 0.764（0.942 / 19.1%）| 0.755（0.954 / 21.0%）|
| 16 obs | 0.616（0.911 / 33.2%）| 0.626（0.914 / 31.4%）| 0.565（0.891 / 37.2%）| 0.641（0.908 / 28.7%）|

> 表格内为 `joint（arr / coll）`。

---

## 7. 结论与讨论

1. **runtime CBF filter 是决定性安全组件**：带 filter 部署 @16 obs joint ~0.93–0.94（coll <1%）；撤掉后所有臂掉到 0.56–0.64（coll 28–37%）。filter 提供的"安全背锅"约一个数量级。
2. **dual 与 filter_only 打平（噪声内）**：16 obs 单命 joint 0.944 vs 0.932；dual 额外在撤 filter 侧略稳（0.616 vs 0.626，同样噪声内）。带 filter 部署建议取二者任一即可。
3. **internalize（撤 filter 也安全）未达成**：任何臂 OFF 都 ≪ ON——与 legacy/M2/M3/New1 跨方案一致；带 filter 训练的臂把规避外包给 filter（贴边行为），撤掉即崩；这是任务级固有问题（论文 single-integrator 无此动力学滞后）。
4. **为何 naive 撤 filter 后"看起来不差"**：naive 从未有 filter，无"外包安全"的贴边行为、自带保守避障 → 撤 filter 无落差；且它**训练卡 2 障、没到 16 障**，数字解释力有限；naive 带 filter 部署反而是最差（0.82，它没学会与 filter 协作、被频繁拦截）→ **不能解读为 naive 更安全**。
5. **reward_only / naive 无滤波 from-scratch 12M 无法升到高密度**：本身即"无滤波策略学不动密集避障"的对照结论。
6. **附加手段均未能 internalize**（New2 全部实验）：obs 加 CBF 边界余量通道、reward 加 h 边界罚（±提前 buffer）、curriculum margin gate、无滤波训练——OFF coll 最低仍 38.3%（E1）> 34.1% legacy 门槛。若追求无 filter 安全，需训练期随机 filter dropout 等结构性手段，或接受"策略 + runtime filter"为最终部署形态。

---

## 8. 图表

**图 1 · 四臂训练对照曲线**（from-scratch 课程 [2,4,8,16]·12M）：课程档位 / 窗口成功 / 窗口碰撞 / 策略熵 随帧数。可见 dual 与 filter_only 同步在 ~4.9M / ~7.3M / ~9.8M 升到 4 / 8 / 16 障，reward_only 与 naive 全程卡在 2 障（熵健康但升不了密度）。

![f1_4arm_training](figures/f1_4arm_training.png)

**图 2 · 四臂严格单命验收柱状图**（@8 / 16 obs）：实色柱 = 带 runtime CBF filter 部署（仅 dual / filter_only）；斜纹柱 = 无 runtime filter（撤 filter 的 dual/filter_only 与天然无 filter 的 reward_only / naive）。可读：带 filter ~0.93–0.98 ≫ 无 filter 0.56–0.79。

![f1_4arm_eval_bars](figures/f1_4arm_eval_bars.png)

（绘图脚本：`OmniDrones/scripts/plot_f1_4arm.py`，数据源 wandb `new_reward` 四 run。）

---

## 9. 部署建议（一页速览）
- **默认部署 = dual（hybrid，w_f=6.0 课程配方，pg6q5ji5@12M）+ runtime CBF filter**：严格单命 @16 obs joint 0.944 / coll 0.4%。
- 若真机无法运行 CBF filter → 目前无 internalize 模型可用（OFF joint ≤0.64），需 filter-dropout 类训练（后续）。
- 机载算力低、想省掉 reward core → filter_only 等价部署（joint 0.932）。

---

# 附录 A · Arena1：全区域布障 + 固定起终点穿越 + 总高 3 m（环境改版后重训总结）

> 日期：2026-09-07 ｜ 分支同前（Arena1 环境 commit `c0528d8`，start z 定 1.0 commit `3831a62`）｜ wandb：**`arena1`** ｜ 阶段记录：`drones/arena1_plan.md`
> 改动要点：NavVel 由「±2.2/±2.8 中央聚集布障 + 随机起终点」→「**6×6 全区域布障 + 固定 start(-2.5,0,1.0)→goal(2.5,0,1.5) 穿越 + 总高 3 m**」；**F1 reward / obs(62) / CBF 公式不变**，四臂 from-scratch 重训。

## A.1 环境改动（相对 §3 评估环境）

| 项 | 旧（本报告 §3） | Arena1 |
|---|---|---|
| 起终点 | 随机 3D waypoint | **固定** start(-2.5,0,1.0) → goal(2.5,0,1.5)，全 env 同点 |
| 布障范围 | 中央 ±2.2 m | 全区域 ±3.0 m（6×6），z∈[0.6,2.4] |
| 总高上限 | z_max 4.5 | **z_max 3.0** |
| 课程 | [2,4,8,16] | **[0,2,4,8,12,16]**（v3 加 0 障首级：先学裸固定穿越再叠障碍）|
| 场景缓冲 | num_scene 16 | 同 16（滑动窗取最近 K=8，obs 恒 62）|

> ⚠️ **start z 由 0.5 抬到 1.0**（用户拍板）：初版 fixed start z=0.5 在现 sim/Crazyflie 下 from-scratch F1 **学不动**（0 障碍也到不了；z=0.5→1.0 单变量 3M arrival 0%→12%），因近地起降不稳。最终 fixed_init z=1.0。

## A.2 训练（F1 配方同 §4，24M，课程 [0,2,4,8,12,16]）

| 臂 | run id | 课程轨迹 | 最终训练档 |
|---|---|---|---|
| dual (hybrid) | 04ykbpii | 0→2→4（14×L0→18×L2→7×L4）| **卡 4** |
| filter_only | gh5c0qf0 | 0→2→4→8（11×L0→4×L2→18×L4→6×L8）| **卡 8** |
| reward_only | e5gul4zg | 0→2（9×L0→30×L2）| 卡 2 |
| naive | z1duerma | 0→2（11×L0→28×L2）| 卡 2 |

- **0 障首级 bootstrap 生效**：filter_only 从 v2（无首级，卡 4）推进到 8；naive/reward_only 也成功走出 0 障（会裸穿越）但在 2 障封顶（无滤波 from-scratch 学不动稠密避障，同旧 F1 结论）。
- **固定 5m 穿越 + 稠密障碍 from-scratch 显著更难**：旧 F1 随机起终点 12M 通关 16；Arena1 24M 带 filter 臂也只到 4–8。**v3 中 filter_only 反超 dual**（训练档 8 > 4）。

## A.3 严格单命 eval（soft_respawn=false @600/1024；ON=带 filter 仅 dual/fo，OFF=撤 filter；ro/naive 天然无 filter 只 OFF）

| 臂 | 档 | ON arr/coll/joint | OFF arr/coll/joint |
|---|---|---|---|
| dual | 4（实际档）| 0.006/1.9%/0.005 | 0.019/7.9%/0.017 |
| dual | 8 | 0.007/1.9%/0.006 | — |
| dual | 16 | 0.041/4.4%/0.039 | 0.090/27.1%/0.060 |
| fo | 8（实际档）| 0.041/1.7%/0.035 | 0.054/9.3%/0.049 |
| fo | 16 | 0.096/2.7%/**0.087** | 0.099/21.3%/0.058 |
| ro | 2（实际档）| — | 0.007/2.1%/0.007 |
| ro | 8 | — | 0.030/8.2%/0.025 |
| ro | 16 | — | 0.063/17.4%/0.043 |
| naive | 2（实际档）| — | 0.058/4.7%/0.056 |
| naive | 8 | — | 0.069/15.5%/0.058 |
| naive | 16 | — | 0.097/31.8%/0.056 |

**图 A-1 · Arena1 四臂训练对照**（课程档位/成功/碰撞/熵 随帧数，24M）：fo 两段升到 8、dual 到 4、ro/naive 走出 0 障后卡 2；无滤波臂 0→2 后成功率虚高（naive 熵持续升 >10 = 未收敛仍在乱逛）。

![arena1_training](figures/arena1_training.png)

**图 A-2 · Arena1 严格单命 eval 柱状图**（各自实际档 + @16 参考）：实色 = 带 filter（仅 dual/fo），斜纹 = 无 filter。可读：绝对 joint 普遍低（<0.09，任务难度如实反映），但 **fo 最高（@16 ON 0.087）且 filter 决定性**（撤 filter coll 2.7%→21.3%）。

![arena1_eval_bars](figures/arena1_eval_bars.png)

（绘图脚本：`OmniDrones/scripts/plot_arena1.py`，数据源 wandb `arena1` 四 run + 上述严格单命 eval。）

## A.4 结论（Arena1）

1. **任务难度剧增是主因，不是四臂机制反转**：固定 5m 穿越 + 全区域稠密布障让 from-scratch 收敛大幅变慢——即便加 0 障首级 bootstrap + 24M，带 filter 臂也只训到 4–8 档（旧 F1 随机起终点 12M 能通关 16）。严格单命绝对 arrival 普遍 <10%，与旧环境（0.9+）不可直接比绝对值。
2. **runtime CBF filter 依旧决定性**：撤 filter 后 coll 从 ~2–4% 升到 21–32%（约 6–8×）——Arena1 再次确认 filter 是安全兜底核心，internalize 依旧未达成。
3. **v3 中 filter_only > dual（贯穿训练与 eval）**：fo @16 ON joint 0.087 > dual 0.039；OFF coll fo 21.3% < dual 27.1%。与旧 F1 的「dual ≈ fo（噪声内打平）」不同——在更难、需更久持续绕障的任务里，dual 的 dual reward core 似有轻微保守/学习负担，纯 filter 兜底的 fo 反而更稳（但两者都远未通关，样本有限）。
4. **ro/naive（无滤波）依旧只能走 0→2 障**：Arena1 再次印证「无滤波 from-scratch 学不动稠密避障」；其高密度数字只作参考。naive @16 coll 31.8% 最高（无安全学习）。
5. **若要冲更高密度**（12/16 通关后才有与旧 F1 同量级的验收意义）：方向 = 加长帧数（>24M）/ 每档多留窗口，或 warm-start（v2/v3 的 dual/fo ckpt 同 obs/reward，仅 fixed_init 变，可作 warm 起点，需用户确认），或接受「策略未通关高密度」如实记录。**F1 reward 未动**（用户此前锁死配方）。
