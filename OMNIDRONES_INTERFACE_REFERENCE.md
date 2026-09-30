# OmniDrones Interface Reference

> **用途**：核心类/函数的接口卡片（签名、caller/callee、input/output、shape、单位、副作用、生命周期、修改风险），
> 供 AI Agent 在**改动任何接口前**快速评估影响面。
> **配套文档**：`OMNIDRONES_PROJECT_SUMMARY.md`（架构与开发指南）。
> **基准**：`drones/OmniDrones/` @ `feat/crazyflie-pidrate` (`1a62313`)；torchrl 0.11.1 / tensordict 0.11.0 / Isaac Sim 5.1。
> **API 稳定性声明**：**本项目未声明任何官方 API 稳定性**。下文的 stable/internal 分类是**根据调用模式推断**的
> （凡被 registry / 多任务 / 配置直接引用的视为 stable-ish）。

**符号**：`N`=num_envs，`n`=每环境无人机数，`R`=num_rotors(4)，`D`=obs 维，`K`=obs 障碍槽位，`M`=场景障碍槽位，
`T`=每迭代步数（=train_every）。

---

## 1. Environment Interfaces

### `IsaacEnv.__init__(cfg, headless)`

定义：`omni_drones/envs/isaac_env.py`

```python
def __init__(self, cfg, headless)   # cfg: Hydra DictConfig（整棵树）
```

**Responsibility**：建立 Isaac Sim 物理上下文、克隆场景、注册 spec、初始化渲染/统计——**一切环境的根基**。

**Called by**：`scripts/train.py`、`play.py`、`eval_ckpt.py`、`demo_fly.py` 等（`env_class(cfg, headless=cfg.headless)`）；
所有 Task 子类的 `super().__init__(cfg, headless)`。

**Calls**：`_configure_simulation_flags` → `SimulationContext(...)` → `_create_viewport_render_product` →
`self._design_scene()`（虚） → `GridCloner.clone` → `RobotBase._envs_positions=...` → `cloner.filter_collisions` →
`sim.reset()` → `self._set_specs()`（虚） → `self.fake_tensordict()`（打印 shapes）。

**Input**

| Parameter | Type | Shape | Unit | Description |
| --- | --- | --- | --- | --- |
| `cfg` | DictConfig | — | — | 需含 `sim/env/task/viewer/headless` 等（本函数读 `cfg.sim.device`、`cfg.env.num_envs`、`cfg.env.max_episode_length`、`cfg.sim.substeps`、`cfg.env.env_spacing`、`cfg.viewer.eye/lookat`） |
| `headless` | bool | — | — | 仅决定是否 enable_render |

**Output**：无返回值；构造出 `self.sim / envs_positions / observation_spec / action_spec / reward_spec / done_spec / progress_buf`。

**Side Effects**：启动/重建 USD stage；克隆 N 个环境；创建相机与 render product；把 `RobotBase._envs_positions` 设为 `(N,1,3)`；
**`sim.reset()` 之后才允许物理视图 initialize**。

**Lifecycle**：进程生命周期内一次（每进程一个 env）。

**Modification Risk**：**High**——改动签名/行为会同时影响全部 Task、全部入口与所有 spec 消费者。
新增字段请用默认值/可选参数。

### `IsaacEnv._step(tensordict)` / `IsaacEnv._reset(tensordict)`

```python
def _step(self, tensordict: TensorDictBase) -> TensorDictBase
def _reset(self, tensordict: TensorDictBase, **kwargs) -> TensorDictBase
```

**Responsibility**：TorchRL 的 step/reset 钩子；`_step` 跑 substeps×（pre_sim_step→sim.step）再算 obs+reward/done；
`_reset` 按 `tensordict["_reset"]` 掩码做部分重置。

**Called by**：torchrl `EnvBase.step / EnvBase.reset`（即由 `SyncDataCollector`、`env.rollout()` 触发）。

**Calls**：`Task._pre_sim_step` / `Task._compute_state_and_obs` / `Task._compute_reward_and_done` / `Task._reset_idx` / `sim.step()`。

**Input**：入参 tensordict 仅用于取 `("agents","action")`（step）或 `"_reset"` 掩码（reset）。

**Output**：`TensorDict(batch_size=[N])`：
- step：`agents.reward (N,n,1)`、`done/terminated/truncated (N,1)`、`agents.observation`、`info`、`stats`；
- reset：`agents.observation` + `truncated`。

**Side Effects**：推进物理；`progress_buf += 1`；env 内缓存的自动刷新；可能触发 `_respawn`。

**Lifecycle**：每个 env step / reset 一次（batch 内所有 env 同步推进）。

**Modification Risk**：**High**——任何改动都会影响所有任务的时序语义（含 done→auto-reset→PPO 的 GAE）。

### `IsaacEnv` 辅助接口

| 接口 | 签名要点 | 用途 | Risk |
| --- | --- | --- | --- |
| `enable_render` | `(enable: bool|Callable)` | 设 `_should_render(substep)` | Low |
| `render` | `(mode="rgb_array") -> np.uint8 (H,W,3)` | 出视频帧（5.x 兼容归一化） | Medium（渲染管线） |
| `get_env_poses` / `get_world_poses` | `(pos, rot) -> (pos±envs_positions, rot)` | 世界系↔环境系换算（支持 dim=3 的 `(N,n,3)`） | Medium |
| `agent_spec` | property → `{name: AgentSpec}` | 算法侧取 per-agent spec（`_AgentSpecView` 在 setitem 时注入 `_env`） | Medium（多机算法依赖） |
| `_set_seed` | `(seed)` → `rep.set_global_seed` + `torch.manual_seed` | 确定性 | Low |
| `close` | 空实现 | 无 | Low（勿依赖） |

### `IsaacEnv.__init_subclass__`（注册钩子）

```python
@classmethod
def __init_subclass__(cls, **kwargs):   # 自动执行
    IsaacEnv.REGISTRY[cls.__name__] = cls
    IsaacEnv.REGISTRY[cls.__name__.lower()] = cls
```

**Responsibility**：把每个 Task 子类登记进 `REGISTRY`（键=类名/小写类名）。
**Called by**：Python 导入机制（`class X(IsaacEnv)` 定义时）。
**Side Effects**：import 即注册（**依赖 import 顺序/是否被导入**）。
**Modification Risk**：High（`scripts/train.py` 直接用它查类；重名会 raise ValueError）。

---

## 2. Task Interfaces（每个 Task 的 6 个钩子）

### `Task._design_scene(self) -> Optional[List[str]]`

