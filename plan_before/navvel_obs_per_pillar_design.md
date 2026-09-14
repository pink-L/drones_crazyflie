# NavVel 障碍观测改造：从「每层一槽」到「每柱一槽」

| 项 | 值 |
|---|---|
| 状态 | **设计待审（刻意未实施）** |
| 提出 | 2026-09-14（你的提问） |
| 关联 | 计划 §0.6.2 卡点 1、§0.6.3 路线 A/B、§3.2（G9/G11）、决策 5（K 扩容）、P4 obs_v3 |
| 一句话 | 技术可行；改动约 **80–95 行、集中在 2 个文件**；**obs 维度不变（仍 62）⇒ 非红线**；但观测语义变 ⇒ **1a 阶梯需重训**、部署侧 obs 组装需同步改 |

---

## 1. 问题：现在的"槽位"粒度是**碰撞体（球/层）**，而不是**障碍物（柱）**

`nav_vel_obstacles.py::build_obs`（**248–287 行**）在滑动窗口模式（M > K）下：

```python
d = torch.norm(self.pos - drone_pos, dim=-1)                    # (N, M) 全部槽位
d = torch.where(self.active, d, torch.full_like(d, inf))
vals, idx = torch.topk(d, k=self.K, dim=-1, largest=False)      # 262 行：最近 K 个“槽”
p_sel = self.pos.gather(1, idx...)                              # (N,K,3)
r_sel = self.radius.gather(1, idx...)                           # (N,K)
block = cat([(dvec / obs_dist_norm).clamp(-1,1),                # 每槽 4 维
             (r_sel / obs_radius_norm).clamp(0,1).unsqueeze(-1)], -1)   # 272–275
return block.reshape(self.num_envs, 1, self.K * 4)              # 287
```

- 槽位 = **一个球 = 一层**；`topk` 在**槽位**上选最近 K 个 ⇒ **一根 6 层的柱可一次吃掉 8 个槽里的 6 个**。
- obs 总维度 = 30 + `4K` = **62**（K=8）；`obstacle_obs_dim = 4 * self.K`（`nav_vel.py:487`）。
- 诊断 `_obs_win_idx`（266 行）暴露了同样口径的窗口选择，所以 A2 的
  **`dropped_relevant_step_frac(ON) = 18.86%`** 正是"同柱多层霸占窗口"的直接后果。

**根因**：观测容量需求 = `柱数 × 每柱层数`（A3 = 8×6 = **48**），而"障碍物"的真实语义单位是**柱**。
两者不一致才导致 K=8 显得不够。**这不是"K 太小"，而是"槽位粒度选错了"。**

### 1.1 一个必须澄清的关键事实（本轮新查证）

**安全层不受此问题影响，且本改造不会碰它：**

- CBF 球通道 `obstacle_cbf` 的规格是 **`(N, M, 4)`** —— `nav_vel.py:550-553`；
- 喂给 `CBFVelocityFilter` 的是**全部 M 个槽**（`nav_vel.py:775-780`），与 obs 的 K 窗口**完全独立**；
- ⇒ 本改造**只改策略观测**；CBF、物理碰撞、奖励、`r_s`/`r_cbf` 半径链**一行不动**。

> 顺带记录一处**会误导人的注释错误**：`nav_vel.py:776` 写 `actm = self.obstacles.active.float()  # (N,K)`，
> 实际是 `(N,M)`（`active` 由 `commit_layout` 写成 `(N,M)`，且 `obstacle_cbf` 规格就是 `(N,M,4)`）。
> 这个错注释正好掩盖了本问题 —— **建议本次一并修正**。

---

## 2. 目标 / 非目标

**目标**
1. "一根柱 = 一个 obs 槽"，使观测容量需求与**每柱层数解耦**，只与**柱数**相关；
2. 让 A3 的 `n_pillars_range=[2,8]`（你已定上界 = 8）**恰好压在 K=8 上**，`dropped_relevant ≡ 0`；
3. **默认关闭**，保证已冻结 profile（A0/A/A1a/A1b/A2/A2L2）逐位不变。

