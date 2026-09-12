# NavVel RL 接口设计说明（观测 / 动作 / 奖励）

> 更新：2026-09-05（对照 HEAD `e2b08bd` + M2 naive 落地 `aed2b1b` 后的当前实现）。
> ⚠️ **2026-09-07 时间点注记**：本文档口径截至 **M2/M3-era**（obs 62 维、CBF reward core nominal/correction/gaussian/dual）。此后 **New1 阶段（2026-09-06）新增 `reward_scheme: f1`**（见 `drones/new_reward.md` §F1 + `new1_plan.md`），并完成 F1 D2-16 课程通关（pg6q5ji5@12M，ON joint 0.930 / coll 0.9%）。**下一步 New2（见 `drones/new2_plan.md`）将给 obs 追加 1–2 维安全余量通道（CBF 边界余量 h / min_clearance，62→63/64）**——本文 §1 obs 表届时需同步更新；其余（动作层/CBF filter 装配/奖励项）仍适用。
> 适用范围：`cfg/task/NavVel.yaml` + `omni_drones/envs/single/nav_vel.py` + `nav_vel_obstacles.py` + 控制链 `VelController`(transforms) + Crazyflie(Lee 内环)。
> 本文回答：**策略输入是什么、输出被解释成什么、奖励每一步怎么算**——是 M2-3 CBF 接入与后续感知化的接口基线。
> 与其它文档关系：障碍机制公式见 `navvel_obstacle_migration_guide.md`；训练/实验决策见 `m2_plan.md`；reward 方案史见 `new_reward.md`；New1/New2 执行见 `new1_plan.md`/`new2_plan.md`。

---

## 0. 总览（控制链分层）

```
PPO 策略 (MLP, TanhNormal)
  a ∈ R^4  (Unbounded, 62 维 obs)          ← 观测/动作层（本文）
  │
  ▼
VelController (torchrl Transform, "velocity" 动作层)
  a → [vx,vy,vz | yaw] 拆分 → max_vel 1.8 方向保持限幅 + yaw ±1.5 rad 限幅
  │
  ▼
Lee 内环 controller (增益已修 lee_controller_crazyflie.yaml)
  → 4 转子归一化油门指令 → 物理(Isaac, 100Hz, dt=0.01)
```

- 任务（M1→M2）：Crazyflie 在 `bound_xy=5`、`z∈[0.15,4.5]` 的方形空间随机起降航点（`target_pos_range`），随机朝向目标；M2 叠加 **K=8 固定槽位、0/2/4/8 档课程**的静态球障碍，需绕障到达。
- 关键点：**策略输出的是"期望速度 + 期望偏航"的连续指令**（不是转子油门、不是姿态率），低层 Lee 已能较好跟踪（M1 实测 +X 1.2 m/s → vx≈1.03）。这也是 CBF 滤波作用于**速度指令**才有意义的原因（§6）。

---

## 1. 观测空间（62 维连续，单 agent，无堆叠帧）

> 拼装位置：`nav_vel.py::_compute_state_and_obs`（前 30 维与 M1 无障版**逐位一致**，障碍块追加在后，故旧 ckpt 因维度变化不可续属预期）。

| # | 维度 | 内容 | 归一化/范围 | 说明 |
|---|---|---|---|---|
| 1–3 | 3 | `rpos = target − pos`（env 系目标相对位置） | 无界（≈±3–4） | 平移不变 |
| 4–7 | 4 | 机体姿态四元数 `rot`（`drone_state[3:7]`） | 单位四元数 | 与位置解耦（rpos 已含平移） |
| 8–13 | 6 | body 系速度 `vel_b`：线速度3 + 角速度3（`[7:13]`） | m/s、rad/s | body 帧，旋转不变输入 |
| 14–16 | 3 | 机头向量 `heading = quat_axis(rot, x)`（`[13:16]`） | 单位向量 | 世界系，用于朝向误差 |
| 17–19 | 3 | 机体上向量 `up = quat_axis(rot, z)`（`[16:19]`） | 单位向量 | 世界系，用于姿态正向/坠机检测 |
| 20–23 | 4 | 归一化油门 `throttle*2 − 1`（`[19:23]`） | ≈[−1,1] | 4 电机当前指令 |
| 24–26 | 3 | `rheading = target_heading − heading`（朝向误差） | 两个单位向量之差（≈±2） | 目标朝向=目标姿态 x 轴世界向量 |
| 27–30 | 4 | time encoding：`progress/max_episode_length` 广播 4 份 | [0,1] | 时间信息（可变 horizon 提示） |
| 31–62 | 32 | **障碍块** K=8 槽 ×4：`[(p_oi − drone)/5 ∈[−1,1]]_3 + [r_oi/0.5 ∈[0,1]]_1` | 见列 | 槽位归一化；未激活槽恒 0（mask） |