**Responsibility**：在模板环境 `/World/envs/env_0` 下创建无人机/地面/目标/障碍等 prim。
**Called by**：`IsaacEnv.__init__`（cloner 之前）。
**Calls**：`MultirotorBase.make/spawn`、`kit_utils.create_ground_plane/set_nested_*`、`prim_utils.create_prim`（NavVel 还会 `ObstacleManager` 相关 prim 创建）。
**Input**：配置（`cfg.task.*`）。
**Output**：跨环境共享的 prim 路径列表（如 `["/World/defaultGroundPlane"]`）——用于 `filter_collisions` 的 global_paths。
**Side Effects**：建 USD prim；建 `self.drone/self.controller`（注册进 RobotBase._robots）。
**Lifecycle**：每 env 进程一次。
**Modification Risk**：High（prim 命名决定 `rotors_view` 等视图能否匹配；`env_0` 之外建的 prim 不会被克隆）。

### `Task._set_specs(self) -> None`

**Responsibility**：定义 `observation_spec / action_spec / reward_spec`、`agent_spec[...]`、`stats`、`info`。
**Called by**：`IsaacEnv.__init__`（`sim.reset()` 之后）。
**Input**：`self.drone.state_spec/action_spec/intrinsics_spec`（**必须先有 drone**）。
**Output**：无（写 self 属性）；正常会构造 `fake_tensordict()`（由 IsaacEnv 打印形状）。
**Side Effects**：注册 spec（含 `stats`/`info` 子树）。
**Lifecycle**：每 env 进程一次。
**Modification Risk**：**High**——spec 是所有数据流的"类型契约"（actor 输入维度、GAE 形状、EpisodeStats 键）。
新增 key 可以；改 shape/键名要全链路排查（见 Summary §30/§37）。

### `Task._reset_idx(self, env_ids: torch.Tensor)`

**Responsibility**：按 env_ids 重置 drone 状态、目标、统计（必须支持**部分重置**）。
**Called by**：`IsaacEnv._reset`。
**Calls**：`drone._reset_idx(env_ids, self.training)`、`drone.set_world_poses/set_velocities`、（NavVel）`self.obstacles.commit_layout`、`_sync_low_level_controller`。
**Input**：`env_ids (k,)` int64。
**Output**：无。
**Side Effects**：改写物理状态、本任务缓存、stats 清零；**影响下一帧 obs/reward**。
**Lifecycle**：每 episode 结束（含 auto-reset）时对该批次 env 调用。
**Modification Risk**：**High**——只操作索引子集；用 mask 广播错误会静默影响其它 env（历史上出现过 (N,N) 广播坑，见 nav_vel 注释）。

### `Task._pre_sim_step(self, tensordict)`

**Responsibility**：把 action 变成物理量（**唯一把动作交给无人机的地方**）。
**Called by**：`IsaacEnv._step`（每个 substep 一次；substeps>1 时同一 action 被重复应用）。
**Calls**：`self.drone.apply_action(actions)`；（NavVel）把 `info.prev_action/policy_action/…` 从 tensordict 同步回 self。
**Input**：`tensordict[("agents","action")] (N,n,R)`（已经过 transforms 翻译）。
**Output**：无（副作用：`self.effort` 等）。
**Side Effects**：写物理（力/关节）；写 self 缓存。
**Lifecycle**：每 env step（×substeps）。
**Modification Risk**：High。

### `Task._compute_state_and_obs(self) -> TensorDictBase`

**Responsibility**：从仿真读状态 → 组观测 + 刷新 `info`/`stats`。
**Called by**：`IsaacEnv._step`（每步）和 `IsaacEnv._reset`（reset 后立即）。
**Calls**：`drone.get_state()`、（NavVel）`obstacles.build_obs/min_clearance/update_min_clearance`。
**Output**：`TensorDict({"agents":{"observation","intrinsics"},"info","stats"})`。
**Side Effects**：写 `self.info[...]`、`self.drone_state`、（NavVel）障碍窗口缓存。
**Lifecycle**：每步 + 每 reset。
**Modification Risk**：**High**（观测变更的核心点，见 Summary §37）。

### `Task._compute_reward_and_done(self) -> TensorDictBase`

**Responsibility**：算 reward/terminated/truncated 并更新 stats。
**Called by**：`IsaacEnv._step`。
**Calls**：（NavVel）`obstacles.clearances/cbf_geom`、`utils/cbf.cbf_violation/filter_velocity`、`_respawn`。
**Output**：`TensorDict({"agents":{"reward":(N,n,1)},"done/terminated/truncated":(N,1)})`。
**Side Effects**：写 stats（EMA/in-place）、可能触发重生/终止、可能改 reward 内部状态（`prev_goal_dist`、`prev_in_collision`）。
**Lifecycle**：每步。
**Modification Risk**：**High**（奖励/终止语义是训练目标本身）。

**典型任务实现对照**：Hover（`envs/single/hover.py`）、NavVel（`envs/single/nav_vel.py`）、Formation（`envs/formation.py`）。

---

## 3. Drone Interfaces

### `RobotBase.spawn(translations, orientations=None, prim_paths=None)`

定义：`omni_drones/robots/robot.py`
**Responsibility**：在模板 env 下创建 drone prim（USD）并设置刚体/articulation 属性。
**Called by**：Task `_design_scene`。
**Calls**：`prim_utils.create_prim(usd_path=…)`、`kit_utils.set_nested_rigid_body_properties / set_articulation_properties`。
**Input**：`translations (k,3)` m；`orientations` 四元数；`prim_paths` 默认 `{TEMPLATE_PRIM_PATH}/{name}_{i}`。
**Output**：prim 列表。
**Side Effects**：stage 变更；`self.n += k`。
**Risk**：High（命名规则影响后续 view 的 prim_paths_expr）。

### `RobotBase.initialize(prim_paths_expr=None)`

**Responsibility**：创建 ArticulationView / RigidPrimView 并完成物理视图初始化。
**Called by**：Task `__init__`（在 `super().__init__` 之后）；（MultirotorBase 里由 `MultirotorBase.initialize` 间接调用）。
**Input**：`prim_paths_expr` 默认 `/World/envs/.*/{name}_.*`。
**Output**：`self._view`、`self.shape`、`self.prim_paths`。
**Side Effects**：`post_reset()`；物理视图建立。
**Lifecycle**：一次（**必须在 `sim.reset()` 之后**，否则 raise）。
**Risk**：High。

---

## 4. Crazyflie Interfaces

### `class Crazyflie(MultirotorBase)`

定义：`omni_drones/robots/drone/crazyflie.py`

```python
class Crazyflie(MultirotorBase):
    usd_path:   str = ASSET_PATH + "/usd/cf2x_pybullet.usd"
    param_path: str = ASSET_PATH + "/usd/crazyflie.yaml"
```

