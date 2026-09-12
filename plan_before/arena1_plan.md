# Arena1：NavVel 全区域布障 + 固定起终点穿越 + 总高 3m（F1 reward 四臂重训与对比）

> 创建：2026-09-07。**本文件 = Arena1 阶段记录文档**（环境改版 + 四臂重训 + 对比；汇报并入 `F1_4arm_report.md` 末尾）。
> 仓库：`/home/lz/lzspace/drones/OmniDrones`（分支 `feat/crazyflie-pidrate`，Arena1 改版 commit `c0528d8`）；环境 `conda activate lz_env`。
> wandb：项目 **`arena1`**（fly-hust）；本阶段 run 均进 `arena1`。
> 上游：`drones/F1_4arm_report.md`（F1 四臂结论）、`drones/f1_recipe_and_runs.md`（配方/口径）、`drones/new_reward.md`（F1 reward）、`drones/new2_plan.md`（internalize 探索，已收敛于"filter 决定性"）。

---

## 1. 一句话

把 NavVel 从「±2.2/±2.8 中央聚集布障 + 随机起终点」改成「**6×6 全区域布障 + 固定 start(-2.5,0,0.5)→goal(2.5,0,1.5) 穿越 + 总高 3 m**」，F1 reward 配方不变，重训四臂（dual/filter_only/reward_only/naive）并在严格单命口径下对比。

## 2. 需求与决策项（§5 答复，含理由）

| 决策项 | 选择 | 理由 |
|---|---|---|
| 固定起终点 | `fixed_init=[-2.5,0,1.0]`、`fixed_target=[2.5,0,1.5]`（yaml 默认开）| 任务 = 固定穿越障碍场；env 读 fixed_* 退化为常量（随机航向保留）。**start z 实证定 1.0**：初定 0.5 近地 from-scratch 学不动（0 障也到不了；z=1.0 同条件 3M arrival 12%），用户拍板抬高到 1.0 |
| 总高 | `z_max: 4.5 → 3.0`（`z_min` 0.15 不变）| 环境总高 3 m 的越界上限；所有分布/判定在 [z_min,3] |
| 障碍 xy 分布 | `spawn_xy_range: [[-3,-3],[3,3]]`（候选 clamp ±2.98）| 覆盖全 6×6；OOB 仍是 ||xy||>5，贴边球不触发越界 |
| 障碍 z 分布 | `spawn_z_range: [0.6, 2.4]` | 下界≥物理球 0.4+余量（防穿地）；上界 2.4 → 球顶≤2.8 < 3.0 留越顶/飞行余量 |
| 半径档 | `radius_choices [0.20,0.30,0.40]` 不变 | 未要求调；几何/CBF 自适应 |
| 净空 | `init_clearance 0.15 / goal_clearance 0.35` 不变 | 布局探针 0 违反证明成立；goal 保持区不被吞 |
| 障碍数/课程 | `levels [2,4,8,12,16]`，from-scratch 从 2 起；`num_scene=16`（M=16，滑动窗口取最近 K=8，obs 恒 62）| 体积≈旧 ±2.2 场 ~1.2×；中插 12 软化 8→16（固定路线更难绕）；布局探针在 16 障可行率 ≥98.5% 封顶成立 |
| 其他 | `bound_xy=5 / soft_respawn / max_episode_length=600 / arrive_*` 不变 | 未要求改；600 步对 ~5m 穿越 + 绕行够用 |

## 3. 改了什么（commit `c0528d8`）

- `cfg/task/NavVel.yaml`：+ `fixed_init/fixed_target`；`z_max 4.5→3.0`；`spawn_xy_range →±3.0`；`spawn_z_range [0.6,3.4]→[0.6,2.4]`；`num_scene null→16`；`curriculum.levels [0,2,4,8]→[2,4,8,12,16]`；注释同步。
- `omni_drones/envs/single/nav_vel.py`：起/终点统一走 `_sample_init_pos/_sample_target_pos`（fixed_* → 常量全 env 同点；None → 原 `D.Uniform`）；`min_init_target_dist` 重采仅随机模式跑；`_reset_idx/_respawn/__init__` 全部走 helper（重生回固定起点，净空 rejection 保持）。**obs 结构/维度(62)、reward/CBF 公式、dr_noise 均不动。**
- `scripts/arena1_layout_check.py`：布局健康/可成功性 CPU 探针。