- **不变性**：位置段用相对量（rpos），速度/姿态为 body/单位向量 → 观测对世界系平移近似不变（无障碍时）。
- **M2 障碍块细节**（`nav_vel_obstacles.py::build_obs`）：
  - 用**几何判定半径 $r_{s,i}=r_{drone}+r_{o,i}+r_{infl}$ 对应的球心距向量**喂给策略（槽内是**原始逻辑半径 $r_{o,i}$**，不喂 CBF 半径——刻意不把"安全滤波器内部参数"暴露给策略，防过拟合）。
  - 距离分量 `/5`、半径 `/0.5` 截断归一化；**激活掩码从 `radius>0` 单一来源**（与 CBF/奖励/碰撞共用 `ObstacleManager.active`，避免口径不一致）。
- **感知化预留**：本模块只在 `build_obs` 处用真值（球心+半径）。将来换雷达/相机估计时**只需替换这一处**（文件头注释声明），obs 槽结构不变。
- `intrinsics`（mass/inertia/KF/KM/…，进入 obs spec 的 `agents.intrinsics`）供 domain randomization 用，默认未开。

---

## 2. 动作空间（4 维连续，无界 → 速度/偏航指令）

> `cfg.task.action_transform: velocity`；装配点：train/play/eval_ckpt 在策略输出后套 `VelController`（`transforms.py::VelController`，`vel_limit` 段）。

| 分量 | 含义 | 参考系 | 限幅 |
|---|---|---|---|
| a[0..2] | 期望线速度 `[vx,vy,vz]` (m/s) | **env/世界系**（实测给 +X 得 vx≈+1.0） | `max_vel=1.8`：**方向保持**的模长截断（只缩不翻），非 tanh squash |
| a[3] | 期望偏航角 `yaw`（rad） | 世界 yaw | `max_yaw_rate=1.5 rad/s` → 实际 clamp `a[3]·π ∈ ±1.5` |

处理链：
1. `action.split([3,1], −1)` → target_vel(3) + target_yaw(1)；
2. 限幅后调 Lee `controller.compute(drone_state[:13], target_vel, target_yaw·π)` → 输出 4 转子归一化油门（`torch.nan_to_num` 兜底）；
3. 无 tanh / 无边界 —— 分布用 TanhNormal（熵可为负即确定性信号，曾用此诊断熵塌缩）。

- 与原生 `drone.action_spec`（4 转子，Bounded[−1,1]）不同：`VelController.transform_input_spec` 会把 `full_action_spec` 覆盖成 `(…,4)` 的 Unbounded **速度指令** spec，PPO 直接在上面输出。
- `prev_action` 由控制链维护（reset 时初始化为 hover 油门），`policy_action` 仅 PIDRate 层会写（本文档不展开）。
- **M2-3 CBF 挂接点（预留）**：在 `a` 进入 VelController **之前**插入一阶 CBF 投影 `v* = proj_CBF(v_nom)`（§6）。

---

## 3. 奖励函数

> 实现：`nav_vel.py::_compute_reward_and_done`（每步标量 reward，1 agent）。**默认值 = M2-0 bake-in 的 M1 fixctl-B 配方 + M2 §4.3 soft-respawn 兼容量级**。

### 3.1 导航 / 姿态项（基础，M1 无障即有，逐元素相加）

令
$$\small d_{pos}=\lVert p_{goal}-p\rVert,\qquad \boldsymbol{rhead}=\text{target\_heading}-heading,\qquad \boldsymbol{d}=\begin{bmatrix}\boldsymbol{rpos}\\ \boldsymbol{rhead}\end{bmatrix},\quad \rho=\lVert \boldsymbol d\rVert$$