**Responsibility**：仅声明资产与参数路径；**没有额外行为**。
**Called by**：`MultirotorBase.REGISTRY["Crazyflie"]`（`cfg.task.drone_model.name: Crazyflie`）。
**Calls**：无（继承全部逻辑）。
**Input/Output**：同 `MultirotorBase.__init__`。
**Side Effects**：类定义时自动注册 REGISTRY。
**Modification Risk**：Medium——加 `__init__` 覆写或改路径会影响使用 Crazyflie 的所有任务与历史口径
（mass/KF 改动 ⇒ 旧 ckpt/曲线不可比）。

**参数文件接口**（`robots/assets/usd/crazyflie.yaml`）——改这些键的影响：

| 键 | 消费点 | 影响 |
| --- | --- | --- |
| `mass`, `inertia.*` | `_reset_idx`/`update_sim` 同步物理；`LeePositionController` 读 `params["mass"]`；`GRAVITY=abs(g)*mass` | 悬停油门、控制器推力补偿、动力学响应 |
| `rotor_configuration.force_constants/max_rotation_velocities` | `KF`（推力上限）、`max_thrusts`（控制器归一化）、mixer | 控制权限与 T2W |
| `rotor_configuration.moment_constants` | `KM` + mixer | 偏航力矩权限 |
| `rotor_configuration.directions` | `_apply_rotors`（反扭矩符号）、mixer | 偏航控制方向（改错=反了） |
| `rotor_configuration.time_constant` | `_apply_rotors` 一阶滞后 | 响应带宽 |
| `rotor_configuration.*` 之外的 `LPF_coef/target_clip/min/max_thrust_ratio/fixed_yaw` | `PIDRateController`（CTBR 路径） | 仅 PIDrate 动作层 |
| `drag_coef` | `apply_action` 阻力项 | 高速段 |

---

## 5. Multirotor Interfaces

### `MultirotorBase.make(drone_model, controller=None, device="cpu")`

```python
@staticmethod
def make(drone_model: str, controller: str = None, device: str = "cpu"):
    drone_cls = MultirotorBase.REGISTRY[drone_model]
    drone = drone_cls()
    if controller is not None:
        controller_cls = ControllerBase.REGISTRY[controller]
        controller = controller_cls(drone.gravity[1], drone.params).to(device)
    return drone, controller
```

**Responsibility**：工厂：按名字建 drone（+可选控制器）。
**Called by**：所有 Task 的 `_design_scene`（如 `hover.py`、`nav_vel.py`、`formation.py`）；`examples/*`。
**Calls**：`REGISTRY[...]`、`ControllerBase.REGISTRY[...]`。
**Input**：drone 名（大小写皆可，REGISTRY 两份键）、controller 名（可 None）。
**Output**：`(drone, controller|None)`——**drone 尚未 spawn/initialize**。
**Side Effects**：`RobotBase.__init__` 会把 drone 写进 `RobotBase._robots`（**同名第二次会 RuntimeError**）。
**Modification Risk**：**High**。

### `MultirotorBase.initialize(prim_paths_expr=None, track_contact_forces=False)`

**Responsibility**：在 `RobotBase.initialize` 之上建立 `base_link`、`rotors_view`、`RotorGroup`、参数张量与状态缓存。
**Called by**：Task `__init__`（`self.drone.initialize()`）。
**Input**：prim 路径表达式（默认按 name 匹配）；`track_contact_forces`。
**Output**：无（构造大量属性：`throttle/KF/KM/thrusts/torques/forces/pos/rot/vel/...`，见 Summary §12）。
**Side Effects**：打印 dof 名与 `rotor_joint_indices`；`update_sim` 时写物理质量/惯量。
**Lifecycle**：一次。
**Modification Risk**：High。

### `MultirotorBase.apply_action(actions) -> torch.Tensor`

```python
def apply_action(self, actions: torch.Tensor) -> torch.Tensor
```

**Responsibility**：**动作→物理力**的终点：更新一阶电机状态、算推力/力矩/阻力/downwash，并写进 PhysX。
**Called by**：Task `_pre_sim_step`（如 `hover.py`、`nav_vel.py`、`formation.py`、所有单机/多机任务）。
**Calls**：`_apply_rotors`、`rotors_view.get_world_poses`、`quat_axis/quat_rotate`、`downwash`、
`_view.set_joint_velocities`、`_view._physics_view.apply_forces_and_torques_at_position`（或 rotors_view 的 fallback）。
**Input**

| Parameter | Type | Shape | Unit | Description |
| --- | --- | --- | --- | --- |
| `actions` | float32 | `(N, n, R)` 或可 expand 的形状 | 归一化 ∈[-1,1] | rotor 命令（推力平方根的仿射） |

**Output**：`throttle.sum(-1) → (N,n)`（"effort" 标量，Hover/NavVel 用它做 reward 项）。
**Side Effects**：`self.throttle/thrusts/torques/forces/throttle_difference` 全部被就地更新；物理状态下一帧变化。
**Lifecycle**：每 env step（×substeps）一次。
**Modification Risk**：**High**——改这里等于改"飞机怎么飞"；所有任务/控制器/奖励（effort/速度统计）与旧 ckpt 语义都受影响。

### `MultirotorBase._apply_rotors(cmds) -> (thrusts, moments)`

**Responsibility**：纯张量的一阶电机模型 + 推力/反扭矩换算（vmap 替代品，见 Summary §15 的公式）。
**Called by**：`apply_action`（唯一 caller）。
**Input**：`cmds (…,R)` ∈[-1,1]。**Output**：`thrusts (…,R)` N、`moments (…,R)` N·m。
**Side Effects**：`self.throttle.add_(...)`（**有状态**：依赖上一步 throttle）。
**Lifecycle**：每步。
**Modification Risk**：High（且必须同步 `RotorGroup.forward`）。

### `MultirotorBase.get_state(check_nan=False, env_frame=True) -> Tensor`

**Responsibility**：刷新并返回 drone 状态向量。
**Called by**：所有 Task 的 `_compute_state_and_obs`；NavVel 的 reward 里也用 `self.drone_state`。
**Output**：`(N,n,19+R)`，布局 `[pos(3) | quat(4) | vel_w(6) | heading(3) | up(3) | throttle*2-1(R)]`；
`env_frame=True` 时 pos 减去 env 原点（**导航类任务必须用默认的 True**，保证平移不变）。
**Side Effects**：更新 `self.pos/rot/vel_w/vel_b/heading/up`。
**Lifecycle**：每步。
**Modification Risk**：**High**——索引位置（`state[...,13:16]`=heading、`[...,7:10]`=线速度、`[...,18]`=up_z）
被多个任务硬编码，改布局会静默错位。

### `MultirotorBase._reset_idx(env_ids, train=True)` / `setup_randomization(cfg)`

