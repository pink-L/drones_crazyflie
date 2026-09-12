# SimpleFlight → drones/OmniDrones (Isaac 5.1 fork) 迁移详细指南

> 配套：`refs_guide.md`（refs 组织）、`how2use.md` §3.2/§4（整合路线 M1/M4）。
> 目标：把 SimpleFlight 的 **Crazyflie + CTBR/速度指令 动作管线**移植进你的 5.1 fork，
> 打通 `M1（速度指令任务）` 与 `M4（PIDrate/CTBR 管线）`，为后续 CBF1/CBF3 打地基。
>
> ✅ **迁移已于 2026-09-04 执行完成并验证通过**（执行记录见文末"附录 A"）。
> 本文前半部分为方法/背景，后半部分（附录 A）为实际执行结果与实测偏差，以附录 A 为准。

---

## 0. 迁移全景（先看这张图）

```mermaid
flowchart LR
    subgraph 策略
      A[PPO 输出 4D<br/>rate_x,rate_y,rate_z,thrust]
    end
    A -->|Transform._inv_call| B[PIDRateController Transform<br/>tanh→rate·180°·clip<br/>thrust→[0,2^16]PWM]
    B --> C[PIDRateController nn.Module<br/>机体角速度率环 PID]
    C --> D[cmd ∈ [-1,1]/转子<br/>存入 agents.action]
    D --> E[drone.apply_action<br/>fork Isaac5.1 转子仿真]
    E --> F[throttle 一阶滞后 + 推力]
    A2[旧轨迹] -.info/prev_action.-> B
```

一句话原理：**策略不再直接给油门，而是给"机体角速度指令 + 集合推力(CTBR)"**；
Transform 层把 CTBR 换算成每转子归一化指令 `cmd∈[-1,1]`，再走 `drone.apply_action`。

---

## 1. 现状盘点（实测，非猜测）

| 模块 | 你的 fork 现状 | SimpleFlight 源 | 迁移动作 |
|---|---|---|---|
| `controllers/cf2x_pid.py` | ✅ **与 SimpleFlight 逐字节相同**(211 行，`DSLPIDControl` 位置控制器) | 相同 | **无需动** |
| `controllers/dsl_pid_controller.py` | ❌ 不存在(`DSLPIDController`) | 131 行 | 复制 + 改 import |
| `controllers/lee_position_controller.py` | 361 行：`Lee/Attitude/Rate`(继承 `ControllerBase`) | 696 行：多 `PID_controller_flightmare`(L433)、`PIDRateController`(L512) | 复制这两个类(或其所在段) |
| `controllers/__init__.py` | 只导出 4 个 | 导出 `DSLPIDController + 上述6个` | 补导出 |
| `utils/torchrl/transforms.py` | 329 行：有 `Rate/Attitude`(Transform)，无 `Vel`/`PIDRate` | 617 行：`Pos/Vel/Rate/PIDRate/flightmare/...` | 补 `VelController`、`PIDRateController` (Transform) |
| `robots/drone/crazyflie.py` | 有(已改 compat import)，**无** `DEFAULT_CONTROLLER` | 有 `DEFAULT_CONTROLLER=DSLPIDController` | 可选补 |
| `robots/assets/usd/crazyflie.yaml` | 旧参数(mass 0.028, kf 2.88e-8)，**缺**控制参数块 | SysID 参数 + `LPF_coef/target_clip/.../time_constant` | 按 §4.3 覆盖 |
| `actuators/rotor_group.py` + `multirotor._apply_rotors` | tau=0.43 硬编码、无 time_constant | tau=`dt/time_constant`、可配 noise | 按 §4.3 小改 |
| env（hover/track 等） | **没有任何 env 提供 `info/drone_state`** | hover/track 均提供 | 按 §4.4 给目标 env 加 info |
| `scripts/train.py` / `play.py` | 只支持 discrete 派发 | 支持 `velocity/attitude/rate/PIDrate/PIDrate_FM` | 补派发分支 |
| `scripts/eval.py` | ❌(只有 play.py) | 有 | 可选(先用 play.py) |
| 附带：`VelController` 的低层 | fork 自带 `LeePositionController.compute(target_vel=...)` ✅ | — | M1 直接可用 |

**结论**：真正要"从 SimpleFlight 搬"的代码量很小且集中（约 4 个类 + 1 段 env 改动 + train.py 分支）；
大头是**让 env 提供 transform 需要的键** 和 **版本适配**（§5）。

---

## 2. 推荐的落地方式（重要）

1. **改代码只发生在 `drones/OmniDrones/`**；`refs/SimpleFlight/` 只读。
2. 先开实验分支，随时可 diff：
   ```bash
   cd /home/lz/lzspace/drones/OmniDrones
   git checkout -b feat/crazyflie-pidrate
   ```