**非目标**
- 不改 obs 维度（仍 `30 + 4K = 62`）；
- 不改 CBF / 安全层 / 奖励 / 几何采样分布；
- 不做 P4 的 box-SDF obs_v3 与 K 扩容 —— 本方案是它的一个**零升维子集**（后续可叠加）。

---

## 3. 设计

### 3.1 柱归属 `pillar_id`（静态张量，构造期一次生成）

| 采样路径 | 归属规则 |
|---|---|
| 随机化路径 `_sample_pillar_random` | 槽位已是**固定块** `[p·L_max, (p+1)·L_max)`（见该函数内 `sl = slice(p*L_max, (p+1)*L_max)`）⇒ `pillar_id = arange(M) // L_max` |
| uniform 混合路径 `_sample_pillar_mixed` | 前 `pillar_ball_count = n_pillars × pillar_layers` 个槽按 `// pillar_layers` 归柱；其余 `n_free_balls` 个自由球**各自一组**（`pillar_id = n_pillars + arange(n_free)`） |
| `M <= K`（固定槽模式） | **不分**：本就一槽一障碍 ⇒ `pillar_id = None`，走原路径（行为完全不变） |

新增成员：`self.pillar_id`（`(M,)` int64，或 None）、`self.n_groups`（= 柱数 + 自由球数）。
`n_groups` 用于 `obs_per_pillar` 生效时的 `topk(k=min(K, n_groups))` 与掩码。

### 3.2 窗口选择（改 `build_obs`）

四步，**维度与每槽特征含义完全不变**：

1. `d = ||pos − drone_pos||`，(N,M)，`active` 掩码（inactive → inf）；
2. **按柱聚合**：`d_g = scatter_reduce(d, pillar_id, reduce="amin")` ⇒ `(N, G)`；
3. `vals_g, idx_g = topk(d_g, k=K, largest=False)` ⇒ **最近 K 根柱**（不足 K 根时其余为 inf → `valid=False` → 补零）；
4. **柱 → 代表层**（变体 a）：对每根入选柱取该柱中 `d` 最小的那一层。
   实现上不必写 argmin 循环：`d` 已经在第 2 步按柱取过 min，直接用
   `sel = (d == d_g.gather(1, idx_g)[:, pillar_id])` 取每柱首个 True 的槽即可；
   随后 `p_sel = pos[sel]`、`r_sel = radius[sel]`，**沿用 272–275 行的原组装**。

**变体对照**

| | **(a) 最近层代表**（建议） | **(b) 柱体圆柱包络**（留给 P4） |
|---|---|---|
| 每槽 4 维含义 | **完全不变**（最近层的 `dvec` 3 维 + `radius` 1 维） | 改为「到柱轴水平距离 / 纵向偏移 / `r_o`」 |
| 信息损失 | 失去"同柱其它层"的显式条目；但纵向偏移仍在 `dvec.z` 里 | 无损失，且更贴真机 0.6 m 方柱 |
| 风险 | **低**（去重，不改特征语义） | 中（要重新设计特征与归一化 `obs_dist_norm`/`obs_radius_norm`） |
| 部署侧改动 | 只需把"最近 K 球"改成"最近 K 柱" | 更大：要重写特征计算 |

### 3.3 诊断口径（改 `scripts/eval_ckpt.py` 的 `dropped_relevant`，现 288–320 行）

- `rel` 改**逐柱**：柱的任一层 `clr < danger_radius` ⇒ 该柱"相关"
  （`rel_g = scatter_reduce(rel, pillar_id, reduce="amax")`）；
- `win` 改 `idx_g`（逐柱）⇒ `dropped = rel_g & ~win_g`；
- 两个指标名不变（`dropped_relevant_frac` 逐柱、`dropped_relevant_step_frac` 逐步），但
  **报告里必须标注口径 = 逐柱**，且**明确声明不可与 A2 的 18.86% 直接比较**（粒度变了）。
- `layout_fp` 不受影响（它只看布局，不看窗口）⇒ ON/OFF 同布局的校验照旧。

### 3.4 开关与默认值

