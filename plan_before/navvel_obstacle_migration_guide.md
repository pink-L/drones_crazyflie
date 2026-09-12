# NavVel 静态障碍避障导航：kaiwu 障碍处理思路迁移指导（M2-I）

> 创建时间：2026-09-04
> 前置：M1（`NavVel` 随机目标 + velocity 动作）已完成 P0/P1 骨架（分支 `feat/crazyflie-pidrate`），但 **P2 基线未收敛**（见 `m1_navvel_plan.md` §9 与本文 §1）。
> 参考母版：腾讯 kaiwu 平台 `drone_obstacle_nav`（ObstacleHover/PPO）的障碍处理实现，源文件索引见附录 A；
> 参考总览：`refs/crazyswarm2_kaiwu/ros2_ws/mynotes/KAIWU_TRAINING_MIGRATION_GUIDE.md`。
>
> ⚠️ **本文件是"规划/实施指导"，不是执行记录**。所有命令均为"待执行"，动手前按 §8/§9 逐条执行并回填结果。

---

## 0. TL;DR（先看结论）

- **做什么**：在现有 `NavVel`（Crazyflie + `action_transform=velocity` 速度指令，随机起点/目标）上加入**静态 3D 障碍**，
  用**纯 PPO 端到端学习避障导航**（本期不接 CBF，CBF1 留到收敛后下一阶段做消融基线）。
- **障碍模型**（依据你 2026-09-04 的选择）：**浮空/矮障碍、3D 可上下绕飞（NavRL 风格）**。为与"kaiwu 真值风格观测
  （固定 K 槽位 相对位置+半径+mask）"兼容，v1 把每个障碍**统一建模为"包围球"**：位置 $p_o\in\mathbb R^3$ + 半径 $r_o$，
  物理上 spawn 同尺寸 **kinematic 刚体球**。障碍数量随机但**半径先固定**（可配），避障是 3D 几何判定。
- **观测**：在现有 obs 上**追加 $K=8$ 个固定槽位**：每槽 = 障碍相对位置(3) + 半径(1)，未激活槽填 0（mask）→ obs 维度
  `30 → 62`（含 time_encoding）。固定槽位天然支持"障碍数量可变"与课程学习。**此格式为未来"大飞机机载雷达/视觉相机"感知部署预留接口**（见 §5.4 注记）。
- **奖励**：迁移 kaiwu 三件套——**障碍 log 距离惩罚（3D 版）+ 碰撞边沿事件惩罚 + 早死惩罚**，另加可选的"近障碍减速"；
  全部权重进 yaml，按 NavVel 量级（每步 O(1)）重新标定（kaiwu 是 CTBR+WP 大权重体系，不能照抄数值）。
- **碰撞/终止**：3D 几何球-球判定（带膨胀），**边沿事件累计 ≥ 2 次即 terminated**；坠地/OOB/NaN 沿用 NavVel 空间判据。
- **速度预算**：给 `VelController` 增加 `max_vel` 限幅（建议 1.5–2.0 m/s），防策略输出超大速度导致动量撞障/发散。
- **课程学习**：仓库 PPO 主循环**无 curriculum 基建** → 在 env 内做**自驱动课程调度器**（写回 env 的 stats，train.py/算法零改动）：
  **固定阶段 0 → 2 → 4 → 8 个障碍**，按"滚动窗口成功率门槛"升级。
- **最大前置风险**：M1 基线未收敛 → 课程 **stage 0 = 无障碍收敛修复**，先达成 M1 验收再升级（你已确认此顺序）。

```mermaid
flowchart LR
    subgraph NavVel 每 episode (stage L 个障碍)
      A[采样随机起点+目标] --> B[课程调度器给出 L]
      B --> C[采样 L 个障碍球心+摆位<br/>未激活槽移出场地]
      C --> D[PPO 策略 输出 vx,vy,vz,yaw]
      D --> E[VelController<br/>+max_vel 限幅]
      E --> F[Lee 控制器 → 转子 cmd]
      F --> G[Crazyflie 动力学]
      G --> H{几何碰撞/坠地/OOB/NaN?}
      H -->|无| I{到达且保持?}
      I -->|未到| D
      I -->|到达| J[arrival bonus + stats]
      H -->|碰撞边沿累计≥2| K[terminated]
      J --> L{课程门槛达标?}
      K --> M[reset 下一 episode]
      L -->|是| N[level+1 → 更密障碍]
      L -->|否| M
    end
```

---

## 1. 背景与前置：M1 现状（必须先解决）

### 1.1 M1 做了什么、现状如何

`m1_navvel_plan.md` 记录了 M1 目标与执行状态：

| 项 | M1 设定 | 2026-09-04 实测 |
|---|---|---|
| 任务 | `NavVel`：随机起点/目标 + velocity 动作 | P0/P1 骨架 ✅ |
| 训练 | 20M@512（wandb `fly-hust/RL90` run `nnsyqhs7`） | **❌ 未学会**：`pos_error≈3.3–3.85`、`arrival=0`（0/512 到达）|
| A 组短测 | minibatch4+epochs8，1M 帧（run `5v3zpwtg`） | ❌ 无改善信号（pos_error≈3.97）|
| B/C 组超参短测 | §10 中规划 | 未跑 |

**结论：在"随机目标到达"这个地基尚未学会之前，不能直接叠障碍。** 障碍课程把 stage 0 定义为"0 障碍"，其验收标准 = M1 验收标准。

### 1.2 M1 不收敛的根因假设（stage 0 排查清单，来自 kaiwu 对照）

kaiwu 的导航任务能收敛，而 NavVel 不能，两者差异里最可疑的几点（按可疑度排序）：

1. **死亡惩罚缺失**：NavVel `misbehave`/超时只是"终止"（无显式惩罚，未完成即结束，GAE 里 return≈0），
   而 kaiwu 有 `in_arena`(−150/步)、`timeout`(−80)、**`early_death_penalty`（开局即死按存活步反比重罚）**。
   → 建议 stage 0 就引入 kaiwu 式 **early-death + timeout 一次性惩罚**（见 §6.4），给"乱飞死掉"明确负信号。
2. **到达奖励太弱/太迟**：NavVel `arrive_bonus=5`（一次），且需 `arrive_hold_steps=100`（1s）保持；kaiwu 悬停成功给
   `HOVER_SUCCESS_REWARD=200` 量级。→ 可调大到达/悬停保持奖励或缩短 hold；先 `success_terminate=False` 保持"学停稳"。
3. **距离势场形状**：`reward_pose=1/(1+(k·d)²)` 在 d 大时梯度很小；kaiwu 用 PBRS（`2·(d_{t-1}−γ·d_t)`）近场远场都有线性梯度。
   → 可加一条 kaiwu 式 **PBRS 目标进度项**（γ=0.995），或调 `reward_distance_scale`。