3. **不要整体替换文件**。fork 的 `multirotor.py`、`isaac_env.py`、`hover.py` 等含 Isaac 5.1 专属改动
   （如 `apply_action` 的 articulation 合力单次调用、5.1 注释），只能"文件级 + 函数级"移植。
4. 每完成一个 Stage 就跑一次冒烟（见 §6），不要攒到最后。
5. import 一律走 fork 的 compat 层（`omni_drones.utils.torchrl.compat`），见 §5。

---

## 3. Stage 1 — 控制器层（纯 torch，先搬）

> 目的：让 fork 里能 `from omni_drones.controllers import PIDRateController`。
> 两个类都只依赖 torch + `omni_drones.utils.torch`（fork 已有全部 helper：`normalize/quaternion_to_euler/quaternion_to_rotation_matrix/quat_rotate_inverse`，已核实），**不碰 Isaac API**，风险最低。

### 3.1 新增 `omni_drones/controllers/dsl_pid_controller.py`
- 整文件复制 `refs/SimpleFlight/omni_drones/controllers/dsl_pid_controller.py`(131 行)。
- 其 import `from omni_drones.utils.torch import normalize, quaternion_to_euler, quaternion_to_rotation_matrix` 在 fork 里直接可用。
- 说明：`DSLPIDController` 在 SimpleFlight 里主要作为 `Crazyflie.DEFAULT_CONTROLLER`（位置-速度型低层）。
  它不是 PIDrate 链路的必需品（PIDrate 用的是 §3.2 的 `PIDRateController`），但补上可保持与上游 robot 语义一致、也方便以后做位置跟踪基线。

### 3.2 在 `controllers/lee_position_controller.py` 追加两个类
把 SimpleFlight 该文件 **L433 `PID_controller_flightmare` 与 L512 `PIDRateController`** 两个类复制进 fork 的 `lee_position_controller.py` 末尾。
- 依赖：文件顶部 import 两边**完全一致**（已核实，含 `quat_rotate_inverse`），fork 只多一个 `ControllerBase` import，无冲突。
- `PIDRateController.__init__(self, dt, g, uav_params)` 会读取：
  - `uav_params["rotor_configuration"]["force_constants"/"max_rotation_velocities"]`（已有）
  - `uav_params["LPF_coef"] / ["target_clip"] / ["min_thrust_ratio"] / ["max_thrust_ratio"] / ["fixed_yaw"]`（**当前 fork crazyflie.yaml 没有** → 必须先做 §4.3）
- `PID_controller_flightmare` 可选（对应 `PIDrate_FM`/飞行模拟器对照）；不急着做可先跳过。

### 3.3 更新 `controllers/__init__.py`
在 `lee_position_controller.py` 的导出里补 `PIDRateController, PID_controller_flightmare`，并 `from .dsl_pid_controller import DSLPIDController`。

### 冒烟（Stage 1 完成）
```bash
conda activate lz_env
cd /home/lz/lzspace/drones/OmniDrones/scripts
python -c "from omni_drones.controllers import DSLPIDController, PIDRateController; import torch; c=PIDRateController(0.01,9.81,{'LPF_coef':1.0,'target_clip':1.0,'min_thrust_ratio':0.,'max_thrust_ratio':0.9,'fixed_yaw':0,'rotor_configuration':{'force_constants':[2.35e-8]*4,'max_rotation_velocities':[2315.]*4}}); s=torch.zeros(1,13); print(c(s, torch.zeros(1,3), torch.ones(1,1)*32768, torch.ones(1,dtype=torch.bool))[0])"
```
（能打印出 4 个 `[-1,1]` 的 cmd 即 OK）

---

## 4. Stage 2 — Transform 层（torchrl 版本适配点最多）

> 目的：让策略输出 CTBR 时自动被换算成转子指令。文件：`omni_drones/utils/torchrl/transforms.py`。

### 4.1 从 SimpleFlight 复制两个 Transform 类
把 `refs/SimpleFlight/.../transforms.py` 中：
- `class VelController(Transform)`（L333，**M1 速度指令要用**）
- `class PIDRateController(Transform)`（L404，**M4 CTBR 要用**）
- （可选）`PIDRateController_flightmare`(L469)

复制到 fork 的 transforms.py。fork 已有 `RateController/AttitudeController` Transform 可作对照。

### 4.2 ⚠️ 必须改的一处（torchrl 0.11 适配）
SimpleFlight 的 Transform 里写的是：
```python
action_spec = input_spec[("_action_spec", *self.action_key)]
```
fork(torchrl 0.11) 的现有 Transform 写的是：
```python
action_spec = input_spec[("full_action_spec", *self.action_key)]
```
**复制后把所有 `"_action_spec"` 改成 `"full_action_spec"`**，否则 KeyError。