| 项 | 公式 | 默认值 | 量级/作用 |
|---|---|---|---|
| 位姿势场 | $r_{pose}=\dfrac{1}{1+(w_{dist}\,\rho)^2}$，$w_{dist}=1.6$ | 恒开 | 主导航信号，目标近→大；位置+朝向联合压 |
| 姿态正向 | $r_{up}=\big(\tfrac{up_z+1}{2}\big)^2$ | 恒开 | 奖励乘数：$\;r_{pose}\cdot(r_{up}+r_{spin})$ |
| 抑自旋 | $r_{spin}=\dfrac{1}{1+\omega_{z,b}^2}$ | 恒开 | 同上，压 body 自旋 |
| 节能 | $r_{effort}=w_{eff}\,\exp(-e)$，$w_{eff}=0.1$ | 0.1 | 温和鼓励低油门 |
| 平滑 | $r_{smooth}=w\cdot\exp(-\Delta u_{throttle})$ | **0.0（关）** | 未用 |
| 到达奖励 | $r_{arr}=10\cdot\mathbb 1[\text{进圈并保持 }50\text{ 步}]$ | 10.0 | 一次性大奖励；`success_terminate=false` 到达后继续学保持 |
| 目标进度 PBRS | $r_{pbrs}=w_{pbrs}\big(d_{t-1}-\gamma d_t\big)$，$w_{pbrs}=2.0,\gamma=0.995$ | 2.0/0.995 | 稠密化；重生/换命时 rebase 基线，避免"传送=进度"假信号 |

$$\boxed{\,r_{nav}=r_{pose}+r_{pose}(r_{up}+r_{spin})+r_{eff}+r_{smooth}+r_{arr}+r_{pbrs}\,}$$

### 3.2 生存项（防自由落体/贴地，M1）

$$r_{surv}=-w_{surv}\max(0,\;z_{ref}-z),\qquad w_{surv}=0.1,\ z_{ref}=1.0\ \text{m}$$

只在掉到 1 m 以下才咬（z 是 env 系高度），**轻微、渐进**（不一次性惩罚，兼容多命软重置）。

### 3.3 障碍项（M2，仅当该环境有激活障碍时计算）

对激活槽定义净空 $d_i=\lVert p-p_{o,i}\rVert-r_{s,i}$，$d_{\min}=\min_i d_i$；几何判定半径 $r_{s,i}=r_{drone}+r_{o,i}+r_{infl}$（0.15+$r_o$+0.05）。

| 项 | 公式 | 默认权重 | 作用/设计说明 |
|---|---|---|---|
| 危险区对数惩罚 | $-\lambda_{log}\, w_{log}\sum_i \phi_i$：$0<d_i\le D$ 时 $\phi_i=\ln(d_i/D)$；$d_i\le0$ 时 $\phi_i=\ln(10^{-3}/D)+100\,d_i$；$D=0.6$ | $w_{log}=1.5$，$\lambda_{log}=0.3$ | 危险区(0,0.6m]内随接近**对数**加深；侵入球内线性 +100d 强惩罚。**每步 O(1)**（防 kaiwu −2500 量级炸 return） |
| 碰撞边沿一次性 | $-w_{edge}\,\mathbb 1[\text{新进入接触}]$（`new_edge`，离开再进才再罚） | 2.0 | 只罚"进入事件"，不累计滞留步 |
| 近障减速 | $-w_{slow}\,v_{\parallel}\,\max(0,1-d_{\min}/D)$，$v_{\parallel}=\max(0,(\boldsymbol v\cdot \boldsymbol u))$，$\boldsymbol u$=指向最近球心单位向量 | 0.5 | **只罚"朝最近障碍飞"**（relu 投影），在危险区线性加重；奖励拆解安全行为 |
| 早死放大（可选） | 见 §3.4 | **0.0（关）** | 默认关 |

> 观测/碰撞/奖励用**同一几何半径** $r_s$；CBF 的含裕量安全半径（M2-3）**与此分离**，勿混（§6）。

### 3.4 一次性死亡惩罚组（默认全 0 —— 与软重置冲突，M2-0 bake-in）

| 键 | 默认 | 含义 |
|---|---|---|
| `reward_crash_penalty` | 0.0 | 坠地(z<0.15 或 NaN) 一次性罚 |
| `reward_oob_penalty` | 0.0 | 超界(‖xy‖>5 或 z>4.5) 一次性罚 |
| `reward_timeout_penalty` | 0.0 | 600 步内从未到达一次性罚 |
| `reward_early_death_weight` | 0.0 | 开局即死放大（task 顶层） |
| `obstacle.reward_early_death_weight` | 0.0 | **碰撞早死放大**：当一条命内碰撞边沿累计达 `max_collisions=2` 触发软重生（`collide_exceed`）时，对触发的那次新边沿罚 $w\cdot \text{clamp}(T_{ed}/\text{life\_steps},1,10)$，$T_{ed}=300$（越早撞满 2 次罚越重） |

