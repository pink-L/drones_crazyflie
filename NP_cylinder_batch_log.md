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
- `pos_error`：~~日志里不可得（tqdm 截断）~~ —— **❗ 2026-09-18 更正：这个说法是错的**。
  `pos_error` **就在 `train/stats` 块里**（`np_train_summary.py` 的 `BLOCK_RE` 能直接解析，见 §5.4），
  当时只看了 tqdm 的 postfix 就下了结论。⇒ 训练期 from-scratch 判据**本来就可判**，无需等到验收。
- `entropy` / `std(a)`：见 §5.2 —— **不是塌缩，而是顶到上限**（历史前科是塌缩，方向相反）。
- `stats.arrival`、`stats.collision_episodes`、`term_obstacle_*`：见表。

### 5.4 逐 seed 训练末值（2026-09-18 补；含 `dual-p0` 崩坏的训练期溯源）

完整表：`/tmp/navvel_np/train_per_seed.txt`（解析脚本不改仓库，直接复用 `np_train_summary.parse_stage`）。

**① `dual-p0` 的 seed 13 在训练期就已经异常**（与 §6.5 的验收崩坏同一 seed）：

| 臂 | n | seed | arrival | `pos_error` | `cbf_violation` | entropy(末) |
|---|---|---|---|---|---|---|
| dual-p0 | 8 | 11 | 0.335 | 2.72 | 0.471 | 1.427 |
| dual-p0 | 8 | 12 | 0.418 | 2.46 | 0.748 | 1.701 |
| dual-p0 | 8 | **13** | **0.126** | 2.56 | 0.760 | **3.037** |
| dual-p0 | 16 | 11 | 0.288 | 3.22 | 0.377 | 1.648 |
| dual-p0 | 16 | 12 | 0.262 | 3.35 | 1.142 | 1.915 |
| dual-p0 | 16 | **13** | **0.069** | 3.22 | 1.021 | **3.648** |

⇒ s13 的训练末到达率只有同臂另两个 seed 的 **1/3–1/4**，且其 entropy **明显高于**同臂其他 seed
（3.0–3.6 vs 1.4–1.9）。对照 §5.2：两个非 CBF 臂的 entropy 是**顶到上限 8.027**，而 s13 是**没收敛到低噪声**。
⇒ 这是「**训练不收敛/不稳定**」，不是「验收时的偶发失败」——**验收崩坏可以从训练日志提前预警**。

**② 三个 `dual-*` / `filter-only` 臂确实带着 proximity 塑形（量化证据）**
`train/stats` 里逐项奖励可见（n8 为例，末值）：`nominal-paper` 的 `term_obs_log = 0.0000`（权重 0 ⇒ 无贡献），
而 `obs-proximity` ≈ 0.50–0.58、`dual-p0` ≈ 0.48–0.66、`dual-p1`/`filter-only-p1` 同量级
⇒ **本批次三个 CBF 臂每条 episode 的回报里约 +0.5 来自 `r_obs_log`（外加 `term_near_slow` ≈ −0.18）**，
这正是用户要求剥离的对象（见 §8 新批次）。

---

## 6. 验收（跑完后回填）

协议（**冻结，不许改**）：`512×600`（对齐）+ `384×1500`（收口）+ **d8 密度协议**（`384×1500` + n=8），
每 ckpt × ON/OFF；`set_seed = 1000 + train_seed`；判"跑成功"看日志里的 `[eval_metrics]` 行**不是 exit code**；
两列数字**永不混表**，报告必须标 `rollout_steps`。

