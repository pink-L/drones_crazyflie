你现在需要对当前工作区中的 **OmniDrones 无人机强化学习项目**进行一次系统性的代码阅读、架构梳理和接口分析。

当前本地项目结构约定为：

```text
drones/
├── .agent/
├── OmniDrones/          # 本次重点分析对象
├── ...
```

其中：

```text
drones/OmniDrones
```

是本任务真正需要分析的代码项目。

你的任务不是修改功能，而是首先彻底理解这个项目，并生成一套专门供后续 **Codex / AI Agent 进行功能开发、Bug 修复和代码重构** 使用的项目知识文档。

---

# 0. 最重要的目标

最终文档必须能够让一个之前完全没有阅读过 OmniDrones 源码的 AI Agent，在阅读文档后快速回答以下问题：

1. OmniDrones 是如何启动的？
2. `scripts/train.py` 的完整调用链是什么？
3. Hydra 配置如何最终创建 Task、Drone 和 Algorithm？
4. 一个 RL Environment / Task 是如何被创建和注册的？
5. `IsaacEnv` 在整个项目中扮演什么角色？
6. 一个 simulation step 从 action 输入到 physics simulation 再到 observation/reward 输出经历了什么？
7. Drone 对象是如何创建的？
8. Crazyflie 在哪里定义？
9. Crazyflie 与其他 multirotor 共用了哪些逻辑？
10. `MultirotorBase` 的职责是什么？
11. action 最终如何变成 rotor / actuator command？
12. rotor dynamics / actuator dynamics 在哪里实现？
13. observation、action、reward、done 分别在哪里产生？
14. TorchRL / TensorDict 在整个数据流中的作用是什么？
15. PPO 等算法如何与 environment 连接？
16. 修改 reward 应该改哪里？
17. 修改 observation 应该改哪里？
18. 修改 action space 应该改哪里？
19. 修改 Crazyflie dynamics 应该改哪里？
20. 新增 Task 应该按照什么已有模式？
21. 新增 Drone model 应该按照什么已有模式？
22. 修改核心接口后需要检查哪些 callers？
23. 项目当前针对 Isaac Sim / IsaacLab / TorchRL 的兼容代码在哪里？
24. 哪些部分属于原始 OmniDrones 架构，哪些属于当前 fork 的适配或扩展？
25. 后续 AI Agent 实现新功能时最容易误改哪些地方？

最终目标不是“介绍项目”，而是建立一个：

> **可以直接指导 AI Agent 修改代码的工程地图。**

---

# 1. 工作范围

重点分析：

```text
drones/OmniDrones/
```

优先分析以下目录：

```text
OmniDrones/
├── scripts/
├── cfg/
├── examples/
└── omni_drones/
    ├── envs/
    ├── robots/
    ├── actuators/
    ├── controllers/
    ├── learning/
    ├── sensors/
    ├── views/
    └── utils/
```

尤其重点分析：

```text
omni_drones/envs/
omni_drones/robots/
omni_drones/robots/drone/
omni_drones/actuators/
omni_drones/controllers/
omni_drones/learning/
omni_drones/utils/torchrl/
scripts/
cfg/
```

不要花大量时间分析：

* figures
* 图片
* 无关实验输出
* checkpoint
* wandb log
* build cache
* Python cache
* 大型生成文件

除非这些内容直接影响项目运行。

---

# 2. 分析原则

## 2.1 代码优先

信息可信度优先级：

```text
真实运行代码
>
配置文件
>
测试 / example
>
README / docs
>
注释
>
文件名推断
```

如果 README 和源码存在冲突：

以源码为准。

并在文档中指出：

```text
README 描述：
...

实际代码：
...
```

---

## 2.2 不允许只根据名字猜测

例如：

看到：

```python
_apply_action()
```

不能仅根据函数名判断它“应用 action”。

必须继续查看：

* action 的类型
* action 的 shape
* 是否 clamp
* 是否 normalize
* 是否转换为 rotor command
* 是否经过 controller
* 是否更新 TensorDict
* 是否调用 actuator
* 是否调用 Isaac Sim API

然后再描述。

---

## 2.3 每个重要结论必须尽量关联到源码位置

使用：