M1 教训：一次性死亡惩罚在 600 步多次软重生时会堆积成 return≈−110、淹没导航信号 → **bake-in 全 0**；要用时 CLI 开（注明与软重置的权衡）。

### 3.5 终止 / 软重生 / 课程口径（reward 之外的状态机）

- **窗口**：`max_episode_length=600` 步（100Hz → 6 s），truncated 即真终止外的统计边界。
- **软重生 soft_respawn=true**：`crash | oob | collide_exceed` → `_respawn`：**保目标、保障碍布局**，换随机起点（对障碍做 ≤12 次拒绝采样避免"生在球里"），rebase PBRS 基线，`life_steps`/命内碰撞清零；episode 续到 600（"多命"）。
- **课程结算**（`_reset_idx` 在清窗口前消费结局）：`success = 本窗口到达过 且 全窗口 0 碰撞边沿`；`collide = 全窗口 ≥1 边沿`；滚动 `gate_window_episodes=3000`，`success≥0.80 AND collide≤0.05 AND ≥2M 帧` 才升档 0→2→4→8（`collision_rate_threshold` 曾 CLI 放宽 0.10 试验），`allow_demote=false`。

---

### 3.6 CBF-RL 论文奖励设计对照（Table II）与调参启示

> 论文：*CBF-RL: Control Barrier Functions for Reinforcement Learning*（single-integrator navigation 实验）Table II。与我们当前实现逐项对照（图版文字在此展开）：

| 论文项 | 论文公式（Table II） | 我们对应项 / 是否采用 | 对照结论 |
|---|---|---|---|
| $r_{goal}$ | $1.0\cdot\mathbb 1[\text{goal reached}]$ | $r_{arr}=10\cdot\mathbb 1[\text{进圈并保持}]$（§3.1） | 同构；我们因 soft-respawn 多命 + 每步尺度放大到 10 |
| $r_{obstacle}$/ $r_{wall}$ | $-1.0\cdot\mathbb 1[\text{collision}]$ | 碰撞边沿 $-w_{edge}\mathbb 1[\text{新接触}]$ + 危险区对数稠密罚（§3.3） | 论文仅“一次性碰撞事件”；我们额外加“接近过程”稠密罚以撑住 D2-16 高密度（每步 O(1)，防 kaiwu −2500 量级炸 return）|
| $r_{progress}$ | $20.0\cdot\dfrac{\|\mathbf p_{t-1}-\mathbf g\|-\|\mathbf p_t-\mathbf g\|}{v_{max}\Delta t}\mathbb 1[\text{active}]$ | $r_{pbrs}=w(d_{t-1}-\gamma d_t)$（$\gamma=0.995$；默认 $w=2.0$，D2 实测 $w=8$ 达峰，§3.7） | **同构差分 shaping**；论文除以 $v_{max}\Delta t$ 做了速度归一（“全速朝目标”每步固定 $+20$，可解释、可校准相对尺度）。我们未归一，靠 $w$ 直接放大 |
| $r_{alive}$ | $0.01\cdot\mathbb 1[\text{active}]$ | 无正向 alive（仅 $r_{surv}$ 低空轻罚 + soft-respawn 多命） | 论文 hard-episode 设定；与我们多命软重置冲突，不采用 |
| $r_{cbf}$ | $100\cdot\big(\min(\nabla h^\top \mathbf v+\alpha h,0)+\big[e^{-\|\mathbf v_{policy}-\mathbf v_{safe}\|^2/0.5^2}-1\big]\big)\mathbb 1[\text{active}]$ | reward core 两项（§3.7）：(i) $\sum_i\min(0,g_i)$ = nominal；(ii) correction $=-\lambda\|\mathbf v_{safe}-\mathbf v_{nom}\|$ | **第一项与我们 nominal 逐位同构；第二项正是我们 `penalty_src=correction` 的平滑高斯版**（见下启示①）|
| $r_{timeout}$ | $-10.0\cdot\mathbb 1[\text{time exceeded}]$ | `reward_timeout_penalty` 默认 0 | soft-respawn 兼容，不照搬 |

