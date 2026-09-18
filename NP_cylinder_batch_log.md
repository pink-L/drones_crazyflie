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
| 4 | **并行链互相杀**（2026-09-17 首次开批次后 8 分钟） | `chain_nominal-paper_s12.log` 写着 `post-run(s12 n2): killing 1 leftover GPU process(es): [1535144]`，而 **1535144 是 s11 的 train.py** ⇒ s11 的 n2 虽已写出 ckpt（ok=True）但随后的 n4 在 **5 秒**内被 SIGKILL，链中断。根因：**子进程把 `NAVVEL_BATCH_ROOT` 覆盖成了自己的 pid**，于是 `clear_gpu()` 的"兄弟保护"退化成"只保护自己人"，两条链互杀 | 只在**顶层**父进程设置 `NAVVEL_BATCH_ROOT`（子进程不覆盖）；并用 **2 条链并行**的自测（`--parallel 2`）复现验证——**上一版自测用的是 `--parallel 1`，没有兄弟，所以漏掉了** |
| 5 | `--resume` 形同虚设 | 父进程打印 `resume: 2 stage(s) already ok`，但子进程仍从 **n2 重跑** | 子进程读的是**自己那份**（刚被清空的）链清单 ⇒ 新增 `--done-from <父清单>`；实测 `resume: nominal-paper s11 n2 already ok -> …` 后才起 n4 |
| 6 | 中断即丢进度 | 父进程启动时**删掉**子清单，而父清单只在"整条链结束"时才汇总 ⇒ 被 kill 时中间档的成果丢失（s12/n2 就是这么丢的，白跑一档） | 不再删子清单；父进程**启动时自动合并**子清单（按 (arm,seed,level) 去重、保留最新） |
| 7 | **台账静默漏行**（批次结束后才暴露） | 子清单文件名只按 **seed** 命名（`.child_manifest_s<seed>.json`），而队列是 seed 优先 ⇒ **同一波里两条同 seed 的链写同一个文件、互相覆盖** ⇒ `dual-p1 s13` 的 **4 档记录全丢**（训练本身正常，4 个 ckpt 都在磁盘上）。汇总还因此报出"56/57"这种看不懂的数 | ① 文件名改成 `.child_manifest_{arm}_s{seed}.json`；② 新增 `scripts/np_manifest_rebuild.py`：**从 wandb run dir 重建台账**（磁盘是真相，台账可丢），并按 project + seed 过滤（否则把 selftest 的 8 档 noise 也扫进来）。重建结果：**60 档 / 全 ok**（其中 5 档标记 `recovered=true`） |

> 教训（值得记四条）：
> 1. **冒烟只覆盖 n=8/n=16 ⇒ 漏掉了最低两档的越界 bug**；新代码路径的冒烟要覆盖**参数区间两端**。
> 2. **自测要用生产配置**：驱动器自测当初用 `--parallel 1`（无兄弟进程）⇒ 兄弟互杀的 bug 没暴露；
>    改成 `--parallel 2` 复现后才修掉。**"能跑通"与"能在并线下跑通"是两个命题。**
> 3. **"我已经实现了 X 功能"要验证 X 真的发生**：`--resume` 打印了正确的提示却**不起作用**——
>    标志位写对了、路径搞错了。凡"跳过/复用"类逻辑，必须看到**被跳过的那一项**出现在日志里。
> 4. **台账不能是唯一副本**：任何"汇总表"都必须能从**不可丢的东西**（磁盘上的产物）重建。
>    键（文件名）要包含**全部区分维度**——按 seed 命名却在同一 seed 下并行两条链，是设计错误而非运气问题。

---

## 4. 训练批次配置

- **臂（5 个，2026-09-17 用户追加第 5 臂）**：`nominal-paper`（论文 `Nominal`）、`obs-proximity`（旧 `naive` 正名）、
  `dual-p0`（论文 `Reward Only`）、`dual-p1`（论文 `Dual`）、`filter-only-p1`（论文 `Filter Only`）
- **档数**：5 臂 × 4 锁档密度 × 3 seed = **60 档**
- **队列顺序 = seed 优先**（`for s in seeds: for arm in arms`）：先让**5 个臂各跑完一条 s11 链**
  （≈1 h）⇒ 中期就能拿到 5 臂的完整密度阶梯做对照，而不是先跑完一个臂等 2 h。
