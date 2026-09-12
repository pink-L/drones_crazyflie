# NavVel `stats` 字段说明（2026-09-08）

> 对象：`omni_drones/envs/single/nav_vel.py` 的 `self.stats`（per-env, shape `(N,1)`），
> 训练 log 前缀 `train/stats.*`；train.py 内置评估前缀 `eval/stats.*`。
> 配套文档：`env_design.md`（环境/单命）、`new_reward.md`（reward 定案）。

## 一、stats 是怎么产生和上报的

1. **每步更新**（`_compute_reward_and_done` 内）：多数键用 EMA（`alpha=0.8`，即
   `new = 0.8*old + 0.2*current`）；少数键是"整窗/事件"直接赋值（见下）。
2. **重置清零**：`_reset_idx` 对结束的 env `self.stats[env_ids] = 0.`（新 episode 从 0 起）。
3. **上报（EpisodeStats）**：`omni_drones/utils/torchrl/env.py` 的 `EpisodeStats` **只在
   `done` 步**收集 done env 的 stats 值（`unbind` 缓存），每个训练迭代 `pop` 后聚合上报。
   所以 `train/stats.X` 的含义 = **近期结束 episode（done 时刻）的 X 值的平均**：
   - 对 EMA 类键（arrival/pos_error/…）= done 时点的 EMA 值；
   - 对整窗类键（return/episode_len/first_arrival_step）= 该 episode 全程累计/全程值；
   - 对事件类键（success_rate/collision_episodes）= done 时点的整窗状态。
4. **eval 侧**：`eval_ckpt.py` 不走 EpisodeStats，直接读 env 内部计数器（arrival_rate /
   end-cause），是验收真值来源。

## 二、字段总表（含义 · 计算 · 陷阱）

| 字段 | 含义 | 计算方法（代码位置） | 采样/口径 | 陷阱 |
|---|---|---|---|---|
| `return` | 本 episode 累计 reward | 每步 `stats["return"] += reward`；reset 清 0 | done 时 = 整窗 return | 数值受 reward 尺度影响，勿跨配方比大小 |
| `episode_len` | 本 episode 已走步数 | `stats["episode_len"] = progress_buf` | done 时 = 整窗长度 | 单位 = 仿真步（dt=0.01s → ×0.01 = 秒） |
| `pos_error` | 到目标距离 ‖rpos‖ | EMA(`‖rpos‖`)，`alpha=0.8` | done 时 EMA | 越小越好；train 值受起点随机影响 |
| `heading_alignment` | 机头对齐目标程度 | EMA(`drone.heading·target_heading`) | done 时 EMA | -1~1，越大越朝目标 |
| `uprightness` | 竖直程度 | EMA(`drone_state[...,18]`) | done 时 EMA | 1=水平，坠机/翻转时掉 |
| `action_smoothness` | 油门抖动（负向） | EMA(`-throttle_difference`) | done 时 EMA | 越接近 0 越平滑 |
| `arrival` | **曾“到达∧保持 arrive_hold_steps(50)步”**（`episode_any_arrival` 持存，reset 清 0） | `stats[:] = episode_any_arrival.float()`（每步写持存值） | done 时 = 已完成 episode 的真实到达率 | [2026-09-08 语义变更] 原为“瞬时在圈内 EMA”（停在圈内即~1、与到达率无关，误导）；现与 eval 的 arrival_rate 同口径 |
| `vel_norm` | 平动速度模长 | EMA(`‖vel[...,:3]‖`) | done 时 EMA | 悬停≈0 |
| `collision` | 障碍接触占比 | EMA(`in_col`)，仅障碍开启 | done 时 EMA | 0 障时无更新=0 |
| `collision_episodes` | 本窗曾碰撞（≥1 edge） | `stats[:] = (ep_collision_edges>0)` | done 时整窗 | 0 障恒 0 |
| `min_clearance` | 到最近障碍表面净空 | EMA(dmin)，clamp/截断到 `obs_dist_norm`(5)；无活动=inf→5 | done 时 EMA | 越小越危险 |
| `success_rate` | 本窗“到达保持50步 ∧ 0 碰撞”（episode_any_arrival 已含保持50步） | `stats[:] = episode_any_arrival & (ep_collision_edges==0)` | done 时事件率 | [2026-09-08] success_terminate=true 时曾 log 恒 0（失真，到达即 reset）；**已还原 false → 恢复正常非 0** |
| `curriculum_level` | 当前激活障碍数 | reset 时写 `levels[level_idx]` | done 时 | 课程开关用 |
| `cbf_violation` | CBF 违反量（≥0） | EMA(`-viol`)，仅 cbf_extra 非空 | done 时 EMA | 无 CBF=0 |
| `first_arrival_step` | **首次"到达保持达成"的步数** | `just_arrived` 时写 `progress_buf`；0=整窗从未到达 | done 时整窗 | 越短 = 到得越快；0 表示没到 |
| `mean_action_diff` | 速度指令差分 | 每步 EMA(`‖a_t−a_{t−1}‖`) | done 时 EMA | 越小越稳（无 CBF 滤波臂恒 0） |