### 4.3 其它 import 适配
- 文件顶部换成 fork compat：`from omni_drones.utils.torchrl.compat import ... UnboundedContinuousTensorSpec ...`（fork 已导）。
- `PIDRateController(Transform)` 内部会用 `self.controller.max_thrusts / target_clip / max_thrust_ratio / min_thrust_ratio / LPF_coef` → 这些来自 §3.2 控制器实例，自动带上。

### 4.4 这些 Transform 依赖 env 提供（重点，见 §5 Stage 4）
- `("info", "drone_state")`：13 维 `[pos(3),quat(4),vel(3),angvel(3)]`
- `("info", "prev_action")`、`("info", "policy_action")`：4 维 CTBR
- `("stats", "action_error_order1")`（写回用）
- `tensordict["done"]`（PID 积分器 reset 用）

---

## 5. Stage 3 — 机器人参数 / 动力学（决定"像不像真 Crazyflie"）

### 5.1 先弄清两边转子模型差异（已核实）
| | fork(5.1) | SimpleFlight |
|---|---|---|
| 一阶滞后 | `tau_up/down=0.43` **硬编码**（每步比例） | `rotor_config["time_constant"]=0.025`，`forward` 内 `tau = dt/time_constant`（**秒单位一阶滞后**） |
| 转子噪声 | `noise_scale=0.002` 硬编码(且×0) | `rotor_config["noise_scale"]=0.0` 可配 |
| cmd→throttle | `sqrt((cmd+1)/2)` | 相同 |
| 推力 | `t*KF`, KF=ωmax²·kf | 相同 |

- fork 的 `apply_action` 走 `multirotor.py::_apply_rotors`（**Isaac 5.1 专属**：articulation 里先设 joint velocity、再用 `apply_forces_and_torques_at_position` 一次合并施力，注释明确写了 5.1 的坑）。
- `RotorGroup.forward` 在 fork 里其实**没被 apply_action 调用**（只用来产出 `rotor_params` 缓冲）。
  → **不要整体替换 `multirotor.py` 或 `rotor_group.py`**，只做两处小改（见 5.3/5.4）。

### 5.2 替换 `crazyflie.yaml`（关键参数表）
把 fork 的 `omni_drones/robots/assets/usd/crazyflie.yaml` 换成 SimpleFlight 的 SysID 版（**保留 fork 中缺失但 SimpleFlight 有的字段**），差异如下：

| 字段 | fork 现值 | SimpleFlight SysID 值 |
|---|---|---|
| `mass` | 0.028 | **0.0321** |
| `drag_coef` | 0.2 | **0.0** |
| `rotor_configuration.force_constants` | 2.88e-8 | **2.350347298350041e-08** |
| `rotor_configuration.moment_constants` | 7.24e-10 | 7.24e-10（同） |
| `rotor_configuration.max_rotation_velocities` | 2315 | 2315（同） |
| `rotor_configuration.time_constant` | ❌无 | **0.025** |
| `rotor_configuration.noise_scale` | ❌无 | 0.0 |
| 顶层 `LPF_coef/target_clip/min_thrust_ratio/max_thrust_ratio/fixed_yaw` | ❌无 | 1.0 / 1.0 / 0.0 / 0.9 / 0 |
| `controller_configuration` | ❌无 | 无效字段（注释里标了 invalid），可带上也可删 |

> 若你只是想先跑通管线（M1/M4 冒烟、不追求 zero-shot），可**先只加"控制参数块"**（LPF/target_clip/…），
> 保留 fork 的 mass/kf；等要复现 SimpleFlight 动力学/做 sim2real 时再整体换成 SysID 值。

### 5.3 让 fork 的 rotor 一阶滞后可配（对应 SysID 的 time_constant）
- `actuators/rotor_group.py`：把
  ```python
  self.tau_up = nn.Parameter(0.43 * torch.ones(self.num_rotors))
  self.tau_down = nn.Parameter(0.43 * torch.ones(self.num_rotors))
  ```
  改成从 `rotor_config` 读 `time_constant`（与 SimpleFlight L34/47-48 相同），缺失时 fallback 0.43。
- `robots/drone/multirotor.py::_apply_rotors`：在 `tau=torch.clamp(tau,0,1)` 之后加一行
  ```python
  tau = self.dt / tau.clamp_min(1e-3)   # 一阶滞后，tau 单位=秒（对齐 SimpleFlight）
  ```
  （`self.dt` 在 fork 里已有，见 multitorotor 初始化 `RotorGroup(rotor_config, dt=self.dt)`。）
  > 影响面：所有用 Crazyflie 的任务。若只想影响 Crazyflie，可把该行放在 `if self.name=="crazyflie"` 分支里，或做成 yaml 开关。