| 指标 | 门槛（plan §4.2/§4.3） | 本轮结果（切片 A，3 seed） |
|---|---|---|
| ON 到达率 @0.2 | 阶段 1：ON ≥0.85 | **仅 3 行过线**：`dual-p1` n8 0.966、`dual-p1` n16 0.854、`filter-only-p1` n8 0.893；其余 7 行 FAIL（最低 `nominal-paper` n16 0.462） |
| OFF 到达率 @0.2 | 阶段 2：ON 与 OFF **均** ≥0.85 | **10 行全部 FAIL**（最高 OFF = `dual-p1` n8 0.652） |
| filter 依赖度 = arr_OFF/arr_ON | ≥0.95 | **10 行全部 FAIL**（滤波臂 0.22–0.67）⇒ 滤波器对到达率是**决定性**的 |
| 零介入率 | ≥0.95 | **全部 FAIL**（0.34–0.65）⇒ **没有任何臂可以撤 filter** |
| 0 碰（ON） | **必须** | ✅ 滤波三臂 n8/n16 全 0；`obs-proximity` 全 0；**`nominal-paper` 不满足**（n8 0.33 / n16 2.67） |
| 0 碰（OFF） | **必须** | ❌ 滤波三臂坏：`dual-p0` n8 1.00/n16 0.67、`dual-p1` n8 0/n16 3.33、`filter-only-p1` n8 0/n16 5.00 |
| 0 OOB / 0 crash | **必须** | ✅ 60/60 全 0 |
| `h_min^train` | ≥0 | ✅ 滤波臂恒 0.12（`mode=none` 臂无此量 ⇒ n/a） |
| `dropped_relevant_frac` | **<1%**（K=4 风险点） | ✅ 逐条精确 0；最差 `dropped_step` 0.008（`filter-only-p1` n16）⇒ **K=4 未丢障碍** |
| stall 占比 | ≤10% | ✅ 最大 0.026 |

> **总判定：不通过 ❌**（10 个 (arm, level) 行全部 FAIL）。但失败集中在**到达率/可撤性**上，
> **安全（0 碰 / 0 OOB / 0 crash）在 ON 侧全面成立**；OFF 侧的碰撞与到达率崩塌说明滤波器是安全与任务的
> **共同依赖**。
> ⚠️ **口径警告**：本表数字来自 `384×1500` + `fixed_init=[-2.8,0,0.5] → fixed_target=[2.8,0,1]`，
> 与训练期 `train/stats` 的到达率（随机起终点分布，如 `nominal-paper` 0.365）**不同口径，永不混表**。

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

### 6.4 驱动恢复后的环境回归（2026-09-18 09:0x，全部通过）

| 步骤 | 结果 |
|---|---|
| 驱动版本 | 内核态 `580.178.04` **=** 用户态 `580.178.04`（重启生效） |
| `--preflight-only` | `torch 2.7.0+cu128 cuda True \| GPU free`（显存 2 MiB） |
| `--plan` | 60 条 spec 的 20 个 profile + 60 个 ckpt 逐条核对，`all present` |
| 环境回归冒烟 | `nominal-paper` n8 ×ON/OFF `2/2 OK`；`filter-only-p1` n8 ×ON/OFF `2/2 OK`，圆柱世界正常建起（`z-scale wrote=3072`，`invalid_prim=0`） |

**冒烟顺带查清的一件事（重要，影响读数方式）**：`cbf.mode=none` 的臂**没有滤波器**——
`build_cbf_filter` 在该模式下返回 `None`，实测 ON 与 OFF 的 44 个指标字段**只有 `runtime_filter` 本身不同**，
且 CBF 诊断键（`intervened_step_frac`/`cbf_diag_steps`/`h_below0_frac`/`corr_*`）**整体缺失**。因此：

- `nominal-paper` / `obs-proximity` 的 ON 与 OFF 是**构造等同**，不是"实测相同"；
- 那两行的"依赖度 = 1.000"**不构成任何证据**（没有滤波器可撤），`interv` 只能 n/a；
- 已在 `np_acceptance_eval.py` 的表格下自动附 `cbf.mode` 图例，避免误读。

反面验证：`filter-only-p1`（`mode=filter_only`）在小规模冒烟里 ON `coll=0` / OFF `coll=2`，诊断键齐全
（`interv` ON 0.937 / OFF 0.932）⇒ ON/OFF 确实产生不同行为，方向与设计一致。
（小规模冒烟的数字**不进入任何结论**。）

启动：2026-09-18 08:51:26（tmux `np_eval`），`384x1500`，串行。实测单次 **39–61 s**（n8 约 39 s，n16 约 50–61 s），
均值 0.7–0.8 min/spec，单次显存峰值约 17.8 GiB。

