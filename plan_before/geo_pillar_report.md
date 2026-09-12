# NavVel pillar28（含柱体）geo 系列报告 — 2026-09-08

> 目标：把"含柱体混合 28 obs（4 柱 + 12 球）"环境的训练/评估演进归档，供决策与汇报。
> 代码改动(pillar 混合布局/DR)均在 OmniDrones 仓库内、未 commit；wandb project = `env_design_geoN`。

## 0. 环境定义

- **环境**：NavVel 6×6×3 固定穿越 `(-2.8,0,0.5)→(2.8,0,1.0)`，严格单命 `soft_respawn=false`，`success_terminate=false`；
- **pillar28 混合（方案 A）**：4 根柱 = 每根 **4 个外接圆球 r=0.354 沿 z 叠 4 层覆盖 [0.4,2.6] 全高**（等效 0.5×0.5×3m 立柱，xy=外接口径）+ **12 个自由球** = **28 个逻辑球全激活**；柱心 xy 采样(净空/keepout_x=2.5/柱间 gap)，自由球 3D 避柱层球；
- **obs 恒 62 维**（M=28 > K=8 滑动窗口取最近 8）→ 与 8/16 球模型 obs 兼容，可 **warm 续训 / 免重训 eval**；
- 判定/CBF/reward 全按 28 逻辑球（柱层球逐球安全）；碰撞率≈0；
- reward = F1/RB-C（w_f1.5 zone1.5 arrive40/40 to60 crash/oob15），ent0.05，单命；
- **T(max_episode_length)**：早期 1000 → geo6 起 **1500**（绕行路径长，1000 截断是主瓶颈）；eval rollout_steps 必须同步 T。

## 1. geo 系列演进与关键 eval（pillar28 口径）

| 轮 | 改动 | 关键结果 @pillar28 |
|---|---|---|
| geo4 (16球, T1000) | warm geo3→lock16 | 16 球双/fo ON 0.867/0.865 |
| geo5 (pillar28, T1000) | warm geo4→pillar28 20M | fo ON 0.703 / dual ON 0.688 / naive 0.629；**ro 崩 0.008(弃)** |
| **geo6 (pillar28, T1500)** | warm geo5 + **T1000→1500** | **fo ON 0.891 / dual ON 0.887 / naive OFF 0.805，全 0 碰** ← baseline 达标 |
| **geo7 (pillar28, T1500, DR)** | warm geo6 + DR(±10% 动力学 + cmd noise 0.15) 20M | nominal ON 0.94；±5%→0.54~0.67；±10%→0.22~0.35 |

## 2. geo7 最终三口径对比表（严格单命 / rollout 1500 / 256 env / arrival_rate·碰撞边沿）

| arm | filter | **nominal** | **±5% DR** | **±10% DR** |
|---|---|---|---|---|
| filter_only | ON | **0.941** · 0碰 | 0.535 · 1 | 0.289 · 1 |
| dual | ON | **0.938** · 0碰 | 0.637 · 0 | 0.352 · 0 |
| dual | OFF | 0.703 · 0碰 | 0.668 · 0 | 0.355 · 1 |
| filter_only | OFF | 0.680 · 0碰 | 0.465 · 2 | 0.223 · 1 |
| naive | OFF(无filter) | 0.648 · 1 | 0.559 · 0 | 0.328 · 2 |

> 补充（geo6 T1500，供演进对照）：fo ON 0.891 / dual ON 0.887 / naive OFF 0.805，全 0 碰。

## 3. 结论

1. **nominal + filter 已接近满血**：dual/fo ON **0.94、0 碰** —— 带 CBF filter 的标称部署质量高；
2. **filter 在 28 高密混合下仍关键**：nominal ON(0.94) ≫ OFF(0.68~0.70)——撤 filter 安全仍 0 碰（避障内化 OK），但**导航完成度掉 ~0.25**（训练带 filter 修正，OFF 为分布外）；
3. **DR 鲁棒性未内化**：geo7 训练 ±10%（+cmd noise 0.15）20M 后，**连 ±5% 都守不住**（dual ON 0.94→±5% 0.637→±10% 0.352）。碰撞仍≈0（安全域稳），崩的是"入圈保持 50 步"的精度——低层 Lee 速度控制器是**标称标定**、不知道随机后的质量/推力，策略 20M 没学会用速度指令补偿中频动力学偏差；
4. naive（无 filter）在 28 混合 + DR 下两头不占（nominal 0.648、±5% 0.559）；
5. 全程碰撞边沿 ≤2 次/窗（≈0），柱外接建模安全成立。

