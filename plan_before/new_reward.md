# NavVel Reward 重设计（new_reward）：移除 Hover 常驻基座 → 论文式「受安全约束的最短时间到达」

> 创建：2026-09-06。状态：**F1 已实现并通关（2026-09-06 22:2x–23:5x，详见 drones/new1_plan.md + f1_recipe_and_runs.md）**——本文档是 reward 方案的「完整历史 + 现行 F1 主方案」参考。
> ⚠️ **2026-09-07（env 适配 · 最新，时间点）**：环境已改 **6×6×3 严格单命 edge 穿越**（见 drones/env_design.md 改动记录）→ reward 采用 **F1「单命终局版」定案，见下方「🆕 2026-09-07 环境适配定案」节**。**navgoal / R1 / NR-1 已全部废弃归档；legacy 仅作历史对照，不再作为新实验基准。**
> ⚠️ **2026-09-07 状态注记（时间点）**：F1 方案（`reward_scheme: f1`，§F1）**已从零重训通关** D2-16 课程（pg6q5ji5@12M），带 CBF filter 部署 **ON joint 0.930 / coll 0.9%** ≫ legacy 0.743；**internalize（OFF 撤 filter）经 I1–I3/T1–T4 + D2-8 密度对照共 7+ 组失败** → reward-shaping 探到极限。**下一步转 obs 结构级改造**（CBF 边界余量 h / min_clearance 入 obs，from-scratch 重训）——设计见 **`drones/new2_plan.md`**（New1 执行记录见 `new1_plan.md` 顶部阶段性总结）。
> ⚠️ **2026-09-06 晚 更新（重要）**：**NR-1 / navgoal（删 pose 的纯 motion-based）方案已被实测否决**——from-scratch 死锁 + warm 无增益（详见 drones/new1_plan.md 执行记录）；**§R1 motion-gated 接近引导探针也失败（2026-09-06 21:33，run ht30t6tm）→ R1 废弃**。现行 reward = **F1（§F1）+ 2026-09-07 单命适配节**。以下 §1–§4 保留作历史与诊断（已标注废弃，不再作为任何当前参数依据）。
> ✅ **关键决策点已定案（2026-09-06，用户确认）**：到达结算 = **time-scaled（越快越多，需加 `first_arrival_step`）**；`success_terminate` = **false（保持）**；训练起点 = **from-scratch 低密度探针 → 升密度**；平滑层 = **速度指令 action-diff 负项**；姿态 up/spin 与能耗 effort = **全删**（详见 §7「★定案」）。
> 目标任务（用户原话）：让模型实现 **「动作平滑 + 时间短 + 安全低碰撞 + 到达终点」**；现状：**Hover 阶段（继承自 Hover 任务）的常驻奖励严重干扰，模型为刷固定 ~300 return 而不再向目标点前进。**
> 输入：
> - 论文：`drones/MinerU_markdown_...CBF-RL...md`（Yang et al. 2026；核心 = §III 式 (18)–(23)、Alg.1、Table II/I/III）
> - 现状：`drones/m3_plan.md`（M3-A/B 全部实验记录，尤其「改进 v4 逐项预算/失衡结论」）
> - 代码：`OmniDrones/omni_drones/envs/single/nav_vel.py::_compute_reward_and_done`、`cfg/task/NavVel.yaml`
> - 口径文档：`drones/navvel_rl_interface.md` §3
> 仓库：`/home/lz/lzspace/drones/OmniDrones`；环境 `conda activate lz_env`，wandb 项目 `CBFM3`。

---

## 💰 奖励系数拆解 · 稠密（每步）/ 稀疏（一次性）数值表（2026-09-07，用户要求补）

> 前提：`reward_scheme=f1`、dt=0.01、v_max=1.8、单命（soft_respawn=false）。只列**当前单命终局版实际会用到的项**。
> ⚠️ 只有 `①` 是「每步都可能有正收入」的稠密项，且上不封顶到 w_f=6/步——这正是 return 被抬到 ~1700–1900 的来源（≈ w_f×飞行步数），**不是到达的质量信号**（见下方「为什么 return 大≠学得好」）。

### 一、稠密项（每步结算）

| 键 | 含义 | 公式 | 每步量级（示例） | 方向 |
|---|---|---|---|---|
| `reward_fly_weight`(w_f)=6 | 飞行主导：正比「朝目标速度投影」 | $+w_f\min(1,\tfrac{\mathrm{relu}(\mathbf v\cdot\hat{\mathbf u}_{goal})}{1.8})$ | 悬停 0；慢飞+0.5~2；**全速对齐 ≈+6/步（封顶）** | 正·稠密 |
| `reward_time_cost`(c_t)=0 | 每步时间成本（默认关） | $−c_t$ | 0（若开 0.05~0.1 → −0.05~−0.1/步） | 负·稠密 |
| `reward_action_smoothness_weight`(w_s)=0.2 | 速度指令差分平滑 | $−0.2\,\lVert\Delta\mathbf a\rVert^2$（Δa=滤波前 4D 指令变化） | 稳态≈0；变向 \|\|Δa\|≈0.5 → −0.05/步；抖振≈1 → −0.2/步 | 负·稠密 |
| ⑦a log 距离罚（`reward_obs_log_weight`1.5 × `scale`0.3 =0.45/球）| 危险区(D=0.6)内净空 | $−0.45\sum_i\varphi(d_i),\ \varphi=\ln(d/D)$（d≤0: ln(1e-3/D)+100d） | d=0.5 → −0.08/步；d=0.3 → −0.31/步；d=0.1 → −0.80/步；d≤0 极负 | 负·稠密（仅 level≥1）|
| ⑦c near 减速（`reward_near_slowdown_weight`=1.0）| 朝障飞减速罚 | $−1.0\,v_{\parallel}\max(0,1-\tfrac{d_{\min}}{0.6})$ | d=0.3,v∥=1 → −0.5/步；d≈0.05 → −0.92/步 | 负·稠密（仅 level≥1）|
| ⑧a CBF viol（`cbf.reward_weight`=0.1）| 罚滤波前指令的 CBF 违反（≤0）| $+0.1\cdot\sum_{i}\min(0,n_i^\top v^{nom}+\alpha h_i)$ | 被拦时 −0.1·\|viol\|/步（viol 越大越负）| 负·稠密（仅 level≥1）|
| ⑧b CBF corr（`correction_weight`=0.1, σ=0.5）| 高斯惩罚滤波纠偏量 | $−0.1(1-e^{-\|v^{safe}-v^{nom}\|^2/0.25})$ | corr=0.5 → −0.063/步；corr≈1 → −0.098/步 | 负·稠密（仅 level≥1）|

