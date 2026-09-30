# NavVel 动态障碍物分模块开发计划

最新 Gate 1 状态（2026-09-23）：**GATE_1_BLOCKED；Gate-1C corrected primary=`INCONCLUSIVE`；NOT_READY_FOR_GATE_2**。Yaw 目标偏差及原有 ±1.5 rad 限幅按用户裁定不阻塞平移速度环辨识；真实 Isaac world-frame 与日志对齐已确认。Z 结构、运行点模型及 XY 耦合尚未满足冻结证据要求，Gate-2 输入仍 suppressed。最终结果与原始分析纠错见 §10.28；§10.26–10.27 按历史保留。


初稿：2026-09-20；接口复核修订：2026-09-21。当前：M0/M1a/M1b/M2/M3/M5/M6及M4a既有模块保持通过；M4a-greedy-runtime-hardening 已交付，correctness=PASS_WITH_APPROXIMATE_GREEDY_SOLVER，M7=NOT_READY_FOR_M7。noisy Dual 已真实合批，B1024 decision p99=18.392ms；真实有限 rollout 仍有高频非收敛/终止，详见§10.8。默认 greedy64/refinement OFF；缺失 backend 仍为 Dykstra。几何与参数继续 provisional，未开始训练。

本文以本次讨论及当前代码为依据，后续按模块交付，不要求一次性完成环境、CBF、网络和训练。当前任务只编写/修订本文，不修改训练代码、不启动训练、不修改旧实验配置。

## 1. 目标、范围与决策状态

### 1.1 已确认需求

1. 最新模型采用 **58 维观测、一个有限高圆柱对应一个障碍物**；多层球构柱属于旧版本，不作为此次主线。
2. 圆柱阶段只在 XY 平面平移，Z 方向速度为零；限制障碍物速度和加速度，数量使用课程学习。
3. 初始尺寸意向为横向 0.3m × 0.3m、高度 1.2m 或 2.5m，用于区分可飞跃与不可飞跃。
4. 实机通过外部动捕/跟踪提供位置；速度由部署侧估计，不能默认 actor 获得仿真真速度或真加速度。
5. 本阶段明确从零训练，不需要定位旧 checkpoint，不把权重迁移列为必做模块。旧 58 维配置仅用于回归和接口参考。
6. 探索 asymmetric actor-critic：actor 使用可部署观测，critic 可以使用动态障碍物真实速度和加速度。
7. 后续独立阶段引入三维自由移动球体，代表其他飞行无人机；当前需要预留接口，不提前实现完整多机动力学或自博弈。
8. **本阶段只做水平绕行，低柱飞跃后置**；不能在主训练中让飞跃成为绕行任务的捷径。
9. **训练使用 CBF filter + CBF reward，最终目标是 without runtime CBF filter**，以 CBF-RL 的安全内化思路为依据；ON 结果仅用于辅助诊断。
10. 实飞场地为 **6m × 6m × 3m**，动捕实际输出 **100–120Hz**；训练加入域随机化。数量和速度分别课程提升，具体终点待定。

### 1.2 待确认事项及处理方式

| ID | 待确认项 | 对计划的影响 | 未明确前的处理 |
|---|---|---|---|
| Q1（已确认） | 只做水平绕行，飞跃后置 | M4b 不属于当前验收 | 当前主场景使用高柱和受限导航高度带，低柱飞跃单列后续 |
| Q2（已确认） | 训练 filter + reward，最终部署无 filter | OFF 为主验收，ON 为诊断 | 初版训练 filter 常开；退火仅后续消融，不视为论文必需条件 |
| Q3（已确认） | 从零训练 | 不需要旧 checkpoint | 从 58 维圆柱配置抽取结构参考，新建 profile；不实现迁移工具 |
| Q4 | 横向 0.3m 是圆柱直径，还是方柱边长的圆柱包络 | 决定圆柱半径和碰撞净空 | 直径对应 r=0.15m；包络方柱对应 r=0.3/√2≈0.2121m；M0 必须定一种 |
| Q5 | 场地 6×6×3m 已确认；导航高度带、无人机尺寸及裕量待定 | 区分物理场地上限和本阶段导航高度范围 | 不改变真实场地高度；配置更窄导航带以避免飞跃，具体值 M0 冻结 |
| Q6 | 动捕 100–120Hz 已确认；端到端延迟、丢帧、噪声待测 | 决定多速率测量模拟、估计器与 DR | 频率在已知范围随机化；延迟等独立标定，不能用 1/f 代替链路延迟 |
| Q7 | 障碍物数量上限、运动装置速度/加速度、训练预算 | 决定课程终点和计算资源 | 数值作为探索范围；不自动启动长训练 |

这些事项不阻止完成计划和独立模块设计；影响某模块行为的事项应在该模块实施时解决。本文不把可选设计写成用户已确认的要求。

### 1.3 建议方案与非目标

- 全部主实验从零训练；旧 actor 迁移不在当前工作范围。
- 从少量低速动态场景开始，同时保留静态 episode；随后加入同场静态/动态混合。
- 第一版用显式速度估计器 + MLP actor；GRU/历史网络属于可选实验。
- 当前只实现高柱/高度重叠范围内的 XY C3BF 与水平绕行；有限高圆柱飞跃和球体 3D C3BF 均为后续独立阶段。
- 不重写整个 NavVel、不切换动作空间、不更换飞控、不引入视觉/雷达、不恢复球堆主线、不修改历史冻结实验。

## 2. 已核实的项目基线和修改风险

代码基线：外层仓库 HEAD `8388713`，嵌套 `OmniDrones` HEAD `1a62313`。HEAD 不包括未提交修改，实际实施前必须再次记录状态。

| 层 | 当前证据 | 本阶段含义 |
|---|---|---|
| 圆柱 profile | `OmniDrones/cfg/profiles/NP-dual-p1-n8.yaml`：shape=cylinder、K=4、obs_safety=none | 30 维主干 + 4×7 维圆柱槽 = 58；不是当前默认 sphere-stack 配置 |
| 槽位 | `nav_vel_obstacles.py::_build_obs_cylinder`：rpos(3)、SDF(1)、normal(3)，按 SDF 选最近 K 个 | 无速度通道；跨帧槽号不等于物体身份 |
| 几何 | 同一参考 profile 的 cylinder_radius=0.4243，高度范围并非固定 1.2/2.5m | 新尺寸是几何分布变化，应与“运动带来的变化”分开验证 |
| 课程 | 参考 NP profile 禁用 curriculum；圆柱路径锁定密度 | 不能仅把 enabled 改为 true，必须恢复圆柱数量调度与固定容量 |
| PPO | `learning/ppo/ppo.py` 已有 priv_critic，但额外输入为 agents.intrinsics | 需要专属障碍物特权状态及 collector/GAE 数据链 |
| CBF | 当前圆柱 `cbf_geom()` 用虚拟球保持距离及法向 | 不能把虚拟球心直接代入依赖真实相对速度的 C3BF |
| 动作链 | nominal policy → CBF → CmdGaussNoise → VelController → 低层控制器 | filter 之后的噪声、限速可能破坏约束，需要新路径明确语义 |
| 限速 | `VelController` 限制三维速度范数，并对第 4 个动作做 yaw 缩放 | 速度球不是三个独立分量上限；原 yaw 语义保持不变 |
| 时间循环 | `IsaacEnv._step()` 每个 physics substep 调用 `_pre_sim_step()` | 运动不能重复按 policy dt 积分；物理与控制时钟必须区分 |
| 物理柱体 | 圆柱创建/缩放代码记录 PhysX 克隆尺寸可能与解析几何不同 | 渲染正确不证明 collider 正确；需检查位姿和尺寸，解析碰撞继续独立验收 |
| 终止/统计 | 历史报告存在 arrival、strict success、碰撞余量等不同口径 | 采用明确定义的一局一命和互斥终止原因，不沿用宽松训练到达率作验收 |

历史参考：`Navvel_dynamic_obs_plan.md` 中的 62 维、方柱主线、actor 真速度、双机同时开展等假设不适用于本计划；本文对当前阶段优先。该旧文件不删除也不改写。`C3BF_dyn.md` 作为数学起点，不当作已验证的完整工程实现。

### 2.1 项目执行路径与依赖

项目是 Python/Torch/TorchRL PPO + Isaac Sim 的 Crazyflie 速度控制导航环境。入口为 `scripts/train.py`、`scripts/eval_ckpt.py`，Hydra 实际根配置为 `scripts/train.yaml`（`config_path="."`、`config_name="train"`），经 `hydra.searchpath: file://../cfg` 加载完整 task profile；CPU 纯逻辑验证与 Isaac/CUDA 集成验证分开。

环境拥有目标、障碍状态和 episode 生命周期；ObstacleManager 拥有解析几何；transform 拥有过滤及控制动作链；PPO 拥有 actor/critic、GAE 和更新。不把运动、估计、CBF 和网络全部塞入 `nav_vel.py`。

### 2.2 配置、初始化与兼容边界（接口复核补充）

- `cfg/task/profiles -> ../profiles` 提供 `task=profiles/<name>`；新增动态配置仍保留 `name: NavVel`，不因 profile 名不同就新增 Task 类。
- `algo=ppo` 来自 `learning/ppo/ppo.py::PPOConfig` 的 ConfigStore 注册，不存在 `cfg/algo/ppo.yaml`。新增 critic 配置应修改 dataclass/消费端并给兼容默认值；独立配置组合工具先加载相同注册，不另造同名 YAML。`priv_actor` 主线保持 false。
- 新运动/观测/CBF 行为由显式动态 profile 开启；旧配置读取用 `.get(..., default)`，默认关闭新行为，不批量改写冻结 profiles。兼容层 `torchrl/compat.py`、`tensordict_compat.py`、`views` 与 rotor/控制器模型不在本阶段修改范围。
- NavVel 在 `super().__init__` 前解析 M/K/观测宽度；父类会调用 `_design_scene`、`sim.reset()`、`_set_specs()`，而 ObstacleManager/物理 view 在返回子类后才初始化。因此 spec 不能依赖尚未创建的 tracker/manager 实例，先由配置计算固定形状，再初始化状态对象。
- 圆柱容量改动必须同时检查 `scene_slot_count()`、`obs_slot_dim()`、NavVel prim 数、ObstacleManager.M 和 view shape。每局 active 数可以变，M 不变；严禁只修改 `num_scene` 就假定圆柱容量跟着变化。
- `set_world_poses` 的障碍物位置需加 `envs_positions`，解析几何/跟踪/观测保持环境局部世界系；只改变平移原点，不旋转速度。测试两个不同环境原点下相同局部场景的等价性。

### 2.3 两份参考文档的冲突与采用口径

本计划引用两份文档作为索引，但以下细节以已核对代码为准；此次不修改那两份文档：

| 文档表述 | 代码核对结果 | 本计划处理 |
|---|---|---|
| Summary §18.2 将 transforms 列表写为 `[InitTracker, CBF, Noise, VelController]`，同时称逆序执行 | `train.py` 实际追加顺序是 `[InitTracker, VelController, Noise, CBF]`（省略可选观测变换） | 区分列表顺序与实际执行顺序，不照抄矛盾列表 |
| Interface §10 称 Transform 在 obs 与 reward 之间执行 | `IsaacEnv._step` 内 obs 后紧接 reward；动作 inverse transform 在进入 base step 前执行 | CBF 决策缓存与 next-state info 分离，见 §3.4 |
| 两份文档多处将 rollout 标成 `(T,N,...)` | 当前 `GAE.forward` 明确沿 `shape[1]`、`reward[:,step]` 递推，train evaluate 同样按 dim=1 取时间 | 现有调用契约按 `[B,T,agent,...]` 核对；运行时断言，不能仅凭 einops 中的字母名称推定时间轴 |
| Summary §37 暗示 `fake_tensordict()` 会立即发现实际观测与 spec 不一致 | `fake_tensordict()` 根据 spec 造假数据，`run_type_checks=False` | 假数据/LazyLinear 初始化只是第一层检查，必须增加真实 reset/step spec 对照 |

这些修订不改变用户已确认的任务目标，只收紧后续实现的接口与验收要求。

## 3. 架构与接口约定

### 3.1 数据流

```text
轨迹参数、随机种子
  → 障碍物真状态 p/v/a ─→ 解析几何、碰撞/奖励、特权 critic
          │             └→ Isaac kinematic 障碍物位姿
          ↓
带时间戳的位置测量模拟 → 估计器 → 估计 p/v、age、valid、误差界
                                           ├→ actor observation → nominal action
                                           └→ 动态 CBF 约束生成
nominal action → 可配置命令扰动 → 动态安全投影 → 速度控制器 → 无人机物理状态
```

新路径建议将可建模的命令扰动置于最终过滤之前；不可消除的执行误差作为鲁棒性对象。旧静态路径保持原顺序以复现历史结果。必须同时保留 raw policy action、filter input、safe command 和实际 controller target，不能混用。

动作 inverse transform 按列表逆序执行。若新执行顺序为 `policy → noise → dynamic filter → VelController`，对应追加顺序为 `VelController, dynamic filter, noise`；其中 raw action 必须在 noise 改写前单独捕获，不能继续假定 filter 入口就是原策略输出。实际实现可用小型记录 transform 或等价明确接口，需在 train/eval 的含噪/无噪模式分别验证。

保持第 4 维现有语义：控制器接收 `target_yaw=action[...,3]×π`，是目标偏航角；配置名 `max_yaw_rate` 在这条路径不能按名字解释成 yaw-rate 动作。策略前三维是 m/s 的无界 Gaussian 输出，经限制后才可执行，不是 [-1,1] 电机归一化输入。

### 3.2 公共状态契约（拟新增接口，名字在 M0 冻结）

设 B 为环境数，M 为固定障碍物容量，K 为 actor 观测窗口容量，C 为约束容量。

| 数据 | 形状/类型 | 约定 |
|---|---|---|
| obstacle position/velocity/acceleration | `[B,M,3]` float | 环境局部世界系，m、m/s、m/s²；圆柱 v_z=a_z=0 |
| active、is_dynamic | `[B,M]` bool | 静态物体 active=true、is_dynamic=false、v=a=0；未激活不等于静态 |
| object_id | `[B,M]` integer | episode 内稳定；reset 后清理历史和跟踪状态 |
| radius、half_height、shape_type | `[B,M]` | 圆柱中心 z=(z_lo+z_hi)/2；球体阶段独立解释几何字段 |
| measured position/time/valid | `[B,M,3]` / `[B,M]` | 采集时间与收到时间分开，不能用到未来样本 |
| estimated p/v、age、valid | 同物体容量 | 所有需要在决策时比较的状态对齐到同一时刻 |
| actor observation | `[B,1,D_actor]` | 不含仿真真 v/a、轨迹未来、不可获得动力学真参数 |
| critic state | `[B,1,D_critic]` 或显式物体集合 | actor 信息 + 真状态，mask 明确；不复用 intrinsics 塞入无关语义 |
| A、b、constraint_mask | `[B,C,3]`、`[B,C]`、`[B,C]` | A u≤b；无效约束不参与求解/指标 |
| projection result | u、feasible、residual、status | 区分已安全、已修正、不可行、数值异常、超时 |

保持张量 device/dtype 一致；每步不做逐环境 CPU 循环、`.item()` 同步或 USD 属性重建。actor 的 K 与几何/CBF 的全 M 分开：actor 窗口裁剪不能悄悄裁剪安全检查。

新增字段同时登记生产者、消费者及 spec：

- 动态 filter 输入建议新增 `info.obstacle_dynamic` 子字段（含 p/v、几何、mask、误差界），不把旧 `info.obstacle_cbf=[center,r]` 的 4 维槽原地扩宽，避免旧 factory/transform 误读。
- critic 特权信息使用独立 `agents.critic_state`（拟议名）；actor 只读取 `agents.observation`。保留 `info.drone_state` 的 13 维控制器契约；CBF 所需估计状态另设字段，不能为了感知噪声直接覆盖所有低层控制器的真状态输入。
- `info`、`stats` 虽位于 observation_spec 下，并不属于 actor 观测；ravel/encoder 必须使用显式 in_keys，不能展平整个根 TensorDict 导致真值泄漏。
- `PPOPolicy` 使用 `observation_spec.zero()` 初始化 LazyLinear；新增 critic 字段必须在构造前就出现在 spec，并在 reset、step、next、terminal、minibatch 中完整传播。
- collector 配置 `return_same_td=True`；跨迭代保存验证样本、失败轨迹或离线数据时 clone 必要字段，不保存将被下一轮覆写的引用。

### 3.3 一步内的时序

1. 在 t_k 获取/发布已到达的测量，按时间戳更新估计器，生成 actor 观测和当前 CBF 输入。
2. actor 产生动作；CBF 对同一决策时刻的估计状态生成约束并过滤。
3. transform 在进入 base env 前完成，`_pre_sim_step` 此时读到的是 rotor command，不能再次作为速度过滤。physics substep 用实际物理 dt 推进障碍和无人机；核对 kinematic API 是目标设置还是瞬移，以及状态与 collider 的时间对齐。
4. `_compute_state_and_obs` 先发布 t_(k+1) 状态/下一拍 info，随后 `_compute_reward_and_done` 计算转移奖励：碰撞/进度使用新状态，CBF 动作奖励使用缓存的 t_k 约束及 nominal action。两者之间没有 action transform。保存 terminal observation，正确区分 terminated/truncated 的 bootstrap。
5. reset 只影响指定环境；清空估计器、轨迹时钟、CBF 状态、观测历史与统计。已结束的评估环境不再污染指标。

仿真频率、policy 频率、动捕频率、估计输出频率分别配置。控制 dt 不必等于物理 dt，也不能默认动捕每个仿真步都有新帧。100–120Hz 的测量模拟使用时间戳驱动；若物理步为 10ms，需用可解释的连续轨迹取样/插值在测量时刻生成状态并模拟到达，不能把 120Hz 简单截成每个物理步一帧。无人机测量也需时间一致；频率 DR、相位、时钟抖动与链路延迟分开。

### 3.4 决策缓存与 bootstrap 的具体契约

**CBF 奖励缓存：**当前旧 reward 在 step 后使用新 `drone_state`/障碍几何重新调用 `cbf_violation/filter_velocity`，且对 nominal 使用逐分量 clamp；这不等于对刚刚执行的 filter 决策计算奖励。动态分支应在 t_k 保存不可变的 nominal、A/b 或已计算的违反值、nominal projection/correction、有效 mask、solver status、决策时间/step ID。`_pre_sim_step` 在物理推进前接收缓存，reward 在 t_(k+1) 消费一次；新 obs 更新下一拍 info 不得覆写上一拍缓存。旧路径保留原行为以便回归。

所有模式（Dual、Filter-only、Reward-only、Nominal、OFF 无 filter）都要捕获原 policy action，用于 PPO 核对和动作平滑统计，不能依赖 CBF transform 存在才写 `policy_action`。`substeps>1` 时动作缓存/前一拍动作只更新一次，运动积分每 substep 更新；否则当前每 substep 更新 prev_policy 的写法可能让平滑差值变为零。

**终止与 GAE：**当前 `PPOPolicy.train_op` 使用 `next.terminated`，`GAE` 又以同一 mask 同时控制 TD bootstrap 和递推；不是已经具备独立的 episode 截断处理。新增模块必须用一条批内“timeout → reset → 新局”的合成序列核对：terminated 禁止 bootstrap；时间上限是否 bootstrap 按任务定义冻结，若允许应使用结束前 terminal critic state；GAE 递推不能跨 reset 接到下一局。若现有实现出现跨局传播，在动态训练路径增加单独的 trace-boundary mask（done/traj ID），保留旧模式，并记录它属于学习语义修复。不能把所有 truncated 一律改成 terminated 来掩盖问题。

`IsaacEnv._reset` 会再次调用 `_compute_state_and_obs`，包括部分 reset 场景；估计更新应按时间戳幂等，不能对未 reset 环境重复摄入同一帧或推进运动时钟。`progress_buf` 是 policy-step 计数，秒级时间取 `progress_buf×physics_dt×substeps`，tracker 另外维护测量事件时间。

## 4. 几何、运动与观测设计

### 4.1 圆柱和高度

新场景建议圆柱竖直、底部贴地、episode 内高度与半径固定，只有 XY 平移。先不加入旋转、竖直移动或在线尺寸变化。

当前场地保持 x/y∈[-3,3]m、z∈[0,3]m 的物理范围，另设含机体尺寸/裕量的可用范围和本阶段导航高度带。推荐主训练先使用 2.5m 高柱，导航高度上限低于柱顶并留余量，保证 OFF 策略不能通过飞高逃避绕行任务。仍保留现有 3D 速度动作和垂直稳定能力，不将任务暗改为固定 u_z=0。导航高度限制必须在 OFF 评估中也成立，并记录高度越界，不用隐藏在线 CBF 实现。若现在保留 1.2m 柱，则导航带也需低于低柱顶部；否则低柱仅留作后续阶段。

以下仅为**后续飞跃阶段**的条件，以无人机中心高度上限 z_max 和垂直有效半尺寸 r_z 为准：

```text
低柱有可飞跃空间：1.2 + r_z + margin_z < z_max
高柱无可飞跃空间：2.5 + r_z + margin_z ≥ z_max
```

M0 同时对齐起点/目标采样高度、场地边界、导航高度带、奖励边界及测试配置，避免限制导航高度后旧采样器生成非法状态。几何接触、膨胀净空侵入、CBF 违反分别统计；改变 collision_margin 不应被误报为碰撞能力提升。

### 4.2 运动模型与场景

- 硬约束为 `norm(v_xy)≤v_max`、`norm(a_xy)≤a_max`，不是逐分量裁剪后假称满足范数上限。
- 初始轨迹采用直线长匀速段 + 有界加速度启停，随后加入平滑转向、停走、圆弧。
- 不使用瞬时反弹、episode 中瞬移、无穷加速度的三角波拐点；截断速度后应重新核对积分位置和加速度的一致性。
- 圆周/正弦参数必须联合检查速度、加速度峰值；更复杂 jerk 限制可后置。
- 起点安全不仅是无几何重叠，还应过滤已经无法在控制限制内规避的迎面初态。
- 轨迹不得穿越墙体或静态柱；多动态柱相互干涉需通过行程规划或可复现拒绝采样处理，不能靠瞬时弹开。
- 固定容量、动态 active mask；无效物体不会产生风险、碰撞或观测。渲染层移走不等于逻辑停用。
- 训练要有指定交汇时刻的横穿/迎面场景，防止大量“障碍在动但从不相遇”的简单样本掩盖问题。

探索起点可用 v_max=0.2–0.4m/s、a_max=0.2–0.5m/s²，随后尝试 0.4–0.8m/s；这些不是已确认的实机能力或最终训练参数。

### 4.3 Actor 与估计器

最小对照保留原 7 维槽，加估计的障碍物 XY 速度 2 维：`30+4×9=66`。也可选相对 XY 速度；二者只选一种并固定坐标系。若用相对速度，自身速度必须在同一时刻、同一坐标系下相减。