## 4. 决策候选（下一步）

- **A** DR 更激进/更久（±3~5% 起、40M+，或每 episode 多次参数重采样）；
- **B** 把随机化后的动力学参数（mass/推力/阻力）作为 **obs 通道**喂给策略（显式感知 → 学会按参数调节），需 obs 增维重训（论文式思路）；
- **C** 接受 **nominal + filter** 交付（0.94、0 碰）；若真实平台参数偏差 <3%，再评估；
- **D(进行中)** 拆"到过一次(不入保持圈)" vs "保持 50 步"：测 ±5% 下 **reach 完成度**，判断 DR 崩的是"到不了"还是"到了保持不住"（见 scripts/eval_ckpt.py `+record_min_rpos`）。

### 4.1 交付模型（定型，2026-09-08）

**主交付 = nominal + 运行时 CBF filter（上位机复刻），pillar28/T1500，确定性 eval ≈0.94、0 碰**：
- `geo7 filter_only`：run-20260908_224733-c1r072di/files/checkpoint_final.pt（eval 0.941·0碰）
- `geo7 dual`      ：run-20260908_224733-k4u0i8wg/files/checkpoint_final.pt（eval 0.938·0碰）
- 备选（如需无 filter 裸策略部署）：`geo6 naive` = run-20260908_221545-1p1nz7wc（pillar28/T1500 0.805，优于 geo7 naive 0.648）

**关键参数（部署/复刻 obs 与 CBF 时照抄，勿臆测）**：

| 项 | 值 |
|---|---|
| 策略输出 | `[vx,vy,vz,yaw]` 速度指令，100Hz（dt=0.01）；Actor std clamp [0.05,1.8]；ent0.05 |
| obs | 62 维 = drone_state13 + time_encoding4 + 障碍最近 8 槽(rpos_xyz/5、r_o/0.5) + 3；滑动窗口 M=28→K=8 |
| 障碍几何 | 4 柱 × 4 层外接球 r=0.354（沿 z 叠覆盖 [0.4,2.6] 全高，等效 0.5×0.5×3 柱）+ 12 自由球(半径档[0.2,0.3,0.4]) = 28 逻辑球；keepout_x=2.5；drone_radius=0.15、inflation=0.05 |
| 任务/判定 | 固定穿越 (-2.8,0,0.5)→(2.8,0,1.0)；T=1500；soft_respawn=false；arrive_radius=0.5 hold50 步；碰撞=几何边沿 dmin<0.05 |
| reward(训练, 部署不感知) | F1/RB-C：w_f1.5 zone1.5 arrive40/40 timeout60 crash/oob15 smooth0.2 |
| CBF filter(需上位机复刻) | omni_drones/utils/cbf.py CBFVelocityFilter：对 28 球(含柱层球)做速度指令投影；cbf_extra=含 brake 余量；VelController 前 |

**sim2real 决策记录**：真机 Crazyflie；场地/起终点与 sim 一致；crazyswarm2/ROS2 下发 100Hz；CBF filter 上位机复刻；**纯外层 DR(±5/10%) 内化有限**（机制=低层标称 Lee 控制器不感知随机动力学，到不了+保持不住），真实参数偏差 <~3% 时以 nominal 部署足够；若偏差更大 → 后续研究（动力学参数入 obs / 在线自适应），非纯 DR。**deploy_plan 文档 = 新会话产出 drones/deploy_plan.md（仅文档）**。

## 6. D 诊断：±5% DR 崩在"到不了"还是"到了保持不住"？（REACH 口径，eval_ckpt `+record_min_rpos`）

REACH = 曾距目标 <0.5m（到过一次，**不需保持 50 步**）；arrival = 曾到 ∧ 保持 50 步。

| arm | 口径 | REACH | arrival(=保持50) | 差值=保持不住 |
|---|---|---|---|---|
| fo | nominal | 0.969 | 0.941 | 0.028 |
| dual | nominal | 0.941 | 0.938 | 0.003 |
| naive | nominal | 0.664 | 0.648 | 0.016 |
| dual | **±5%** | 0.734 | 0.637 | **0.097** |
| fo | **±5%** | 0.656 | 0.535 | **0.121** |
| naive | **±5%** | 0.609 | 0.559 | 0.050 |

