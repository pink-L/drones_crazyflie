# NavVel 模型注册表（`NAVVEL_MODEL_REGISTRY.md`）

> 版本 **2026-09-12 v1（新建，K1 入库动作）**。规范见 `NAVVEL_VERSION_AND_RETRAIN_PLAN.md` §2.5。
>
> **一行 = 一个 run group**（不是单个 seed）。成绩列一律 **3-seed 均值 ± 极差**，并指向被发布的那个 seed。
> 状态机：`计划中 → 候选 → 验证中 → 现役 → 退役`。**产物不可变**；晋升/回滚只改
> `navvel_export/_current` 软链 + 本表状态列。
>
> 目录约定：`/home/lz/lzspace/navvel_export/<model_id>/`（见该目录内 `lineage.json` / `SHA256SUMS` / `acceptance.md`）。

---

## 1. 模型表

| model_id | 状态 | obs | geometry_profile | 半径链 | arm / p | run group | ckpt sha256（前 12） | 阶段 1 验收 | 阶段 2 验收 |
|---|---|---|---|---|---|---|---|---|---|
| `navvel-cfb-v1.0.0-dual-p1-s11` | **现役**（验收不通过） | obs_v2 / 62 | `A0-legacy` | `r_s=r_o+0.20`、`r_cbf=r_o+0.30` | `dual` / always-on | `run-20260909_191309`（seed 11/12/13） | `4d604d6c30c9` | n/a（旧世界） | ✅**已测**：**不通过** ❌ |
| `navvel-cfb-v1.1.0-dual-p1-s11` | 计划中（P0.2） | obs_v2 / 62 | `A`（口径 A） | `r_s=r_o+0.12`、`r_cbf=r_o+0.17` | `dual` / always-on | 待跑 | — | 待测 | 待测 |
| `navvel-cfb-v1.2.0-*-s*` | 计划中（P1 = A1a→A4） | obs_v2 / 62 | `A1a`…`A4` | `A` | 待定（沿用 `dual`） | 待跑 | — | 待测 | 待测 |
| `navvel-cfb-v2.0.0-*-p*-s*` | 计划中（P4 = 1b 红线批） | obs_v3 / 114、K=12 | `A4` + 方体 SDF | `A` | P3 选出的最优臂 | 待跑 | — | 待测 | 待测 |

> `ckpt sha256（前 12）` = **被发布的那个 seed** 的 `checkpoint_final.pt` 哈希前缀；完整值见各
> `lineage.json`（含 run group 全部 3 seed 的哈希）。

---

## 2. 交付种子的实测哈希（`checkpoint_final.pt`，2026-09-12 复核）

| seed | run_id | run_name | sha256 |
|---|---|---|---|
| 11 ✅发布 | `run-20260909_191309-hpzc2m3r` | `cfb-dual-DR2-ctrlSync-1` | `4d604d6c30c9480bf1c59e564e1876b5c02dabcad9f72836ff5a2f331d25ed03` |
| 12 | `run-20260909_191309-72s1zkt6` | `cfb-dual-DR2-ctrlSync-2` | `7d03a9c33dec84cbaac940e105e616831b3c56c04fa3dbefc331d86fc6a4fffd` |
| 13 | `run-20260909_191309-pczh85ou` | `cfb-dual-DR2-ctrlSync-3` | `524b6364bcb94fe2192e4c54f1a8c58b70c95362d04fbe33d82dd6270d504dd7` |

`meta.json.sha256` == seed 11 的 `checkpoint_final.pt` ⇒ 交付产物确由 seed 11 导出（复核通过）。

---

## 3. 成绩留档（G12 / G16）

### 3.1 验收口径基线（2026-09-12 实测，D-5 决策建立）

**协议**：`A0-legacy` profile，512 envs × 600 步，确定性 `MODE`，`eval_points=fixed`
（起点 `[-2.8,0,0.5]` → 目标 `[2.8,0,1.0]`），`set_seed = 1000+train_seed`（ON/OFF 共用布局）。
复现：`scripts/acceptance_eval.sh <seed>:<on|off>:<ckpt>` → `scripts/aggregate_acceptance_eval.py`。
证据：`navvel_export/navvel-cfb-v1.0.0-dual-p1-s11/{eval_metrics.json,eval_logs/}`。

| 指标 | ON（3-seed 均值） | OFF（3-seed 均值） | 门槛（§4.3） | 判定 |
|---|---|---|---|---|
| `arrival@0.2` | **0.3412** | **0.3438** | ≥ 0.85 | ❌ FAIL |
| `arrival@0.5` | 0.3932 | 0.3678 | 记录 | — |
| **filter 依赖度** `OFF/ON` | — | **1.0076** | ≥ 0.95 | ✅ PASS |
| **零介入率** | **0.1613** | 0.1951（shadow） | ≥ 0.95 | ❌ FAIL |
| **`h_min^train`** | **−0.0500** | −0.0500 | ≥ 0 | ❌ FAIL |
| 碰撞 env 数 | **0** | 0.33（s13 有 1 次） | 必须 0 | ❌ FAIL |
| OOB env 数 | **0** | **0** | 必须 0 | ✅ PASS |
| `min d_min`（m） | 0.0512 | 0.0492 | ≥ 0.10 | ❌ FAIL |
| `stall_frac` | 0.0132 | 0.0217 | ≤ 0.10 | ✅ PASS |
| `dropped_relevant_frac` | 0.0000 | 0.0000 | < 0.01 | ✅ PASS |
| `E‖Δa‖` p50 / p95 | 0.6385 / 1.4485 | 0.6974 / 1.5779 | 记录 | — |