### 二、稀疏项（一次性）

| 键 | 含义 | 公式 | 量级 | 方向 |
|---|---|---|---|---|
| `arrive_bonus`(w_arr)=30 + `arrive_time_bonus`(w_t)=30 | 到达（进圈 0.5m 保持 50 步）一次性结算 | $+30+30(1-\tfrac{t_{arr}}{600})$ | t_arr=0 → +60；t_arr=300 → +45；t_arr=590 → ≈+30 | 正·稀疏 |
| `reward_crash_penalty`=10 | 坠地(z<z_min)即整局结束 | $−10$ | −10/局 | 负·稀疏·终局 |
| `reward_oob_penalty`=10 | 出界(|x|>3/|y|>3/z>3)即整局结束 | $−10$ | −10/局 | 负·稀疏·终局 |
| `reward_timeout_penalty`=40 | 600 步从未到达 | $−40$ | −40/局 | 负·稀疏 |
| ⑦b `reward_collision_edge`=6 | 新碰撞边沿（单命=同时终局）| $−6\,\mathbb 1[\mathrm{new\,edge}]$ | −6/次 | 负·稀疏·终局 |

### 三、为什么 return≈1700–1900 大 ≠ 学得好（本批 30M 实测教训）
- 一次「**飞了但没到**」的窗口：全速朝目标飞 ~300 步 × +6 ≈ **+1800**（fly 收入），扣掉少量平滑，return 照样 ~1770——即使 arrival=0。
- 到达只 +30~60、超时 −40，相对 300 步的 +1800 是「零头」→ **reward 里「到达/失败」的稀疏信号被 w_f=6 的每步飞行收入完全淹没**。
- 实测：四臂 train return 1773–1904、`arrival` EMA 0.63–0.96，但**严格单命 eval 固定点 arrival_rate 0–8.6%** → 这些模型「会飞（赚 fly 分）但不可靠到达」。
- **方向性判断**：① w_f=6 每步收入需与「到达奖励/超时」重新配平（或改窄核/减 w_f）；② 单命 + `success_terminate=false` 下「到了不停继续飞/OOB」让每局更易失败，须重估；③ 训练统计 `arrival`(EMA 瞬时内圈占比) ≠ 到达率，判定一律以 eval `arrival_rate`(曾到达保持) 为准。

---

## 🆕 2026-09-07 环境适配定案（时间点：2026-09-07，紧跟 env_design 环境改动）：F1「严格单命 · 6×6×3」终局版

> 前置环境变更（详见 drones/env_design.md 改动记录）：场地 6×6×3 + 箱式 OOB(±3)；起终点强制对侧（start 固定 `x=-2.8` 线、target 固定 `x=+2.8` 线，y∈[-2.8,2.8]、z∈[0.4,2.4]，距墙 0.2/0.1m）；**严格单命**（`soft_respawn=false` + `obstacle.max_collisions=1`：坠地/OOB/碰一次即整局结束）；**去掉 survival 保高惩罚**；eval 固定点 start(-2.8,0,0.5)→goal(2.8,0,1.0)。

### 一、结论：reward 需要改吗？
**需要，但只改「终局 / 存活」类项并重标定，F1 的 ①②③④⑤⑥⑦ 结构不变**（仍以 `reward_scheme: f1` 为基）。四个触发点：
1. **严格单命 ⇒ 一次失败 = 整局结束（不再复活）**：旧 F1 把 crash/oob/early-death 全设 0 是因为与多命软重生冲突（M1 return≈−110）；单命下这些一次性惩罚不再被复活稀释，可当「终局成本」重新启用并标定。`reward_respawn_penalty` **语义失效（无 respawn）→ 删除**。
2. **survival 已由环境删除**：reward 公式里的存活项同步删掉；低空(0.4~0.6m)飞行不再被罚 → 近地 from-scratch 可学性风险转由「训练 z 下限 / 0 障 bootstrap」处理（env 参数，非 reward）。
3. **碰撞现在 = 终局**：⑥b `edge` 每局至多 fire 一次；per-step 主力变为 ⑥a log + ⑥c near + ⑦ CBF dual。
4. **任务变长且贴边**：起/终点贴 6×6 边界、y 全覆盖 → 直飞路程可达 ~6–8 m（≈350–500 步）；from-scratch 乱飞极易瞬时 OOB/近地坠 ⇒ 终局罚要小、课程需 0 障首级，否则 Arena1「单命学不动」会复现。

### 二、终版公式（f1-singlelife；删去的项用删除线标出）
$$r_t=\underbrace{w_f\,\min\!\big(1,\ \tfrac{\mathrm{relu}(\mathbf v_t\cdot\hat{\mathbf u}_{goal})}{v_{\max}}\big)}_{\text{① 飞行主导(无核)}}+\underbrace{\big[w_{arr}+w_t(1-\tfrac{t_{arr}}{T})\big]\mathbb 1[\mathrm{arrive}]}_{\text{③ 到达}}-
\underbrace{c_t}_{\text{② 时间成本(默认0)}}$$
$$\qquad-\underbrace{w_s\lVert\Delta\mathbf a_t\rVert^2}_{\text{④ 平滑}}
-\underbrace{\big(w_{crash}\mathbb 1[\mathrm{crash}]+w_{oob}\mathbb 1[\mathrm{oob}]+w_{ed}\,\mathrm{scale}\,\mathbb 1[\mathrm{crash}\cup\mathrm{oob}]\big)}_{\text{⑤终局(单命, 新启用)}}
-\underbrace{w_{to}\mathbb 1[\mathrm{timeout}]}_{\text{⑥超时}}$$
$$\qquad-\underbrace{\Big[w_{log}\lambda_{log}\sum_i\varphi(d_{i,t})+w_{edge}\mathbb 1[\mathrm{new\,edge}_t]+w_{slow}\,v_{\parallel}\,\max(0,1-\tfrac{d_{\min,t}}{D})\Big]}_{\text{⑦ 障碍安全}}
-\underbrace{w_1\!\sum_{i\in act}\min(0,\,n_i^{\top}\mathbf v^{nom}_t+\alpha h_{i,t})+w_2\big(1-e^{-\lVert\mathbf v^{safe}_t-\mathbf v^{nom}_t\rVert^2/\sigma^2}\big)}_{\text{⑧ CBF dual}}$$
> 删除项：~~−λ_s·max(0, z_ref−z)~~（旧 survival 保高，2026-09-07 删）；`reward_respawn_penalty`（无 respawn，删除）；时间成本 ② 默认 0（600 步窗对 6 m 横穿≈350–500 步仍够，若贴边磨蹭/时间紧再开 0.05–0.1）。