4. **动作语义/限幅**：`VelController` 现在**无速度限幅**，策略输出可能极大速度/抖动；且 action 第 4 维是 `yaw*π`（速度/角速度指令层），
   M1 可能输出了不合理 yaw。→ 本方案直接落 §8.3 的 `max_vel`/`max_yaw_rate` 限幅（对 stage 0 同样有效）。
5. **超参/训练长度**：512 env × 600 步 × ~20M 帧，理论上样本足够；但 PPO 的 `train_every=32`（每 32 步一学）与 obs 归一化、
   reward 量级都值得复查；B/C 组短测未跑。
6. **到达即被 reset 打散统计**：`EpisodeStats` 只统计真终止，随机目标大多 truncated → 看 wandb 的 `arrival` EMA 而非 return。

> **Stage 0 的排查方法**：在 stage 0（0 障碍）把 §6 的终止惩罚 + §8.3 限幅先落上，短训 2–5M 帧观察 `pos_error` EMA 与
> `arrival` 是否出现 >0；若不收敛再按 m1 §10 的 B/C 组对照（LR/minibatch/epochs/网络宽度）逐项试。**验收门槛见 §9 表格 Stage 0。**

---

## 2. 迁移对象提炼：kaiwu 障碍处理五要素 → NavVel 适配表

kaiwu 对障碍物的处理可拆成 5 个可迁移要素（已在会话中总结，此处给"要素 → 本方案落点"的对照表）：

| # | kaiwu 要素 | kaiwu 侧关键事实 | 迁移到 NavVel 的形态 | 差异/注意 |
|---|---|---|---|---|
| E1 | 布局采样 | 全场高圆柱、最多 8、半径档 [0.15…0.40]、交错格点候选池、起终点留 margin | **3D 球**：每 episode 在场地内随机 L 个球心；与起点/目标/互不重叠；半径先固定 | 圆柱(2D)→球(3D)；"能绕飞/能翻越"由球的位置(z)体现；布局采样重写但保留"约束过滤"思想 |
| E2 | 障碍真值观测 | raw obs 固定 K 槽：`obstacle_rpos(8×3,masked)`+`obstacle_radii(8,masked)`；特征层再加工(48 扇区射线等) | 追加 K=8 槽：`(rpos_xyz(3), r(1))`，未激活=0（mask）；v1 不做扇区射线特征 | NavVel 是 MLP+单向量 obs，不在 agent 里做特征层；直接把槽位拼进 obs；射线特征留作可选增强（§5.3） |
| E3 | 障碍奖励 | `obstacle_log_distance`(phi log 惩罚) + `collision_event`(边沿 −10/次,weight250) + 早死惩罚 + 动态限速 | 3D log 距离惩罚 + 碰撞边沿事件 + 早死惩罚（+可选近障减速）；权重重标定 | 公式泛化 2D→3D（距离用球面距）；数值重标（NavVel 每步 O(1)） |
| E4 | 碰撞/终止 | 几何判定（2D 表面距<margin）+ 边沿事件计数 + `max_collisions=2` 终止 | 3D 球-球几何判定 + 边沿计数 ≥2 终止；坠地/OOB/NaN 沿用 NavVel | margin/膨胀系数沿用 kaiwu 思路（+0.05 膨胀、0.05 margin） |
| E5 | 阶段机/统计 | nav→hover 状态机、评分、collision_count 等 stats | 复用 NavVel 到达机制；新增 `collision_count/collision_rate/min_clearance` 等 stats 进 wandb | 无 WP/阶段机（NavVel 是单目标直接导航）；课程门槛读这些 stats |

**框架层面的差异（决定"思路迁移"而非"代码搬运"）**：

| 维度 | kaiwu | NavVel(drones) | 影响 |
|---|---|---|---|
| 训练框架 | kaiwu 同步 PPO + 平台 `isaac_env`（缺失）+ kaiwu 接口 env | OmniDrones fork：`IsaacEnv` + torchrl `SyncDataCollector` + 自带 PPO | reward/obs 挂接点完全不同；`reward_process.py` 的"加权求和 compute_reward"在平台缺失包里，本就不可搬，需在 env 内重写 |
| 动作层 | CTBR 转子指令（4 维，tanh→clip） | velocity 速度指令（`[vx,vy,vz,yaw]`→Lee→转子） | 障碍奖励只依赖位置/速度，与动作层解耦；但**速度限幅**必须落到 `VelController` |
| 障碍维度 | 2D（全场高柱，z 只做地/天花板） | 3D（浮空/矮球，需学 z 升降） | 碰撞/奖励/观测公式全部 3D 化（本文已给出） |
| 课程 | 无（每 episode 从 [0,8] 直接随机） | **本期新增**：0→2→4→8 按成功率门槛 | 需自建课程调度器（§7） |
| 场地 | `[0,5]²×[0,3]` 轴对齐方块 + 墙 | 中心对称：`xy` 以 env 原点为中心、`bound_xy=5`（球形 OOB），z∈[0.15,4.5] | 无"墙"概念 → log 距离项只算障碍，不算墙；OOB 单独惩罚 |

> 想了解 kaiwu 奖励/观测公式原始细节与"可抄的纯函数"：见附录 A 源码索引；想了解仓库侧的 OmniDrones fork 结构：
> `README.md`、`how2use.md`、`m1_navvel_plan.md`。

---

## 3. 总体设计（M2-I 数据流与模块划分）

```mermaid
flowchart TD
    subgraph 配置
      Y["cfg/task/NavVel.yaml<br/>障碍/课程/奖励权重/限幅"]
    end
    subgraph env (omni_drones/envs/single/nav_vel.py)
      SC["_design_scene<br/>spawn K 个 kinematic 球(模板 env_0)"]
      RS["_reset_idx<br/>课程 level→采样 L 个球心<br/>激活/移出槽位 set_world_poses"]
      OB["_compute_state_and_obs<br/>拼目标rpos+自身+K槽障碍obs"]
      RW["_compute_reward_and_done<br/>奖励+几何碰撞+边沿计数+终止+stats"]
      CU["课程调度器<br/>滚动成功率窗口→level±1"]
    end
    subgraph 动作管线 (scripts/train.py + transforms.py)
      PO["PPOPolicy 输出 v∈R4"]
      VC["VelController<br/>限幅 max_vel/max_yaw_rate<br/>→ LeePositionController"]
    end
    Y --> SC; Y --> RS; Y --> RW
    OB --> PO --> VC --> RS
    RW --> CU --> RS
    RW --> S["stats → wandb/eval_ckpt"]
```

**新增/改动文件一览**（详细步骤见 §8）：