```text
relative/path/file.py::ClassName.method_name()
```

例如：

```text
omni_drones/envs/isaac_env.py::IsaacEnv
omni_drones/robots/drone/multirotor.py::MultirotorBase.apply_action()
scripts/train.py::main()
```

如果实际路径不同，请使用真实路径。

禁止为了符合示例而虚构路径。

---

# 3. 第一阶段：建立 Repository Map

首先不要急着写最终文档。

先扫描：

```text
OmniDrones/
```

生成内部的 repository map。

重点识别：

### 启动入口

搜索：

```text
if __name__ == "__main__"
@hydra.main
main()
init_simulation_app
SimulationApp
train
play
evaluate
demo
```

重点查看：

```text
scripts/train.py
scripts/play.py
scripts/train_lidar.py
examples/
```

以及其他真实存在的入口。

---

# 4. 第二阶段：彻底追踪训练入口

重点分析：

```text
scripts/train.py
```

不要只解释 `main()`。

从命令：

```bash
python scripts/train.py task=Hover algo=ppo headless=true ...
```

开始向下追踪。

最终需要得到类似：

```text
CLI
 ↓
Hydra
 ↓
root config
 ↓
task config
 ↓
algorithm config
 ↓
SimulationApp
 ↓
Environment class lookup
 ↓
Task construction
 ↓
Drone construction
 ↓
TorchRL transforms / collector
 ↓
RL algorithm
 ↓
training loop
 ↓
environment.step()
```

这只是示意。

必须根据真实代码重新建立调用链。

至少追踪到：

```text
train.py
→ environment creation
→ task class
→ drone creation
→ algorithm creation
→ collector / rollout
→ env.step
```

并记录每一步：

* 文件
* 类
* 函数
* 输入
* 输出
* 配置来源

---

# 5. 第三阶段：分析 Hydra 配置系统

完整扫描：

```text
cfg/
```

重点回答：

```text
根配置是什么？
task config 在哪里？
algorithm config 在哪里？
drone config 在哪里？
sim config 在哪里？
controller config 在哪里？
```

追踪真实配置组合关系。

生成类似：

```text
train.yaml
    │
    ├── task: Hover
    │      ↓
    │   cfg/task/Hover.yaml
    │
    ├── algo: ppo
    │      ↓
    │   cfg/algo/ppo.yaml
    │
    └── sim
```

实际路径以源码为准。

尤其追踪：

```text
cfg.task
cfg.algo
cfg.sim
cfg.headless
cfg.device
```

最终分别被谁读取。

不要只解释 YAML。

必须回答：

> 一个 YAML 参数最终在哪一行 Python 代码中产生实际效果？

---

# 6. 第四阶段：Environment / Task 架构

这是本项目最重要的分析对象之一。

完整分析：

```text
omni_drones/envs/
```

重点找到：

```text
IsaacEnv
```

以及所有重要基类。

回答：

### IsaacEnv

* 定义在哪里？
* 父类是什么？
* TorchRL EnvBase 是否参与？
* 初始化顺序是什么？
* scene 在哪里创建？
* simulation context 在哪里创建？
* observation spec 在哪里创建？
* action spec 在哪里创建？
* reward spec 在哪里创建？
* reset 如何执行？
* step 如何执行？
* env 数量如何管理？
* vectorized environment 如何实现？
* device 如何管理？

重点追踪生命周期：

```text
__init__
 ↓
design_scene / setup
 ↓
set_specs
 ↓
reset
 ↓
pre_sim_step
 ↓
physics step
 ↓
compute_state
 ↓
compute_observation
 ↓
compute_reward
 ↓
compute_done
```

函数名称以真实代码为准。

不要为了匹配这个示意强行套用。

---

# 7. Task 注册和创建机制

找到所有：

```text
Hover
Track
FlyThrough
Forest
Pinball
Formation
Transport
Payload...
```

等 Task 的注册或 import 机制。

重点回答：

```text
task=Hover
```

到底怎样从字符串变成：

```python
Hover(...)
```

分析是否存在：

```text
registry
dict
getattr
hydra instantiate
import mapping
class mapping
factory
```

生成完整链路：

```text
Hydra task=Hover
        ↓
???
        ↓
Hover class
        ↓
IsaacEnv
```

