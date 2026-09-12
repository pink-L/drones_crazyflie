# NavVel 版本管理与重训计划（阶段 1a / 1b / 阶段 2）

> 版本 **2026-09-12 v1（新建）**。**个人执行文档**：现状事实 + 版本管理方案 + 分批重训计划 + 分阶段验收标准。
>
> **范围**：只覆盖 **阶段 1a**（长方体立柱·球近似，obs 62 冻结）、**阶段 1b**（obs_v3 升维 + 方体 SDF CBF）、
> **阶段 2**（去 runtime filter）。**不含阶段 3 动态障碍**（见 `Navvel_dynamic_obs_plan.md`，本计划全部达标后才启动）。
>
> **配套文档**
> - `NAVVEL_RETRAIN_GUIDE.md` —— 决策依据、公式、实验矩阵的原始出处；**本文是其"执行收敛版"**，
>   凡本文与它冲突处，以本文 §附录 B 的裁决记录为准。
> - `project_summary.md` —— 代码现状（模块/奖励/CBF 的详细说明）。
> - `navvel_export/meta.json` —— 当前交付 artifact 的元数据（已核实与本地 ckpt sha256 一致）。
>
> **本文所有"现状"条目均已在本机（`hybrid-5090d:/home/lz/lzspace/drones`）核实**，来源标注为
> `[code]`（读源码）/`[cfg]`（读 cfg 或 run config.yaml）/`[fs]`（读文件系统）/`[待确认]`。

---

## 0. 本文冻结的决策

| # | 决策项 | 结论 | 影响 |
|---|---|---|---|
| 1 | 覆盖范围 | **阶段 1a + 1b + 阶段 2** 三个阶段，含几何口径对齐、实验矩阵、整机验收 | 本文即完整执行计划 |
| 2 | 本文定位 | **个人执行文档**（可操作、可复现、命令级） | 详细到文件/键名/门槛 |
| 3 | 几何口径方向 | **选项 A：训练放宽到部署口径**（`drone_radius 0.10 / inflation 0.02 / r_safety_margin 0.05`，`use_brake_term=false` ⇒ `r_s = r_o+0.12`、`r_cbf = r_o+0.17`） | 必重训；旧"0 碰"与新"0 碰"不可直接比较，必须先重跑基线 |
| 4 | 归因纪律 | **分批重训**，每批只引入一个小变量集；几何变化走 A0→A0′→A1a→A1b→A2→A3→A4 递进 | 轮次多但可归因；总 GPU 时间仍 < 6 h（见 §3.7） |
| 5 | `K=8 → 10/12` 升维批次 | **放 P4（1b）与 obs_v3 合并**，只做一次重导 + 重对拍；1a 保持 obs 62 维 | 保住 1a"零升维、零重导"的卖点；K 扩容不静默丢弃（附录 B-2） |
| 6 | 验收标准 | **阶段 1 与阶段 2 分开定义**：阶段 1 允许 filter ON；阶段 2 必须 filter OFF 达标 | 见 §4.1 差异对照表 |
| 7 | 版本管理对象 | 模型与导出物、部署配置、训练代码与配置快照、文档与计划（**不含**场地/硬件布置图，见 §2.8 待办） | 见 §2 |
| 8 | 资源与粒度 | 单卡 5090；单 run ≈ 20M frames；**每格 ≥3 seed**（候选交付配置 ≥5） | 见 §3.7 预算 |
| 9 | 动态障碍 | **本文与后续重训一律不涉及**；任何动态障碍相关工作不得进入 P0–P5 | 阶段 3 前置条件写在 `Navvel_dynamic_obs_plan.md` |
| 10 | 文档落点 | 本文 `drones/NAVVEL_VERSION_AND_RETRAIN_PLAN.md`；模型注册表另建 `drones/NAVVEL_MODEL_REGISTRY.md` | 见 §2.5 |

---

## 0.5 K1 执行记录（2026-09-12）

> **状态：K1 六项入库动作全部完成 ✅**，卡点 **K1 = 绿**。新增缺口 G13–G21（见 §1.4）。

### 0.5.1 已完成动作（对应 §2.7）

| # | 动作 | 结果 |
|---|---|---|
| 1 | 提交计划文档与脚本副本 | 外层 commit `d47d87e`；文档/`plan_before/`/`figures/`/论文 md 全部入库 |
| 2 | 子模块提交 + 打 tag | 子模块 commit `2a5c1b0`；外层 annotated tag **`navvel-cfb-v1.0.0`** |
| 3 | 迁移导出物 + `SHA256SUMS` + `lineage.json` | `/home/lz/lzspace/navvel_export/navvel-cfb-v1.0.0-dual-p1-s11/`；新增 `run_config.yaml`、`acceptance.md`；`sha256sum -c` 全绿 |
| 4 | 落地 `cfg/profiles/A0-legacy.yaml` | ✅ **142 leaf keys 完整快照**，自包含（base env/sim 已内联）；hydra 可加载为 `task=profiles/A0-legacy` |
| 5 | 建注册表 | `drones/NAVVEL_MODEL_REGISTRY.md`（含 3-seed checkpoint 哈希 + G12 留档） |
| 6 | 建 `_current` 软链 | `navvel_export/_current -> navvel-cfb-v1.0.0-dual-p1-s11` |

### 0.5.2 与文档假设不符之处（执行时修正）

| 项 | 文档假设 | 实际 |
|---|---|---|
| 仓库根 | §2.7-1 写 `git add drones/*.md …`（暗示仓库根 = 工作区根） | **`/home/lz/lzspace` 不是 git 仓库**；仓库根 = `drones/`。故 `drones/*.md` → `*.md`（仓库内） |
| 脚本副本路径 | §2.7-1 写 `export_navvel_actor.py`（工作区根，仓库外） | 已复制到 **`drones/OmniDrones/scripts/export_navvel_actor.py`**（= §1.1 所说"服务器路径"）并入库；工作区根副本保留 |
| profile 路径 | §2.7-4 写 `cfg/profiles/<profile>.yaml` | 内容落在此路径；另加**软链** `cfg/task/profiles -> ../profiles`，使 hydra 能按 task 组加载（`train.yaml` 的 `defaults: - task: <name>` 只认 `cfg/task/`） |
| `algo=ppo` 配置 | （未提及） | **`cfg/algo/ppo.yaml` 不存在且 git 历史从未有过**；PPO 超参由代码内 `ConfigStore` 注册（`omni_drones/learning/ppo/ppo.py:59`）⇒ 见 G15 |
| 子模块状态 | G4 说"有未提交改动" | 执行时**已 clean**，但 HEAD 与外层记录的指针差 15 个 commit（`+774538f`） |

### 0.5.3 附录 A 四条核查命令的结果

| 命令 | 结论 |
|---|---|
| **G1** 部署侧文件定位 | ❌ **仍缺**。在 `/home` 全盘 `find`（`navvel_deploy*.yaml` / `navvel_obstacles*.yaml` / `navvel_cbf.py` / `navvel_offline_check.py`）**零命中**；`navvel*` 目录只找到 `navvel_export`。⇒ K6 仍红 |
| **G6** | `eval_ckpt.py` 指标 | ⚠️ **部分可用**：已有 `+runtime_filter=true|false`（= 文档说的 `filter_mode`，ON/OFF 判据可用），并输出 `arrival_rate`/`collision`/`collision_episodes`/`min_clearance`/`success_rate`/end-cause/`reach`(需 `+record_min_rpos=true`)。**但缺** `intervened` 零介入率、`h_min^train`、`Δa` p50/p95、`stall`、`dropped_relevant` ⇒ §4.2/§4.3 的门槛仍无法直接判。**✅ 2026-09-12 已修（K5）**，见 §0.5.5 |
| **G11/G12** 三 seed 成绩 | ✅ 已取到，但**口径与文档不同**：`wandb-summary.json` 只有训练内 `eval/stats.*`（soft-respawn 窗口口径），3-seed `success_rate` 均值 **0.4320**（0.4766/0.4229/0.3965），`min_clearance` 均值 0.6363，`collision`=0。文档引用的 **ON 0.891 / OFF 0.855 无留档且不可复现** ⇒ 见 G16 |
| **口径 A 半径链自检** | ✅ 本地实跑 `omni_drones.utils.cbf`，与本文数值**完全一致**：`A0-legacy` `r_s=r_o+0.20` / `r_cbf=r_o+0.30`；`A` `r_s=r_o+0.12` / `r_cbf=r_o+0.17` |

### 0.5.4 D-1–D-4 决策（2026-09-12 已确认，见附录 A）

| 项 | 决策 |
|---|---|
| **D-1** | 口径 A **不改** `collision_margin`，保持 `0.05` |
| **D-2** | `K=8→12` 扩容**放 P4**，1a 保持 K=8 |
| **D-3** | `obs_v3` 取 **SDF+法向 7 维** ⇒ obs = 30+7×12 = **114** |
| **D-4** | 阶段 1 真机沿用 `arrival@0.2 ≥ 0.85` |
| **D-5（新增）** | `v1.0.0` 基线 = **补跑 `eval_ckpt.py` 严格单命验收重建**（不用训练内 eval 0.4320） |

### 0.5.5 K5 已完成（2026-09-12）+ v1.0.0 阶段 2 基线实测

**① 指标补齐（K5，修 G6）——已完成 ✅**

| 落点 | 改动 |
|---|---|
| `omni_drones/utils/cbf.py::CBFVelocityFilter` | 新增 `shadow`（算 `a_cbf` 但**不写回**动作）与 `record_diag`（逐步攒 `[‖Δa‖, intervened, h_min, fix_norm]`）；**`filter_velocity` 数学未动** |
| `omni_drones/envs/single/nav_vel_obstacles.py::build_obs` | 暴露 `_obs_win_idx/_obs_win_valid`（滑动窗口选中的槽位）→ 支持 `dropped_relevant` |
| `scripts/eval_ckpt.py` | `runtime_filter=false` 改挂 **shadow 滤波器**（策略行为 == 撤掉 filter，但仍能量"本会介入多少"）；新增 `_AcceptanceCb` 累加 `arrival@0.2/0.3/0.5`、`stall`、`oob/crash ever`、`dropped_relevant`；`+set_seed` 确定性 + `layout_fp` 布局指纹（验证 ON/OFF 同分布）；输出 `[eval_metrics]` JSON 单行 |
| **新增** `scripts/acceptance_eval.sh` | 批量评估 runner（`<seed>:<on\|off>:<ckpt>`，可 `PARALLEL=2`） |
| **新增** `scripts/aggregate_acceptance_eval.py` | 汇总日志 → §4.2/§4.3 表 + 门禁判定 + `eval_metrics.json` |
| `scripts/cbf_test.py` | 新增 `t9_shadow_diag()`（6 项断言，覆盖 shadow/诊断/逐位兼容） |

**② 评估协议（新增，写死，后续批次必须沿用）**

`512 envs × 600 步`、确定性 `MODE`、`eval_points=fixed`（`[-2.8,0,0.5] → [2.8,0,1.0]`）、
`set_seed = 1000+train_seed`（ON/OFF 共用 ⇒ 同一套障碍布局）。
> **显存实测**：`1024×1500` **OOM**；`512×1500` 峰值 26.4 GiB（不能并行）；**`512×600` 峰值 13.6 GiB**
> ⇒ 可 2 进程并行（6 run 共 1m51s，峰值 28.5 GiB）。

**③ v1.0.0 阶段 2 验收结果：不通过 ❌**（3 seed × ON/OFF，证据见
`navvel_export/navvel-cfb-v1.0.0-dual-p1-s11/{acceptance.md,eval_metrics.json,eval_logs/}`）

| 门禁 | 门槛 | 实测（3-seed 均值） | 判定 |
|---|---|---|---|
| filter 依赖度 `OFF/ON` | ≥ 0.95 | **1.0076** | ✅ PASS |
| 零介入率 | ≥ 0.95 | **0.1613** | ❌ FAIL |
| `h_min^train` | ≥ 0 | **−0.0500** | ❌ FAIL |
| `arrival@0.2`（ON） | ≥ 0.85 | **0.3412** | ❌ FAIL |
| 0 碰 | 必须 | ON 0 / OFF **1** | ❌ FAIL |
| 0 OOB | 必须 | 0 | ✅ PASS |
| `min d_min` | ≥ 0.10 m | 0.0512 | ❌ FAIL |
| `stall` | ≤ 10% | 0.0132 | ✅ PASS |
| `dropped_relevant` | < 1% | 0.0000 | ✅ PASS |