## 4. 布局健康 / 可成功性（探针输出，2026-09-07）

口径：固定 start/goal；每档采样 N=1024 布局；净空按名义值检查；可成功性 = 保守 6-连通 voxel(0.28) BFS，无人机中心自由空间需 ≥ r_s+col+margin。

| L | 起点违反(生在球内) | 终点违反 | 球-球 gap 违反 | start→goal 可行 |
|---|---|---|---|---|
| 2 | 0(0) | 0 | 0 | 99.8% |
| 4 | 0(0) | 0 | 0 | 99.7% |
| 8 | 0(0) | 0 | 0 | 99.6% |
| 12 | 0(0) | 0 | 0 | 99.2% |
| 16 | 0(0) | 0 | 0 | **98.5%** |

球分布：z∈[0.62,2.38]、x∈[-2.98,2.98] —— 铺满 6×6、均在 3 m 高内。可行失败 ≤1.5%（保守口径上界），可接受（600 步窗 + soft-respawn 兜底 + 课程门）。

## 5. 训练（F1 reward，from-scratch 课程 [2,4,8,12,16]，16M，4 并行，wandb `arena1`）

| 臂 | cbf.mode | run id | log | 训练轨迹(待回填) |
|---|---|---|---|---|
| dual | hybrid | (启动) | /tmp/navvel_arena1_dual_16M.log | |
| filter_only | filter_only | | /tmp/navvel_arena1_filterOnly_16M.log | |
| reward_only | reward_only | | /tmp/navvel_arena1_rewardOnly_16M.log | |
| naive | none | | /tmp/navvel_arena1_naive_16M.log | |

配方 = F1（wf6, arrive30+30t, to40, smooth0.2, ent0.05, edge4/near1 默认改版 yaml, dual 0.1/0.1 σ0.5, brake-off）；obs_safety=none(62)。**CLI 不再覆盖 spawn（已由 yaml 全区域）。**

## 6. 评估（严格单命，验收口径）

- `task.soft_respawn=false` + `rollout_steps=600`；密度档：新场地建议 eval 用 `num_scene=16, levels=[16]`（封顶档，穿越难度主口径）；可选低档 `levels=[8]`。
- ON（带 runtime CBF filter，dual/filter_only）/ OFF（无 filter，四臂）。obs_safety 不设(62)。
- 结果（待回填）。

## 7. 记录（回填）

### 2026-09-07 训练：四臂 from-scratch 全卡 2 障、arrival≈0 —— 定位为 start z=0.5 阻塞
- 四臂(16M, from-scratch 课程[2,4,8,12,16], wandb arena1: dual 3xvwqibf / filter_only thsmby7g / reward_only mvlksbd2 / naive ejr5pgwp) 全部 curriculum_level 恒 2、final arrival≈0（fo/dual 0.0, naive 0.003, ro 0.002）。**不是臂差异**。
- 诊断链条：
  1. dual 训练信号：vel≈0.85(在飞)、return≈+1650(高) 但 arrival≈0、pos_error min 仅 ~1.0 → 从没接近目标保持区。
  2. **0 障碍**严格 eval(同 dual ckpt)：pos_error min 4.0、arrival 0 → 不是障碍密度问题。
  3. **0 障碍 from-scratch 4M**(z=0.5)：arrival≈0 → 连裸固定 5m 穿越都学不到。
  4. **单变量：start z 0.5→1.0**(其余全同, 0 障碍 3M)：arrival **12%**、pos_err 0.74 → 高度是决定性变量。
  5. **z=0.5 + 去掉 survival 罚**(0 障碍 3M)：arrival 仍 0 → 不是 survival 罚，是 **z=0.5 近地飞行本身**（Crazyflie 低频低空起降不稳/持续触地→crash/respawn 循环, from-scratch 无 bootstrap）。