新增工具 `scripts/np_eval_report.py`：只读 `rows_all.json` 生成最终报告——**逐条对照 §6 冻结门槛的判定表**、
三 seed `mean[min..max]` 主表（含 ON/OFF 两侧的 `min_clr`/诊断量）、3 个基准问题的自动作答
（凡"A 比 B 好"都附逐 seed 差值与符号一致性；n=3 时 3/3 同号只说明"无反转"，**不构成 p<0.05**）。

### 6.5 切片 A 结果（2026-09-18 09:37 收口，60/60，0 失败）
产物：`/tmp/navvel_np/eval/eval_final.md`（判定表 + 合并表 + 逐 seed 表 + 3 问作答）、
`rows_all.json`（60 条原始指标）、`eval_seed_tables.md`（驱动每 seed 落一节）、`<tag>.log` ×60。

**三 seed 合并（`mean[min..max]`，`384×1500`）**

| 臂 | n | arr@0.2 ON | arr@0.2 OFF | 严格成功 ON | 碰 ON | 碰 OFF | 零介入率 ON | 依赖度 |
|---|---|---|---|---|---|---|---|---|
| nominal-paper | 8 | 0.660 [0.526..0.737] | 同（无滤波器） | 0.657 | 0.33 | 0.33 | n/a | n/a |
| nominal-paper | 16 | 0.462 [0.391..0.539] | 同 | 0.460 | **2.67** | 2.67 | n/a | n/a |
| obs-proximity | 8 | 0.789 [0.750..0.810] | 同 | 0.791 | 0.00 | 0.00 | n/a | n/a |
| obs-proximity | 16 | 0.532 [0.526..0.539] | 同 | 0.534 | 0.33 | 0.33 | n/a | n/a |
| dual-p0 | 8 | 0.670 [**0.201**..0.979] | 0.449 [**0.050**..0.716] | 0.604 | 0.00 | 1.00 | 0.515 | 0.559 |
| dual-p0 | 16 | 0.534 [**0.003**..0.898] | 0.215 [**0.000**..0.323] | 0.536 | 0.00 | 0.67 | 0.344 | 0.273 |
| dual-p1 | 8 | **0.966** [0.924..0.997] | 0.652 [0.604..0.714] | 0.966 | 0.00 | 0.00 | 0.654 | 0.674 |
| dual-p1 | 16 | **0.854** [0.810..0.932] | 0.194 [0.162..0.219] | 0.855 | 0.00 | **3.33** | 0.455 | 0.228 |
| filter-only-p1 | 8 | 0.893 [0.883..0.911] | 0.571 [0.414..0.682] | 0.893 | 0.00 | 0.00 | 0.584 | 0.638 |
| filter-only-p1 | 16 | 0.839 [0.805..0.870] | 0.188 [0.169..0.206] | 0.840 | 0.00 | **5.00** | 0.417 | 0.223 |

**⚠️ 均值掩盖的最大事实：`dual-p0` 有 1/3 个 seed 崩了**（逐 seed 表见 `eval_final.md` §2b）：
`n16 s13` = `arr@0.2 0.003`、`joint 0.000`、`notarrived_step_frac 1.000`（几乎不飞）；
`n8 s13` = `arr@0.2 0.201` 但 `arr@0.5 0.862`、**`joint 0.000`**（飞到了但**停不住**）。
其 `min_clr` 因此被污染（`n16` 均值 0.0734 主要来自崩掉 seed 的 0.1191——不接近障碍所以"裕度很大"）。
`dual-p1` / `filter-only-p1` 三个 seed **全部稳定**（n8 OFF 0.604–0.714、n16 OFF 0.162–0.219）。

**对照口径**：`arr@0.2`（plan 门槛用）= "曾进到目标 0.2 m 以内"；**严格成功** = 到达 ∧ 保持
`arrive_hold_steps` ∧ 0 碰（`arrival_triggered` 锁存）。两者对多数臂近似相等，
但 `dual-p0 s13 n8` 是 0.201 vs **0.000** ⇒ **只看 plan 门槛会把"飞过去停不住"读成"部分成功"**。

**3 个基准问题的答案**