- **密度链**：n = 2 → 4 → 8 → 16，**顺序 warm-start**（每档 profile 锁死，链式等价于任务书要的 2→4→8→16 课程；
  用户 2026-09-17 裁决"不做在线升档"）。**n=2 档是真正的 from-scratch**（`nominal_paper` 不许 warm 自 A4）。
- **seed**：11 / 12 / 13（3 seed 起步；`nominal-paper` 视 from-scratch 表现补到 5）
- **帧数**：每档 10M frames（104 迭代 @1024 envs），`save_interval=100`
- **并行**：2 条链（=2 个 Isaac 进程，`--parallel 2` 是硬上限）
- **wandb**：project `env_design_cyl`，group `NavVel-NP-<arm>`，run_name `cfb-cyl-<arm>-s<seed>-n<level>-final`
- **实测吞吐**：~46–61k frames/s（1024 envs；**每档实测 ≈350 s**：s11/n2 = 353 s、s12/n2 = 349 s，含启动与 teardown）
  ⇒ 60 档中已复用 2 档（`--resume`）⇒ 剩 58 档 ÷ 2 并行 ≈ **2.8 h**（预计 **2026-09-18 01:40 前后**跑完）
- **启动命令**：
  ```bash
  cd OmniDrones/scripts
  /home/hybrid/miniconda3/envs/lz_env/bin/python np_chain_batch.py \
    --arms nominal-paper obs-proximity dual-p0 dual-p1 \
    --levels 2 4 8 16 --seeds 11 12 13 --parallel 2 \
    --project env_design_cyl --frames-per-level 10000000 \
    --logdir /tmp/navvel_np --resume
  ```
- **开训历史（诚实记录）**：
  1. 22:19 首次启动 → 22:27 发现**并行链互杀**（§3 问题 4），主动停机止损（损失 1 档 n2 的 GPU 时间，
     该档 ckpt 已写出且被 `--resume` 复用）；
  2. 修好后先跑 **2 条链并行**自测（`--parallel 2`、8 档）→ **8/8 ok、0 次互杀**；
  3. 22:5x 用 `--resume` 重启正式批次。
- **自测**（驱动器验证）：project `np_chain_selftest`。①单链 2 档（`run-20260917_221633-5wuz1a0l`
  n2 / `run-20260917_221740-o637mm9h` n4）证明链式 warm-start 与 ckpt 发现；
  ②**双链并行 8 档**证明兄弟保护（这是暴露互杀 bug 的配置）。

**产物清单**：`/tmp/navvel_np/np_chain_manifest.json`（每档 arm/seed/level/ok/ckpt/sha256/wandb_run/耗时），
每档训练日志 `/tmp/navvel_np/train_<arm>_s<seed>_n<level>.log`，每条链日志 `/tmp/navvel_np/chain_<arm>_s<seed>.log`。

---

## 5. 训练结果（✅ 60/60 档产出 checkpoint；台账已按磁盘重建）

**批次结束**：2026-09-18 **01:49**（15 条链全部 rc=0；预测区间 01:40–02:10 ✓）。
**台账**：`/tmp/navvel_np/np_chain_manifest.json`（60 档全 ok，其中 5 档标 `recovered=true`）。
**逐档汇总**：`/tmp/navvel_np/train_summary.txt`（由 `scripts/np_train_summary.py` 从 wandb run dir 的
`files/output.log` 解析，纯 CPU；日志里只有 `entropy` 是逐迭代的，`pos_error` 被 tqdm 截断 ⇒ 不进文本）。

### 5.1 训练末值（最后一个 `train/stats` 块，3 seed 均值）