| 文件 | 动作 |
|---|---|
| `omni_drones/envs/single/nav_vel.py` | 主改造：障碍 spawn/采样/obs/奖励/碰撞/终止/课程（可抽 `omni_drones/envs/single/nav_vel_obstacles.py` 模块保持 nav_vel 整洁，见 §8.1 取舍）|
| `cfg/task/NavVel.yaml` | 新增 `obstacle:`、`curriculum:`、`reward_obstacle_*:`、`vel_limit:` 段 |
| `omni_drones/utils/torchrl/transforms.py` | `VelController` 增加 `max_vel`/`max_yaw_rate` 限幅（默认不动行为）|
| `scripts/train.py` / `scripts/play.py` | 实例化 `VelController` 时传限幅参数 |
| （可选）`omni_drones/utils/nav_curriculum.py` | 课程调度器独立成纯逻辑模块，便于单测/将来复用 |
| （可选，M2 预留不实现）`omni_drones/utils/cbf.py` | 见 §12.1 |

---

## 4. 障碍物几何与布局采样（E1，3D 球模型）

### 4.1 障碍模型约定（v1 简化 + 依据）

- **统一为"包围球"**：每个障碍用球心 $p_o=(x_o,y_o,z_o)$ 与半径 $r_o$ 描述。物理上 spawn **同尺寸 kinematic 刚体球**（USD `Sphere` + `RigidBodyAPI` + `CollisionAPI` + `kinematicEnabled=True`，即仓库 `omni_drones/envs/utils/__init__.py::create_obstacle` 的用法，prim_type 用 `"Sphere"`）。
- **为什么用球**：① 与你选的"固定 K 槽：相对位置+半径"观测格式**精确匹配**（球只有一个半径，无朝向）；② 碰撞、obs、奖励三者共用同一几何（球-球），不会出现"obs 半径与物理半径不一致"的错位；③ 是未来动态障碍（球跟踪）与 3D 感知（检测框→球估计）的最简载体。
- **3D 可绕飞如何体现**：同一水平位置可放"矮球"（球心 z 低，可从上方翻越）或"浮空球"（球心 z 高，可从下方/两侧通过）。v1 全部用球，靠 $z_o$ 与 $r_o$ 的随机组合产生"可绕/可越/卡缝"的多样性。
- **半径先固定**（v1）：因每 env 每槽位一个物理 prim，reset 时逐帧改刚体半径既不便宜也易与缓存不一致。**v1 令所有障碍 $r_o = r_{fixed}$（如 0.30 m，可配），课程只加数量**；半径随机档位（kaiwu 的 `radius_choices`）作为 Phase D 增强，通过"单位球 + `set_world_scales`"实现（§11.4），obs 的半径槽位结构**已经预留**。
- **无人机半径/膨胀**：$r_{drone}$ 取 Crazyflie 安全包络（几何对角线 ≈0.12 m，留裕量建议 **0.15 m**，可配），障碍再叠加 kaiwu 式膨胀 `inflation=0.05` → 判定半径 $r_s = r_{drone}+r_o+inflation$。obs 喂**原始 $r_o$**（不加膨胀），奖励/碰撞用膨胀后半径（与 kaiwu 一致：`sensed = radii + OBSTACLE_RADIUS_INFLATION`）。

### 4.2 布局采样（每 episode，batch 化，全部在 env 帧内）

采样空间（与 NavVel 目标/起点分布同处 env 帧、中心对称，注意避开 `init_pos_range`/`target_pos_range` 与边界）：

```
球心采样范围:  x,y ∈ spawn_xy_range = [-2.8, 2.8]²    (给 bound_xy=5 留 margin)
              z   ∈ spawn_z_range   = [0.6, 3.4]       (保证球完整在场内: r_o≤0.4, z±r_o 不越 z_min/z_max)
约束:
  (a) 对起点/目标 3D 球面距离 ≥ endpoint_margin(=r_s+0.1 左右): 防止堵死起飞/到达
  (b) 球心互距 ≥ min_obstacle_spacing(=2·r_s): 防止球互相叠穿、留出可通过缝
  (c) 不要求"必定有缝"——是否可通由策略学，课程低阶段障碍少天然容易
```

实现要点（抄 kaiwu `layout.py` 的**约束过滤**思想但按 3D/球重写）：

1. **近似均匀候选池**：网格点（间距 ≈ min_obstacle_spacing + 随机抖动）→ 过滤 (a)(b) → 从中不放回地抽 L 个。batch 化：每个 env 独立网格偏移 + 掩码，全程张量操作、避免 Python 循环（512 env × 8 槽的体量不允许 for）。
2. **不可行兜底**：若过滤后候选不足 L 个（极少见），允许放宽 (a)（只保起点）或减小间距，保证 reset 不挂。
3. 采样结果 `obstacle_pos (N,K,3)`：前 L 槽有效，其余槽置 0（同时 mask=0）。
4. 起点/目标由 NavVel 现有采样先定，再采障碍（障碍依赖起点/目标坐标）。

> 与 kaiwu 的差异：kaiwu 起点固定 `start_abs=[0.5,2.5,0.15]`，障碍过滤用固定端点即可；NavVel 起点/目标每 episode 随机 → 障碍过滤必须在 reset 内、逐 env 对随机端点做。因此本采样器**不能直接 import kaiwu layout 代码**，只能抄思路。

### 4.3 物理摆位（reset）

- 模板 `_design_scene` 建 K 个：`create_obstacle("/World/envs/env_0/obstacle_{i}", "Sphere", translation=(0,0,2), attributes={"radius": r_fixed})`，i=0..K-1。GridCloner 自动复制到每 env（`/World/envs/env_*/obstacle_{i}`）。
- view：`RigidPrimView("/World/envs/env_*/obstacle_*", reset_xform_properties=False)`（形状需冒烟确认是 `(N,K)`，必要时显式 `shape=(num_envs,K)`，参考 FlyThrough/Transport 的多体 view 用法）。
- `_reset_idx(env_ids)`：
  - 激活槽（前 L 个）：`obstacles.set_world_poses(obstacle_pos[env_ids,:L] + envs_positions[env_ids].unsqueeze(1), env_indices=env_ids)`（env 系→world 系，照抄 `target_vis.set_world_poses` 的写法）；
  - 未激活槽：**移到场地外**（如 z=-100）或缩放为 0，避免残留物理碰撞/遮挡（注意 RigidPrimView 需要支持按槽索引更新，若不方便则用"K 个独立单槽 view"逐槽 set，冒烟时确定最省写法）。
- 障碍是 **kinematic 静止刚体**：reset 只摆位、不动速度 → 每 episode 布局固定、step 间不更新（无需 `_post_sim_step` 额外逻辑）。

---

## 5. 观测设计（E2，固定 K 槽 + mask + 未来感知接口）

### 5.1 现有 obs（NavVel）