1. **`nominal_paper` 能否从零学会避障？—— 能，但明显弱于 `obs_proximity`。**
   n8：0.660 vs 0.789，Δ = **+0.129 [+0.034..+0.284]（3/3 同号）**，碰撞 0.33 vs 0.00；
   n16：0.462 vs 0.532，Δ = +0.070 [−0.008..+0.135]（**符号翻转 ⇒ 到达率上不可区分**），
   但碰撞 **2.67 vs 0.33**。⇒ proximity 塑形的贡献**在 n8 到达率上明确**，在 n16 到达率上不可区分，
   在**碰撞**上两级都偏向 `obs-proximity`。
2. **`dual-p0` 在撤-filter 时是否仍最优？—— 不成立。**
   带滤波器三臂的 OFF：n8 `dual-p1` 0.652 > `filter-only-p1` 0.571 > `dual-p0` 0.449；
   n16 三者 0.215 / 0.194 / 0.188 **不可区分**（差异 0.03 远小于种子极差 0.32）。
   且 `dual-p0` 是**唯一**出现 seed 崩坏的臂（OFF 侧 n8 0.050 / n16 0.000）⇒ 稳定性上 `dual-p1`
   与 `filter-only-p1` 明显更好。
3. **撤 filter 后有没有任何臂同时满足"高到达 + 0 碰"？—— 没有。**
   n8 OFF：`dual-p1`/`filter-only-p1` 确实 0 碰，但到达只有 0.652/0.571（<0.85）；
   n16 OFF：三个滤波臂**全部出现碰撞**（0.67/3.33/5.00 个 env），到达 0.19–0.22。
   最接近的两行是**本来就没有滤波器**的 `obs-proximity`（n8 0.789/0 碰、n16 0.532/0.33 碰），
   但其 n16 仍有碰撞且到达 <0.85。⇒ **安全与到达率都依赖滤波器**（ON 侧 30 次滤波臂 eval 碰撞**全为 0**）。

**其他确认项**：`oob`/`crash` 全 0；`h_min^train` 恒 0.12（≥0）；`dropped_relevant_frac` 精确 0、
最差 `dropped_step` 0.008 <1% ⇒ **K=4 容量足够，无需改 K**；`stall` ≤0.026 <10%。
`min d_min` 仅记录（ON 侧 0.0456–0.0510，OFF 侧 0.0381–0.0508），按 §0.5.22 **不作门槛**。

---

## 7. 待办 / 风险

- [x] 训练批次 **60 档**（2026-09-18 01:49 完成，60/60 产出 ckpt）
- [x] 训练期曲线检查（§5；结论：**没塌缩，但两个非 CBF 臂 std 顶到上限**）
- [x] 台账修复（§3 问题 7：`np_manifest_rebuild.py` 从磁盘重建，60 档全 ok）
- [x] 验收驱动 `scripts/np_acceptance_eval.py`（per-spec profile + 按 seed 分组的对比表 + 三 seed 合并；自检通过）
- [x] **验收切片 A 完成**（§6.5）：60/60、0 失败；判定 **不通过**，失败在到达率与可撤性、不在安全
- [x] `dropped_relevant_frac` 在 n=8/n=16 上报：**精确 0，最差 `dropped_step` 0.008 <1% ⇒ K=4 够用**
- [x] 结论写回 plan `§0.5.31`（含失败与"不可区分"）
- [x] **新批次：`-noprox` 三臂**（§8）—— 剔离 proximity 塑形，已开训
- [ ] §5.2 的 std 上限问题做**单变量诊断**（待用户裁决；验收显示确定性到达率不差，但 n16/OFF 不能排除其贡献）
- [ ] 目视确认 R1（物理圆柱高度是否跟随 per-episode scale）
- [ ] 导出侧同步（**范围外**，与用户确认后再做）

---

## 8. 新批次：`-noprox` 三臂（剥除 obstacle-proximity 塑形）

### 8.1 动机（由 §5.4 的量化证据触发）

三个 CBF 臂（`dual-p0` / `dual-p1` / `filter-only-p1`）的 profile 里带着
`obstacle.reward_obs_log_weight: 1.5` + `obstacle.reward_near_slowdown_weight: 0.5`，
而论文的 `r_obstacle` **不含**这个 proximity 塑形项。训练日志的量化证据（§5.4）：这三个臂的
`train/stats` 里 `term_obs_log` ≈ **+0.5/episode**（另加 `term_near_slow` ≈ −0.18），而论文口径的
`nominal-paper` 是 **0.0000** ⇒ **三个「论文行」被一个论文里不存在的塑形项混淆了**。
用户裁决（2026-09-18）：**把该项剥离后重训这三臂**，再出一张新旧对照的测试总表。