---

# 8. 选取代表 Task 做深入分析

不要逐个分析所有 Task。

选择至少：

```text
一个简单单无人机 Task
一个相对复杂 Task
一个多无人机 / multi-agent Task
```

优先考虑：

```text
Hover
Forest / FlyThrough / Track
Formation / Transport
```

以真实代码情况决定。

对于每个代表 Task 分析：

```text
初始化
scene creation
drone creation
observation
reward
termination
reset
action processing
```

然后总结：

> 新 Task 通常需要实现哪些接口？

---

# 9. Crazyflie 专项分析

这是本项目必须单独存在的一章。

搜索所有：

```text
Crazyflie
crazyflie
CF2
cf2
```

相关代码和配置。

回答：

1. Crazyflie 类定义在哪里？
2. 是否继承 `MultirotorBase`？
3. Crazyflie 与 Hummingbird 等其他 drone model 的差异是什么？
4. Crazyflie 使用什么 USD / asset？
5. Crazyflie 参数从哪里加载？
6. mass / inertia / rotor geometry 在哪里定义？
7. rotor 数量如何确定？
8. rotor position / direction 如何定义？
9. thrust 参数在哪里？
10. torque 参数在哪里？
11. motor time constant / actuator dynamics 在哪里？
12. action range 是什么？
13. `apply_action()` 实际走哪个实现？
14. controller 和 Crazyflie 如何连接？
15. reset 时 Crazyflie 哪些状态被恢复？
16. batched drones 如何表示？
17. tensor shape 是什么？

生成：

```text
Crazyflie
     ↓ inherits
MultirotorBase
     ↓
Rotor / Actuator
     ↓
Isaac Sim articulation / rigid body
```

实际结构以源码为准。

---

# 10. MultirotorBase 专项分析

深入分析：

```text
MultirotorBase
```

这很可能是后续无人机开发最重要的类之一。

记录：

### 构造阶段

* 参数来源
* asset 来源
* rotor 初始化
* articulation 初始化

### 状态

找到类似：

```text
position
rotation
velocity
angular velocity
heading
up
rotor state
throttle
```

具体以代码为准。

### Action

彻底追踪：

```text
action
 ↓
MultirotorBase.apply_action()
 ↓
...
 ↓
rotor command
 ↓
thrust
 ↓
moment
 ↓
Isaac Sim force / torque
```

必须确认真实实现。

---

# 11. Actuator / Rotor Dynamics 专项分析

深入查看：

```text
omni_drones/actuators/
```

重点回答：

```text
RL action
```

如何最终变成：

```text
motor / rotor state
thrust
torque
force
```

分析：

* actuator class
* rotor model
* throttle mapping
* RPM / angular velocity（如果存在）
* force calculation
* moment calculation
* first-order dynamics（如果存在）
* time constants
* clamp
* normalization

明确公式所在源码位置。

不要自行推导不存在于代码中的动力学。

---

# 12. Controller 架构

分析：

```text
omni_drones/controllers/
```

重点找到：

```text
LeePositionController
attitude controller
rate controller
PID
```

等实际存在的 controller。

说明：

```text
target
 ↓
controller
 ↓
command
 ↓
MultirotorBase
 ↓
rotor / actuator
```

对于核心 Controller 记录：

* input
* output
* tensor shape
* units
* caller
* callee

重点区分：

```text
RL policy directly outputs motor action
```

和：

```text
RL / command → controller → motor action
```

这两类路径。

---

# 13. Observation 专项分析

这是后续修改 RL 输入时最重要的部分。

对于代表性 Task：

完整追踪：

```text
simulator state
 ↓
drone state
 ↓
relative state / target state
 ↓
observation construction
 ↓
TensorDict
 ↓
policy
```

记录：

```text
observation key
shape
含义
来源
```

例如实际代码若存在：

```text
agents.observation
agents.state
stats
info
```

需要解释层级结构。

不要猜测 key。

---

# 14. Action 专项分析

完整追踪：

```text
Policy
 ↓
TensorDict action
 ↓
Environment
 ↓
Task
 ↓
Drone.apply_action()
 ↓
Actuator
 ↓
Physics
```

记录：