建议可部署版本再加入 age、valid，每槽 11 维，对应 `30+4×11=74`。66/74 均为主干仍为 30、K=4、无额外安全通道时的候选维度，不先冻结新模型维数。无效槽的 mask 和 age 编码应明确，不能填 NaN/inf。

原 58 维的 30 维主干要逐项核对实机来源：rpos(3) + quaternion(4) + world linear/angular velocity(6) + heading(3) + up(3) + `throttle*2-1`(4) + relative heading(3) + time(4)。尤其 4 维 throttle 是仿真电机内部状态，不等同于上一拍速度指令或动捕信息；应明确真实遥测、可部署估计或移除方案。不可获取的状态不得直接复制真值；若移除 throttle，主干变为 26，66/74 维候选也相应变为 62/70，最终以字段来源审计冻结 schema。保留 heading/up 时使用同一姿态估计派生。底部贴地且两种固定高度时，相对中心高度可提供高度线索；显式 top/bottom 特征作为可选消融，未经决定不额外加进网络。

速度先按 object_id 从位置历史估计，再选择 K 个槽。初版用 α–β 或 Kalman 估计，位置和速度可外推到决策时刻；不通过 noisy position 二阶差分硬造加速度。首次测量、乱序帧、过期帧、短时丢帧与长时失联分别定义行为，不能把失联物体直接当不存在。

第一版先保留 SDF 最近邻选择便于隔离速度通道效果；后续添加“最近邻保底 + 短期风险补充 + 选择滞回”的消融。风险计算使用估计状态，不能借真实速度决定 actor 看见谁。CBF 使用全部有效跟踪物体或有明确保守依据的候选筛选。

### 4.4 Critic 与历史信息

critic 接收 actor 观测及额外真 p/v/a、几何、active mask，可选真实动力学参数。轨迹生成器有隐藏相位/目标时，应明确当前 p/v/a 不一定构成完整 Markov 状态；必要时给 critic 加生成器状态，不默认提供未来随机噪声序列。

初版以固定 M 的带 mask 集合编码/展平实现最小可用版本，避免每个课程等级改变网络维度。actor 导出不依赖 critic 字段。若以后采用 recurrent actor，应把对应历史/隐状态提供给 critic 并核对训练理论及 bootstrap，不能认为特权真值自动解决所有部分可观测问题。

## 5. C3BF 分阶段实现与边界

### 5.1 M4a：高柱 XY 碰撞锥

对真实圆柱 XY 中心构造：

```text
p_rel = p_obs_xy - p_uav_xy
v_rel = v_obs_xy - v_uav_xy
R = r_cylinder + r_uav_xy + margin
rho = sqrt(dot(p_rel,p_rel) - R²)
h = dot(p_rel,v_rel) + rho * norm(v_rel)
q = p_rel + rho * v_rel / norm(v_rel)
b = dot(q,v_uav_xy)
    + tau * [norm(v_rel)² + norm(v_rel)/rho * dot(p_rel,v_rel)
             + dot(q,a_obs_xy) + gamma*h]
[q_x,q_y,0] dot u ≤ b
```

使用真实物体中心，不能使用 `cbf_geom()` 的位置依赖虚拟球心。静态柱用 v_obs=a_obs=0 可走同一新动态接口；其结果不要求与旧距离 CBF 一样，因为屏障本身已经变化。

一阶速度环 `dot(v)=(u-v)/tau` 是近似。tau 应辨识整个速度闭环，不能取电机时间常数；若 XY/Z 时间常数不同，需要改控制系数推导，而非随意选一个标量。

### 5.2 加速度不确定性与数值条件

部署初版可取 a_hat=0，但必须明确轨迹启停/转向时 a_obs≠0。如果已知 `norm(a_obs_xy-a_hat_xy)≤Delta_a`，在其他状态准确的条件下：

```text
b_robust = b(a_hat) - tau * norm(q_xy) * Delta_a
```

该式仅覆盖加速度误差；位置、速度、时延、tau 失配和下层跟踪误差要单独建模、标定或压力测试。虽然最终部署不运行 filter，训练期 filter 仍建议使用部署同源估计及误差界，以减少依赖 actor 看不到的真值所造成的训练分布偏差。critic 知道真加速度不意味着该估计过滤器读取真加速度；oracle filter 仅作为显式标注的训练/诊断对照。

必须处理 `v_rel≈0`、`d≈R`、`d≤R`、退化 q、相关约束与空约束集。平滑速度范数会改变原碰撞锥安全集合，rho 截断也改变边界附近的导数；文档示例的 eps 处理不构成自动安全证明。对已在膨胀区内的状态输出异常/恢复状态，不能跳过约束后报告安全。

### 5.3 投影与真实执行约束

共用优化目标为最小化 `||u-u_nom||²/2`，满足 `A u≤b` 和实际可执行速度集合。

- 当前 `norm(u_xyz)≤u_max` 是球约束，不能直接用仅支持线性半空间的 active-set 枚举就宣称完整求解。
- M4a 可以验证半空间 + 球约束的专用求解器；CPU oracle 用于核对，不要求直接部署通用重型 solver。
- 备选是明确使用保守内接多面体/分轴预算，承认其缩小速度集合并单独测试；不能静默改变控制器语义。
- 若保持 u_z 不变，XY 可用速度预算为 `sqrt(u_max²-u_z²)`，但高度/边界约束可能要求联合修改 u_z，最终以三维执行可行性为准。
- 文档的 1/2/3 active-set 枚举可作纯半空间参考实现；不在大批量 GPU 每步使用 Python 穷举全部组合。性能验收后再决定批量算法。
- 解后检查全部约束残差及实际 controller target，记录不可行率、求解耗时和超时率。
- 不可行时定义恢复策略和状态，区分软约束违背与硬安全满足；“置零悬停”不是动态场景的通用安全解。
- 加入飞行高度/墙体边界处理，避免障碍物过滤改善碰撞却导致 OOB/掉高；这些约束同样需要考虑速度环滞后。

PPO 的 log_prob 对应 raw sampled action，不能用投影后的 action 假装是 Gaussian 直接采样结果。环境按实际执行动作产生状态转移；训练数据需保留两者。

### 5.4 M4b：有限高柱的飞跃（后置，不属于当前交付）

`v_obs,z=0` 不意味着 `v_rel,z=0`。始终启用 XY 圆盘约束相当于无限高柱，会阻止合理飞跃；仅按当前高度开关也可能允许下降撞顶。

本模块需单独比较并选择：

1. 高度区间预测 + XY 约束门控 + 独立垂直安全约束/恢复策略；必须有切换滞回、上升/下降可达性、延迟覆盖。
2. 为有限高圆柱推导匹配速度环的三维屏障约束，并验证棱边/顶面非光滑区域。

正式选择前先用确定性升越、顶上下降、擦顶、侧顶交界、门控抖动场景判断。只做经验门控时标注经验安全策略，不声称沿用原 C3BF 连续安全保证。不能用恢复多层球替代用户指定的圆柱主线。

### 5.5 下一阶段 M4c：三维移动球体

使用真实球心和完整三维 p_rel/v_rel/a_obs 构造约束，复用估计接口和投影器；增加球体 shape_type、三维速度观测及新 schema。单独考虑机间有效半径、机体姿态包络和下洗，不能认为球碰撞模型覆盖了全部无人机间相互作用。

## 6. 奖励、课程与从零训练

### 6.1 奖励修改原则

主任务保持到达/碰撞/越界/超时语义明确。先改必要的动态项，再做附加 shaping，避免把新场景、网络、奖励同时改到无法归因。

**CBF-RL 对应关系：**已阅读用户提供论文 §IV、Eq.18–23 和 Algorithm 1。主线为 Dual：训练执行过滤后的动作，同时用 nominal 违反项和 Gaussian correction 项提供奖励；最终执行原 actor 动作，不调用 runtime CBF。论文的单积分器单约束闭式解和离散安全条件不能直接视为本项目一阶速度环、多动态约束的证明。

采用本文 `A_i u≤b_i` 符号时，对 nominal action 定义 `c_i=b_i-A_i u_nom`，候选奖励为：

```text
r_cbf = w_v * aggregate_i[min(c_i / scale_i, 0)]
        + w_c * (exp(-norm(u_nom-u_projected_nom)² / sigma²)-1)
```

`u_projected_nom` 是在相同约束下对 nominal 动作的投影；命令 DR 若先扰动动作再执行过滤，不能把“纠正外加噪声”全部罚给 actor，需单独计算 nominal shadow projection 并记录额外成本。无命令 DR 时两次投影可共用。多约束聚合与尺度归一化是项目扩展，M6 冻结；不能任意缩放 A/b 后保持约束相同却让奖励尺度漂移。Gaussian correction 项位于 [-1,0]，但完整奖励中的线性违反项并非因此也有界。不可行状态需独立奖励/终止约定，不能将未定义投影当作正常安全标签。

训练 filter 默认每步启用，定期独立运行 OFF 评估；先不加入概率退火。若 OFF 长期没有改善，再将按 OFF 指标控制的退火或无过滤训练片段作为明确消融，不能将其冒称为论文原始流程。

1. 当前 near_slowdown 使用自身朝最近柱中心的速度；改为基于真实相对运动的接近程度。圆柱优先采用 SDF 外法向 n（从障碍表面向 UAV）计算 `closing=max(0,-dot(n,v_uav-v_obs))`；球形可用 `max(0,-dot(p_rel,v_rel)/norm(p_rel))`。
2. 奖励/碰撞可用真值，actor 特征只能用估计；若奖励项刻画“部署过滤器修正”，必须使用该估计过滤器实际修正，不混入 oracle。
3. CBF nominal violation 与 correction 分开记录；更新约束后重新标定权重，不沿用旧距离 CBF 量纲与阈值。raw 动作和带扰动 filter input 各自指标明确。
4. 等待、暂时远离目标可以是合理动作；不新增无条件低速惩罚。用任务完成与超时区分让行和长期停滞。
5. 短时预测净空惩罚为可选消融，不作为首轮训练必选项；不要用 TTC 单独替代几何碰撞。
6. 障碍物求和奖励随数量增长，需明确 sum/mean/max 或饱和聚合选择，记录各分项尺度。
7. 新从零训练 profile 若启用 proximity log 项，显式设置 `obstacle.reward_obs_log_mode: penalty`（若权重为零也写明该设置），避免继承默认 legacy 的反号奖励；这是新实验定义，不回写旧 NP profile。审核 reward_scheme、proximity 开关及各分项，历史臂不一定采用同一奖励。PBRS 若启用，核对折扣、终止和势函数约定。

### 6.2 课程设计

| 阶段 | 场景 | 本阶段主要变化 |
|---|---|---|
| D0 | 新接口静态场景，另保留旧几何回归 | 验证静态兼容与新尺寸影响 |
| D1 | 1–2 个低速动态高柱；约 20%–30% 静态 episode（建议值） | 学习相对运动 |
| D2 | 少量静态 + 动态同场，低速保持 | 学会受限空间绕行/让行 |
| D3 | 逐步增加活动物体数量、动态比例 | 密度课程，固定容量 M |
| D4 | 数量固定，增加速度，再增加加速度/轨迹复杂度 | 运动课程 |
| D5 | 维持水平绕行，逐步增加感知/控制 DR，在全部目标档位进行 OFF 验收 | 本阶段部署鲁棒性；低柱飞跃另开阶段 |

课程应支持锁档评估、resume 状态、最小采样量、按类别成功/碰撞统计。升级门槛不能被大量简单静态 episode 稀释；速度/数量等档位变化仅应用到新 reset 的 episode，不在进行中的场景瞬间改速或增障。

参考旧成功率 0.80、碰撞率 0.05 只能作为训练升级阈值的起点，不是实机安全验收标准。CBF 常开训练时 ON 成功率不能证明 actor 已独立学会避障。本项目明确脱离 filter 为目标，因此周期性固定场景 OFF 验证必须参与升级：用独立验证环境/结果回传，不把 ON rollout 指标冒充 OFF。选择最佳 checkpoint 也按 OFF 安全与成功联合指标，不能只按训练 return。

**OFF 验证实施方式：**现有 `train.py::evaluate()` 复用训练 env，调用 eval、set_seed、rollout、reset，且不会自动把 CBF 切成 OFF；不能直接拿它的指标驱动新课程。Isaac stage、`RobotBase._robots` 和环境原点是进程级共享状态，`IsaacEnv.close()` 当前为空实现，不能直接在同进程再构造第二个独立 NavVel。

M7/M8 默认实现独立评估进程：训练导出带 ID 的模型快照与冻结配置，评估进程锁档、MODE 动作、runtime_filter=false，返回 checkpoint ID、课程档位、schema/config hash、场景种子和指标。训练在后续迭代边界读取完整结果，只在下一次 episode reset 应用课程改变；拒绝错档/错 schema/过期结果。评估不更新训练课程、不消耗训练 RNG，不持有 collector buffer 引用。执行时评估与训练的 GPU 占用要限额，优先串行安排；若剩余 GPU 内存不足，需在训练批边界保存 bundle 并退出训练进程释放显存，评估后按已定义的 episode 边界恢复；仅暂停采样不会释放 Isaac 显存。不临时在训练 env 上 reset 冒充独立评估。

### 6.3 从零训练与 checkpoint 契约

本阶段从零训练，不实现旧模型迁移。以下兼容性规则用于后续模块间继续训练和未来有明确需求时的迁移，非当前必做工作：

- 只改奖励且输入/动作不变：actor 权重仍可用；旧 critic 对旧回报拟合，宜重置或明确重新拟合。
- 58→66/74：按字段迁移首层权重，新增通道可初始化为零；按槽插入字段后不能简单复制前 58 列。
- actor 主干不变时可以迁移兼容层；critic 特权分支新增时默认重建 critic。初始化 std 单独记录。
- 跨任务迁移默认重置优化器、学习率日程、回报归一化统计、课程窗口及旧 rollout；观测统计仅迁移语义相同的字段。
- 当前 `train.py` 保存 `policy.state_dict()`，包含注册模型参数/buffer（含 ValueNorm），但不保存普通属性中的 Adam 状态、collector、课程、环境与 RNG；现有 `+init_ckpt` 仅加载权重，不是精确 resume。新训练恢复需单独实现 M7 的训练状态 bundle，并标注为 episode 边界恢复；不要求本阶段对 Isaac 物理轨迹逐位重现。跨 schema warm-start 后置，不能用 `strict=False` 静默掩盖缺失键。
- checkpoint 保存 obs/action/reward/geometry schema、resolved config、种子、代码版本、训练帧数、迁移来源与字段映射。导出后实机端同步 schema，重新离线对拍。

M7 训练状态 bundle 的最小内容为 actor/critic/ValueNorm、两套 Adam、累计 frames/iteration、课程档位与窗口、已消费 OFF 结果 ID、Python/NumPy/Torch CPU/CUDA RNG、schema/config hash。恢复时从新 episode 重启环境并清空 tracker/轨迹，明确这不是逐轨迹精确恢复；未完成 episode 的统计不得混入课程窗口。模型推理 `state_dict` 与训练 bundle 分开存储，旧评估器只读前者；已有 state_dict 可以保留，不能伪造其中不存在的优化器或采样状态。

### 6.4 分阶段实验矩阵

先做最小因果对照，避免一开始开展大规模全组合：

| 实验 | Actor | Critic | 目的 |
|---|---|---|---|
| E0 | 新接口，静态速度为零 | 对称 | 静态回归和新几何基线 |
| E1 | 动态位置 + 估计速度 | 对称 | 可部署动态基线 |
| E2 | 同 E1 | 特权真状态 | 隔离非对称 critic 的收益 |
| E3（后置） | 同 E2，可选历史网络/风险选槽 | 同 E2 | 逐项消融，不同时加入 |
| 消融（后置） | 与 E2 相同且从零训练 | 与 E2 相同 | 固定网络比较 Dual / Filter-only / Reward-only / Nominal；预算不足先保留 Filter-only 对照 |

E1/E2 均使用训练期 filter + reward 的 Dual 模式，固定奖励、课程及初始化协议。OFF 是主结果，ON 衡量 filter 能补救多少。每个选定模型都做 ON/OFF 配对测试；oracle 估计/过滤只作诊断上界。初期短试验单 seed 排错，正式结论建议至少 3 个训练 seed，并使用独立测试布局/轨迹种子，具体预算待定。

## 7. 模块实施清单与验收

下表中的新文件名均为建议，不表示文件已经存在。现有旧模块优先增加显式新分支/薄接口，纯逻辑提取为小模块；不做无关重构。

| 模块 | 依赖 | 主要修改面 | 交付及完成判据 |
|---|---|---|---|
| **M0 基线与契约** | 无 | 本文；新 profile/schema 清单；只读核对旧配置与 checkpoint | 确认 Q4/Q5、58 维逐字段来源、动作/碰撞语义和从零训练 profile；保存基线命令和结果 |
| **M1a 纯运动状态** | M0 | 独立纯 Torch `envs/single/nav_vel_motion.py` 与 CPU 行为测试；不接入 ObstacleManager/NavVel | XY 轨迹、active mask、固定容量、可重复随机种子；v/a 上限和位置导数一致 |
| **M1b Isaac 同步** | M1a | `nav_vel.py::_pre_sim_step/_reset_idx`、柱体 prim/view、必要的 dt 接口 | 每物理步逻辑/渲染/collider 位姿对齐；尺寸核实；局部 reset 隔离；静态不漂移 |
| **M2 测量与估计** | M1a | 建议 `utils/obstacle_tracking.py`；测量模拟薄接口 | 时间戳、延迟、丢帧、初始化；真值隔离；估计误差与滞后报告 |
| **M3 Actor 观测** | M0、M2 | `nav_vel.py::_set_specs/_compute_state_and_obs`、`nav_vel_obstacles.py::build_obs`、导出输入契约 | schema 与实际宽度一致；按物体估速；mask、排序、选槽可测；actor 不读特权字段 |
| **M4a XY CBF** | M0、M1a；部署式接入依赖 M2 | 建议 `utils/c3bf.py`、`utils/safety_projection.py`；旧 cbf factory/transform 薄适配；train/eval 对齐 | 高柱动态约束、速度球和边界、不可行诊断；CPU oracle 对拍；GPU 批量性能合格 |
| **M4b 低柱飞跃（后置）** | M1b、M4a | 有限高几何约束/门控独立模块及对应配置 | 升越/下降/侧顶切换/延迟确定性测试通过；说明保证范围与残余局限 |
| **M5 特权 Critic** | M3；真值来自 M1 | `learning/ppo/ppo.py::PPOConfig`/网络、env specs、collector/GAE 契约（`learning/ppo/common.py`）、export | actor 不变；current/next/terminal critic state 齐全；时间轴/终止测试通过；保存加载和纯 actor 导出可用 |
| **M6 奖励** | M1、M4a；可先做纯函数 | `nav_vel.py::_compute_reward_and_done`、建议独立 reward helper、新 profile | 相对接近符号正确；等待可行；nominal/correction 来源明确；分项可追踪 |
| **M7 课程与从零训练** | M3、M6；非对称依赖 M5；过滤依赖 M4 | `utils/nav_curriculum.py`、圆柱采样、`scripts/train.py`、新 profiles、独立进程 OFF 验证回传、训练状态 bundle | 圆柱数量/速度实际变化；锁档/reset/episode 边界恢复正确；从零训练可复现，OFF 参与升级 |
| **M8 评估与部署契约** | 随模块逐步完善；最终依赖前述模块 | `scripts/eval_ckpt.py`、`play.py`/`demo_fly.py` 能力检查、独立动态评估入口/报告、导出与跟踪适配 | 场景配对、互斥终止、各类碰撞/估计/CBF 指标齐全；离线 sim/deploy 对拍 |
| **M9 三维球体阶段** | 圆柱阶段稳定后 | sphere3d 运动/几何/观测 + M4c 约束生成 | 三维交叉运动独立训练验收；不是本轮代码交付范围 |

建议交付顺序：`M0 → M1a → M1b → M2 → M3 → M4a → M5 → M6 → M7`；M8 的测试夹具从 M1 开始建设，M4b/M9 仅作后续路线，不阻塞当前水平绕行交付。依赖允许的独立工作不代表自动并行启动子代理或训练任务。

每次只交付一个可审查模块或子模块，附修改文件、输入输出契约、实际运行的检查、剩余问题和下一模块入口。模块通过后再扩大集成范围，不以“一次训练能启动”代替正确性。

跨入口规则：M4/M8 搜索 `train.py`、`eval_ckpt.py`、`play.py`、`demo_fly.py` 的所有速度 transform 组装点。实际支持动态任务的入口接入相同 factory/契约；暂不支持的入口遇到动态 schema 应显式报错，不能静默运行旧静态过滤器。不要求为此扩展所有历史批量脚本，但模型登记/报告中写死的 58/62 维检查须识别新 schema。

## 8. 验证分层、评估指标与停止条件

### 8.1 CPU 纯逻辑与契约测试

应覆盖真实行为而非镜像实现：

- M1：静止、直线、平滑转弯、触边前减速；数值导数与声明 v/a 对比；部分 reset；不同 seed；活动数量与容量。
- M2：已知匀速/加速轨迹上的估速误差；不同采样率、延迟、丢帧、乱序、ID 更换；不得访问未来样本。
- M3：58 维旧 schema 保持；新宽度精确；静止动态物体 valid=true；槽位交换不产生速度尖峰；真值变化但测量相同时 actor 观测不变。
- M4：CBF 导数有限差分核对、单约束解析投影、同向/迎面/横穿、多约束、无约束、退化/不可行、速度球、解后残差；鲁棒收紧符号与方向；采样间穿越。
- M5：保持 actor 观测不变只改变特权输入，actor 输出不变而 critic 输入确实变化；next/terminal 字段、state_dict、actor-only export。
- M6：障碍远离不应按接近惩罚；静止无人机被迎面逼近应产生风险；当前导航高度带内 SDF 与净空合理；数量变化的奖励尺度。飞跃相关回归随 M4b 后置。
- M7：门槛边界、窗口清理、仅 reset 生效、锁档评估、resume、困难动态组不被静态组稀释。

接口复核新增必测项：

- M1/M3：`scene_slot_count`、manager.M、prim/view 数一致；平移不同 env 原点后结果相同；真实 reset/step 输出逐字段对照 spec，不能只检查 fake TD。
- M2/M3：部分 reset 重算 obs 不重复更新其他环境估计；只有 critic 真值改变时，actor 输入及选槽保持不变；电机内部状态来源明确。
- M4/M6：构造 t_k 安全但 t_(k+1) 危险及反向场景，确认动作奖励只匹配 t_k 缓存；启用/禁用 filter 均正确捕获原始动作；substeps=1/2 下同一 policy-step 平滑差值语义一致。
- M5：实际 rollout `batch_size` 与时间轴断言；合成 termination、timeout 和 reset 序列手工核对 GAE；collector 下一轮覆写不改变已 clone 的证据。
- M7/M8：独立 OFF 评估前后训练 RNG/轨迹状态不变；结果 ID/档位不匹配被拒绝；模型 state_dict 与训练 bundle 加载路径明确；episode 边界恢复不重复累计已完成窗口。

### 8.2 可复用的现有命令