### 5.4 控制频率（重要）
- SimpleFlight：`sim.dt=0.01`(100 Hz)、substeps=1。
- fork 默认：`dt=0.016`(62.5 Hz)。
- `PIDRateController` 用 `cfg.sim.dt` 做积分/微分，**dt 变了等于换了一套 PID/电机响应**。
  → Crazyflie/CTBR 实验建议在 task yaml 覆盖 `sim.dt: 0.01`（如何覆盖见 §7.4）。

---

## 6. Stage 4 — env 提供 `info` 键（绕不开的一步）

> 已核实：fork **所有 env 都没写 `observation_spec["info"]`**，而所有控制器 Transform 都读 `("info","drone_state")`。
> 所以即便 Stage1-3 全搬完，直接 `action_transform=PIDrate` 也会 KeyError。必须给目标 env 加。

两条路线：

### 路线 A：给 fork 现有 `Hover` 做"最小手术"（推荐先做，M1/M4 冒烟）
参考 SimpleFlight `envs/single/hover.py` 的对应改动（L168/280-287/333-336/350-370/431），在 fork 的 `Hover` 里加：
1. `__init__`：`self.prev_actions = torch.zeros(self.num_envs, 1, 4, device=self.device)`
2. `_set_specs`：构造并挂 info spec
   ```python
   info_spec = CompositeSpec({
       "drone_state": UnboundedContinuousTensorSpec((1, 13), device=self.device),
       "prev_action": UnboundedContinuousTensorSpec((1, 4), device=self.device),
       "policy_action": UnboundedContinuousTensorSpec((1, 4), device=self.device),
   }).expand(self.num_envs).to(self.device)
   self.observation_spec["info"] = info_spec
   self.info = info_spec.zero()
   ```
3. `_reset_idx`：`self.info[env_ids]=0`，并把悬停推力写进 prev_action 第 4 维（thrust 通道）：
   ```python
   cmd_init = 2.0 * (self.drone.throttle[env_ids]) ** 2 - 1.0
   self.info["prev_action"][env_ids, :, 3] = cmd_init.mean(-1)
   self.prev_actions[env_ids] = self.info["prev_action"][env_ids].clone()
   ```
4. `_pre_sim_step`：把 Transform 写回的键收进 `self.info`（供下一次 obs 输出）：
   ```python
   self.info["prev_action"]   = tensordict[("info", "prev_action")]
   self.info["policy_action"] = tensordict[("info", "policy_action")]
   self.prev_actions = self.info["prev_action"].clone()
   self.effort = self.drone.apply_action(actions)   # 原有
   ```
5. `_compute_state_and_obs`：先填 `self.info["drone_state"][:] = self.drone_state[..., :13]`，返回的 td 里加 `"info": self.info`。

> 这样 fork 的 Hover 就同时支持 `rate / attitude / velocity / PIDrate` 四种 transform 了。

### 路线 B：整体移植 SimpleFlight 的 `track.py`/`hover.py`（真正复现其奖励与观测）
若目标是"复现 SimpleFlight Track 的奖励课程/观测/评估轨迹"（M4 高端版），直接把
`refs/SimpleFlight/omni_drones/envs/single/{hover,track}.py` 拷过来改名（如 `TrackSF`）再适配。
需要处理的差异（已核实）：
1. `cfg.task.drone_model`：SimpleFlight 是**字符串** `"Crazyflie"`（env 里 `MultirotorBase.REGISTRY[...]`）；
   fork 是 **dict `{name, controller}`**（env 里 `MultirotorBase.make(...)`）。二选一统一（fork REGISTRY 同样存在）。
2. import：`from torchrl.data import ...` → `from omni_drones.utils.torchrl.compat import ...`；`tensordict.nn` 的 helper 视 fork 而定。
3. SimpleFlight 的 Track 有 `use_eval/eval_traj/action_history/use_ab_wolrd_pos` 等任务级超参 → 在 task yaml 里补齐（照抄 `refs/SimpleFlight/cfg/task/Track.yaml` 的键）。
4. `MultirotorBase.make` 返回 `(drone, controller)`；若你的 env 不需要 env 内 controller，`controller=None` 即可。

> **建议**：先走路线 A 用 fork Hover 冒烟；Track 级别的复现放到路线 B，且作为独立任务，别动 fork 现有任务。

---

## 7. Stage 5 — 训练/回放入口派发 + 任务配置