### 三、参数表（f1-singlelife 起点 = 在旧 F1 配方 pg6q5ji5 之上仅改 ⑤存活/终局）

| # | 项 | 键 | 公式 | 新起点 | 旧 F1 值 | 说明 |
|---|---|---|---|---|---|---|
| ① | 飞行主导 | `reward_fly_weight` | $+w_f\min(1,\tfrac{\mathrm{relu}(\mathbf v\cdot\hat{\mathbf u}_{goal})}{v_{\max}})$ | **6.0** | 6.0 | 不变；单命下若 from-scratch 卡 → 先 0 障 + 6；若冲得过猛再降 |
| ② | 时间成本 | `reward_time_cost` | $−c_t$ | 0 | 0 | 默认关；600 步够用，磨蹭/时间紧再开 0.05–0.1 |
| ③ | 到达 | `arrive_bonus`/`arrive_time_bonus` | $+w_{arr}+w_t(1-\tfrac{t_{arr}}{T})$ | 30 / 30 | 30/30 | 不变；任务时间更紧 ⇒ time-scaled 更关键 |
| ④ | 平滑 | `reward_action_smoothness_weight` | $−w_s\lVert\Delta\mathbf a\rVert^2$ | 0.2 | 0.2 | 不变 |
| ⑤a | 坠地终局 | `reward_crash_penalty` | $−w_{crash}\mathbb 1[\mathrm{crash}]$ | **10** | 0 | **单命新启用**；≤20 防 from-scratch 拒飞/早期大负 |
| ⑤b | 出界终局 | `reward_oob_penalty` | $−w_{oob}\mathbb 1[\mathrm{oob}]$ | **10** | 0 | **单命新启用**；贴边 from-scratch 易瞬时 OOB，先 10 |
| ⑤c | 早死 | `reward_early_death_weight` | $−w_{ed}\cdot\mathrm{scale}\cdot\mathbb 1$ | 0 | 0 | 先不启用（贴边瞬时 OOB 会被放大）；需要再 ≤5 |
| ~~~ | ~~respawn 罚~~ | ~~`reward_respawn_penalty`~~ | — | **删/0** | 0 | 无 respawn ⇒ 语义失效 |
| ~~~ | ~~survival~~ | ~~`survival_penalty_weight`~~ | ~~−λ_s max(0,z_ref−z)~~ | **0（已删）** | 0.1 | 环境已删（env_design），reward 同步删 |
| ⑥ | 超时未达 | `reward_timeout_penalty` | $−w_{to}\mathbb 1[\mathrm{timeout}]$ | 40 | 40 | 不变；600 步整窗从未到达 |
| ⑦a | log 距离罚 | `reward_obs_log_weight/scale` | $−w_{log}\lambda_{log}\sum_i\varphi(d_i)$ | 1.5×0.3 | 1.5×0.3 | 不变；单命下 per-step 主力之一 |
| ⑦b | 碰撞边沿 | `reward_collision_edge` | $−w_{edge}\mathbb 1[\mathrm{new\,edge}]$ | **6** | 4 | 单命=终局事件（每局至多一次）⇒ 上调强化「别碰」 |
| ⑦c | 近障减速 | `reward_near_slowdown_weight` | $−w_{slow}v_{\parallel}\max(0,1-\tfrac{d_{\min}}{D})$ | 1.0 | 1.0 | 不变 |
| ⑧ | CBF dual | `cbf.reward_weight`/`correction_weight`/`sigma` | viol + 高斯 corr | 0.1/0.1/0.5 | 0.1/0.1/0.5 | 起步不变；单命下 viol 更「贵」，想加强 OFF 安全可 w1→0.2 小扫 |
| — | 熵 | `algo.entropy_coef` | — | 0.05 | 0.05 | 单命短窗方差大 → 卡住可 0.05–0.1 |

### 四、窗级预算（单命 6×6×3，d0≈5–8 m、直飞≈350–500 步、保持 50）

| 策略 | ① 每步 | ③/⑥ | ⑤终局 | 净 return/窗（粗估，w_f=6） |
|---|---|---|---|---|
| 安全高效直达 | +1.2~3/步（w_f6×对齐度） | +30~51 / 0 | 0 | **高正（数百）** |
| 贴障穿缝直达（filter 拦） | 同上 | +30~51 | 0 | 正但降（⑦/⑥a 扣）|
| 绕远磨蹭 600 内到 | 低 | +30~33 | 0 | 明显更少（time-scaled）|
| 悬停/原地 600 步 | 0 | 0 / −40 | 0 | **≈ −40**（无 survival，仅 timeout）|
| 早碰/早出界（~100 步） | 少量 + | 0 | −10~−16 | **明显负 → 强「别死」信号** |

> 关键差异：**直达(数百正) vs 悬停(−40) vs 早死(负)** —— 单命下「早死即亏掉整局可达收益」本身就构成强隐式代价，⑤ 终局罚只需小量（10 左右）帮 value 收敛，勿设大。

### 五、作废 / 删除清单（老旧的 reward 与参数，2026-09-07）
1. **reward_scheme = navgoal / r1**：探针死锁 → **废弃**（代码分支仅作兼容保留，不再使用）。
2. **reward_scheme = legacy（Hover 常驻基座）**：代码默认但**不再是新实验基准**；仅 Arena1/历史对照（新环境必须 CLI 切 `reward_scheme=f1`）。
3. **survival 保高**（`survival_penalty_weight=0.1`、`z_ref`）：**已删=0**（env 与 reward 同步）。
4. **`reward_respawn_penalty`**：单命无 respawn → **删除/恒 0**。
5. **PBRS**（`reward_pbrs_weight`/`pbrs_gamma`）：F1 不用 → 新配方恒 0（保持键位兼容）。
6. R1/NR-1 的 `reward_gate_weight`(w_g)、progress 势差 γ=1.0 等旧参数：随方案废弃，不作为任何当前依据。
7. 基于「多命 600 窗」的旧预算/验收叙述：作废，以本节约算为准（§5.3 表按单命/固定点重读）。

---

## 0. TL;DR（一句话）

**旧 reward 的根子 = 悬停也恒正的常驻项（`pose` 径向场 + `pose·(up+spin)` + `effort` 正 + PBRS 悬停红利）堆出 ~100–300/窗 刷分平台，把任务项稀释到 <15%（诊断见 §1）。**
**现行 reward = F1（`reward_scheme: f1`，见 §F1）**：无距离核飞行主导 `w_f·relu(v·u_goal)/v_max` + time-scaled 到达 + 超时 + 障碍/CBF dual，已删光 passive 基座；D2-16 课程 12M from-scratch 通关（pg6q5ji5，ON joint 0.930）。
**2026-09-07 环境改为「6×6×3 严格单命 edge 穿越」后 → F1「单命终局版」**（新增 crash/OOB 终局一次性罚、删 survival 与 respawn 罚、碰撞=终局 ⇒ edge 上调）——**完整公式与参数表见下方「🆕 2026-09-07 环境适配定案」节**。

