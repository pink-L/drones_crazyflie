# NP 批次记录：解析圆柱环境 + 论文口径 `Nominal` 臂

> 本文是 **2026-09-17 解析圆柱改造之后**的训练/评估流水账（用户要求新开文档记录）。
> 权威执行文档仍是 `NAVVEL_VERSION_AND_RETRAIN_PLAN.md`（本次改动见其 **§0.5.30**），
> 任务书是 `prompt_new_naive_env.md`。**冲突时以 plan 为准。**
>
> 每次跑完一段就往本文追加，**数字只从日志 / `agg.json` / manifest 读**，不凭记忆。

---

## 0. 本次改动的口径（与旧结果一律不可比）

| 项 | 旧（P3/P3a/P3b-1、A0–A4） | 新（本轮） |
|---|---|---|
| 障碍几何 | 柱 = 沿 z 叠 `pillar_layers` 个外接球（球堆近似） | **解析竖直圆柱**，一柱一槽 |
| 物理槽数 M | `n_pillars × layers` = 16–48 | `n_pillars` = 2/4/8/16 |
| obs 障碍块 | `K×4`，K=8 ⇒ 全 obs **62** | `K×7` = `[rpos(3), sdf, n̂(3)]`，K=4 ⇒ 全 obs **58** |
| 柱高 | 全高 `[0.4, 2.6]`（`pillar_z_range`） | **随机**：`z_lo~U[0.35,0.9]`、`z_hi~U[1.0,2.6]`，每柱 30% 为矮柱（`z_hi≤1.5`，可飞越） |
| CBF 几何 | 球：`h = ‖p−c‖ − r_safe − extra` | **有限高圆柱 SDF**；经 `cbf_geom()` 的"虚拟球"适配接入，`filter_velocity` 数学一行未改 |
| 密度机制 | `curriculum.levels` **空转**，实际密度 = `n_pillars_range` 随机 | **锁档**：一档一个 profile（`NP-<arm>-n<level>`） |

**红线/护栏**
- 🔴 obs 58 ≠ 62：旧 ckpt **必须加载失败**（`eval_ckpt.py` 已加显式护栏）。
- 🔴 冻结口径未受影响：`obstacle.shape` 默认 `sphere_stack`，球堆路径表达式逐字未改，
  4 个既有 CPU 套件改后仍全绿。
- 🔴 **导出侧必然失效**（范围外，未修）：`scripts/export_navvel_actor.py` 硬编码
  `obs_dim = 30 + 4*K + obs_safety_dim`，圆柱世界会**静默算错维度**；`K_SLOTS`、obs 布局、
  CBF 参考向量、`navvel_deploy.yaml` / `navvel_obstacles_cyl.yaml` 的 sha256 都要在部署侧同步。
  **状态：未完成、强依赖本轮结论。**

**档位阶梯（CPU 探针实测 + 首次通过率定档）**

| n | R (m) | `min_corridor` W | 首次抽签连通通过率 | 说明 |
|---|---|---|---|---|
| 2 | 0.4243 | 1.34 | 0.934 | R 保持方柱外接圆（部署保守量） |
| 4 | 0.4243 | 1.34 | 0.793 | 同上 |
| 8 | 0.4243 | 1.00 | 0.539 | **验收主档（d8 协议）**；W=1.34 在 n=8 不可行 |
| 16 | 0.30 | 0.70 | 0.656 | R 与 W 同时下调；W=0.85 首次通过率仅 0.211 ⇒ 冒烟出现 1/256 未验证布局，已弃 |

> ⚠️ n=16 档的柱比其它档**更细**（R 0.4243→0.30）⇒ 跨档比较不是单变量，已在 plan §0.5.30-⑤ 记录。

---

## 1. 代码与工具落点（commit 子模块 `510ac22`＋后续修复 / 外层 `650b7b5`）

| 文件 | 作用 |
|---|---|
| `omni_drones/envs/single/nav_vel_obstacles.py` | `cylinder_sdf_and_normal()`（连续有限高圆柱 SDF）、`cbf_geom()`（虚拟球适配）、`_sample_cylinder*()`（逐 env 粘性连通性重抽）、`_build_obs_cylinder()` |
| `omni_drones/envs/single/nav_vel.py` | `shape` 接线、Cylinder prim 创建、逐 episode `xformOp:scale` 写入（带一次性落账）、CBF 装配改走 `cbf_geom()`、obs 布局启动打印 |
| `omni_drones/utils/cbf.py` | **未改**（红线） |
| `cfg/task/NavVel.yaml` | 新增 `shape` / `cylinder_*` / `obs_sdf_norm` 键（默认 = 冻结口径） |
| `scripts/cylinder_geometry_test.py` | 16 项几何/一致性单测（含 `M<K` 回归 t9） |
| `scripts/cylinder_layout_check.py` | 布局不变量门禁 + `--ladder` 阶梯探针 + `--profile` 端到端检查 |
| `scripts/make_np_profiles.py` | 从 `A4.yaml` 生成 20 个 `NP-*.yaml`（5 臂 × 4 锁档密度） |
| `scripts/np_chain_batch.py` | **密度链驱动器**（`train_batch.py` 只能传一个 `--init-ckpt`，无法表达 per-(arm,seed) 的 warm-start 链） |
| `scripts/eval_ckpt.py` | obs 布局硬护栏 |