**结论（D）**：nominal 下 reach≈arrival → 保持不是问题；±5% DR 下崩的是**两者都有**——
- 主因是**"到不了目标圈"**（fo reach 0.969→0.656、dual 0.941→0.734：re-reach 本身掉 0.2~0.3）；
- 次因是**"到了但保持不住 50 步"**（fo/dual 差值升到 ~0.10-0.12）。
两者共同指向：**低层标称 Lee 速度控制器在 ±5% 质量/推力偏差下末段精度不足**（速度跟踪/悬停漂移），而策略速度指令无法补偿——这正是 DR 20M 无法内化的根因（策略不能改变低层控制器对错误动力学的响应）。

## 5. run 索引（wandb env_design_geoN，本地副本 OmniDrones/scripts/wandb）

- geo4(1937xx)：dual `-vahyki07` fo `-eqib5z3i` ro `-5d6x79dt` naive `-8sfvddjh`
- geo5(214527)：dual `-1iorg9bb` fo `-g6jp97s2` ro `-xlksu28b` naive `-29yaxbff`
- geo6(221545)：dual `-o062mpfa` fo `-0sl045st` naive `-1p1nz7wc`（T1500）
- geo7(224733)：dual `-k4u0i8wg` fo `-c1r072di` naive `-oih9kkqc`（T1500 DR）

## 7. B1 对照（2026-09-09）：低层 Lee 感知随机化真实动力学 → DR 掉点溯源

> 问题：geo7 DR（±10% 动力学，20M）后连 ±5% 都守不住（dual ON 0.94→±5% 0.637→±10% 0.352）。
> B1 假设：DR 掉点是 **sim 特有假困难**——随机化只改了物理（mass/KF/KM/drag），而低层
> `LeePositionController` 是脚本按**标称** `drone.params` 新建的 → 重力/推力补偿错配 → 末端悬停漂移。
> 真机 Crazyflie 固件用自己的 SysID 参数自标定 → 真机**不存在**这个错配。

**B1 实验**：`task.controller_sync_dr=true`，每次 reset 后把随机化后的真实 per-env `mass/KF` 全量同步进
低层 Lee（`lee_position_controller.sync_randomized`），**不重训**，直接对 geo7 ckpt 重放 eval
（rollout 1500 / 256 env / 严格单命 / fixed 穿越 / filter ON / 0 碰）。

| arm | 口径 | baseline（历史） | +controller_sync_dr | REACH |
|---|---|---|---|---|
| dual | nominal | 0.938 | **0.945**（sanity, mass std=0） | 0.949 |
| dual | ±5% | 0.637 | **0.930** | 0.934 |
| dual | ±10% | 0.352（本次复现 0.395） | **0.953** | 0.961 |
| fo | ±10% | 0.289（本次复现 0.277） | **0.895** | 0.922 |

（min_rpos mean：±10% dual sync 0.103；残余 12-27 env 为 1500 步内 timeout，sync 后 ±5/±10/nominal 三口径≈打平 0.93-0.95）

**B1 补充（2026-09-09 下午）：filter OFF 对比**——撤运行时 CBF filter（`+runtime_filter=false`，
同一脚本 `/tmp/b1off_eval.sh`），测 sync 是否仍恢复 DR 掉点：

| arm | 口径 | baseline（历史） | +controller_sync_dr | REACH | 对照 nominal(OFF) |
|---|---|---|---|---|---|
| dual | OFF ±5% | 0.668 | **0.680**（0碰） | 0.699 | 0.703 |
| dual | OFF ±10% | 0.355（复现 0.410） | **0.664**（0碰） | 0.699 | 0.703 |
| fo | OFF ±10% | 0.223（复现 0.277） | **0.625**（0碰） | 0.637 | 0.680 |

（filter OFF baseline 有 1 次碰撞边沿；sync 后全部 0 碰）

**结论补充（filter 的独立价值 + B1 更完整判读）**：
- filter OFF 下 sync 同样显著恢复（±10% dual 0.410→0.664、fo 0.277→0.625，且 0 碰）→ **低层错配确实是
  DR 掉点主因**（撤 filter 也成立），sync 后 ±10% ≈ 各自 nominal OFF 水平（0.66-0.68），DR 边际惩罚基本消除；
- 但 filter OFF + sync 只到 ~0.66-0.68（= 无 filter nominal 0.70），远低于 filter ON + sync 的 0.95 →
  **CBF filter 在 28 高密混合下的价值独立于动力学 DR**（安全 + 到达路径质量），撤 filter 即使低层完美也不可行；