以下为**将来实施时的验证命令，本文生成时未执行这些测试**。在项目 Python 环境中，从 `drones/OmniDrones/` 运行，并先确认脚本依赖与配置适用性：

```bash
python scripts/cylinder_geometry_test.py
python scripts/cbf_test.py
python scripts/test_clearance_conventions.py
python -m py_compile <changed_python_files>
```

新增模块应提供对应 CPU 脚本，例如 `dynamic_motion_test.py`、`obstacle_tracking_test.py`、`dynamic_observation_test.py`、`c3bf_test.py`；这些名称为计划，当前不能当作已有命令运行。旧 sphere/pillar 测试仅在修改共享逻辑时回归，不作为恢复旧建模路线的理由。

### 8.3 Isaac 小规模集成

- 先 1–8 个环境、有限步数，验证移动 collider/几何、时间同步和 partial reset，再提高批量。
- 使用新 profile 的实际注册名，显式设置 `max_iters`/步数和 env 数，禁用 W&B 上传；不能继承长训练默认值：实际入口 `scripts/train.yaml` 当前为 150M frames，另一个 `cfg/train.yaml` 为 250M，两者不可混淆。
- 以下仅为命令模板，尖括号必须替换为实际完成的配置，不是当前可直接执行命令：

```bash
# working directory: drones/OmniDrones/scripts/
python train.py task=<dynamic_profile> algo=ppo headless=true wandb.mode=disabled max_iters=1 total_frames=256 task.env.num_envs=8 algo.train_every=32 +render_eval=false
python eval_ckpt.py task=<matching_profile> algo=ppo headless=true wandb.mode=disabled +checkpoint=<absolute_checkpoint> +rollout_steps=100 task.env.num_envs=8 +runtime_filter=true +set_seed=1000
```

运行后记录退出码、真实步数、NaN/shape 错误、位姿残差和对应指标。CPU 通过不代表 Isaac 集成通过，进程启动不代表训练收敛。

注意：现有 `train.py` 在 `max_iters=1` 后仍无条件执行一次完整 final evaluate，`eval_interval=-1` 只关闭周期评估。上述模板限制训练 batch，不保证整个进程只有 32 步。初次接口 smoke 应另用有固定步数的动态环境脚本，或在新入口增加默认保持旧行为的 `skip_final_eval`/评估步数上限；该开关当前尚未实现，不把它写成可直接运行参数。`+render_eval=false` 仅减少渲染，不跳过 final rollout。按最大 M 检查 PhysX/GPU 容量，不随意调低已有池大小以“省显存”。

### 8.4 固定评估集

当前至少包括静态回归、单柱横穿/迎面/同向追赶、双柱交叉、混合窄通道、高柱绕行、导航高度越界、动态阻塞目标、失联/延迟、未见轨迹参数。低柱升越/柱顶下降为 M4b 后续测试，不属于本阶段验收。

主验收 runtime_filter=false：若保留 shadow filter，只能旁路输出日志，不修改动作、不改变 actor 输入或物体选择、不调用隐藏安全投影；实机 actor 控制路径不依赖 shadow solver。正常速度饱和与底层飞控仍保留，明确“无 runtime CBF”不等于移除飞控。额外给出不实例化 filter 的导出/回放检查。

训练随机种子、测试布局种子、轨迹种子、测量噪声种子分开；ON/OFF 测试复用同一外生轨迹/测量噪声计划，不能依赖 actor 行为改变随机抽样顺序而导致场景不配对。

指标包括：

- 严格成功率、到达率、静态/动态几何碰撞、净空侵入、crash/OOB/timeout；互斥终止原因之和等于 episode 总数。
- 最小净空、近失事件、相遇次数/风险暴露率、等待时长、到达时间、路径长度、绕行比例与飞高逃逸次数；正式飞跃指标留待 M4b。
- nominal 违反、filter 修正、介入率、不可行率、求解残差、实际执行后约束残差、计算时间分位数。
- 位置/速度估计误差、数据年龄、丢帧时长；按速度/数量/高度/延迟分组报告。
- filter ON/OFF 的同场景差异；区分 actor 能力与 filter 补救。

最终性能阈值在 M0/M8 根据基线、场地与部署目标冻结，不能事后随结果修改。训练课程阈值不是最终验收线。有限样本零碰撞只描述测试集结果，不表述为普遍安全保证；正式报告提供样本数与不确定性。

### 8.5 回归与停止条件

- 旧静态 profile/58 维 checkpoint 路径保持可用；新分支显式选择，不覆盖 NP/A 系列冻结配置。
- 若静态回归失败、真值泄漏、几何与时间错位、filter 输出违反实际限速或不可行被静默忽略，先修该模块，不通过加大奖励继续长训练掩盖。
- 模型指标不涨先比较状态/动作/估计/约束证据，不同时更换网络、奖励和课程。重复同一失败两次后重新分类原因。
- 有模块阻塞时继续可独立完成的模块；不把待标定参数伪装为已完成，不为写计划安装环境或更改 bootstrap。

## 9. 配置与制品清单

新增配置建议包含以下命名空间（均为拟议，不是当前已有键）：

| 配置块 | 内容 |
|---|---|
| obstacle.motion | enabled、type、speed/accel bounds、trajectory ranges、boundary policy |
| obstacle.geometry | 固定半径、高度类别、grounded、capacity、shape schema |
| tracking | measurement rate、noise、delay、dropout、estimator、stale policy |
| observation | schema/version、velocity representation、K、selection policy、age/mask |
| cbf.dynamic | model、tau、gamma、accel bound、geometry mode、solver、feasibility tolerances |
| curriculum.dynamic | count/dynamic fraction/speed/accel stages、per-group gates、static replay |
| algo critic input | privileged schema、encoder、normalization |
| checkpoint init | 本阶段 scratch/resume、schema 校验、训练状态；warm-start 后置 |
| evaluation | scene manifest、seed sets、termination semantics、filter mode、report path |

制品最少包括：resolved config、schema 字段表、场景/轨迹 manifest、checkpoint 及来源、训练 seed、评估 seed、代码状态、指标 JSON/报告、必要的失败轨迹。后续实际文件名随模块实现记录在下方台账。

## 10. 当前实施台账与下一步

```text
M0 = PASS_WITH_PROVISIONAL_GEOMETRY
M1a = PASS
M1b = PASS
M2 = PASS
M3 = PASS
M4a-core = PASS_WITH_CANDIDATE_SOLVER
M4a-core boundary constraints = PASS
M4a Dykstra solver = CANDIDATE_RUNTIME_MEASURED (preserved compatibility backend)
M4a-greedy-projection = PASS_WITH_APPROXIMATE_GREEDY_SOLVER
M4a experimental solver = greedy_most_violated, max_iters=64 (production qualification PENDING)
M4a-integration = PASS_WITH_CANDIDATE_SOLVER
M5 = PASS
M6 = PASS
M7 readiness = NOT READY
M4 solver production = OPEN_BLOCKER_BEFORE_M7_PRODUCTION_TRAINING (remaining Dual cost / nonconvergence qualification)
```

| 项目 | 当前状态 |
|---|---|
| 计划文档 | 已纳入水平绕行、训练 Dual/部署 OFF、从零训练、6×6×3m、100–120Hz 和密度/速度课程的确认 |
| M0 | `PASS_WITH_PROVISIONAL_GEOMETRY`；圆柱半径、场地/导航高度与分析几何 provisional 值已按用户决策冻结，真实 UAV z 几何与 CBF margin 仍待标定/后续决策 |
| M1a | `PASS`；独立纯 Torch 运动状态与 CPU 测试已完成 |
| M1b | `PASS`；在 `lz_env` 的 Isaac Sim 5.1 pip runtime 中完成 deterministic Isaac smoke：logical→world pose、physics dt/substeps、静态不漂移、partial reset、多个 env origin、inactive parking、capacity/view shape、USD Cylinder collider radius/height/collision-enabled 均通过 |
| M2 | `PASS`；独立纯 Torch 测量流、固定 delay/dropout/out-of-order 处理、alpha-beta 估计器与 CPU/CUDA 测试完成；经 M3 接入 actor observation |
| M3 | `PASS`；真实 `NavVelDynamicActor-v1` reset、3 次 step、partial reset 输出均为 `[B,1,70]`，dtype/device/finite/spec 对拍通过；旧 58-D cylinder path 真实 runtime 回归通过；runtime truth-isolation 未重复，CPU truth-isolation 通过 |
| M4a-core | `PASS_WITH_CANDIDATE_SOLVER`；高柱 XY C3BF、加速度误差收紧、六面 safe-center HOCBF、联合完整 XYZ 速度球、CPU oracle 与 Torch 批量 candidate solver 已通过测试；boundary constraints = PASS，生产资格 PENDING，见 §10.2–10.3；性能测量见 §10.4 |
| M4a-integration | `PASS_WITH_CANDIDATE_SOLVER`；真实动作链、全 M + 六面联合投影、四级动作、t_k cache、ON/OFF、failure policy、partial reset、train/eval factory 与 Isaac 回归完成，见 §10.4 |
| M5 | `PASS`；独立 critic_state、固定 M mask、current/next/terminal、partial reset、真实 collector 时间轴、动态 GAE 边界修复、checkpoint/actor-only export、旧 symmetric/intrinsics 回归全部通过，见 §10.5 |
| M6 | `PASS`；t_k raw nominal violation/shadow correction、noise attribution、relative closing、worst aggregation、四模式、cache/terminal/reset、真实 Isaac 和增量性能测量均通过，见 §10.6 |
| M4a-greedy-projection | `PASS_WITH_APPROXIMATE_GREEDY_SOLVER`；greedy64 显式实验后端、Dykstra兼容保留；CPU/CUDA/oracle/Isaac/static回归通过，详见 §10.7 |
| M4b / M7–M9 | 未实施；本轮完成 M4a-greedy-projection 后停止，M7 NOT READY |
| 代码/配置改动 | M1–M5 既有改动保留；M6 修改 NavVel gate/producer/组合奖励与 M4 runtime/factory，新增纯 Torch reward helper、dev fragment、CPU/Isaac/benchmark scripts 和文档；M5 schema/GAE、solver/core、旧 profiles 未改 |
| CPU/Isaac/训练测试 | M6 CPU 8项、新 Isaac reward smoke、9个指定 CPU 脚本、4个既有 Isaac regression、shadow benchmark、py_compile、内外 diff --check 全部通过；Hydra PPO training=NOT RUN、long rollout=NOT RUN、W&B=NOT USED（既有 M5 regression 含一次 synthetic optimizer smoke） |
| 下一步 | 不自动开始 M7。greedy64 将 B1024 solver p99 降至14.164ms，但 noisy Dual decision p99=30.453ms，固定1024样本中6例未收敛；先评估剩余吞吐和稳健性，生产资格 blocker 保留 |

### 10.1 RUNTIME-VERIFY 实际记录（2026-09-21）

- 正确运行环境：`/home/hybrid/miniconda3/envs/lz_env/bin/python`，Python 3.11.16；Isaac Sim pip package 5.1.0 位于该环境。base `/home/hybrid/miniconda3/bin/python` 是 Python 3.14.7，且 pre-Kit 不含 `isaacsim`/`omni`。
- 项目 launcher：`omni_drones.init_simulation_app(cfg)`，headless experience 为 `isaacsim.exp.base.python.kit`；`omni` 与 `omni.isaac.core` 只在 `SimulationApp` 启动后检查。
- 最小 probe：exit `0`；`isaacsim`、`omni`、`omni.isaac.core` 均真实导入成功。
- M1b：`/home/hybrid/miniconda3/envs/lz_env/bin/python scripts/dynamic_isaac_smoke.py task=profiles/NP-dual-p1-n2`，exit `0`；全部 `[PASS]` 与 `All M1b Isaac smoke checks passed`。
- M3：`/home/hybrid/miniconda3/envs/lz_env/bin/python scripts/dynamic_observation_isaac_smoke.py`，exit `0`；全部 reset/step/partial-reset/spec 检查通过，并输出 `RUNTIME_TRUTH_ISOLATION_NOT_REPEATED`。
- 旧 static 回归：`/home/hybrid/miniconda3/envs/lz_env/bin/python scripts/static_profile_isaac_smoke.py`，exit `0`；既有 `NP-dual-p1-n2` profile 的 motion gate、dynamic actor gate、tracker 均关闭，真实 reset/step 的 actor observation 为 58-D 且静态障碍不漂移。
- CPU 回归：`/home/hybrid/miniconda3/envs/lz_env/bin/python scripts/dynamic_observation_test.py`，exit `0`；truth isolation、partial reset isolation、CUDA smoke 通过。
- `py_compile`：runtime harness 与 `nav_vel.py` exit `0`。上述命令均未安装包、未启动训练、未启动 M4a。

### 10.2 M4a-core 实际记录（2026-09-21）

- 初始 obstacle-core 状态：当时记录为 `PASS_WITH_CANDIDATE_SOLVER`，但尚未含六面边界；按后续完整口径为 `PASS_WITH_CANDIDATE_SOLVER_BOUNDARY_PENDING`。CPU oracle = PASS；Torch batched candidate = PASS against oracle on tested cases；production performance = PENDING。§10.3 完成 boundary 后才使用当前完整 PASS 状态。完整契约/交付见 [M4a-core](OmniDrones/docs/m4a_core.md)。
- 新增：`OmniDrones/omni_drones/utils/c3bf.py`、`omni_drones/utils/safety_projection.py`、`scripts/c3bf_test.py`、`docs/m4a_core.md`（后三者同属 OmniDrones）。本轮既有文件仅更新此台账；未改 runtime、旧 CBF、58/70-D schema、M1/M2/M3、reward/PPO/critic/curriculum/profile/checkpoint。
- 新约束统一 `A u <= b`；`p_rel=p_obs_xy-p_uav_xy`、`v_rel=v_obs_xy-v_uav_xy`、`R=r_cylinder+r_uav_xy+inflation+cbf_margin`，不另加 collision_margin，不复用旧位置相关虚拟球心。独立求导与中央有限差分验证 `tau*(dot(h)+gamma*h)=b_nominal-Au`。
- `build_estimated_constraints` 只接受显式估计状态；缺省 a_hat=0 明示为 `zero_estimate`；`build_oracle_constraints` 接受显式 truth，仅用于测试/诊断。active 与 valid 分开；静态 v/a 归零。C=完整 safety capacity，不按 actor K=4 截断。
- acceleration tightening 为 `b=b_nominal-tau*norm(q)*Delta_a`，只覆盖障碍物加速度估计误差；不是完整鲁棒安全证明。tau、gamma、几何、CBF margin、Delta_a 均显式配置；u_max 显式求解参数。
- d<=R 报 inside；近边界/rho/q/相对速度退化报 recovery required；NaN/inf 报 numerical failure。失效/过期跟踪 policy=`reject`；`conservative_hold` 未实施并显式拒绝，最终存在性/失联恢复策略为 `M4A_INTEGRATION_DECISION_PENDING`。必须经 `project_c3bf` 传播状态，不能只丢掉无效约束后称安全。
- 最小化 `.5*norm(u-u_nom)^2`，联合完整 3D 速度球，**允许修改 u_z**。CPU oracle 为独立 NumPy 小规模 active-plane/球截面候选枚举；Torch 为固定预算 Dykstra，按约束行循环且整批计算，无逐环境 Python loop/`.item()`/GPU active-set 枚举。检查全部原始约束残差和对偶间隙；不可行需支持函数证据，预算不足单列 iteration_limit，失败返回诊断迭代点而非恢复命令。
- 发现并保留历史差异：旧 filter/reward component clamp 与 VelController XYZ norm clamp 不同；旧圆柱 cbf_geom 的 h=SDF-extra 未减 clearances 中 UAV radius+inflation。独立 core 不受阻；不静默修写历史路径，具体记录见交付文档 M4A BLOCKING ISSUE。
- 实际命令（cwd=`OmniDrones/`，P=`/home/hybrid/miniconda3/envs/lz_env/bin/python`）：
  - `P scripts/c3bf_test.py`：15 tests PASS，exit 0；包括 static/迎面/横穿/远离/同向近零速、退化/inside、robust 最坏方向、投影解析解/多约束/平行/重复/空集、XYZ 速度球、不可行/迭代不足区分、全约束残差、CPU oracle、CUDA。
  - 随机 oracle 对拍 B=80/C=6、seed=421、float64：最大目标差 `2.220e-15`，最大 Torch residual `3.053e-16`；另测 float32 混合可行/不可行批次。
  - CUDA core smoke B=256/C=8、float32：PASS；solver 开启 PyTorch sync-debug（原型检测，非完整性能分析）。未测生产性能。
  - `P scripts/cbf_test.py`：all PASS，exit 0。
  - `P scripts/test_clearance_conventions.py`：8/8 PASS，含已有真实 A4 日志检查，exit 0。
  - `P scripts/dynamic_motion_test.py`：all PASS，exit 0。
  - `P scripts/obstacle_tracking_test.py`：all PASS，含 CUDA，exit 0。
  - `P scripts/dynamic_observation_test.py`：all PASS，含 truth isolation、58/70-D 与 CUDA，exit 0。
  - `P -m py_compile omni_drones/utils/c3bf.py omni_drones/utils/safety_projection.py scripts/c3bf_test.py`：PASS，exit 0。
  - 内外仓库 `git diff --check`：PASS，exit 0；新增文件与此台账另以 `git diff --no-index --check /dev/null FILE` 检查，无空白错误输出（exit 1 表示文件与 /dev/null 不同）。
- 测试过程：最初测试骨架因新模块尚不存在失败（仅 availability baseline）；首次完整测试因十进制 d=.4 与半径求和的一位舍入差产生一个夹具失败，改用精确二进制边界 R=.5 后全部通过。不是将数值退化改成安全。
- 参数：`tau=CALIBRATION_PENDING`；synthetic tau=.4/gamma=1.2、margin=0/.05/.10、Delta_a=0/.6 与速度球均为 TEST_ONLY。最终 CBF margin、Delta_a、部署 v_max/a_max、r_uav_z/实体包络、tracking bounds/controller delay 仍待标定。新 core 不把旧 a_max 当作速度环已识别能力，也没有新增执行器加速度限幅约束。
- `Isaac runtime smoke=NOT REQUIRED`；`Hydra train=NOT RUN`；`RL training=NOT RUN`。本轮没有启动 Isaac，没有 commit/push，没有修改 submodule pointer。
- 专门后置到 M4a-integration：transform wiring、raw policy action capture、noise ordering、runtime filter、solver timing、infeasible/degenerate/stale runtime recovery、train/eval alignment、存在性/ID/时间对齐与边界高度处理。M6 后置 CBF reward。**本轮已停止，不开始 integration。**

### 10.3 M4a-core-b 实际记录（2026-09-21）

- 模块：六面场地/导航 safe-center HOCBF，与 obstacle constraints 及 XYZ speed ball 联合求解。状态：`M4a-core=PASS_WITH_CANDIDATE_SOLVER`；boundary constraints = **PASS**；production solver performance = **PENDING**；M4a-integration = **NOT_STARTED**。完成后停止。
- 修改前已检查 AGENTS、本计划、core 文档、c3bf/projection、NavVel/obstacle 实现和默认 task 配置，并输出 `M4A-CORE-B INSPECTION`。默认 OOB 为 abs(x/y)>3 或 norm(xy)>5、crash z<.15、上界 z>3；动态 smoke 才覆盖 [.30,2.00]。默认 edge 采样 x=±2.8、y∈[-2.8,2.8]、z∈[.4,2.4]，与本任务导航高度并不一致，保留为 integration 对齐事项。
- 六种边界语义分开：物理场地 x/y∈[-3,3]、z∈[0,3]；UAV-center 安全 box；起终点采样；OOB/终止；实体表面 clearance；CBF margin。新 API 显式接收 `[3]` 或 `[B,3]` lower/upper safe-center bounds，不由物理墙自动推导，不做隐藏半径或 margin 缩减。测试 x/y∈[-2.8,2.8]、z∈[.30,2.00] 仅为 **TEST_ONLY/PROVISIONAL**。
- 新增 `OmniDrones/omni_drones/utils/safety_boundaries.py`、`OmniDrones/scripts/c3bf_boundary_test.py`；仅修改 `OmniDrones/docs/m4a_core.md` 和本台账。未修改 c3bf.py、safety_projection.py、原 15 项测试、NavVel、旧 CBF、transform、train/eval、M1–M3、58/70-D schema、reward/PPO/critic/curriculum/profile/checkpoint。
- 独立推导：`p_dot=v`、`v_dot=(u-v)/tau`；inward n 下 `h=n·p+d`、`h_dot=n·v`、`h_ddot=n·(u-v)/tau`。取 `k1=lambda_1+lambda_2`、`k0=lambda_1*lambda_2` 得 `A=-n`、`b=(tau*k1-1)*(n·v)+tau*k0*h`，固定面顺序 xmin/xmax/ymin/ymax/zmin/zmax。解析轴向与 exact-flow 中央有限差分均验证符号。
- 连续高阶不变性还要求初始 `psi1=h_dot+lambda_1*h>=0` 和 `h>=0`；模块显式报告 psi1 和 hocbf_admissible。位置在框内不代表满足此条件。内向速度放松约束的单调性要求 `tau*(lambda_1+lambda_2)>=1`；主测试 synthetic tau=.4、lambda_1=lambda_2=2 满足此条件，同时有限差分也覆盖系数为负的正确公式。
- BoundaryStatus：INSIDE_SAFE_SET、ON_BOUNDARY、OUTSIDE_SAFE_SET、NUMERICAL_FAILURE、INVALID_BOUNDS。h<0 保留约束，不 mask；任何负值均为 outside。无效张量保留 active 行和 NaN RHS，避免裸 solver 忽略坏输入后报告 safe；无效标量配置抛受控错误。
- `merge_obstacle_boundary_constraints` 原样拼接障碍行再六面，`C_total=C_obs+6`，不受 actor K=4 限制。`project_joint_velocity` 只调用一次原 XYZ-ball solver，返回 raw projection 与联合 feasible/status。outside 或 psi1<0 即使 recovery QP 可行仍为 RECOVERY_REQUIRED/feasible=false；保留 INFEASIBLE 与 ITERATION_LIMIT 的区别。失败候选仅用于诊断，无零速度恢复。
- 行为 RED：先测旧 obstacle-only 输出 u_x=-.0574522，违反同场景 xmin 的 u_x>=-.016，exit 1；新联合路径通过，测试同时保留旧路径违反墙面的证据。首轮新测试的 CUDA 检测发现夹具在检测区内从 CPU 复制 bounds；将输入准备前置、模块 basis 改为设备内生成，完整 builder/merge/solve 通过 sync-debug。不是生产性能验收。
- 实际命令（cwd=`OmniDrones/`，P=`/home/hybrid/miniconda3/envs/lz_env/bin/python`）：
  - `P scripts/c3bf_boundary_test.py`：19/19 PASS，exit 0；六面、中心/表面/越界、psi1 条件、非法输入、boundary-only、obstacle+wall、height+obstacle+ball、分别可行联合不可行、预算不足、全残差、精确拼接、producer 状态传播、重复/近平行、CPU oracle、CUDA、采样间检查。
  - CPU float64 oracle：seed8127、B64/M8/C14、2048 iterations，ITERATION_LIMIT=0/64，max residual=2.498e-15，max objective difference=8.882e-15。
  - CUDA float32：B256/M8/C14、1024 iterations，ITERATION_LIMIT=0/256，max residual=1.848e-6；残差/gap 容差 2e-5/2e-4；设备一致、finite、全部约束和 XYZ norm 通过。sync-debug 是原型检测，未做 runtime benchmark。
  - wall+obstacle：512 iterations，残差0；height+obstacle+active ball：2048 iterations，残差2.082e-17，oracle objective difference=8.882e-16；两者均收敛，无 iteration limit。
  - sampled-time：每个 dt 运行14条轨迹（六面+八角）各2s，理想一阶速度环 exact ZOH，单步16 iterations；检查端点和每轴 v(t)=0 的区间内部极值。dt=.005/.01/.02 的最小采样间 margin 分别8.168778e-3/8.095526e-3/7.949048e-3 m；最大残差5.551e-17；ITERATION_LIMIT分别0/5600、0/2800、0/1400；均无穿越。另有端点都在框内但区间中穿越的反例验证检查器。仅数值压力测试，非通用离散安全证明。
  - `P scripts/c3bf_test.py`：15/15 PASS，exit 0；原 CPU oracle 最大目标差2.220e-15，原 CUDA通过。
  - `P scripts/cbf_test.py`：all PASS，exit 0。
  - `P scripts/test_clearance_conventions.py`：8/8 PASS，exit 0。
  - `P -m py_compile omni_drones/utils/c3bf.py omni_drones/utils/safety_projection.py omni_drones/utils/safety_boundaries.py scripts/c3bf_boundary_test.py`：PASS，exit 0。
  - 内外仓库 `git diff --check`：PASS，exit 0；四个本轮变更文件另做 no-index whitespace 检查，无诊断（exit 1 表示不同于 /dev/null）。对任务开始前 omni_drones/cfg/scripts 的全部已有 Python/YAML 做 SHA256 对比，均未改动。