---

## 2. GPU 冒烟记录（2026-09-17，全部通过）

`max_iters=60`（覆盖 T=1500 的 episode 重置 ⇒ 走到逐 episode scale 写入），`+render_eval=false`，
`wandb.mode=disabled`（不污染正式项目）。

| # | 命令要点 | 结果 | 关键日志行 |
|---|---|---|---|
| A | `NP-nominal-paper-n8`, 128 envs | exit=0，**0 WARN**，ckpt 已写 | `cylinder world: M=8 Cylinder prims (phys radius 0.4 m, base height 0.5 m …)`<br>`obs layout: … K=4 slot_dim=7 … total obs 58`<br>`z-scale writes: envs=128 M=8 wrote=1024 invalid_prim=0 missing_xformOp:scale=0 (z-scales 1.00..4.39)` |
| B | `NP-dual-p1-n16`, 256 envs（CBF filter 路径） | exit=0 | `M=16 Cylinder prims (phys radius 0.3 m …)`；`cbf_violation 0.003–0.043`、`cbf_corr ≤1.1e-2`（无爆炸/NaN） |
| B2 | 同上，W=0.85→**0.70** 后重跑 | exit=0，**0 WARN** | 未验证布局告警消失 ⇒ 阶梯改档生效 |
| C | `NP-dual-p0-n8`, 128 envs（p=0 软蒸馏路径） | exit=0，**0 WARN** | `term_cbf_viol ≈ −2.4e-3`、`term_cbf_corr ≈ −2.4e-3`（有限、量级正常） |

**结论**：四个密度档 + 三种 CBF 配置（none / hybrid-p1 / hybrid-p0）都能在 GPU 上建环境、
跑满一个 episode、写 checkpoint；Cylinder prim 与逐 episode `xformOp:scale` 均为**已验证路径**
（`wrote = envs × M`，0 缺失）。

**残留风险 R1（已设计规避、尚未目视确认）**：`sim.replicate_physics=true` 下 PhysX 可能不跟随
per-clone `xformOp:scale`。规避方式是**把物理 prim 基准高度设为最矮柱高（0.5 m）**，于是过期
碰撞体永远落在逻辑圆柱**内部**，不会挡住合法飞越；且障碍接触本就不是终止判据。**待 GUI 演示确认。**

---

## 3. 冒烟过程中抓到的 3 个问题（都已修）

| # | 问题 | 症状 | 修法 |
|---|---|---|---|
| 1 | `M < K` 时窗口补齐列越界 | `_build_obs_cylinder` 在 n=2/n=4 档崩：`index 3 is out of bounds for dimension 1 with size 2`（n=8/n=16 冒烟看不出来，是 CPU 布局探针跑 n=2 才暴露的） | `idx.clamp(min=0, max=self.M-1)` + 新增单测 t9（n=2/n=4） |
| 2 | 密度链驱动器 **fork bomb** | 我构造了子进程 `env`（含 `NP_CHAIN_CHILD=1`）却**忘了传给 `Popen`** ⇒ 子进程重入调度器、再启子进程，10 个空转进程、GPU 无任何负载 | `Popen(..., env=child_env, cwd=TB.HERE)` + 启动前 `assert` 标记存在 |
| 3 | n=16 档门禁过紧 | W=0.85 首次通过率仅 0.211 ⇒ 粘性重抽 15 轮后仍有 1/256（1024 env 约 4 个）落回**未验证布局** | 按"首次通过率 ≥ ~0.5"重选 W=0.70（0.656），并把这个判据写进 `make_np_profiles.py` |

> 教训（值得记）：**冒烟只覆盖 n=8/n=16 ⇒ 漏掉了最低两档的越界 bug**；以后新代码路径的冒烟要
> 覆盖**参数区间的两端**（最小/最大密度），而不是挑一个中间值。

---

## 4. 训练批次配置

- **臂**：`nominal-paper`（论文 `Nominal`）、`obs-proximity`（旧 `naive` 正名）、`dual-p0`（论文 `Reward Only`）、`dual-p1`（论文 `Dual`）
  （可选第 5 臂 `filter-only-p1` = 论文 `Filter Only`；本轮先跑 4 臂）
- **密度链**：n = 2 → 4 → 8 → 16，**顺序 warm-start**（每档 profile 锁死，链式等价于任务书要的 2→4→8→16 课程；
  用户 2026-09-17 裁决"不做在线升档"）。**n=2 档是真正的 from-scratch**（`nominal_paper` 不许 warm 自 A4）。
