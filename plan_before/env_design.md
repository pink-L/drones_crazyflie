# env_design：NavRL 训练场景 → 6×6×3 Crazyflie 避障实验的迁移设计

> 创建：2026-09-07。目的：把 NavRL（CERLAB-UAV-RL-Navigation，`refs/NavRL/isaac-training/training/scripts/env.py`）
> 的训练场景**设计**迁移到「6×6×3 m 部署 + Crazyflie + 先静态障碍后动态障碍」的实验。
> 面向对象 = OmniDrones `NavVel` 环境（分支 `feat/crazyflie-pidrate`，HEAD `1d7e9df`）。
> 上游文档：`drones/arena1_plan.md`（6×6 全区域布障/固定穿越已做）、`drones/f1_recipe_and_runs.md`、
> `drones/new_reward.md`（F1 reward）、`drones/new2_plan.md`。代码基线 `cfg/task/NavVel.yaml` + `omni_drones/envs/single/nav_vel.py`。
> ⚠️ md/figures 属 drones 外层仓库、从不入库（历史惯例），本文件同样只本地留存。

---

## 改动记录（2026-09-07 · 已实现进 NavVel.yaml + nav_vel.py + eval_ckpt.py 模板）

> 本节 = 代码落地说明；下文 §3.x 的早期建议若有与本节冲突，**以本节为准**。

### 一、现在改了什么（本次已实现）

1. **起终点采样 → `episode_sampler=edge`**（`nav_vel.py` 新增 `_sample_edge_pos`，NavVel.yaml 默认）
   - start 恒在 `x=-2.8` 线（左）、target 恒在 `x=+2.8` 线（右）；y 随机 `[-2.8,2.8]`、z 随机 `[0.4,2.4]`；
   - 固定 ±2.8 = 距墙 0.2（中心 OOB 判定）/0.1（机身半径 ~0.2m）裕量——rev 2026-09-08 废弃原 x 边带 [2.6,3)、y 满幅 [-3,3]（贴墙瞬时 OOB）；
   - ⇒ 每局必横穿场地中央，防“贴边走逃逸不避障”。`fixed_*` 非 None 时一律优先 = eval 固定点用。
   - 旧 `uniform`（全范围随机）保留为兜底，向后兼容。