> **最重要的解读**：**「依赖度 PASS」≠「可以撤 filter」**。同一次评估里零介入率只有 **0.16**
> ⇒ 滤波器 **84% 的步都在介入**（`‖Δa‖` 中位 0.64、p95 1.45 m/s，`v_max=1.8`），
> 但到达率 ON/OFF 在统计上不可区分（差 2.6e−3，标准误 ≈ 2.1%）。
> 机制：`filter_velocity` 只沿外法向扣除"朝障碍的靠近速度"，**切向（朝目标）进度不受影响**；
> 在 `cbf_extra=0.10` 的保守球 + 28 障碍下几乎总有约束绑定 ⇒ **介入率虚高但无实效**。
> ⇒ 这是「滤波器做无用功」，**不是**「策略已内化安全」——正是 **P3** 要治的对象，
> 也说明 §4.3 必须**同时**看 `依赖度` 与 `零介入率`（本表就是反例）。
>
> 另外 `dropped_relevant ≈ 0` ⇒ **A0 未出现 K=8 容量不足**（A3/A4 柱数升到 8 后需重测）。

### 0.5.6 P0.1 已完成（2026-09-12）—— **逐位完全复现 ✅**

**目的**：复现 `v1.0.0`（含 `+init_ckpt` 续训路径），并验证 `A0-legacy` profile 是交付配置的**完整快照**（G3）。

**命令**（task 侧 100% 来自 profile；非 task 参数只剩 6 项 ⇒ 这本身就是 profile 完整性的证据）：

```bash
cd drones/OmniDrones/scripts
<lz_env>/bin/python train.py task=profiles/A0-legacy algo=ppo headless=true \
  wandb.mode=online wandb.entity=fly-hust wandb.project=env_design_geo10_p01repro \
  wandb.group=NavVel-P0.1-repro wandb.run_name=cfb-dual-DR2-ctrlSync-p01-<1|2|3> \
  seed=<11|12|13> algo.entropy_coef=0.05 total_frames=20000000 save_interval=100 \
  +render_eval=false +init_ckpt=<geo8>/files/checkpoint_19693568.pt
```

> **新增 wandb 项目（后续批次沿用建议）**：`fly-hust / env_design_geo10_p01repro`，
> group `NavVel-P0.1-repro`，run group `run-20260912_195345`（`7wexmcym` / `bd51cg95` / `npgxdjor`）。

| 判据 | 门槛 | 实测 | 结论 |
|---|---|---|---|
| `arrival@0.2`(ON) 3-seed 均值 vs §0.5.5 基线 | ±0.02 | **Δ = 0.0000**（0.3412 vs 0.3412） | ✅ **PASS** |
| `checkpoint_final.pt` sha256 vs 交付 run | 记录 | **3/3 完全相同** | ✅ PASS |
| 训练侧 `eval/stats.*` / `train/stats.*` vs 交付 | 记录 | 逐项相同（`env_frames=19988480`、`entropy`、`cbf_violation` …） | ✅ PASS |
| 流水线（含 `+init_ckpt`）可用 | 必须 | 3/3 正常完成，19:53→20:08 ≈ 15 min | ✅ PASS |

**含义（重要）**：

1. **本机训练逐位确定**：同 (代码 commit, 配置, seed, 硬件, 库版本) ⇒ **权重 sha256 完全相同**
   ⇒ `P0.2 / A1a…A4` 的批次对比是**真单变量**（跨批次运行噪声 = 0），归因能力强于本计划预期。
2. 两点边界：
   - **不**证明跨机器可复现（未换机器/驱动/库版本验证）；
   - 逐位确定 ⇒ 3 seed 只提供**种间差异**（0.3086–0.3887，跨度很大），**不提供运行噪声估计**
     ⇒ §4.2 的 `±0.02` 对"同机重跑"偏宽松，对"换配置重训"才是有效门槛。
3. `A0-legacy` profile 已被证明**忠实且完整**（G3 闭环）。

**证据**：`navvel_export/navvel-cfb-v1.0.0-dual-p1-s11/repro_p01/`
（`REPRO.md` + 3 份训练日志 + 6 份评估日志 + `eval_metrics.json` + `SHA256SUMS`，全部 `sha256sum -c` 通过）。

### 0.5.7 执行注意（本机环境坑，2026-09-12 实测记录）

> P0.2 的**前两次尝试**因此作废：第一次静默卡死在 6.58M/20M 帧，第二次因 `PhysX PxgCudaDeviceMemoryAllocator failed to allocate memory` 崩溃。
> 两者都不是配置问题，而是**进程/资源管理**问题，记录以免重犯：

| # | 坑 | 现象 | 正确做法 |
|---|---|---|---|
| 1 | **`train.py` 调用 `setproctitle`** | 进程名变成 wandb `run_name`，`pgrep -f "train.py"` **找不到运行中的训练** ⇒ 我据此误判"训练已结束"，实际 3 个进程仍活着占 21 GiB | 用 `nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader` 判定，再 `ps -p <pid> -o stat=,etime=,cmd=` |
| 2 | **长任务不要 `wait`** | 之后在同一终端执行命令会连带 `wait` 及其子进程一起结束（进程无 traceback 直接消失） | `setsid nohup <cmd> > log 2>&1 < /dev/null &` + `disown -a`，把 pid 写入文件留档；**不 `wait`** |
| 3 | **训练期间不要 import `omni_drones`**（含 `--cfg job`、导出脚本、CPU 单测） | 触发 kit/GPU 资源争用：运行中的训练会**静默卡死**（100% CPU 但不写 checkpoint），新进程报 PhysX 显存分配失败 | 训练窗口内只做 `nvidia-smi` / `tail` / `grep` 等轻量监控；所有 Isaac 相关命令排到训练之外 |
| 4 | GPU 基线（启动段） | 3 seed × 1024 env 训练：**稳定后约 3.9 GiB/进程**（干净启动）；若看到 ~7 GiB/进程，说明有其它残留进程在抢显存 | 开训前先确认 `nvidia-smi` 无 compute apps |
| 5 | **长训练末期显存膨胀** ⇒ **并发上限是 2，不是 3** | 单进程显存随训练**单调增长**：~3.9 GiB（启动）→ **~11 GiB（20M 帧末端）**。3 路 ≈ 33 GiB > 32 GiB ⇒ P0.1 侥幸过关，P0.2 的 **s12 在最后一步崩**：`torch.OutOfMemoryError: Tried to allocate 364.00 MiB`，报 "Process 2918516 has 10.98 GiB / Process 2918518 has 10.98 GiB"，崩点在 `tensordict/_torch_func.py stack_fn` | **批次并发默认 `--parallel 2`**。必须 3 路时把 `task.env.num_envs` 降到 512（显存近半）。崩溃点在**收尾**，所以训练其实已跑完，只需单进程重跑该 seed |

**作废的 run（仅留档，勿引用）**：
第一次 `cfb-dual-chiA-p02-{1,2,3}` → `run-20260912_202653-{l6e8qgys,km9d5k5e,71obo25e}`（停在 6.58M 帧）；
第二次 `cfb-dual-chiA-p02-r2-{1,2,3}` → `run-20260912_2030{40,40,43}-{zf5njn30,afzw0f99,st1go87f}`（仅启动即崩）；
第三次的 **s12 一支** `bq3qb0ej` 因坑 5 在收尾 OOM（s11/s13 正常出 final），已**单进程重跑**为
`cfb-dual-chiA-p02-2-final2` → `njn50ubq`（见表 §0.5.8③）。本地目录已归档到 `/tmp/navvel_p02/void_runs/`。

### 0.5.8 P0.2（口径 A → `v1.1.0`）执行记录（2026-09-12）

**① 快照派生：`cfg/profiles/A.yaml`**

用 `scripts/make_geometry_profile.py` 新增的 **派生模式**从 `A0-legacy` 复制后**只改指定键**：

```bash
python scripts/make_geometry_profile.py --from-profile cfg/profiles/A0-legacy.yaml \
  --profile-id A \
  --set obstacle.drone_radius=0.10 --set obstacle.inflation=0.02 \
  --set cbf.r_safety_margin=0.05 --set cbf.use_brake_term=false \
  --out cfg/profiles/A.yaml
```

* 工具会打印**实际发生变化的键**（未变的 `--set` 不会被记成改动）：本次为 **3 个键** ——
  `obstacle.drone_radius 0.15→0.10`、`obstacle.inflation 0.05→0.02`、`cbf.r_safety_margin 0.10→0.05`
  （`cbf.use_brake_term` 本来就是 `false`，故无变化）。
* **独立复核**：`diff` 两份 profile 的 YAML 只有 **3 行**；再经 **hydra 组合后**逐键比对**也正好 3 行**。
* `obstacle.collision_margin` **保持 0.05**（D-1）；其余 142 个 leaf key 与 `A0-legacy` 逐位相同。
* 半径链（本地实跑 `omni_drones.utils.cbf` 复核）：**`r_s = r_o + 0.12`、`r_cbf = r_o + 0.17`** ✅ 与计划一致。
* ⚠️ **判撞口径也变了**：`r_s` 从 `r_o+0.20` 降到 `r_o+0.12` ⇒ P0.2 的"0 碰"与 P0.1 **不可直接比较**
  （这正是 §0.5.1 决策 3 要单独成批隔离口径 A 的原因）。`arrival` / 零介入率 / `h_min` 定义不变，
  仍可比。

**② 导出脚本 v2（配置驱动）—— 已完成并通过回归**（§2.4 红线）

v1 把整套 v1.0.0 几何（0.15/0.05/0.10、4×4 柱的固定 xy、K=8、T=1500 …）**硬编码**在脚本里；
口径 A 改了半径链，而 `r_cbf` 要写进 `meta.json` / `cbf_test.npz` 给部署侧 ⇒ **必须参数化**。改动：

| 项 | v1 | v2 |
|---|---|---|
| 几何/控制常量 | 硬编码 | 从 **profile 或 run `config.yaml`** 读（`--profile`，两种格式都认，自动解 wandb 的 `{value:}` 包裹） |
| 测试障碍布局 | 手写 4 柱 xy + 12 个固定自由球 | 用 env 自己的 **`ObstacleManager.sample_layout`（CPU）** 采样 ⇒ 布局天然与训练同规则、结构合法 |
| `obs_dim` / `K` / `obstacle_cfg` | 62 / 8 / 固定 | 由配置推导；`obs_safety != none` 显式报错（本导出器不镜像安全通道） |
| `meta.json` | — | **纯增量**：保留全部 v1 键与取值（`arena_bound_xy` 仍为标量、`cbf.r_si` 键名保留、`r_cbf` 文案在 brake-off 时逐字复现），只新增 `model_id`/`geometry_profile`/`test_vectors` 等 |

> 实现细节：障碍模块用 `importlib` **按文件加载**（与 `scripts/pillar_geometry_test.py` 同法），
> 因为走包路径会执行 `envs/single/__init__.py` → 拉入 Isaac Sim（无 `SimulationApp` 会失败）。

**回归证据（v1.0.0 配置 + v1.0.0 权重）**：

| 检查 | 结果 |
|---|---|
| 旧 `navvel_actor.ts` vs 已提交 `action_test_server.npy`（同一 `obs_test.npy` 输入） | `max|Δ| = 0.000e+00` |
| **新** `navvel_actor.ts` vs 已提交 `action_test_server.npy` | `max|Δ| = 0.000e+00` |
| 新旧 TorchScript 在同一 obs 上互相比较 | `max|Δ| = 0.000e+00` |
| `filter_velocity` 重算已提交 `cbf_test.npz` 的 `v_safe` / `fix_norm` | `max|Δ| = 0.0` |
| `meta.json` geometry/cbf 块 | 17 处差异**全部是新增键**，无一处改值 |
| `meta.json` 丢失的顶层键 | 0（schema 向后兼容） |