- 结论：**固定 start z=0.5 在现 sim/Crazyflie 动力学下 from-scratch F1 学不动**（旧 F1 随机起终点 init z∈[1,2.5] 无此问题）；z≥1.0 可学。需用户决策（保持 0.5+缓解 / 抬高 start z / 其他），四臂重训暂停待定。

### 2026-09-07 迭代 v2（start z=1.0, levels [2,4,8,12,16], 16M）
- 用户拍板 start z→1.0（commit `3831a62`）。四臂 v2：dual ek137zf9 / filter_only xh9birtp / reward_only yy6eth65 / naive 1devybcq。
- 结果：**dual 勉强到 4（仅 1 窗）、filter_only 到 4（9 窗）、reward_only/naive 卡 2**；final arrival 0.5–0.9% @4。z=1.0 解决了 0 障碍学不动，但**固定 5m 穿越 + 障碍 from-scratch 仍太陡**（旧 F1 随机起终点 12M 到 16 vs 此处 16M 才到 2–4）→ 缺「0 障碍裸穿越」bootstrap 首级。
- 决策：课程加 **0 障碍首级** → levels `[0,2,4,8,12,16]`（先学固定穿越, 再叠障碍）。

### 2026-09-07 迭代 v3（levels [0,2,4,8,12,16], 24M）
- 四臂 v3：dual / filter_only / reward_only e5gul4zg / naive z1duerma（log /tmp/navvel_arena1_v3_*.log）。reward_only/naive 预计仍卡（无滤波 from-scratch 上限低, 记录用）。
- 结果（部分，待全量回填）：
  - **reward_only (e5gul4zg)**：卡 level 2（9×level0 → 30×level2 无更高），final eval arrival 0.001。
  - **naive (z1duerma)**：卡 level 2（11×level0 → 28×level2 无更高），final eval arrival 0.074 / coll_ep 0.095。
  - **filter_only (gh5c0qf0)**：0→2→4→8 通关（11×level0 → 4×level2 → 18×level4 → 6×level8）但 **卡 level 8**（未到 12/16）；final eval @8 arrival 0.008 / coll_ep 0.033。较 v2（卡 4）有进步——0 障首级 bootstrap 生效，但 24M 仍不够冲到 16。
  - **dual (04ykbpii)**：0→2→4 通关（14×level0 → 18×level2 → 7×level4）但 **卡 level 4**（未到 8/12/16）；final eval @4 arrival 0.006 / coll_ep 0.031。v3 中 filter_only 反而超过 dual。
- **严格单命 eval 结果（soft_respawn=false @600/1024, 固定起终点全区域, 串行跑避并行崩溃；dual/fo ON=带 filter, OFF=撤; ro/naive 天然无 filter）**：