> **结论：阶段 2 验收不通过**（0 碰项红 + 3 项门槛红）。详见
> `navvel_export/navvel-cfb-v1.0.0-dual-p1-s11/acceptance.md`。
>
> **关键解读**：filter 依赖度 PASS（1.0076）**不代表**可以撤 filter —— 同一次评估里
> 零介入率只有 **0.16**，即滤波器 **84% 的步都在介入**（中位修正 0.64 m/s）。
> 两者必须同时看：现在的状态是「**滤波器大量做无用功**」（只扣朝障碍的法向靠近速度，
> 不改变切向朝目标进度），**不是**「策略已内化安全」。

### 3.2 训练内 eval（`wandb-summary.json`，窗口口径，**非验收口径**）

| 口径 | seed 11 | seed 12 | seed 13 | 3-seed 均值 |
|---|---|---|---|---|
| wandb `eval/stats.success_rate` | 0.4766 | 0.4229 | 0.3965 | **0.4320** |
| wandb `eval/stats.min_clearance`（m） | 0.6584 | 0.6227 | 0.6278 | 0.6363 |
| **计划/文档引用的「ON 0.891 / OFF 0.855」** | ？ | ？ | ？ | **？来源不明** |

> ⚠ **G16 仍未完全闭环**：文档引用的 `0.891/0.855` 在仓库内**无留档**，**无法从 wandb 复现**，
> 也与本次实测的新基线（`arrival@0.2 ≈ 0.34`）**不在同一协议上**。本轮的价值是
> **确立了一个可复现的、写清协议的新基线**，供 `A0′`/`A1a`…`A4` 对比；
> 旧数字若要复核，需先找到当时的 eval 命令行（仓库内无记录）。

### 3.3 P0.1 复现批次 — **逐位完全复现 ✅**（2026-09-12）

| 项 | 值 |
|---|---|
| 批次 | P0.1（plan §3.1）—— `A0-legacy` 3 seed 从 `geo8` warm-start 续训 20M |
| wandb | `fly-hust` / **`env_design_geo10_p01repro`** / group `NavVel-P0.1-repro` |
| run group | `run-20260912_195345`（seed 11 `7wexmcym` / 12 `bd51cg95` / 13 `npgxdjor`） |
| 耗时 | 19:53 → 20:08 ≈ **15 min**（3 run 并行），`env_frames = 19988480` |

**结果**：

| 判据 | 门槛 | 实测 | 结论 |
|---|---|---|---|
| `arrival@0.2`(ON) 3-seed 均值 vs §3.1 基线 | ±0.02 | **Δ = 0.0000** | ✅ PASS |
| `checkpoint_final.pt` sha256 vs 交付 run | 记录 | **3/3 完全相同** | ✅ PASS |
| 训练侧 `eval/stats.*` vs 交付 | 记录 | 逐项相同 | ✅ PASS |
| 流水线（含 `+init_ckpt` 续训） | 可用 | 3/3 正常完成 | ✅ PASS |

> **这是本轮最有价值的结论**：本机训练**逐位确定** ⇒ `P0.2 / A1a…A4` 的批次对比是**真单变量**
> （跨批次运行噪声 = 0），归因能力强于计划预期。
> 边界：(a) **不**证明跨机器可复现；(b) 逐位确定 ⇒ 3 seed 只提供**种间差异**
> （0.3086–0.3887，很大），**不提供**运行噪声估计 ⇒ `±0.02` 对"同机重跑"偏宽松，
> 对"换配置重训"才是有效门槛。
> 证据：`navvel_export/navvel-cfb-v1.0.0-dual-p1-s11/repro_p01/`（`REPRO.md` + 训练/评估日志 + `SHA256SUMS`）。

---

## 4. 三个锚点的当前状态（plan §2.3）

| 锚点 | 位置 | 状态 |
|---|---|---|
| **训练锚** | git tag `navvel-cfb-v1.0.0` + `run_config.yaml` + wandb run id | ✅ tag 已打；`run_config.yaml` 已随产物入库；**algo 超参不在 `cfg/`**，来自代码 ConfigStore（`omni_drones/learning/ppo/ppo.py:59`），故由 tag→submodule commit 锚定 |
| **导出锚** | `navvel_export/<model_id>/` + `SHA256SUMS` + `meta.json` | ✅ |
| **部署锚** | `navvel_deploy.yaml`（含 `model_id` + `sha256` + 几何常量） | ⛔ **仍缺**（G1：部署侧仓库不在本工作区）；P2/P4/P5 硬卡点 K6 |

---

## 5. 一致性契约提醒（写进部署锚时必须核对）

`meta.json` 与 `run_config.yaml` 必须一致的量：`obs_dim/K`、`obs_dist_norm/obs_radius_norm`、
`drone_radius/inflation/r_safety_margin/use_brake_term`、`alpha/a_max/max_vel/filter_iterations`、
`time_encoding(=step/1500)`、`action_transform`、clamp 顺序、`max_episode_length`。
任一不一致 ⇒ 按 plan §2.3「以训练锚为准 → 重导 → 更新部署锚」处理。