| 接口 | 作用 | 备注（Risk） |
| --- | --- | --- |
| `_reset_idx` | 清零力/速度、采样 DR、（train 用 train 分布）重置 throttle=悬停油门 | High：`env_ids` 语义、throttle 初始化影响起飞学习 |
| `setup_randomization` | 依据 `cfg["train"/"eval"]` 注册 DR 分布（mass/inertia/t2w/f2m/drag/com/tau_up/tau_down） | Medium：键名必须与 `_randomize` 分支一致，否则 raise |
| `_randomize` | 采样并写回物理（`set_masses/set_inertias/set_coms`）+ 更新内部常数 + 记录 `intrinsics` | High：与 `update_sim`、`controller_sync_dr`（Lee 侧 `sync_randomized`）配对联调 |

---

## 6. Actuator Interfaces

### `RotorGroup.forward(cmds) -> (thrusts, moments)`

定义：`omni_drones/actuators/rotor_group.py`

```python
class RotorGroup(nn.Module):
    def __init__(self, rotor_config, dt: float)
    def forward(self, cmds: torch.Tensor)   # 见 Summary §15 公式
```

**Responsibility**：原版旋翼模型（曾被 `vmap(vmap(rotors))` 调用；现在 `MultirotorBase` **不再用它做前向**，
但参数仍由 `make_functional(self.rotors)` 提取：`KF/KM/throttle/directions/tau_up/tau_down`）。
**Called by**：`MultirotorBase.initialize`（构造 + 参数提取）；历史/示例代码可能直接调用。
**Input**：`cmds (…,R) ∈[-1,1]`；**Output**：thrusts N、moments N·m。
**Side Effects**：内部 `self.throttle` 就地更新（若被直接调用）。
**Lifecycle**：每步（若被调用）。
**Modification Risk**：Medium——**注意**：它与 `_apply_rotors` 是同一公式的两份实现，改动必须成对。

### `omni_drones.utils.tensordict_compat.make_functional(module) -> TensorDict`

**Responsibility**：把 `nn.Module` 的 `named_parameters` 拷成 TensorDict，并把原参数**转为 buffer**。
**Called by**：`MultirotorBase.initialize`（`rotor_params = make_functional(self.rotors)`）。
**Output**：`TensorDict({name: tensor})`，可 `.expand(shape).clone()`。
**Side Effects**：**改动传入 module 的参数类型**（`Parameter`→`buffer`）并 `requires_grad_(False)`。
**Modification Risk**：Medium（兼容层，见 Summary §27；tensordict≥0.11 下必需）。

---

## 7. Controller Interfaces

### `ControllerBase`（抽象）

定义：`omni_drones/controllers/controller.py`
**接口**：`compute(*args, **kwargs) -> Tensor`、`process_rl_actions(actions) -> Tensor`；`REGISTRY`（类名/小写）。
**Modification Risk**：Medium——新增控制器请继承它（自动注册，`MultirotorBase.make` 才能按名字找到）。

### `LeePositionController.compute(root_state, target_pos=None, target_vel=None, target_acc=None, target_yaw=None, body_rate=False)`

定义：`omni_drones/controllers/lee_position_controller.py`

**Responsibility**：几何控制（Lee 2010）：位置/速度误差→期望加速度→期望姿态→角加速度→mixer→rotor 命令。
**Called by**：`utils/torchrl/transforms.py::VelController._inv_call`（NavVel 动作链）；其它任务可能经 `RateController/AttitudeController` 间接调用。
**Calls**：`_compute`（内部逐样本 `reshape(-1,13)`）；`mixer`、`pos_gain/vel_gain/attitute_gain/ang_rate_gain`（来自 `controllers/cfg/lee_controller_<name>.yaml`）。
**Input**（per element）：`root_state(…,13)`（pos,quat,linvel,angvel；world 系角速度）；`target_vel(…,3)` m/s；`target_yaw(…,1)` rad；`target_acc/pos` 可空。
**Output**：`cmd (…,R)` ∈[-1,1]。
**Side Effects**：无（除可选 `_mass_dyn/_max_thrusts_dyn` 覆盖）。
**Lifecycle**：每步（动作链内）。
**Modification Risk**：**High**（改变飞行行为、CBF 介入率、reward 标定）。

### `LeePositionController.sync_randomized(mass=None, kf=None)`

**Responsibility**：DR 后让控制器用**真实**质量/推力上限（模拟固件自校准）。
**Called by**：`NavVel._sync_low_level_controller()`（reset 后，`controller_sync_dr: true` 时）。
**Input**：`mass (…,1)` kg；`kf (…,R)` N。**Output**：self。
**Modification Risk**：Medium。

### `PIDRateController.forward(root_state, target_rate, target_thrust, reset_pid) -> (cmd, ctbr)`

定义：`lee_position_controller.py`（SimpleFlight 迁移）
**Responsibility**：CTBR（collective thrust + body rate）→ PID → 4 电机命令。
**Called by**：`utils/torchrl/transforms.py::PIDRateController._inv_call`（`action_transform: PIDrate`）。
**Input**：`target_rate (…,3)` **deg/s**；`target_thrust (…,1)` **0..2^16**；`reset_pid (…,)` bool（来自 `done`）。
**Output**：`cmd (…,4) ∈[-1,1]`；`ctbr (…,4)`（诊断/日志）。
**Side Effects**：内部积分状态 `integ/last_body_rate` 就地更新（**依赖 reset_pid 正确传入**）。
**Modification Risk**：High（控制回路）。

---

## 8. Sensor Interfaces

本 fork 的 NavVel 主线**不使用传感器**；以下接口供扩展参考。

| 接口 | 位置 | 输入 → 输出 | 备注 |
| --- | --- | --- | --- |
| `omni_drones.sensors.camera.*` | `omni_drones/sensors/camera.py` | 相机 prim → 图像张量 | 仅有封装类（见文件内定义）；NavVel 不用 |
| `RayCaster`（IsaacLab） | `omni_drones/envs/single/forest.py`（函数内 import） | 射线 → `ray_hits_w` | 每步 `self.lidar.update(self.dt)`；scan=`lidar_range-‖hit-pos‖`，obs `("lidar", (1,36,4))` |
| `ContactSensor`（IsaacLab） | `omni_drones/envs/single/pinball.py`（**模块级** import） | prim → 接触读数 | **缺 IsaacLab 会导致 import 失败**（`envs/__init__.py` 有 try/except 提示） |

**扩展规则**：新增传感器时（a）把数据放进 obs（`_set_specs` 与 `_compute_state_and_obs` 双改）；
（b）若依赖 IsaacLab，参照 forest 的"函数内 import + 可选依赖"模式，不要加模块级依赖。