- 部署定论不变且更强：**真机 = nominal 策略 + 板载固件自标定（=sync）+ 上位机 CBF filter** → 对应 sim
  filter ON + sync 的 **0.95、0 碰**口径。

**结论（定论）**：
1. **DR 掉点 ≈ 全部是低层标称错配的 sim artifact，非策略不鲁棒**。同策略（零重训）只要低层用对真实参数，
   ±10% 随机动力学下完成度从 0.35-0.40 直接拉回 **0.89-0.95、0 碰**；
2. **策略本身对动力学扰动是鲁棒的**（会导航/避障，碰≈0），只是不能代替低层做"重力/推力标定"；
3. **sim2real 含义**：真机低层固件自动适配自身参数 → 仿真里"随机动力学 + 标称低层"造成的困难在真机上不存在 →
   **nominal + CBF filter（0.94、0 碰）对真机是正确交付**；DR 也不需要再扛 ±10%（真机偏差由固件吸收，
   残余只由策略速度指令裕量覆盖）；
4. 若真机参数偏差显著（>3-5%）也无需 obs 通道/重训——低层按真机 SysID 配置即可，策略侧保留现权重。

> 注：sync 仅同步 mass（重力/推力补偿）与 KF（→ max_thrusts 归一化）；f2m/drag/inertia 未同步低层
> （姿态内环高带宽吸收 + drag 属速度层由策略应对），恢复至 0.93-0.95 说明这两项非主要失配源。
> 复现/脚本：`/tmp/b1_eval.sh`；日志 `/tmp/b1_eval_all.log`、`/tmp/b1_{run}.log`。
> 代码改动（OmniDrones 内，已提交 3a6775c）：lee_position_controller.py（sync_randomized/_compute 动态值）、
> nav_vel.py（controller_sync_dr + _sync_low_level_controller）、eval_ckpt.py/train.py（挂 low_level_controller）、
> NavVel.yaml（controller_sync_dr: false）。

## 8. CFB（Crazyflie 2.1 Brushless）模型迁移与训练（2026-09-09）

> 背景：部署真机实为 **CFB 无刷版（实测 42 g，含桨保护 + 动捕球）**，原 sim 为空心杯 CF2.1（32.1 g）。
> 模型参数取自论文 *How to Model Your Crazyflie Brushless*（arXiv:2603.05944）Table II（带桨保护）。

### 8.1 参数迁移（commit `0b88cc6` @ 2026-09-09 17:50 CST）

| 字段 | 旧（空心杯） | 新（CFB 42g） | 依据 |
|---|---|---|---|
| `mass` | 0.0321 | **0.042** | 用户实测（论文 44g 备选 0.044） |
| `inertia` | 1.4e-5/1.4e-5/2.17e-5 | **3.3e-5/3.6e-5/5.9e-5** | 论文 J（带桨保护） |
| `force_constants` | 2.3503e-08 @ 2315 | **3.4364e-08 @ 2900** | 满油门单电机 0.289 N，T2W≈2.81 |
| `moment_constants` | 7.24e-10 | **1.058e-9** | 保持 KM/KF=0.0308（须含 ω_max 变化，勿直接 ×2.29） |
| `time_constant` | 0.025 | **0.05** | 论文电机一阶 T=50 ms |
| lee `attitude_gain` | [0.0014,0.0014,0.0022] | **[0.0033,0.0036,0.006]** | raw×I_new/I_old 保姿态带宽 ~10 rad/s |
| lee `angular_rate_gain` | [0.00028,…] | **[0.00066,0.00072,0.00117]** | 同上 |

### 8.2 update_sim 只同步 mass 的建模缺口（commit `774538f` @ 17:56 CST）
- 原 `update_sim: True` 只把 yaml mass 写进 sim 刚体，**inertia 不写** → sim 物理仍是 USD 的 CF2.1 小惯量，
  而低层控制器按 yaml（CFB）大惯量建 mixer/角增益 → 等效姿态增益放大 ~2.4× 错配。
- 修复：`update_sim` 同时同步 yaml inertia 到 sim 刚体。验证：env 日志 `Mass 0.042 / Inertia 3.3/3.6/5.9e-5`。

### 8.3 免训 eval（~18:00 CST）：geo7 权重 × CFB = **0/256**
- 两次（第 1 次含惯性错配 bug、第 2 次修复后）均为 0/256，min_rpos≈5.15（几乎不动）→ 排建模因素后
  确认动力学包络变化（质量 +31%、T2W 1.6→2.8、惯量 +2.4×、滞后翻倍）使旧权重彻底失配，**必须重训**。