- M1–M3 共享代码没有修改，因此不重复 motion/tracking/observation suites。Isaac smoke = NOT REQUIRED；Hydra train = NOT RUN；RL training = NOT RUN；未启动 Isaac、未 commit/push、未改 submodule pointer。
- 待标定：velocity-loop tau（CALIBRATION_PENDING）、lambda gains、最终 safe-center box、wall surface margin、r_uav_z/physical body envelope、boundary CBF margin；obstacle CBF margin、Delta_a 和状态/控制误差界延续待定。测试通过不升级为 production solver 或实机安全保证。
- 后置到 M4a-integration：transform wiring、raw action capture、noise ordering、runtime filter、t_k decision cache、真实 B/C/control-period runtime benchmark、infeasible/recovery runtime policy、train/eval alignment，以及采样/OOB/安全边界语义对齐。**推荐下一模块 M4a-integration，但本轮不开始。**

### 10.4 M4a-integration 实际记录（2026-09-21）

- 状态：`PASS_WITH_CANDIDATE_SOLVER`；solver=`CANDIDATE_RUNTIME_MEASURED`，production qualification **PENDING**。完整接口、限制和证据见 [integration delivery](OmniDrones/docs/m4a_integration.md)，原始性能数据见 [benchmark JSON](OmniDrones/docs/m4a_solver_benchmark.json)。历史 §10.2–10.3 的 NOT_STARTED/PENDING 是当时状态，不覆盖本节当前证据。
- 修改前输出 `M4A-INTEGRATION INSPECTION`，并检查安装版 TorchRL：Compose inverse 倒序、TransformedEnv 每次 policy step 只调用一次 inverse、TensorDict inverse 仅浅克隆。新 append order=`VelController, DynamicCBF, Noise, RawPolicyCapture`；实际执行 `raw capture → noise → dynamic filter → controller → rotor`。
- 新增：`omni_drones/utils/dynamic_cbf.py`、`omni_drones/utils/torchrl/dynamic_cbf.py`、`cfg/dynamic_cbf_smoke.yaml`、`scripts/dynamic_cbf_test.py`、`scripts/dynamic_cbf_isaac_smoke.py`、`scripts/dynamic_cbf_benchmark.py`、`docs/m4a_solver_benchmark.json`、`docs/m4a_integration.md`（均在 OmniDrones）。修改：NavVel gated lifecycle、train/eval dynamic factory 分支、play/demo capability guard，以及本台账。
- 默认缺失新键仍走原静态分支。dynamic actor 要求显式 dynamic namespace；OFF 使用 enabled=true/runtime_filter=false。train/eval 共用 factory/config，play/demo 明确拒绝 dynamic schema/config。动态路径要求 legacy cbf.mode=none、soft_respawn=false、single_episode_per_window=false；禁止旧 eval policy perturb wrapper，并检查冲突的顶层 runtime_filter。历史 profiles 和旧 cbf.py/VelController 均未改。
- 四级动作：raw_action 是 noise 前 Gaussian sample clone；filter_input 是 noise 后；safe_action 是成功投影/明确标记的 OFF passthrough 或失败 fallback；controller_target_velocity/yaw 是 VelController 限幅后送入 Lee.compute 的实际 target。当前 rollout agents.action 和 sample_log_prob 保留 raw sample。yaw 仍为 action[...,3]*pi 的目标角度（保留原可选 angle cap），不进 XYZ solver。
- 输入：M2 全 M estimated p/v/age/valid/ID；不读取 M1 velocity/acceleration/future trajectory。a_hat=0，Delta_a 显式。UAV p/v 与 actor 同源，标明 SIMULATION_ADAPTER；场景 active/ID/radius/static-dynamic 元数据也是 simulation registry adapter。invalid/stale/ID mismatch 的 active track 拒绝，即使在 actor K 之外。测试 M8/K4/C14，六面 bounds 显式接收 safe-center 范围。
- cache=`info.dynamic_cbf`，固定 spec；包含 step/time、四级 action/target、A/b/mask、nominal violation/correction、solver/raw-runtime status/feasible/residual/iterations/runtime、tracking/face status、intervention/failure counters。controller recorder 在 physics 前完成一次快照；t_(k+1) observation 仅发布 clone，不重算覆盖 t_k 证据。prev policy 在 NavVel `_step` 更新一次，障碍仍 per-substep 更新。partial reset 只清所选 env 的 cache/previous safe/counters/status/previous policy，旧 transition snapshot 保持不变。
- ON 一次联合求解 full M + 6 + XYZ ball，并检查实际 controller target 原始约束残差。OFF 不构建约束、不调用 projection、不运行 shadow，不改变原输入命令，normal controller cap 照常。噪声仅 XYZ，在 filter 前，关噪声 raw==input。
- 失败策略显式 configurable：zero_terminate（默认 dev）或 zero_diagnostic。零速度只是诊断 fallback，无安全保证；前者在该 bounded physics transition 结束后置 terminated/done，reset 前锁存。ITERATION_LIMIT → SOLVER_NOT_CONVERGED，其他无效/不可行状态单列；controller 二次限幅若破坏约束也失败。cache 中 solver_candidate 仅诊断，executed_feasible 与 solver_feasible 分开；无静默接受。
- 真实 Isaac smoke：项目 launcher、B2/M8/K4、dt=.01/substeps2，safe/head-on/wall/z/static 五种同 seed/初态/相对 measurement schedule 的 ON/OFF 配对均通过；M2 从显式两个 position packets 推导速度，alpha=beta=1 是 TEST_ONLY，速度对照实际 motion；其余障碍显式快速远离以保留可行退让方向。真实 raw preservation、noise order、controller target/yaw/残差、cache/spec、substeps、partial reset、invalid slot7 terminate 均通过。不是策略性能比较。
- 实际执行（cwd=`OmniDrones/`；P=`/home/hybrid/miniconda3/envs/lz_env/bin/python`），最终均 exit 0 且核对 PASS 标记：`P scripts/dynamic_cbf_test.py` 9 tests；`P scripts/c3bf_test.py` 15 tests；`P scripts/c3bf_boundary_test.py` 19 tests；`P scripts/cbf_test.py` all PASS；`P scripts/test_clearance_conventions.py` 8/8；`P scripts/dynamic_motion_test.py`、`P scripts/obstacle_tracking_test.py`、`P scripts/dynamic_observation_test.py` all PASS；`PYTHONUNBUFFERED=1 P scripts/dynamic_isaac_smoke.py task=profiles/NP-dual-p1-n2`、`P scripts/dynamic_observation_isaac_smoke.py`、`P scripts/static_profile_isaac_smoke.py`、`P scripts/dynamic_cbf_isaac_smoke.py` 全部真实 runtime PASS。
- `P scripts/dynamic_cbf_benchmark.py` exit 0：RTX5090D/Torch2.7.0+cu128/CUDAfloat32，C14，每 B warmup3 + measured30，固定512 cycles，CUDA synchronize 前后计时，独立于 Isaac。B2 mean/median/p95/p99/max=337.398/336.972/340.417/343.804/344.830 ms；B256=339.137/338.729/341.781/344.884/346.057 ms；B1024=339.624/339.524/343.200/345.707/346.243 ms。默认训练 batch1024 已覆盖，未启动学习。
- benchmark ITERATION_LIMIT=0%/0.390625%/1.171875%，infeasible均0%，最大残差1.192e-7/1.848e-6/8.434e-3（含被拒绝候选）；最后一项绝未当作 safe。测试批次重复30次，不是独立部署风险采样。smoke control_dt=.02，p99/control_dt=17.190/17.244/17.285；默认NavVel substeps1 的 .01s 周期下为34.380/34.488/34.571。没有自行定义生产阈值；性能明显超过周期，保持 candidate，生产优化/资格验收待定。
- 开发失败已记录：锁定的 Composite spec 改为 clone/unlock/assign；新 mixed-dtype info 从旧 float reset 中分离；初始 head-on 夹具联合不可行时正确拒绝，之后将 distractor 改为显式远离测试可行介入。Kit close 可吞异常或未 flush 输出，新 harness 保留非零异常；M1b 首次 exit0 但无最终输出未计 PASS，unbuffered 重跑取得全套 PASS。
- changed/new Python `py_compile`、内外 `git diff --check`、新增文件 whitespace 检查通过。NavVel `_compute_reward_and_done` 与开始前逐字一致；没有修改 PPO loss、critic、M1/M2/M3 构建器或58/70-D schema。原有 NavVel/obstacle/eval_2048 脏改动和外层删除/未跟踪资料保留；未改 submodule pointer，未 commit/push。
- 参数仍 TEST_ONLY/PROVISIONAL/CALIBRATION_PENDING：tau/gamma/CBF margin/Delta_a、boundary gains、最终中心 box、实体包络、deployment u_max、tracking uncertainty/delay margins。simulation adapter 不是硬件实现；无 sampled-data 安全证明；默认采样/OOB 与安全范围仍需部署对齐。solver_runtime 诊断默认关（-1 + runtime_measured=false）；开启时同步，不能误当免费生产计时。
- Hydra RL train=NOT RUN；long rollout=NOT RUN；W&B=NOT USED。后置 M5 privileged critic；M6 violation/correction reward；M7 curriculum/scratch RL/independent OFF evaluation；M8 deployment adapter 和最终 ON/OFF 报告。**推荐按计划下一步 M5，但本轮完成后停止，不开始其他模块。**

执行记录模板：`模块 / 前置决策 / 修改文件 / 命令及结果 / 未通过项 / 制品路径 / 下一步`。每次模块交付更新一次，不堆积无关会话历史。

本次开始前已有工作区改动：外层 `OmniDrones` 标记修改；`figures/record_fly_test.mp4`、`vis_traj.png`、`vis_traj_filter8.png`、`vis_traj_naive.png` 已删除；`.agents/`、`0920night.md`、`AGENTS.md`、`C3BF_dyn.md`、本文件及碰撞轨迹 npz 未跟踪。嵌套仓库已有 `scripts/eval_2048.py` 修改和 `omni_drones/utils/lzspace.code-workspace` 未跟踪。本计划不处理这些既有变更，不修改 submodule pointer，不提交或推送。

2026-09-21 复核时外层还已有 `project_summary.md` 删除，以及 `0908_project_summary.md`、两份 `OMNIDRONES_*` 文档、`prompt/` 未跟踪；同样全部保留。本次新增改动仅为本计划的接口修订，具体纠正依据见 §2.3，新增模块验收见 §8。

## 11. 依据与开发规范

- 项目规则：[AGENTS.md](AGENTS.md)。
- 接口复核依据：[OMNIDRONES_INTERFACE_REFERENCE.md](OMNIDRONES_INTERFACE_REFERENCE.md)、[OMNIDRONES_PROJECT_SUMMARY.md](OMNIDRONES_PROJECT_SUMMARY.md)。冲突条目已回查代码，见 §2.3。
- 本次应用技能：[drones-crazyflie-context](.agents/skills/drones-crazyflie-context/SKILL.md)、[project-onboarding](.agents/skills/project-onboarding/SKILL.md)、[implementation-workflow](.agents/skills/implementation-workflow/SKILL.md)。
- 数学起点：[C3BF_dyn.md](C3BF_dyn.md)。
- 当前参考圆柱配置：[NP-dual-p1-n8.yaml](OmniDrones/cfg/profiles/NP-dual-p1-n8.yaml)。该配置仅作结构参考，不用于继承旧权重。
- 核心环境：[nav_vel.py](OmniDrones/omni_drones/envs/single/nav_vel.py)；几何：[nav_vel_obstacles.py](OmniDrones/omni_drones/envs/single/nav_vel_obstacles.py)。
- 过滤与控制：[cbf.py](OmniDrones/omni_drones/utils/cbf.py)、[transforms.py](OmniDrones/omni_drones/utils/torchrl/transforms.py)。
- 学习与课程：[ppo.py](OmniDrones/omni_drones/learning/ppo/ppo.py)、[nav_curriculum.py](OmniDrones/omni_drones/utils/nav_curriculum.py)。
- CBF-RL 训练机制：[用户提供的论文](MinerU_markdown_Yang_等_-_2026_-_CBF-RL_safety_filtering_reinforcement_learning_in_training_with_control_barrier_functions_2054593947461390336.md)，重点为 §IV、Eq.18–23、Algorithm 1 及 Dual 无 runtime filter 消融。
- 历史实验口径：[NP_cylinder_batch_log.md](NP_cylinder_batch_log.md)、[0920night.md](0920night.md)。

开发时以当前可执行代码、resolved config 和测量结果为依据；文档中的候选公式/参数必须经过对应模块验证后才能提升为实现契约。


### 10.5 M5 Privileged Critic 实际记录（2026-09-21）

- 状态：**M5=PASS**。完整 inspection、字段单位/来源/尺度、学习语义修复、命令/退出码和 18 项验收见 [M5 delivery](OmniDrones/docs/m5_privileged_critic.md)。
- 新 gate：`algo.critic_input_mode=obstacle_privileged`；要求 PPO + M3 dynamic cylinder actor、priv_actor/priv_critic=false、soft_respawn=false、single_episode_per_window=false。默认 legacy 保持旧 priv_critic→vehicle intrinsics 含义；不将 obstacle truth 塞入 intrinsics。
- actor 仍为 `NavVelDynamicActor-v1 [B,1,70]`、K=4；输入、网络、Gaussian 分布、4-D action/log_prob 未变。新 `NavVelObstacleCritic-v1 [B,1,70+13*M]` = actor prefix + 每槽 truth p/v/a/radius/half_height/active/is_dynamic；inactive 用 NaN-safe where 清零，不输入 object_id/global origin。固定 scales p=5m、v=1m/s、a=1m/s²、radius=1m、half_height=2.5m 均 PROVISIONAL。
- spec 由配置 M 提前创建，早于 tracker 和 policy LazyLinear。每次 producer 分配独立存储，current=s_t、next=s_(t+1)，terminal next 在 reset 前保存。真实 partial reset env0 更新、env1 返回值及 producer 值不变；历史 terminal reference 保留。
- 修改前 probe 与最终真实 collector 均测得 batch_size=[2,3]、names=[None,time]，时间 dim=1、agent dim=2。最终真实 M=2，critic=[2,1,96]，rollout=[2,3,1,96]，minibatch=[6,1,96]。两个 return_same_td iteration 都 clone，验证第一批不被第二批覆盖；最终 rollout.next 与 step 即时快照一致。
- **LEARNING SEMANTICS FIX**：旧 GAE 的 terminated 同时控制 bootstrap/trace，timeout 可能跨 reset。仅新模式改为 bootstrap=~terminated；trace=~(done|truncated|terminated|traj_id_change)。timeout 定义为人工截断，从 reset 前 terminal critic value bootstrap；true terminated 不 bootstrap。旧 symmetric/intrinsics 和共享 GAE 四参数调用保持旧语义，不宣称全局修复。
- CPU 手算 A0/A1/A2 timeout→B0/B1 terminated：gamma=.9/lambda=.8，expected advantage=[4.74912,-5.904,-20.7,-23.4,-45]，return=[14.74912,14.096,9.3,16.6,5]；新增 true termination 批内边界测试。expected 不由被测 GAE 生成。
- actor truth isolation：相同 observation、不同 critic_state 时 loc/scale/action/log_prob 逐位相同；critic first-Linear hook 证实消费不同 privileged 输入。full state_dict actor/critic/非零 ValueNorm roundtrip 通过；加载后提取 actor、70-D-only TD inference、TorchScript 保存/加载通过。
- 附带明确兼容修复：Composite vehicle intrinsics 仅拼接其 named leaves，旧 flat intrinsic 网络不变；ValueNorm 注册提前到 checkpoint load 前（所有 PPO 配置），修复构造加载漏 buffer，不涉及 optimizer resume。
- 实际验证：`privileged_critic_test.py` 7 项、`gae_boundary_test.py` 3 项、`privileged_critic_isaac_smoke.py` 和 `--static`、dynamic_motion/obstacle_tracking/dynamic_observation/dynamic_cbf/c3bf/c3bf_boundary 六项回归全部退出 0；changed-files py_compile 和内外 git diff --check 通过。无既有 PPO/GAE 专用测试，使用新增覆盖。
- 对本轮前快照 `/tmp/m5_before/` 审查：actor construction 逐字相同，reward、M4 step/pre_sim_step/reset_idx、M3 actor builder AST 不变。既有脏文件保留，没有 commit/push/submodule pointer 更新。
- M4 solver=`CANDIDATE_RUNTIME_MEASURED`，p99≈344–346ms，**UNCHANGED / OPEN_BLOCKER_BEFORE_M7_PRODUCTION_TRAINING**；M5 没有优化或重测 solver。
- Hydra RL training=NOT RUN；long rollout=NOT RUN；W&B=NOT USED。仅 CPU synthetic fixture 做一次有限 optimizer update，真实 Isaac 不更新参数。
- 后置 M6：CBF violation/correction/dynamic near-slowdown reward、reward aggregation/normalization。后置 M7：curriculum、training bundle、scratch training、independent OFF evaluation。**推荐下一模块 M6，但本轮已停止，不开始它。**


### 10.6 M6 Dynamic Reward 实际记录（2026-09-21）

- 状态：**M6=PASS**（correctness，不是 reward tuning 或 production qualification）。完整 inspection、公式/单位/时序/模式/失败合同、测试退出码和21项验收见 [M6 delivery](OmniDrones/docs/m6_dynamic_reward.md)；增量性能原始数据见 [shadow benchmark](OmniDrones/docs/m6_shadow_benchmark.json)。§10.4–10.5 的下一步表述是历史记录，以本节为当前状态。
- Gate：`task.dynamic_reward.enabled=true`，独立 `cbf_enabled` 与 M4 runtime_filter 组成 Dual/Filter-only/Reward-only/Nominal；缺失 gate 保持旧路径。要求 M3 dynamic cylinder/M4 namespace、legacy cbf.mode=none、soft_respawn=false、single_episode_per_window=false。新 proximity log 启用时必须显式 `reward_obs_log_mode=penalty`；未改旧 NP profiles。
- Actor nominal 冻结为 raw Gaussian sample 的 XYZ，不 clamp、不用 noisy filter_input。归一化 `c_norm=(b/||A||-(A/||A||)·u_raw)/u_ref`，A/b 正比例缩放不改变 reward（浮点可表示范围）；非零行无需 epsilon，零行恒真忽略、矛盾/非法行报失败。C3BF 与 boundary 除 ||A|| 后均为 m/s，除 u_ref 后无量纲。
- 默认仅支持 worst：`r_v=-w_v*max_active relu(-c_norm)`；新 closing 取最大 weighted relative risk；log proximity 从旧 sum 改为最负 phi（仅新 gate）。重复安全/危险约束不使奖励随数量线性增长；真实2槽/8重复槽验证 proximity 不放大四倍。
- Shadow：同一 t_k estimated A/b/mask、producer readiness 和 XYZ speed ball，对 raw 求最小纠偏。`r_c=w_c*(exp(-||u_raw-u_shadow||²/sigma²)-1)`，sigma 单位m/s、无隐藏 u_max 归一化。Dual 无 noise 且 raw=input 复用 execution result；有 noise 额外 solve；Reward-only 唯一 raw shadow 不改 OFF action/controller target/terminate；Nominal 零 solve。
- 时序：shadow/CBF reward evidence 在 physics 前完成并冻结；reward 在 t_(k+1) 只消费 t_k cache，不重建 CBF。真实 post-physics TEST_ONLY teleport 验证 safe→dangerous 和 dangerous→safe 均按 t_k 计罚；reward_step_id 对齐 decision_step_id/progress_buf。missing/stale/重复消费显式状态和 penalty，不拿当前状态补算。
- Closing：truth SDF outward normal（surface→UAV）、truth v_uav-v_obs，`closing=relu(-n·v_rel)`；`r_close=-w_close*max_active(clamp(1-clearance/D,0,1)*closing/v_ref)`，t_(k+1) privileged reward-only signal，不写 actor/critic。静止UAV+迎面障碍有正 closing；同速/远离为0，远处等待无低速罚。
- Failure：保存 core shadow_solver_status；无有效 shadow 时普通 violation/correction 项为0，由单个 `-failure_penalty` 替代，shadow_feasible=false、correction_norm=-1。M4 runtime termination/fallback 不变，不额外加第二份 runtime CBF fee；物理失败 reward 仍独立。Reward-only shadow failure 不过滤、不触发 runtime terminate。
- Cache/reset/stats：新增固定 shape/device 的奖励、margin、nominal/executed correction、signed norm difference、active count、shadow status/time/calls/validity 等。cache copy-on-write；env0 terminal reward 先算再 reset 清cache，env1保持。新 gate 在 _step 返回前发布当步 stats clone，防 terminal 分项滞后一拍；旧 stats 发布行为不变。
- Provisional dev 参数：w_v=.5、w_c=.5、sigma=.5m/s、u_ref=1m/s、failure_penalty=2、closing_weight=.2、closing_distance=.6m、closing_velocity_reference=1m/s，aggregation=worst。配置片段 `cfg/dynamic_reward_smoke.yaml` 不是正式 training profile；待 M7 基于真实分布标定。
- 实测 shadow cost：RTX5090D/Torch2.7+cu128、float32、M=8/C=14、512iterations；B=2/1024，每模式3warmup+20次同步测量。无 noise Dual：1 solve、0额外 shadow；noisy Dual：2 solves。B=2 额外 shadow mean/p99=324.145/325.991ms，decision p99=658.644ms；B=1024 额外 shadow mean/p99=327.869/335.277ms，decision p99=666.280ms。Reward-only为1 shadow、0 execution；Nominal为0 solve。此为固定合成批样本估计，不替代生产性能分布。
- M4 solver 原状态 **CANDIDATE_RUNTIME_MEASURED**、原单投影 p99≈344–346ms **UNCHANGED**；**OPEN_BLOCKER_BEFORE_M7_PRODUCTION_TRAINING**。M6没有优化 solver；噪声下 shadow 增加约一次投影成本。
- 实际测试：dynamic_reward_test 8项；dynamic_cbf 9项、c3bf 15项、boundary 19项、motion/tracking/observation、privileged_critic 7项、GAE 3项均通过；新的 dynamic_reward_isaac_smoke 及既有 dynamic_observation/dynamic_cbf/privileged_critic/static_profile 四个 Isaac smoke 全通过；benchmark JSON完成；7个 changed/new Python py_compile、内外 diff --check通过。全部最终退出0，Isaac确认PASS marker。
- 静态兼容证据：以 `/tmp/m6_before/` 为基线，M6 gate OFF 后奖励 AST 与原函数完全一致；M5 PPO/common/schema及M3 builder、C3BF/boundary/projection三个核心文件hash未变。raw smoothness和prev-policy一次/policy-step保持原M4实现。
- Hydra PPO training=NOT RUN；long rollout=NOT RUN；W&B=NOT USED。用户要求的旧 M5 CPU regression 内含一次 synthetic optimizer smoke，未启动RL训练。既有脏文件保留，未stage/commit/push/修改submodule pointer。
- 后置 M7：formal dynamic training profile、curriculum、scratch training、checkpoint bundle、independent OFF evaluator、实际分布 reward tuning。**不自动开始 M7；先重新评估/优化 CBF solver runtime blocker，再进入 M7。本轮完成 M6 后停止。**