```text
TensorDict key
shape
range
normalization
physical meaning
```

尤其回答：

> Policy 输出的 `[-1, 1]`（如果确实如此）最后代表什么物理量？

如果并不是 `[-1,1]`，不要写成该范围。

---

# 15. Reward 专项分析

分析代表 Task。

建立：

```text
reward component
weight
formula
source state
final aggregation
```

对于 Hover 等代表 Task，生成类似：

| Reward term | 源码位置 | 输入状态 | 含义 |
| ----------- | ---- | ---- | -- |

重点指出：

修改 reward 时需要同步检查：

```text
stats
logging
termination
normalization
multi-agent aggregation
```

等实际相关代码。

---

# 16. Done / Termination / Reset

追踪：

```text
terminated
truncated
done
reset
```

实际实现。

回答：

```text
episode 什么时候结束？
timeout 在哪里判断？
crash 在哪里判断？
距离限制在哪里判断？
reset_idx 如何得到？
```

然后追踪：

```text
done
 ↓
reset
 ↓
drone state reset
 ↓
task state reset
 ↓
new observation
```

---

# 17. TensorDict / TorchRL 专项分析

当前 OmniDrones 使用 TorchRL/TensorDict，因此必须单独建立说明。

搜索：

```text
TensorDict
CompositeSpec
TensorSpec
EnvBase
TransformedEnv
Collector
SyncDataCollector
ReplayBuffer
```

等实际使用对象。

重点回答：

### TensorDict hierarchy

生成真实的数据结构，例如：

```text
TensorDict
├── agents
│   ├── observation
│   ├── action
│   └── reward
├── done
├── terminated
├── truncated
└── stats
```

以上只是示例。

必须依据实际代码生成。

对于每个核心 key：

```text
key
shape
dtype
producer
consumer
```

---

# 18. TorchRL compatibility layer

当前 fork 很可能包含：

```text
omni_drones/utils/torchrl/
```

以及类似：

```text
tensordict_compat.py
```

的兼容逻辑。

必须分析：

1. 为什么存在 compatibility layer？
2. 替代了哪些旧 API？
3. 哪些代码是为了较新 TorchRL/TensorDict 版本新增的？
4. 哪些接口属于兼容 shim？
5. 后续开发时哪些地方不能轻易删除？
6. 哪些旧 OmniDrones 代码依赖这些 shim？

将其单独标记：

```text
Compatibility-sensitive code
```

---

# 19. Learning / RL Algorithm 架构

分析：

```text
omni_drones/learning/
```

不要把所有算法逐行分析。

重点分析：

```text
PPO
```

因为它可以代表训练主流程。

再快速说明：

```text
SAC
TD3
MAPPO
MATD3
QMIX
DQN
```

等存在的算法如何共享抽象。

对于 PPO 重点追踪：

```text
observation
 ↓
actor
 ↓
action
 ↓
environment
 ↓
rollout
 ↓
advantage
 ↓
loss
 ↓
optimizer
```

说明：

```text
policy class
critic class
network builder
loss
optimizer
collector
```

分别在哪里。

---

# 20. Training Loop 专项分析

从：

```text
scripts/train.py
```

继续分析真正训练 loop。

回答：

```text
谁驱动 environment.step()？
谁收集 rollout？
谁计算 loss？
谁 update network？
什么时候 evaluate？
什么时候 save checkpoint？
什么时候写 wandb？
```

建立完整流程：

```text
Config
 ↓
Environment
 ↓
Agent / Policy
 ↓
Collector
 ↓
Rollout
 ↓
Training batch
 ↓
Loss
 ↓
Optimizer
 ↓
Checkpoint / Logging
```

---

# 21. Isaac Sim / IsaacLab 集成

当前项目不是纯 Python RL 项目。

必须分析：

```text
Isaac Sim
IsaacLab
Omniverse
```

的边界。

回答：

1. SimulationApp 在哪里初始化？
2. SimulationContext 在哪里创建？
3. stage / prim 在哪里创建？
4. drone USD 在哪里 spawn？
5. physics step 在哪里执行？
6. articulation view / rigid prim view 在哪里使用？
7. scene reset 如何执行？
8. GPU simulation 如何配置？
9. headless 如何生效？

---