---

---

## ❌ R1（已废弃·归档 2026-09-07）：motion-gated 接近引导

> 结论：**探针失败（run ht30t6tm，0 障 from-scratch 10M arrival 0）——接近势核 k=1.6 使远端≈死区 + 平滑罚压死探索，PPO 学成“静止”（与 navgoal 同型）。教训 → 用 F1「无距离核飞行主导」解决（见 §F1）。**

---

## ⭐⭐ F1（现行主方案 · 2026-09-07 起按「单命终局版」运行）：飞行主导 + 时间成本

> **用户反馈（2026-09-06 22:xx）：「目前让四旋翼起飞的吸引力完全不够，还是需要重新设计 reward」**。
> **失败总结论**：navgoal（纯运动差分）与 R1（v·u_goal × 接近势核）from-scratch 双杀，共用两个结构缺陷：
> ① **远端引导衰减到≈0**（R1 的核 k=1.6 在 d≈3.6 处 pose≈0.03 → 远端=navgoal=无引导）；
> ② **悬停无持续代价**（只有 episode 末 −40 一次，600 步内悬停几乎「免费」）→ PPO 最优解 = 静止。
> **F1 的设计对偶地同时修这两点**：把「飞向目标」从「距离核 × 运动」改为**纯运动项（无距离核，远端=近端同强）**，并加 **per-step 时间成本** 让悬停持续亏钱；平滑罚降档不再压死探索。

### F1 主公式（nav_vel.py `reward_scheme: f1`）——完整形式（含全部项，见下方分项表）
$$r^{f1}_t=\underbrace{w_f\,\min\!\Big(1,\ \tfrac{\mathrm{relu}(\mathbf v_t\cdot\hat{\mathbf u}_{goal})}{v_{\max}}\Big)}_{\text{① 飞行主导(无距离核, 悬停/远离=0)}}+\underbrace{\big[w_{arr}+w_t\big(1-\tfrac{t_{arr}}{T}\big)\big]\,\mathbb 1[\mathrm{arrive}]}_{\text{③ time-scaled 到达}}-\underbrace{c_t}_{\text{② 时间成本(默认0)}}$$
$$\qquad-\underbrace{w_s\lVert\Delta\mathbf a_t\rVert^2}_{\text{④ 动作平滑}}-\underbrace{\lambda_s\max(0,\,z_{ref}-z_t)}_{\text{存活罚(2026-09-07 已删=0)}}-\underbrace{w_{to}\,\mathbb 1[\mathrm{timeout}]}_{\text{⑤ 超时未达(600步从未到达)}}-\underbrace{r^{obs}_t}_{\text{⑥ 障碍安全}}-\underbrace{r^{cbf}_t}_{\text{⑦ CBF dual}}$$

> **完整分项**（逐项对应 `nav_vel.py::_compute_reward_and_done` 的 f1 分支；$T=600$、$v_{\max}=1.8$、$\mathbf a_t$=滤波前 4D 速度+yaw 指令）：
> ⑥（净空 $d_i=\lVert \mathbf p-\mathbf p_{o_i}\rVert-r_{s,i}$，$r_{s,i}=r_{o,i}+0.15+0.05$，$d_{\min}=\min_i d_i$，危险区 $D=0.6$）：
> $$r^{obs}_t=w_{log}\lambda_{log}\sum_{i}\varphi(d_{i,t})+w_{edge}\,\mathbb 1[\mathrm{new\,edge}_t]+w_{slow}\,v_{\parallel,t}\max(0,\,1-\tfrac{d_{\min,t}}{D}),\qquad \varphi(d)=\begin{cases}\ln(d/D)&0<d\le D\\ \ln(10^{-3}/D)+100\,d&d\le 0\end{cases}$$
> ⑦（决策球 $r^{cbf}_i=r_{s,i}+r_{safe}$，brake-off $r_{safe}=0.1$；$\mathbf v^{nom}$=滤波前指令，$\mathbf v^{safe}$=滤波投影）：
> $$r^{cbf}_t=w_1\!\sum_{i\in act}\min(0,\,n_i^{\top}\mathbf v^{nom}_t+\alpha h_{i,t})+w_2\Big(1-e^{-\lVert \mathbf v^{safe}_t-\mathbf v^{nom}_t\rVert^2/\sigma^2}\Big),\qquad h_{i,t}=\lVert \mathbf p_t-\mathbf p_{o_i}\rVert-r^{cbf}_i$$

**F1 最终配方完整分项表（数值 = D2-16 通关配方 `pg6q5ji5`）**

| # | 项 | 键 | 公式 | 配方值 | 类型 / 触发 |
|---|---|---|---|---|---|
| ① | 飞行主导 | `reward_fly_weight` | $+w_f\,\min(1,\tfrac{\mathrm{relu}(\mathbf v\cdot\hat{\mathbf u}_{goal})}{v_{\max}})$ | **6.0** | 稠密·正（无核，悬停/远离=0）|
| ② | 时间成本 | `reward_time_cost` | $-\,c_t$ | 0（默认关）| 稠密·负（每步）|
| ③ | 到达 | `arrive_bonus`/`arrive_time_bonus` | $+w_{arr}+w_t(1-\tfrac{t_{arr}}{T})$ | 30/30 | 稀疏·大正（进圈0.5m 保持50步）|
| ④ | 平滑 | `reward_action_smoothness_weight` | $-\,w_s\lVert\Delta\mathbf a\rVert^2$ | 0.2 | 稠密·负（指令差分）|
| 存活 | 掉高罚 | `survival_penalty_weight`(`z_ref`) | $\,-\,\lambda_s\max(0,z_{ref}-z)$ | 0.1 → **0（2026-09-07 已删）** | 稠密·负（已删）|
| ⑤ | 超时未达 | `reward_timeout_penalty` | $-\,w_{to}\,\mathbb 1[\mathrm{timeout}]$ | 40 | 事件·大负（600步整窗未达）|
| ⑥a | log 距离罚 | `reward_obs_log_weight/scale` | $-\,w_{log}\lambda_{log}\sum_i\varphi(d_i)$ | 1.5×0.3（D=0.6）| 稠密·负 |
| ⑥b | 碰撞边沿 | `reward_collision_edge` | $-\,w_{edge}\,\mathbb 1[\mathrm{new\,edge}]$ | 4 | 事件·负（dmin<0.05 进入瞬间）|
| ⑥c | 近障减速 | `reward_near_slowdown_weight` | $-\,w_{slow}\,v_{\parallel}\max(0,1-\tfrac{d_{\min}}{D})$ | 1.0 | 稠密·负 |
| ⑦a | CBF viol | `cbf.reward_weight`(`alpha`) | $+\,w_1\,\mathrm{viol}(\mathbf v^{nom})$（≤0→罚）| 0.1（α=1.0）| 稠密·负 |
| ⑦b | CBF correction | `cbf.correction_weight`/`correction_sigma` | $-\,w_2(1-e^{-\lVert \mathbf v^{safe}-\mathbf v^{nom}\rVert^2/\sigma^2})$ | 0.1/0.5 | 稠密·负（被拦截时）|
| — | 熵 | `algo.entropy_coef` | — | 0.05 | 防塌缩 |