### 7.1 `scripts/train.py`（fork 版，L62-73 只支持 discrete）
在 `else: raise NotImplementedError` 之前追加（参考 SimpleFlight train.py L157-183，但适配 fork 的 import 与签名）：
```python
elif action_transform == "velocity":
    from omni_drones.controllers import LeePositionController
    from omni_drones.utils.torchrl.transforms import VelController
    controller = LeePositionController(9.81, base_env.drone.params).to(base_env.device)
    transforms.append(VelController(controller))
elif action_transform == "rate":
    from omni_drones.controllers import RateController as _RC
    from omni_drones.utils.torchrl.transforms import RateController
    transforms.append(RateController(_RC(9.81, base_env.drone.params).to(base_env.device)))
elif action_transform == "attitude":
    from omni_drones.controllers import AttitudeController as _AC
    from omni_drones.utils.torchrl.transforms import AttitudeController
    transforms.append(AttitudeController(_AC(9.81, base_env.drone.params).to(base_env.device)))
elif action_transform == "PIDrate":
    from omni_drones.controllers import PIDRateController as _PRC
    from omni_drones.utils.torchrl.transforms import PIDRateController
    transforms.append(
        PIDRateController(_PRC(cfg.sim.dt, 9.81, base_env.drone.params).to(base_env.device))
    )
```
> 注意：fork 的 policy 走 `ALGOS[..](cfg.algo, obs_spec, action_spec, reward_spec)`（新式），
> transform 改 `("full_action_spec","agents","action")` 后策略自然拿到 4D 连续动作空间，**无需改 policy**。
> `LeePositionController(9.81, params)` 构造里会读 `controllers/cfg/lee_controller_<name>.yaml`（fork 已有 cfg/）。

### 7.2 `scripts/play.py`
同样补派发分支（照抄 train.py 的写法），否则回放时维度对不上。

### 7.3 任务 yaml（在 `cfg/task/` 下新建，别改 fork 原任务）
- `HoverCrazyflie.yaml`（冒烟用）：以 `Hover.yaml` 为底，改：
  ```yaml
  drone_model:
    name: Crazyflie
    controller: null
  action_transform: PIDrate   # 或 velocity / rate
  ```
- `TrackSF.yaml`（路线 B 时）：照抄 SimpleFlight `cfg/task/Track.yaml` 全部键 + fork 式 `drone_model` dict。

### 7.4 sim dt 覆盖
在 task yaml 里（Hydra 顶层结构 fork 的 task 下没有 sim，需用命令行覆盖）：
```bash
python train.py task=HoverCrazyflie algo=ppo headless=true wandb.mode=disabled \
  sim.dt=0.01 sim.substeps=1 max_iters=1
```
（fork `cfg/base/sim_base.yaml` 默认 dt=0.016，实测覆盖后冒烟用。）

---

## 8. Stage 6 — 冒烟与验收

按顺序，每步通过再进下一步：

1. **Stage1 控制器**：§3.3 的 python -c 能打印 4 个 cmd。
2. **Stage3 参数**：`cfg/task/HoverCrazyflie.yaml` 配好后，
   ```bash
   python train.py task=HoverCrazyflie algo=ppo headless=true wandb.mode=disabled \
     sim.dt=0.01 sim.substeps=1 max_iters=1
   ```
   不报 KeyError（尤其 `info/drone_state`、`LPF_coef` 等键）、能采集 1 轮。
3. **Stage4/5 联动**：短跑 `total_frames=2e6`，看 wandb 里 `return` 上升、悬停稳定
   （CTBR 悬停时 thrust 通道应收敛到悬停指令、rate 通道≈0）。
4. **M1 速度指令**：`action_transform=velocity`，Hover 目标改成"飞向随机点/跟轨迹"（用 fork 自带 Lee 的 `target_vel`），
   观察无人机能平滑到位、无 NaN。
5. **M4 CTBR**：`action_transform=PIDrate` + TrackSF（路线 B），对比 SimpleFlight 论文量级的表现
   （跟踪误差 < 0.1m 量级、动作平滑）。此时再谈 SysID 参数整体替换与 DR。
6. 回放目视：`python play.py task=... algo=ppo action_transform=PIDrate checkpoint=... headless=false`

---

## 9. 版本适配要点汇总（最容易踩的坑）

1. **`"_action_spec"` → `"full_action_spec"`**（torchrl 0.11，fork transforms 里现成的写法）。
2. **所有 spec/torchrl import 走 `omni_drones.utils.torchrl.compat`**，别直接 `from torchrl.data import ...`。
3. **env 必须先提供 `info/drone_state` 等键**，否则 Transform 报 KeyError（fork 目前没有任何 env 提供）。
4. **控制器读的 crazyflie.yaml 键必须先补齐**（`LPF_coef/target_clip/.../time_constant/noise_scale`）。
5. **sim dt**：PIDrate 是 dt 相关控制器，Crazyflie 实验建议 0.01；fork 默认 0.016 属于"另一个世界"的参数。
6. **fork `multirotor.py`/`apply_action` 是 5.1 专属**：只改 `_apply_rotors` 内部，别整文件替换。
7. **task yaml 的 `drone_model` 结构**：fork 是 dict（`name/controller`），SimpleFlight 是字符串；从 SimpleFlight 拷 env 时统一。
8. **policy 接口**：fork 走 `ALGOS(cfg.algo, obs/action/reward_spec)`，别照抄 SimpleFlight 的 `agent_spec` 旧式调用。
9. **不要 `git submodule update`**（SimpleFlight third_party 是 ssh 老 torchrl/tensordict，本机不需要）。
10. 环境名 `lz_env`，命令都在 `OmniDrones/scripts/` 下跑。