### 10.7 M4a-greedy-projection 实际记录（2026-09-21）

- 状态：**PASS_WITH_APPROXIMATE_GREEDY_SOLVER**；**M7 NOT READY**。完整 inspection、算法/状态/API、150案例逐项oracle对比、24组CUDA迭代性能、双目标/五模式成本、命令退出码与16项验收见 [本轮交付](OmniDrones/docs/m4a_greedy_projection.md)。本节为当前状态；§10.4/10.6 的344–346ms/659–666ms仍作为历史Dykstra基线保留，不再代表显式greedy配置。
- 保留 Dykstra 和独立 CPU oracle；原 Dykstra 函数除重命名外 AST 完全一致。缺失 solver.backend 保持 Dykstra，历史flat参数继续有效；只有 TEST_ONLY dynamic_cbf_smoke.yaml 显式选择 greedy_most_violated、64轮、feasibility_tol=speed_tol=2e-5、row_eps=0、most_violated_normalized。未修改训练或旧静态profile。
- 单半空间 `u-=relu(a.u-b)/||a||²*a` 为闭式解析投影；多半空间+完整XYZ球为有限轮迭代近似，不保证联合最优，也不保证有限轮可行。先球投影，每轮按归一化半空间欧氏距离选最大违约，平局最低index，投影后再次入球；负b可能因球缩放再违约。B/C全向量化，只有固定轮数Python循环，无每步.item/CPUcopy。
- 最终 ALL original Au-b、XYZ球、finite 检查才可 feasible。原始残差tolerance不用于提前冻结轨迹，避免整体缩小A/b导致几何修正消失；浮点可表示非零行选择/轨迹缩放测试通过。精确矛盾零行才报STRUCTURAL_INFEASIBLE；tiny非零行不能单独证明矛盾；非收敛为ITERATION_LIMIT，不冒充一般INFEASIBLE。非法输入/溢出报NUMERICAL_FAILURE。
- Result保留原字段，增加iterations_configured、first_feasible_iteration、distinct selected_constraint_count、last_selected_constraint、normalized/halfspace/ball residual、backend ID、optimality flags。greedy duality_gap=-1，optimality_metric_valid=false，optimality_certified=false。candidate objective不是最优证书；失败candidate不作为安全命令。
- M4 runtime与M6 shadow统一读solver_options，execution=noisy input、shadow=raw；无噪声复用、有噪声独立raw solve、Reward-only不改动作。M6文档撤销无条件argmin，greedy correction明确backend-dependent approximate；Gaussian公式/权重/t_k cache/raw-noise attribution/四模式未改。新增缓存shadow_solver_backend、shadow_solution_approximate。原failure penalty与zero_terminate/zero_diagnostic保留。
- [Oracle对比](OmniDrones/docs/greedy_projection_comparison.json)：150案例含10个真实Isaac决策；oracle可行148，Dykstra512接受144。greedy64接受147，总可行性一致率99.333%；false feasible=0；false non-converged=1（near-tangent可行案例）。状态PROJECTED141、ALREADY_SAFE6、ITERATION_LIMIT2（其中1例实际不可行）、STRUCTURAL_INFEASIBLE1。全部candidate最大半空间残差1（包含拒绝的矛盾案例），接受集最大9.31514e-6；球残差最大2.22045e-16。
- greedy64 vs oracle可行目标差：mean=.2152234、max=1.7070474、min=-3.19609e-5，147个共同可行案例；小负差来自有限feasibility tolerance，不是优于精确最优。相对Dykstra的纠偏范数差mean=.06557666、max=.32812086，144个共同接受案例。不能宣称最小纠偏最优。
- [CUDA sweep](OmniDrones/docs/greedy_projection_benchmark.json)：RTX5090D/Torch2.7+cu128、float32、B2/256/1024、C14、seed8127、5warmup+30次同步测量，iters1/3/5/8/16/32/64/128。B1024 iteration-limit分别77.148/27.637/24.512/17.969/7.324/2.441/.586/.195%；各组false feasible=0。64是覆盖普通oracle案例及B256的最小测试预算；128成本约翻倍，仍不解决near-tangent案例。此为实验折中，不是生产失败率资格。
- 同次测量 solver p99：B2 Dykstra337.778→greedy64 14.518ms（23.27x）；B256 342.781→14.083ms（24.34x）；B1024 346.288→14.164ms（24.45x）。B1024接受1018/1024，6个未收敛全部拒绝，最大接受原始残差1.27852e-5；全部candidate最大残差.0668166，不能当safe。
- 双目标 B1024 两次独立solve p99=28.327ms，stack2B=14.372ms，所有result字段逐位一致。stack仅benchmark验证，runtime仍两次独立解，不暗改M6。B1024 decision p99：Dual无noise16.662ms（1+0），Dual noise30.453ms（1+1），Reward-only16.622ms（0+1），Filter-only16.046ms（1+0），Nominal .572ms（0+0）；不含controller/Isaac。相对历史Dykstra noisy Dual666.280ms约21.88x。
- 真实Isaac：显式greedy配置的dynamic_cbf_isaac_smoke、dynamic_reward_isaac_smoke及旧static_profile_isaac_smoke均exit0且核对最终PASS marker。M4五场景ON/OFF、noise/raw/controller/yaw/fullM/六面/球/t_k/partialreset/failure通过；M6四模式、raw shadow、noise隔离、timing、terminal/reset、Reward-only failure通过。导出10个prephysics决策到 [fixture](OmniDrones/docs/greedy_isaac_fixture.json)，已纳入oracle对比。
- CPU/CUDA测试：greedy_projection_test15项；c3bf15、boundary19、dynamic_cbf9、dynamic_reward8、旧cbf全PASS、clearance8/8。两条新comparison/benchmark脚本均exit0；11个相关Python py_compile和内外diff --check通过。日志/tmp/greedy_*，退出码/tmp/greedy_regressions.json。
- 开发失败记录：初始availability断言确认缺后端；后续完整缩放测试发现按raw tolerance提前冻结会破坏小scale轨迹，RED后改成仅无几何违约no-op，最终全部通过。没有降低最终残差阈值。
- 保护审查：C3BF/tightening、boundary HOCBF、静态cbf.py、M1/M2/M3、actor70、critic/GAE、NavVel reward、train/eval共用factory及play/demo guards相对本轮快照hash未变。生产仅修改projection/runtime/reward三文件；其余为dev配置/测试/文档。新增7文件，修改11个nested已有文件及本台账；保留既有脏文件、删除与未跟踪工作。未stage/commit/push/reset/clean或更改submodule pointer。
- **M7 NOT READY / production blocker OPEN**：虽显著加速，noisy Dual30.453ms仍超过20ms smoke和10ms默认控制周期（尚不含controller/physics）；B1024及near-tangent非收敛风险仍需评估，没有擅设生产失败率阈值。多约束最优性/有限轮可行性/一般安全均未认证。后续可评估双目标合批接入及稳健性/预算折中，但本轮不实施。
- Hydra RL training=NOT RUN；long rollout=NOT RUN；W&B=NOT USED。不做reward tuning、curriculum、checkpoint或active-set重写。**DO NOT START M7 automatically；本轮完成后停止。**

### 10.8 M4a-greedy-runtime-hardening 实际记录（2026-09-21）

- **实现/正确性 PASS_WITH_APPROXIMATE_GREEDY_SOLVER；M7 NOT_READY_FOR_M7；M7 NOT STARTED。** 完整 inspection、全字段等价/缓存合同、真实 rollout、性能、专项诊断及命令退出码见 [MODULE DELIVERY](OmniDrones/docs/m4a_greedy_runtime_hardening.md)。本节为当前状态，前节两次 solve 和仅依控制周期的判断保留为历史记录。
- runtime [2B,3] query-major 合批真实接入：execution=0（noisy filter_input），shadow=1（raw policy action），共享所有约束与 solver 配置；所有 ProjectionResult 字段逐位等于独立求解。Dual 无噪声1 launch/1 query、有噪声1/2；Filter-only1/1；Reward-only1/1且OFF执行不变；Nominal0/0且不构造约束。实际相等XYZ即复用，包括noise配置开但输入相等。
- decision cache新增两份完整投影结果、per-decision launch/query计数；保留raw/filter/safe/controller、独立状态/纠偏、step/time、consume-once和partial reset。执行失败沿用zero_terminate/zero_diagnostic；shadow失败仅按M6 penalty，不冒充execution安全。两种混合成功/失败查询通过测试。旧查询计数保留含义，共享launch没有独立shadow耗时，以-1标记。
- 真实Isaac：B256/1024/4096，每种五模式20warmup+200measured，seed7103、headless、八场景及zero/scripted/Gaussian三种命令；只对done成员partial reset，真实Lee/rotor/physics/M1/M2推进。另测B1024 compact64+64相同步数。统计完整分开execution/shadow和accepted/rejected；全部false feasible=0，max accepted halfspace=1.99861825e-05、ball=3.57627869e-07，容差均2e-5。
- B1024 transitions/s（包含测试的partial reset/fixture恢复）：Nominal=22308.105, Filter-only=9132.088, Dual no-noise=9068.470, Dual noise=8479.352, Reward-only=15035.508。noisy Dual相对Nominal成本=2.631x；执行/shadow失败=12.8955%/9.2969%，failure termination=12.8955%。主要压力来自near-tangent，mixed也有非收敛。测试压力分布不代表部署/训练策略发生概率；reset恢复额外开销已与不含reset的step时间分列。
- 运行时benchmark（实际capture/decide/controller_target，未含Isaac）B1/2/256/1024/4096，20warmup+100calls。B1024 noisy Dual p99=18.392ms，旧separate30.453ms、Dykstra666.280ms，约1.66x/36.23x；旧isolated2B 14.372ms未冒充runtime结果。B2 p99=17.174ms，/10ms=1.717、/20ms=.859，仅参考。没有torch.compile。
- 原near-tangent fixture在64/96/128/192轮residual=.007229/.004682/.003403/.002125，均ITERATION_LIMIT；CPUfloat64额外4096诊断首次feasible=1965，属于慢收敛，未自动上调默认。真实失败158个分层首例回放（可能跨query重复）中oracle可行96；64/96/128/192接受0/24/34/39，既有可恢复漏解，也有oracle不可行约束；ITERATION_LIMIT本身不作为不可行证书。
- 据实际可恢复漏解实现可配置greedy continuation，默认enabled=false、extra_iters64、policy=greedy_continue、strategy=masked（可compact）。从base candidate继续；base-feasible no-op；保存first/last/selected历史；最终全残差检查；失败仍ITERATION_LIMIT。无逐env循环/CPUcopy；compact nonzero动态形状同步显式记录；两策略逐位一致。B1024 random batch masked/compact约27.55/27.71ms，与global128约27.54ms接近；empty compact约14.37ms，才可省去第二阶段。
- 真实B1024 noisy Dual optional compact中execution base→final iteration-limit=12.2402%→12.1772%，恢复比例=0.5146%；termination仍12.3018%。因此base default64、optional refinement OFF；训练smoke设置尚不批准；diagnostic可选compact64+64及near-tangent预算专项。不是实机参数标定。
- 所有规定CPU/CUDA、M4/M6/static Isaac回归及新增joint/refinement测试通过；三组基线有限rollout及refined rollout均exit0/PASS。py_compile、内外diff检查见verification；Dykstra/CPUoracle/边界builder AST未改，C3BF/NavVel/actor70/critic/GAE/factory/历史profile与dev权重hash保持。两个旧benchmark仅更新当前合批标签/计数/未知独立耗时处理，历史JSON保留。
- **NOT_READY_FOR_M7 的准确阻塞是near-tangent慢收敛、实际不可行状态及高failure termination；不是只因solver p99超过control_dt。** 吞吐已知，未达可接受失败/终止证据；更多64轮不足。下一步仅建议针对这两类状态做有界诊断及预算/失败处理验证，再重评M7；不自动开始curriculum/M7a/PPO/独立OFF evaluator。
- Hydra PPO training=NOT RUN；long training=NOT RUN；W&B=NOT USED。既有脏文件保留，没有stage/commit/push/reset/clean/submodule pointer修改。**本轮完成后停止。**

### 10.9 M4a-failure-feasibility-diagnostics 实际记录（2026-09-21）

- **PASS_DIAGNOSTICS_COMPLETE；Reviewer PASS；M7=NOT_READY，NOT STARTED。** 完整 inspection、MODULE DELIVERY、逐项命令/退出码、分类与统计局限见 [诊断交付](OmniDrones/docs/m4a_failure_feasibility_diagnostics.md)，机器可读聚合见 [summary](OmniDrones/docs/greedy_failure_delivery_summary.json)，独立审查见 [review](OmniDrones/docs/greedy_failure_review.md)。本节为当前状态；前节结果作为历史保留。
- 实际使用六个命名子代理：explorer/watcher 并行只读检查，architect 设计，implementer 实现，test_runner 独立执行，reviewer 只读审查；全部成功 spawn，均无嵌套分派。运行时 model/reasoning metadata 均 **NOT EXPOSED / NOT VERIFIED**，不将 TOML 模型名或自动 manifest 加载当作运行证据；详见 [agent provenance](OmniDrones/docs/greedy_failure_agents.json)。
- **Production behavior changed=NO。** 只新增五个独立诊断/测试脚本、docs 制品及本台账；无需生产 hook。capture 显式默认关闭，gate-off 方法/RNG/状态无变化。未改 C3BF、boundary HOCBF、greedy、base64、2e-5 容差、refinement 默认关闭、速度限幅、reward、failure policy、actor/critic/GAE、curriculum 或训练配置。
- 正式有限 Isaac capture：B256/B1024，Dual noisy sigma=.2，M8/C14，CUDAfloat32，seed7103、sampling seed27103；各20 warmup+200 measured，headless、W&B disabled。execution 共256000 queries/32940失败（12.8671875%）；shadow 共256000/23785失败（9.291015625%）。执行失败终止32940。B256分别6572/4727失败；B1024分别26368/19058。此为八种固定压力夹具分布，不代表训练策略或部署概率。
- 有界 corpus=545（execution272/shadow273），占两角色56725失败query的0.960776%。各 run/query random reservoir128；另保留producer-aware scene/category首例及最大残差，去重后保留arm。硬上界960；全量只累计状态、六维覆盖和残差统计。制品 [corpus](OmniDrones/docs/greedy_failure_corpus.pt)/[manifest](OmniDrones/docs/greedy_failure_corpus_manifest.json)；单run manifest保存config/source hash、git状态、命令、dtype/shape及顺序。逐项clone/detach，保存完整源状态，不保留TensorDict引用。
- 545/545原始25个ProjectionResult字段及源状态重建A/b/mask逐位一致；同一corpus两次完整回放数值完全一致、blocking mismatch=0。两轮独立完成capture的全部sample字段、ID、arm及全量计数也完全一致，见 [repeat audit](OmniDrones/docs/greedy_failure_capture_repeat.json)。greedy预算64/96/128/192/256/512/1024/2048；Dykstra512仅参考；既有CPUfloat64 oracle以1e-8数值容差作为F1/F2/F3依据，非exact-arithmetic证书。
- **Corpus主分类（有增强采样偏置，不是全量比例）**：execution F1/F2/F3/F4/F5/F6/F7/F8=253/1/12/3/3/0/0/0；shadow=245/0/18/3/7/0/0/0。仅random arm按各run失败总数加权，F1占execution/shadow失败点估计95.6242%/92.4980%，F3=3.5945%/5.1582%。加权Wilson端点仅作参考范围，无总体95%覆盖保证；稀有类别零观测不等于不存在。全量producer粗计数execution iteration/inside/recovery=32593/32/315，shadow=23438/32/315；这些可直接计数的稀有producer状态优先用census。
- 30个F3全部完成六组ball/no-ball消融：28 BALL_BUDGET_CONFLICT、2 OBSTACLE_ONLY_INFEASIBLE，其余归因0。真正无球min-norm独立低维枚举通过解析测试；28例所需速度min/median/max=1.836774/1.838742/2.283198m/s，当前u_max=1.8；deficit=.036774/.038742/.483198。逐行LOO中obstacle_0解除30例、obstacle_3解除4例；移除全部obstacles解除30，boundary移除均不解除。**conflict evidence，不是exact/minimal IIS。** 同A/b仅诊断u_max+10%/+25%均解除26/30，不建议自动提高速度或去margin；未证明provisional参数的因果责任。
- F4保留inside inflated region源证据，F5样本均为boundary psi1<0而仍在center box内，不与普通不收敛合并。F6精确零行负b是原始字面不等式的严格结构矛盾；数值oracle可因其1e-8容差接受极小负b，诊断显式保存这两种事实，不当作生产false feasible；tiny非零行不归F6。
- Near-tangent已知夹具结论 **BALL_HALFSPACE_PING_PONG**：同一行反复投影，球投影每轮重新引入违约；residual缓慢单调下降，无非平凡循环证据。CPUfloat32/64首次可行1966/1965；known及三个真实oracle可行漏解逐轮4096、双精度、64/128/512/2048/4096端点与生产求解器全exact，见 [trace](OmniDrones/docs/greedy_near_tangent_trace.json)。一个multiple_active F2 execution在2048仍残差5.123615e-4，oracle witness残差1.78e-15；不能称不可行，random arm未抽中也不等于不存在。
- accepted execution/shadow计数223060/232215；max halfspace=1.998245716e-5/1.953542233e-5，max ball均2.384185791e-7；nonfinite/违反容差/false feasible均0。rejected execution/shadow=32940/23785，max halfspace均.192514718，单独报告，绝不当safe。显式非有限计数避免NaN被max汇总隐藏。
- 实际独立验证：新diagnostics24组；greedy_projection/joint/refinement、c3bf/boundary、dynamic_cbf/reward七项CPU回归；两组capture、merge、重复CUDA replay、analysis、trace；dynamic_cbf/dynamic_reward/static三项Isaac smoke全部PASS；五文件py_compile与内外diff-check通过。旧greedy_isaac_fixture经smoke后逐字恢复。开发期中断、buffered marker丢失、cuda别名误阻断、真实trace算术不一致均保留历史，并在独立复跑后解决；未改生产或放宽阈值，见 [verification](OmniDrones/docs/greedy_failure_verification.json)。
- 原8959文件基线审查除本次授权台账外保持；既有脏文件、外层删除和未跟踪资料保留，未改gitlink/index/HEAD、未stage/commit/push。Hydra PPO training=NOT RUN；long rollout=NOT RUN（仅上述有界诊断）；curriculum/OFF evaluator=NOT STARTED；W&B=NOT USED。
- **唯一下一模块建议：M4a-targeted-solver-recovery。** 优先解决有实际轨迹证据的ball/halfspace极慢收敛及multiple-active persistent miss，同时保持oracle不可行与inside/recovery合同分离。该建议不等于直接增大全局迭代数或提高u_max。**本轮只诊断，未修复12.8672%执行失败，因此M7保持NOT_READY；到此停止，不开始下一模块。**


### 10.10 M7a Dynamic Training Infrastructure 实际记录（2026-09-21）