### 8.4 阶段一：warm geo7 dual + 小 DR（17:57–18:21 CST，`env_design_geo8`，4 seed × 20M）
- 配方：warm geo7 dual（run-20260908_224733-k4u0i8wg）；DR = mass ±3%、inertia/t2w/f2m/drag ±10%；
  dr_noise 0.15；T1500；pillar28。
- **nominal CFB eval（~19:00 CST，固定穿越/filter ON/T1500/256 env）**：

| run | seed | nominal CFB arrival | REACH | 0 碰 |
|---|---|---|---|---|
| m9v87266 | 0 | 0.938 | 0.938 | ✓ |
| 560tmtq9 | 2 | 0.965 | 0.965 | ✓ |
| ox43lc0z | 3 | 0.965 | 0.977 | ✓ |
| r02a809m | **4** | **0.969** | 0.973 | ✓ |

  → 全部 0 碰，seed2/3/4 **优于** geo7 空心杯（0.938）。
- **±20% DR eval（seed3/4，~19:10 CST）掉到 0.46–0.47（0 碰）** → 阶段一 DR 内化不足，需阶段二。

### 8.5 阶段二：warm seed4 + ±20% DR + controller_sync_dr（19:13 CST 启动，`env_design_geo9`，3 seed × 20M）
- 配方：warm seed4（r02a809m/checkpoint_19693568.pt）；DR 放大到论文档 = mass ±3%、
  inertia/t2w/f2m ±20%、drag ±10%；**`task.controller_sync_dr=true`**（B1 关键：训练时也让低层按每 env
  随机化真实 mass/KF 适配，避免 geo7 “低层不感知随机化 → DR 内化不了” 的假困难）；dr_noise 0.15。
- run：`cfb-dual-DR2-ctrlSync-{1,2,3}`（训练 seed 11/12/13）。
- 目标：nominal 保持 ~0.95+，且 ±20% DR eval 回升到 ≥0.8（能扛真机标定误差的交付形态）。
- 时间线（全部 2026-09-09，CST）：参数 commit 17:50 → 建模修复 17:56 → 免训 eval 0/256 ~18:00 →
  阶段一 17:57–18:21 → nominal eval ~19:00（0.94–0.97）→ ±20% DR eval ~19:10（0.46–0.47）→ 阶段二 19:13 启动。

### 8.6 阶段二结果（19:13–19:30 训练，~19:45 eval）——DR 内化达成

> ⚠️ **eval 口径教训**：阶段二训练开了 `controller_sync_dr=true`，eval 也必须加同开关（= 真机固件
> 自标定语义）。不带 sync 的 eval 会让低层退回标称、面对 ±20% 随机物理 → 制造 geo7 式“低层错配”假崩溃
> （nominal 0.86–0.91 / ±20% DR 仅 0.20–0.31）。带 `+task.controller_sync_dr=true` 才是正确验收。

`env_design_geo9`，warm seed4 + DR ±20%（mass±3/inertia·t2w·f2m±20/drag±10）+ controller_sync_dr + dr_noise 0.15，3 seed × 20M。

| run (seed) | nominal CFB | ±20% DR | 0 碰 | 训练末期 success_rate |
|---|---|---|---|---|
| ctrlSync-1 (hpzc2m3r) | 0.891 | **0.906** | ✓(nominal 1 边缘) | 0.556 |
| ctrlSync-2 (72s1zkt6) | 0.879 | 0.867 | ✓ | 0.505 |
| ctrlSync-3 (pczh85ou) | 0.891 | 0.883 | ✓ | 0.431 |

**判读**：
1. **±20% DR ≈ nominal（0.87–0.91）→ DR 在 controller_sync_dr（真机固件自标定语义）下真正内化**；
   nominal 仅比阶段一 seed4（0.969）降 ~0.06–0.09（DR 强化的标称代价，换取对真机标定误差的鲁棒）。
2. **交付**：主 = **ctrlSync-1**（±20% DR 0.906、0 碰）或 ctrlSync-3（nominal 0.891 & DR 0.883）；
   若真机 SysID 偏差确认 <2% 且追求标称极致，可回退阶段一 seed4（nominal 0.969）。
3. 全程 0 碰；CBF filter 仍为部署必需（见 §7 filter OFF 结论）。