- 新配置键：`obstacle.obs_per_pillar: false`（**默认 false**）。
- 关闭时 `pillar_id=None`，`build_obs` 走原路径 ⇒ **已冻结世界逐位不变**（用 §6.2 的 twin run 复验）。
- `nav_vel.py` **无需改动**：`obs_per_pillar` 由 manager 自己从 `oc` 读；`obstacle_obs_dim = 4*K` 不变；
  `obstacle_cbf` 通道不变。（唯一建议的改动是 §1.1 那条错注释。）

---

## 4. 逐文件 diff 计划（供审，**尚未实施**）

| # | 文件 | 位置 | 改动 | 估计 |
|---|---|---|---|---|
| 1 | `omni_drones/envs/single/nav_vel_obstacles.py` | `__init__`（`self.M = ...` 之后） | 读 `obs_per_pillar`；调 `_build_pillar_id()`；`print` 里带上一行诊断 | ~10 |
| 2 | 同上 | 新增方法 `_build_pillar_id()` | 按 §3.1 生成 `(M,)` id 表 / None + `n_groups` | ~22 |
| 3 | 同上 | `build_obs`（248–287） | 插入 §3.2 的分支；原逻辑保留为 `else` | ~35 |
| 4 | `scripts/eval_ckpt.py` | 291–317 | `rel`/`win` 改逐柱（§3.3） | ~18 |
| 5 | `omni_drones/envs/single/nav_vel.py` | 776 行注释 | 修正 `# (N,K)` → `# (N,M)`（纯注释） | 1 |
| 6 | `scripts/aggregate_acceptance_eval.py` | 报告输出 | 标注 `dropped_relevant` 口径（逐柱/逐层） | ~4 |
| 7 | `cfg/profiles/*.yaml`（新） | 新 profile | 单键 `obstacle.obs_per_pillar: true` | 1 键 |
| | | | **合计** | **~90 行** |

**关键代码骨架（供审，非最终代码）**

```python
# nav_vel_obstacles.py —— 新增
def _build_pillar_id(self):
    """(M,) 槽->组 归属。返回 (ids, n_groups)，或 (None, 0) 表示无需分组。

    组的语义 = 一个“障碍物”：一根柱（其所有层）算一组；每个自由球算一组。
    仅在 obs_per_pillar 且 M > K 时使用（M <= K 时本就一槽一障碍）。
    """
    if not self.obs_per_pillar or self.M <= self.K:
        return None, 0
    if self.pillar_random:
        L = self.pillar_layers_max
        ids = torch.arange(self.M, device=self.device) // L        # 固定块编号
        n_g = self.n_pillars_max
    else:
        L = self.pillar_layers
        ids = torch.arange(self.M, device=self.device) // L
        ids[self.pillar_ball_count:] = self.n_pillars + \
            torch.arange(self.M - self.pillar_ball_count, device=self.device)
        n_g = self.n_pillars + self.n_free_balls
    return ids, n_g

# build_obs 内的窗口分支改写为（伪码，保留原组装）
if self.obs_window:
    d = torch.where(self.active, torch.norm(self.pos - drone_pos, dim=-1), inf)
    if self.pillar_id is None:
        vals, idx = torch.topk(d, k=self.K, dim=-1, largest=False)      # 原路径
    else:
        d_g = torch.full((N, self.n_groups), inf, device=...)
        d_g.scatter_reduce_(1, self.pillar_id.expand(N, -1), d, reduce="amin")
        vals_g, idx_g = torch.topk(d_g, k=min(self.K, self.n_groups), dim=-1, largest=False)
        hit = d == d_g.gather(1, idx_g)[:, self.pillar_id]               # (N,M) 代表层
        idx = hit.float().argmax(-1)                                     # 每柱首个 True
        vals = d.gather(1, idx)
    # —— 以下与现状完全相同（272–276 行）：gather pos/radius、组装、乘 valid
```

---

## 5. 兼容性、版本与交付影响

- **obs 维度不变 ⇒ 非红线**（计划 §2.x：红线由"obs 维度变"触发）。TorchScript 输入形状仍是 `[1,62]`，
  **不需要重导图**、**不需要部署端改 obs 长度**。