# 22. Isaac Sim 5.1 / IsaacLab 2.x 兼容代码

当前 fork 存在针对较新 Isaac Sim / IsaacLab 的适配。

重点搜索：

```text
omni.isaac
isaaclab
isaacsim
compat
deprecated
view
ArticulationView
RigidPrimView
```

以及明显的 fallback / try-import。

建立一节：

```text
Version Compatibility Notes
```

分为：

```text
原始 OmniDrones 行为
当前 fork 修改
修改原因
受影响模块
未来升级风险
```

仅根据 git/code 能确认的内容编写。

---

# 23. Sensors

分析：

```text
omni_drones/sensors/
```

重点关注：

```text
LiDAR
Camera
Contact Sensor
```

等真实存在模块。

尤其分析：

```text
train_lidar.py
Forest
```

如果存在关联。

说明 Sensor 数据如何进入 observation。

---

# 24. Multi-Agent 架构

选择一个真实 multi-agent Task，例如：

```text
Formation
Transport
```

分析：

```text
num_agents
agent dimension
TensorDict
observation
state
action
reward
done
```

明确 single-agent 和 multi-agent 的数据 shape 差异。

例如需要确认：

```text
[num_envs, num_agents, obs_dim]
```

是否真实成立。

不能直接假设。

---

# 25. Shape Ledger

这是本任务非常重要的输出。

建立：

# Tensor Shape Ledger

记录至少：

```text
drone position
drone quaternion
linear velocity
angular velocity
action
throttle
rotor state
observation
reward
done
```

以及代表 Task 的核心 tensor。

格式：

| Tensor | Shape | Producer | Consumer | Meaning |
| ------ | ----- | -------- | -------- | ------- |

如果 shape 中存在：

```text
N
M
D
```

必须定义：

```text
N = num_envs
M = num_agents / num_drones
D = feature dimension
```

---

# 26. Units Ledger

对于机器人项目，必须尽量记录单位。

建立：

# Units Ledger

例如：

| Quantity         | Unit  | Code location |
| ---------------- | ----- | ------------- |
| position         | m     | ...           |
| velocity         | m/s   | ...           |
| angular velocity | rad/s | ...           |
| thrust           | N     | ...           |

仅记录源码能够确认的内容。

不确定则明确写：

```text
Unit not explicitly documented in code.
```

---

# 27. Public / Internal Interface 分类

识别后续开发应该依赖哪些接口。

分成：

## Stable-ish Interfaces

例如可能包括：

```text
IsaacEnv
MultirotorBase
Task lifecycle hooks
controller interface
```

但必须通过实际代码判断。

## Internal Interfaces

例如：

```text
private helper
compat shim
temporary view wrapper
```

如果项目没有正式声明 API stability：

明确注明：

```text
The project does not explicitly declare API stability.
The following classification is inferred from usage patterns.
```

---

# 28. 必须建立核心 Interface Reference

为以下真实存在的重要接口建立接口卡片。

至少覆盖：

```text
IsaacEnv.__init__()
IsaacEnv.reset()
IsaacEnv.step() 或实际对应接口
Task observation function
Task reward function
Task reset function
MultirotorBase.apply_action()
MultirotorBase.get_state()
Drone reset function
Actuator / Rotor forward
Controller.compute()
PPO action/update interface
```

实际函数名以代码为准。

每个接口统一记录：

## `Class.method()`

定义：

```text
path/file.py
```

签名：

```python
def method(...):
```

### Responsibility

### Called by

```text
caller A
caller B
```

### Calls

```text
callee A
callee B
```

### Input

| Parameter | Type | Shape | Unit | Description |
| --------- | ---- | ----- | ---- | ----------- |

### Output

| Type | Shape | Unit | Description |
| ---- | ----- | ---- | ----------- |

### Side Effects

例如：

```text
修改 drone state
写入 simulator
修改 buffer
修改 TensorDict
```

### Lifecycle

例如：

```text
每 physics step 调用一次
```

### Modification Risk

例如：

```text
修改 action shape 会影响：
- task specs
- actor output
- collector
- apply_action
```

---

# 29. Call Graph

至少建立以下调用图。

## Training Call Graph

```text
train.py
→ ...
```

## Environment Step Call Graph