---

## 9. TorchRL Interfaces

### `omni_drones.utils.torchrl.SyncDataCollector`（`collector.py`）

```python
class SyncDataCollector(torchrl.collectors.SyncDataCollector):
    def rollout(self) -> TensorDictBase        # 记录 self._fps
    def iterator(self) -> Iterator[TensorDictBase]   # 每轮 yield 一批 frames
```

**Responsibility**：驱动 env.step + policy 前向，产出 `(T,N,…)` 的 rollout。
**Called by**：`scripts/train.py`（`for i, data in enumerate(tqdm(collector))`）。
**关键语义**：`return_same_td=True` → **不 clone**，同一 TensorDict 每轮被覆写（不要跨轮保存引用）；
`split_trajs=False`（默认训练）；`self._frames` 为累计帧数（日志/eval 触发用）。
**Modification Risk**：High（训练数据流的唯一来源）。

### `Transform` 族群（`utils/torchrl/transforms.py` + `utils/cbf.py`）

| 类 | in_keys_inv | 作用 | 输出写回 | Risk |
| --- | --- | --- | --- | --- |
| `VelController` | `("info","drone_state")` | 速度指令 + 限幅 → Lee → rotor cmds | `("agents","action")` | High |
| `PIDRateController` | 同上 | `tanh` → LPF → CTBR → PID → rotor cmds；写 `("info","policy_action")`、`("stats","action_error_order1")` | `("agents","action")` | High |
| `AttitudeController` | 同上 | thrust+roll/pitch/yaw_rate → rotor cmds | `("agents","action")` | Medium |
| `RateController` | 同上 | target_rate/target_thrust → rotor cmds | `("agents","action")` | Medium |
| `FromDiscreteAction` / `FromMultiDiscreteAction` | `action_key` | 离散索引 → 连续动作（改 `full_action_spec` 为 Discrete/MultiDiscrete） | `("agents","action")` | Medium（仅离散算法用） |
| `CBFVelocityFilter`（`utils/cbf.py`） | `("info","drone_state")`, `("info","obstacle_cbf")` | 把平动速度投影到 CBF 半平面；可选 shadow/p 调度/emit_info | `("agents","action")`、`("info","policy_action")`、`("info","p_filter/cbf_corr/…")` | High（若不挂接顺序错，会静默不生效） |
| `CmdGaussNoise` | `("agents","action")` | 速度分量加高斯噪声（DR） | 同 key | Medium |
| `History` | 任意 in_keys | 维护滑窗历史（默认 32 步） | `…_h` key | Low |
| `ravel_composite(spec, key)` | — | 把 CompositeSpec 摊平成向量（配 MLP encoder） | — | Medium（改变 encoder 类型/维度顺序） |

**顺序契约（关键）**：`Compose._inv_call` 以 `reversed(self.transforms)` 执行（torchrl 0.11.1 源码实证）。
因此**列表里越靠后的变换，越先接触策略动作**。NavVel 期望的执行序：
`policy → CBF → DR噪声 → VelController`，对应列表追加顺序 `VelController, CmdGaussNoise, CBFVelocityFilter`。

### `AgentSpec`（`utils/torchrl/env.py`）

```python
@dataclass
class AgentSpec:
    name: str; n: int
    observation_key/action_key/state_key/reward_key/done_key: Optional[str|tuple]
    _env: Optional[EnvBase]
    # 属性：observation_spec / action_spec / state_spec / reward_spec / done_spec
```

**Responsibility**：算法侧取 per-agent spec 的适配层（会去 `_env.observation_spec[...]`、`input_spec["full_action_spec"]` 等取）。
**Called by**：`_set_specs` 里的 `self.agent_spec["drone"] = AgentSpec(...)`；多机算法（MAPPO/HAPPO）读取。
**Side Effects**：`agent_spec` property 返回 `_AgentSpecView`，`__setitem__` 会注入 `_env`（**不能整体替换**）。
**Risk**：Medium-High（多机算法依赖；`full_action_spec` 与 `action_spec` 的差异由 transforms 引入）。

### `EpisodeStats` / `RenderCallback`

- `EpisodeStats(in_keys).add(tensordict)`：从 `tensordict["next"]` 里挑 `done` 为真的样本，收集 `stats.*`；`pop()` 返回均值用 batch；
  **长度=已收集 episode 数**（train.py 用它判断 `>= num_envs`）。
- `RenderCallback(interval)`：`__call__(env)` 每 interval 帧抓 `env.render("rgb_array")`；`get_video_array()` 返回 TCHW。
  `Risk`：Low（纯诊断），但 render 在生产环境可能触发 GPU 渲染问题。

---

## 10. TensorDict Schema（接口视角）

| Key | Type/Spec | 生产者 | 消费者 | 说明 |
| --- | --- | --- | --- | --- |
| `("agents","observation")` | `UnboundedContinuousTensorSpec((n,D))`（或嵌套） | Task `_compute_state_and_obs` | PPO actor/critic、obs transforms | 唯一被策略读取的观测 |
| `("agents","intrinsics")` | `drone.intrinsics_spec.unsqueeze(0)` | Task obs | `priv_actor/priv_critic` 分支 | privileged DR 参数 |
| `("agents","action")` | 随 transforms 变化（最终 `Bounded(-1,1,(n,R))`） | actor → transforms | Task `_pre_sim_step` | **同一 key 在链上被逐级改写** |
| `("agents","reward")` | `UnboundedContinuousTensorSpec((n,1))` | Task reward | PPO GAE/ValueNorm | — |
| `done/terminated/truncated` | `DiscreteTensorSpec(2,(1,),bool)` | Task | torchrl auto-reset；PPO 用 `next.terminated` | done=term∨trunc |
| `("info","drone_state")` | `(n,13)` | Task obs（每步写） | 所有控制器 transforms | **Transform 的输入契约**：pos3+quat4+vel6 |
| `("info","prev_action")` | `(n,4)` | Task obs / transforms | LPF/PIDRate | — |
| `("info","policy_action")` | `(n,4)` | CBF filter / PIDRate transform | Task reward core（CBF/平滑项） | **滤波前策略指令** |
| `("info","obstacle_cbf")` | `(n,M,4)` | Task obs | `CBFVelocityFilter` | `[p_o(3), r_cbf(1)]`，未激活全 0 |
| `("stats", …)` | 任务自定义 | Task | `EpisodeStats`、日志 | 不喂策略 |
| `("loc","scale")` | `(n,4)` | actor | `get_dist`（train_op 后 exclude） | 分布参数 |
| `("sample_log_prob")` | `(n,1)` | actor（ProbabilisticActor） | PPO ratio | — |
| `("state_value")` | `(n,1)` | critic | GAE/ValueNorm | — |
| `("adv","ret")` | `(T,N,n,1)` | `train_op` | `_update` | 训练期临时键 |