- **PASS_M7A_INFRA_SOLVER_DISTRIBUTION_PENDING；M7A_INFRA_PASS_SOLVER_DISTRIBUTION_BLOCKED；NOT_READY_FOR_M7B。** 本轮由用户明确授权有限M7a，覆盖此前历史“不开始M7”限制；不是正式M7训练。完整合同、制品、命令/退出码、局限与审查见 [MODULE DELIVERY](OmniDrones/docs/m7a_training_infrastructure.md)。独立test_runner全部规定测试RC0、reviewer源码及制品复审PASS；不据exit0单独判PASS。
- 新增dynamic_train_base/D0–D3 profiles和安全有限root配置；历史NP/A profiles未修改。fixed M8/K4、actor70、critic174、action4、CBF14保持。D0=2static+0dynamic，D1=2+2，D2=4+2，D3=4+4；D2/D3仅配置，不训练。
- D1使用既有smoke来源的v_max=.05m/s、a_max=.2m/s²、START_STOP最大.1m短直线，PROVISIONAL/TEST_ONLY，XY travel[-2.8,2.8]按半径收缩，整段swept-disc保守不相交验证，vz=az0。2.5m落地高柱、导航z[.3,2]；无飞跃/3D球。D0底层motion容量存在但全部STATIC、实际v=a0、stage.motion_enabled=false。
- 独立DynamicCurriculum保存desired/pending与per-env applied stage、lock、reset IDs、completed windows/group counts、last OFF ID及hash。新stage仅选中env下一reset应用；真实B2 env0先D1、env1保留D0后再D1，motion/tracker/IDs/actor/critic/CBF cache/reward/Isaac poses隔离通过。自动progression=false；未配阈值未来gate fail closed；未完成episode不计completed window。
- 新profile显式同步reset位置测量适配：同t正常measurement已消费后，selected reset取得当前p/active/IDs位置packet，零noise/delay/dropout才允许；无truth v/a输入，不改M2估计数学/原时钟，不全局重置nonselected。CPU基线证明缺帧，CPU和Isaac证明修复后selected立即valid、nonselected逐字段不变。仅仿真reset acquisition合同，非部署传感器承诺。
- 双制品：inference原state_dict+identity sidecar；training bundle保存model/ValueNorm、实际actor_opt/critic_opt两个Adam、scheduler空、frames/iteration/collector/optimizer steps、课程lock/pending/windows、Python/NumPy/TorchCPU/allCUDA RNG及motion/measurement Generators、seeds、五种schema/hash、resolved config/hash、git/dirty、checkpoint/bundle/parent IDs。严格校验后strict=True加载，错schema/config拒绝；原子临时文件fsync/rename。实际跨进程episode-boundary resume frames512→768、iteration2→3、每Adam4→6，恢复audit全true；清tracker/motion/cache，不承诺物理轨迹逐位恢复。
- 独立OFF worker新PID/Isaac加载匹配模型，training/evaluation config hashes分开、白名单OFF派生；runtime_filter=false、shadow=false、M6 cbf_enabled=false，actual projection绑定若调用即raise，execution/shadow calls均0。runtime recorder/cache确实实例化，如实报告。2episodes固定seed、短64-step horizon，均timeout/strictsuccess0，仅协议smoke。worker期间TRAIN RNG/curriculum hash不变；训练侧验证后仅记录last consumed OFF身份，不升级stage/修改ON windows。错ID/stage/hash/config、过期、partial/incomplete/checksum、duplicate拒绝。
- 四组单seed7103 scratch：D0/D1 B8各512frames，B64各4096frames；32collector steps×2train_op，预算预先设ppo_epochs1/minibatches2，每Adam4次step，无按loss调参。actor/critic/action/reward shape与time dim1/agent dim2、loss/gradient/parameters/ValueNorm有限，NaNInf0；W&B未使用，finaleval0，D1B256/1024未运行。
- **实际D0/D1分布各4608 queries/role：execution与shadow全部RECOVERY_REQUIRED，failure与failure termination=100%，ITERATION_LIMIT=0，accepted=0，false_feasible=0，accepted residual=N/A。** 不是此前混合压力12.9%分布，不应归咎5轮不够。当前C3BF把零相对速度标DEGENERATE，joint映射RECOVERY_REQUIRED；CPU远离静柱/六面VALID复现，静止reset+zero_terminate造成一帧episode循环。没有改数学、容差、预算、failure policy掩盖；有限更新不代表学会绕行。
- NavVel生产增量仅35新增/3替换行的gated初始化/reset/step；train.py仅默认兼容skip_final_eval。reward/observation AST、PPO/GAE、M1–M6核心和历史profiles hash保持；旧static58真实reset/step、symmetric/intrinsics forward及规定CPU回归通过。原13,332文件保护，无非授权变化，保留既有外层删除/脏文件，未改gitlink/index/HEAD，未stage/commit/push。
- 六命名会话均实际参与：explorer/watcher初检，architect设计，早期implementer恢复受thread-limit拒绝故主体由Orchestrator实施，后来implementer完成review发现的状态修正，test_runner独立复跑，reviewer逐snapshot复审。runtime model/reasoning均NOT EXPOSED/NOT VERIFIED；不冒称TOML自动加载。初次review因硬编码PASS_FINITE_TRAINING而REVIEW_BLOCKED，已改为finite_chain_pass与solver-blocked明确分离；保留审查历史。
- full curriculum/D2/D3/multi-seed/long evaluation=NOT RUN；W&B=NOT USED；M4b/M9=NOT STARTED。**下一模块只建议M7a-stationary-reset-C3BF-degeneracy-resolution阻塞专项，不开始它；不进入M7b。**


### 10.11 M7a stationary-reset C3BF degeneracy resolution 实际记录（2026-09-22）

- **PASS_STATIONARY_C3BF_DEGENERACY_RESOLVED；Reviewer PASS；READY_FOR_M7B_D0_D1_DEBUG_TRAINING。** READY仅表示单seed、有限预算、锁定D0/D1调试资格，不代表无solver failure、D2/D3/full curriculum/reward tuning/实机安全。完整 [MODULE DELIVERY](OmniDrones/docs/stationary_c3bf_delivery.md)、[推导](OmniDrones/docs/stationary_c3bf_degeneracy.md)、[review](OmniDrones/docs/stationary_c3bf_review.md) 与 [命令台账](OmniDrones/docs/stationary_c3bf_validation/commands.json)。本节是最新状态，旧§10.10原始NOT_READY记录保留。
- 修改前已输出完整INSPECTION。根因是constraint producer将v_rel≈0标DEGENERATE、mask清空，joint随后RECOVERY_REQUIRED与zero_terminate形成1-step循环；不是5轮solver无法处理有效障碍row。本轮新增显式低速distance-HOCBF，不跳过障碍、不改tracker首帧0、不注入truth、不加eps冒充原推导。
- p=po-pu、v=vo-vu；hd=p²-R²、psi1=2p·v+lambda1 hd；A=[p_x,p_y,0]，bn=p·vu+tau|v|²+tau p·ahat+tau(lambda1+lambda2)p·v+tau lambda1 lambda2 hd/2；b=bn−tau|p|Delta_a。独立推导及FD确认 **tau H=2(bn−Au)**。参数speed_threshold=.05m/s、lambda1=lambda2=2/s、admissibility_tol=1e-8m²/s均PROVISIONAL/TEST_ONLY；缺配置/disabled保留旧分支，正常速度逐字段冻结reference78对比exact。单阈值无状态、无blend/hysteresis。
- LOW_SPEED_DISTANCE_HOCBF为active/ready；psi1低于−tol保留有限recovery行但ready=false，两个adapter显式RECOVERY；d<=R仍unsafe。所选分支finite判断独立未选分支溢出。保留原h的m²/s单位，新hd/psi诊断仅结果对象，未改cache/spec。M8/K4/C14、actor70/critic174/action4不变。
- runtime继续M2 estimated p/v，UAV显式SIMULATION_ADAPTER，ahat=0/Delta_a=0；不读M1真v/a/future。D1真实启动加速度非零不被Delta=0覆盖，明确不提供实机/采样/切换系统不变性保证。
- 新16项focused覆盖CPUfloat64/float32、CUDAfloat32、静止/同速/hover/朝向限幅/切向远离、near-R/inside/psi恢复、mixed tracking、阈值往返、robust worst direction、正比例缩放、两个adapter与实际fallback绑定的M6noise归因。独立解析轨迹4cases×3dt：归一化H identity最大全步误差1.2104966806703032e-6，最细步最大5.4016435768744486e-8；原tauH形式误差各乘.4。TDD RED真实status3!=6，后GREEN及独立复跑RC0。
- 真实reset第一拍：D0的2static、D1的2static+2dynamic均UAV/M2velocity0、vrel0、hd/psi>0、LOW_SPEED有效行、ALREADY_SAFE、donefalse。partial reset env0之后，env1 tracker/motion/cache/IDs/UAV state保持，env1继续normal C3BF。env1第二decision出现真实ITERATION_LIMIT/done，未删证据或改fixture掩盖。
- 四组seed7103 scratch保持32collector steps×2PPO updates/每Adam4steps：D0 B8=512frames、execution32/512=6.25%、shadow33/512=6.4453%、fallback362/1024、完成episode均长12.9091(N33)；D0 B64=4096frames、execution289/4096=7.0566%、shadow281/4096=6.8604%、fallback2916/8192、均长10.5719(N292)；D1 B8=512frames、execution53/512=10.3516%、shadow51/512=9.9609%、fallback948/2048、均长9.1132(N53)；D1 B64=4096frames、execution340/4096=8.3008%、shadow331/4096=8.0811%、fallback6550/16384、均长9.6064(N343)。各组failure termination count等于execution failures；完成episode主要因失败结束，右删失N=7/57/6/56单列，不以此宣称学习成功。
- 四组producer inside/recovery/degenerate/tracking/numerical均0；所有失败均ITERATION_LIMIT。accepted execution=480/3807/459/3756，shadow=479/3815/461/3765，false_feasible全0；max accepted halfspace1.919269561767578e-5、ball3.5762786865234375e-7，均满足原2e-5容差。loss/gradient/parameters/ValueNorm/reward有限。全active行min_psi可在normal分支为负，不等同于fallback违规被接受。
- Solver greedy算法/5轮/full residual/XYZ ball/zero_terminate不变，safety_projection AST仅project_c3bf新增status薄映射。M6 reward公式/权重/attribution/time/cache、PPO/GAE、课程/bundle/OFF代码均不改。全部规定CPU/CUDA测试及dynamic CBF/reward/old58-D static真实Isaac RC0；实际OFF新PID 2episodes64steps、execution/shadow calls0、train RNG/curriculum保持；新bundle跨进程resume仅1update×2steps，512→528frames、updates2→3、Adam4→6，audit全true。非学习效果加长实验。
- 四份原始runner report保留自动NOT_READY_FOR_M7B（既有helper任一failure即保守拒绝）的pre-review字段；Reviewer按本轮用户§22单独得出有限debug READY，未改写历史/原始制品。既有§10.10的100%failure证据全部保留。
- 六命名代理实际参与，只有Orchestrator分派；runtime model/reasoning均NOT EXPOSED/NOT VERIFIED。核心实现由implementer完成；后续恢复implementer/watcher遇host thread limit，Orchestrator补最终test-only断言、保护审计与文档，test_runner独立复跑，reviewer最终PASS。原22,096项基线保护，源码只有6个授权既存文件变化（另自动pyc），outer ledger仅增补；未commit/push/stage/改子模块指针。
- Hydra long training/D2D3/multi-seed=NOT RUN；W&B=NOT USED。**推荐下一模块 M7b-D0-D1-debug-training，仅为建议；本轮完成后停止，不开始 M7b。**

### 10.12 M7b D0/D1 single-seed debug training 实际记录（2026-09-22）

- 本轮只执行了有限 D0 Phase A。固定 seed=7103、B64、collector T=32，D0锁定2个静态高柱/0动态/2 active，runtime filter ON、CBF reward ON、greedy_most_violated、max_iters=5、现有2e-5容差；49,152个完整collector frames（不超过50k上限），W&B/long training未使用。
- 新增隔离的有限编排入口 `OmniDrones/scripts/m7b_debug_training.py`，复用已经验证的 M7a finite runner，以 atomic model/bundle/report chunk 逐段 episode-boundary resume；动态 runner增加 `updates=0` 的真实frame-0 bundle和显式OFF episode数。OFF协议保留兼容默认2，可显式请求32。
- frame0及其后8个chunk均启动独立OFF worker，每次32 episodes、64-step上限；288 episodes全部timeout、strict_success=0；每个result runtime_filter=false、shadow_filter=false、execution_projection_calls=0、shadow_projection_calls=0，训练worker RNG/curriculum未被改变。
- 共24次PPO update（actor/critic各48 Adam steps）。70-D actor、174-D obstacle-privileged critic、4-D action、named time axis与ValueNorm均保持；loss/gradient/parameter finite，NaN/Inf=0。平均reward约-2.04到-2.41，无单调OFF改善，不能称为学习收敛。
- 真实D0 aggregate：execution queries=49,152，accepted=45,604，ITERATION_LIMIT=3,548，failure=7.2184%；shadow accepted=45,628，ITERATION_LIMIT=3,524，failure=7.1696%；STRUCTURAL_INFEASIBLE/NUMERICAL_FAILURE/其它失败=0；false feasible=0。最大accepted半空间残差execution=1.9863e-5、shadow=1.9670e-5，最大ball residual均2.3842e-7；rejected candidate独立计数。solver failure分布阻塞Phase A延长和D1。
- 每个resume bundle的model/optimizer/scheduler/curriculum/RNG/hash/schema audit均true；collector中未完成episode按既有resume合同清理，aggregate记录discarded_incomplete_episodes=415。由于D0学习/solver gate未满足，没有伪造D1 transition或D1 bundle，不进入500k extension。
- 结论：**PARTIAL_M7B_SOLVER_DISTRIBUTION_BLOCKED**。solver correctness（观测accepted集）PASS；M7b learning trend未确认；D1、D2/D3、自动curriculum、多seed、long training、checkpoint selection、refinement均NOT RUN/NOT IMPLEMENTED。rejected candidate只保留失败计数，未保留max rejected residual，列为下一次受门控实验的metrics gap。完整真实数据见 `OmniDrones/docs/m7b_debug_training.md` 与 `OmniDrones/docs/m7b_D0_B64_phaseA/report.json`。
- 回归：greedy projection/joint-query、C3BF/boundary、dynamic CBF/reward、training bundle、OFF protocol、GAE boundary与dynamic CBF/dynamic reward/static-profile Isaac smoke均通过；首次OFF协议回归发现默认episode兼容问题，恢复默认2并仅对M7b显式请求32后RC0。py_compile及内外`git diff --check`通过。未stage、commit、push、reset、clean或修改submodule pointer。
- agent运行元数据：explorer/watcher/architect均按用户要求只读完成；早期implementer因host thread限额未交付主体补丁，Orchestrator完成最小编排改动；后续test_runner/reviewer无法再spawn（host thread limit），因此runtime model/reasoning metadata均 **NOT EXPOSED / NOT VERIFIED**，不将TOML配置当运行证据。

### 10.13 M7b-D0 solver distribution review and budget selection（2026-09-22）

- 本轮仅做 bounded solver distribution review；没有修改 greedy/C3BF/reward/network/GAE/tolerances/profile，没有启动 D1、D2/D3、PPO scratch/long training、multi-seed、OFF 正式评估、commit 或 push。新增入口为 `OmniDrones/scripts/m7b_d0_solver_budget_review.py`，制品为 `OmniDrones/docs/m7b_D0_solver_budget_review/report.json` 与 `OmniDrones/docs/m7b_d0_solver_budget_review.md`。
- D0 B64 Phase-A 的真实 report 只有 aggregate status/residual，没有 per-query `A/b/mask/u_nom/u_max` 与 producer state。因此本轮明确复用既有固定 seed=7103、CUDA float32、Dual-noise、B256+B1024 failure corpus，未将其冒称 D0-B64 corpus；report 内 `exact_d0_b64_phase_a_per_query_capture=false`。
- corpus=545（execution272/shadow273），full query=256000/role，failure=32940/23785；deterministic replay 545/545，blocking mismatch=0，false feasible=0。64轮 review taxonomy（execution/shadow）：F1 budget-limited=253/245，F2 persistent=1/0，F3 oracle-infeasible=12/18，F4 inside=3/3，F5 recovery=3/7，F6 numerical/malformed=0/0，F7 unclassified=0/0。标签将旧 diagnostics F1_GREEDY_RECOVERABLE 映射为本轮合同 F1_BUDGET_LIMITED_FEASIBLE。
- 预算 sweep 5/8/16/32/64 均保存逐样本 status/feasible/residual/objective/first-feasible；扩展 replay 的 accepted 样本为 64/96/128/192/256/512/1024/2048轮=16/27/43/44/46/52/88/514（分母545）。所有 accepted residual 仍通过2e-5；oracle-infeasible、inside/recovery样本不因加轮数被混入可恢复类。near-tangent既有trace在64/96/128/192仍 ITERATION_LIMIT，192 residual≈2.12e-3，已知约1019–1067轮才可行。
- CUDA solver-only重新测 B2/B256/B1024 与5/8/16/32/64轮；最终记录的64轮 p99=13.798/14.189/14.196ms。该计时不是Isaac policy-step或生产实时保证；独立near-tangent trace的128轮仍未收敛（p99=27.693ms）。旧 D0 Phase-A aggregate仍为49,152 frames，execution/shadow ITERATION_LIMIT=7.2184%/7.1696%，false feasible=0，accepted halfspace最大1.9863e-5/1.9670e-5。
- 选择：**base max_iters=64 保持不变；second-stage refinement=NOT IMPLEMENTED；无全局128/192升级**。原因是 exact D0 per-query corpus 缺失，near-tangent在合理额外轮数仍不收敛，且新增轮数成本近线性；本轮没有足够 runtime-realistic continuation证据证明 masked fallback 收益。Frozen policy frame0/final runtime comparison未重新启动Isaac，沿用D0 report有限产物。
- 结论：solver correctness（本轮review corpus）PASS；D0 restart readiness=`NOT_READY_TO_RESTART_D0`，因为 exact D0 capture 缺失且真实D0 finite run仍约7% iteration-limit。下一模块唯一建议是先制作 exact D0-B64 bounded failure capture，再以真实rollout验证 masked continuation；不自动开始该模块。

### 10.14 M7b-D0 extended filter-ON training 编排实现（2026-09-22）

- 当前用户决策覆盖历史阶段门控：实现新的、隔离的 `M7b-D0-extended-filter-on-training-20260922-seed7103-B64T32-v1` 编排能力；实际已执行 bounded smoke 与 Phase C，未启动 Phase D/E 长程阶段。父 lineage 固定为 frame100352 bundle；D0、seed7103、B64/T32、M8/K4、runtime CBF ON、CBF reward ON、greedy/max_iters5、continuation/refinement off 及既有配置/schema hash 不变。
- 新 runner 支持 exact smoke `100352→102400`、Phase C `102400→499712`、编排用 Phase D `499712→999424`、编排用 Phase E `999424→1998848`；regular checkpoint=6144 与 C/D/E major union。当前只保留 smoke/Phase C 的执行入口，绝不自动跨阶段。RTX5090D 31GB 采用串行 train/eval、B64/T32，不为吃满显存扩大 batch；W&B=NOT USED，运行时元数据=`NOT EXPOSED / NOT VERIFIED`。
- `--no-off` 路径不生成 `off_request/off_result`、不启动旧 OFF worker，并在 aggregate/manifest/report 中明确 `OFF=NOT RUN`；旧默认 OFF 行为保持兼容。major checkpoint 后可串行启动独立 `m7b_on_eval_worker.py`，先按 B64 training config 验证 parent bundle/model sidecar/schema/stage/seed/frame identity，再用64/128 episodes构造 deterministic MODE runtime-filter-ON + CBF-reward-ON eval，原子 checksummed JSON 保存 raw nominal violation/correction/status/intervention/task metrics及 residual/false-feasible checks。
- 新增 targeted contract tests：no-off artifact guard、exact pair/major schedule、ON status/metric schema；7/7 contract tests、py_compile 与 `git diff --check` 通过。smoke ON64 完成，Phase C 训练到 499712，但最终 ON128 因 `RECOVERY_REQUIRED`（projection code6）硬停止，未启动 D1/D2/D3、Phase D/E 或 OFF ablation。**OFF runtime-filter ablation/evaluation deferred until completion of D0-D3 curriculum.**
- Reviewer hardening additionally pins the frame100352 bundle id/SHA/config/schema anchor, makes ON evaluation mandatory on the no-off path (64-episode smoke, 128-episode majors), preserves the reset-time start manifest, and enforces the 28 GiB warning / 30 GiB stop guard between serialized GPU jobs.
- 实际 bounded run：smoke `100352→102400` 与 Phase C 训练 `102400→499712` 已执行；smoke ON64 通过，Phase C 训练 bundle 完整落到 `499712`，但最终 ON128 观察到 `RECOVERY_REQUIRED`（projection code6），因此状态为 `CORRECTNESS_BLOCKED`，Phase D/E 未启动。失败记录保存在 `OmniDrones/docs/m7b_D0_extended_filter_on_20260922_seed7103_B64T32_v1/phaseC_499712/frame_499712/filter_on_failure.json`；OFF 仍为 **NOT RUN**，并保持 **OFF runtime-filter ablation/evaluation deferred until completion of D0-D3 curriculum.**

### 10.15 M7b D0 Gate A recovery diagnostic（2026-09-22）

- 状态：**HOLD / CORRECTNESS_BLOCKED**。本轮只增加独立、只读的 Gate A 诊断捕获/分类/双 replay 比较器；未修改 CBF 数学、solver、reward、PPO/GAE、fallback、action selection 或 termination，也未启动 Phase D、P1/P2/P3 pilot、Phase E 或 OFF ablation。
- 精确 frame499712 parent identity 已校验：bundle `20a832087a9e48e39b88a86d91442412`，bundle SHA256 `3a0af7cb5879875318d7d568a9f3ad2d3abc2f1cd45ecf0469cf49918841b82e`，config hash `5053861e3c6db7a49889f1f543de7c1664b47e45907a03f3393236ade72fa46a`；runtime metadata 保持 **NOT EXPOSED / NOT VERIFIED**。
- Gate A classifier 仅允许完整有限证据下的 `EXPECTED_HOCBF_RECOVERY` 或 `EXPECTED_INSIDE_UNSAFE`；code6 与 inside 混淆为 `SPURIOUS_RECOVERY_BUG`，code7/unknown/nonfinite/shape-dtype/tracking/inactive/mask/schema/hash/replay 问题 fail closed。比较器拒绝 `FAIL_CLOSED/UNCLASSIFIED_PENDING`，不会把缺失证据误报为 deterministic match。
- 验证：诊断测试 **6/6**、既有 M7b contract tests **7/7**、相关 `py_compile`、内外 `git diff --check` 均通过。此前成功 ON128 的 frame249856 结果提供了可校验固定场景 manifest：evaluation seed `8103`、ON filter/CBF reward、`scenario_manifest_hash=81c28b2c61faf75c436c1bdc1e6d2b6c611345ffe55a9967b2a3c6561b6e83e0`，且 config hash 与 frame499712 一致。
- 实际诊断：v1 两次因错误指定不存在的 frame499712 manifest 路径而正确 fail closed；改用 frame249856 manifest 的 v2 replay_1 启动 Isaac 后无结果文件，v2 replay_2 未启动，无法获得首个 code6/3/7/unknown 的完整 telemetry，也无法完成 deterministic comparison。故不能把旧 `UNCLASSIFIED_6` 改判为任何预期 recovery 类别。
- 资源/阶段纪律：GPU 回到约14 MiB idle，无遗留训练/评估进程；B64/T32 保持冻结，OFF 为 **NOT RUN: deferred until completion of D0-D3 curriculum**。下一步必须先取得可复核的两次完整 Gate A replay；在此之前不实现或运行并行 scheduler/pilot。

### 10.16 M7b Gate A replay lifecycle hardening（2026-09-22）

- 本轮仍为 D0 诊断，不改变生产 CBF/env/solver/reward/PPO/actor/critic/failure behavior，不启动训练、Phase D/E、P1/P2/P3 pilot 或 OFF eval。新增 `scripts/m7b_recovery_replay.py` 子进程生命周期包装器、`probe` 模式及对应纯测试；运行元数据保持 **NOT EXPOSED / NOT VERIFIED**。
- 包装器拒绝旧训练 artifact root 和非空输出目录；将 stdout/stderr、atomic heartbeat、超时/信号/退出码、最后逻辑 step、完整 checkpoint/bundle/manifest provenance 与 result existence 写入新的 `replay_lifecycle.json`。子进程异常、超时、缺结果、身份失败均 fail closed，不把 wrapper 成功误报为 Gate A 成功。
- 诊断脚本新增 bounded 1–3 step exact-scene probe，再允许 full capture；probe 必须同时满足 frame499712 identity、frame249856 fixed manifest reset equality、EVAL_SEED=8103、runtime filter ON、CBF reward ON、MODE、finite action/cache、valid cache。代码6 的 `EXPECTED_HOCBF_RECOVERY` 现在还必须由逐行 `h_d > 0` 与 `psi1 < -admissibility_tol` 证据支持；未暴露的 q 明确为 `NOT_AVAILABLE`，不以 A 冒充 q；静态障碍 relative velocity 证据按 runtime 的 zeroing 规则记录。
- 纯验证：recovery diagnostic/replay tests **10/10**，py_compile 通过。GPU probe/full replay 正由独立 test_runner 串行执行；只有 probe PASS 才运行 replay_1/replay_2 和 comparator。结果目录为 `OmniDrones/docs/m7b_D0_recovery_diagnostic_20260922_seed7103_v3/`，最终 Gate A 状态待实际制品与 reviewer 复核，不提前分类。