### 关键定义
- **到达（just_arrived）**：`inside` 连续 `arrive_hold_steps=50` 步（`arrive_timer≥50`）首次达成；
  `episode_any_arrival |= just_arrived`。注意"在圈内"≠"到达"，必须**连续保持 50 步**才算。
- **success_rate**：本窗 `episode_any_arrival ∧ ep_collision_edges==0`。
- **train.py 内置 eval（`eval/stats.*`）**：训练末尾对当前 policy 的一次采样评估，
  **非确定性（随机探索采样）**，历史上多次"假高/假回落"——**不作为验收**。

## 三、必须记住的 4 个坑

1. ~~`train/stats.arrival` 高 ≠ 到达率高~~（**已修复 2026-09-08**）：原为“此刻在圈内”EMA（zone 引导贴 center 就≈1）；现已改为 `episode_any_arrival` 持存（曾到达保持50步）→ train log 即真到达率。
2. ~~`train/stats.success_rate` 在 success_terminate=true 下恒 0~~（**已修复 2026-09-08**）：到达即结束→reset 清 episode_any_arrival→EpisodeStats 采到 0；已还原 `success_terminate=false`（到达后不结算、继续飞到 timeout）→ success_rate 恢复正常非 0。课程升级判据（`_reset_idx` 读 reset 前值）始终不受影响。
3. **训练内置 eval 假高**：`eval/stats.arrival≈0.95` 常见于随机采样；验收一律用
   `eval_ckpt.py`（确定性 MODE + 固定起终点 + `soft_respawn=false` 严格单命）。
4. **episode 语义随 success_terminate 变**：true 时到达 env 提前 done（episode_len<600），
   false 时最多 600。换 T（max_episode_length）会改 time_encoding/时间缩放，eval 的
   `rollout_steps` 必须与训练 T 一致。

## 四、验收真值（eval_ckpt.py 输出）
- `arrival_rate` = 窗口内曾 `just_arrived`（到达保持）的 env 比例；
- `collision edges` = 几何接触边沿计数/率；
- `joint success` = `arrival ∧ 0 碰撞`；
- `end-cause` = 未到达 env 的末状态归类：`crash`(坠地/NaN) | `oob`(出界) | `collide` |
  `timeout`(600 未到) | `arrived`。

## 五、本轮 0 障基线（zone reward，2026-09-08）观测记录
- `train/stats.arrival ≈ 0.99`、`return ≈ 557`、`episode_len ≈ 430`（部分提前结算）→ 模型在圈内；
- `train/stats.success_rate = 0` → 上述坑 2（失真，不代表没到）；
- `entropy` 单调升 5.6 → 12.5 → ⚠️ 高斯 std 持续放大（策略朝随机漂移），train 指标不可信，
  必须看确定性 eval（见下一节结果）。