> f1 删除 legacy 常驻正基座：`pose`、`pose·(up+spin)`、`effort(正)`、`PBRS`；到达后 `success_terminate=false` 保持。
- $\mathbf u_{goal}$、$\mathbf v$、$\mathbf{rpos}$ 同 §R1；$\text{①}$ **无距离衰减** → spawn 处全速直飞每步 +w_f（≈legacy「接近正」量级的 3–10×），**远端拉起梯度不再死**；且 $\text{①}$ 是**速度指令的直接函数**（action-local，非 position 积分效应），梯度信噪比高 → from-scratch 有望直接 hill-climb
- $\text{②}$ per-step −c_t：悬停窗 = −c_t·600（大负），绕圈/磨蹭持续亏 → 配合 ① 使「直飞 ≈ +O(200·w_f)」vs「悬停 −60」落差巨大（治「时间短」）；c_t 同时对每步生效，critic 更易学
- **悬停平台=0**：静止时 ①=0 且 ② 在扣 → 无 legacy 式 +300 基座；到达后 soft-respawn 续命转下目标，无理由滞留
- 平滑 ④ 权重降到**不压死探索**的水平：乱飞期 adiff≈1.5 时罚 w_s·2.25 须 < ① 远场收益（w_f≥1 时成立）——这是 R1 失败点②的反向修复
- 数值起点：`w_f`=1.5、`c_t`=0.1（可选，用户先不加）、`w_s`=0.2、arr 30+time30、to 40（可保留）、ent 0.05；CBF hybrid/dual w1=w2=0.1 σ0.5
- 窗预算（0 障，d0≈3.4，全速直飞 ~200 步）：直飞 ≈ +1.25×200 −20 ≈ **+230**；悬停 = −60；差 ≈ **+290**（navgoal/R1 差仅 ~90，且 R1 远端不可达）
- 键：`task.reward_scheme=f1` + `task.reward_fly_weight`(=w_f)/`task.reward_time_cost`(=c_t)（默认关）；①②③④ stat 复用
- 探针：0 障 from-scratch 10M——按用户选定**先不加时间成本②**，纯①无核飞行主导（w_f=1.5, w_s=0.2, ent 0.05）；验证 arrival 爬升/pos_error 下探/无静止。
- **✅ 探针结果（run `emy1u3ow`，2026-09-06 21:45）：纯① from-scratch 10M 可学（三方案首个不死的）**——最终 eval arrival 5.7%；train 尾段 return **+98**（转正）、pos_error **3.75→2.49 单调降**（在接近目标）、vel_norm 0.32、adiff 1.57→0.41、**entropy 稳定 -1.6（未塌到 -6）**。对照 R1（arrival 0、pos_error 恒 3.6、熵塌 -6、return -5）= **「接近势核 k=1.6 远端≈0 死区」确认为 from-scratch 失败主因；去掉核+运动主导即可学**。
- **未收敛点**：10M 尾段趋平（arrival 5.3%、pos_error 2.49、平均速度仍偏慢 0.32）——到达完成度还差 legacy 很远；下一步候选：①延长 30M 看上限 / ②现在补加 ②时间成本(治 loiter、推完成)复测 / ③warm S3 验证属性。
- **📊 延训+调参结果（2026-09-06，详见 new1_plan.md）**：纯①延训到 **30M → eval arrival 49.7%**（10M 的平台只是早段）；**w_f 1.5→3.0 是加速旋钮**（10M from-scratch arrival 5→18.4%、pos_error 2.4→0.62，≈纯① 20M 水平）；时间成本 c_t=0.1 与到达奖励 60/60 在 10M 口径未见益（2.6–5.0%）。当前最优配方 **F1 w_f=3.0**。
- **📊📊 第二批（w_f 上限/组合）**：**w_f 单调强加速——1.5→5% / 3.0→18% / 6.0→71.4% @10M from-scratch**（wf6 run `0tjlxy7c`，pos_error 0.40、success 1.0、熵 +0.97 健康）；wf3 延到 30M = 48% ≈ 纯① 30M ⇒ **高 w_f 比长训练有效**；**时间成本②在强吸引子上加成显著**（w3+c0.1 → 56.9%，run `4fjm3il8`）。**当前最强 = F1 w_f=6.0**。⚠️ w_f=6 ⇒ +6/步 会淹没安全项(edge4/dual0.1) → 升密度前需重标 ⑥⑦。
- **📊📊📊 第三批（0 障上限 + 首测 2 障）**：**w_f=9.0 @10M 0 障 → eval arrival 93.9%**（run `12hf3149`，pos_error 0.33、success 1.0、熵 +1.75）——w_f 单调到 9 仍涨（1.5→5 / 3→18 / 6→71 / 9→94%），0 障基本一次学会；wf6 延 30M = 64% < 其 10M 的 71%（长训不如直接高 w_f）；**首次带障碍：wf3-2障 @10M → 80.4% arrival / 0 collision**（run `s2xprexh`，edge4/dual0.1 默认即够）→ **f1 有障碍可学且安全**。0 障最优 = **F1 w_f=9**；下一步 = **D2-16 对照 legacy**（w_f=3~6 + 同步标定安全权重比，盯 ON joint 0.743 / OFF coll 34%）。
- **📊📊📊📊 课程 2-4-8-16 四变体（2026-09-06 22:28）**：**F1 w_f=6.0 + curriculum [2,4,8,16] = 通关配方**——12M from-scratch 到 **16 障：eval arrival 90.6% / pos_error 0.34 / collision 仅 1.27%**（run `pg6q5ji5`）；wf3 卡在 2–4 障（弱吸引子穿不动密集）；**时间成本在密集障碍有害**（wf6+c0.1：67.8%、CBF 干预 0.15）。纸面已超 legacy D2-16（ON joint 0.743 / OFF coll 34%），**待确定性 ON/OFF eval 同口径确认**。最终推荐配方：**F1 w_f=6.0, w_s=0.2, ent0.05, arrive 30+30t, to40, edge4/near1, CBF hybrid dual 0.1σ0.5, curriculum [2,4,8,16]**。
- **✅ D2-16 确定性 eval 判定（2026-09-06，pg6q5ji5 @600/1024）**：**ON joint 0.930（arrival 0.936, coll 0.9%）≫ legacy 0.743（coll 2.3%）** —— 带 CBF filter 部署下 F1 大胜 legacy（from-scratch 12M vs legacy 50M+）；**OFF（internalize）joint 0.588 ≈ legacy 0.572 但 coll 41% > legacy 34.1% = 仍未 internalize**（与 legacy/M3 同卡点；按 CBF-RL「filter 运行时保安全」预设，ON 即部署口径已达标）。
- 风险/待观察：① 无距离耦合可能近程 overshoot 振荡（靠 ③+soft-respawn 缓解）；② c_t 会罚绕障路程（轻微，接受为「时间短」目标）；w_s 过小动作可能毛糙（用 ④ 标定）

