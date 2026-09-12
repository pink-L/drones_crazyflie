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
| `navvel-cfb-v1.0.0-dual-p1-s11` | **现役**（未验收） | obs_v2 / 62 | `A0-legacy` | `r_s=r_o+0.20`、`r_cbf=r_o+0.30` | `dual` / always-on | `run-20260909_191309`（seed 11/12/13） | `4d604d6c30c9` | n/a（旧世界） | **未验收** |
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

## 3. 成绩留档（G12）

| 口径 | seed 11 | seed 12 | seed 13 | 3-seed 均值 |
|---|---|---|---|---|
| wandb 训练内 eval `success_rate`（窗口口径，**非验收口径**） | 0.4766 | 0.4229 | 0.3965 | **0.4320** |
| wandb 训练内 eval `min_clearance`（m） | 0.6584 | 0.6227 | 0.6278 | 0.6363 |
| **计划/文档引用的「ON 0.891 / OFF 0.855」** | ？ | ？ | ？ | **？来源不明** |

> ⚠ **G12 未闭环**：文档引用的 `0.891/0.855` 在仓库内**无留档**，且**无法从 wandb run 的
> `wandb-summary.json` 复现**（表中给出的是训练内 `eval/stats.*`，属 soft-respawn 窗口口径，
> 与 §4.2/§4.3 的严格单命固定起终点验收口径不同构）。
> ⇒ **A0 复现判据（plan §3.1 P0.1）在补跑 `eval_ckpt.py` 之前不可用**；详见
> `navvel_export/navvel-cfb-v1.0.0-dual-p1-s11/acceptance.md`。

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