**参考价值小结（是否可指导调参）**：

1. **① correction 方向获论文背书，且论文给了更优的惩罚形状**。论文 $r_{cbf}$ 第二项 $e^{-\|\mathbf v_p-\mathbf v_s\|^2/0.5^2}-1\in[-1,0)$：纠偏为 0 时不罚、$\sigma=0.5\,\text{m/s}$（≈0.28 $v_{max}$）以内几乎无感、大纠偏**饱和到 −1**。对比我们当前线性 correction $=-\lambda\|\mathbf v_{safe}-\mathbf v_{nom}\|$（大纠偏线性放大、不饱和）。→ 已于 2026-09-06 落地：① `penalty_src=gaussian`（论文式高斯核惩罚，commit `afc6fa2`，§3.7）；② M3-A `penalty_src=dual`（论文 Eq.22+23 两项相加完整形式，commit `d2c33ec`，§3.7）——均只动 CBF 项，无需全臂重训，仅 hybrid 臂。
2. **② 权重量级不能照抄**。论文 $r_{cbf}$ 权重 ×100 仍能训好，因 single-integrator、每步 $r_{progress}$ 最高 +20、硬 episode；我们是四旋翼（内环动力学滞后→需滤波兜底）+ D2-16 高频触发，实测 **CBF 权重一大（$\lambda\ge0.2$）就保守塌陷**（arrival 卡 0.44–0.49 加长救不回），$\lambda 0.05\!-\!0.1$ + 滤波兜底最优 → 我们“小 λ 微调”哲学成立，论文的 ×100 只可作形状参考不可作数值。
3. **③ $r_{progress}$ 归一化思路可借**：除以 $v_{max}\Delta t$ 后 shaping 与罚面尺度可比、权重可解释（$w$=“全速朝目标每步增益”）。我们 D2 实测 $w$ 2→8 显著提升（§3.7）印证“shaping 要够强才压得过罚面”；若想精确复刻论文相对比例可做归一化版（**动共享奖励 → 需全臂重训**，放后续）。
4. **④ $r_{alive}$/硬超时不采用**：与 soft-respawn 多命设定冲突（M1 已证一次性死亡罚在 600 步多命下 return≈−110 淹没导航信号）。

---

### 3.7 我们的 CBF 奖励核心（当前实现 + D2-16 标定）

> 实现：`nav_vel.py::_compute_reward_and_done` reward core + `utils/cbf.py`（`cbf_violation`/`filter_velocity`）；装配见 `cfg/task/NavVel.yaml` 的 `cbf:` 段。mode ∈ `none|filter_only|reward_only|hybrid`（§6）。滤波作用在策略输出 $\mathbf v_{nom}$ 进 VelController 之前；reward core **用滤波前 $\mathbf v_{nom}$** 计算，策略才学得到“被罚的是自己输出”（CBF-RL soft-CBF）。

**CBF 安全半径**（只进滤波/奖励 core，**不进 obs**）：
$$r^{cbf}_{s,i} = r_{s,i} + r_{margin} + \mathbb 1[\text{use\_brake}]
\tfrac{v_{max}^2}{2a_{max}},\qquad r_{s,i} = r_{drone}+r_{o,i}+r_{infl}$$

每激活槽位令 $h_i=\|\mathbf p-\mathbf p_{o,i}\|-r^{cbf}_{s,i}$，$g_i = \mathbf n_i^{\!\top}\mathbf v_{nom}+\alpha h_i$（$\alpha=1.0$ 默认）。