---

## 1. 为什么旧 reward 让模型「刷 Hover 不前进」（诊断）

### 1.1 现状奖励结构（`_compute_reward_and_done` + NavVel.yaml 默认；无障时主项）

设 $d_{pos}=\lVert\mathbf p_{goal}-\mathbf p\rVert$，$\mathbf d=[\mathbf{rpos};\ \mathbf{rhead}]$，$\rho=\lVert\mathbf d\rVert$（**位置 3D 与 yaw 朝向向量差混成一个距离**），`v_max=1.8`、`dt=0.01`、窗=600 步=6 s。

| 项 | 公式（现值） | 类型 | 悬停/巡航时 |
|---|---|---|---|
| `reward_pose` | $1/\big(1+(1.6\rho)^2\big)$ | **被动径向场**（越近越大） | 恒正；悬停=常数 |
| `reward_pose·(reward_up+reward_spin)` | ×$\big(\tfrac{up_z+1}{2}\big)^2+\tfrac1{1+\omega_z^2}$ | 乘法放大 | 平飞悬停 = ×2 |
| `reward_effort` | $0.1\,e^{-e}$ | **正奖励低能耗** | 悬停低油门 → 正 |
| `reward_action_smoothness` | $w_s\,e^{-\Delta u_{throttle}}$ | 正奖励（**默认 0 关**） | 若开：悬停=满正 |
| `reward_arrival` | $10\cdot\mathbb 1[\text{进圈保持 50 步}]$ | 稀疏 | 0 |
| `reward_pbrs` | $2.0\,(d_{t-1}-0.995\,d_t)$ | 稠密势差 | **γ<1 ⇒ 悬停也 +w(1−γ)d/步** |
| survival | $-0.1\max(0,z_{ref}-z)$ | 负，仅低空 | 0（正常） |
| obstacle log/edge/near | 见 §3.7 | 负，危险区 | 0 |
| CBF dual viol/corr | 见 §3.7 | 负，被拦时 | 0 |
| crash/oob/timeout | 默认 0 | 稀疏负 | 0 |

### 1.2 m3_plan「改进 v4」已算清的逐项预算（关键引用，L330–360）

| 项 | 巡航步 | 600 步窗累计（估） |
|---|---|---|
| `pose×up(+spin)` | +0.15…0.35 | **+120…300（return 基座，用户看到的 ~300）** |
| `effort` | +~0.08 | +~45 |
| PBRS（w8） | +0.02…0.14 | +15…30（势差上限 w·d₀≈24） |
| 障碍/CBF 稠密罚 | 0 | −15…−60（仅穿障/被拦时） |
| **任务项（PBRS+arrival）窗内合计** | — | **≤ ~84，占整窗 <15%** |

### 1.3 三个结构性问题（非调参可解）

1. **Passive 径向正基座（主力）**：`pose` 只依赖「此刻离目标多近」，不依赖「是否在靠近」。悬停在任意次优距离上都能拿到一个**与运动无关的稳定正 return**（~100–300/窗）；对它而言「前进冒险穿越障碍密集区」的期望收益 <「原地不动拿固定分」→ 模型锁定悬停吸子。**CBF-RL 论文里根本没有这类项**：single-integrator 导航只有 `r_progress`（运动相关势差，悬停=0）+ `r_alive=0.01` + 稀疏 `r_goal=+1`/`r_timeout=−10`。
2. **γ<1 的 PBRS 悬停红利**：现 $r_{pbrs}=w(d_{t-1}-0.995\,d_t)$，即使不动（$d_t=d_{t-1}$）每步也 $+0.005w\,d$——又一个「悬停正」。论文式 progress 是**严格差分**（$\gamma{=}1$，悬停严格 0）。
3. **`effort` 用「正奖励低能耗」而非「罚能耗」**：悬停/低速耗能最低 → 变相奖励悬停。up/spin 只应保证「不摔/不特技」，不该做 reward 乘数放大。

> 反证（M3 数据）：m3 一路在外围加 `arrive_bonus`/`timeout_penalty`/`w16` 是在**保留基座**前提下调平衡，W4≈V3（ab/to 60/40 饱和）、S 系列到顶——因为 **ab/to 只能抬「到达峰值」，抬不动「悬停/绕远的正平台」**。根治必须删基座，重排 reward 结构。

---

## 2. 从 CBF-RL 论文学到的 reward 设计原则（Table II 对照）

论文 Table II（single-integrator 导航，引用其结构）：

| 论文项 | 公式 | 类型 | 我们能吸收的设计点 |
|---|---|---|---|
| `r_goal` | $1.0\cdot\mathbb 1[\text{goal}]$ | 稀疏结算 | 到达给**明确的大正结算**（我们把"到达后继续给被动正"去掉） |
| `r_progress` | $20.0\cdot\dfrac{\lVert\mathbf p_{t-1}-\mathbf g\rVert-\lVert\mathbf p_t-\mathbf g\rVert}{v_{max}\,\Delta t}$ | 稠密势差（**运动相关**） | 只奖「真的在接近」；**悬停=0、后退<0**；除 $v_{max}\Delta t$ 归一化使势和有界 |
| `r_alive` | $0.01\cdot\mathbb 1[\text{active}]$ | 极小常驻 | 常驻项只能**极小**，且与位置无关时绝不能是大正（防平台） |
| `r_obstacle`/`r_wall` | $-1.0\cdot\mathbb 1[\text{collision}]$ | 事件负 | 碰撞是事件/稠密负项，不设「接近障碍也给正」 |
| `r_cbf` | $100\big[\min(a^\top v+b,0)+e^{-\lVert v^{pol}-v^{safe}\rVert^2/\sigma^2}-1\big]$ | 稠密负（组合两项） | viol 项（教"指令留安全区"）+ 高斯 correction 项（教"贴近安全动作"），训练中滤波 → internalize |
| `r_timeout` | $-10.0\cdot\mathbb 1[\text{time exceeded}]$ | 稀疏负 | 未达超时给**真实成本**（打破保守/悬停吸子） |