- 但**观测语义变** ⇒ 按 §2.x 属 **MINOR**（"obs 维度不变但输入分布/安全语义变"）⇒ 建议 **`v1.3.0`**。
- **必须重训 1a 阶梯**（旧 ckpt 的 actor 见过的是"最近 K 个球"，分布不同、不可比）≈ **1 h** GPU。
- **交付链待办（逐条，必须写进注册表）**：
  1. `export_navvel_actor.py`：轨迹图不变，但 `obs_test.npy` 夹具**必须重生成**（值来自 env）；
  2. `cbf_test.npz`：**预期不变**（CBF 路径未动）—— 仍要复跑确认，作为"没碰安全层"的证据；
  3. **部署侧 obs 组装**（K6 仓库，仍不在本机）："最近 K 个球" → "最近 K 根柱"，**这是本次唯一真正的交付链依赖**；
  4. `navvel_deploy.yaml` 的 `model_id` / `sha256` 更新 + 启动自检；
  5. `NAVVEL_MODEL_REGISTRY.md` 增加一行，注明"维度不变、**观测口径变**"。

---

## 6. 测试与验收计划（实施后执行）

1. **CPU 单测**（仅 torch / PyYAML，训练期间安全）：
   - `pillar_id` 正确性：随机化路径块内同 id、块间递增；uniform 路径柱/自由球分组正确；
   - **`M == K` 时 `obs_per_pillar` 开/关必须逐位相同**（固定槽模式本就一槽一障碍）；
   - **决定性场景**：构造"一根柱的 6 层全在 `danger_radius` 内 + 另 2 根远柱"，
     断言窗口里**该柱只占 1 槽**、且另 2 根柱仍在窗口内 ⇒ 直接验证卡点 1 被消灭。
2. **逐位不变性**：`obs_per_pillar=false` 的 A1b 400k twin run 的 ckpt sha256 必须仍是
   `cae36ac63f562ab9…`（与 §0.5.13 的基线一致）。
3. **对照实验**：
   - `A2L2P` = A2L2 + `obs_per_pillar=true`（M=8=K）应与 `A2L2` **几乎相同**（M≤K 时无差别）→ 反向验证开关；
   - **`A2P` = A2 + `obs_per_pillar=true`（M=24）是决定性实验**：预期
     `dropped_relevant_step_frac` 从 18.86% → ~0、`arrival@0.2` 回升（若回升到 ≥0.85 ⇒ 阶段 1 收口且**不动红线**）。
4. **A3**：`n_pillars_range=[2,8]`（已定上界）+ `obs_per_pillar=true` ⇒ K=8 恰好满窗。

---

## 7. 风险与回退

| 风险 | 评估 | 缓解 |
|---|---|---|
| 观测信息损失 | 策略不再看到"同柱其它层"；但柱位与最近层相对位置（含 `dvec.z`）仍在 ⇒ 影响小 | 若证明不够，转变体 (b) |
| 训练动力学变化 | 窗口内容由"若干不同柱的层"变为"若干柱的代表层" ⇒ 输入分布变化 ⇒ **必须从零重训**（不能 warm-start 旧 actor） | 已计入 1a 重训成本 |
| 与 CBF 口径差异 | 策略看柱、滤波器看球 ⇒ 一类新的"观测看不见但滤波器看得见"不一致（与 G20 同族） | **必须写进文档**；诊断指标同时报"逐柱"与"逐层"两个口径 |
| 部署端未同步 | K6 仓库不在本机 ⇒ 交付链有明确待办 | 注册表 + `navvel_deploy.yaml` 自检；**不要在没有部署侧改动前把新模型标成"现役"** |
| 回退 | 开关置 `false` 即回到现状；冻结 profile 不受影响 | — |

---

## 8. 待你确认的开放问题

1. **变体 (a) 还是 (b)**？（建议 (a)：风险最低、维度与特征含义都不变）
2. **是否把 `A2P` 决定实验排在 A3 之前**？（建议：是 —— 它是"卡点 1 是否真被消灭"的**唯一直接证据**，
   且若通过，路线 A（K 8→12 红线）**大概率就不需要了**）
3. **重训范围**：(i) 只训 `A2P`/`A3P`，承认与 A0–A2L2 跨口径不可比（省时间）；还是
   (ii) 全量重训 A/A1a/A1b/A2（≈1 h，保持阶梯单变量可比）？（建议 (ii)：GPU 成本低，归因纪律更值钱）