```
obs = [ rpos(3)           目标 − 无人机位置 (env 帧, 平移不变)
        drone_state[3:](20)  Crazyflie state=23, 去掉 pos 后 20
        rheading(3)       目标航向 − 当前 heading
        time_encoding(4) ]          → 合计 30
```

### 5.2 新增 K 槽障碍块

```
obstacle_block = [ obstacle_rpos(3) × K   障碍球心 − 无人机位置 (env 帧), 未激活槽 = 0
                   obstacle_radius(1) × K 障碍半径, 未激活槽 = 0 ]     → 合计 8K = 32 (K=8)
总 obs = 30 + 32 = 62
```

关键点（全部承自 kaiwu，已在会话总结）：
- **固定 K 槽 + mask**：`mask = (radius > 0)`，未激活槽 rpos/radius 填 0。网络永远见 K 槽，学"忽略 0 槽"。
  与课程天然兼容（0→2→4→8 只是激活槽数量变化，obs 维度不变，可跨阶段续训/评估）。
- **相对量、平移不变**：障碍 rpos 用"球心 − 无人机"，与 `rpos`(目标−无人机) 同语义，策略对所有布局平移泛化。
  ⚠️ 与 kaiwu 同一坑：**不要给绝对坐标 obs**。
- **归一化建议**：rpos 分量 / `obstacle_dist_norm(=5)` 截到 [−1,1]；半径 / `obstacle_radius_norm(=0.5)` 截到 [0,1]（常量放进 yaml / env）。NavVel 现有状态量未归一化（沿用 Hover），若发现收敛慢，优先给**新增的距离量**做归一化，成本最低、收益最大。
- **是否需要障碍数标量 / 最近障碍距离**：kaiwu 都没给（网络自 8 槽推断）；v1 也不加，保持输入最小。若想给"最近障碍在哪"更强先验，可用 `stats` 提供但**不进 obs**（避免维度膨胀）。

### 5.3 可选增强（v2 再考虑，本期不做）

kaiwu 的 **48 扇区水平射线**与**速度走廊**特征本质是给 MLP 一个"廉价 2D LiDAR 摘要"。本期障碍是 3D 球且数量 ≤8，8 槽真值 + 距离势场应够；若 8 障碍后学不动，再考虑加"朝向目标方向的射线净空"或水平扇区射线（公式可从 kaiwu `observation_builder.py::_ray_circle_intersections` 泛化 3D 抄）。**不要一开始就上**——维度大、归一化难、难以归因。

### 5.4 未来"大飞机 + 机载雷达/视觉相机"感知部署注记（⚠️ 重要，防遗忘）

> 你 2026-09-04 确认：后续将用**大飞机搭载机载雷达与视觉相机**部署，本格式需为其预留接口。
>
> 1. **本阶段 obs 槽位喂的是"真值"**（仿真内直接用 obstacle_pos，真机评估用动捕已知地图喂同格式）。**这不是感知**。
> 2. 未来感知化时，**保持 8 槽格式不变**，把每槽的内容从"真值 $(p_o,r_o)$"替换为"感知估计 $(\hat p_o,\hat r_o)$ 或目标级检测列表"，
>    并在槽位上叠加：检测置信度、尺寸类别、速度估计（动态障碍阶段才需要）等字段（扩维度时注意跨 checkpoint 兼容策略）。
> 3. 感知会引入**漏检/虚警/延迟**：奖励与终止用的"几何真值"与策略 obs 用的"感知估计"届时必须**解耦成两套数据通路**——
>    训练早期用真值，后期用"真值 + 噪声/遮挡模拟"做 sensor-noise curriculum（本阶段就应把 obs 拼装函数与碰撞函数分开写，见 §8.1 的模块划分，避免以后重构）。
> 4. 雷达 vs 视觉 vs 真值 的域差异、以及"稠密障碍下 8 槽不够用（需按距离/威胁优先级选 K 个）"的槽位选择策略，留到感知阶段单独设计。

---

## 6. 奖励 / 碰撞 / 终止设计（E3+E4，3D 版 + 按 NavVel 量级标定）

### 6.1 记号与判定几何

```
p       = 无人机位置 (env 帧)
p_oi    = 第 i 个激活障碍球心;  r_oi = 其半径 (未激活: r_oi=0 不参与)
r_drone = 0.15 (可配)      infl  = 0.05 (膨胀)
r_si    = r_drone + r_oi + infl        (判定半径)
d_i     = ||p − p_oi|| − r_si          (3D 球面净距)
碰撞(几何) : d_i < collision_margin(=0.05)
近障危险区 : d_i < danger_radius(=0.6)
min_clear = min_i d_i  (对所有激活障碍)
```

碰撞**边沿事件**：`in_collision = (min over i 的 d_i < margin)`；`new_collision_event = in_collision & ~prev_in_collision`；
episode 内累计 `cumulative_collisions += new_event`；**`cumulative_collisions ≥ max_collisions(=2)` → terminated**（导航阶段内）。

### 6.2 建议奖励结构（全部权重在 yaml，公式内给"原始量级"）

沿用 NavVel 现有项 + 新增障碍项。**原始系数先按"每步最多贡献约 0.1–1.0"设计**，权重只做微调：

| 项 | 原始公式（每步） | 建议初始权重 | 说明 |
|---|---|---|---|
| `reward_pose`（保留） | $1/(1+(k·d_{goal+heading})^2)$ | 1.0 | 现有到达势场 |
| `arrival`（保留） | $+arrive\_bonus$ 一次性 | 5–10 | 见 §1.2 可调大 |
| （可选）PBRS 目标进度 | $2.0\,(d_{t-1}-\gamma d_t)$ | 3.0 | 抄 kaiwu `target_progress`，缓解大距离梯度弱 |
| **`obstacle_log_distance`**（新，3D） | $-\lambda_{log}\,\phi(d_{min},\,D_{danger})$，$\lambda_{log}=0.3$，$D_{danger}=0.6$ | 2.0 | 见式 (1) |
| **`collision_event`**（新） | $-C_{col}\cdot n_{new}$，$C_{col}=10$ | 1.0 → 实际单次 −10 | 只罚"新进入接触"边沿 |
| **`early_death`**（新） | $-C_{ed}\cdot \mathrm{clamp}(\frac{T_{ed}}{\max(\text{存活步},1)},1,10)$，$T_{ed}=300$ | 2.0 | 见式 (2) |
| （可选）`near_obstacle_slowdown` | $-w\,v_{\|}\,\mathrm{relu}(1-d/D_{danger})$ | 1.0 | 近障且朝障飞才罚（见 §6.5） |
| `reward_effort`（保留） | 0.1·exp(−effort) | 0.1 | |
| `reward_action_smoothness`（保留） | 0.0 | 0 | 平滑惩罚后续再看 |