| 臂 | 档 | ON arr/coll/joint | OFF arr/coll/joint |
|---|---|---|---|
| dual | 4(实际档) | 0.006/1.9%/0.005 | 0.019/7.9%/0.017 |
| dual | 8 | 0.007/1.9%/0.006 | — |
| dual | 16 | 0.041/4.4%/0.039 | 0.090/27.1%/0.060 |
| fo | 8(实际档) | 0.041/1.7%/0.035 | 0.054/9.3%/0.049 |
| fo | 16 | 0.096/2.7%/**0.087** | 0.099/21.3%/0.058 |
| ro | 2(实际档) | — | 0.007/2.1%/0.007 |
| ro | 8 | — | 0.030/8.2%/0.025 |
| ro | 16 | — | 0.063/17.4%/0.043 |
| naive | 2(实际档) | — | 0.058/4.7%/0.056 |
| naive | 8 | — | 0.069/15.5%/0.058 |
| naive | 16 | — | 0.097/31.8%/0.056 |

- eval 解读：①**绝对值普遍低（arrival<10%）**——固定 5m 穿越 + 稠密障碍对 from-scratch v3 模型（最高只到 4/8 档）仍是硬任务，未冲过 12/16 档 → 严格单命下无法可靠穿越，数字低于旧 F1（随机起终点 0.9+）是任务难度的如实反映。②**runtime CBF filter 依旧决定性安全组件**：撤 filter 后 coll 从 ~2–4% 暴涨到 21–32%（~6–8×），Arena1 同样成立。③**v3 中 fo > dual 贯穿训练与 eval**（fo@16 ON joint 0.087 > dual 0.039；OFF coll fo 21.3% < dual 27.1%）。④naive@16 coll 31.8% 最高（无安全学习、纯靠乱撞换 arrival）；ro 因 w1·viol 略自保（17.4%）。⑤@16 对卡低档臂是外推压力档，数字意义有限但反映 filter 兜底价值。
- **汇报已并入 F1_4arm_report.md 末尾「附录 A · Arena1」（2026-09-07）**：含环境改动表、v3 训练档位表、严格单命 eval 表 + 图 arena1_training.png / arena1_eval_bars.png（脚本 OmniDrones/scripts/plot_arena1.py）+ A.4 结论（任务难度剧增主因 / filter 仍决定性 / fo>dual / ro-naive 无滤波卡 2 / 冲高密度方向）。本文件收尾。

## 8. 结论与后续（Arena1）
- **任务难度**：固定 5m 穿越 + 全区域稠密布障 from-scratch 远难于旧 F1 随机起终点——三版迭代（z=0.5 全卡 → z=1.0 卡 4 → +0 障首级 fo 到 8）才把带 filter 臂从「完全学不动」推到「能到 4–8 档」。24M 内冲不到 12/16。
- **四臂横向**：fo > dual > ro ≈ naive（v3）；filter 决定性安全（ON coll <5% vs OFF 21–32%）贯穿 Arena1。
- **后续可选**（需用户拍板）：①加长帧数/每档多窗口冲 12/16；②warm-start v2/v3 dual/fo ckpt（同 obs/reward 仅 fixed_init 变，warm 有效性需验证）；③DR 或 reward 微调（用户此前锁 F1 配方）。

### 2026-09-07 诊断 + 用户拍板（方向 B：respawn 一次性惩罚；评估 8obs 为主）
- **诊断**：严格单命 @实际档到达率全低（fo@8 arr 4.1%、dual@4 0.6%、ro/naive@2 <6%），但训练日志 fo 在 8 档**窗口多命 success_rate ~0.67–0.72**（arrival EMA 0.004 是"此刻在圈内"非"曾到达"）→ **多命注水 ~20×**：模型靠 600 步窗内撞了重生反复试、蹭到一次到达，严格单命一次飞不过。根因 = **判据错位（多命训练 vs 单命验收）+ 每档停留不足**，非 F1 reward 数学失效（同配方旧 F1 随机终点 12M 通关 16、单命 joint 0.94 已验证）。
- **用户拍板**：①方向 **B**——reward 微调「每次 soft-respawn 加一次性惩罚」（不动 F1 主结构），逼单次无失误穿越；②评估口径**以 8 obs 为主**、训稳后再上 16。
- **实现（commit 待回填）**：`task.reward_respawn_penalty`（默认 0 逐位兼容；建议 2~10 起步，勿大——M1 早死反比 return≈-110 前车之鉴）在 `_compute_reward_and_done` soft-respawn 分支于 `_respawn` 前对触发重生 env 扣分。语义断言 PASS + GPU 冒烟（8 障 1 iter reward_respawn_penalty=5）EXIT0。
- **指标语义澄清**：`train/stats.success_rate` = 整窗(600 步多命)内 `episode_any_arrival & 0 碰撞边沿`（soft_respawn 下一条窗可重生多次，任一命到达即可）→ fo@8 档 0.7；`stats.arrival`(EMA) = "此刻恰在目标圈内"的瞬时比例(~0.004, 非到达率)；严格单命验收 `arrival_rate` = 单命一次飞行曾到达保持 ≥50 步 → fo@8 仅 4%。**差异根源 = 多命允许"坠/出界/碰超限后重生重试"，单命一次失误即失败**；respawn 罚正是给"每丢一命"定价，逼单次飞好。
- **训练设计（用户拍板）**：四臂都训、from-scratch、`reward_respawn_penalty=5.0`、课程 levels=[0,2,4,8] 封顶 8 档（现阶段只要求 8 obs 站稳）、24M、wandb arena1 run Arena1-v4-respawn5-<arm>。**⚠️ 配方对照说明：v3 实际用 yaml 默认 edge2/near0.5（CLI 未覆盖），与旧 F1 pg6q5ji5 的 edge4/near1 不同——四臂同配方仅 respawn 罚为变量**。

### 2026-09-07 迭代 v4（reward_respawn_penalty=5.0, from-scratch [0,2,4,8] 封顶 8, 24M）
- 四臂：dual=iha3ahlu / fo=fxag6qqc / ro=34urxgyk / naive=qbx66j5u（log /tmp/navvel_arena1_v4_*_24M.log）。
- 课程轨迹：fo 0→2→4→8（11×L0→4×L2→22×L4→**2×L8**，8 档只 2 窗）、dual 0→2→4（卡 4，19×L4 未升 8）、ro/naive 卡 2——**与 v3 几乎一致，respawn 罚未让多命课程推进更快**（多命 success 本就靠重生，5/次未压过重生收益）。
- **严格单命 eval（soft_respawn=false @600/1024, 8 obs 主口径 + 各自档；ON 仅 dual/fo）**：

| 臂/档 | v3 ON joint | v4 ON joint | v3 OFF joint | v4 OFF joint |
|---|---|---|---|---|
| fo @8 | 0.035 | 0.026 | 0.049 | 0.025 |
| dual @4 | 0.005 | **0.010** | 0.017 | 0.027 |
| dual @8 | 0.006 | 0.017 | — | 0.045 |
| ro @2 | 0.007 | 0.012 | — | — |
| naive @2 | 0.056 | **0.014**(↓) | — | — |

- **判定 ❌ respawn 罚 5.0 未显著改善单命到达**：fo@8 ON 0.026（≈v3 0.035，噪声内甚至略降）；dual@4 0.010 / dual@8 0.017 仅微升（噪声级）；naive@2 反降。课程轨迹无实质推进 → **多命注水是训练/判据结构问题，单加 respawn 一次性罚不足以逆转**（模型仍靠重生蒙，罚 5 太小压不过到达 +30 与"多一条命继续试"的长期收益）。
- 后续可选：①respawn 罚加大(~20-40)或改 per-life 累积；②**训练侧改判据**（课程窗口按"单命无重生到达"算 success——彻底对齐验收）；③训练期关闭 soft_respawn 的早期档（只在接近部署密度重开多命）；④接受"filter 部署下多命到、单命难"为 Arena1 固定穿越的任务特性, 重新审视任务/到达保持/时间预算。**F1 reward 主结构未动**。





## 8. 坑与注意
1. 布局采样候选网格是笛卡尔网格（_candidate_pool），全区域 ±3 使候选数 ~1944/env，布局 CPU/GPU 开销略升（探针 N=1024 单档 ~10s 可接受）。
2. 固定起终点 → 所有 env 同 start/goal、障碍各不同 → 训练数据同目标多样布局；重生回固定起点（障碍静态故净空保证）。
3. survival z_ref=1.0：start z=0.5 低于 z_ref → 起飞段持续小罚，策略需先爬升（F1 的 v·u_goal 朝 goal z=1.5，天然驱动）。若收敛慢可留意。
4. 布局探针 feasible 为保守口径；若某些档撞到 >2% 再降密度或加走廊约束（当前不需要）。