- **seed**：11 / 12 / 13（3 seed 起步；`nominal-paper` 视 from-scratch 表现补到 5）
- **帧数**：每档 10M frames（104 迭代 @1024 envs），`save_interval=100`
- **并行**：2 条链（=2 个 Isaac 进程，`--parallel 2` 是硬上限）
- **wandb**：project `env_design_cyl`，group `NavVel-NP-<arm>`，run_name `cfb-cyl-<arm>-s<seed>-n<level>-final`
- **实测吞吐**：~59k frames/s（1024 envs，单 run，自测）⇒ 每档 ≈ 170 s + 启动 ≈ 220 s，
  48 档 ÷ 2 并行 ≈ **1.5 h**
- **启动命令**：
  ```bash
  cd OmniDrones/scripts
  /home/hybrid/miniconda3/envs/lz_env/bin/python np_chain_batch.py \
    --arms nominal-paper obs-proximity dual-p0 dual-p1 \
    --levels 2 4 8 16 --seeds 11 12 13 --parallel 2 \
    --project env_design_cyl --frames-per-level 10000000 \
    --logdir /tmp/navvel_np
  ```
- **自测**（驱动器验证，独立项目，2 个 400k 帧的小 run）：project `np_chain_selftest`，
  run `run-20260917_221633-5wuz1a0l`(n2) / `run-20260917_221740-o637mm9h`(n4)，
  证明链式 warm-start 与 ckpt 发现可用。

**产物清单**：`/tmp/navvel_np/np_chain_manifest.json`（每档 arm/seed/level/ok/ckpt/sha256/wandb_run/耗时），
每档训练日志 `/tmp/navvel_np/train_<arm>_s<seed>_n<level>.log`，每条链日志 `/tmp/navvel_np/chain_<arm>_s<seed>.log`。

---

## 5. 训练结果（跑完后回填）

> 数据源：`/tmp/navvel_np/np_chain_manifest.json` + wandb project `env_design_cyl`。

| 臂 | seed | n=2 | n=4 | n=8 | n=16 | 备注 |
|---|---|---|---|---|---|---|
| nominal-paper | 11 |  |  |  |  | |
| nominal-paper | 12 |  |  |  |  | |
| nominal-paper | 13 |  |  |  |  | |
| obs-proximity | 11 |  |  |  |  | |
| obs-proximity | 12 |  |  |  |  | |
| obs-proximity | 13 |  |  |  |  | |
| dual-p0 | 11 |  |  |  |  | |
| dual-p0 | 12 |  |  |  |  | |
| dual-p0 | 13 |  |  |  |  | |
| dual-p1 | 11 |  |  |  |  | |
| dual-p1 | 12 |  |  |  |  | |
| dual-p1 | 13 |  |  |  |  | |

**训练期必看曲线**（任务书 §3.1 的 from-scratch 风险判据）
- `pos_error`：**若 5M 帧内不下降 ⇒ 停**，先做单变量诊断（密度/熵/奖励量级），**不许加权重**。
- `entropy` / `std(a)`：是否塌缩（历史前科见 `/memories/repo/navvel-nr1.md`）。
- `stats.arrival`、`stats.collision_episodes`、`term_obstacle_*` 分项。

---

## 6. 验收（跑完后回填）

协议（**冻结，不许改**）：`512×600`（对齐）+ `384×1500`（收口）+ **d8 密度协议**（`384×1500` + n=8），
每 ckpt × ON/OFF；`set_seed = 1000 + train_seed`；判"跑成功"看日志里的 `[eval_metrics]` 行**不是 exit code**；
两列数字**永不混表**，报告必须标 `rollout_steps`。

| 指标 | 门槛（plan §4.2/§4.3） | 本轮结果 |
|---|---|---|
| ON/OFF 到达率 @0.2 | 阶段 1：ON ≥0.85；阶段 2：ON 与 OFF **均** ≥0.85 | |
| filter 依赖度 = arr_OFF/arr_ON | ≥0.95 | |
| 0 碰 / 0 OOB | **必须**（ON 与 OFF 都要） | |
| `h_min^train` | ≥0 | |
| `dropped_relevant_frac` | **<1%**（K=4 的风险点，d8/d16 必测） | |
| stall 占比 | ≤10% | |

**本批次要回答的 3 个问题**（任务书 §3.2）
1. `nominal_paper` 能否**从零**学会避障？（对照 `obs_proximity` ⇒ 差值 = proximity 塑形的贡献）
2. `dual-p0`（Reward Only）在**新圆柱环境**下是否仍是撤-filter 最优？
3. 撤 filter（OFF 列）时，有没有**任何臂**能同时满足"高到达 + 0 碰"？

---

## 7. 待办 / 风险

- [ ] 训练批次 48 档（进行中）
- [ ] 训练期曲线检查（§5 的 from-scratch 判据；`nominal-paper` 每档都要看）
- [ ] 双协议 + d8 验收（§6）
- [ ] `dropped_relevant_frac` 在 n=8 / n=16 档上报（K=4 的风险点）
- [ ] 目视确认 R1（物理圆柱高度是否跟随 per-episode scale）
- [ ] 导出侧同步（**范围外**，与用户确认后再做）
- [ ] 结论写回 plan（新开 `§0.5.31`），**包括失败与"无法区分"的结论**