**③ 训练**：`task=profiles/A`，与 P0.1 **完全相同的 6 项非 task 参数**（`seed=11/12/13`、
`algo.entropy_coef=0.05`、`total_frames=20M`、`save_interval=100`、`+render_eval=false`、
`+init_ckpt=<geo8>`），wandb `fly-hust/env_design_geo10_p01repro`、group `NavVel-P0.2-chiA`、
run name `cfb-dual-chiA-p02-{1,2,3}-final`，run group **`run-20260912_203247`**
（`7gziinv0` / `bq3qb0ej` / `51rmfdcr`）。
> 前两次尝试的作废原因见 §0.5.7（环境坑，非配置问题）。

**s12 单进程重跑**（因坑 5 收尾 OOM，见 §0.5.7）：`cfb-dual-chiA-p02-2-final2` → run **`njn50ubq`**
（目录 `run-20260912_204807-njn50ubq`），单进程、其它参数逐字相同；日志尾
`Final Eval at 19988480 steps` + `Saved checkpoint to .../checkpoint_final.pt`，无 error。

**三个 seed 的产物（均为 `seed` 固定 + `total_frames=20M`）**：

| train seed | wandb run | `checkpoint_final.pt` sha256 |
|---|---|---|
| 11 | `7gziinv0` | `e05eba92f4d54b478b126397cc583f8edf9f2d7d403d95c872c08f0ff95236b1` |
| 12 | `njn50ubq`（重跑） | `0ed7ce8e2274727e113be13061381b4caa5c05b2c9d9b7dd25083e89547c6019` |
| 13 | `51rmfdcr` | `6f8fb83b3240443e4df03960ea6170eb696fae075b890487a6dfd4d2bd040f33` |

（wandb 汇总里 `env_frames = 19 988 480` 略小于 `20M`，是 update 粒度对齐所致，与 P0.1 的
`19693568` 帧存档点同源，三 seed 一致。）

**④ 结果**：见 §0.5.9。

---

### 0.5.9 P0.2 结果（2026-09-12）—— 口径 A 相对 A0 的收益与代价 **均已量化**

**① 验收评估**：6 次（3 seed × ON/OFF），协议与 P0.1 **逐字同构**（`512 envs × 600 步`、
`set_seed=1000+train_seed`、`eval_points=fixed`、ON/OFF 配对同一布局），6/6 `exit=0`，
`cbf_diag_steps = 307200 = 600×512`（覆盖全部步，非抽样）。`layout_fp` 同 seed 的 ON/OFF 完全一致。

| 指标（ON / OFF 均值） | **v1.0.0**（A0-legacy，`r_cbf=r_o+0.30`） | **v1.1.0**（口径 A，`r_cbf=r_o+0.17`） | Δ |
|---|---|---|---|
| `arrival@0.2` | 0.3412 / 0.3438 | **0.4733 / 0.4245** | **+0.1321** / +0.0807 |
| 零介入率 | 0.1613 / 0.1951 | **0.2429** / 0.2656 | **+0.0816** |
| `corr_p50`（中位修正） | 0.6385 / 0.6974 | **0.4678** / 0.5187 | **−0.1707** |
| **filter 依赖度** `OFF/ON` | **1.0076 ✅ PASS** | **0.8969 ❌ FAIL** | **−0.1107（由过转不过）** |
| `collision_envs` ON / OFF | 0 / 1 | **0 / 5**（s11:3、s12:2） | 判撞半径 0.20→0.12，**不可比** |
| `h_min^train` | −0.0500 | 0.0000 | ⚠️ 见 ③ |
| `stall_frac` / `dropped_relevant` | 0.0132 / 0.0000 | 0.0127 / 0.0001 | ≈ / ≈ |
| `min_clearance_global_min` | 0.0512 / 0.0492 | 0.0508 / 0.0459 | ≈ |
| `oob_envs_ever` / `crash_envs_ever` | 0 / 0 | **0 / 0** | ✅ |

**门禁（§4.1/§4.3）**：依赖度 ❌、零介入率 ❌、`arrival@0.2 ≥ 0.85` ❌、0 碰 ❌（OFF 5 个 env）、
0 OOB ✅、`stall ≤ 10%` ✅、`dropped_relevant < 1%` ✅、`h_min ≥ 0` ⚠️（名义 PASS，按 ③ 不计入）

**② 解读 —— 这是本批次最有价值的产出**

1. **口径 A 显著"松绑"了滤波器**：`r_cbf` 收到 `r_o+0.17` 后介入减少约 40%（零介入率 0.16→0.24），
   中位修正幅度 0.64→0.47 m/s，**到达率 +13.2 个百分点**。与 §0.5.5 的机制解释自洽：A0 的保守球
   几乎每步都绑定约束，扣掉的多是**无用的法向速度**。
2. **依赖度由"过"转"不过"**——**不要读成"变差"**。P0.1 的 1.0076 之所以过关，恰恰是因为滤波器
   **对任务结果毫无贡献**；口径 A 下撤掉滤波器到达率掉 10.3% ⇒ 滤波器**有真实贡献**。
   ⇒ 阶段 2 的命题（撤 filter 可飞）不但**更明确地不成立**，而且**失败原因从"滤波器无用"变成了
   "策略确实依赖滤波器"** —— 这正是 **P3** 要内化的东西，P0.2 为 P3 提供了一个**有信号、未饱和**
   的对照起点（A0 那一列是饱和的：依赖度 1.0076 已经把"滤波器无用"顶到天花板）。
3. OFF 出现 5 个碰撞 env 而 ON 全 0（同批次内可比）⇒ 一致支持"策略未内化安全"。
4. `dropped_relevant ≈ 0` ⇒ K=8 窗口在 M=28 下未把危险障碍挤出窗口，**§3.2 的"K 容量不足"风险在
   A 仍未出现**；`A3/A4` 柱数翻倍后必须重测（G8/G9）。

**③ ⚠️ 新发现的口径缺陷 G20 —— 不许把 `h_min ≥ 0` 当证据**

理论上应严格满足 `h_min = min_clearance − cbf_extra`（两把尺子只差标量 `cbf_extra`）。实测：

| 批次 | `cbf_extra` | `min_clearance`(ON) | 预测 | 实测 `h_min` | 一致？ |
|---|---|---|---|---|---|
| v1.0.0 | 0.10 | 0.0512 | −0.0488 | −0.0500 | ✅ 差 0.0012 |
| v1.1.0 ON | 0.05 | 0.0508 | +0.0008 | 0.0000 | ✅ 差 0.0008 |
| **v1.1.0 OFF** | 0.05 | 0.0459 | **−0.0041** | **0.0000** | ❌ **方向相反** |

**已排除**（本次实测）：诊断抽样（`cbf_diag_steps=307200=600×512`，覆盖全部步）；
障碍集合口径（CPU 探针实测 `ObstacleManager.pos=(4,28,3)`、`r_safe=(4,28)`，而 `max_slots=8`
**只截 obs 块**，滤波器拿到的是全部 28 个障碍 ⇒ 与 `min_clearance` 同集合）。
**待查**（P1 开训前必须定论）：`ep_min_clearance` 的重置时机/窗口；滤波器算 `h` 用的无人机位置
是否与 `update_min_clearance` 同一步；`r_safe` 与 `clearances()` 自算 r_s 是否同值。
**处置**：`v1.1.0` 的 `h_min≥0` **名义 PASS 但不计入结论**；建议 P1 前把安全门禁改挂
**`min_clearance`（全障碍、全步）**，`h_min` 暂降级为诊断量。

**④ 交付物**：`/home/lz/lzspace/navvel_export/navvel-cfb-v1.1.0-dual-p1-s11/`
（`navvel_actor.ts`/`obs_test.npy`/`action_test_server.npy`/`cbf_test.npz`/`meta.json` +
`run_config.yaml` + `eval_metrics.json` + `eval_logs/`（6 个）+ `train_s12_retry.log` +
`acceptance.md` + `lineage.json` + `SHA256SUMS`（**16/16 校验通过**））。
导出：TorchScript vs 参考 `max|Δ| = 0.000e+00`；`meta.json` 向后兼容（差异全为新增键 + 口径 A 的
3 个几何键 + 3 个随 run 变化的键）；`meta.sha256 == seed 11` ckpt 哈希 ✅。
**`_current` 仍指向 `v1.0.0`**（阶段 2 未通过 ⇒ 不晋升；`v1.1.0` 状态 = 候选）。

**⑤ 本批次带出的新缺口**：**G20**（上述 `h_min` 口径不一致，见 ③）。
另记录 **G21**：`scripts/acceptance_eval.py` 之前把**相对路径** checkpoint 透传给以
`cwd=scripts/` 运行的 worker，导致 6 次评估全部 `FileNotFoundError` 静默失败（日志里只有
torch 栈，`acceptance_eval` 只在末尾打 WARN）⇒ 已加 `os.path.abspath` 保护；**凡批量脚本向子进程
传路径一律先 absolutize**，且首次运行必须抽查子日志而非只看退出码。

**⑥ 结论**：`v1.1.0` = **候选，未晋升**。P0.2 达成了它的设计目的：**隔离"几何口径"这一个变量**，
量化其收益（+13.2 pt 到达率、−40% 介入）与代价（依赖度转红，暴露了真实的 filter 依赖），
为 P1（几何泛化）与 P3（撤 filter）提供了可比的、未饱和的起点。

---

## 1. 当前版本现状
### 1.1 交付物与谱系（已核实）

| 项 | 值 | 来源 |
|---|---|---|
| 模型 ID（本文自定，见 §2.2） | **`navvel-cfb-v1.0.0-dual-p1-s11`** | — |
| 模型名（meta.json） | `CFB ctrlSync-1`，dual-CBF PPO | `[fs]` |
| 交付 run | `run-20260909_191309-hpzc2m3r`（seed 11） | `[cfg]` |
| 同组 run（3 seed 并行） | `run-20260909_191309-72s1zkt6`(seed 12, ctrlSync-2)、`-pczh85ou`(seed 13, ctrlSync-3) | `[cfg]` |
| W&B | entity `fly-hust` / project `env_design_geo9` / group `NavVel` | `[cfg]` |
| 上游谱系（warm-start） | `init_ckpt = run-20260909_180042-r02a809m/files/checkpoint_19693568.pt`（`cfb-dual-warm-DR1-20M-s4`，project `env_design_geo8`，seed 4） | `[cfg]` |
| checkpoint sha256 | `4d604d6c30c9480bf1c59e564e1876b5c02dabcad9f72836ff5a2f331d25ed03` —— **与 `navvel_export/meta.json` 完全一致** | `[fs]` |
| 导出产物 | `/home/lz/lzspace/navvel_export/`：`navvel_actor.ts`（[1,62]→[1,4]）、`meta.json`、`obs_test.npy`、`action_test_server.npy`、`cbf_test.npz` | `[fs]` |
| 导出脚本 | 服务器 `OmniDrones/scripts/export_navvel_actor.py`；本工作区根目录有一份副本 `export_navvel_actor.py`（`K_SLOTS=8`、`MAX_STEPS=1500`、对拍门槛 actor `<1e-5`） | `[fs]` |
| 训练耗时（实测） | 19:13 起 → 19:27/19:28 落 `checkpoint_final.pt`，**≈14–15 min / 20M frames（3 run 并行）** | `[fs]` |

> ⚠ **交付模型不是 from-scratch**：它是 `geo8` 组（DR1 warm，20M）的下游 20M 续训。做版本升级判断时，
> `PATCH` 与 `MINOR` 的区别必须按"是否换了世界/口径"来定，而不是按"是否续训"。

### 1.2 交付 run 的完整配置（`v1.0.0` 基线口径，全部已核实）

**几何 / 障碍** `[cfg]`