| 臂 | n | arrival | success | coll_ep | min_clr | **entropy(末)** | cbf_viol |
|---|---|---|---|---|---|---|---|
| nominal-paper | 2 | 0.723 | 0.723 | 0.000 | 1.842 | **8.027** | 0 |
| nominal-paper | 4 | 0.520 | 0.520 | 0.000 | 1.013 | **8.027** | 0 |
| nominal-paper | 8 | 0.365 | 0.365 | 0.000 | 0.543 | **8.027** | 0 |
| nominal-paper | 16 | 0.248 | 0.248 | 0.000 | 0.307 | **8.027** | 0 |
| obs-proximity | 2 | 0.697 | 0.697 | 0.000 | 1.806 | **8.027** | 0 |
| obs-proximity | 4 | 0.529 | 0.529 | 0.000 | 1.043 | **8.027** | 0 |
| obs-proximity | 8 | 0.397 | 0.397 | 0.000 | 0.566 | **8.027** | 0 |
| obs-proximity | 16 | 0.261 | 0.261 | 0.000 | 0.312 | **8.027** | 0 |
| dual-p0 | 2 | 0.225 | 0.225 | 0.000 | 1.831 | 0.873 | 0.186 |
| dual-p0 | 4 | 0.375 | 0.375 | 0.000 | 1.062 | 1.684 | 0.469 |
| dual-p0 | 8 | 0.293 | 0.293 | 0.000 | 0.582 | 2.055 | 0.660 |
| dual-p0 | 16 | 0.206 | 0.206 | 0.000 | 0.360 | 2.404 | 0.847 |
| dual-p1 | 2 | 0.225 | 0.225 | 0.000 | 1.946 | 0.481 | 0.050 |
| dual-p1 | 4 | 0.750 | 0.750 | 0.000 | 1.560 | 1.300 | 0.123 |
| dual-p1 | 8 | 0.668 | 0.668 | 0.000 | 0.861 | 1.296 | 0.289 |
| dual-p1 | 16 | 0.565 | 0.565 | 0.000 | 0.596 | 1.542 | 0.376 |
| filter-only-p1 | 2 | 0.641 | 0.641 | 0.000 | 2.286 | 0.749 | 0.096 |
| filter-only-p1 | 4 | 0.828 | 0.828 | 0.000 | 1.536 | 0.867 | 0.205 |
| filter-only-p1 | 8 | 0.648 | 0.648 | 0.000 | 0.834 | 1.207 | 0.571 |
| filter-only-p1 | 16 | 0.561 | 0.561 | 0.000 | 0.552 | 1.602 | 0.817 |

⚠️ 这些是**训练时（带探索噪声）**的 episode 级数值，**不是验收值**；确定性验收（贪心）才能回答 §6 的 3 个问题。

### 5.2 ⚠️ 关键异常：两个非 CBF 臂的策略 std 被钉在**上限**

`nominal-paper` 与 `obs-proximity` 的 entropy 在 n4/n8/n16 档**恒为 8.027**（与 seed、与档位无关）。
验算：4 维高斯在 std = clamp 上限 1.8 时的熵 $=4\times\frac{1}{2}\ln(2\pi e\cdot1.8^2)=\mathbf{8.027}$ —— **完全相等**。
⇒ 这两个臂的探索噪声从 n4 档起顶死在上限（1.8 m/s）；三个 CBF 臂则稳定在 std≈0.6–0.9（熵 1.2–2.4）。

- **机制候选（待单变量诊断；任务书明令不许先扫权重）**：`algo.entropy_coef=0.05` 继承自旧批次，
  那些批次靠很强的 `w_f` 前进 shaping 与熵奖励抗衡；论文口径的 `Nominal` 只有**稀疏碰撞惩罚**，
  于是熵奖励占主导、把策略推向上限噪声。
- **必须先看确定性验收**：std=1.8 时训练侧 arrival 被噪声主导，贪心均值的表现可能明显不同。
- **不要**据此立刻改 `entropy_coef` 重跑 —— 先确认（a）确定性到达率是否也已受损，（b）是不是
  「std 大但均值策略仍能飞」的假警报，再决定是否做单变量对照。

### 5.3 其他观察（待验收确认，不得当作结论）

- 全部 60 档 `collision_episodes = 0.000`：失败几乎都是**超时**而非碰撞；min_clearance 随密度下降
  （n16 ≈ 0.31 m）。**但**这也可能意味着策略根本不接近障碍（"绕远"而非"避障"）—— 需用验收的
  `min d_min` / 路径长度比 / `dropped_relevant` 去区分。
- arrival 随密度单调下降（所有臂一致）⇒ 难度阶梯生效，不是自旋/卡死。
- 训练侧 `nominal-paper` 与 `obs-proximity` 差别很小（n8: 0.365 vs 0.397；n16: 0.248 vs 0.261）
  ⇒ 本轮 proximity 塑形在训练侧没拉开差距（与 P3b-1 的叙事不同，但那批是 warm-start + 另一套奖励口径）。