| `penalty_src` | reward core 公式 | 语义 |
|---|---|---|
| `nominal`（默认，逐位兼容旧行为） | $\text{viol}=\sum_{i\in\text{act}}\min(0,g_i)+\mathbb 1[\text{penalty\_intrude}]\sum_{i\in\text{act}}\min(0,h_i)\le 0$；$r\mathrel{+}= \lambda\cdot\text{viol}$ | 罚“原始指令 $\mathbf v_{nom}$ 的 CBF 违反”（soft-CBF 原版）|
| `correction`（仅 filter/hybrid 有意义） | 在 reward core 复跑 `filter_velocity` 得 $\mathbf v_{safe}$；$\text{corr}=\|\mathbf v_{safe}-\mathbf v_{nom}\|\ge0$；$r\mathrel{-}= \lambda\cdot\text{corr}$ | 罚“滤波器实际纠偏量”：滤波没拦就不罚，拦得越多罚越多 → 逼策略学“安全近穿”而非“远离罚区”保守绕行 |
| `gaussian`（仅 filter/hybrid 有意义） | $\text{corr}=\|\mathbf v_{safe}-\mathbf v_{nom}\|\ge0$；$r\mathrel{-}= \lambda(1-e^{-\text{corr}^2/\sigma^2})\in[0,\lambda)$ | correction 的**论文式平滑高斯核**（CBF-RL Table II $r_{cbf}$ 第二项）：0 纠偏不罚、小纠偏几乎无感、大纠偏饱和到 $\lambda$ → 治强 shaping 下线性 correction"罚大拽回 hybrid"。$\sigma=$ `correction_sigma`（默认 0.5≈0.28·$v_{max}$）。commit `afc6fa2` |
| `dual`（仅 filter/hybrid 有意义；M3-A） | $r\mathrel{+}=\underbrace{w_1\cdot\text{viol}(\mathbf v_{nom})}_{\text{nominal viol}}+\underbrace{w_2\cdot\big(1-e^{-\text{corr}^2/\sigma^2}\big)}_{\text{gaussian corr}}$；$w_1=$ `reward_weight`，$w_2=$ `correction_weight` | **论文 $r_{cbf}$ 两项相加完整形式**（Eq.22+23，commit `d2c33ec`）：nominal viol 的"持续到安全"信号 + gaussian 的"贴近安全动作"平滑信号同时存在 → 训练中滤波让策略 **internalize 安全**（部署无 rt.filter 也安全：论文 Dual 92.7% vs Filter-only 38.7%，Table I）。仅 filter/hybrid 有真实纠偏；`reward_only` 无滤波自动退化为仅 $w_1\cdot\text{viol}$ |

> 实现注：correction/gaussian/dual 的纠偏项都在 `nav_vel.py` reward core 内用同一 `filter_velocity` **复算**（不新增 info key/spec，`CBFVelocityFilter` 不变）；`reward_only`（无滤波）correction/gaussian 自动回退 nominal、dual 自动退化为仅 $w_1\cdot\text{viol}$。commit `deb97b7`（correction）、`afc6fa2`（gaussian）、`d2c33ec`（dual）。

**默认键**：`mode: none`（基线）/ `reward_weight: 0.5` / `penalty_src: nominal` / `penalty_intrude: true` / `alpha: 1.0` / `use_brake_term: true` / `filter_grad: detach` / `filter_iterations: 3` / `correction_sigma: 0.5` / `correction_weight: 0.0`（仅 dual 用）。D2 配方另见 §5。

**D2-16 实测标定（确定性 eval @600 / 1024 env，warm `lmhvaqka`-final，关 brake、ent0.02；arrival/coll%/joint）**：

| 配方 | 帧数 | 结果 | 结论 |
|---|---|---|---|
| nominal λ0.05 | 40M | 0.647 / 2.3 / 0.634 | w=2.0 时 reward core 最优（首次超 filter_only 39M）|
| **correction λ0.05** | **20M** | **0.682 / 2.1 / 0.669** | 罚纠偏量消除保守偏置；**甜点 ~20M**（加长 40M 退化 0.521）|
| correction λ0.05 + **shaping w=8** | 20M | 0.766 / 1.1 / 0.757 | 强前向 shaping 再推高（$w$:2→8 单变量 +8.8pt）|
| **filter_only + w=8（无 reward core）** | 20M | **0.806 / 2.2 / 0.789** | **w8 全臂公平重训下 filter_only 反超 hybrid**（见下）|
| naive / reward_only（无滤波）+ w8 | 20M | arrival 0.72–0.74 / **coll 43–49%** / joint ≤0.50 | shaping 把到达率拉高但无滤波兜底 → 全程擦撞，不可用 |

**臂序随 shaping 强度反转（重要机制结论）**：w=2.0 时 correction 让 hybrid(0.669) > filter_only(0.627)；**w=8 时 filter_only(0.789) > hybrid corr(0.708–0.720，即便取最优复现 run 0.757 仍落后)**。机制：强前向 shaping 驱动策略猛冲 → 滤波频繁纠偏 → correction 罚（=纠偏量）变大 → 拽回 hybrid；filter_only 无 reward-core 罚项，shaping 无阻力地生效 → “纯滤波 + 强 shaping”组合最大化。→ 若想 hybrid 在强 shaping 下借 reward-core 仍领先，**候选迭代 = 论文式高斯平滑 correction（§3.6 启示①）减轻“大纠偏过罚”**。