| 键 | 值 | 备注 |
|---|---|---|
| `obstacle.max_slots` (K) | 8 | obs = 30 + 4K = **62 维** |
| `obstacle.num_scene` (M) | 16 | `n_pillars>0` 时被忽略，`M = 柱层球 + 自由球` |
| `obstacle.n_pillars` | 4 | 固定柱数 |
| `obstacle.pillar_layers` | 4 | **全 batch 同一层数**（`[code]` `_pillar_layer_zs(n)` 只接受单个 `n`） |
| `obstacle.pillar_radius` | 0.354 | = 0.5·√2/2 ⇒ 训练柱 = **0.5×0.5 m 方柱的外接球** |
| `obstacle.pillar_z_lo / z_hi` | 0.4 / 2.6 | 柱层 z = `linspace(0.4+0.354, 2.6-0.354, 4)` = `[0.754, 1.251, 1.749, 2.246]` |
| `obstacle.n_free_obstacles` | 12 | 自由球（`radius_choices [0.2,0.3,0.4]`） |
| **M 实际值** | **28** | 4×4 + 12 |
| `obstacle.drone_radius` / `inflation` | 0.15 / 0.05 | ⇒ `r_s = r_o + 0.20` |
| `obstacle.collision_margin` | 0.05 | `d_min < 0.05` 判撞 |
| `obstacle.danger_radius` | 0.6 | 危险区（log 罚/近障减速） |
| `obstacle.keepout_x` | 2.5 | 柱心 `|x| ≤ 2.5-0.354 = 2.146` |
| `obstacle.obs_dist_norm / obs_radius_norm` | 5.0 / 0.5 | `r_o/0.5` ⇒ 0.354→0.708 |
| `obstacle.obs_safety` | `none` | 无额外安全通道（obs 恒 62） |
| `obstacle.initial_clearance / goal_clearance / min_gap_between` | 0.15 / 0.35 / 0.25 | 可达性硬约束 |
| 场地 | `arena_bound [3,3]`、`z ∈ [0.15, 3]` | 6×6×3 m |
| `episode_sampler` | `edge`（起点 x=−2.8 线 → 目标 x=+2.8 线） | 每局必横穿 |

**CBF / 安全层** `[cfg]`

| 键 | 值 | 含义 |
|---|---|---|
| `cbf.mode` | `hybrid` | = 部署文档里的 "dual" 臂（filter + reward core） |
| `cbf.penalty_src` | `dual` | `w1·viol(v_nom) + w2·(1−exp(−corr²/σ²))` |
| `cbf.reward_weight` (w1) | 0.1 | violation 项 |
| `cbf.correction_weight` (w2) | 0.1 | gaussian correction 项 |
| `cbf.correction_sigma` | 0.5 | ≈0.28·v_max |
| `cbf.r_safety_margin` | 0.1 | |
| `cbf.use_brake_term` | **false** | ⇒ `cbf_extra = 0.10` ⇒ **`r_cbf = r_o + 0.30`** |
| `cbf.alpha / a_max / max_vel / filter_iterations` | 1.0 / 2.0 / 1.8 / 3 | |
| `cbf.h_penalty_weight` / `h_penalty_buffer` | **0 / 0** | **裕度势能已实现但默认关闭**（见 §1.3-①） |
| `filter_grad` | `detach` | env 不反传滤波 |

**奖励 / 训练超参** `[cfg]`

| 键 | 值 |
|---|---|
| `reward_scheme` | `f1`（`reward_fly_weight 1.5` + `reward_zone_weight 1.5`，无距离核） |
| `arrive_bonus` / `arrive_time_bonus` / `arrive_radius` / `arrive_hold_steps` | 40 / 40 / 0.5 / 50 |
| `reward_timeout_penalty` / `reward_crash_penalty` / `reward_oob_penalty` | 60 / 15 / 15 |
| `reward_action_smoothness_weight` | 0.2（速度指令层） |
| `reward_pbrs_weight` / `reward_time_cost` / `reward_gate_weight` | 0 / 0 / 0 |
| `soft_respawn` / `success_terminate` / `max_collisions` | **false / false / 1**（严格单命） |
| `curriculum` | `enabled=false`，`levels=[16]`，锁 M=28 全量 |
| `num_envs` / `max_episode_length` / `max_episode_length`(步) | 1024 / 1500 步 = 15 s @100 Hz |
| `total_frames` | 20 000 000 |
| `action_transform` / `vel_limit` | `velocity` / `max_vel 1.8`、`max_yaw_rate 1.5` |

**域随机化（DR）** `[cfg]`

| 项 | 值 |
|---|---|
| `randomization.drone.train.mass_scale` | `[0.97, 1.03]` |
| `...t2w_scale / f2m_scale / inertia_scale / drag_coef_scale` | `[0.8,1.2]` / `[0.8,1.2]` / `[0.8,1.2]` / `[0.9,1.1]` |
| `dr_noise_sigma`（执行层速度噪声） | **0.15 m/s** |
| `controller_sync_dr` | **true**（`ctrlSync-1` 的来源） |

> ⇒ `v1.0.0` 是 **DR2 + ctrlSync 已开**的模型；DR 不是这一阶段的待改变量，**P1–P5 一律沿用本表不动**。

### 1.3 现状与 `NAVVEL_RETRAIN_GUIDE.md` 假设的差异（必须知道，否则会照错文档干活）

| # | 指南里的说法 | 实际现状 | 影响 |
|---|---|---|---|
| ① | §B.2「`relu(−h)` 只在已违反时给梯度 ⇒ 必须**配**裕度势能，否则内化无从发生」 | **已实现**：`cbf.h_penalty_weight` + `cbf.h_penalty_buffer` → `h_boundary_penalty(dmin, extra, buffer, weight)`（`[code]` `omni_drones/utils/cbf.py:114`），`E1`（buffer=0）与 `E1-v2`（buffer>0）两版都有。交付 run 里两者均为 **0（关）** | 阶段 2 **不需要新写代码**，只需在 cfg 里开 `h_penalty_weight>0` + `h_penalty_buffer∈[0.1,0.2]`；§3.6 清单相应缩水 |
| ② | §B.2「四臂 = 奖励塑形臂」按 `use_r_cbf / use_r_fix` 两个 bool 描述 | 实际是 **`cbf.mode`（none/filter_only/reward_only/hybrid）× `cbf.penalty_src`（nominal/correction/gaussian/dual）**；`dual` 臂 = `mode=hybrid + penalty_src=dual + correction_weight>0` | 实验矩阵的"臂"要用实际键名表达，见 §3.4 |
| ③ | §B.5 #5「`scripts/eval.py` 支持 `filter_mode`」 | `scripts/` 下**没有** `eval.py`，实际是 **`scripts/eval_ckpt.py`** | 改动落点改到 `eval_ckpt.py` |
| ④ | §A.6(4)「`navvel_obstacles_box.yaml` 模板 + `*_box` 可视化（v10 已就绪）」 | **本工作区找不到任何 `navvel_*.yaml` / `navvel_cbf.py` / `navvel_offline_check.py`**（`find` 全盘无结果） | 部署侧代码在另一个仓库/机器上（缺口 G1）；1b 的"已有基础设施"结论**不可假设**，需先定位 |
| ⑤ | §A.1「`n_free_obstacles` 需新增 0 开关」 | 键**已存在**，且 `cfg/task/NavVel.yaml` 仓库默认已是 `n_free_obstacles: 0`；交付值 12 只由命令行 override 带入 | 仓库默认 ≠ 交付口径（缺口 G3），cfg 快照必须入库 |
| ⑥ | §B.1「新增 `p_filter`（概率生效/退火）」 | **确认不存在**：`grep p_filter` 无命中；`cbf.py` 只有 `CBFVelocityFilter` 确定性变换 | 阶段 2 唯一必须新写的训练侧代码，见 §3.4 |
| ⑦ | §A.2「`K=8` 容量风险」 | 已确认 `_pillar_layer_zs` 全 batch 单层数、`M = n_pillars*layers + n_free`；柱数上限由 `M` 与 prim 预算决定 | 缺陷 G9/G10/G11 |

### 1.4 现状缺口清单（G1–G12）

| # | 缺口 | 证据 | 阻塞谁 |
|---|---|---|---|
| **G1** | **部署侧代码不在本工作区**（`navvel/`、`navvel_deploy.yaml`、`navvel_obstacles*.yaml`、`navvel_cbf.py`、`navvel_offline_check.py`） | `[fs]` find 无结果 | 版本对齐自动化、1b 对拍、真机验收记录 |
| **G2** | 无 `p_filter`（训练期 filter 生效概率/退火）钩子 | `[code]` | 阶段 2 第一轮 |
| **G3** | 仓库 `cfg/task/NavVel.yaml` 默认 ≠ 交付配置（`n_pillars: 0` vs 4、`n_free_obstacles: 0` vs 12、`num_scene: 16`） | `[cfg]` | 复现性；交付配置只活在 wandb `files/config.yaml` |
| **G4** | `drones/` 仓库**无 tag、无交付 commit**；`NAVVEL_RETRAIN_GUIDE.md`、`Navvel_dynamic_obs_plan.md`、`project_summary.md`、`plan_before/`、`figures/` 全部 untracked；`OmniDrones` 子模块有未提交改动 | `[fs]` `git log/status` | 整个版本管理方案的前提 |
| **G5** | `navvel_export/` 平铺、无版本号、无 run id、无 `run_config.yaml`、无 `SHA256SUMS` | `[fs]` | 产物不可变与回滚 |
| **G6** | `eval_ckpt.py` 是否输出 `filter 依赖度 / 零介入率 / h_min^train / min TTC` **未确认**；`--no-cbf` 等部署开关也未核 | `[待确认]` | §4 全部量化门槛 |
| **G7** | `radius_choices` 在 `n_free_obstacles=0` 后**语义失效**（没有任何障碍用它） | `[code]` | 1a 的 cfg 清理 |
| **G8** | **柱场拓扑可通行性校验未实现**（`arena1_layout_check.py` 是球布局检查） | `[fs]` scripts 列表 | A3/A4（窄通道不可行 ⇒ 整体退化） |
| **G9** | 逐柱独立 `layers / z_lo / z_hi` **未实现**（全 batch 单一层数） | `[code]` `_pillar_layer_zs` | A2 |
| **G10** | `pillar_side`、`n_pillars_range`、`pillar_layers_range`、`min_corridor` **cfg 键不存在** | `[cfg]` | A1b–A4 |
| **G11** | 柱数/层数上限未做**显存与物理预算预检**：8 柱 × 6 层 = **48 ball/env × 1024 env**（现状 28×1024） | `[code]` 推算 | A3/A4 开训可行性 |
| **G12** | 交付模型的 **3 seed 成绩表**（0.891/0.855 是哪个 seed / 3-seed 均值？）未在仓库内留档 | `[待确认]` | §4.2 A0 复现判据 |
| **G13** ✅已修 | **外层 `drones/` 仓库无 git 提交身份**（`user.name`/`user.email` 全未配置，`git commit` 直接失败） | `[fs]` `git config --get` 空 | K1 可执行性；**已设 repo-local 身份 = 与子模块一致（`pink-L`）** |
| **G14** ✅已修 | `drones/IsaacLab/` = **169 MB、自带 `.git` 的嵌套仓库**，未作为 submodule 登记，永久污染 `git status` | `[fs]` `du -sh`、`IsaacLab/.git` | 版本管理噪音；**已加入 `drones/.gitignore`**；若要钉版本需登记为 submodule |
| **G15** | **`cfg/algo/ppo.yaml` 不存在，且 git 全历史从未有过**；`algo=ppo` 的超参来自**代码内 ConfigStore**（`omni_drones/learning/ppo/ppo.py:59` `cs.store("ppo", node=PPOConfig, group="algo")`，另有 `ppo_priv`/`ppo_priv_critic`） | `[code]` + `[fs]` find 零命中；`train.py --cfg job` 可组合出 `algo:{name: ppo, train_every: 32, ppo_epochs: 4, num_minibatches: 16, entropy_coef: 0.001, …}` | **训练锚 §2.3 必须含代码 commit**，不能只靠 cfg 快照；`run_config.yaml` 里的 `algo.*` 是解析结果、非来源 |
| **G16** | **交付成绩 `ON 0.891 / OFF 0.855` 在仓库内无留档，且无法从 wandb 复现**；`wandb-summary.json` 只有训练内窗口 eval（3-seed `success_rate` 均值 **0.4320**，口径与 §4.2/§4.3 验收不同构） | `[fs]` 3 个 run 的 `wandb-summary.json` | **P0.1 判据原文（"3-seed 均值与交付成绩一致"）不可用**；**✅ 2026-09-12 已按 D-5 重建新基线**（`arrival@0.2` ON **0.3412** / OFF **0.3438**，§0.5.5）—— **旧 0.891/0.855 仍来源不明**（新基线与之不同协议，不可直接比） |
| **G17** | ~~**`scripts/wandb/` 被 `.gitignore`（OmniDrones/.gitignore:135 `wandb/`）** ⇒ 全部 `checkpoint_final.pt` 只存在于磁盘单点，无备份、无校验清单~~ **⚠️ 2026-09-12 复核后降级**：`train.py:262-270` 会把最终 checkpoint 作为 **wandb artifact `NavVel-ppo`** 上传（同时 run files 里也传 `config.yaml`/`output.log`）⇒ **存在异地副本**，风险远低于原描述 | `[fs]` `git check-ignore -v` + `[code]` `train.py` + P0.1 日志 `uploading artifact NavVel-ppo` | 剩余缺口仅"无本地归档/校验清单" —— 本轮已把 sha256 写进注册表与 `lineage.json`、并在各 `SHA256SUMS` 中留档 |
| **G18** | `scripts/arena1_layout_check.py`（CPU 单测）**当前必崩**：`torch.as_tensor(task.fixed_init, ...)` 遇到仓库默认 `cfg/task/NavVel.yaml` 的 `fixed_init: null` | `[fs]` 实跑 `TypeError: must be real number, not NoneType` @ line 27 | 与本次改动**无关**（K5 未触碰该文件/该键）；但会让 CPU 回归套件常红 ⇒ 建议加 `None` 守卫或改从 profile 读 |
| **G19** | **`OmniDrones/.gitignore:150` 忽略 `*.sh`** ⇒ 本仓库内 shell 脚本无法入库（本轮 runner 因此改写为 Python） | `[fs]` `git check-ignore -v` | 后续若需 shell 工具，要么 `git add -f`，要么写 `.py`（已按后者处理） |
| **G20** | **`h_min^train` 与 `min_clearance − cbf_extra` 不一致**（P0.2 的 OFF 列：预测 −0.0041、实测 0.0000，方向相反）⇒ **`h_min ≥ 0` 这条安全门禁目前不可作为证据**。已排除诊断抽样（`cbf_diag_steps=307200=600×512`）与障碍集合（CPU 探针：`pos=(4,28,3)`、`max_slots=8` 只截 obs 块）两种解释 | `[run]` P0.2 六个 `eval_metrics.json` × P0.1 基线 × `/tmp/navvel_p02/probe_obstacle_shapes.py` | **P1 开训前必须定论**（见 §0.5.9③）：查 `ep_min_clearance` 的重置窗口 / 滤波器算 `h` 用的位置是否与 `update_min_clearance` 同一步 / `r_safe` 与 `clearances()` 的 r_s 是否同值。**临时处置**：安全门禁改挂 `min_clearance`（全障碍、全步），`h_min` 降级为诊断量 |
| **G21** | **批量脚本向子进程传相对路径会静默全挂**：`acceptance_eval.py` 的 worker 以 `cwd=scripts/` 跑 `eval_ckpt.py`，我传了相对 checkpoint ⇒ `FileNotFoundError`，6 次评估全失败；而 runner 只在末尾打 WARN，只看退出码不会发现 | `[run]` `/tmp/navvel_p02/eval/s11_on.log` 的 torch 栈 | 已在 `run_one()` 加 `os.path.abspath`；**约定：批量脚本向子进程传路径一律先 absolutize，且首次运行必须抽查子日志内容（grep 错误关键字），不能只看 `exit code`** |