2. **6×6×3 箱式越界**（新键 `arena_bound: [3,3]`）：`|x|>3` 或 `|y|>3` = 飞出房间 = 失败（与圆形 `bound_xy` 是“或”）。
3. **训练改“严格单命”**：`soft_respawn: false` + `obstacle.max_collisions: 1` ⇒ 坠地/OOB/**碰一次**即 terminated、不复活，与 eval 同构（对齐 NavRL“碰撞即失败重抽一局”）。
4. **去掉 z 轴保高惩罚**：`survival_penalty_weight: 0`（允许飞到 z_ref=1.0 以下不扣分，支持低 z 起点/目标）。
5. **eval 固定点**（已写进 `eval_ckpt.py` 顶部模板）：`start(-2.8,0,0.5) → goal(2.8,0,1.0)`，仍严格单命。
6. **未加**“连线走廊至少 1 障”布局保证（§3.3 暂缓）：按你的选择，先靠 y 全覆盖 + 全区域布障 + 密度课程。
7. **障碍出生走廊净空 `keepout_x`（新键，rev 2026-09-08）**：障碍**逻辑球面** x 不越过 ±keepout_x
   （球心随半径收窄 `|x| ≤ keepout_x − r_o`，per-slot 施加于 `nav_vel_obstacles.py` 的
   `_sample_one_pass` valid mask 与 `_fallback_layout` clamp）；y 仍全幅 `[-3,3]` 布障、z 不变。
   NavVel.yaml 默认 `keepout_x: 2.5` = 与出生线 ±2.8 中心距 0.3m / 无人机横向净空 ~0.15m
   （用户口径：逻辑球 r_o，走廊界 2.5）；`inf` = 不限，向后兼容。
   注：物理球固定 0.4 观感仍可能探入走廊，判定/碰撞/reward/CBF 均按逻辑球面，语义安全。
   （CPU 冒烟：L2/4/8/16 球面 max(|x_c|+r_o)=2.500 ≤ 2.5；fallback keepout=1.0 = 0.999 ✓）

### 二、避障跑通后还要改（未来待办，按优先级）

1. **对称化左右侧**：现在 start 恒左→target 恒右，策略只学 +x 导航；跑通后应随机左右对侧（甚至四边），避免部署方向偏好。
2. **z 近地可学性监控**：`edge_z` 下限 0.4、eval start z=0.5 —— Arena1 曾证 <~0.6 近地 from-scratch 学不动（当时带 survival 惩罚）；若 0 障都学不动 → 训练 z 下限抬到 ≥1.0，或 warm-start M1/F1 ckpt。
3. **课程/密度重标定**：硬单命下 curriculum（现 `[2,4,8,12,16]`）可能过陡 → 视可学性改 `[0,2,4,8]`/加 0 障首级/调升档门槛；16 障只当压力测试，非验收主口径。
4. **走廊/路径有障保证（§3.3）**：低密度(1–4 球)时“连线必穿障”仍无硬保证，观察训练是否“绕开不避”再决定是否补。
5. **速度/到达/CBF 小房间标定**：`max_vel`、`arrive_radius`、CBF brake 项/半径按 6 m 房间重调。
6. **动态障碍（S3）**：DynamicObstacleManager + obs 速度通道 + 时变 CBF（§3.5），静态跑通后再做。
7. **Arena1 固定穿越回归**：部署若是定点穿越，最后用 `fixed_*` 把随机导航 ckpt 接到固定场景微调/评估。

---

## 0. TL;DR（先回答三个问题）

1. **NavRL 的训练场景需要缩小吗？**
   需要**缩成部署体积**（6×6×3），但不是把 NavRL 数字"等比例缩小"——而是按 Crazyflie 动力学、
   小房间约束和你的现有基建**重新推导**。NavRL 场地 40×40×4.5（地形 50×50），若在 40 m 场地训练、
   部署 6 m 房间，避障策略学的距离感/密度/机动预算完全不匹配（sim-to-real gap 直接放大）。
   **好消息：你的 Arena1 已经把 NavRL 的"场地"部分落地为 6×6×3**（`spawn_xy ±3`、`z_max 3.0`），
   这一步不需要再重做，缺的是"起终点/障碍的**任务语义**"仍停留在 Arena1 的固定穿越。

2. **就 env 而言，如何做 NavRL → 我的实验迁移？**
   不要移植 NavRL 的 `env.py`（它基于 Hummingbird + 高度场地形 + 幽灵障碍 + lidar，架构与你不兼容）。
   你的 `NavVel`（球障碍 + ObstacleManager + CBF + 课程 + 软重生）已经**重实现了 NavRL 想表达的东西**，
   迁移对象是 **NavRL 的 env 设计决策**（见 §3 映射表），落到你已经抽好的抽象上：
   `_sample_init_pos/_sample_target_pos`（fixed/随机双模式）、`obstacle.*`、`curriculum.*`、`cbf.*`。

3. **train 和 eval 同场景、一个随机采样一个固定采样？**
   NavRL 确实是这个哲学（train 四边随机起终点；eval 固定对边起终点），**这个哲学直接采纳**：
   同一个 env/同一套 obs+reward+CBF，train 用随机起终点 + 随机布局 + 多命软重生；
   eval 用固定（或种子固定）起终点 + 种子固定布局 + 严格单命。你的 `eval_ckpt.py` 已经按此固化。

**核心建议**：bootstrap 阶段**不要用 Arena1 的"固定 5 m 穿越 + 全区域稠密"**（实证非常难学，
strict single-life arrival <10%），改用 **NavRL 式"随机起终点 + 中低密度静态障碍"**（= 你 M1/F1
已验证可学的路），先把"会避障"跑通；跑通后再①按需加密度、②叠 Arena1 式固定穿越作为最终部署场景、
③最后加动态障碍。

---

## 1. NavRL env 复盘（对照速查，详见上一条问答）

| 项 | NavRL（`env.py` + `cfg/train.yaml`） |
|---|---|
| 场地 | `map_range=[20,20,4.5]`；高度场地形 40×40（+5 平边带 = 50×50），静态障碍在 ±20 内 |
| 起终点 | 训练：四边等概率 ±24 边缘带，z∈[0.5,2.5]；`min_init_target_dist` **没有**；eval：固定对边（y=24→y=-24）|
| 静态障碍 | 地形 `HfDiscreteObstaclesTerrainCfg`：350 个长方体（宽 0.4–1.1 m，高 4–6 m 为主），seed=0 固定 |
| 动态障碍 | 80 个"幽灵体"RigidObject（碰撞关）：8 类 = 4 档宽 × 2 档高（3D 矮 cuboid 1 m / 2D 通天 cylinder 5 m）；在 local_range 5 m 内换目标，0.5–1.5 m/s |
| 观测 | lidar(36×4, 4 m 只扫地形) + 自身 8 维状态 + 最近 N 动障相对状态(位/速/尺码) |
| 碰撞语义 | 碰撞/越界 → `terminated` → 重置为**新随机 start+target**（不是回原起点）|
| 每 env 无人机 | 1 架 Hummingbird；地形/动障在 `/World` **全局共享**（所有 env 跑同一场地）|
| 并行 | `env.num_envs`（repo 默认 2，可调大）|

**NavRL 的设计要点（值得抄的）**：①起终点都取"场地外围/边缘"→ 让大多数回合必须横穿内部障碍区
（但**没有显式保证连线有障**，靠密度 + 对边概率 ~75%）；②静态稠密 + 动态移动双通道；③安全 = 距离型
稀疏惩罚 + 提前终止；④碰撞 = "重抽一局"而非"回起点重飞"。

**不值得抄的**：全局共享场地、幽灵动态障碍（物理不挡）、350 个地形障碍、lidar 只扫地形、无显式净空
保证（start/goal 可能生在障碍里）。

---

## 2. 缩小还是重推？——6×6×3 的缩放结论

先给结论：**训练体积必须 ≈ 部署体积**（6×6×3），但不能简单把 NavRL 的"每项 ×(6/40)"。因为：

- Crazyflie（`drone_radius 0.15`、`max_vel 1.8`、dt 0.01）比 Hummingbird 小很多、快很多（相对房间）；
- 3 m 总高让场地从 NavRL 的"准 2D 导航"变成**真 3D**（高 = 边长一半）；
- 你的障碍模型是球（几何判定 + CBF），NavRL 是长方体地形 + 幽灵体——两者密度/碰撞语义不同。

缩放表（NavRL → 6×6×3，右侧 = 你的 NavVel 现状/建议）：

| 项 | NavRL | 6×6×3 Crazyflie（建议） |
|---|---|---|
| 场地 xy | ±20 障碍区 + ±5 平边带 | `spawn_xy_range [[-3,-3],[3,3]]`，障碍贴边 ±2.8 起（Arena1 已有）|
| 总高 | 4.5 m | `z_max 3.0`（Arena1 已有）；起点 z ≥ 1.0（实证近地学不动）|
| 障碍体积 | 长方体 0.4–1.1 m | 球 r ∈ [0.2,0.3,0.4]（已有；若部署物更大再加 0.5 档）|
| 静态数量 | 350/1600 m² ≈ 0.22/m² | 36 m² 等效 ≈ 8；bootstrap 用课程 **0/1–2–4–8** 起步（勿一开始 16）|
| 起终点 | ±24 四边，z∈[0.5,2.5] | 半边/对半采样（见 §3.2），z∈[0.8,2.2] |
| 障碍 z | 地形柱 0–6 m | `spawn_z [0.6,2.4]`（已有），可选少量"通天柱"保留 2D 绕行 |
| 动态障碍 | 80（幽灵、分析碰撞）| 后加 4–8 个移动球 + 分析碰撞 + 速度通道 obs（§3.5）|
| 传感器 | lidar 4 m 扫地形 | 无 lidar；obs = 最近 K 球相对状态 + CBF（已有）|
| 安全半径 | 碰撞判定 ~0.3 | `r_s = 0.15+r_o+0.05`；`danger_radius 0.6`（小房间可调 0.5–0.8）|
| env 结构 | 1 机/共享全局场地 | **1 机/独立克隆场景**（保留！比 NavRL 好，可 num_envs=1024）|

> 一句话：**不用缩小什么——你的场地已经是 6×6×3；真正要做的是把"任务语义"从 Arena1 的固定穿越
> 切回 NavRL 式随机导航，并把障碍/速度/净空按小房间重新标定。**

---

## 3. 逐项迁移设计（就 env 而言）

### 3.1 场地结构与每 env 无人机

- 沿用你现在的结构：`num_envs` 个 env，每个 env **1 架 Crazyflie + 独立随机障碍布局 + 独立起终点**。
- 这与 NavRL"全局共享一个 40 m 场地"不同，是**有意改进**：env 之间解耦 → 并行度可拉满
  （`num_envs: 1024`），且不会出现 NavRL 多机共享场地时的互相干扰。**迁移时保留，不要改成 NavRL 式**。
- 场地坐标/越界沿用 Arena1：`bound_xy 5.0`（6×6 内不触发）、`z_min 0.15`、`z_max 3.0`。

### 3.2 起点 / 终点采样（train 随机 vs eval 固定）

NavRL 在 40 m 场用"±24 四边"是因为边上有 4 m 平地带可安全出生。6×6×3 没有这种边带，**不能直接抄
"四边采样"**。
> ✅ **已定案并实现（2026-09-07；rev 2026-09-08）**：最终采用"方案 C 修改版"（见文档开头改动记录）：
> `episode_sampler=edge` = start 恒 `x=-2.8` 线、target 恒 `x=+2.8` 线，y∈[-2.8,2.8]、z 随机 [0.4,2.4]（距墙 0.2/0.1m）；
> eval 固定 `start(-2.8,0,0.5)→goal(2.8,0,1.0)`。以下 A/B/C 仅作备选思路的历史记录（A 未采用、B 兜底保留、C 为本次实现基础，落地为固定 ±2.8 线改进版）。

小房间的等效做法（按简单→复杂）：

1. **方案 A：对半采样（推荐，最接近 NavRL 语义、代码最小）**
   start 落在 x<0 半场、target 落在 x>0 半场（或 y 半场，交替），z 各自 ∈[0.8,2.2]。
   ⇒ 天然保证"要横穿场地中部"，与低密度障碍叠加后走廊大概率有障。
   实现：`_sample_init_pos/_sample_target_pos` 已抽象，加一个 `sample_mode: uniform|half` 即可
   （fixed 已支持）。
2. **方案 B：均匀 + `min_init_target_dist`（你已有，M1/F1 用过的兜底）**
   start/target 全场地均匀，`min_init_target_dist ≥ 2.5`（≈ 半房间），净空 rejection 保证出生/到达安全。
   注意：全场地均匀时低密度障碍下"连线是否穿障"不受控 → 配 §3.3 的走廊检查。
3. **方案 C：外围带采样（NavRL 直接缩小版）**
   沿 6×6 内缩一个 0.4 m 的边框带（如 ‖xy‖ 在 2.6–2.9 之间）取点。小房间边带太薄、3D 障碍会侵入，
   一般不推荐，除非部署就是"沿墙飞行"。（rev 2026-09-08：最终实现取其改进版 = 固定 ±2.8 线 + y∈[-2.8,2.8]，见上方定案）

> **eval 端（固定）**：`fixed_init`/`fixed_target` 已是现成开关。evaluation = 同场景同配方，
> 仅 start/goal 固定 + 布局种子固定 + `soft_respawn=false`（严格单命）。
> NavRL 的 eval 是"一排行 start → 固定 target"；你可以等价地 eval 一排固定对（如 x=±2.5、z=1.0/1.5 的
> 几组），比单个固定对更能反映避障能力，且不落入 Arena1 单点穿越的"难到学不动"陷阱。

### 3.3 保证"起点→终点路径上有障碍"（NavRL 没显式做，6×6×3 低密度时必须补）

NavRL 靠"350 障碍 + 对边出发 ~75%"概率性保证；6×6×3 在 1–4 个障碍时这个保证会破（连线可能全空）。
补法（按强度）：

- **走廊检查（推荐，bootstrap 就开）**：每 env 采样布局后拒绝"start→target 直线走廊内没有任何障碍"的
  布局。走廊判定：
  $$
  \exists\, o:\ \mathrm{dist}(p_o,\ \overline{\mathrm{start}\to\mathrm{target}})
  \le r_{s,o} + R_{\text{corridor}},\quad R_{\text{corridor}}\approx 0.6\text{–}0.8
  $$
  在你的布局探针里已经写了类似几何（`arena1_layout_check.py`），把它变成**采样约束**（不合格重采样，
  有限轮后放松，兜底不挂 reset），并让"路径近障数"随课程 level 单调增。
- **构造式保证（level=1 最简单）**：先放 1 个障碍于 start→target 中点附近（确保在连线上），其余随机。
- **纯密度（NavRL 方式，level≥8 后才够）**：≥8 个球均匀铺 6×6，对半起终点几乎必然穿障。

> ⚠️ 同时仍要遵守你已有的硬约束（M2 净空公式）：`dist(球心, init) ≥ r_s + init_clearance`、
> `dist(球心, goal) ≥ r_s + goal_clearance`、球间 `≥ r_i+r_j+min_gap_between`——保证"有障但可达"，
> 而不是"有障但把路堵死"。

### 3.4 静态障碍（先做，现在就有）

- 保持**球模型**（几何 + CBF + obs 口径一致），半径 `[0.2,0.3,0.4]` 不变；小房间窄缝多，
  保持 `min_gap_between 0.25`。
- 密度课程建议 **`levels=[0,2,4,8]`（或 [1,2,4,8]）**、`num_scene=8`（M=K 先省显存；跑到 8 稳定再上 16）。
  这比 Arena1 的 `[2,4,8,12,16]` 温和，符合"先跑通避障"目标。
- 障碍 z：`spawn_z [0.6,2.4]`（球顶 ≤2.8<3）；建议混入**少量"高柱"障碍**（把球拉长成
  yz/xy 向的柱，或直接放 `height≈3` 的细柱，半径档沿用）来保留 NavRL 那种"2D 绕行 + 3D 越顶"的
  行为多样性——纯浮球会鼓励"全从顶上绕"，和真实家具(地面物体)不符。
- 出生 z ≥ 1.0、`0 障首级` bootstrap——两条都是你 Arena1 血泪教训，直接固化成默认。

### 3.5 动态障碍（后做，NavRL 模板）

NavRL 动障的设计可直接做模板，但换成你的球 + 几何口径：

- **模型**：每 env 少量移动球（建议从 2–4 起步），给每个球一个速度 `v_o`；移动方式照抄 NavRL
  `move_dynamic_obstacle` 的"局部区域换目标 + 匀速直飞"（`local_range ≈ 2–3 m`、`vel 0.3–1.0 m/s`
  起步，小房间别学它 1.5 m/s）。
- **物理**：NavRL 是"幽灵体 + 分析碰撞"（物理不挡）。你可同样用分析碰撞（`‖p−p_o‖−r_s<margin`），
  或开物理碰撞但把障碍做成慢速（对 Crazyflie 更真实）。**先分析后物理**。
- **obs**：在你 K 槽障碍块里给**移动球加速度通道**（目标系/机体系 3 维速度 + 已有 rpos/半径），
  即 NavRL `dynamic_obstacle` 通道的等价物；需要区分"静态槽 vs 动态槽"（或独立一段 obs）。
- **CBF**：静态 CBF 是 `h=‖p−p_o‖−r`、`ḣ=n·v`；动障变成**时变 CBF**：
  $$
  h=\|p-p_o\|-r_{s},\qquad \dot h = \frac{(p-p_o)^\top(v-v_o)}{\|p-p_o\|},\quad
  \dot h+\alpha h\ge 0
  $$
  仍是 v 的线性约束（`v_o` 视为已知外扰），可沿用你 `cbf.py` 的迭代投影，只需把 `n·v` 换成
  `n·(v−v_o)`，并把 `r_s^cbf` 按"速度可达集"加裕量（动障越快裕量越大）。**这是一个新的实现点**。
- **reward**：安全项从"静态距离 log"扩成"预测最近距离"（`d−|v_o|Δt` 前瞻），或沿用 NavRL 的
  距离型 + 碰撞终止；filter 兜底仍然保留。

### 3.6 碰撞 / 重置语义差异（务必在文档/汇报里讲清）

| | NavRL | 你的 NavVel |
|---|---|---|
| 碰撞后 | `terminated` → 整局重置，**重抽新 start+target** | `soft_respawn=true`：窗口(600 步)内软重生回**本局起终点**，障碍/目标不变（多命）；`max_collisions=2` 累计边沿触发重生 |
| 达到 | `reach_goal` → terminated | `success_terminate=false`：继续悬停保持（学停稳）|
| eval | 固定对边、确定性 | `soft_respawn=false` 严格单命 + 固定/种子布局 |

- 你的软重生 + 多命是**训练侧注水**（Arena1 实证：多命 success~0.7 vs 严格单命 <10%）。训练期保留
  多命以提速没问题，但**验收/汇报必须用严格单命**（已是你的标准模板）。NavRL 的"碰撞重抽一局"更接近
  "每次都是新任务"，对随机导航是好事——你可把 `soft_respawn=false`（碰撞即本命失败）作为 bootstrap
  训练的一种口径，等价 NavRL，但要注意会损失样本效率（Arena1 已证固定穿越下会卡）。

### 3.7 小房间相关的标定（速度 / 到达 / CBF）

- **速度**：`max_vel 1.8` 在 6 m 房间偏快（对半穿越只需 ~3 s、刹停距离 ≈v²/2a≈0.8 m）。bootstrap 建议
  降到 `1.0–1.5`，避障跑通后再调回；同时**保留 CBF brake 项**（小房间内环滞后占比更大）。
- **到达**：`arrive_radius 0.5` 相对 6 m 房间可保留（与 `goal_clearance 0.35` 不冲突）；若部署要求
  更精确入位再缩到 0.3。
- **CBF**：`r_safety_margin 0.1`、`use_brake_term` 在小房间内影响更大，用"同 ckpt 仅 eval 改半径"
  零成本扫描一次即可；`alpha 1.0`、`filter_iterations 3` 沿用。
- **密度上限**：6×6×3 里 16 个 r=0.4 球 + 0.25 间隙就是 Arena1 档（很难），静态先封顶 8，
  稳定后再冲 12/16 当压力测试，别当验收主口径。

---

## 4. 落地路线（阶段划分，可直接跑）

| 阶段 | 内容 | env 改动 | 验收 |
|---|---|---|---|
| **S0 基线** | 0 障随机导航（NavRL 语义、无 Arena1 固定穿越）| `fixed_init/target=null`、随机均匀/对半采样、`min_init_target_dist 2.5`、z∈[0.8,2.2] | M1 口径：到达 ≥0.8（warm M1 ckpt 更快）|
| **S1 静态避障 bootstrap** | 课程 0→2→4，`num_scene=8`，走廊检查开，`max_vel 1.2` 起 | + 对半采样、+ 走廊有障采样约束（§3.3）| 严格单命：2 障 OFF(带 filter) joint 明显 >0、4 障不崩 |
| **S2 密度课程** | 0/2/4→8→12/16，`num_scene=16` | 无（调 curriculum）| 严格单命 @8 为主、@16 压力；对照 naive/reward_only |
| **S3 动态障碍** | 先 2–4 移动球分析碰撞 | + `DynamicObstacleManager`、obs 速度通道、时变 CBF（§3.5）| 移动球下 ON/OFF 碰撞/到达对照 |
| **S4 部署场景** | 需要时切回 Arena1 固定穿越/固定布局作为"最终场景" | 只改 `fixed_*` + eval 布局 | 以部署形态为准 |

> 顺序原则：**先随机起终点把"会避障"学到（容易），再用固定穿越/固定场景逼近部署（难，放后）**——
> 与 Arena1 直接上固定穿越的路径相反，避免重蹈"from-scratch 学不动"。

---

## 5. 推荐配置（NavRL 风格 6×6×3 随机导航，S1 可跑版）

```bash
cd /home/lz/lzspace/drones/OmniDrones/scripts
source /home/hybrid/miniconda3/etc/profile.d/conda.sh && conda activate lz_env

python -u train.py task=NavVel algo=ppo headless=true wandb.mode=online \
  wandb.project=navvel_env_design wandb.run_name=NavVel-navrl6x6-s1-2obs \
  # ---- NavRL 语义：随机起终点（关 Arena1 fixed 穿越）----
  task.fixed_init=null task.fixed_target=null \
  task.init_pos_range=[[-2.6,-2.6,1.0],[2.6,2.6,2.2]] \
  task.target_pos_range=[[-2.6,-2.6,0.8],[2.6,2.6,2.2]] \
  task.min_init_target_dist=2.5 \
  # ---- 6×6×3 场地/障碍 ----
  task.z_max=3.0 \
  task.obstacle.spawn_xy_range=[[-2.8,-2.8],[2.8,2.8]] \
  task.obstacle.spawn_z_range=[0.6,2.4] \
  task.obstacle.num_scene=8 \
  task.obstacle.radius_choices=[0.20,0.30,0.40] \
  # ---- 温和课程（含 0 障首级 bootstrap；走廊检查需代码，见 §3.3）----
  'task.curriculum.levels=[0,2,4,8]' task.curriculum.initial_level=0 \
  task.curriculum.success_rate_threshold=0.80 \
  # ---- 速度/到达（小房间先慢后快）----
  task.vel_limit.max_vel=1.2 task.vel_limit.max_yaw_rate=1.5 \
  task.arrive_radius=0.5 task.arrive_hold_steps=50 \
  # ---- F1 reward + CBF（复用 pg6q5ji5 已验证配方；mode 视对比需要）----
  task.reward_scheme=f1 task.reward_fly_weight=6.0 task.reward_action_smoothness_weight=0.2 \
  task.arrive_bonus=30 task.arrive_time_bonus=30 task.reward_timeout_penalty=40 \
  task.cbf.mode=hybrid task.cbf.use_brake_term=false \
  task.cbf.reward_weight=0.1 task.cbf.correction_weight=0.1 task.cbf.correction_sigma=0.5 \
  algo.entropy_coef=0.05 total_frames=20_000_000 save_interval=100 +render_eval=false \
  2>&1 | tee /tmp/navvel_envdesign_s1_2obs.log
```

> 说明（2026-09-07 后）：NavVel.yaml 默认已内置本迁移的全部几何与终止语义——`episode_sampler=edge`
> （start 左带→target 右带）、`arena_bound [3,3]` 箱式越界、`soft_respawn=false + max_collisions=1`
> 严格单命、`survival_penalty_weight=0`。故上面命令里的 `fixed_init/target=null`、spawn/z 范围均可省；
> 保留的是**任务/奖励层**选择（课程档、速度、reward scheme、CBF mode）——S1 阶段按需保留。
> `vel_limit` 在 NavVel.yaml 命名空间是 `vel_limit.max_vel`（CLI 用 `task.vel_limit.max_vel`）。
> 评估（同场景固定点）见 eval_ckpt.py 顶部模板：`task.fixed_init=[-2.8,0,0.5] task.fixed_target=[2.8,0,1.0]`。

---

## 6. 建议新增的代码点（都落在现有抽象上，最小侵入）

1. `nav_vel.py` `_sample_init_pos/_sample_target_pos`：加 `init_mode/target_mode = uniform|half`，
   对半采样 = NavRL 四边语义在 6×6×3 的等价物（§3.2-A）。`fixed_*` 已有，不动。
2. `ObstacleManager.sample_layout`（或布局层）：加"走廊至少 n 个障碍"约束的 rejection / 构造式放置
   （§3.3）。复用 `arena1_layout_check.py` 的几何。
3. `ObstacleManager` + 新 `DynamicObstacleManager`：移动球状态/步进/换目标（§3.5），
   沿用 NavRL `move_dynamic_obstacle` 的 goal-switch 逻辑。
4. `nav_vel.py` obs 块：动态槽加"速度通道"（尺寸随 K 变，注意 obs 维度/ckpt 兼容，参照
   `obs_safety` 加维的先例——**加维即断 warm**）。
5. `utils/cbf.py`：时变 CBF（把 `n·v` 改为 `n·(v−v_o)`）+ 按动障速度的可达集裕量（§3.5）。

---

## 7. 与 Arena1 的关系与取舍

- **Arena1（6×6 全区域 + 固定 5 m 穿越）已经证明了场地基建可行**，但也证明"固定穿越 + 稠密布障
  from-scratch"很陡（strict single-life <10%、冲不到 12/16）。
- 本设计的定位 = **NavRL 式随机导航避障是"先跑通"的正确台阶**，Arena1 式固定穿越保留为 **S4 部署场景**
  （部署就是"定点穿越"，最后再把 A→B 固定）。两者**共享同一 env**，只差 `fixed_*`、采样器、课程密度——
  所以不需要两套环境。
- 动态障碍只在随机导航/半固定场景下有稳定信号（固定穿越 + 移动障碍更难），故放 S3 之后。

---

## 参考

- NavRL：`refs/NavRL/isaac-training/training/scripts/env.py`（`reset_target/_reset_idx/_design_scene/_compute_state_and_obs`）、
  `cfg/train.yaml`（`num_obstacles 350 / env_dyn 80`）、`cfg/sim.yaml`（dt 0.016）。
- 你的基线：`OmniDrones/cfg/task/NavVel.yaml`、`omni_drones/envs/single/nav_vel.py`、
  `omni_drones/envs/single/nav_vel_obstacles.py`、`omni_drones/utils/nav_curriculum.py`、
  `omni_drones/utils/cbf.py`、`scripts/arena1_layout_check.py`。
- 相关阶段文档：`arena1_plan.md`、`f1_recipe_and_runs.md`、`new_reward.md`、`new2_plan.md`。