---

## 10. 文件级"搬运清单"（速查）

| # | 动作 | 源(refs/SimpleFlight) | 目标(drones/OmniDrones) |
|---|---|---|---|
| 1 | 复制 | `omni_drones/controllers/dsl_pid_controller.py` | 同路径（新） |
| 2 | 追加类 | `controllers/lee_position_controller.py` L512 `PIDRateController`(+L433 可选) | 同文件末尾 |
| 3 | 补导出 | `controllers/__init__.py` | 同文件 |
| 4 | 复制+改键 | `utils/torchrl/transforms.py` L333 `VelController`、L404 `PIDRateController` | 同文件（`_action_spec`→`full_action_spec`） |
| 5 | 覆盖/合并 | `robots/assets/usd/crazyflie.yaml` | 同路径 |
| 6 | 小改 | `actuators/rotor_group.py` L46-48 | 读 time_constant |
| 7 | 小改 | `robots/drone/multirotor.py` `_apply_rotors` | 加 `tau=self.dt/tau` |
| 8 | 小改 | `envs/single/hover.py`(SimpleFlight L168/280/333/350/370/431 六处) | fork 同文件 |
| 9 | 补分支 | `scripts/train.py` / `play.py` | fork 同文件 |
| 10 | 新建 | `cfg/task/TrackSF.yaml` 等 | 同路径 |

> 参考对照命令：
> ```bash
> diff -u refs/SimpleFlight/omni_drones/controllers/lee_position_controller.py \
>       drones/OmniDrones/omni_drones/controllers/lee_position_controller.py   # 看 L433-696 差异段
> ```

---

## 11. 与后续研究（CBF/NavRL）的衔接

- **M1 落地后**：速度指令的"策略输出"就是 VelController 的输入 `[vx,vy,vz,yaw]` ——
  在这里插 CBF1 滤波（`omni_drones/utils/cbf.py`），再交给 Lee → 电机，正是 how2use §4.1 的落点。
- **M4 落地后**：`PIDRateController(Transform)._inv_call` 里的 `action`（4D CTBR）就是 CBF3 滤波的插入点
  （滤波需要 `drone_state` + 障碍 → transform 里都有，天然 vectorized）。
- **记录中间量**：Transform 已把 `prev_action/policy_action/action_error_order1` 写进 info/stats，
  CBF 违反次数等指标照此模式加 `("stats", ...)` 键即可进 wandb。
- NavRL 的动态障碍/导航奖励属于"任务内容"，等 M1/M4 动作管线稳定后再按 `refs_guide.md` §4.2 移植。

---

## 附录 A：迁移执行记录（2026-09-04，已完成 ✅）

> 分支：`feat/crazyflie-pidrate`（`drones/OmniDrones`）。
> 冒烟硬件：Isaac Sim 5.1 headless，`lz_env`（torchrl 0.11.1）。所有验证命令在 `OmniDrones/scripts/` 下执行。

### A.1 实际改动清单（本次迁移）

| 文件 | 改动 | 说明 |
|---|---|---|
| `omni_drones/controllers/dsl_pid_controller.py` | **新增**（131 行，从 refs 原样复制） | `DSLPIDController` |
| `omni_drones/controllers/lee_position_controller.py` | 末尾**追加** `PID_controller_flightmare` + `PIDRateController` | 文件 361→约 626 行；顶部 import 复用，无新增依赖 |
| `omni_drones/controllers/__init__.py` | 补导出 `PIDRateController, PID_controller_flightmare, DSLPIDController` | |
| `omni_drones/utils/torchrl/transforms.py` | **追加** `VelController(Transform)` + `PIDRateController(Transform)` | 已做 `_action_spec → full_action_spec` 适配 |
| `omni_drones/robots/assets/usd/crazyflie.yaml` | **整体覆盖**为 SimpleFlight SysID 版 | mass 0.0321 / kf 2.3503e-8 / time_constant 0.025 / 控制参数块 |
| `omni_drones/actuators/rotor_group.py` | 读 `rotor_config["time_constant"]`；forward 内 `tau = dt/tau` | **有 `time_constant` 才启用**，否则回退 0.43（不影响其它机型） |
| `omni_drones/robots/drone/multirotor.py` | ① `initialize`：`update_sim: True` 时把 yaml mass 写进 sim；② `_apply_rotors`：`tau = self.dt / tau`（仅 time_constant 机型） | fork 原版不把 yaml mass 同步到 sim（实测 USD 质量 0.027） |
| `omni_drones/envs/single/hover.py` | 加 `info/drone_state/prev_action/policy_action` 五处 | 参考 SimpleFlight L168/280/333/350/370/431 |
| `scripts/train.py` / `scripts/play.py` | action_transform 加 `velocity`、`PIDrate` 分支 | |
| `omni_drones/controllers/cfg/lee_controller_crazyflie.yaml` | **新增**（从 hummingbird 复制，初始增益） | 支持 Crazyflie 走 `velocity` |
| `cfg/task/HoverCrazyflie.yaml` | **新增**（Hover + Crazyflie + `action_transform: PIDrate` + `sim.dt: 0.01`） | 冒烟/训练入口 |
| `omni_drones/controllers/cf2x_pid.py` | **未改动** | 与 SimpleFlight 逐字节相同（fork 仓库里处于未跟踪状态，本就存在） |