**训练期必看曲线**（任务书 §3.1 的 from-scratch 风险判据，本节已按其执行）
- `pos_error`：日志里不可得（tqdm 截断）⇒ **改用确定性验收 + 中途 ckpt**（`checkpoint_3309568`≈3.3M 帧）。
- `entropy` / `std(a)`：见 §5.2 —— **不是塌缩，而是顶到上限**（历史前科是塌缩，方向相反）。
- `stats.arrival`、`stats.collision_episodes`、`term_obstacle_*`：见表。

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

### 6.1 🔴 开跑验收前的阻塞点（必须先解决）

`scripts/acceptance_eval.py` 把 `--profile profiles/A0-legacy` 当作**固定几何快照**，
那是**球堆口径（obs 62）**，与本批次的圆柱 ckpt（obs 58，且每臂/每档的 profile 都不同）**不兼容**——
`eval_ckpt.py` 的 obs 护栏会直接报错（这正是它存在的意义）。

⇒ 本批次的验收需要一个**按 ckpt 的 (arm, level) 逐个换 profile** 的驱动
（`profiles/NP-<arm>-n<level>`），并且要同时跑两个协议（`512×600` 对齐 + `384×1500` 收口）× ON/OFF。
**方案（用户已批准，已实现）**：新增 `scripts/np_acceptance_eval.py`（复用 `acceptance_eval.py` 的 spec 构造与 VRAM 守卫，
profile 变为 **per-spec**，日志 tag 含 arm+level 以避免撞名，按 seed 串行执行并在每个 seed 收尾时落一张对比表，
最后合并三 seed 求均值 + 报**种子极差**）。先只跑**有区分度的切片**回答上面 3 个问题：

- **切片 A（先跑）**：n=8（= P3b-1 的 d8 协议，唯一有区分度）+ n=16（诊断档），5 臂 × 3 seed × {ON,OFF}，
  `--num-envs 384 --steps 1500` ⇒ **60 次 eval**（串行，不能并行冷启动多个 Isaac：历史教训）；
- **切片 B（按需）**：n=2/n=4（低保真，预期饱和）+ `512×600` 对齐列；
- 必测 `dropped_relevant_frac`（K=4 风险点，n=8 与 n=16 都要报）。

### 6.2 🔴🔴 2026-09-18 08:23 环境事故：系统自动升级驱动，**CUDA 全线不可用**（与本次改动无关）

**现象**：`nvidia-smi` → `Failed to initialize NVML: Driver/library version mismatch`（NVML 库 580.178）；
torch → `cuda_available=False`，`Error 804: forward compatibility was attempted on non supported HW`。

**证据链（三件套版本错位，升级发生在训练批次结束之后，所以 §5 的训练结果不受影响）**：

| 组件 | 版本 | 来源 |
|---|---|---|
| 已加载内核模块 | `580.173.02` | 9/4 00:51 开机时载入（升级前） |
| 磁盘上 dkms 模块 | `580.178.04` | 升级后（`nvidia-dkms-580-open`） |
| 用户态 `libcuda` / `libnvidia-ml` | `580.178.04` | 升级后 |

`/var/log/apt/history.log` 2026-09-18 06:16:17–06:18:03：`unattended-upgrade` 把整条 NVIDIA 栈
（`libnvidia-*`、`nvidia-utils-580`、`nvidia-driver-580-open`、`nvidia-dkms-580-open`、`nvidia-kernel-source-580-open`）
从 `580.173.02` 升到 `580.178.04`，替换了 `nvidia-firmware-580`；同批还升级了 `libc6` 并写了 `/var/run/reboot-required`。
新模块已落盘，但**旧模块仍在运行**，用户态（178）与内核态（173）不匹配 ⇒ NVML 拒绝服务、CUDA 报 804。

**影响**：切片 A 的 60 次 eval **一次也跑不了**（不是配置问题）。**没有任何东西丢失**：3 个 seed × 5 臂 × 4 档 = 60 个 ckpt 在盘上、
`np_chain_manifest.json` 完好、验收驱动已写好并自检通过 ⇒ GPU 一恢复即可一条命令开跑。

**为什么不能在这边修**：需要加载 178 版内核模块，等价于 `rmmod/modprobe nvidia*`（root，且会杀掉使用 GPU 的显示会话）或重启。
两条路都触碰「不重启服务器」的红线，**必须由用户决定**，我不做特权操作。