**规则**：
1. 新增 **Transform 需要的** 中间量 → 放 `info`（并在 Task 的 `info_spec` 声明，否则 `fake_tensordict()` 会失败/形状漂移）；
2. 新增 **给策略的信号** → 放 `("agents","observation")` 并同步 spec 与 actor 输入维度；
3. **不要**把 `info/stats` 当观测喂给 actor（也不要在 reward 里依赖 `info` 中"未来才写入"的键——顺序是
   `_compute_state_and_obs` 先写 info，`_compute_reward_and_done` 后读，Transform 在两者之间执行）。

---

## 11. Algorithm Interfaces

### `PPOPolicy`

```python
class PPOPolicy(TensorDictModuleBase):
    def __init__(self, cfg: PPOConfig, observation_spec, action_spec, reward_spec, device)
    def __call__(self, tensordict) -> TensorDict          # actor+critic 前向（collector 用）
    def train_op(self, tensordict) -> dict[str, float]    # GAE + PPO 更新，返回日志
    def _update(self, tensordict) -> TensorDict           # 单个 minibatch
```

**Called by**：`SyncDataCollector(policy=policy)`（内部调用 `policy(td)`）；`train.py` 的 `policy.train_op(data)`。
**Input（train_op）**：rollout TensorDict（含 `next.*`、`state_value`、`sample_log_prob`、`agents.action`）。
**Output**：`{"policy_loss","value_loss","entropy","actor_grad_norm","critic_grad_norm","explained_var"}`（float）。
**Side Effects**：更新两个 Adam（actor/critic）与 `ValueNorm1` 的 running stats；在 td 上写 `adv/ret`。
**Lifecycle**：每 collector 迭代一次；内部 `ppo_epochs × num_minibatches` 次梯度步。
**Modification Risk**：**High**——超参（clip_param 硬编码 0.1、γ=0.99、λ=0.95、lr=5e-4）改动会让历史曲线不可比；
`clip_param` 与 `entropy_coef` 的仓库约定见 `cfg`/内存笔记。

### `GAE.forward(reward, terminated, value, next_value)`

**Input**：`reward (T,N,n,1)`、`terminated (T,N,n,1)`（**注意 PPO 里把 `next.terminated` repeat 到 agent 维**）、`value/next_value (T,N,n,1)`。
**Output**：`(advantages, returns)` 同 shape。
**Risk**：High（bootstrap 语义；`truncated` 不参与截断——这是刻意的，改前想清楚）。

### `ALGOS`（`learning/__init__.py`）

| 键 | 类 | 构造签名 |
| --- | --- | --- |
| `ppo` / `ppo_rnn` / `ppo_adapt` | `PPOPolicy` / `PPORNNPolicy` / `PPOAdaptivePolicy` | `(cfg.algo, obs_spec, act_spec, rew_spec, device)` |
| `mappo(_old)` / `happo` | `MAPPO` / `MAPPOPolicy` / `HAPPOPolicy` | 同上（读取 `env.agent_spec`） |
| `sac/td3/matd3/dqn/qmix/tdmpc` | 各自 Policy | 同上 |

**Risk**：High（`cfg.algo.name.lower()` 直接查表；键名改=所有训练命令失效）。

---

## 12. Configuration Interfaces

### `scripts/train.yaml`（根配置）关键键

| 键 | 消费点 | 说明 |
| --- | --- | --- |
| `hydra.searchpath` | Hydra 组合 | `file://../cfg`（相对 `scripts/`） |
| `defaults: task/algo` | Hydra | `task: Hover`、`algo: ppo` |
| `headless` | `init_simulation_app` + `IsaacEnv.enable_render` | — |
| `sim: ${task.sim}` / `env: ${task.env}` | 各脚本读取 | 从 task 树解引用 |
| `total_frames/max_iters/eval_interval/save_interval/seed` | `train.py` | — |
| `viewer.eye/lookat/resolution` | `IsaacEnv` 相机 + render product | — |
| `wandb.*` | `utils/wandb.py::init_wandb` | entity/project/group/run_name/mode |

### `cfg/task/*.yaml`（任务配置）

| 键 | 生效点 |
| --- | --- |
| `name` | `IsaacEnv.REGISTRY[cfg.task.name]`（**字符串=类名**） |
| `defaults: [/base/env_base@_here_, /base/sim_base@_here_]` | 把 `env:`/`sim:` 合并进本文件 |
| `env.{num_envs,max_episode_length,env_spacing}` | `IsaacEnv.__init__` / GridCloner |
| `sim.{dt,substeps}` | `SimulationContext(physics_dt=)` / `_step` 循环 |
| `drone_model.{name,controller}` | `MultirotorBase.make` |
| `action_transform` | `train.py/play.py/eval_ckpt.py` 的 if-elif 分支 |

**NavVel 专属键（节选，全部在 `cfg.task.*` 命名空间）**：
`arena_bound/bound_xy/z_min/z_max`、`episode_sampler(edge|uniform)`、`fixed_init/fixed_target`、
`arrive_radius/arrive_hold_steps/arrive_bonus`、`vel_limit.{max_vel,max_yaw_rate}`、`dr_noise_sigma`、
`reward_scheme(legacy|navgoal|r1|f1)` 及各项权重、`soft_respawn`、`single_episode_per_window`、
`randomization.drone.{train,eval}.*`、`obstacle.*`（形状/密度/奖励/CBF 几何）、`cbf.*`（模式/参数/调度）、
`curriculum.*`、`controller_sync_dr`。

### `PPOConfig`（ConfigStore，`learning/ppo/ppo.py`）

| 字段 | 默认 | 生效点 |
| --- | --- | --- |
| `name` | `"ppo"` | `cfg.algo.name.lower()` 查 ALGOS |
| `train_every` | 32 | `frames_per_batch = num_envs * train_every` |
| `ppo_epochs` / `num_minibatches` | 4 / 16 | `train_op` 循环 |
| `entropy_coef` | 0.001 | `_update` 的 entropy 项 |
| `priv_actor` / `priv_critic` | False | actor/critic 是否拼接 `intrinsics` |
| `checkpoint_path` | null | 构造时 `load_state_dict(strict=False)` |

**Risk**：Medium——`cs.store("ppo", ...)` 是 `algo=ppo` 的**唯一来源**（详见 Summary §8.1 的实测证据）；
改动默认值会改变所有未显式覆盖的超参。

---

## 13. Simulator Interfaces