### A.2 执行中发现并处理的偏差（相对指南原文）

1. **fork 的 `Rate/Attitude`(ControllerBase) 不可实例化**：只实现 `forward` 未实现抽象 `compute`（已用 `python -c` 验证 `compute in dict: False`），因此 **train.py/play.py 只加了 `velocity` 与 `PIDrate` 两个分支**，没有加 rate/attitude（fork 本就跑不通）。
2. **fork 的 `LeePositionController` 只有 `compute` 没有 `forward`** → 移植的 `VelController(Transform)` 改为调用 `controller.compute(drone_state, target_vel=..., target_yaw=...)`（SimpleFlight 版是直接 `controller(...)`）。
3. **`sim.dt` 不能通过命令行覆盖**：fork 根 `cfg.sim` 是 `${task.sim}` 插值，`sim.dt=0.01` 会报 "Could not override" → 把 `sim: {dt: 0.01, substeps: 1}` 直接写进 `cfg/task/HoverCrazyflie.yaml`。
4. **SimpleFlight 也没有 `lee_controller_crazyflie.yaml`**（它只对 Firefly/Hummingbird 用 velocity）→ 新建，初始复制 hummingbird 增益，注释标明待调。
5. **转子一阶滞后做成"有 `time_constant` 才启用 dt/tau"**：比指南的"无条件加一行"更安全，避免影响 Firefly/Hummingbird 等其它机型（fork 原 0.43/步语义保留）。
6. **新增 `update_sim` 质量同步**（指南未覆盖，实测发现）：fork 原版 sim 用 USD 资产质量 0.027，SimpleFlight 用 yaml 质量 0.0321 并写回 sim；已按 `params.get("update_sim")` 加同步，日志确认 `Mass: 0.0321`。

### A.3 验证结果

| 验证 | 命令 | 结果 |
|---|---|---|
| 控制器前向 | `python -c "...PIDRateController(0.01,9.81,params)..."` | ✅ cmd/ctbr shape (2,1,4)，悬停 cmd≈0 |
| 转子参数 | CPU 构造 `RotorGroup` | ✅ `use_time_constant=True`，tau buffer=0.025 |
| 全链路 PIDrate | `python train.py task=HoverCrazyflie algo=ppo headless=true wandb.mode=disabled max_iters=1` | ✅ 采集/训练/checkpoint 正常，Mass=0.0321 |
| M1 velocity | 同上 + `task.action_transform=velocity` | ✅ 跑通 |
| 稳定性 | `max_iters=40` | ✅ rollout_fps 16–21k；无 NaN/崩溃；stats 正常上报（return/pos_error/episode_len…） |

### A.4 遗留 / 下一步建议

- [x] **短训看 reward 上升**（`total_frames≈5e6`）—— **已完成 2026-09-04**：跑到 4,304,896 帧，收敛良好，见 A.5。
- [x] **回放/评估** —— **已完成 2026-09-04**：fork `play.py` 原本不加载 checkpoint，已补 `checkpoint=` 加载 + 确定性评估；并新增 `scripts/eval_ckpt.py` 一键量化评估（见 A.5）。有头 `headless=false` 目视仍可作为可选人工检查。
- [ ] M1 真训练：把 Hover 目标改为随机点/轨迹（速度指令），调 `lee_controller_crazyflie.yaml` 增益。（**下一步主线**）
- [ ] M4 Track 级复现（SimpleFlight `track.py` 整体移植，作为独立任务 `TrackSF`），见正文 §6 路线 B。
- [ ] 若做 sim2real/零样本，再核对 `cf2x_pybullet.usd` 几何与电机方向/`max_rotation_velocities`（2315）与固件一致。
- [x] git 整理 —— **已完成 2026-09-04**：分 2 个 commit（`0cc01fc` pre-migration + `d02ca10` 迁移），后续工具改动 `fd3486e`，见 A.5/A.6。