**五条可迁移原则**：
- P1 **取消一切 passive 正基座**：不留「离目标近就恒正」的项；位置目标只通过「势差/结算」编码。
- P2 **进度 = 运动相关势差**：$\gamma{=}1$ 严格差分，悬停 0、倒退负、前进正，势和有界（除 $v_{max}\Delta t$）。
- P3 **常驻项归零或极小**：与任务无关的正常驻一律删；确需的（姿态/能耗/平滑）只做成「异常时才触发的**负惩罚**」或严格 0。
- P4 **时间短要靠「结算差」显式编码**：到达越快 bonus 越大 + 超时大负（论文 `r_timeout`），否则策略会绕远/磨时间（m3 实证：无 timeout 时保守绕行是无负反馈的中性吸子）。
- P5 **安全 = 稠密（近障/CBF）负 + 事件负（碰撞）+ 训练中滤波**，比例在去掉基座后重标定（论文用×100 是因为 base 小；我们删基座后相对强度会变，需换算，见 §4 结论 / 顶部单命定案）。

---

## 🗑️ 3. 方案 NR-1 / navgoal（已废弃·归档 2026-09-07）

> 结论：**from-scratch 死锁 + warm 无增益 → 废弃。删 passive 正基座的方向是对的，但「纯运动差分(悬停=0)」缺远端稠密引导而学不动；F1 用无核飞行主导同时给稠密 + 无悬停平台（§F1）。所需 stat `first_arrival_step`/`mean_action_diff` 已在 f1 分支实现。**

---

## 🗑️ 4. NR-1 数值预算（已废弃·归档 2026-09-07）

> 结论：**预算逻辑（直达 ≫ 悬停 −40）与 F1 一致；单命 6×6×3 的最新预算见顶部「2026-09-07 环境适配定案」节。保留一条通用原则：删基座后所有旧权重须按比例换算并小网格重扫，以「安全直达 > 贴障 > 绕远 > 悬停」为平衡校验。**

---

## 5. 训练 / 评估 / 验收协议

### 5.1 训练（必须 from-scratch，不能 warm 旧 ckpt）

- **原因**：新 reward 改变整个 value landscape；旧 ckpt（学成悬停刷分 + 在 ~600 基座上标的 value）只会污染新训练（保留旧 bias，M2「熵塌缩后勿盲加帧」教训的推广）。
- **协议（定案：from-scratch 低密度探针 → 升密度，用户 2026-09-06 确认）**：
  1. **收敛探针**：from-scratch 锁低密度（`levels=[0,2,4]`, `initial_level=1`，2 障）5–10M——验证 NR-1 下能学到 hover/到达（M1 无障 arrival 99% 证明此起点可达；新 reward 需复验），盯 `time_to_arrive` 是否下探、有无悬停平台。
  2. **主训**：同 ckpt/同配方升密度或开自动课程（`levels=[0,2,4,8,16]` 锁目标档或课程），hybrid/dual，20–40M。
  3. **早停纪律（沿用 M3 教训）**：reward-core 是早峰型；`save_interval=100`（≈3.3M ckpt 粒度），**每个 mid-ckpt 都跑确定性 eval**，取峰部署，勿盲加帧。
  4. 熵：`algo.entropy_coef=0.02`（M2 恢复探索实证值），盯 TanhNormal 差分熵（<0 即近确定性，勿在 final 上加帧）。
  5. 5.3 的对照与论文对齐表按同一配方口径填格（公平对比须各臂同 reward 参数）。

### 5.2 评估

- 确定性 eval：`eval_ckpt.py ... +rollout_steps=600` @1024 env，D2-16 同布局参数。
- **部署口径**：每个候选 ckpt 都要跑 `+runtime_filter=true` **与** `+runtime_filter=false`（internalize 验收）±`+perturb=cmd_gauss 0.3`（鲁棒）。
- **新指标**：`avg_time_to_arrive`（首达步均值）、`timeout_rate`、`mean_action_diff`、collision、arrival、joint。报告（arr / coll / joint / **T_arr** / action_diff）五元组。

### 5.3 验收（对应用户 4 目标）

| 目标 | 指标 | 验收线 |
|---|---|---|
| 到达终点 | arrival / joint | 带 filter ON：arrival ≥0.75、joint ≥0.75（对齐 M2 最佳 0.79 档） |
| 时间短 | avg_time_to_arrive / timeout_rate | **T_arr 显著短于旧配方**（旧悬停吸子恒 ~600 步；NR-1 目标直线 ~170 步、绕行 <400），timeout_rate 下降 |
| 动作平滑 | mean_action_diff + 轨迹 | action_diff 窗口均值显著低于旧（无抖振），无高频振荡 |
| 安全低碰撞 | collision（ON/OFF） | ON coll ≤2%；**OFF coll 显著低于 M2 OFF 基线 36–41%**（dual 方向，论文 Dual w/o rt.f 92.7% success） |
| 结构健康 | cbf_violation、entropy、return 分布 | 无「悬停平台 return」；viol 随训降但不以 arrival 塌为代价（M3 v2 教训） |

---

## 6. 实现映射（先不改代码；落地顺序建议）

> 目的：**保留 legacy 逐位不变**，新增一套分支/键让 NR-1 与旧 reward 并存、可一键切换，不动任何既有 run/ckpt/基线（延续 M2/M3 的「新键默认不碰旧行为」惯例）。