### 1.5 现状的一句话总结

> **模型侧**：一个双 seed 谱系下 warm-start 出来的 20M 续训模型（`hybrid+dual`），在 **0.5 m 柱 + 12 自由球 + 训练口径 `r_cbf=r_o+0.30`** 的世界里达到 ON 0.891 / OFF 0.855（0 碰），已导出 TorchScript 且 sha256 可对，**但它的世界与真机（0.6 m 方柱、部署口径 `r_cbf=r_o+0.17`）口径不一致**。
> **工程侧**：训练侧代码完备度高（裕度势能、dual 奖励、obs 安全通道、margin gate 全都已实现），**但版本管理为零**（无 tag、无 cfg 快照入库、产物平铺），**且部署侧仓库不在本工作区**——所以下一步的第一件事不是改几何，而是**把版本与快照钉住**（P0）。

---

## 2. 版本管理方案

### 2.1 版本号语义

`navvel-cfb v<MAJOR>.<MINOR>.<PATCH>`

| 位 | 触发条件 | 是否红线（必须重导+重对拍） | 例子 |
|---|---|---|---|
| **MAJOR** | **obs 维度或顺序**、**动作语义/维度**、**time_encoding 语义**（T）变化 | ✅ 是 | 1b 的 `obs_v3`（62→86/114）；阶段 3 的 `obs_v4` |
| **MINOR** | **世界/几何/安全口径**变化（障碍形状尺寸、柱数与层数分布、场地拓扑、`r_s`/`r_cbf` 半径链、DR 开关） —— obs 维度不变但**输入分布或安全语义变** | ⚠️ 仅当缩放常量变才升级为红线 | P0.2 口径 A（`v1.1.0`）；P1 几何泛化（`v1.2.0`） |
| **PATCH** | 同口径下的**重训 / 超参 / 奖励权重 / seed 扩增** | ❌ 否（但仍要重导 + 更新 sha256，因为权重变了） | P3 的臂与 `p` 调度；同组补 seed |

**附加后缀（不进版本号，进模型 ID）**：`-<arm>-p<filter>-s<seed>`
- `<arm>` ∈ `naive | reward_only | filter_only | dual`
- `p<filter>` ∈ `p1`（always-on）/ `pann`（anneal）/ `p0`（always-off，裸策略）
- 例：`navvel-cfb-v1.2.0-dual-p1-s11`

> **一次重训 = 一个 run group**：同一 `wandb.run_name` 前缀 + ≥3 个 seed 目录。**版本号由 run group 决定，不由单个 seed 决定**；注册表里一行 = 一个 run group（3 seed 均值 ± 极差 + 指向发布的那个 seed）。

### 2.2 产物目录规范（修复 G5）

```
navvel_export/
  <model_id>/
    navvel_actor.ts            # TorchScript actor, [1,obs_dim] -> [1,action_dim]
    meta.json                  # obs/action/geometry/cbf/action_post（沿用现有 schema）
    run_config.yaml            # ★ 交付 run 的 files/config.yaml 原样拷贝（修复 G3）
    obs_test.npy               # 对拍输入
    action_test_server.npy     # 服务器参考输出
    cbf_test.npz               # CBF 参考向量
    SHA256SUMS                 # 覆盖以上全部文件 + checkpoint_final.pt
    lineage.json               # ★ run_id / run_name / seed / init_ckpt / 上游 model_id
    acceptance.md              # ★ 本 model_id 的验收记录（§4.5 模板填写结果）
  _current -> <model_id>       # 软链：当前"现役"指针（回滚只改这里）
```

`lineage.json` 最小模板：

```json
{
  "model_id": "navvel-cfb-v1.0.0-dual-p1-s11",
  "created": "2026-09-09",
  "wandb": {"entity": "fly-hust", "project": "env_design_geo9",
            "run_id": "run-20260909_191309-hpzc2m3r",
            "run_name": "cfb-dual-DR2-ctrlSync-1", "seed": 11},
  "init_ckpt": "run-20260909_180042-r02a809m/files/checkpoint_19693568.pt",
  "ckpt_sha256": "4d604d6c30c9480bf1c59e564e1876b5c02dabcad9f72836ff5a2f331d25ed03",
  "obs_version": "obs_v2", "obs_dim": 62, "action_dim": 4,
  "geometry_profile": "A0-legacy", "cbf_extra": 0.10,
  "arm": "dual", "p_filter": "always-on",
  "status": "retired"
}
```

### 2.3 三类锚点与一致性契约

| 锚点 | 位置 | 必须互相一致的量 |
|---|---|---|
| **训练锚** | git tag `navvel-cfb-v<X.Y.Z>` + `run_config.yaml` + wandb run id | `obs_dim`、`K`、`obs_dist_norm/obs_radius_norm`、`drone_radius/inflation`、`r_safety_margin`、`use_brake_term`、`alpha`、`max_vel`、`time_encoding`(=step/1500)、`action_transform`、clamp 顺序 |
| **导出锚** | `navvel_export/<model_id>/` + `SHA256SUMS` + `meta.json` | 同上 + checkpoint sha256 + 对拍残差 |
| **部署锚** | `navvel_deploy.yaml`（含 `model_id` + `sha256` + 几何常量） | 同上；**启动时自检**：读 `meta.json` 比对本地常量，不一致拒绝起飞 |

**不一致的处理规则**：以 **训练锚** 为准 → 重新导出（不改训练）→ 更新部署锚 → 若训练锚本身要改，则按 §2.1 升版本号并走红线流程。

### 2.4 红线：必须重导 TorchScript + 重跑离线对拍

下列任一改动 ⇒ **必须**重跑 `scripts/export_navvel_actor.py` + `navvel_offline_check.py`：

1. obs 维度/顺序/K/任何归一化常量（`obs_dist_norm`、`obs_radius_norm`、新增通道）
2. `time_encoding`（T）或 `max_episode_length`
3. 动作语义、`vel_limit`、`cbf.max_vel`、clamp 顺序
4. CBF 数学（`alpha`、半径链 `margin/brake/drone_radius/inflation`、投影实现、`filter_iterations`）
5. `controller_sync_dr` / `dr_noise_sigma`（影响"策略实际面对的动作-结果映射"）

**对拍门槛（沿用，不得放宽）**：actor 逐元素 `max|Δ| < 1e-5`；CBF 参考向量 **0 差**。对拍记录写进 `acceptance.md`。

### 2.5 模型注册表（新建 `drones/NAVVEL_MODEL_REGISTRY.md`）

| model_id | 状态 | obs | geometry_profile | arm / p | run_id | ckpt sha256(前 12) | 阶段 1 验收 | 阶段 2 验收 |
|---|---|---|---|---|---|---|---|---|
| `navvel-cfb-v1.0.0-dual-p1-s11` | **现役** | obs_v2/62 | A0-legacy (`r_cbf=r_o+0.30`) | dual / always-on | run-20260909_191309-hpzc2m3r | `4d604d6c30c9` | n/a（旧世界） | 待测（基线） |
| `navvel-cfb-v1.1.0-dual-p1-s11` | **候选**（P0.2 已测，未晋升） | obs_v2/62 | A（`r_cbf=r_o+0.17`） | dual / always-on | `run-20260912_203247-7gziinv0`（seed 11） | `e05eba92f4d5` | n/a（球近似） | ✅ 已测 **不通过**（依赖度 0.8969；见 §0.5.9） |
| …… | | | | | | | | |

状态机：`候选 → 验证中 → 现役 → 退役`（产物**不可变**；晋升只改 `_current` 软链与状态列）。

### 2.6 回滚策略

1. **模型回滚**：改 `navvel_export/_current` 指向上一个"现役" `model_id`，同步 `navvel_deploy.yaml` 的 `model_id/sha256`，跑一次部署侧自检。
2. **训练世界回滚**：每个 `geometry_profile` 保留一份 `cfg/profiles/<profile>.yaml` **完整快照**（不要依赖命令行 override）；回滚 = 换 profile 文件。
3. **代码回滚**：`git tag` 是唯一权威；子模块 `OmniDrones` 的变更必须**先提交再打 tag**（当前它是 `M` 状态，属于未设防状态）。
4. **真机对照保留**：现场保留现有障碍布置，`A0-legacy` 模型与 cfg 不入库**不得**删除。