### 10.17 M7b Gate A recovery replay classified（2026-09-22）

- **最终状态：`GATE_A_CLASSIFIED / EXPECTED_OTHER_RECOVERY`；Reviewer PASS。** v8 使用全新目录和正确的 frame499712 checkpoint/bundle、frame249856 fixed manifest；probe 与两次 serial capture 均完成 `PROCESS_EXIT`，保留 `last_step=3/48`，exit=0、timeout=false、stdout/stderr/result/lifecycle checksums 完整。RTX5090D 仅使用约3–4.5GiB峰值，结束后约14MiB idle，未需要扩大 B64/T32。
- Probe `PASS`：runtime_filter=true、cbf_reward=true、finite=true、MODE、EVAL_SEED=8103、fixed manifest hash `81c28b2c61faf75c436c1bdc1e6d2b6c611345ffe55a9967b2a3c6561b6e83e0`。两次 capture 命令逐字核验 bundle 均为 `/phaseC_499712/frame_499712/training_bundle.pt`，没有复用错误 v7 的 frame249856 bundle。
- 首事件 deterministic match：`env_id=86`、`episode_id=0`、`reset_id=0`、`episode_step=48`、`decision_step_id=49`、`projection_status_code=6`、`runtime_status_code=8`；comparator=`DETERMINISTIC_MATCH`。两份结果均 `gate_a=PASS_CLASSIFIED`、`classification=EXPECTED_OTHER_RECOVERY`、checksum 相同。
- evidence validation 全部 true：finite、tracking、inactive mask、A/b/mask reconstruction、shape/dtype。producer reason=`BOUNDARY_ADMISSIBILITY`；safe-center box 内、boundary h 非负且 boundary psi1 为负；`inside_unsafe=false`。debug telemetry 同时保存 `h_d/dot_h/distance_h/distance_psi1`，normal q 明确 `NOT_AVAILABLE`，runtime metadata 仍 **NOT EXPOSED / NOT VERIFIED**。
- solver evidence 如实保留：`greedy_most_violated`、`max_iters=5`、`continuation=false`、`feasible=false`、`iterations=5`。该分类只完成 Gate A code6 现场归因，不解锁训练；Phase D/E、P1/P2/P3 pilot、OFF evaluation 仍 NOT RUN，B64/T32 与生产 failure behavior 继续冻结。
- 回归：最新 test_runner report 为 diagnostic **9/9**、replay wrapper **3/3**、py_compile、git diff --check 全部 RC0；final reviewer **PASS**，不再运行 GPU。v3/v4/v5/v6/v7 旧失败/字段/错误参数记录保留，不覆盖历史；未 stage/commit/push/reset/clean。

### 10.18 M7b-D0 parallel long filter-ON training（2026-09-22）

- 新增隔离的 `OmniDrones/scripts/m7b_parallel_child.py` 与 `m7b_parallel_training.py`。child 复用既有真实 Isaac/PPO/filter-ON/CBF-reward 构建，支持 1–512 个 PPO update、episode-boundary bundle resume、A exact RNG restore、B/C stable fork seed；scheduler 只负责 lineage、进程隔离、资源采样、并发 pilot、ON semaphore、阶段门禁与 metrics，不改 solver/C3BF/reward/PPO/GAE/ValueNorm 或 profile。
- 父快照严格固定为 frame499712：bundle `20a832087a9e48e39b88a86d91442412`、bundle SHA256 `3a0af7cb5879875318d7d568a9f3ad2d3abc2f1cd45ecf0469cf49918841b82e`、checkpoint `871352ce289e4cb1995046b63f1a7084`、config hash `5053861e3c6db7a49889f1f543de7c1664b47e45907a03f3393236ade72fa46a`；fixed ON scene manifest hash `81c28b2c61faf75c436c1bdc1e6d2b6c611345ffe55a9967b2a3c6561b6e83e0`。新制品根为 `OmniDrones/docs/m7b_D0_parallel_long_filter_on_20260922_seed7103_v1/`，不复用 v8 或父目录。
- 资源门禁固定 warning=28 GiB、hard stop=30 GiB；scheduler 记录 GPU used/utilization、child RSS、CPU/RAM，并在 hard stop 时只终止本轮子进程。Pilot 设计为 1/2/3 并发各8次 PPO update、无 ON eval，按 aggregate transitions/s 选择最高合格并发；ON eval 通过跨进程 semaphore=1 串行，测量 overlap 的 VRAM delta 与 throughput drop，超过20%或不安全则 checkpoint-boundary pause/eval/resume。
- collector batch=2048，1,000,000 请求帧按完整 batch 落在 `actual_target=1,001,472`；D0 major checkpoint 为 749,568、999,424、1,001,472，各分支固定128-episode ON eval。Phase E=NOT RUN，只有至少2/3分支有可信趋势且 correctness/resources 稳定才可授权；D1=NOT STARTED；OFF=NOT RUN。
- ON evaluator 现在把 code3 `INSIDE_UNSAFE_REGION` 与 code6 `RECOVERY_REQUIRED` 计入 `boundary_admissibility_failure`，仍对 unknown status、false feasible、NaN/Inf、残差超容差及身份/schema/hash错误 fail closed。两类状态仅是安全分布失败，不被误报为软件 bug。
- 本节创建时 test_runner/reviewer 尚未完成；该历史状态已由后续 §10.19 的最终本地测试与真实执行记录覆盖。原计划仍保持：不启动 D1、OFF 或 Phase E，除非新门禁明确授权。

### 10.19 M7b-D0 parallel long filter-ON training 实际执行结果（2026-09-22）

- 最终状态：**`PARTIAL_D0_LEARNING_BLOCKED`**。实现、真实 GPU 执行、资源采样、并发 pilot、ON semaphore/eval、lineage 与硬停保护均完成；没有 commit、push、reset、clean 或修改既有脏工作区。
- 最终制品根为 `OmniDrones/docs/m7b_D0_parallel_long_filter_on_20260922_seed7103_v5/`，父快照仍为 frame499712 bundle `20a832087a9e48e39b88a86d91442412`。RTX5090D 可用显存按31GiB处理，scheduler warning=28GiB、hard stop=30GiB；全程无OOM/hard stop，训练结束 GPU 回到约14MiB idle。
- 真实 pilot（每个并发8次 PPO update）均通过：并发1=`879.148` transitions/s、峰值`5.44GiB`；并发2=`1202.648`、`11.87GiB`；并发3=`1326.284`、`17.27GiB`。因此选择并发3。overlap artifact 已生成，但由于 ON eval residual gate 失败按 `PAUSE_AT_CHECKPOINT` 保守处理，没有把 overlap 当作安全通过。
- 选定并发3后，A/B/C 三个分支均完整训练至749568 frames，aggregate=`1759.813` transitions/s，三个 training bundle/model/report 与资源记录均完整。随后固定128 episode ON eval 均出现 `max_residual` 超限：A=`0.3469409`、B=`0.2778940`、C=`0.3400257`，容差均为`2e-5`；false feasible=0、status anomaly=0，identity/scene/schema检查通过。故在749568后停止，未运行999424或1001472。
- scheduler最终 `report.json` 的状态为 `PARTIAL_D0_LEARNING_BLOCKED`；Phase E=`NOT RUN`，D1=`NOT STARTED`，OFF=`NOT RUN`（继续保持“D0-D3 curriculum完成前不做OFF ablation/evaluation”）。该 residual 是实际安全分布门禁，不改判为资源故障，也不伪造学习趋势。
- 最终回归：相关脚本 `py_compile` RC0；M7b parallel contract tests 6/6、debug tests 7/7；此前完整指定回归合计46 passed、4 warnings；nested/outer `git diff --check` 均通过。详细实现见 `OmniDrones/scripts/m7b_parallel_child.py`、`m7b_parallel_training.py`，结果见 `OmniDrones/docs/m7b_D0_parallel_long_filter_on_20260922_seed7103_v5/report.json`。
- 下一步唯一建议：先针对固定 ON eval 的 residual/solver safety-distribution gate 做受门控诊断与 exact capture，再决定是否恢复 D0；不自动开始 Phase E、D1 或 OFF。

### 10.20 M7b-D0 ON residual gate diagnostic（2026-09-22）

- 最终状态：**`REJECTED_CANDIDATE_GATE_BUG`（B）/ evaluator v2 PASS / `READY_TO_RESUME_PARALLEL_D0_TRAINING`**。完整静态 inspection、branch-A 身份、两次 replay 首事件、A/b/mask/action hashes、float32/float64 独立重算、review、ON128 统计、资源与 artifact SHA256 见 [交付文档](OmniDrones/docs/m7b_d0_on_residual_gate_diagnostic.md)。
- 原 evaluator 将所有 live candidate 的 `solver_residual` 取最大，scheduler 却将其解释为 accepted residual。两次独立 replay 的首个触发均为 step4/env21，decision IDs `4/4/4`，status5 `ITERATION_LIMIT`、feasible/executed/accepted 均 false；candidate halfspace residual `2.1755695343e-5`，float32/float64/cached 完全一致，rejected candidate 未执行，zero-XYZ fallback 与 controller target 保持分离。因此不是 A/C/D/E；accepted/rejected 聚合混淆是伴随统计缺陷，但它实际触发 blocker，按冻结决策树以更具体的 B 为主分类。cached/f32/f64 一致仅排除 producer/reconstruction mismatch，并不排除 aggregate-label defect。
- 最小修复只改变 evaluator/statistics/runner contract：显式拆分 solver-claimed、final accepted、rejected；claimed/accepted candidate 与 accepted controller 按原 halfspace/ball tolerance gate；rejected maxima 只诊断；检查 rejected zero-XYZ execution、runtime status9、非有限值与 `t_k` decision-step 对齐。schema=`M7b-D0-FilterOn-v2`。solver、C3BF、reward、actor/critic、GAE/PPO、controller/fallback 数学和 `2e-5` 容差未改。
- 同 branch-A/frame749568/seed8103/scene ON128 修复后 RC0：4453 samples，claimed/accepted/rejected=`4356/4356/97`；status=`422 ALREADY_SAFE + 3934 PROJECTED + 97 ITERATION_LIMIT`；accepted candidate/controller halfspace max均`1.953355968e-5`，all/rejected max仍`0.3469409347`；false feasible、controller/time/execution/nonfinite/status anomaly均0。资源 gate true，GPU max `6,280,970,240` bytes，无 hard stop。
- `timeout=128` 是兜底终止桶，**不得表述为128条均跑满**：其中97个 `ITERATION_LIMIT` 早停，episode length min/max/mean=`4/64/34.7890625`。strict success/arrival=0，本诊断不声称学习收敛。
- read-only Phase1 reviewer=`APPROVE_MINIMAL_EVALUATOR_FIX`；Phase2 reviewer=`FINAL_APPROVE`，blocker none。最终 CPU 回归为9个脚本68 tests全通过：worker6、diagnostic7、parallel9、recovery diagnostic9、dynamic CBF9、dynamic reward8、stationary fallback16、training bundle1、recovery replay3；static-profile、dynamic-CBF、dynamic-reward 三个真实 Isaac smoke 以独立进程串行运行并全部 PASS。py_compile 与 inner/outer diff-check RC0。
- §10.19 的 `PARTIAL_D0_LEARNING_BLOCKED` 保留为历史 stop artifact；其 residual blocker 已被本诊断解除，但训练尚未恢复，本模块 Phase D continuation/E/D1/OFF 均 **NOT RUN**。下一模块 exactly **`M7b-D0-parallel-long-filter-on-training-resume`**，**DO NOT START**。

### 10.21 M7b-D0 parallel long filter-ON training resume（2026-09-22）

- 最终状态：**`PARTIAL_D0_SAFETY_DISTRIBUTION_BLOCKED`**；完整 lineage、事前冻结 gate、训练/ON128/PPO/reward/raw-policy/boundary/resource/checksum-repair/test/reviewer 证据见 [交付文档](OmniDrones/docs/m7b_d0_parallel_long_filter_on_training_resume.md)。Phase E=`NOT RUN`，OFF=`NOT RUN`，D1=`NOT STARTED / NOT_READY_FOR_D1`。
- A/B/C 分别从自己的 frame749568 full bundle exact resume；bundle IDs=`47f437…/0bd571…/347124…`，未从共同 frame499712 重新 fork。model/critic/ValueNorm、optimizer steps、Python/NumPy/Torch CPU/CUDA RNG、D0 curriculum、config/schema 全部 audit PASS；三支只称 future-RNG continuations，不称独立 seeds。
- 算法完全冻结：D0 B64/T32、M8/K4、static2/dynamic0、actor70/critic174、runtime filter ON、CBF reward ON、greedy_most_violated/max_iters5/continuation=false、tolerances=2e-5；config hash=`5053861e…fa46a`。只新增 resume/eval/resource/metrics/report plumbing；production algorithm=`UNCHANGED`。
- 在任何未来帧结果前冻结 `FROZEN_GATE_V1`，最终 hash=`d0082a1b…9e85`。先串行补 A/B/C frame749568 evaluator-v2 baseline，再完成三进程 exact one-update smoke；随后正式并行 `749568→999424→1001472`，两个 checkpoint 的 ON128 均严格 A→B→C 全局串行。主段 aggregate throughput=`1747.52 transitions/s`，VRAM mean/p95/max=`16.961/17.325/17.325GiB`，GPU util=`85.08/89/90%`，温度最高42C，无 OOM/hard stop；结束回到14MiB idle且无残留进程。
- 两个 Phase-D ON128 的 accepted correctness 全部 PASS：全局 accepted/controller halfspace max=`1.9729137421e-5`、ball=0；training execution/shadow accepted halfspace max=`1.9967556e-5/1.9997358e-5`；false feasible、controller/time/execution/nonfinite/status anomaly均0。rejected halfspace max=`0.5399950743` 仅作诊断，不再污染 accepted gate。
- 1001472 A/B/C 的 strict success/arrival均0；goal progress=`-0.011405/0.008370/0.001994`，final distance=`5.011405/4.991630/4.998006m`，三支在999424与1001472均 `outcome_gain=false, distance_gain=false, improve=false`，credible branch count=0。PPO/ValueNorm/parameter/update norm全有限且 optimizer 732→978，但无可信任务学习趋势。
- 冻结 safety gate 的直接 blocker 是 B rejected/live-step rate：749568=`84/5067=0.016578`，999424=`125/2079=0.060125`，1001472=`125/2154=0.058032`，超过 baseline+0.01。v2 episode records 证明1001472的兼容 timeout桶128实际为 A `42 time-limit+86 IL`、B `3+125 IL`、C `27+100 IL+1 recovery`；不能把128表述为全部跑满。A/C per-branch safety及三支 collision/crash/OOB/intrusion aggregate gate均通过。
- 合法 boundary recovery 仅 C 各点1次：baseline/999424/1001472 的 rate=`0.0002480/0.0003334/0.0003275`，episode step=`49/59/50`，均为z_min且完整保存 h/psi1/UAV position/velocity/raw action。它未触发冻结边界率 blocker，也未误判成 correctness bug。
- post-run 发现两份顶层报告因整数 frame key 在 JSON 落盘后转字符串而 checksum 不可复验；TDD 增加 scheduler-local string-key canonicalization，保留原文件备份与 repair manifest，仅重封 checksum，pre/post body和 gate决定不变。最终正式根45/45 JSON、6/6 bundles/models、9/9 eval payload/envelope均复验通过。
- 最终验证：请求的9个CPU脚本预检共55 tests、最终 parallel16/child2/worker7/training-bundle1、static/dynamic真实Isaac smoke、py_compile6、内外diff-check、三进程resume smoke全部PASS；独立 reviewer=`FINAL PASS`。未stage/commit/push/reset/clean，既有脏工作区与旧 artifacts保留。
- 不授权 Phase E、D1 或 OFF，也不调整 solver/tolerance。下一模块 exactly **`M7b-D0-safety-distribution-diagnostics`**，聚焦 B 在749568/999424/1001472固定ON128上的 rejected/ITERATION_LIMIT 分布变化；**DO NOT START**。

### 10.22 M7b-D0 safety-distribution diagnostics（2026-09-22）

- 本模块按冻结范围完成：真实 ON capture 覆盖 A/B/C 的 `749568/999424/1001472`，每 checkpoint 每 role `16,384` live solver queries（全 corpus `294,912` rows），保存 actor loc/scale、raw/filter/safe action、joint A/b/mask、obstacle/boundary producer states、state/estimates、solver fields、reward/termination flags。production solver 保持 `greedy_most_violated`、`max_iters=5`、`continuation=false`、halfspace/ball tolerance=`2e-5`；没有 PPO update、Phase E、D1 或 OFF。
- transition copy-on-write cache 修正后，冻结 production replay contract **PASS**：status mismatch=`0`、feasible mismatch=`0`、candidate/residual 全部在 frozen tolerance 内。首轮 base-cache capture 仅作为 retry audit 保留，最终 corpus 只合并 transition-corrected `captures_v2`。
- CPU float64 oracle 对全部 IL rows（execution+shadow 共`10,536`）分类：`F1_BUDGET_LIMITED_FEASIBLE=8,298`、`F2_GREEDY_PERSISTENT_MISS=2,064`、`F3_TRUE_INFEASIBLE=174`；true-infeasible attribution=`ball_budget 20 / obstacle_boundary 152 / obstacle_only 2`。故 `ITERATION_LIMIT` 未被当作 infeasible 证明。
- 约束归因的 IL denominator=`5,268`/role；last-selected 主要为 `x_min=57.86%`、`obstacle_1=21.18%`、`obstacle_0=21.00%`，normalized nominal attribution 为 `x_min=61.05%`、`obstacle_1=20.25%`、`obstacle_0=18.62%`。B rejected/live-rate 变化与预算受限 F1 群体均应由后续决策树结合 same-state 结果解释，不能直接归因于策略退化。
- immutable `BANK_EARLY=B749568` 与 `BANK_LATE=B1001472` 各`4,096` states，比较 B749/B1M/A1M/C1M deterministic mean 及 common fixed-epsilon action；same-state matrix 已保存。training logs 的 episode lengths、right-censored lengths、useful non-solver fraction 与 ON termination cause（timeout/IL/recovery/collision/OOB）分开记录；GAE 只做 read-only semantics check（bootstrap=`~terminated`，trace boundary=`done|truncated|terminated|traj_id change`）。
- 当前证据决策为 **`MIXED`**：replay correctness 已解除；有限预算可行群体明显大于 persistent greedy miss，且存在少量 true infeasible。该结论不授权 solver/continuation 调参，不授权训练恢复、Phase E、D1 或 OFF；完整制品见 `OmniDrones/docs/m7b_D0_safety_distribution_diagnostics_20260922_seed8103_v1/report.md`。

### 10.23 M7b-D0 continuation ablation and horizon recovery（2026-09-23）

- 本模块最终状态：**`PASS_CONTINUATION_SOLVER_ONLY_BENEFIT`**。生产默认未改变：global continuation=`OFF`；base backend=`greedy_most_violated`；base max_iters=`5`。Treatment 仅在 experiment-local profile 启用 `greedy_continue`、`masked`、`extra_iters=16`；未改成32/64，未修改 reward/PPO/GAE/ValueNorm/tolerance/base solver。
- 当前分布审计复用上一模块冻结 corpus/replay：F1=`8,298`，base5+candidate16 recovered=`3,222`（`38.828633%`），unresolved=`5,076`；F3 accepted=`0`，false feasible=`0`，最大 accepted halfspace=`1.9907951355e-5`、ball=`0`，production replay contract 仍 PASS。既有 runtime evidence 的 failure-rate reduction=`4.08–4.97pp`、P95 overhead=`1.0718–1.0733x`、false feasible=`0`，因此16候选通过且被冻结。
- A/B/C parent 均为 frame=`1,001,472`。六条 control/treatment lineage 两两恢复相同 parent bundle 与 exact parent RNG hash；pair equality、base5、arm-only config checks 全部 PASS。真实 Isaac control/treatment short smoke 各1次 PPO update 均 PASS；随后按三进程两wave完成六条stage-1 lineage到collector-aligned frame=`1,251,328`（B64/T32，122 updates）。
- Frozen-policy ON128 在固定 evaluation seed=`8103`、同一固定场景协议、全局串行ON semaphore下完成。A/B/C treatment相对control的 rejected-rate reduction=`20.12%/52.25%/33.60%`，median episode length delta=`+17.0/+10.5/+8.0`，continuation recovered/invoked=`410/485`、`1,186/1,290`、`870/958`；false feasible、controller/time/nonfinite errors均0，recovery-retained-failure/termination=`0`。frozen gate PASS。
- 1.25M ON128 后 solver/horizon效应仍在：A/B/C rejected-rate reduction=`62.49%/37.36%/53.75%`，median episode length delta=`+16.0/+11.5/+20.5`，useful-step fraction delta=`+3.91/+2.22/+3.11pp`。但 task/raw-policy proxy 未改善：三对 goal progress/final distance 未通过非回归门，treatment训练 exposure 中 nominal violation/correction明显增加；PPO loss/entropy/std/gradient/ValueNorm/update/reward均finite，非数值不稳定解释不了horizon变化。
- 因而按预冻结决策树分类为 **`CONTINUATION_SOLVER_ONLY_BENEFIT`**：说明solver truncation链条真实存在，但不是唯一learning blocker；Stage 2=`NOT RUN`（仅`CONTINUATION_BENEFICIAL`才允许），OFF=`NOT RUN`（继续延期至D0-D3 curriculum完成），D1=`NOT RUN`。下一模块唯一建议为 **`M7b-D0-learning-signal-diagnostics`**，不要自动开始。
- 完整交付见 `OmniDrones/docs/m7b_D0_continuation_ablation_20260923_seed8103_v1/report.md` 与 `report.json`；附带 current-distribution audit、parent/fork manifests、6份child reports、冻结ON128和1.25M ON128 payload。模块运行中未commit、push、reset、clean或修改submodule pointer。

### 10.24 M7b-D0 continuation ablation 延长至10M后的效果诊断（2026-09-23）