kaiwu 的 log 距离公式（2D 圆柱），3D 化后逐障碍（注意 kaiwu 是"最近一个"取 phi，NavVel 建议**对所有在危险区内的障碍求和**，避免一个被遮另一个靠近时漏罚）：

$$d_i=\|p-p_{o,i}\|-r_{s,i},\qquad
\phi(d,D)=
\begin{cases}
0, & d>D\\[2pt]
\ln\!\big(\tfrac{\max(d,10^{-3})}{D}\big), & 0<d\le D\\[2pt]
\ln\!\big(\tfrac{10^{-3}}{D}\big)+k_{pen}\,d, & d\le0
\end{cases}
\qquad (k_{pen}=100)$$

$$r_{\text{obsLog}}=-\lambda_{\log}\sum_{i\,\in\,\text{active}}\phi(d_i,\,D_{\text{danger}}) \tag{1}$$

早死惩罚（抄 kaiwu `_reward_early_death_penalty` 思想）：

$$r_{\text{earlyDeath}}=-\mathbb{1}\{\text{死因∈\{碰撞,OOB\}} \wedge \text{存活步}<T_{ed} \wedge \text{本episode未罚过}\}\cdot C_{ed}\cdot \mathrm{clamp}\!\Big(\tfrac{T_{ed}}{\text{存活步}},1,10\Big) \tag{2}$$

> 与 kaiwu 的数值差异提醒：kaiwu 的 weight 体系建立在"CTBR 大奖励 + 大量 WP 步骤 + 每项内部再乘常数"上，单次碰撞可达 −2500；
> NavVel 每步奖励量级 O(1)，**照抄数值会让障碍惩罚淹没导航信号**。上面给的初始权重是"量级正确、需实测标定"的起点。

### 6.3 标定方法论（每步奖励项都要能单独观测）

1. 把每一项的**原始贡献**写进 `stats`（如 `stats/term_obs_log`、`stats/term_collision`），wandb 里按帧看均值/分布；
2. 原则：**安全项在"相关状态"下显著、常态下接近 0**（log 距离只在 d<0.6 出现；collision 只在边沿）；常态项（pose/effort）决定整体量级；
3. 调序：先只开 stage0（无障碍）把导航学出来（此时障碍项全为 0 自动隐身）；stage1 起开障碍项，若出现"宁可绕远路也不靠近障碍"的过度保守 → 调小 log 项；若碰撞率不降 → 调大碰撞/早死项。

### 6.4 终止惩罚与 done（也是 stage0 的修复项）

NavVel 现有 `misbehave`（坠地/OOB/NaN）只是终止。**建议为三类失败分别记账并加一次性负信号**（kaiwu 的 `in_arena/timeout/early_death` 思路）：

- `OOB`（`||xy||>bound_xy` 或 `z>z_max`）：失败原因=oob，一次性 −（可配，如 −20）；
- `坠地`（`z<z_min`）：失败原因=crash，同上（碰撞判定不把地面算进去——地面由 z_min 管）；
- `collision_exceeded`：见 §6.2 `early_death`/`collision_event`；
- `timeout`（`progress≥max_episode_length` 且未到达）：失败原因=timeout，一次性 −（如 −10），kaiwu 用 −80 量级，NavVel 建议小些；
- 到达（`arrival`）：成功，+arrive_bonus。

`terminated` 里把上述失败与到达区分开（`success_terminate` 仍可关），`truncated` 只有 timeout。

### 6.5 可选：近障碍减速（对应 kaiwu `dynamic_velocity_limit`/`velocity_corridor` 的简化 3D 版）

kaiwu 用"净空分档限速 + 速度走廊射线"很复杂。NavVel 已有 `max_vel` 限幅兜底，v1 建议只做一行简化惩罚：
把无人机速度分解为"指向最近障碍的分量 $v_{\|}=\max(0,\;-\dot d)$"，在 $d<D_{danger}$ 时给 $-w\,v_{\|}\,(1-d/D_{danger})$。
近障还横冲直撞才罚，远离障碍/绕行不罚。**先作为可选开关（默认开 small），视 stage1 表现决定去留。**

---

## 7. 课程学习设计（0 → 2 → 4 → 8，成功率门槛升级）

### 7.1 为什么放 env 内自驱动（架构决策）

OmniDrones fork 的 PPO 主循环（`scripts/train.py` + torchrl `SyncDataCollector`）**不触碰 env/task 参数**，全仓无 curriculum 基建。
改动训练器（train.py）来"定时改 env"会让 play.py/eval 与训练逻辑分叉，且 torchrl collector 对 env 内部状态不敏感。
**最稳做法：课程状态机住在 env 内**（`nav_vel.py` 的 `self.curriculum_level`），由 env 在 `_reset_idx` 每 episode 结算时推进；
train.py/play.py/算法**零改动**，`level` 通过 `stats` 上报 wandb，eval 时可用 CLI 覆盖 `task.curriculum.initial_level` 锁级评估。

### 7.2 状态机与门槛

```
levels = [0, 2, 4, 8]           # level index → 每 env 激活障碍数 = levels[idx]
成功定义: episode 结束原因 == arrival && cumulative_collisions == 0
统计:    env 内滚动维护最近 W(=3000) 个 episode 的 success_rate、collision_rate
升级:    success_rate ≥ threshold(=0.80) 且 距上次升级帧数 ≥ min_frames(建议 ≥ 2~5M 帧)
降级:    默认关；可配 allow_demote（连续 ~30M 帧无进展且 success_rate<0.3 时回退一级，防止卡死）
```

要点：
1. **成功统计要区分真终止**：NavVel 大多 episode 是 truncated(timeout) 结束，**不能用 return** 做门槛（kaiwu 同样只用 stats 不用 return）。在 `_reset_idx` 的收尾处，依据"上次 done 的 env 的结束原因"更新滚动计数（`reset_terminated` 里带 reason）。
2. **门槛加滞后 + 最少帧数**，避免临界抖动反复升降；
3. 同一 `level` 下所有 env 障碍数一致（可复现、易归因）；若要更强鲁棒性，后期可改成"每 env 从 [0, level] 分布采样"，本文先给一致版。
4. `level` 写入 `stats["curriculum_level"]`（EMA/或直接常数），wandb 可按帧画出学习曲线与课程的对应关系；eval/`play.py` 用 `task.curriculum.initial_level=3`（8 障）直接锁级测最强难度。

### 7.3 为什么课程放"数量"而不是先放"半径/布局难度"

- 观测是**固定 K 槽**，数量变化只改变"激活槽数"，不改变网络输入 → 无 obs 断层，可平滑跨阶段；
- 数量是"并行探索的天然困难旋钮"：2 个障碍先学会"绕单个障碍"的基本技能，4/8 再学"穿缝/优先级"；
- 半径/最小缝宽/起点-目标距离等作为**第二旋钮**（Phase D），等数量课程收敛后再叠加（§11.4）。