### 2.7 P0 必须完成的入库动作（修复 G4/G5）

| # | 动作 | 命令/产出 |
|---|---|---|
| 1 | 提交全部计划文档与脚本副本 | `git add drones/*.md plan_before/ figures/ export_navvel_actor.py` → commit |
| 2 | 提交子模块改动并打 tag | `cd drones/OmniDrones && git add -A && git commit -m "navvel: cfb v1.0.0 baseline" `；`cd .. && git tag navvel-cfb-v1.0.0` |
| 3 | 迁移导出物到 `<model_id>/` 目录 + 生成 `SHA256SUMS` + `lineage.json` | 见 §2.2 |
| 4 | 落地 `cfg/profiles/A0-legacy.yaml`（把交付 run 的 override 全部固化） | 从 `run-.../files/config.yaml` 反填 |
| 5 | 建 `NAVVEL_MODEL_REGISTRY.md` 并填第一行 | §2.5 模板 |
| 6 | 建 `navvel_export/_current` 软链 | `ln -sfn navvel-cfb-v1.0.0-dual-p1-s11 _current` |

### 2.8 版本管理范围的明确排除（本次未纳入）

- 场地/硬件布置图、真机障碍实测尺寸表、动捕刚体标定文件 —— 本次**不纳入**统一版本管理，
  仅要求在真机验收记录（§4.5）里以文字/截图留档。若后续现场障碍表复查频繁，再单独建
  `navvel_site_registry.md`。

---

## 3. 重训计划（分批，保留归因）

### 3.0 批次总览

```mermaid
flowchart TD
  P0["P0 钉版本可复现<br/>不改训练变量<br/>A0 复现 + A0' 仅口径A"]
  P1["P1 = 阶段1a 几何泛化<br/>A1a 去自由球 → A1b 底面0.6 → A2 逐柱层高 → A3 拓扑 → A4 交付"]
  P2["P2 = 阶段1 真机验收<br/>方体场地 N0-N3, filter ON, 逐档 0 碰"]
  P3["P3 = 阶段2 第一轮<br/>臂 x p_filter 矩阵, 目标 依赖度>=0.95"]
  P4["P4 = 阶段1b<br/>obs_v3 升维 + K=12 + 方体SDF CBF, 一次重导+对拍"]
  P5["P5 = 阶段2 第二轮 + 整机交付<br/>方体精确口径复验, N0-N3 beta 然后 alpha"]
  D["交付: 无 runtime filter 可飞<br/>navvel-cfb v2.0.0"]
  P0 --> P1 --> P2 --> P3 --> P5
  P2 --> P4 --> P5
  P3 --> P4
  style P0 fill:#eef
  style P5 fill:#dfd
  style D fill:#dfd
```

**纪律**：批次内**只有一个变量维度**在动（几何 ≠ 口径 ≠ 奖励 ≠ DR ≠ obs 维度）；`DR / 奖励基座 / 场地尺寸 / T=1500 / 单命制` 在 P0–P5 全程冻结（见 §1.2 表）。

### 3.1 P0 —— 钉住"可复现的现状"（不改任何训练变量）

| 子批 | 配置 | 唯一目的 | 判据 |
|---|---|---|---|
| **P0.1** | `A0` = 交付口径原样（4 柱×4 层 `r=0.354`、12 自由球、`side=0.5`、口径 legacy `0.15/0.05/margin 0.1`、`hybrid+dual`、3 seed 11/12/13） | 复现 `v1.0.0`，确认流水线仍在（含 `init_ckpt` 续训路径） | **✅ 2026-09-12 完成，逐位复现**：`arrival@0.2`(ON) 3-seed 均值 **Δ=0.0000**、3 seed 的 `checkpoint_final.pt` **sha256 与交付完全相同**。详见 §0.5.6。判据已由"±0.02"收紧为"**sha256 相同**"（同机） |
| **P0.2** | `A0′` = A0 + **仅**口径 A（`drone_radius 0.10 / inflation 0.02 / r_safety_margin 0.05 / use_brake_term=false` ⇒ `r_s=r_o+0.12`、`r_cbf=r_o+0.17`） | **隔离"口径 A"这一个变量**，得到阶段 2 的基线；同时产出 `v1.1.0` | **✅ 2026-09-12 完成**（详见 §0.5.9）：ON/OFF 双列已记录；**预期被证实且更细致** —— 到达率 ON 0.3412→**0.4733**、零介入率 0.1613→**0.2429**（介入减 40%）；**依赖度 1.0076(过)→0.8969(不过)**，即失败原因由"滤波器无用"变成"滤波器有真实贡献"；OFF 碰撞 env 1→5（同批次内可比）。判据：三 seed 全出 final + 6/6 验收 `exit=0` ✅ |

> **为什么 P0.2 必须在几何变化之前**：口径 A 会同时改变**碰撞判定半径**（`r_s` 从 `r_o+0.20` → `r_o+0.12`），
> 即"什么算撞"变了 ⇒ 旧 run 的"0 碰"与后续所有"0 碰"**不可直接比较**。先把这条基线单独立出来，后面 A1–A4 的成绩才有参照。
>
> **待你确认的子决策 D-1**：是否连 `collision_margin` 一起对齐？建议 **保持 `0.05`**（只动 `drone_radius/inflation`），
> 以免同时改"判撞阈值"和"判定半径"两个量。

**P0 产出**：`v1.0.0` 入库（§2.7 六项动作全绿）+ `v1.1.0` 候选 + `geometry_profile: A` 快照。

### 3.2 P1 —— 阶段 1a：几何泛化（A1a → A1b → A2 → A3 → A4）

全部在 **口径 A** 上执行（即继承 P0.2），逐组单变量。**obs 保持 62 维、K=8 不变**（红线留到 P4，见决策 5）。

| 子批 | 柱数 | 每柱层数 | 层高 | 自由球 | 底面 `side` | 新增拓扑 | 隔离出的变量 | 期望观察 |
|---|---|---|---|---|---|---|---|---|
| **A1a** | 4 固定 | 4 固定 | 固定 0.4–2.6 | **0** | 0.5 | — | 去自由球 | `r_o` 通道仍 0.708；CBF 介入率应下降 |
| **A1b** | 4 固定 | 4 固定 | 固定 0.4–2.6 | 0 | **0.6** | — | **底面 0.5→0.6**（`r=0.4243`，`r_o` 通道恒 0.8486） | obs 半径通道信息量→0（可接受） |
| **A2** | 4 固定 | **逐柱 2–6** | 逐柱随机 `z_lo/z_hi` | 0 | 0.6 | — | 高度多样性（修 G9） | 高度维度泛化 |
| **A3** | **2–8 随机** | 逐柱 2–6 | 逐柱随机 | 0 | 0.6 | **窄通道 / L 形遮挡 + 可通行性格筛**（修 G8/G10） | 布局多样性 | 布局泛化；观察是否出现"漏障碍" |
| **A4** | 2–8 | 逐柱 2–6 | 逐柱随机 | 0 | 0.6 | 同 A3 + 格筛 | **交付配置冻结** | `≥3 seed`（建议 5）；通过 §4.2 全部门槛 |

**A3/A4 的硬约束（G8，必须实现）**

- 采样后做**可通行性校验**：起点↔终点连通性（栅格/可见性图），或退化为"存在一次拐弯的走廊"；
- 走廊净宽下界：`min_corridor_width ≥ 2·(r_o + drone_radius + inflation) + 0.25 m`（口径 A 下 `r_o=0.4243` ⇒ **≥ 1.10 m**）；
- 保留现有"起点/终点净空 + 障碍互距 + `keepout_x`"校验（`[code]` `_sample_pillar_mixed` 已有），把校验从"净空"扩到"连通性"；
- 新增 `scripts/pillar_layout_check.py`（CPU 单测，风格对齐 `arena1_layout_check.py`）。

**A2/A3 的 `M` 与显存预检（G11）**：`M = n_pillars × layers`（`n_free=0`），最大 `8×6=48`（现状 28）。
⇒ **A3 前先跑 1 次 `n_pillars=8, layers=6` 的 3-iter smoke test**，确认 1024 env 下不 OOM、物理不炸（`sim.gpu_*` 容量）；若超预算，把 `n_pillars_range` 上界降到 6（`M≤36`）。

**A2/A3 的 obs 容量风险（决策 5 的代价）**：K=8 时"最近 8 个"可能全落在 1–2 根柱上（每柱最多 6 层）。
本批**不升 K**，改为**量化风险**：在 `eval_ckpt.py` 里加统计 `dropped_relevant = #{i : d_i < danger_radius 且未进 obs 窗口}`。
若 A3 出现"碰撞但 obs 无对应障碍"的归因，或 `dropped_relevant > 0` 的步占比 >1%，则**提前升级 P4 的 K 部分**。

### 3.3 P2 —— 阶段 1 真机验收（filter ON）

在 A4 冻结布局 + 现场方体场地（`side=0.6` 实测中心/尺寸）上按 §4.4 阶梯 N0–N3 执行，
**使用部署默认配置（filter ON）**，判据见 §4.2；真机判定日志**同时**记录 `d_min`（球口径）与 `box_net`（方体净空），两值之差 = 外接球保守量。

### 3.4 P3 —— 阶段 2 第一轮：臂 × `p_filter` 矩阵（新增代码 G2）

**因子**

- **F1 臂**（实际键名，见 §1.3-②）
  | 臂 | `cbf.mode` | `penalty_src` | `correction_weight` | 说明 |
  |---|---|---|---|---|
  | `naive` | `none` | — | — | 无滤波无 reward core |
  | `reward_only` | `reward_only` | 自动回退 `nominal` | 0 | 不滤波，只罚 `viol(v_nom)` |
  | `filter_only` | `filter_only` | `nominal` | 0 | 滤波 + 罚 violation |
  | `dual` | `hybrid` | `dual` | `w2>0`（起点 0.1） | 滤波 + `w1·viol + w2·gauss` |
- **F2 `p_filter`**（训练期 filter **执行**概率）：`p1`（1.0）/ `pann`（1→0 线性或分段）/ `p0`（0）
- **F3 裕度势能**（`h_penalty_weight` / `h_penalty_buffer`）：起点 `w_h>0`、`buffer≈0.1–0.2`，与 `obs_safety` **不改**（保持 `none`）
  > 为什么 F3 必须开：`relu(−h)` 只在已违反时给梯度 ⇒ 单靠 `dual` 的 violation 项**几乎无梯度**，
  > "内化"不会发生（指南 §B.2 的判断，实现已就绪）。F3 是本轮能否达标的关键开关。

**有效矩阵 = 8 个配置**（不是机械的 4×3=12）

| 臂 \ p | `p1` | `pann` | `p0` |
|---|---|---|---|
| `naive` | ✅（= 纯基线） | —（无 filter 无意义） | —（同 `p1`） |
| `reward_only` | ✅ | —（本就不执行 filter） | —（同上） |
| `filter_only` | ✅ | ✅ | ✅ |
| `dual` | ✅ | ✅ | ✅ |

⇒ **8 配置 × 3 seed = 24 runs ≈ 2 h**。若预算充裕，`p0` 组补到 5 seed（`p0` 是"裸策略"形态 α 的直接来源，最需要统计置信）。

**核心机制（`p` 只控执行，不控计算）**

- `a_exec = a_cbf(a)` if `rand < p` else `a`；
- 只要该臂的奖励含 correction 项（`filter_only` / `dual`），**始终计算** `a_cbf` 与 `‖Δa‖`（否则 `p=0` 时没有梯度）；
- ⇒ `p=0` 也有意义：策略裸奔执行，却被罚"偏离 CBF 建议" = **软蒸馏 / 无 filter 模仿**。

**实现要点（G2）**