- 六条 lineage 均从各自 `1,251,328` frame stage-1 bundle exact resume，分9个chunk完成到 collector-aligned `10,000,384` frames；A/B/C 各自 control/treatment 的所有 chunk frame 边界、child status、continuation arm、NaN/Inf 检查均 PASS。正式训练制品为 `OmniDrones/docs/m7b_D0_continuation_ablation_10m_20260923_seed8103_v1_retry1/`。此前因预写 `run.log` 触发 child 非空目录保护的初始目录保留为失败审计现场，不参与分析。
- 最终 ON128 fixed-policy evaluator 六份均通过 schema/residual/identity 校验，使用相同 `EVAL_SEED=8103` 与 ON 协议；OFF、D1、Phase E 未运行。control/treatment 的 strict success 与 arrival 均为 `0/128`，但 treatment episode length 相对 control 为 A/B/C `+3.438/+11.703/+7.109` steps，最终未解决 rejection rate 分别为 `3.77% vs 4.75%`、`3.80% vs 7.36%`、`3.37% vs 5.11%`。
- treatment 的 raw actor/filter 指标在三对全部升高：raw nominal violation 增量 `+0.260836/+0.143843/+0.141499`，executed filter correction 增量 `+0.335274/+0.209915/+0.183859`；goal progress 增量为 `-0.002108/+0.000637/-0.000227`，没有一致任务改善。treatment continuation recovery 为 `1064/1180`、`860/982`、`566/677`，恢复后保留 failure/termination 均为0。
- 8,749,056-frame continuation segment 的 weighted telemetry 同样显示 solver failure 降低但 raw violation/correction 增加：A/B/C treatment failure rate `4.36%/4.36%/4.40%`，对应 control `7.73%/9.89%/9.69%`；final chunk treatment actor std 为 `0.3195/0.3044/0.3073`，高于 control `0.1818/0.2448/0.2201`。critic explained variance 为 finite 且 treatment final chunk `0.9798/0.9521/0.9199`，不能仅凭10M telemetry归因于 critic collapse。
- 10M effect diagnostic 状态：**`PASS_CONTINUATION_SOLVER_ONLY_BENEFIT_AT_10M`**；primary=`CONTINUATION_SOLVER_ONLY_BENEFIT`，secondary=`FILTER_DEPENDENCE_PRESENT`。这证明 continuation 在更长训练后仍主要提供 solver/horizon benefit，同时 actor 对 safety layer 的依赖增强；不能证明 navigation learning 改善。
- 完整效果报告见 `OmniDrones/docs/m7b_D0_learning_signal_diagnostics_10m_20260923_seed8103_v1/effect_report.md` 与 `effect_summary.json`；新增只读汇总工具为 `OmniDrones/scripts/m7b_10m_effect_diagnostic.py`。由于本次仅基于训练 telemetry 与 ON128 evaluator，transition corpus、GAE replay、raw/safe per-transition attribution、diagnostic backward 尚未完成，full learning-signal classification 保持 **`INCONCLUSIVE_WITHOUT_TRANSITION_CORPUS`**。未commit、push、reset、clean或修改submodule pointer。

### 10.25 M7b-D0 velocity-loop and raw/safe-credit diagnostic（2026-09-23）

- 最终状态：**`MIXED_DYNAMICS_MODEL_MISMATCH x CREDIT_MISMATCH`**。诊断严格只读：PPO optimizer updates=`0`，未改变 production CBF/reward/PPO/controller/solver；production contract 固定为 `greedy_most_violated`、base `max_iters=5`、continuation OFF。resolved contract 来自10M control bundle，config hash=`5053861e…fa46`，physics/policy decision dt=`0.01s`，`tau=0.4s`，`max_vel=1.8m/s`。
- action-chain contract 已锁定为 policy `[vx,vy,vz,yaw_pi]` world-frame → optional noise → DynamicCBF → direction-preserving velocity norm clamp → yaw clamp/π conversion → Crazyflie `LeePositionController` → Isaac physics → measured world velocity。独立 harness 明确标记 **`CONTROLLER CHARACTERIZATION ONLY`**，不加载 policy、不经过 CBF、不做 PPO update；协议冻结在实测前，覆盖 x/y/z 正负 step、0→±v→0、PRBS-like、XY coupling、yaw=0，并保留 controller target/low-level command/physics-state/decision timestamps。
- Isaac controller characterization 共`374,528` rows；held-out M1/M2/M3 辨识显示当前 `K=1,tau=.4s,delay=0` 一阶模型不充分：x/y M2 最优候选为约6 decision-step delay且一阶增益拟合失稳，z 同样偏离当前模型。把辨识模型用于10M ON accepted-action one-step prediction时，M2/M1 RMSE 约为`0.0114/0.0173`（A）、`0.0110/0.0179`（B）、`0.0102/0.0154`（C）。因此保守分类为 mixed dynamics mismatch，不把单一tau更新当作已证实修复。
- 从10M A/B/C control 的真实 filter-ON transitions 各采集`16,384` rows，保留 obs、actor loc/scale/raw log-prob、raw/filter/safe/controller-target action、CBF A/b/mask/status/violation/correction、reward_cbf components、value/next-value/return/GAE inputs、raw/safe goal vectors、termination/reason 与 model hash。accepted safe/controller-target residual 均在`2e-5`内；静态 obstacle C3BF relative-velocity contract 保持 zeroing；x/y/z boundary 与 z_min face 均有 raw/safe 分项审计。
- credit evidence：A/B/C raw-unsafe rate=`19.08%/39.08%/25.43%`，filter rescue=`14.39%/30.99%/19.95%`；raw-unsafe normalized advantage mean=`-0.5685/-0.2032/-0.5287`，accepted-safe=`+0.1340/+0.1304/+0.1803`，但 rescued rows 中 positive-advantage 比例=`16.28%/33.22%/17.81%`，超过冻结`10%`阈值。CBF reward labels 对 violation/correction 的 rank correlation 为`0.78–0.86`，少量 failure-label sign mismatch 来自失败行的显式 failure semantics；这支持“filter provides insurance / raw-safe credit mismatch”，不声称 safe action 有 PPO likelihood。
- acceptance 全部 PASS：contract/action-pipeline、冻结协议、controller-only harness、synthetic first-order/delay fitter、CBF one-step/r_cbf sensitivity、held-out fit、三 arm corpus、two-dimensional analysis、optimizer/hash audit 均通过；model hash before==after，production source 未改。完整制品见 `OmniDrones/docs/m7b_D0_velocity_loop_credit_diagnostic_20260923_seed8103_v1/`，工具为 `OmniDrones/scripts/m7b_D0_velocity_loop_credit_diagnostic.py`。
- 解释与下一步：10M continuation benefit 不能归因于 navigation learning；当前证据同时显示 velocity-loop model mismatch 与 raw/safe credit mismatch。继续保持 D1、OFF、Phase E 与任何 production solver/reward/controller/tau 调参 **NOT RUN / NOT AUTHORIZED**；若进入下一步，应先在冻结协议下做独立 dynamics-model redesign proposal 与 raw/safe credit attribution review，再决定是否设计受门控实验。

### 10.26 Gate 1 — velocity-loop system identification（2026-09-23）

- 最终状态：**`GATE_1_BLOCKED`；`NOT_READY_FOR_GATE_2`**。本记录只完成 Gate 1，不启动 Gate 2。没有训练或 PPO optimizer step；production CBF/C3BF/HOCBF、controller、reward、solver、tau/config 与 training artifacts 未改；capture manifest 的 protected source before/after hashes 一致，`cbf_used=false`、`policy_used=false`、`optimizer_updates=0`。
- 冻结 contract：policy action `[vx,vy,vz,yaw_pi]` 的 XYZ 是 environment/world-frame m/s，yaw 乘 π 得 heading；`VelController` norm cap=`1.8m/s`，实际 Crazyflie `LeePositionController` 接 Isaac physics，反馈 `base.drone_state[:,0,7:10]`。resolved decision/physics dt=`0.01s`，substeps=`1`，100Hz；source profile tau=`0.4s`。M0 为此 tau 的 exact ZOH 等效；M1/M2/M3、阈值和 whole-trial split 见 protocol 与 control contract。唯一 fit 专用性能优化使用每 trial-repeat 的回归充分统计；固定种子 naive row-level bootstrap 对比测试在 `rtol=1e-7/atol=1e-8` 下通过，训练/验证 whole-trial-repeat 重采样与 delay 重选、抽样次数不变。capture-time script hash=`12bc27b1…9377a502`；fit-time script hash=`d2e1f1bf…e2035a40`，差异和 provenance sidecar 已明确记录，不与 capture hash 混用。
- protocol 在 acceptance capture 前冻结，含40 families×5固定 seeds=`200` trial IDs，train/validation/test=`120/40/40`，每 trial 3 repeats；包含 x/y/z 正负 steps、PRBS、多步、XY/XZ/YZ coupling、yaw0/yaw45 与 moving-start。一次初始可行性 pilot 发现零 setpoint 下稳定 z velocity bias≈`−0.0396m/s`，因此冻结协议用稳定 pre-baseline 并拟合 offset；pilot 未纳入数据。一次错误 `omni.timeline` clock 的完整采集被拒绝保存，后续改用 `Isaac SimulationContext.current_time`；1 trial/3 repeats clock preflight 的 decision/controller dt 均值=`0.0099999998s`、std=`0` 后才运行 canonical capture。
- canonical real Isaac corpus=`566,798` rows / `200` trial IDs / `600` repeat runs。decision、physics、policy decision clocks均值/最小/最大=`0.0099999998s`，std/jitter=`0`；controller sim timestamp `n=566,797`，integrity PASS。capture SHA256=`fa7f1773c505a5e9b0d3e214b176c5b12fdacaed3bad8cd4c59bd15403c8d499`；protocol SHA256=`de7011e8549da51dba0d019117b577bfef54a8b0ead82a13e0ffcb237e05afdc`；contract SHA256=`7cfee18c2b7df2c15e77d362a67f76757ed251a355124f9e0c773e0bc4aacf9a`。
- held-out open-loop rollout RMSE（M0/M1/M2/M3，m/s）：X=`0.09583/0.22841/0.14240/0.05331`，Y=`0.09747/0.22982/0.14408/0.05323`，Z=`0.06342/0.05917/0.04478/0.03806`。M3 相对 M2 聚合改善=`56.35%`，达到 material second-order effect。M2 gain K X/Y/Z=`0.9781/0.9779/0.9295`；tau=`1.227/1.226/0.593s`。X/Y delay均选中 search max `10` steps，bootstrap delay CI亦在边界，因此明确是 `RIGHT_CENSORED_AT_SEARCH_MAX`，不是精确 delay estimate。模型推荐已 suppressed；未提出 production surrogate。
- yaw/frame gate 未通过：yaw0 平均 heading 误差约`0.0002/0.0215/0.0001rad`；yaw45 实际平均 heading约`0.016/−0.016/−0.0002rad`，相对 π/4 的误差=`0.770/0.801/0.786rad`。因此 yaw45 heading 没有到达目标，跨 heading 的增益比较不支持坐标-frame-bug结论；最终标记 `INCONCLUSIVE_YAW_TRACKING_UNVERIFIED`，secondary 包含 `YAW_TRACKING_UNVERIFIED`、`DELAY_SEARCH_BOUNDARY_HIT`、`SECOND_ORDER_EFFECT_MATERIAL`、`OPERATING_POINT_DEPENDENT`。不能将此 fit 用来确认第一阶 surrogate 或 controller frame contract。
- 与旧 `374,528`-row diagnostic corpus 的单独 historical cross-check 标为 **`PARTIALLY_CONSISTENT`**：两次 analysis 都显示冻结 M1 不充分；但旧 X/Y M2 alpha>1、tau=null、K≈`1.11e6/7.54e5`，旧 Z tau≈`28.03s`、K≈`34.78`，与新估计明显不一致。旧协议无 yaw probe、以 batch64 采样、75/25 cycle split，且旧指标是一步 row prediction，不能和新 whole-trial split 的 open-loop rollout RMSE 数值直接比较。逐维度检查还确认：旧 fit 没有 operating-bin/饱和分层分析、虽做 simultaneous XY excitation 但没有报告 cross-axis 模型项，也没有参数或 trial-bootstrap CI；因此旧 valid operating region、cross-axis consistency 与 uncertainty overlap 均为 **NOT ESTABLISHED / NOT COMPARABLE**。旧拟合只作定性历史参考，未并入或重拟合 Gate 1。
- 最终 reviewer 结果：**BLOCKED**。未满足 Gate 1 的 yaw/frame sanity；X/Y delay 右删失；M3 material improvement 说明一阶模型结构不充分。要解除 blocker，需要先冻结并运行可确认 yaw target tracking 的独立 capture；若要估 X/Y delay，另行冻结扩展搜索范围及新的 held-out protocol，再重新验证。Gate 2、CBF re-derivation、tau/config 调整都保持 **NOT STARTED / NOT AUTHORIZED**。
- 制品与 evidence hashes：`OmniDrones/docs/gate1_velocity_loop_system_id_20260923_v1/`；fit SHA256=`7ba2526f535ee584c65f376d886b9577a874e9f3bfda9c5e7656a8bed0b525f5`，report SHA256=`b4cdc2375a9cf861f1cc986850640a9b84b07cb36587bcddfe9b985decd2f3f0`，legacy cross-check=`df56d63e24e71f621612293fd77abae5c23c01fae5f7b0d3fd7a40cfd42d8b1f`，fit provenance=`59f9153776f53fa1874338235991a6ca4cf7b05c0806e5c4dd4aae0bd38d9419`。Fit/report/manifest/clock/coupling/saturation/bootstrap/step analysis 与 trial index 均在该目录；未 commit/push。

### 10.27 Gate-1B — runtime yaw/frame, delay and model-structure resolution（2026-09-23）

- **最终状态：`GATE_1_BLOCKED`；primary=`YAW_CONTROLLER_RUNTIME_BLOCKED`；Gate 2=`NOT_READY`。** 本轮只运行 Gate-1B Stage-1 诊断；Stage-2 扩展 delay、M2/M3 重拟合、held-out 比较、operating/saturation/coupling、bootstrap 和 Gate-2 模型输入全部 `NOT_RUN_BY_GATE`。Production controller/CBF/reward/tau/PPO 未改；训练未运行，PPO optimizer steps=`0`。
- v1 yaw45 的分析代码把内部 **WXYZ** 四元数按 **XYZW** 解码，故 v1 报告中“yaw45≈0 rad”属于诊断误读，不是可靠的 runtime 跟踪结论。Gate-1B 保留原 v1 corpus、fit 和报告，改用明确的 WXYZ 解码、heading 向量交叉核对和真实 `SET_YAW_AND_WAIT`；此条纠正 §10.26 的 yaw45 解释，不修改 v1 制品，也不把 v1 重新解码当 Gate-1B 验收证据。
- 新协议在 Isaac 采集前冻结，SHA256=`cfffc3315249afb1c0b9857b2570d9c0b871b5f3f69a7f49ebca645a64f41f00`。从 yaw0 reset，先零速 hover 稳定，再通过现有 `VelController → LeePositionController` 命令 0°、+45°、−45°、90°；yaw 误差≤2°且航向角速度≤2°/s 连续 100 个 100Hz 步才允许 +x/+y 各 0.3m/s 的已知第 200 步阶跃。8 个角度/轴 parent probes、每组 3 repeats，共 24 次；所有 Gate-1B 探针从后续模型选择中排除。
- 真实 yaw 判稳：0°=`5/6`，+45°=`1/6`，−45°=`3/6`，90°=`0/6`。+45° 失败重复中控制器确实消费 45°，而机体在约 48.89° 或 39.30° 附近以近零角速度停住；不能归因于固定等待时间过短。90° 请求被现有 `max_yaw_rate=1.5` 的 heading 限幅裁到 1.5rad≈85.94°，六次均超时；未改限幅或 controller gains。首次 yaw 失败后只继续剩余 yaw-only 探针，没有继续速度激励或系统辨识。
- 五次成功进入速度激励的探针全在 yaw 连续达标之后采样，均为 yaw0（x=`3/3`、y=`2/3`）。非零 yaw 下没有合格速度激励，故 frame contract 只能记 **`INCONCLUSIVE`**，不能凭代码路径宣布 WORLD_FRAME_CONFIRMED。已观测五次命令赋值→控制器消费的软件 offset=`0` steps，速度响应阈值检测延迟=`10–11` steps；这些是阈值检测时间，不是精确物理纯延迟。日志对齐覆盖仅全计划 `5/24`、yaw0 x/y `5/6`，最终分类 **`PARTIAL_ALIGNMENT_EVIDENCE / FAIL_CLOSED`**，不得作为完整对齐验收。
- Stage-1 使用 `gate_probe_seed + repeat`，导致不同 parent probe 的随机种子碰撞；24 次是重复运行，不是 24 个独立试验，不能据此报 trial CI。该限制不改变 yaw 超时与 90° 命令限幅事实。v1 X/Y delay=`10` 撞旧 0..10 上界、M3 优势与模型结构问题均保持未解决；无新 tau/K/delay 或 Gate-2 surrogate 推荐。
- 证据见 `OmniDrones/docs/gate1B_velocity_loop_resolution_20260923_v1/`：冻结 protocol、24 份逐步原始 gzip 遥测、trial index、yaw/frame/alignment/runtime 判定、被门控的后续制品和 `report.md`。Production 12 个、Gate-1 v1 13 个受保护文件哈希运行前后匹配；CPU test=`10/10 PASS`。独立 Reviewer 对 Gate 1 给出 **BLOCKED**，确认原始文件/哈希完整且没有 Stage-2/test-set 泄漏；Reviewer 指出的对齐覆盖误报已在派生制品中改为 FAIL_CLOSED。未 commit/push/reset/clean；下一个可考虑模块仅为针对 yaw 目标限幅与稳态偏差的 Gate-1 运行时诊断，不自动开始。

### 10.28 Gate-1C — velocity-loop identification completion（2026-09-23）

- **最终状态：`GATE_1_BLOCKED`；更正后 primary=`INCONCLUSIVE`；Gate 2=`NOT_READY`，输入 contract=`SUPPRESSED`。** 独立 reviewer 判定 BLOCKED。此节覆盖 §10.27 当时的下一步建议：用户已将 yaw 精确目标跟踪和既有 ±1.5 rad 限幅裁定为非阻塞，仅用稳定的实际 yaw 验证平移 world-frame 合同；没有修改 yaw controller/clamp/gains，也未扩展调查 yaw 根因。
- Gate-1C protocol 在真实 Isaac 运行前冻结，SHA256=`ea03f40af4225c59519fd67c57e48ce4335795e5ea9002a8e5f18e046f9b70b2`。yaw0、+45°、−45° 的稳定实际航向上，12/12 个 +X/+Y 探针确认 `WORLD_FRAME_RUNTIME_CONFIRMED`；6/6 个 X/Y/Z known-step 探针确认 `LOGGING_ALIGNMENT_CONFIRMED`。命令赋值到 controller 消费 offset=`0` step；X/Y 阈值响应检测=`10–11` step、Z=`2` step，这不是纯 dead time。实际 yaw 与请求值有稳态偏差，作为已知限制记录。
- 新 canonical corpus：14 个 gate/alignment probes、60/60 个 ID parent trials，全新有效 seeds=`74/74 unique`，无 collision，train/validation/test 按 parent=`20/20/20`；ID raw=`230,136` rows（含稳定段），激励 waveform=`218,400` rows，总 gate+ID=`242,625` raw rows。旧 Gate-1/1B 探针不参与拟合或 bootstrap。60 个 ID 中含 X/Y/Z 正负 step/return/PRBS、0.3/0.8/1.3m/s 幅值及 6 个同步独立 XY PRBS trials。全部 waveform 行无 command clamp 或 actuator-near-limit；观测 command norm=`0–1.30m/s`、velocity norm=`0–1.249m/s`，仅代表已采样非饱和支持。
- 在冻结 0..50 step delay 搜索和同一 train/validation/test 支持下，M2 X/Y/Z delay=`17/18/3`，tau=`0.637/0.577/0.478s`，K=`1.007/0.994/0.929`；M3 delay=`7/7/2`，各自最优点均在搜索内部且为 sharp minimum。M3 X/Y 离散极点分别≈`0.97712±0.02765i`、`0.97759±0.02780i`，连续衰减时间≈`0.440/0.449s`，显式保留两项输入及 delay。Z M3 极点≈`0.97872/0.27537`，衰减≈`0.465/0.00775s`；这些是诊断 surrogate 而非已授权 production 参数。
- 测试集 100ms 开环 RMSE（M0/M2/M3，m/s）：X=`0.11976/0.04993/0.00891`，Y=`0.11649/0.04442/0.00912`，Z=`0.04826/0.02653/0.02448`；500ms 为 X=`0.23817/0.15387/0.05189`，Y=`0.23033/0.12517/0.05544`，Z=`0.08601/0.06380/0.05777`。X/Y 的 M3 短时 score 在验证集提升≈`86.5%/85.9%`、测试集≈`86.5%/84.9%`，符合冻结 material 判据。Z 验证短/长改善分别只有`0.00144/0.00422m/s`，均未达冻结`0.005m/s`绝对阈值；bootstrap 也未证明 M2 等效，因此 Z model class=`INCONCLUSIVE`，独立阻塞 Gate 1。500 次 whole-parent bootstrap、参数/极点/零点区间、step response 和完整 10–500ms horizon 见制品。
- **原始一次性分析有可审计的后验纠错。** 原 `model_selection.json` 将 overall primary 判为 `OPERATING_POINT_DEPENDENT_MODEL_REQUIRED`，但其运行点结论依据 X/Y 的 M2 tau/K，而冻结验证选择 X/Y M3；原 `coupling_analysis.json` 用 ARX1 自动态判 `XY_COUPLING_MATERIAL`，还在未预冻结耦合判决前混入 held-out XY trials。因此原文 blanket `test_used_for_selection=false` 对耦合不成立。保留原 JSON/哈希，新增 train+validation-only、未重读 test raw 的 additive correction：M3 运行点 X 不确定、Y 有低高速度衰减差异候选，但未获新的独立 held-out 确认，overall=`INCONCLUSIVE`；M3 自动态下 XY cross RMS X←Y=`0.0145` [95% CI `0.0038,0.0282`]、Y←X=`0.0182` [`0.0086,0.0255`] m/s，未能证明 material 或 negligible，corrected=`XY_COUPLING_INCONCLUSIVE`。轴模型的预冻结选择和一次 test 确认仍可审计；原耦合总体结论不能作为干净 held-out 验收。
- 独立 reviewer 确认 corpus、frame/alignment、保护哈希有效，但因 Z 未定及 operating/coupling 证据不足而给出 **BLOCKED**。`gate2_input_contract.json` 保持 suppressed；其原始 blocker 文案是历史记录，以 `post_analysis_correction_addendum.json` 和最终 `report.md` 的纠错状态为准。无生产 controller/CBF/reward/tau/PPO/config 修改、无 training、PPO optimizer step=`0`，无 commit/push/reset/clean。主脚本 CPU tests=`15/15`、纠错 tests=`2/2`，py_compile、nested/outer `git diff --check`、raw/hash/timing/nonfinite 与 protected source hash 检查通过。完整制品在 `OmniDrones/docs/gate1C_velocity_loop_identification_20260923_v1/`；后续若继续，须另行冻结新独立 held-out 验证 Z、M3 运行点及 XY 耦合，不能将本次 blocked 改写为 Gate-1 PASS 或自动开启 Gate 2。