### 8.2 用户裁决

| 议题 | 裁决 |
|---|---|
| 新臂命名 | **`-noprox` 后缀**：`dual-p0-noprox` / `dual-p1-noprox` / `filter-only-p1-noprox`（旧臂名不改，避免弄断已完成批次的记录） |
| 训练档位 | **四档全链 `n2→n4→n8→n16`**（每档 10M 帧）——只有链末的 n8/n16 才与旧三臂**可比**（旧臂的 n8/n16 也是链末档） |
| eval 档位 | **n8 + n16**，`384×1500` 一档，**不跑 `512×600`** |

### 8.3 单变量改法（已断言）

`make_np_profiles.py` 新增三臂，只覆盖两个权重：`reward_obs_log_weight 1.5 → 0.0`、
`reward_near_slowdown_weight 0.5 → 0.0`。`--check` 新增断言：noprox 臂的两个权重必须为 0
**且 `reward_collision_edge` 必须仍为 2**（碰撞惩罚属于论文的 `r_obstacle`，不属于被剥离的塑形）。

验证：`diff <(grep -v '^#' 旧) <(grep -v '^#' 新)` 非注释行**只差这两行**；
重新生成后旧的 20 份 profile **字节未变**（`git status` 只出现 12 个新文件，无 `M`）。
运行中的 live config 也已核验：`reward_obs_log_weight: 0.0`、`reward_near_slowdown_weight: 0.0`、
`reward_collision_edge: 2`、`obs layout ... total obs 58`。

### 8.4 开跑记录与计划

- 启动：2026-09-18 **10:17:51**（tmux `np2`），**36 档**（9 链 × 4 档），`--parallel 2`，
  project `env_design_cyl_noprox`（**独立 project + 独立 logdir**，`np_manifest_rebuild.py` 不会与旧批混），
  logdir/manifest `/tmp/navvel_np2/`。
- 预估：每档 ≈350 s（沿用旧批实测）⇒ 36 档 ÷ 2 ≈ **1.8 h**，收口约 **12:00–12:15**。
- 验收计划：**36 次 eval**（三臂 × {n8,n16} × 3 seed × {ON,OFF}），`384×1500`，串行，≈35 min。
- 总表：`np_eval_report.py --rows <旧 rows_all.json> <新 rows_all.json>` —— 已改造为
  **多文件合并 + 臂/档/seed 从数据推导 + `cbf.mode` 从 profile 读取**（不再硬编码臂表），
  新增"新旧同臂对照（proximity 塑形净效应）"一节（逐 seed 差值 + 符号一致性）。

### 8.5 早期监测：n2 首档（2026-09-18 10:27 完成）

**① 剥离塑形没有破坏 from-scratch 学习，n2 档反而更好**（同 arm **同 seed** 对比，训练末 `stats.arrival`）：

| 臂 | 旧（`reward_obs_log_weight=1.5`） | 新（`noprox`，=0.0） |
|---|---|---|
| `dual-p0` s11 n2 | 0.125 | **0.282** |
| `dual-p1` s11 n2 | 0.009 | **0.042** |

两者 `term_obs_log` 末值均为 **0.0** ⇒ 剥离在**运行中的配置**里确实生效（不只看 profile 文本）。

**② ⚠️ 我自己踩过的坑（留档）**：我先用"新臂 n2 = 0.042"去比旧臂的 **3-seed 均值 0.225**，
得出"差 5 倍、疑似没在学"的错误印象；正确基线是**同 seed**（0.009）⇒ 结论**反了**。
教训：**同档对比必须同 seed**；本工程 seed 间方差大到可以反转结论（旧 `dual-p1` n2 的 3 seed 是
0.009 / 某 / 某，均值 0.225）。

**③ 校准后的进度**：实测 **482 s/档**（两链并行，实测 467/496 s）⇒ 36 档 ÷ 2 ≈ **2.3 h**，
收口约 **12:45**（原估 1.8 h 偏乐观，已修正）。完成后接 36 次 eval（≈35 min）。