```text
policy
→ action
→ env
→ drone
→ simulator
→ observation/reward
```

## Reset Call Graph

```text
done
→ reset
→ task
→ drone
→ simulator
```

## Crazyflie Action Call Graph

```text
policy/controller
→ Crazyflie / MultirotorBase
→ rotor
→ force
→ simulator
```

## Observation Call Graph

```text
sim state
→ drone state
→ task obs
→ TensorDict
→ policy
```

---

# 30. Dependency Graph

生成模块级依赖：

```text
scripts
   ↓
cfg
   ↓
envs
   ├────→ robots
   │        ↓
   │     actuators
   │
   ├────→ sensors
   │
   └────→ controllers

learning
   ↓
TorchRL
   ↓
envs
```

实际依赖以源码为准。

特别指出：

```text
high fan-in module
high fan-out module
```

即：

> 哪些文件一改，很可能影响整个项目。

---

# 31. 新 Task 开发指南

根据项目现有 Task，总结真正的新 Task 开发步骤。

例如最终形成：

```text
1. 新建 Task class
2. 继承 XXX
3. 实现 XXX
4. 定义 observation spec
5. 定义 action spec
6. 实现 reward
7. 实现 reset
8. 注册 Task
9. 添加 Hydra config
10. 添加训练命令
```

但步骤必须来自真实代码。

同时给出：

```text
推荐参考 Task：
Hover
```

说明为什么它适合作为模板。

---

# 32. 新 Drone Model 开发指南

尤其结合 Crazyflie / Hummingbird。

回答：

```text
一个普通 quadrotor 最少需要什么？
```

例如：

```text
USD
parameter yaml
MultirotorBase subclass
rotor config
```

以真实项目结构为准。

说明：

```text
什么时候只需要 subclass？
什么时候需要 override apply_action？
什么时候需要自定义 actuator？
```

---

# 33. 修改 Crazyflie Dynamics 指南

单独建立：

# Modifying Crazyflie Dynamics

按类别告诉后续 Agent：

### 修改 mass / inertia

去哪里？

### 修改 motor dynamics

去哪里？

### 修改 thrust coefficient

去哪里？

### 修改 rotor geometry

去哪里？

### 修改 control rate

去哪里？

### 修改 action mapping

去哪里？

### 修改 controller

去哪里？

并说明每种修改可能影响：

```text
Task
policy checkpoint
observation
action spec
reward
controller
simulation stability
```

---

# 34. 修改 Observation 指南

生成：

```text
如果要给 policy 增加一个新的 observation：
```

具体需要检查：

```text
Task observation construction
observation spec
TensorDict
actor input dimension
normalization
checkpoint compatibility
multi-agent shape
```

并引用真实文件。

---

# 35. 修改 Action 指南

生成：

```text
如果要修改 policy action：
```

需要检查：

```text
action spec
actor output
TensorDict
Task
MultirotorBase.apply_action()
actuator
controller
checkpoint
```

并给出真实调用链。

---

# 36. 修改 Reward 指南

生成：

```text
如果要增加 reward term：
```

说明：

```text
修改位置
依赖 state
stats logging
weight config
termination interaction
```

以真实代码为准。

---

# 37. 调试导航

建立：

# Debugging Guide

如果出现：

```text
shape mismatch
```

优先查看哪里？

如果：

```text
drone 不产生 thrust
```

优先查看哪里？

如果：

```text
env reset 异常
```

查看哪里？

如果：

```text
policy 输出正常但 drone 不动
```

检查链：

```text
policy
→ action TensorDict
→ apply_action
→ actuator
→ force
→ articulation
```

如果：

```text
reward 不变化
```

检查哪里？

如果：

```text
Hydra 找不到 Task
```

检查哪里？

如果：

```text
Isaac Sim API 报错
```

哪些 compatibility layer 需要先检查？

---

# 38. AI Agent 修改代码时的规则

最终文档必须包含：

# AI Agent Development Rules

以后 AI Agent 修改 OmniDrones 代码时：

## 修改前必须

1. 阅读本项目总结
2. 定位目标模块
3. 搜索目标 symbol
4. 搜索全部 callers
5. 搜索全部 subclasses
6. 搜索 Hydra config
7. 搜索 TensorDict key
8. 检查 tensor shape
9. 检查 unit
10. 检查 compatibility layer
11. 检查 tests/examples