### A.5 进度更新（2026-09-04，12:25）

**① Git 提交（3 个 commit，工作区已干净）**
```text
fd3486e  feat: checkpoint loading + deterministic eval tools
d02ca10  feat: port SimpleFlight Crazyflie PIDrate/velocity action pipeline   (迁移，12 文件)
0cc01fc  chore: local Isaac Sim 5.1 fork fixes (WIP before migration)          (迁移前本地改动)
688774c  origin/isaacsim-5.1-blackwell  (上游)
```
- 仓库级身份：`pink-L <lz1470229071@gmail.com>`（`git config user.name/email`，仅本仓库）。
- 尚未 push 到任何远程。

**② 5M 帧短训 + 量化评估（M4/PIDrate 悬停收敛确认）**
- 训练：`python train.py task=HoverCrazyflie algo=ppo headless=true wandb.mode=disabled total_frames=5_000_000 save_interval=50`
- 评估：`scripts/eval_ckpt.py`（新增工具，headless 确定性 rollout 400 步）对 `checkpoint_4304896.pt` 的结果：

| 指标 | 值 | 含义 |
|---|---|---|
| 距目标 `\|rpos\|` | 均值 0.109 m；97/128 (76%) < 0.1 m | 悬停到位 |
| xy 漂移 | 均值 0.086 m / max 2.24 m | 少数 outlier 仍有漂移 |
| `uprightness` | 0.998 | 机身水平 |
| `heading_alignment` | 0.991 | 航向对齐 |
| `return` | ≈795（早期 ~23） | 明显收敛 |
| `episode_len` | 392/400（个别 ~39） | 大多撑满 |

> 结论：**PIDrate/CTBR 管线已能学会稳定悬停** → M4 的底层能力达成。
> 注意：`EpisodeStats` 只统计"真终止(坠机/飞出)"的 episode；学好后多为 500 帧截断，故 train.py 不再打印 `train/stats` —— 属正常，用 `eval_ckpt.py` 看指标即可。

**③ 工具补充（已在 fd3486e）**
- `scripts/play.py`：补 `+checkpoint=...` 加载 + 确定性评估（原 fork 无此功能）；用法：
  ```bash
  python play.py task=HoverCrazyflie algo=ppo headless=true wandb.mode=disabled \
      +checkpoint=/path/to/checkpoint_XXXX.pt total_frames=200000
  ```
- `scripts/eval_ckpt.py`：一键数值评估：
  ```bash
  python -u eval_ckpt.py task=HoverCrazyflie algo=ppo headless=true wandb.mode=disabled \
      +checkpoint=/path/to/checkpoint_XXXX.pt +rollout_steps=400
  ```
  （`-u` 避免重定向文件时 print 缓冲丢失；新增键要用 `+` 前缀，如 `+checkpoint`/`+rollout_steps`。）

**④ 下一步（待做）**
1. **M1（推荐）**：新建/改造一个"随机目标点"任务，`action_transform=velocity` 训练"飞向随机目标"，为 CBF1 滤波打基础（研究主线）。
2. 或续训打磨 outlier：`total_frames=15_000_000`。
3. 或 M4 Track（`TrackSF` 整体移植）。

### A.6 Git 常用操作速查（供以后自查）

> 在 `drones/OmniDrones` 下执行；身份已配好（pink-L），无需再配。

```bash
# 看状态/差异
git status                       # 改动概览
git diff                         # 未暂存差异
git diff --stat                  # 差异统计

# 常规提交
git add <文件...>                # 精确暂存（或 git add -A 全部）
git commit -m "message"          # 提交
git log --oneline -10            # 看最近提交

# 若要按"文件归属"分多次提交，先挑拣：
git add path/to/file1.py path/to/file2.py
git commit -m "feat: ..."
git add path/to/file3.py ...
git commit -m "feat: ..."

# 提交后发现错了，撤销（本地安全）
git reset --soft HEAD~1          # 撤掉最近一次 commit，改动回到暂存区
git reset --hard HEAD~1          # 撤掉并丢弃改动（慎用）
git commit --amend               # 修改最近一次 commit 的 message

# 推送/拉取
git remote add mine <你的仓库URL>   # 指向你自己的 GitHub 空仓库
git push -u mine feat/crazyflie-pidrate   # 首次推送并绑定上游
git push                         # 之后直接推
git pull --rebase                # 拉取并变基（保持历史线性）

# 新键/字段必须用 + 前缀（Hydra），例如 +checkpoint=... / +rollout_steps=400
```

> 提示：本分支基于上游 `isaacsim-5.1-blackwell`，若之后想合回上游改动：
> ```bash
# git fetch origin && git rebase origin/isaacsim-5.1-blackwell
# ```