---

## 8. 代码实施步骤（文件级，落点基于 2026-09-04 实测）

> 全部在 `OmniDrones/` fork 内（分支 `feat/crazyflie-pidrate`），`conda activate lz_env`，命令在 `OmniDrones/scripts/` 执行。

### 8.1 `omni_drones/envs/single/nav_vel.py` 主改造

建议把障碍相关逻辑拆成同目录小模块（若嫌文件多，也可直接并入 nav_vel.py，但**务必保持 obs 拼装与碰撞函数分离**，见 §5.4）：

```
omni_drones/envs/single/
├── nav_vel.py                  # NavVel：接入 obstacle block
├── nav_vel_obstacles.py        # (推荐) ObstacleManager:
│                               #   __init__(cfg, device, num_envs, K)
│                               #   sample_layout(pos, goal) -> (pos[N,K,3], radii[N,K], active[N,K])
│                               #   reset(spawn/移出)
│                               #   min_clearance(pos, drone_pos) / collision_edge(...)
│                               #   build_obs(drone_pos) -> [N,K,4]
│                               #   (纯逻辑, 无 isaac 依赖 → 可单测 + 未来感知化只换这一层)
└── nav_vel_curriculum.py       # (推荐) 见 §8.6
```

对 `nav_vel.py` 逐方法的改动点：

| 方法 | 改动 |
|---|---|
| `__init__` | 读 `cfg.task.obstacle` / `cfg.task.curriculum`；建 `ObstacleManager`；`self.obstacle_views = RigidPrimView("/World/envs/env_*/obstacle_*", ...)`（形状冒烟确认）；初始化课程状态 |
| `_design_scene` | 循环 i in K：`create_obstacle(f"/World/envs/env_0/obstacle_{i}", "Sphere", translation=(0,0,2.), attributes={"radius": r_fixed})`（kinematic、collision on；GridCloner 自动复制） |
| `_set_specs` | observation_spec 维度 `30→62`（K=8）；stats_spec 追加：`collision_count / collision_rate / min_clearance / success_rate / curriculum_level / term_*` |
| `_reset_idx` | ① 采样 init/target（现有逻辑）→ ② `level=levels[curriculum_idx]` → `ObstacleManager.sample_layout(...)` → ③ 激活槽 `set_world_poses`、未激活槽移出 → ④ 重置碰撞计数/边沿缓存/课程结算 |
| `_compute_state_and_obs` | obs 追加 obstacle block（归一化后 concat） |
| `_compute_reward_and_done` | 加入 §6 各项；几何碰撞边沿检测；terminated 区分 reason（crash/oob/collision_exceeded/arrival）；更新 stats；每 episode 收尾调课程结算 |

> 冒烟必查：RigidPrimView 对 `/World/envs/env_*/obstacle_*` 的形状是否为 `(N,K)`；未激活槽"移出"写法是否会触发物理同步报错；障碍碰撞是否与地面/env 间 filter 正确（`cloner.filter_collisions` 只滤 env 间，env 内 drone-障碍保留）。

### 8.2 `cfg/task/NavVel.yaml` 新增配置段

```yaml
# ---- [M2] static 3D obstacles (kaiwu-inspired, 3D sphere model) ----
obstacle:
  max_slots: 8            # obs 固定槽位 K（与 obs 维度绑定，改它要同步改 obs dim）
  radius_fixed: 0.30      # v1 固定半径
  spawn_xy_range: [[-2.8, -2.8], [2.8, 2.8]]
  spawn_z_range: [0.6, 3.4]
  endpoint_margin: 0.35
  min_obstacle_spacing: 0.85   # ≈ 2*(r_drone+r_obs+infl)+裕量
  drone_radius: 0.15
  inflation: 0.05
  collision_margin: 0.05
  danger_radius: 0.6
  max_collisions: 2
  # ---- rewards（初始值，按 §6.3 标定）----
  reward_obs_log_weight: 2.0
  reward_obs_log_scale: 0.3
  reward_collision_penalty: 10.0
  reward_early_death_weight: 2.0
  early_death_threshold_steps: 300
  reward_near_slowdown_weight: 1.0
  reward_timeout_penalty: 10.0
  reward_oob_penalty: 20.0
  reward_crash_penalty: 20.0

# ---- [M2] curriculum: fixed stages 0->2->4->8, success-rate gate ----
curriculum:
  levels: [0, 2, 4, 8]
  initial_level: 0
  gate_window_episodes: 3000
  success_rate_threshold: 0.80
  min_frames_between_promote: 2_000_000
  allow_demote: false

# ---- [M2] velocity limit (applied in VelController transform) ----
vel_limit:
  max_vel: 1.8        # m/s
  max_yaw_rate: 1.5   # rad/s (可选)
```

### 8.3 `VelController` 限幅（transforms.py + train.py/play.py）

`omni_drones/utils/torchrl/transforms.py::VelController`（现 L268）在 `_inv_call` 里直接把 `action[:3]` 当 `target_vel` 送 `controller.compute`，**无任何限幅**。改动：

```python
class VelController(Transform):
    def __init__(self, controller, action_key=("agents","action"),
                 max_vel=None, max_yaw_rate=None):
        ...
        self.max_vel = max_vel            # 标量或 (3,) 张量
        self.max_yaw_rate = max_yaw_rate
    def _inv_call(self, tensordict):
        drone_state = tensordict[("info","drone_state")][..., :13]
        action = tensordict[self.action_key]
        target_vel, target_yaw = action.split([3, 1], -1)
        if self.max_vel is not None:
            norm = target_vel.norm(dim=-1, keepdim=True).clamp(min=1e-6)
            target_vel = target_vel * (norm.clamp(max=self.max_vel) / norm)   # 只缩模长不改方向
        if self.max_yaw_rate is not None:
            target_yaw = target_yaw.clamp(-self.max_yaw_rate/math.pi, self.max_yaw_rate/math.pi)
        cmds = self.controller.compute(drone_state, target_vel=target_vel,
                                       target_yaw=target_yaw * torch.pi)
        torch.nan_to_num_(cmds, 0.)
        tensordict.set(self.action_key, cmds)
        return tensordict
```

`scripts/train.py`（L62–89 的 `velocity` 分支）与 `scripts/play.py` 同款装配处，从 `cfg.task` 读 `vel_limit` 传入：

```python
elif action_transform == "velocity":
    from omni_drones.controllers import LeePositionController
    from omni_drones.utils.torchrl.transforms import VelController
    controller = LeePositionController(9.81, base_env.drone.params).to(base_env.device)
    vl = base_env.cfg.task.get("vel_limit", {})
    transform = VelController(controller,
                              max_vel=vl.get("max_vel", None),
                              max_yaw_rate=vl.get("max_yaw_rate", None))
    transforms.append(transform)
```