| # | 改动点 | 文件 | 说明 |
|---|---|---|---|
| 1 | 新增 `reward_scheme: legacy\|navgoal`（默认 `legacy`） | `nav_vel.py` cfg 解析 | NR-1 全量逻辑放 `navgoal` 分支，`legacy` 与现在逐位一致 |
| 2 | `navgoal` 分支重写 `_compute_reward_and_done` 主项 | `nav_vel.py` | 删 pose/up/spin/effort(正)，加 ①②④⑦；⑥⑨逻辑复用 |
| 3 | ② 动作平滑 = action-diff 负项 | `nav_vel.py` | `-w_s·‖a_t−a_{t-1}‖²`（速度指令层；`prev_actions`/`policy_actions` 已缓存）；保留旧 `exp(-Δthrottle)` 定义到 legacy |
| 4 | ④ 首达步 + time-scaled bonus（**定案必做**） | `nav_vel.py` | arrival 触发处用 `progress_buf` 记 `first_arrival_step`，bonus=$w_{arr}+w_t(1-\tfrac{t_{arr}}{T})$ |
| 5 | `pbrs_gamma=1.0`（纯差分） | CLI / yaml 新默认 | 悬停红利=0 |
| 6 | 新增 stat：`first_arrival_step`、`mean_action_diff` | `nav_vel.py`/`EpisodeStats` | 上报 wandb，验收用 |
| 7 | `success_terminate=true` | — | **定案：不采用（保持 false）**——多命/课程统计口径不变，时间短由 ④⑤ 表达；仅记录为将来可选项 |
| 8 | yaml 文档同步 + `cbf_test.py` CPU 回归 + GPU 冒烟 | `NavVel.yaml`/`cbf_test.py` | 照 M2/M3 惯例 |

> ⚠️ 纯 CLI 可先验证的部分：`reward_pbrs_weight=8 + pbrs_gamma=1.0 + arrive_bonus=30 + reward_timeout_penalty=40 + edge4 + near1 + effort 0 + CBF dual w1=w2=0.1` **几乎全部现有键**——但**删 pose/up/spin 正基座与改平滑为 action-diff 负项必须改代码**（旧代码里没有「关闭 pose」的开关）。所以 NR-1 的落地本质是一次集中小改动（#1–#6），改动后即全 CLI 可扫。

---

## 7. 风险、备选与决策点（★=已定案；其余为落地后按数据再调）

| 决策点 | 决定（★=已定案 2026-09-06；其余落地后按数据再调） | 备选 / 可调 |
|---|---|---|
| 训练起点 ★ | **from-scratch + 低密度收敛探针（2 障 5–10M）→ 升密度**（用户已定） | 不 warm 旧 reward ckpt |
| progress 权重 ① | $w_p=8,\ \gamma=1.0$，先扫 $\{4,8,12\}$ | 若 arrival 学不动 → 临时回 $\gamma{=}0.995$ 加一点悬停红利帮起步，再切 1.0 |
| 到达结算 ④ ★ | **time-scaled**：30 + 30·(1−t_arr/T)（越快越多；加 `first_arrival_step` stat） | 若 time bonus 难学 → 临时 flat 30 观察 |
| 超时 ⑤ | 40（60 也可，S3/W2 实证区间） | 若悬停仍出现 → 提到 60；若碰撞环境学不到 → 降到 20 观察 |
| 平滑 ② ★ | **速度指令层 action-diff 负项** $w_s=1.0$（用户已定） | $w_s$ 按抖振/action_diff 数据调 |
| 能耗 ③ ★ | **全删（0）**（用户已定） | 将来若需能耗效率再以 $-w\,e_t$ 负项加入（勿用正） |
| 到达后行为 ★ | **保持 `success_terminate=false`**（用户已定） | 将来若要硬「最短时间」再切 true（需同步课程统计口径） |
| CBF ⑦ | dual w1=w2=0.1 起 → 网格 | 若 OFF internalize 不够：w1 加大（M3 实证 w1 主 internalize）；若太保守：w1 减、w2 保 |
| 与 DR 关系 | NR-1 先无 DR 收敛，再叠 M3-B DR（论文 Table I） | DR 早加可更 robust（若预算允许直接 from-scratch+DR） |
| 与现跑批次 | **等待/让路现有 M3-B DR 批次跑完**再执行（同 GPU/仓库多会话勿撞车，仓库教训） | — |

---

## 8. 与 m3_plan 的关系 & 下一步

- **定位**：m3_plan 的 M3-A/B 是在**保留 Hover 基座**前提下修外围（dual/ab/to/w/DR），数据证明到顶（W4≈V3、S 饱和、OFF coll 18.6% 为极限）；**本文档 = 根治性重设计**，属 M3 之后的独立主线（可命名 **M4 / NR-1**）。
- **保留的资产**：CBF 滤波器（`cbf.py` 与论文 QP(18–20) 等价，不动）、障碍几何/obs/soft_respawn/课程基建、eval_ckpt 的 `runtime_filter`/`perturb` 基建、mid-ckpt 早停纪律。
- **✅ 执行状态（2026-09-07 时间点）**：上述「下一步」已按 §F1 全部落地并通关——**F1 `reward_scheme: f1` 是现行最终 reward 配方**（w_f=6.0/w_s=0.2/ent0.05/arrive 30+30t/to40/edge4/near1/CBF hybrid dual 0.1σ0.5/curriculum[2,4,8,16]），D2-16 课程 12M from-scratch 通关（pg6q5ji5），带 filter ON joint 0.930 / coll 0.9%（≫ legacy 0.743）。**internalize（OFF 撤 filter）reward-shaping 全组失败** → 非 reward 可解，转 obs 结构级改造（**New2**：CBF 边界余量 h / min_clearance 入 obs，见 `drones/new2_plan.md`）。
- **下一步行动清单（New2，待用户拍板后执行）**：
  1. 改代码：nav_vel.py obs spec 追加 1–2 维安全余量通道（CBF 边界余量 `h=min(‖p−p_oi‖−r_i^cbf)` / min_clearance，归一化到 danger_radius/CBF 半径），默认关、逐位兼容；`cbf_test.py` CPU 回归 + GPU 冒烟。
  2. from-scratch 低密度收敛探针（验证新 obs 可学 + h 信号有信息量）。
  3. 课程 2-4-8-16 主训 + §5 确定性 eval（filter ON/OFF × perturb）+ 看 OFF internalize 是否首次出现。
  4. 回填本文档「执行记录」+ new1_plan.md / new2_plan.md。

---

### 附录 A：引用位置
- 论文：CBF-RL md L211–223（Eq.22+23 组合 r_cbf）、L226–233（Alg.1）、Table II（single-integrator reward terms）、L248–257（Table I/III 消融与部署口径）、L250（DR 注）。
- m3_plan.md：M3-A/B 全部；尤其「改进 v4 §1 逐项预算 / §2 失衡结论 / §3 数值重设计」（Hover 基座 ~600、悬停 +120–300/窗、任务项 <15%、to 40–60 抗退化、w16 抬早峰、W4≈V3 饱和）。
- navvel_rl_interface.md §3（legacy reward 口径）；nav_vel.py `_compute_reward_and_done`（当前实现）。