| 接口 | 位置 | 输入 | 输出/副作用 | Risk |
| --- | --- | --- | --- | --- |
| `init_simulation_app(cfg)` | `omni_drones/__init__.py` | `cfg.headless`、（可选）`cfg.enable_livestream/port/address`、env `NAVVEL_KIT_EXTRA_ARGS` | 启动 SimulationApp；返回 app 句柄 | **High**（任何入口的第一步；异常 = 环境搭不起来） |
| `SimulationContext(...)` | `IsaacEnv.__init__` | `physics_dt=cfg.sim.dt`、`sim_params`（含 GPU 缓冲池）、`backend="torch"` | 物理上下文；`sim.reset()` 后才可建 physics view | High |
| `GridCloner` | `IsaacEnv.__init__` | `spacing=cfg.env.env_spacing`、模板 prim | 克隆 N 个 env，返回 `envs_positions (N,3)` | High |
| `SimulationContext.step(render)` | `IsaacEnv._step` | bool render | 推进物理（**段错误风险点**，见 sim_base.yaml 注释） | High |
| `omni_drones.views.ArticulationView / RigidPrimView` | `views/__init__.py` | prim 路径表达式 + shape | 批量读写物理状态/属性；fork 增补 mass/inertia/com getters/setters | High |
| `apply_forces_and_torques_at_position(...)` | `multirotor.apply_action`（经 `_physics_view`） | forces/torques `(count*num_bodies,3)`，`is_global=True` | 写入外力（**一次调用=一个 articulation 的全体**） | **High**（5.1 力取消语义） |
| `set_joint_velocities(...)` | 同上 | `rot_vel (count,R)` + joint_indices | 刷新关节速度（**必须在施力之前**） | High |

---

## 14. Call Graphs

### 14.1 Training Call Graph

```text
scripts/train.py::main(cfg)
 ├─ omni_drones/__init__.py::init_simulation_app
 ├─ omni_drones/utils/wandb.py::init_wandb
 ├─ IsaacEnv.REGISTRY[cfg.task.name] → Task 类 → Task.__init__
 │    └─ IsaacEnv.__init__ → Task._design_scene → MultirotorBase.make/spawn → IsaacEnv._set_specs
 ├─ utils/torchrl/transforms.py（Compose 组装；cbf.build_cbf_filter / VelController …）
 ├─ TransformedEnv(base_env, Compose(*transforms)).train()
 ├─ learning/ppo/ppo.py::PPOPolicy.__init__（fake_input 前向初始化 LazyLinear）
 ├─ utils/torchrl/collector.py::SyncDataCollector(env, policy, frames_per_batch, total_frames)
 └─ for data in collector:
       ├─ EpisodeStats.add(data.to_tensordict())
       └─ PPOPolicy.train_op(data.to_tensordict())
            ├─ GAE.forward
            ├─ ValueNorm1.update/normalize
            └─ _update ×(ppo_epochs·num_minibatches) → Adam.step
```

### 14.2 Environment Step Call Graph

```text
SyncDataCollector.rollout (torchrl)
 └─ policy(tensordict)                        # TensorDictModuleBase.__call__ → actor/critic
 └─ env.step(td)  = TransformedEnv.step
      ├─ transform._inv_call（逆序）: CBFVelocityFilter → CmdGaussNoise → VelController → LeePositionController.compute
      └─ IsaacEnv._step
           ├─ Task._pre_sim_step → MultirotorBase.apply_action → _apply_rotors → PhysX forces
           ├─ SimulationContext.step(render)
           ├─ Task._compute_state_and_obs → drone.get_state → obs/info
           └─ Task._compute_reward_and_done → reward/done/terminated/truncated (+ _respawn)
```

### 14.3 Reset Call Graph

```text
torchrl step_and_maybe_reset（done=True 的 env）
 └─ IsaacEnv._reset(td)
      ├─ env_ids = td["_reset"].nonzero()
      ├─ Task._reset_idx(env_ids)
      │    ├─ MultirotorBase._reset_idx(env_ids, training)   # 清零力/速度 + DR + 悬停油门
      │    ├─ （NavVel）curriculum.update(...); _sync_low_level_controller()
      │    ├─ drone.set_world_poses / set_velocities
      │    └─ （NavVel）obstacles.sample_layout / commit_layout / _write_obstacle_cylinder_scales
      ├─ progress_buf[env_ids] = 0
      └─ Task._compute_state_and_obs()   # 新观测
```

### 14.4 Crazyflie Action Call Graph

```text
policy action (N,1,4) [vx,vy,vz,yaw]
 →（可选）CBFVelocityFilter._inv_call           # utils/cbf.py
 →（可选）CmdGaussNoise._inv_call
 → VelController._inv_call                      # 限幅 + 调控制器
      └─ LeePositionController.compute → _compute → mixer → cmd = (mixer@[ang_acc, thrust] / max_thrusts)*2-1
 → Task._pre_sim_step
      └─ MultirotorBase.apply_action(cmds)
           ├─ _apply_rotors: throttle(tau) → thrusts=throttle²·KF, moments=±throttle²·KM
           ├─ torques = Σ moments·rotor_z_axis ;  forces += drag（+ downwash if n>1）
           ├─ set_joint_velocities(throttle·directions·MAX_ROT_VEL)
           └─ _physics_view.apply_forces_and_torques_at_position(combined, is_global=True)
 → PhysX 推进（sim.step）
```

### 14.5 Observation Call Graph

```text
sim state（PhysX + 视图）
 → MultirotorBase.get_state()      # (N,n,19+R)  （pos 转 env 系）
 → Task._compute_state_and_obs()
      ├─ rpos = target_pos - state[...,:3]
      ├─ rheading = target_heading - state[...,13:16]
      ├─ （NavVel）obstacles.build_obs / min_clearance / update_min_clearance / cbf_geom → info.obstacle_cbf
      ├─ obs = cat([rpos, state[...,3:], rheading, time, obstacle_block, safety?], -1)
      └─ info.drone_state[:13]、info.prev_action ← 由 transforms 写入的部分同步回 self.info
 → TensorDict("agents"/"info"/"stats")  → ("next", …) 组装 → policy.actor
```

---

## 15. Interface Dependency Matrix