> 方向不变量：只压模长、不动方向，保证"朝目标飞"语义不被破坏；stage0 也应开启（见 §1.2 假设 4）。

### 8.4 注册/统计

- `NavVel` 已注册（`envs/single/__init__.py` + `IsaacEnv.__init_subclass__`），**无需改注册**。
- 新 stats 键自动随 `stats_spec` 进 wandb / eval（train.py 的 evaluate 按 `stats` 键记录），无需改 trainer。

### 8.5 阶段 0 的"收敛修复"额外项（与障碍无关，但先做）

如 §1.2：terminated 附 reason 与失败惩罚（§6.4 用 `reward_timeout/oob/crash_penalty` 不用障碍代码即可启用）、
可选 PBRS 目标进度项、`arrive_bonus` 调大测试、B/C 组超参短测。这些都在 `cfg/task/NavVel.yaml` 开关控制，避免动结构。

### 8.6 课程结算的位置与写法要点

在 `_reset_idx(env_ids)` 内、**这些 env 重置前**，用它们上一 episode 的 done 信息更新滚动计数：

```python
# nav_vel.py（伪码，落点自定）
for i, reason in enumerate(self._last_done_reason[env_ids]):   # reason ∈ {arrival, crash, oob, collision_exceeded, timeout, nan}
    ep_success = (reason == "arrival") and (self._last_collisions[env_ids[i]] == 0)
    self._curriculum_queue.push(ep_success, collided=...)
self._maybe_advance_curriculum()   # 读滚动成功率 → level+1 / (可选)-1
```

> 已确定：`level` 全局（所有 env 同 level）；升/降门槛与最少帧数见 §7.2；若 torchrl collector 的 reset 触发点取不到 done reason，可改在 `_compute_reward_and_done` 里缓存 reason、`_reset_idx` 消费（冒烟时确认数据流）。

---

## 9. 训练执行计划与验收标准（分阶段）

> 命令均为待执行；执行后把 run id / 结果回填到 §13。所有短训先把 `wandb.mode=disabled`，正式跑再 online。

### Stage 0 —— 无障碍收敛修复（课程 level=0）
```bash
python train.py task=NavVel algo=ppo headless=true wandb.mode=online wandb.project=RL90 \
    task.curriculum.initial_level=0 total_frames=5_000_000 save_interval=50
```
验收（沿用 M1 §1 表格）：`pos_error` EMA 从 ~3 降到 <0.3；`arrival` EMA 从 0 升到出现持续 >0；无 NaN；
`eval_ckpt` 式确定性评估到达率 ≥80%（0.5m 内保持 ≥1s）。**未达标不要进入 Stage 1。**

### Stage 1 —— 障碍机制冒烟 + 2 个障碍
- 先锁 2 障跑 1 轮冒烟（确保无报错、stats 全出）：
```bash
python train.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
    task.curriculum.initial_level=1 max_iters=1
```
- 再正式训（让课程从 1 起）：
```bash
python train.py task=NavVel algo=ppo headless=true wandb.mode=online wandb.project=RL90 \
    task.curriculum.initial_level=1 total_frames=10_000_000 save_interval=50
```
验收：2 障下到达率≥80%、碰撞率（含边沿事件）低（目标 <5% episodes 碰撞）、奖励各项量级合理（见 §6.3 标定）。

### Stage 2 / 3 —— 4 障、8 障
课程门槛达标会自动升；若中途需手动续训指定难度：`task.curriculum.initial_level=2|3`。
验收：8 障到达率 ≥80%（可接受比 2 障略低，最低 ≥60% 见 §13 协商）、碰撞率低、mean 到达时间/`min_clearance` 合理；无 NaN、GPU 显存/物理负荷 OK（512 env×8 球）。

### Stage 4 —— 评估与鲁棒性（每阶段达标后都做）
```bash
python eval_ckpt.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
    task.curriculum.initial_level=3 +checkpoint=/path/to/checkpoint_XXXX.pt +rollout_steps=600
# 有头目视
python play.py task=NavVel algo=ppo headless=false task.curriculum.initial_level=3 \
    +checkpoint=/path/to/checkpoint_XXXX.pt
```
固定多个 seed × 多组手工布局（含"必经缝"窄布局、目标紧贴障碍后方）测：到达率、碰撞率、min_clearance 分布、
贴障碍最近距离（保守度）；对比无障碍 stage0 的到达时间损失（避障代价）。

---

## 10. 里程碑 / 风险 / 坑

### 10.1 里程碑
| 阶段 | 内容 | 验收 |
|---|---|---|
| M2-S0 | stage0 无障碍收敛修复（含终止惩罚/限幅/超参） | pos_error<0.3、到达率≥80% |
| M2-S1 | 障碍机制（spawn/obs/奖励/碰撞/课程）落地 + 2 障收敛 | 2 障到达率≥80%、碰撞率<5% |
| M2-S2 | 4 障 | 4 障到达率≥80%（或协商≥70%） |
| M2-S3 | 8 障 + 鲁棒性评估 | 8 障达标 + 评估报告 |
| M3（后） | CBF1 消融（naive/filter_only/reward_only/hybrid） | how2use §4.5 |

### 10.2 风险与坑（kaiwu 实测 + 本仓库实测 + 框架特性）

1. **M1 未收敛是最前置风险**（§1）——不加障碍先修好。
2. **数值照抄 kaiwu 会崩**：NavVel 每步 O(1)，kaiwu 碰撞 −2500/早死 −200 量级直接覆盖导航信号 → 权重一律按 §6.3 标定、分项进 stats。
3. **mask 槽位的观测坑**：未激活槽 rpos=0 可能被网络当"障碍就在机头"（0 距离）→ 必须让网络能从 `radius=0` 学到"忽略"；
   若训练发现网络对 0 槽敏感，可把未激活槽 rpos 设成"远离值（如 [0,0,-100]）+ radius=0"或加显式 active 标志（进 obs 的 0/1），二选一在冒烟期定。
4. **几何 vs 物理不一致**：obs/奖励用球-球几何；真实物理里 drone 撞 kinematic 球会有物理响应（被顶开/卡住/偶发 NaN）。
   缓解：碰撞边沿事件阈值(margin 0.05)先于物理接触触发终止（2 次内），且 `max_vel` 限幅降冲击；若仍见 NaN，考虑把障碍碰撞层 `collision_enabled` 与几何判定分层（见 §11.3）。