### 8.6 新批次结果 + **8 臂测试对比总表**（2026-09-18）

**收口**：训练 36/36 档（10:17:51→12:32:19，均值 412 s/档，0 失败）；验收 36/36 次（12:32→12:59，0 失败）。
产物：`/tmp/navvel_np2/eval/master_8arms.md`（总表 + 门槛判定 + 逐 seed + 新旧对照）、`rows_all.json`。

#### 8.6.1 测试对比总表（8 臂；`384×1500`，3 seed 均值 `[min..max]`）

| arm | n | mode | 到达@0.2 ON | 到达@0.2 OFF | 严格成功 ON | 碰 ON | 碰 OFF | 零介入率 ON | 依赖度 |
|---|---|---|---|---|---|---|---|---|---|
| nominal-paper | 8 | none | 0.660 [0.526..0.737] | 同（无滤波器） | 0.657 | 0.33 | 0.33 | n/a | 1.000° |
| nominal-paper | 16 | none | 0.462 [0.391..0.539] | 同 | 0.460 | 2.67 | 2.67 | n/a | 1.000° |
| obs-proximity | 8 | none | 0.789 [0.750..0.810] | 同 | 0.791 | 0.00 | 0.00 | n/a | 1.000° |
| obs-proximity | 16 | none | 0.532 [0.526..0.539] | 同 | 0.534 | 0.33 | 0.33 | n/a | 1.000° |
| dual-p0 | 8 | hybrid | 0.670 [**0.201**..0.979] | 0.449 | 0.604 | 0.00 | 1.00 | 0.515 | 0.559 |
| dual-p0 | 16 | hybrid | 0.534 [**0.003**..0.898] | 0.215 | 0.536 | 0.00 | 0.67 | 0.344 | 0.273 |
| dual-p1 | 8 | hybrid | 0.966 [0.924..0.997] | 0.652 | 0.966 | 0.00 | 0.00 | 0.654 | 0.674 |
| dual-p1 | 16 | hybrid | 0.854 [0.810..0.932] | 0.194 | 0.852 | 0.00 | 3.33 | 0.455 | 0.228 |
| filter-only-p1 | 8 | filter_only | 0.893 [0.883..0.911] | 0.571 | 0.891 | 0.00 | 0.00 | 0.584 | 0.638 |
| filter-only-p1 | 16 | filter_only | 0.839 [0.805..0.870] | 0.188 | 0.837 | 0.00 | 5.00 | 0.417 | 0.223 |
| **dual-p0-noprox** | 8 | hybrid | **0.955** [0.940..0.966] | **0.775** | 0.954 | 0.00 | 0.67 | 0.627 | **0.812** |
| **dual-p0-noprox** | 16 | hybrid | 0.567 [0.380..0.672] | **0.534** [0.276..0.807] | 0.552 | **0.33** | 0.67 | 0.288 | 1.111 |
| **dual-p1-noprox** | 8 | hybrid | 0.876 [0.734..0.977] | 0.607 | **0.652** [0.073..0.974] | 0.00 | 0.33 | 0.498 | 0.698 |
| **dual-p1-noprox** | 16 | hybrid | **0.891** [0.841..0.966] | 0.274 | 0.888 | **0.33** | 2.33 | 0.396 | 0.310 |
| **filter-only-p1-noprox** | 8 | filter_only | **0.984** [0.971..0.997] | **0.741** | **0.984** | 0.00 | 0.67 | 0.662 | 0.755 |
| **filter-only-p1-noprox** | 16 | filter_only | **0.928** [0.836..0.982] | 0.218 | **0.925** | 0.00 | 2.67 | 0.507 | 0.233 |

° `mode=none` 的臂没有滤波器，其 OFF 列**不是**"撤掉滤波器后的测量"，依赖度/零介入率不计分。

#### 8.6.2 剥离 proximity 塑形的净效应（逐 seed 差值，新−旧）