## 修改时

优先：

```text
复用现有 abstraction
保持 TensorDict schema
保持 vectorized environment
保持 device 一致
保持 dtype 一致
保持 batch dimension
保持 Hydra 配置兼容
```

## 不允许

不要：

```text
看到函数名就猜实现
仅修改 Tensor shape 的一端
绕过已有 MultirotorBase abstraction
重复实现已有 controller / actuator
无关重构
大范围 rename
无意义格式化
随意删除 compatibility shim
在不知道 caller 的情况下修改核心 API
```

---

# 39. 输出文件

最终生成两个文档。

## 文件一

```text
PROJECT_SUMMARY.md
```

重点回答：

```text
项目整体架构
目录
入口
配置
执行流程
模块职责
数据流
开发导航
```

## 文件二

```text
INTERFACE_REFERENCE.md
```

重点回答：

```text
核心类
关键函数
接口签名
caller
callee
input
output
shape
unit
side effects
lifecycle
modification risk
```

如果当前项目已经存在：

```text
PROJECT_SUMMARY.md
project_summary.md
```

不要直接覆盖已有文档。

先阅读已有文档。

如果旧文档内容仍然有价值，则保留，并创建：

```text
OMNIDRONES_PROJECT_SUMMARY.md
OMNIDRONES_INTERFACE_REFERENCE.md
```

如果确定用户希望更新现有文档，再进行覆盖。

本任务中默认：

> 不修改任何业务源码。

---

# 40. 文档的推荐结构

`OMNIDRONES_PROJECT_SUMMARY.md`：

```markdown
# OmniDrones Project Summary

## 1. Project Overview
## 2. Tech Stack
## 3. Repository Structure
## 4. Important Files
## 5. Entry Points
## 6. Training Entry Flow
## 7. High-Level Architecture
## 8. Hydra Configuration System
## 9. Environment Architecture
## 10. Task Architecture
## 11. Task Registry
## 12. Drone Architecture
## 13. Crazyflie
## 14. MultirotorBase
## 15. Actuator / Rotor Dynamics
## 16. Controllers
## 17. Observation Pipeline
## 18. Action Pipeline
## 19. Reward Pipeline
## 20. Reset / Done Lifecycle
## 21. TensorDict Schema
## 22. TorchRL Integration
## 23. Learning Algorithms
## 24. PPO Training Flow
## 25. Isaac Sim Integration
## 26. IsaacLab Integration
## 27. Version Compatibility Layer
## 28. Sensors
## 29. Multi-Agent Architecture
## 30. Tensor Shape Ledger
## 31. Units Ledger
## 32. Dependency Graph
## 33. Extension Points
## 34. Add a New Task
## 35. Add a New Drone
## 36. Modify Crazyflie Dynamics
## 37. Modify Observation
## 38. Modify Action
## 39. Modify Reward
## 40. Debugging Guide
## 41. Known Risks / Technical Debt
## 42. AI Agent Development Rules
## 43. Open Questions
```

`OMNIDRONES_INTERFACE_REFERENCE.md`：

```markdown
# OmniDrones Interface Reference

## 1. Environment Interfaces
## 2. Task Interfaces
## 3. Drone Interfaces
## 4. Crazyflie Interfaces
## 5. Multirotor Interfaces
## 6. Actuator Interfaces
## 7. Controller Interfaces
## 8. Sensor Interfaces
## 9. TorchRL Interfaces
## 10. TensorDict Schema
## 11. Algorithm Interfaces
## 12. Configuration Interfaces
## 13. Simulator Interfaces
## 14. Call Graphs
## 15. Interface Dependency Matrix
```

---

# 41. Interface Dependency Matrix

额外创建一个非常重要的表格：

| Interface | Called By | Calls | Input Shape | Output Shape | Risk   |
| --------- | --------- | ----- | ----------- | ------------ | ------ |
| `...`     | `...`     | `...` | `...`       | `...`        | High   |
| `...`     | `...`     | `...` | `...`       | `...`        | Medium |

Risk 的定义：