| 落点 | 改动 |
|---|---|
| `omni_drones/utils/cbf.py` | `CBFVelocityFilter` 增 `p_filter`（标量或 callable）+ 自身 step 计数；把 `a_cbf`、`‖Δa‖`、`intervened = (‖Δa‖>0)` 写入 `info`。**`filter_velocity` 数学不动**（保对拍） |
| `omni_drones/envs/single/nav_vel.py` | 用**同一** schedule（按 `env.step` 计数）计算 `p`，供奖励 core 与统计使用；`info` 增 `p_filter / a_cbf / corr / intervened` 供 `eval_ckpt.py` 直接取用 |
| `cfg/task/NavVel.yaml` | `cbf.p_filter_schedule: {mode: always_on\|anneal\|always_off, start: 1.0, end: 0.0, anneal_frames: N}`、`cbf.h_penalty_weight`、`cbf.h_penalty_buffer` |
| `scripts/eval_ckpt.py` | 支持 `filter_mode ∈ {on, off}`；输出 §4.3 全部指标 |

> ⚠ **PPO 口径警告（沿用指南 §B.1）**：`p>0` 时实际执行的不是策略采样的动作，而 PPO 似然仍对 `a` 计算 ⇒
> "梯度-结果不一致"。必须监控 `ratio / KL / entropy` 与 `std(a)` 是否塌缩；
> `pann` 需与 `clip_range` 同步放宽；`p1` 与 `p0` 必须**同 seed 同预算**才可比。

### 3.5 P4 —— 阶段 1b：obs_v3 升维 + K 扩容 + 方体 SDF CBF（**一次性红线批**）

三件事**合并成一次**重导 + 重对拍（避免做两遍），产出 `v2.0.0`：

| # | 项 | 具体 |
|---|---|---|
| 1 | `obs_v3` | 障碍块 `4 → 7` 维：`[rpos(3)/5, sdf/0.6, 法向(3)]`（推荐，与 CBF 同几何量）；或 `8` 维 `[rpos(3)/5, 半尺寸(2~3)/0.6, yaw_sin, yaw_cos]`。**必须冻结**后重导 |
| 2 | `K: 8 → 12` | obs 维度：`30 + 7×12 = 114`（SDF 版）/ `30 + 8×12 = 126`（半尺寸版）。同时加"同柱最多计入 3 层"防同柱刷满窗口 |
| 3 | 方体 CBF | `h_i = sdf_OBB(p) − (drone_radius + inflation + margin)`，`∇sdf` 分面/棱/角三类（单位外法向，有界）。**不做**"每面一个 CBF"（约束 ×6，投影失去闭式解） |
| 4 | 导出/对拍 | `export_navvel_actor.py` 的 `K_SLOTS`、obs 布局、CBF 参考向量同步改；门槛不变（actor `<1e-5`、CBF 0 差）；`navvel_deploy.yaml` / `navvel_obstacles_box.yaml` 更新 sha256 |
| 5 | 复训 | 用 **P3 选出的最优臂**（依赖度最高者）+ A4 布局 + 口径 A |

**前置（未满足不许开 P4）**：P2（真机方体场地 filter ON 0 碰）+ P3（`filter 依赖度 ≥ 0.95`）+ G1（部署侧仓库定位）。

### 3.6 P5 —— 阶段 2 第二轮 + 整机交付

1. 方体精确口径下**复验 filter 依赖度**（预期优于 1a，因为消除了外接球保守量 ~0.124 m）；
2. 真机 N0–N3：先 **β 形态**（关 CBF/accel_limit/z 地板/yaw 限速，留 OOB abort + 位姿看门狗 + 硬件急停）→ 再 **α 形态**（连 OOB abort 也关，仅手动急停，需 `safety.bare` 开关）；
3. 逐档 0 碰 ⇒ 发布 `navvel-cfb v2.0.0`，注册表状态转"现役"，`_current` 指向它。

### 3.7 训练侧改动清单（文件级，含批次与红线标记）

| # | 文件（`drones/OmniDrones`） | 改动 | 批次 | 红线 |
|---|---|---|---|---|
| 1 | `cfg/task/NavVel.yaml`（obstacle 段） | `pillar_side`（派生 `pillar_radius = side·√2/2`）、`n_pillars_range`、`pillar_layers_range`、`pillar_z_lo/hi_range`、`min_corridor`；`n_free_obstacles: 0` 设为默认；标注 `radius_choices` 失效（G7/G10） | P1 | ❌ |
| 2 | `envs/single/nav_vel_obstacles.py::_pillar_layer_zs` | 支持**逐柱独立** `layers / z_lo / z_hi`（批内张量各异）（G9） | P1 | ❌ |
| 3 | `envs/single/nav_vel_obstacles.py::_sample_pillar_mixed` | `n_pillars_range` 采样 + 窄通道/L 形模板 + 连通性校验接入 | P1 | ❌ |
| 4 | **新增** `scripts/pillar_layout_check.py` | 可通行性格筛（CPU 单测）（G8） | P1 | ❌ |
| 5 | `cfg/task/NavVel.yaml`（obstacle+cbf 段） | **口径 A**：`drone_radius 0.10 / inflation 0.02`；`cbf.r_safety_margin 0.05`、`use_brake_term false` | **P0.2** | ❌（但**必重导**，因半径链写入 meta） |
| 6 | `utils/cbf.py::CBFVelocityFilter` | 增 `p_filter` + 写 `info(a_cbf, corr, intervened)`；**`filter_velocity` 数学不动**（G2） | P3 | ❌（数学不动） |
| 7 | `envs/single/nav_vel.py` | `p` 调度（step 计数）+ 奖励 core 与执行解耦（始终算 `a_cbf`）+ stats | P3 | ❌ |
| 8 | `cfg/task/NavVel.yaml`（cbf 段） | `p_filter_schedule`、`h_penalty_weight>0`、`h_penalty_buffer 0.1–0.2` | P3 | ❌（`h` 项只进奖励） |
| 9 | `scripts/eval_ckpt.py` | `filter_mode ∈ {on,off}`；输出 §4.2/§4.3 全部指标 + `dropped_relevant` | P2/P3 | ❌ |
| 10 | `scripts/export_navvel_actor.py`（服务器 `scripts/` + 本工作区副本） | obs_v3 布局 + `K=12` + 方体 CBF 对拍向量 | P4 | ✅ |
| 11 | `utils/cbf.py::filter_velocity` | 新增方体 SDF 版（单约束/障碍，`∇sdf` 三等类） | P4 | ✅ |
| 12 | 部署侧（G1 定位后） | `safety.bare`(α 形态)、`navvel_obstacles_box.yaml`、启动自检（`model_id`+`sha256`+几何常量） | P5 | ✅（obs/几何变则重导） |

### 3.8 P0–P5 开训卡点（未过不许开）

| 卡点 | 内容 | 阻塞 |
|---|---|---|
| **K1** | §2.7 六项入库动作全绿（tag / 目录 / SHA256SUMS / profile / 注册表 / `_current`）—— **✅ 2026-09-12 已绿**（见 §0.5） | ~~P0 之外的一切~~ 已解除 |
| **K2** | `geometry_profile: A`（口径 A）数值冻结并写入 `meta.json` 模板 | P0.2、P1 |
| **K3** | `M=48`（8 柱×6 层）smoke test 通过（不 OOM、物理不炸），否则定 `n_pillars_range` 上界（G11） | A3 |
| **K4** | `pillar_layout_check.py` 实现 + CPU 单测通过；`min_corridor` 下界已按 `r_o=0.4243` 算出（G8） | A3/A4 |
| **K5** | `eval_ckpt.py` 指标扩展完成，并用 `v1.0.0` 回归（旧值可复现）（G6）—— **✅ 2026-09-12 已完成**（见 §0.5.5：`shadow` 反事实滤波器 + §4.2/§4.3 全套指标 + `[eval_metrics]` JSON + 批量 runner/汇总器） | 已解除 |
| **K6** | 部署侧仓库定位 + `navvel_deploy.yaml` 可编辑（G1） | P2、P4、P5 |
| **K7** | 真机方体障碍实测（中心/边长/高度）与 `navvel_obstacles_*.yaml` 生成 | P2 |

### 3.9 预算（按实测 ≈15 min/20M frames/run，3 run 并行）

| 批次 | run 数 | 估算 |
|---|---|---|
| P0（A0 3 seed + A0′ 3 seed） | 6 | ~0.5 h |
| P1（A1a/A1b/A2/A3 各 3 seed + A4 5 seed） | 17 | ~1.5 h |
| P3（8 配置 × 3 seed） | 24 | ~2 h |
| P4（复训 3 seed + 对拍/导出自检） | 3–5 | ~0.5 h |
| **合计** | **~50 run** | **≈4.5–5 h GPU** |

⇒ 预算**充裕**：建议把 A4 与 P3 的 `p0` 组提到 **5 seed**，其余保持 3 seed；仍 < 8 h。

---

## 4. 验收标准（阶段 1 与阶段 2 分开）

### 4.1 两阶段验收的差异（核心对照表）

| 维度 | **阶段 1 验收**（几何泛化） | **阶段 2 验收**（无 runtime filter） |
|---|---|---|
| 要证明的命题 | 换到方体世界后**仍能安全到达** | 策略**自身**安全，filter 退化为恒等映射 |
| filter 状态 | **允许 ON**（用部署默认配置） | **必须 OFF 也能达标** |
| 新增核心指标 | 窄通道通过率、路径长度比、`dropped_relevant`、`box_net` 保守量 | `filter 依赖度`、`零介入率`、`h_min^train`、`Δa` p50/p95 |
| 到达率门槛 | `arrival@0.2 ≥ 0.85`（新布局，OVER 全 seed） | ON 与 OFF **均** ≥0.85 且 `OFF/ON ≥ 0.95` |
| 碰撞 | 0 碰 / 0 OOB | 0 碰 / 0 OOB（**OFF 列也要**） |
| 安全余量 | `min d_min ≥ 0.10`（相对**实物**，即 `box_net` 口径） | `h_min^train ≥ 0` **且** `min d_min ≥ 0.10` |
| CBF 介入率 | **记录即可**（允许高） | **零介入率 ≥ 0.95** |
| 真机 | N0–N3，filter ON，逐档 0 碰 | N0–N3，**β 先飞 → α 后飞**，逐档 0 碰 |
| 典型"不通过"信号 | 到达率整体下降、策略"等待"、窄通道通过率塌方 | 依赖度 <0.9、OFF 列出现碰撞、`h_min^train < 0`、stall >10% |

> **为什么必须分开**：阶段 1 的 filter 是**允许的拐杖**，验收看"世界泛化"；阶段 2 的 filter 是**被审查的对象**，
> 验收看"独立性"。用同一套门槛会两头失真 —— 阶段 1 被无谓地卡住，阶段 2 又漏掉"依赖度"这个唯一要害指标。

### 4.2 阶段 1（几何泛化）指标与门槛

| 指标 | 定义 | 门槛 | 适用批次 |
|---|---|---|---|
| `arrival@0.50 / 0.30 / 0.20` | 距目标 < r 且保持 0.2 s | `@0.2 ≥ 0.85`（A3/A4）；`@0.5` 记录 | A3/A4 |
| **0 碰 / 0 OOB** | 全 seed 全条件 | **必须** | A0′–A4 |
| `min d_min` | 全程最小表面净空 | `≥ 0.10 m` | A0′–A4 |
| `min box_net` | 方体口径净空（真机同时报） | `≥ 0.05 m`，并记录与 `d_min` 之差（= 外接球保守量） | P2 |
| CBF 介入率 | `intervened` 步占比 | **记录**（去自由球后应较 A0 下降） | A1a 起 |
| 窄通道通过率 | 对含窄通道布局的成功率 | 记录（用于回看 `min_corridor` 是否过紧） | A3/A4 |
| 路径长度比 | 航迹长 / 直线距离 | 记录（判"绕远"） | A3/A4 |
| `dropped_relevant` | `d_i < danger_radius` 但未进 obs 窗口的障碍数占比 | `< 1%`；超限 ⇒ 提前做 P4 的 K 扩容 | A3/A4 |
| `z_err RMSE` / 终端速度 | 沿用 `NAVVEL_RETRAIN_GUIDE.md` 第二部分 §4 | 不劣于 A0 | 全部 |
| 复现性 | A0 vs 交付成绩 | 3-seed 均值在 ±0.02 内（修 G12） | A0 |