| 臂 | 档 | Δ到达@0.2 ON | 符号 | 备注 |
|---|---|---|---|---|
| `dual-p0` | n8 | **+0.285** [−0.013..+0.758] | 翻转 | 均值增益**几乎全来自 s13 崩坏消失**（0.201→0.958）；s12 微降 |
| `dual-p0` | n16 | +0.033 [−0.518..+0.669] | 翻转 | 但出现 **1 次 ON 碰撞**（旧臂为 0）⇒ 安全回退 |
| `dual-p1` | n8 | **−0.090** [−0.263..+0.052] | 翻转 | **变差** |
| `dual-p1` | n16 | +0.037 [−0.065..+0.156] | 翻转 | 再出现 **1 次 ON 碰撞** |
| `filter-only-p1` | n8 | **+0.090** [+0.070..+0.115] | **3/3 同号** | ✅ **唯一统计干净的改善** |
| `filter-only-p1` | n16 | **+0.088** [+0.031..+0.138] | **3/3 同号** | ✅ 且**全程 0 碰**、极差最窄 |

#### 8.6.3 结论（含失败与"不可区分"）

1. **剥离塑形不是普遍利好**：只有 `filter-only-p1` 在两个档都**干净地变好**（+0.09，3/3 同号，0 碰）；
   `dual-p0` 的 +0.285 是**单个 seed 崩坏消失**带来的，逐 seed 符号不一致；
   `dual-p1` 在 n8 **变差**（−0.090），n16 只是不可区分地略好。
2. **新的最优臂 = `filter-only-p1-noprox`**：n8 **0.984** [0.971..0.997]、n16 **0.928** [0.836..0.982]，
   两个档 **0 碰**、极差最窄（n8 仅 0.026 宽）。它对应论文的 `Filter Only` 行，
   即"**只跑滤波器、既无 r_cbf 奖励也无 proximity 塑形**"。
3. **两个 dual 的 noprox 臂在 n16 出现各自的病态**（必须留档，不能被均值掩盖）：
   - `dual-p0-noprox` n16 s12：**ON 0.380 但 OFF 0.807**（依赖度 2.12）⇒ 该 seed 上**滤波器反而拖累到达率**
     （"滤波器与策略对抗"或 seed 病态），同时 s11 有 1 次 ON 碰撞；
   - `dual-p1-noprox` n8 s12：到达 0.734 但**严格成功仅 0.073**（到达@0.5 = 0.982）⇒ 老批 `dual-p0 s13` 的
     "**飞得到、停不住**"模式在新臂上复现，且这次发生在**带滤波器**的臂上。
4. **门槛层面仍然 FAIL**（16 行全 FAIL）且卡点未变：**OFF 到达率全部 <0.85**（最高 0.775）、
   **零介入率 0.29–0.66 ≪ 0.95** ⇒ **仍然没有任何臂可以撤掉滤波器**。
   唯一通过依赖度门槛的格子是 `dual-p0-noprox` n16（1.111），但它同时**违反 0 碰**，不算胜出。
   ON 到达率 ≥0.85 的行从 3 行增到 **8 行**（三个新臂在 n8 全部过线、两个在 n16 过线）。
5. **`filter-only-p1-noprox` 是唯一同时满足"n8/n16 双档高到达 + 双档 0 碰 + 极差最窄"的配置**；
   若下一步要选部署候选，它是当前最强证据。

#### 8.6.4 速度维度（首次到达终点所需步数）—— 2026-09-18 追加

**口径（从 env 读出，非猜测）**：`stats["first_arrival_step"]` = 本 episode 内**首次满足「进入
`arrive_radius=0.5 m` 并保持 `arrive_hold_steps=50` 步」时的步数**（0 = 从未到达，被排除）。
`sim.dt = 0.01 s` ⇒ **1 步 = 10 ms**；**保持的 50 步（0.5 s）计入该值** ⇒ 净飞行 = 首达步数 − 50。
物理参照：`fixed_init→fixed_target` 直线 **5.622 m**，扣掉到达半径 ⇒ 净飞行 ≈ **5.122 m**。

⚠️ **必须与到达率并读**：`arrived n` 是**分母**（只统计确实到达过的 env）。到达率低的臂只统计了
"最容易的那批 env"，会**显得更快** —— 这是幸存者偏差，不是速度优势。