```text
High:
修改后很可能影响训练/仿真主链路

Medium:
影响单个 subsystem

Low:
局部 helper
```

---

# 42. “Where Should I Modify?” 快速索引

在 `PROJECT_SUMMARY` 前部增加：

# Development Quick Index

格式：

| 需求                    | 首先查看 | 然后查看 |
| --------------------- | ---- | ---- |
| 修改 Crazyflie          | ...  | ...  |
| 修改电机模型                | ...  | ...  |
| 修改 thrust             | ...  | ...  |
| 修改 observation        | ...  | ...  |
| 修改 action             | ...  | ...  |
| 修改 reward             | ...  | ...  |
| 修改 termination        | ...  | ...  |
| 新增 Task               | ...  | ...  |
| 新增 Drone              | ...  | ...  |
| 修改 PPO                | ...  | ...  |
| 修改 Controller         | ...  | ...  |
| 修改 LiDAR              | ...  | ...  |
| 修改 simulator timestep | ...  | ...  |
| 调试 TensorDict         | ...  | ...  |

该表必须引用真实代码路径。

这是以后 AI Agent 最常使用的索引。

---

# 43. 不确定性处理

如果遇到无法确认的逻辑：

不要猜。

使用：

```markdown
### Unconfirmed

**Question**

...

**Observed evidence**

- `file.py::method()`
- `config.yaml`

**Likely explanation**

...

**Need to inspect**

...
```

---

# 44. Git History 的使用

如果当前仓库可访问 git history，可以对下列高风险代码适当使用：

```bash
git log
git blame
git diff
```

尤其是：

```text
TorchRL compatibility
TensorDict compatibility
Isaac Sim 5.1 compatibility
IsaacLab compatibility
Crazyflie modifications
```

目的是判断：

```text
这段代码是原始架构，
还是当前 fork 为兼容新版本新增的修改。
```

不要为了补充文档而分析所有 commit。

---

# 45. 最终自检

完成后必须验证以下问题是否都能仅靠文档回答：

### Architecture

* 主入口在哪里？
* 环境怎么创建？
* Task 怎么选择？
* Drone 怎么创建？
* Algorithm 怎么创建？

### RL

* observation 从哪里来？
* action 去哪里？
* reward 在哪里算？
* done 在哪里算？
* rollout 谁负责？

### Drone

* Crazyflie 在哪里？
* MultirotorBase 在哪里？
* rotor model 在哪里？
* actuator 在哪里？
* thrust 在哪里产生？

### Data

* observation shape 是什么？
* action shape 是什么？
* TensorDict schema 是什么？
* single-agent 和 multi-agent 区别是什么？

### Development

* 新增 Task 改哪里？
* 修改 Crazyflie 改哪里？
* 修改 observation 改哪里？
* 修改 reward 改哪里？
* 修改 action 改哪里？

### Compatibility

* Isaac Sim 5.1 compatibility 在哪里？
* IsaacLab compatibility 在哪里？
* TorchRL compatibility 在哪里？
* TensorDict compatibility 在哪里？

如果有任何问题文档无法回答：

继续阅读源码并补充。

---

# 46. 执行方式

现在直接执行。

不要先向我询问 OmniDrones 的架构。

不要假定 README 完全正确。

不要只阅读 README。

首先：

```text
1. 扫描 drones/OmniDrones
2. 定位训练入口
3. 定位 Hydra 配置
4. 追踪 Task 创建
5. 追踪 Environment lifecycle
6. 追踪 Crazyflie / MultirotorBase
7. 追踪 action → actuator → physics
8. 追踪 physics → state → observation/reward
9. 追踪 TensorDict → PPO
10. 再生成文档
```

在分析过程中可以使用：

```text
rg
grep
find
git grep
git log
git blame
```

等工具辅助定位。

优先使用 symbol / reference 搜索，不要盲目逐文件阅读。

---

# 47. 最终回复格式

完成任务后只需要向我汇报：

```text
Documentation generated:
- ...
- ...

Main entry:
- ...

Core execution chain:
...

Crazyflie chain:
...

Important compatibility layers:
- ...

Unconfirmed issues:
- ...

Business source code modified:
No
```

除文档文件外，不要修改 OmniDrones 业务代码。