---

## 4. 关键常量速查（默认，均在 `NavVel.yaml`）

| 类 | 键 | 值 |
|---|---|---|
| 空间/任务 | `bound_xy`/`z_min`/`z_max` | 5.0 / 0.15 / 4.5 |
| 起点/目标 | `init_pos_range`/`target_pos_range` | 方形 ±3 × z 见文件；`min_init_target_dist=1.5` |
| 到达 | `arrive_radius`/`arrive_hold_steps`/`arrive_bonus` | 0.5 m / 50 步 / 10.0 |
| 障碍几何 | `max_slots`/`radius_choices`/`drone_radius`/`inflation`/`collision_margin`/`danger_radius` | 8 / [0.2,0.3,0.4] / 0.15 / 0.05 / 0.05 / 0.6 |
| 可达性 | `init_clearance`/`goal_clearance`/`min_gap_between` | 0.15 / 0.35 / 0.25 |
| 速度层 | `vel_limit.max_vel`/`max_yaw_rate` | 1.8 m/s / 1.5 rad/s |
| CBF reward core（§3.7） | `cbf.mode`/`reward_weight`/`penalty_src`/`penalty_intrude`/`alpha`/`use_brake_term`/`filter_iterations`/`filter_grad`/`correction_sigma`/`correction_weight` | none（基线）/ 0.5 / nominal / true / 1.0 / true / 3 / detach / 0.5 / 0.0（D2 配方：mode 按臂、λ0.05、`penalty_src`=correction/gaussian/dual(hybrid)、关 brake、`reward_pbrs_weight=8`；M3-A dual 用 `reward_weight`=w1 与 `correction_weight`=w2） |
| 课程 | `levels`/`gate_window_episodes`/`success_rate_threshold`/`collision_rate_threshold`/`min_frames_between_promote` | [0,2,4,8] / 3000 / 0.80 / 0.05 / 2M |

---

## 5. 实验标定结论（为什么是这些默认，2026-09-04~05 实测）

- **导航奖励（M1 fixctl-B，run `9eb3e923`）**：软重置 + survival 0.1 + PBRS 2.0/γ0.995 + 死亡惩罚全 0 + vel 1.8 → 无障 arrival 99%。
- **障碍项量级（M2）**：必须"每步/每次事件 O(1)"——数值照抄 kaiwu（−2500 量级）会淹没导航信号。edge=2.0、near_slow=0.5 起步；`edge 2→4`(L4 coll 8.5→6.6%)、`+early_death 0.3`(反效果 7.6%)、`edge→6/near→2`(过度保守，arrival 0.97→0.93) 均已系统性试过——**L4 碰撞 ~6.6%、8 障 ~15-16% 是 naive 的奖励权衡+密度固有上限，改奖励/加帧(20M→220M)均无法突破**（详细见 `m2_plan.md` §11.2e）。这正是 CBF 引入的动机。
- **CBF reward-core 变体标定（D2-16，2026-09-05，详表见 §3.7）**：① `penalty_src=correction`（罚滤波纠偏量）消除 nominal 的“远离罚区”保守偏置，λ0.05@20M joint 0.669 超 nominal λ0.05@40M(0.634)，**甜点 ~20M**（correction 加长到 40M 退化——学会近穿后罚≈0、后期无约束越贴越狠）；② 强化目标进度 shaping（`reward_pbrs_weight` 2→8）单变量 +8.8pt（corr λ0.05 w8 = 0.757）；③ **w8 全臂公平**：filter_only w8=0.789 反超 hybrid corr w8=0.708–0.720——强 shaping 驱动猛冲→滤波频繁纠偏→correction 罚大→拽回 hybrid，纯滤波 + 强 shaping 组合最大化（arm 序随 shaping 反转）；④ naive/reward_only 无滤波任何 w 都 coll 43–49% 不可用。
- **调参教训**：CBF 权重“小 λ 微调”（0.05–0.1）而非论文式 ×100；correction 类变体甜点在短训（~20M），勿按 nominal 的 40M 甜点加长；强 shaping(w≥8) 才压得过障碍罚面，但会翻转 correction 的 reward-core 增益（§3.6 启示）。
- **M3-A dual 到达↔安全平衡标定（2026-09-06，详记 m3_plan.md）**：D2-16 下 dual reward-core 后期出现"cbf_violation 降 + arrival 塌"保守 drift。逐项核算（dt=0.01→600 步=6s 窗；Hover 常驻 pose/up/effort 堆 return 基座 ~600，任务项占比 <15%；PBRS 势差近似路径无关不罚绕远）后做**到达侧×3 数值重设计**：`timeout_penalty` 高(40–60)淘汰悬停/绕远超时（**抗后期退化主角**：W2(to40) 20M ON 0.530 全谱最高）、`arrive_bonus` 适中(30，60 反伤)、`reward_pbrs_weight` 8→**16**（稠密前进 credit，早峰 ON +4~5pt）。**主推 S3 配方（早停 @6.5M）= (w1,w2)=(0.2,0.2)+`reward_pbrs_weight=16`+`arrive_bonus=30`+`reward_timeout_penalty=60` → 确定性 eval ON joint 0.743 / 无 runtime filter OFF joint 0.572（coll 34.1%）**；求 20M 不早停用 W2（w8+ab30+to40 → ON 0.530 / OFF 0.444, coll 20.6%）。⚠️ 均为 CLI 覆盖（yaml 默认未动），公平对比需各臂同参。