| 臂 | n | 首达步数(ON) 均值[min..max] | 净飞行 | 路径比 | 末端速度 | 到达样本 |
|---|---|---|---|---|---|---|
| nominal-paper | 8 | 408.6 [404..413] | 3.59 s | 4.369 | 0.513 | 252/384 |
| nominal-paper | 16 | 443.2 [431..450] | 3.93 s | 4.670 | 0.643 | 177/384 |
| obs-proximity | 8 | 431.7 [421..440] | 3.82 s | 3.511 | 0.314 | 304/384 |
| obs-proximity | 16 | 459.5 [455..463] | 4.10 s | 4.251 | 0.536 | 205/384 |
| dual-p0 | 8 | 509.5 [502..517] | 4.59 s | 3.645 | 0.499 | 232/384（含 0） |
| dual-p0 | 16 | 592.7 [572..614] | 5.43 s | 3.422 | 0.461 | 206/384（含 0） |
| dual-p1 | 8 | 509.4 [498..517] | 4.59 s | 2.022 | 0.075 | 371/384 |
| dual-p1 | 16 | 597.7 [586..606] | 5.48 s | 2.429 | 0.168 | 327/384 |
| filter-only-p1 | 8 | 500.7 [485..528] | 4.51 s | 2.473 | 0.160 | 342/384 |
| filter-only-p1 | 16 | 595.9 [592..599] | 5.46 s | 2.461 | 0.185 | 321/384 |
| dual-p0-noprox | 8 | 500.9 [494..506] | 4.51 s | 2.103 | 0.101 | 366/384 |
| dual-p0-noprox | 16 | 579.1 [573..582] | 5.29 s | 3.343 | 0.457 | 212/384 |
| dual-p1-noprox | 8 | 503.7 [498..513] | 4.54 s | 3.491 | 0.490 | 250/384 |
| **dual-p1-noprox** | 16 | **568.5** [558..580] | 5.19 s | 2.677 | 0.232 | 341/384 |
| **filter-only-p1-noprox** | 8 | 504.2 [490..532] | 4.54 s | **1.787** | **0.046** | 378/384 |
| **filter-only-p1-noprox** | 16 | 589.1 [574..605] | 5.39 s | **2.110** | **0.112** | 355/384 |

**读数（5 条）**

1. **在 n8，所有带滤波器臂的首达步数几乎一样**（500.7–509.5，差 ≤9 步 ⇒ ≤0.09 s）。⇒ **剥离塑形
   与滤波器都几乎没有改变"多快到达"**；速度维度的分离度**远小于到达率维度**（后者从 0.839 到 0.984）。
2. **n16 才出现速度差**：`dual-p1-noprox` **568.5**（5.69 s）最快，比旧 `dual-p1`（597.7）快 **29 步 ≈0.29 s**，
   且样本数相当（341 vs 327）；新旧 `filter-only-p1` 都是 589–596，几乎无差。
3. **`mode=none` 臂"更快"（408–460）是幸存者偏差**：它们只在 44–79% 的 env 上到达（如 `nominal-paper` n16
   只有 177/384"达标 env"），统计的正是最容易被到达的那批。**不可据此说它们飞得更快。**
4. **分离度最高的是轨迹质量而不是时间**：`filter-only-p1-noprox` 的**路径比 1.787**（最接近直线）
   vs 旧 `filter-only-p1` 2.473、`nominal-paper` 4.369；n16 同样 2.110 vs 2.461/4.670
   ⇒ **proximity 塑形诱导了明显绕行**（`r_obs_log` 在靠近障碍时给正奖励，鼓励"贴着走"）。
5. **末端速度**（rollout 末 0.5 s 平均 |v_xy|）：`filter-only-p1-noprox` **0.046**（最干净的停）
   vs `dual-p0-noprox` 0.101 / `dual-p1` 0.075 / 旧 `filter-only-p1` 0.160 / `obs-proximity` 0.314 /
   `nominal-paper` 0.513 ⇒ 新最优臂不只是"到得多"，还**停得最稳、走得最直**。
6. `p90` 距 1500 步上限很远（443–688）⇒ **没有"贴着超时线到达"的问题**；
   最快臂净飞行 3.59 s ⇒ 平均 **1.43 m/s**，滤波臂 ≈4.5 s ⇒ **1.14 m/s**（均未顶到速度上限）。