**顺带修掉的自身缺陷（已在本机自检）**：`np_acceptance_eval.py` 的 GPU 预检原先直接 grep `nvidia-smi` 输出，
会把 NVML 的报错文本当成 PID 而误报「GPU is busy」。现在预检区分三种状态并在故障时给出精确诊断：

```
[np_eval] FATAL: NVML is broken - nvidia-smi says:
    Failed to initialize NVML: Driver/library version mismatch
  loaded kernel module = 580.173.02, userspace libcuda = 580.178.04
```

**教训（值得留档）**：① `unattended-upgrade` 会在训练任务之间悄悄换掉整条驱动栈——批次跑完与开验收之间必须做一次 GPU 预检，
而不是假定「刚才还好」；② 任何 GPU 忙检测都必须解析**数字 PID**并单独处理 NVML 故障，否则会把环境故障误报成资源占用；
③ 报「CUDA 不可用」时必须同时打印**内核模块版本 vs 用户态库版本**，否则无法与「卡被别人占用/显存不足」区分；
④ 自检必须在**真实环境**下跑一次（这次靠 `--preflight-only` 才发现守卫本身有 bug）。

### 6.3 驱动恢复后的开跑流程（用户 2026-09-18 已确认：先回归、再开切片 A）

用户裁决：① 稍后自行重启机器，恢复后通知我；② **开 60 次之前先做环境回归**（重启换驱动属环境变更，
必须先确认 obs 58 的圆柱世界仍能建起来）。恢复后的固定动作：

```bash
cd /home/lz/lzspace/drones/OmniDrones/scripts
# 1) 预检：NVML 正常 + torch 能看到卡，否则立即停（不要硬跑）
python np_acceptance_eval.py --preflight-only
#   期望：preflight: torch 2.7.0+cu128 cuda True | GPU free
# 2) 前置条件复核（不碰 GPU）：60 条 spec 的 profile 与 ckpt 逐条核对
python np_acceptance_eval.py --plan
# 3) 环境回归冒烟：1 臂 × 1 档 × 1 seed × ON/OFF，小规模，只验管线与 obs 宽度
python np_acceptance_eval.py --arms nominal-paper --levels 8 --seeds 11 \
       --num-envs 64 --steps 200 --outdir /tmp/navvel_np/eval_smoke
#   期望：2/2 产出 [eval_metrics]，日志里 obs layout 为该档的 slot_dim/K，
#         冒烟数字不得进入任何结论（规模不符协议）
# 4) 切片 A 正式开跑（60 次，串行；驱动自带每轮 progress/ETA）
python np_acceptance_eval.py --num-envs 384 --steps 1500 \
       --outdir /tmp/navvel_np/eval 2>&1 | tee /tmp/navvel_np/eval/driver.log
```

产物：`/tmp/navvel_np/eval/<tag>.log`（每次一个）、`eval_seed_tables.md`（每 seed 一节，跑完即落）、
`rows_seed<seed>.json`、`rows_all.json`（三 seed 合并的原始指标，供复核）。

---

## 7. 待办 / 风险

- [x] 训练批次 **60 档**（2026-09-18 01:49 完成，60/60 产出 ckpt）
- [x] 训练期曲线检查（§5；结论：**没塌缩，但两个非 CBF 臂 std 顶到上限**）
- [x] 台账修复（§3 问题 7：`np_manifest_rebuild.py` 从磁盘重建，60 档全 ok）
- [x] 验收驱动 `scripts/np_acceptance_eval.py`（per-spec profile + 按 seed 分组的对比表 + 三 seed 合并；自检通过）
- [ ] **验收**（§6）：🔴 **被环境阻塞**——2026-09-18 06:16 `unattended-upgrade` 升级驱动栈，CUDA 当前不可用（§6.2）
- [ ] `dropped_relevant_frac` 在 n=8 / n=16 档上报（K=4 的风险点）
- [ ] §5.2 的 std 上限问题做**单变量诊断**（先看确定性验收再决定，不许先扫权重）
- [ ] 目视确认 R1（物理圆柱高度是否跟随 per-episode scale）
- [ ] 导出侧同步（**范围外**，与用户确认后再做）
- [ ] 结论写回 plan（新开 `§0.5.31`），**包括失败与"无法区分"的结论**