### 4.3 阶段 2（去 runtime filter）指标与门槛

| 指标 | 定义 | 门槛 |
|---|---|---|
| **filter 依赖度** | `arrival_OFF / arrival_ON`（同 seed、同分布） | **≥ 0.95**（1.0 = 完全不依赖） |
| **零介入率** | `1[‖a_cbf − a‖ == 0]` 的步占比（OFF 时也计算） | **≥ 0.95** |
| **`h_min^train`** | 全程 `min_i(d_i − r_cbf^train)`，其中 `r_cbf^train = r_o + 0.17`（口径 A ⇒ **与部署口径合一，无需再报双口径**） | **≥ 0** |
| `min d_min` | 相对实物表面净空 | `≥ 0.10 m` 且 **0 碰** |
| 修正幅度 `E‖Δa‖` | p50 / p95（filter OFF 时也计算） | 记录趋势，越接近 0 越好 |
| stall 占比 | 速度 < 0.05 m/s 且非到达 | **≤ 10%**（防"等待"策略） |
| `arrival@0.2`（OFF） | — | `≥ 0.85` |
| 0 碰 / 0 OOB | 全条件、**ON 与 OFF 都要** | **必须** |
| 动作率 / jerk | — | 不劣于 `v1.0.0` |

### 4.4 真机验收阶梯（N0–N3，两阶段共用的阶梯，判据不同）

**形态定义**

- **β 最小兜底**（先飞）：关 CBF / accel_limit / z 地板 / yaw 限速，只留 **OOB abort + 位姿看门狗 + 硬件急停**。
- **α 裸策略**（后飞）：连 OOB abort 也关，仅保留手动急停（需部署侧 `safety.bare`）。

| 档 | 场地 | 命令要点 | 判据 |
|---|---|---|---|
| **N0** 空场 | `navvel_obstacles_empty.yaml` | `--no-cbf --vmax 0.6 --ema 0.3 --yaw-rate 0.8` | 0 碰 / 0 OOB / 0 abort；到达精度按指南 §1.4 |
| **N1** 单柱 | 1 根方柱（实测中心，`radius=0.4243`） | 同上 | 0 碰；`min d_min ≥ 0.10` |
| **N2** 少量 | 方体版 `few` 模板 | 同上 | 0 碰 |
| **N3** 全场 | 现场方体全布置 + `*_box` 可视化 | 同上，`--vmax` 逐步提到 1.0–1.2 | **0 碰 + 到达率 ≥ 0.8（≥20 次）** |

> ⚠ 阶段 2 的 N0–N3 **先 β 过 N0–N2 再测 α**；禁止第一次就上 α。
> ⚠ 无 CBF 时 `abort_margin_no_cbf_m` 必须有效（当前 0.02 → N1 起建议 0.10–0.12）。

### 4.5 记录表模板（每档 5 次 × 每形态）

| 日期 | model_id | 形态 | 档 | goal | cmd_mode | vmax | ema | yaw-rate | `min r_goal` | 终端 `\|r\|` | `z` 偏差 | `min d_min` | `min box_net` | CBF 次数 | abort 次数 | tilt max | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|

### 4.6 判定规则

| 结论 | 条件 |
|---|---|
| **通过** | 该阶段**全部**"必须"项绿 + 全部数值门槛达标（含 ≥3 seed 或 ≥20 次真机） |
| **不通过** | 任一"必须"项红（碰撞 / OOB / 依赖度不达标 / `h_min^train<0`） |
| **回转** | 门槛边缘（如 `arrival` 差 ≤0.03、依赖度 0.90–0.95）⇒ **只补 seed，不改变量**；补到 5 seed 仍不过再回上一批 |
| **回上一批** | 出现"归因明确的机制性失败"（如 `dropped_relevant > 1%` ⇒ 回 P4 升 K；CBF 介入率虚高 ⇒ 转 1b 方体精确） |

---

## 5. 风险与回滚

| 风险 | 表现 | 缓解 | 回滚 |
|---|---|---|---|
| **口径 A 使 OFF 列变差** | P0.2 的 OFF 到达率明显低于 0.855 | 预期内（约束放宽）；这正是 P3 的目标。用 F3 裕度势能补偿 | 退回 `A0-legacy` 口径（`v1.0.0`） |
| **窄通道致任务不可行** | 到达率整体下降、策略"等待" | K4 的连通性校验 + `min_corridor ≥ 1.10 m` | 放宽 `min_corridor` 或去掉窄通道模板 |
| **K=8 容量不足（1a 期间）** | `dropped_relevant > 1%`、碰撞但 obs 无对应障碍 | 1a 内限制同柱层数上限；监控该指标 | 提前执行 P4 的 K 扩容 |
| **`M=48` 超显存/物理预算** | OOM 或物理不收敛 | K3 smoke test；`n_pillars_range` 上界降 6 | 缩 `num_envs` 或 `M` |
| **`p>0` 的 PPO 梯度-结果不一致** | `ratio/KL/entropy` 异常、`std(a)` 塌缩 | 监控 + `pann` 与 `clip_range` 同步放宽 + 动作幅度下限惩罚 | 退回 `p1`（= 现状安全配置） |
| **obs_v3 升维后对拍不过** | actor 残差 > 1e-5 | 冻结 obs 顺序后逐块对拍定位 | 保持 `obs_v2`，1b 只改 CBF 不改 obs |
| **"贴柱飞"过拟合规则几何** | 真机柱面粗糙/有支架致擦碰 | 真机障碍表加实测余量；必要时 1b 补尺寸随机 | 加大 `inflation`（= 升 MINOR 版本） |
| **部署侧仓库长期定位不到（G1）** | 版本对齐只能人工、真机验收无法留档 | K6 设为 P2 硬卡点 | 先把训练侧闭环做完（P0/P1/P3 不依赖 G1） |

---

## 附录 A. 待确认项与验证命令（本机可直接跑）

```bash
cd /home/lz/lzspace/drones/OmniDrones

# G1 部署侧仓库/文件在哪（当前 find 无结果）
find / -name "navvel_deploy.yaml" -o -name "navvel_obstacles_box.yaml" -o -name "navvel_cbf.py" 2>/dev/null | head

# G6 eval_ckpt.py 现有指标 & 是否有 --no-cbf 类开关
grep -nE "arrival|arrive|filter_mode|no_cbf|use_cbf|d_min|min_clearance|interven" scripts/eval_ckpt.py | head -40

# G4 子模块是否已有未提交改动需要入库
cd /home/lz/lzspace/drones/OmniDrones && git status --short | head -30

# G11 交付组三 seed 的实际成绩（用于 A0 复现判据，修 G12）
for r in run-20260909_191309-{hpzc2m3r,72s1zkt6,pczh85ou}; do
  echo "== $r"; cat scripts/wandb/$r/files/wandb-summary.json | python3 -m json.tool | head -30
done

# K3 M=48 smoke test（先确认不 OOM 再开 A3）
python scripts/train.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
  task.obstacle.n_pillars=8 task.obstacle.pillar_layers=6 task.obstacle.n_free_obstacles=0 \
  task.obstacle.pillar_radius=0.4243 total_frames=98304 task.env.num_envs=1024

# 口径 A 的参数合法性（r_s = r_o+0.12 / r_cbf = r_o+0.17）自检
python -c "
from omni_drones.utils.cbf import cbf_safety_radius
r_o=0.4243
print('r_s  =', r_o+0.10+0.02)
print('r_cbf=', cbf_safety_radius(r_o,0.10,0.02,0.05,1.8,2.0,use_brake_term=False))
"
```

**人工确认项（2026-09-12 已确认，原为待确认）**

1. **D-1** ✅ 决策：口径 A **不改** `collision_margin`，保持 **0.05**（只动 `drone_radius 0.10` / `inflation 0.02`）
2. **D-2** ✅ 决策：`K=8→12` 扩容**放 P4**；1a 保持 K=8，仅加"同柱层数上限"监控 + `dropped_relevant` 统计
3. **D-3** ✅ 决策：`obs_v3` 取 **SDF+法向 7 维**（`[rpos(3)/5, sdf/0.6, 法向(3)]`）⇒ obs = 30+7×12 = **114**
4. **D-4** ✅ 决策：阶段 1 真机验收沿用 **`arrival@0.2 ≥ 0.85`**
5. **D-5（执行中新发现，见 G16）** ✅ 决策：`v1.0.0` 基线**补跑 `eval_ckpt.py` 严格单命验收重建**，不使用训练内 eval 的 0.4320

---

## 附录 B. 与 `NAVVEL_RETRAIN_GUIDE.md` 的差异与裁决（本文优先）

| # | 指南 | 本文裁决 | 理由 |
|---|---|---|---|
| B-1 | §0.1 决策 4「filter 退火两者都做，矩阵 4×3」 | 收敛为 **8 配置**（`naive`/`reward_only` 的 `p` 轴退化） | `mode=none` 无 filter；`reward_only` 本就不执行 filter，其 `p` 轴无意义 |
| B-2 | §A.2 决策 3「K 扩容 or 限制同柱层数」二选一（暗示可在 1a 做） | **K 扩容放 P4**；1a 仅加"同柱层数上限"监控（不改组装） | 保住 1a 的"零升维/零重导"价值；升维红线只做一次 |
| B-3 | §B.2「必须新增裕度势能，否则内化无从发生」 | **已实现**（`h_boundary_penalty`），只需开 `h_penalty_weight/buffer` | §1.3-①：代码已在，指南写于实现之前的推断 |
| B-4 | §B.5 #5「改 `scripts/eval.py`」 | 改 **`scripts/eval_ckpt.py`** | §1.3-③：`eval.py` 不存在 |
| B-5 | §A.6(4)「`navvel_obstacles_box.yaml` + `*_box` 可视化 v10 已就绪」 | **待验证**（本工作区无该文件，G1） | §1.3-④：不能假设基础设施存在 |
| B-6 | §B.3 选项 A「训练放宽到部署口径」并"与 1a 一起改" | 提前到 **P0.2 单独成批**（先于几何） | 口径 A 改了碰撞判定半径 ⇒ 必须先有同口径基线，否则 A1–A4 无法归因 |
| B-7 | §C 里程碑「§D 清单填完」为第 1 项 | 等价为本文 **K1**（入库动作）+ **K6**（部署侧定位） | 把"填清单"变成可判定的卡点 |

---

**下一步**：K1 ✅ / K5 ✅ / P0.1 ✅（逐位复现）/ **P0.2 ✅（2026-09-12 完成，见 §0.5.9）**。

**P0.2 的实际执行（与原计划的差异，均已记录）**：
① profile 未用"手工改 4 键"，而是给 `make_geometry_profile.py` 加了**派生模式**（`--from-profile …
--set k=v`），只改**3 个键**（`use_brake_term` 本来就是 `false`，工具如实报告"未变化"）；
② 3 seed × 20M 续训，wandb `fly-hust/env_design_geo10_p01repro`、group `NavVel-P0.2-chiA`，
run group `run-20260912_203247`（s12 因收尾 OOM 另起 `run-20260912_204807` 单进程重跑）；
③ 6 次验收评估（同 512×600 协议）已跑完并与 §0.5.5 基线对照 —— **预期被证实**：OFF 列变差
（依赖度 1.0076→0.8969 转红）、零介入率 0.1613→0.2429（介入反而减少，因约束放宽）；
④ 已按 §2.1 升 **MINOR** → `navvel-cfb-v1.1.0-dual-p1-s11`，建新 model 目录（16 项 `SHA256SUMS`
全过）+ 注册表新行 §3.4 + tag `navvel-cfb-v1.1.0`；**因阶段 2 未通过，`_current` 不晋升**。
> 另：P0.1 已证明同机逐位可复现 ⇒ P0.2 与 P0.1 的差异**只可能来自那 3 个键**，归因非常干净。

**P0.2 带出的两个新缺口（必须先处理再开 P1）**：**G20**（`h_min` 与 `min_clearance − cbf_extra`
不自洽 ⇒ 安全门禁暂不可信，见 §0.5.9③）与 **G21**（批量脚本传相对路径会静默全挂，已加保护）。