| Interface | Called By | Calls | Input Shape | Output Shape | Risk |
| --- | --- | --- | --- | --- | --- |
| `IsaacEnv.__init__` | 全部入口、所有 Task 的 super() | SimulationContext / GridCloner / `_design_scene` / `_set_specs` | cfg, bool | — | **High** |
| `IsaacEnv._step` | torchrl EnvBase.step | `_pre_sim_step`、`sim.step`、`_compute_*` | td[(agents,action)] `(N,n,R)` | reward/done/obs TD | **High** |
| `IsaacEnv._reset` | torchrl reset | `_reset_idx`、`_compute_state_and_obs` | `_reset` mask `(N,)` | obs TD | **High** |
| `Task._design_scene` | IsaacEnv.__init__ | `MultirotorBase.make/spawn`、kit 工具 | — | prim 列表 | High |
| `Task._set_specs` | IsaacEnv.__init__ | 构造 CompositeSpec | — | — | High |
| `Task._reset_idx` | IsaacEnv._reset | drone._reset_idx、set_world_poses、布局采样 | `(k,)` | — | High |
| `Task._pre_sim_step` | IsaacEnv._step | `drone.apply_action` | `(N,n,R)` ∈[-1,1] | — | High |
| `Task._compute_state_and_obs` | IsaacEnv._step/_reset | `drone.get_state`、障碍 obs | — | obs `(N,n,D)` | High |
| `Task._compute_reward_and_done` | IsaacEnv._step | 障碍/CBF 工具、`_respawn` | — | reward `(N,n,1)`, done `(N,1)` | High |
| `MultirotorBase.make` | Task._design_scene、examples | REGISTRY | name str | `(drone, controller)` | High |
| `MultirotorBase.initialize` | Task.__init__ | RobotBase.initialize、RotorGroup、make_functional | prim expr | — | High |
| `MultirotorBase.apply_action` | Task._pre_sim_step | `_apply_rotors`、views、PhysX | `(N,n,R)` | effort `(N,n)` | **High** |
| `MultirotorBase._apply_rotors` | apply_action | torch 张量运算 | `(…,R)` | thrusts `(…,R)`, moments `(…,R)` | High |
| `MultirotorBase.get_state` | 所有 Task obs | 视图 get_* | — | `(N,n,19+R)` | High |
| `MultirotorBase._reset_idx` | Task._reset_idx | `_randomize`、set_masses/inertias | `(k,)` | — | High |
| `RotorGroup.forward` | （历史/vmap 路径）、参数提取 | 张量运算 | `(…,R)` | thrusts/moments | Medium |
| `RotorGroup.__init__` | MultirotorBase.initialize | — | rotor_config, dt | — | Medium |
| `make_functional` | MultirotorBase.initialize | 参数提取 | module | TensorDict | Medium |
| `LeePositionController.compute` | VelController | `_compute`、mixer | root_state `(…,13)` | cmd `(…,R)` | High |
| `LeePositionController.sync_randomized` | NavVel._sync_low_level_controller | — | mass `(…,1)`, kf `(…,R)` | self | Medium |
| `PIDRateController.forward` | PIDRate transform | PID+mixer | `(…,13)`, `(…,3)`, `(…,1)`, `(…,)` | cmd `(…,R)`, ctbr `(…,4)` | High |
| `VelController._inv_call` | TransformedEnv（动作侧） | `controller.compute` | action `(N,n,4)` | action `(N,n,R)` | High |
| `CBFVelocityFilter._inv_call` | TransformedEnv（动作侧） | `filter_velocity` | action `(N,n,4)`、obs_cbf `(N,n,M,4)` | action 同 shape | High |
| `build_cbf_filter` | train.py / eval 脚本 | `extract_cbf_params` | cfg | filter 或 None | Medium |
| `filter_velocity` | CBFVelocityFilter、(NavVel) reward | `_gradients` | pos `(…,3)`, v `(…,3)`, obs `(…,K,3)`, r `(…,K)`, act `(…,K)` | v_safe `(…,3)`, fix_norm `(…,)` | Medium |
| `cbf_violation` | （NavVel) reward core | `_gradients` | 同上 | viol `(…,)` ≤0 | Medium |
| `ObstacleManager.build_obs` | NavVel._compute_state_and_obs | （内部窗口/SDF） | drone_pos `(N,1,3)` | `(N,1,4K 或 7K)` | Medium |
| `ObstacleManager.clearances/min_clearance/cbf_geom` | NavVel reward/obs | SDF 工具 | drone_pos | `(N,K)`/`(N,1)`/`(N,M,3)+(N,M)` | Medium |
| `ObstacleManager.sample_layout(_full)/commit_layout/update_min_clearance` | NavVel reset/step | 布局采样 | init/goal pos、env_ids | 布局张量/写 self | Medium |
| `scene_slot_count / obs_slot_dim` | NavVel.__init__ / _set_specs | — | oc cfg dict | int | Medium（与 prim 数一致性） |
| `AgentSpec`（属性） | 多机算法、_set_specs | env specs | — | TensorSpec | Medium |
| `EpisodeStats.add/pop` | train.py | — | rollout TD | list/长度 | Low |
| `SyncDataCollector.iterator/rollout` | train.py / 批量脚本 | torchrl collector | — | `(T,N,…)` TD | High |
| `PPOPolicy.__call__/train_op/_update` | collector / train.py | GAE、ValueNorm、Adam | rollout TD | 指标 dict | High |
| `GAE.forward` | train_op | — | `(T,N,n,1)` ×4 | adv/ret | High |
| `PPOConfig`（ConfigStore） | Hydra | — | — | algo 配置节点 | Medium |
| `init_simulation_app` | 全部入口 | SimulationApp | cfg | app | High |
| `views.ArticulationView/RigidPrimView.*` | robot/multirotor/env | Isaac physics API | — | 张量 | High |
| `tensordict_compat.make_functional` | multirotor.initialize | — | module | TensorDict | Medium |
| `torchrl.compat.*`（spec 别名） | 全项目 import | — | — | 类 | **High**（全项目 import 面） |

---

## 附：修改者速查（本仓库特有约定）

1. **`("agents","action")` 的生命周期**：actor 写 → transforms 逆序改写 3 次（CBF/噪声/控制器）→ Task 读。
   想插入新的动作层处理，**追加到 transforms 列表**并核对逆序语义。
2. **`info` 是"时序契约"**：`_compute_state_and_obs` 必须把 Transform 下一拍需要的量写全
   （`drone_state`、`obstacle_cbf` 等），漏写会在 Transform 里 KeyError 或读到陈旧值。
3. **`stats` 是仪表盘**：改 reward 记得同时加 `term_*` 类的分项 EMA（本仓库历史教训）。
4. **兼容层不可删**：`utils/torchrl/compat.py`、`utils/tensordict_compat.py`、`views/__init__.py` 的 try/except、
   `multirotor.apply_action` 的 5.1 分支。
5. **默认关=逐位兼容**：所有新行为都应"默认关闭"（仓库约定，见 `_set_specs`/yaml 注释里的 "默认 0=关(逐位兼容)"）。
6. **改动后跑最小验证**：`python train.py task=<x> algo=ppo headless=true total_frames=<小> wandb.mode=disabled`
   （GPU 串行、`--parallel 2` 上限）；确定性验收用 `eval_ckpt.py +checkpoint= +rollout_steps=`。