---

## 6. M2-3 CBF 接口预留（与本文口径一致的要求）

1. **输入真值同一来源**：CBF 滤波/reward-core/碰撞/obs 都消费 `ObstacleManager` 暴露的 `pos (N,K,3)`、`radius (N,K)`、`active (N,K)`，只是半径取法不同：
   - 几何（obs/碰撞/奖励）：$r_s = r_{drone}+r_o+r_{infl}$；
   - CBF 安全半径：$r^{cbf}_{s,i}=r_{drone}+r_{o,i}+r_{margin}+\underbrace{v_{max}^2/(2a_{max})}_{\text{制动裕量}}$（**进滤波/奖励 core，不进 obs**）。
2. **滤波作用点** = §2 策略输出 $v_{nom}\in\mathbb R^4$ 进入 VelController 之前；reward core 的违反量用**滤波前 $v_{nom}$** 计算（否则策略学不到被罚的是自己输出）。
3. `cbf.mode ∈ none|filter_only|reward_only|hybrid`；`mode=none` 必须与本文所述 naive 行为逐位一致（回归基准 = `lmhvaqka` 等 8 障基线）。
4. ⚠️ **2026-09-07 New2 口径变更预告**：第 1 条「CBF 安全半径不进 obs」将放宽——New2（`drones/new2_plan.md`）给 obs 追加 **CBF 边界余量 $h=\min_i(\|p-p_{oi}\|-r^{cbf}_{s,i})$ 与/或 min_clearance** 通道（62→63/64 维，默认关）。理由：internalize（撤 filter 也安全）需要策略**事前知道 filter 触发边界**（reward-shaping 已证伪，见 new1_plan.md 顶部总结）；obs 加 h 是把「事后账本」变「前向可预测特征」。部署侧：h/min_clearance 是纯几何量（障碍位置 + 确定性 CBF 公式），真机有障碍地图/感知即可复算，**不依赖 filter 在线**（internalize 兼容）；**勿把 filter 介入量 ‖v_filt−v_pol‖ 放 obs**（撤 filter 时恒 0 → 分布偏移）。§1 obs 表与 §3.7 届时同步更新。

---

## 附：文件↔职责对照

| 文件 | 职责 |
|---|---|
| `cfg/task/NavVel.yaml` | 上述全部键默认值（含 obstacle/curriculum/vel_limit 段） |
| `envs/single/nav_vel.py` | spec/obs 拼装/奖励/终止/软重生/课程结算/动作挂接 |
| `envs/single/nav_vel_obstacles.py` | `ObstacleManager`：布局采样/碰撞/净空/obs 块（纯 torch、可 CPU 单测） |
| `utils/nav_curriculum.py` | 课程窗口/门控 |
| `utils/torchrl/transforms.py::VelController` | 速度指令限幅 + 送 Lee 内环 |
| `robots/drone/multirotor.py` | 23 维 `drone_state` 布局（见 §1） |