5. **RigidPrimView 多体形状**：`/World/envs/env_*/obstacle_*` 形状是否 (N,K)、按槽索引 set 的 API、未激活"移出"写法需冒烟确认；若别扭就退回"K 个独立单槽 view"（K×512 场景构建成本仍在克隆时一次付清，step 内只 set 激活的 L 个）。
6. **障碍数量多后的物理/显存**：512 env × 8 球 = 4096 额外刚体，注意 sim_base 的 `gpu_max_rigid_contact_count` 等缓冲；若 OOM/慢，`num_envs` 降到 256 或把障碍数按 level 用"同一球模板复用"。
7. **课程门槛数据源**：只能用"真终止 episode 的结束原因"统计成功率，别用 return；truncated(timeout) 占比高时滚动窗口要足够大（3000+），且升档需最少帧数。
8. **obs 维度变了 = 旧 checkpoint 不可续**：stage0 起就是新维度（62），M1 的 30 维 ckpt 不能 load（正常，重训）；跨 0/2/4/8 阶段维度不变可续训。
9. **z 方向学习**：3D 障碍要求策略会主动升降绕障；若 8 障后出现"只会 xy 绕、撞顶/撞地"，检查 `reward_pose` 里 rheading/高度项与 z 目标范围，必要时给障碍按 `z_o` 分"矮/浮空"两档标注（进 obs 一个类别位）作为 v2 增强。
10. **归一化**：新增距离量若不归一化，MLP 输入尺度差异大 → 收敛慢/不稳（§5.2）。

---

## 11. 后续阶段接口预留（本期不实现，但代码结构要留好口子）

### 11.1 CBF1（收敛后的 M3）
- `omni_drones/utils/cbf.py` 骨架已在 m1 §7 定义签名：`velocity_cbf_filter(p, v_nom, p_obs, v_obs, r_safe, alpha, v_max)`。
- 本期的障碍真值缓冲（位置/半径、`ObstacleManager`）就是 CBF 的输入来源 → 只需让 manager 暴露 `p_obs/r_safe` 张量即可；
- 消融开关占位（yaml `cbf: {mode: none|filter_only|reward_only|hybrid, ...}`）本期保持 `none`。

### 11.2 动态障碍（NavRL 移植，更后期）
- 每个障碍槽将来扩展速度 `v_o(3)`；`ObstacleManager` 加 `step(dt)`（位置积分 + 写回 sim）。本期布局/采样与"每 episode 固定"的逻辑要写成可替换的接口，别把静态假设写死在碰撞函数里。

### 11.3 大飞机感知（雷达/相机）
- 见 §5.4 注记：保持 8 槽格式与"obs 拼装 / 碰撞判定"分离；训练后期加 sensor-noise curriculum（真值+扰动喂 obs、真值判碰撞）。

### 11.4 半径随机化 / 第二难度旋钮
- v1 固定半径 → Phase D 用"单位球 + per-env `set_world_scales`"实现 `radius_choices` 桶；obs 半径槽已预留，届时只放开采样分布即可。
- 第二旋钮候选：起点-目标最小距离、最小缝宽（min_obstacle_spacing 下调）、障碍 z 分布（矮/浮空混合）。

### 11.5 CTBR / PIDrate 动作层（更后期，与本期解耦）
- 本期奖励/碰撞只依赖"位置+速度"，与动作层解耦；将来换 `action_transform: PIDrate` 只需改 yaml，env 障碍逻辑不动。

---

## 12. 需要你（或后续执行者）注意的决策日志

| 决策 | 2026-09-04 结论 | 备注 |
|---|---|---|
| 课程起步 | stage0=无障碍收敛修复，先达标再升级 | 你确认 |
| 障碍类型 | 浮空/矮 3D 可绕（NavRL 风格） | 你确认 → 本文用"包围球"统一建模（§4.1） |
| 观测 | kaiwu 真值：固定 8 槽 相对位置+半径+mask；**未来大飞机机载雷达/相机感知部署要沿用此格式** | 你确认（§5.4 注记防遗忘） |
| 课程方式 | 固定阶段 0→2→4→8，成功率门槛升级 | 你确认（§7） |
| CBF | 本期纯 PPO，CBF1 留收敛后 | 你确认（§11.1） |
| 碰撞/限速 | 几何碰撞 + 累计 2 次终止 + `VelController.max_vel≈1.5–2 m/s` 限幅 | 你确认（§6.1/§8.3） |

---

## 13. 本文件状态跟踪（完成后更新）

- [ ] S0 无障碍收敛修复（记录 pos_error/arrival、run id）—— **进行中/未开始**
- [ ] 障碍机制实现（spawn/obs/奖励/碰撞/课程）+ 冒烟
- [ ] S1 2 障收敛（到达率/碰撞率/标定记录）
- [ ] S2 4 障收敛
- [ ] S3 8 障收敛 + 鲁棒性评估报告
- [ ] （M3 入口）CBF1 消融基线对比
- 时间戳：2026-09-04（创建，待回填）

---

## 附录 A：可参考的 kaiwu 源码索引（只读参考，勿直接 copy 依赖平台包的部分）

| 想要的东西 | 源文件（refs 下） | 可取内容 | 注意 |
|---|---|---|---|
| 观测 95 维拼装（含障碍 K 槽） | `refs/crazyswarm2_kaiwu/OmniDrones-2026-kaiwu/omni_drones/envs/obstacle_hover/obstacle_hover_logic.py::compute_observation` | mask 槽位填 0 的写法、字段顺序 | 需改成 3D/适配 NavVel obs |
| 障碍度量/几何 | 同上 `compute_obstacle_metrics`（2D 圆柱版） | 净空/碰撞判定骨架 | 2D→3D 球 |
| 布局采样 | 同上 `.../obstacle_hover/layout.py` | 均匀候选池、端点 margin、batch 化思路 | 端点改每 episode 随机 |
| 奖励原始函数 | `.../obstacle_hover_eval/kaiwu_model/agent_ppo/feature/reward_process.py` | `_log_safety_reward`(phi 公式)、`_reward_collision_event`(边沿检测)、`_reward_early_death_penalty`(反比早死)、`_reward_dynamic_velocity_limit`(分档限速，可选) | `compute_reward` 加权循环在平台缺失包，自写（§6.3） |
| 观测特征（可选增强） | 同 kaiwu_model `.../feature/observation_builder.py` | 48 扇区/速度走廊/路径射线（若 v2 要加） | 与 NavVel MLP 拼装需自适配 |
| 常数/权重参考 | kaiwu_model `.../conf/conf.py`、`.../conf/train_env_conf.toml` | 半径档、margin、膨胀、危险半径、门槛量级 | 数值需按 §6.3 重标 |
| 训练总览/迁移方法论 | `refs/crazyswarm2_kaiwu/ros2_ws/mynotes/KAIWU_TRAINING_MIGRATION_GUIDE.md` | 平台耦合点清单、obs 95 布局、奖励权重速查表 | — |
