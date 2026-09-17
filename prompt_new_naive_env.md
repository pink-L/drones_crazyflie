# 新对话提示词：新 nominal 臂 + 真柱体（解析圆柱）训练环境

> 用法：把本文件**整份**贴进一个新对话的第一条消息。它是一个自包含的任务说明书，
> 假设新 agent 对项目零上下文。
> 写于 2026-09-17，作者 = 上一个对话的 agent（已完成 P3a / P3-pre / P3b-1 验收）。

---

## 0. 你的角色与边界

你是这个项目的训练侧工程师。你的任务分三件（**按顺序做，每件都有验收门**）：

1. **命名纠偏**：把项目里叫 `naive` 的臂改名为 `obs_proximity`（因为它的"避障能力"来自障碍
   proximity 奖励塑形，不是"裸策略"）。
2. **新建论文式 `nominal_paper` 臂并 from-scratch 训练**：奖励里**只有碰撞惩罚**，没有任何障碍
   proximity 项 —— 对齐 CBF-RL 论文 Table III 的 `Nominal`。
3. **把训练环境的障碍物从"球堆近似柱"换成"解析圆柱"**（半径 = 方柱外接圆，高度随机），
   并把 obs 升级为含 $(\mathrm{sdf},\hat n)$ 的新布局。

**范围内**：训练侧代码（`drones/OmniDrones`）、`cfg/profiles/*.yaml`、训练批次、验收评估、
`drones/NAVVEL_VERSION_AND_RETRAIN_PLAN.md` 的更新。

**范围外（用户已明确排除，不要动）**：部署侧一切 —— `navvel_deploy.yaml`、
`export_navvel_actor.py` 的部署适配、NUC 真机工作、K6 卡点。⚠️ 但 obs 布局一变，
**导出侧必然连带失效**，你要在文档里把这个依赖标成"未完成、强依赖"，**不要自己去改**。

**用户已定的红线（违反会毁数据）**：
- **不能重启服务器**（原因见 §7）。
- **一切 GPU 作业串行**；绝不在训练进行中并发跑 eval（已两次 OOM 把训练进程一起杀掉）。
- 单批次训练 `--parallel 2` 上限。

---

## 1. 30 秒背景

Isaac Sim 5.1 + IsaacLab + OmniDrones 的无人机 RL 项目（`/home/lz/lzspace/drones`）。
任务：6×6×3 m 场地里无人机从一边飞到另一边，躲避柱状障碍，动作为速度指令（100 Hz）。
项目里有一个 **CBF 安全滤波器**（闭式投影，非 QP），训练与部署时都可用。

项目分两大阶段：**阶段 1（几何泛化）已完成**；**阶段 2（去 runtime filter）**——让策略自己
内化安全约束，使滤波器退化为恒等映射。

### 为什么现在要做这三件事（诊断，必读）

上一轮 P3a 训练了 8 个配置（`dual`/`filter_only`/`reward_only`/`naive` × `p_filter`
的 `p1`/`pann`/`p0`），结论是：**只有在 d8 密度下、撤掉 filter 后，才看得出臂间差异**
（d4 协议饱和）。其中最刺眼的一条是：

> **`naive` 臂（cbf.mode=none）撤 filter 后 0.98 到达 / 0 碰撞 —— 但它根本不是论文的 `Nominal`。**
> 项目的 `naive` 带着 **障碍 proximity 奖励**（`edge` 近接触 / `near` 近障减速 / `log` log 距离），
> 光是这些塑形项就足以学会避障，**于是"有没有 CBF filter / 有没有 CBF 奖励"这件事被掩盖了**。
> 论文的 `Nominal`（Table II）只靠 **`r_obstacle = −1×1(碰障)`、`r_wall = −1×1(碰墙)`** 这两个
> 稀疏碰撞惩罚来学避障。

同时，当前障碍物实现是**沿 z 叠一串外接球**来近似一根柱（`n_pillars × pillar_layers` 个球），
导致 M（物理障碍数）被放大到 16–48、obs 窗口 K=8 里一根柱要占 4–6 槽。用户决定：
**改成一个柱 = 一个解析圆柱**，同时把柱高随机化（矮柱可飞越、高柱必须绕行，由策略自主决定）。

---

## 2. 必读（按顺序，不要跳）

1. **`drones/NAVVEL_VERSION_AND_RETRAIN_PLAN.md`** ← **唯一权威执行文档**。重点：
   - `§0.5.26` / `§0.5.27` / `§0.5.28` / `§0.5.29` —— P3a / P3-pre / P3b-1 的完整验收结论
     （含"`dual-p0` ≈ 论文 `Reward Only`、且是唯一撤-filter 达标的臂"）。
   - `§3.4` —— P3 的臂/p_filter 矩阵与实现落点。
   - `§3.5` —— P4 的"方体 SDF"原议程（**注意：本任务用的是更简单的圆柱路线，见 §4**）。
   - `§4.1`–`§4.3` —— 阶段 1/2 的门槛（**两阶段故意用不同门槛**）。
   - `§0.5.19` —— 五个"仪器说谎"类 bug（读它省几个小时）。
   - `§0.5.25` —— `p_filter` 机制、零介入率定义、奖励量级量化。
2. **`drones/MinerU_markdown_Yang_等_-_2026_-_CBF-RL_..._md`** ← CBF-RL 论文。**重点 Table II
   （奖励项）与 Table III（四个变体的训练/部署配置）**：
   - `Nominal` = 训练只用 nominal 奖励、部署无 filter；
   - `Reward Only` = nominal + `r_cbf`、部署无 filter；
   - `Filter Only` = 训练有 filter、部署有/无 filter；
   - `Dual` = `r_cbf` + filter。
3. **仓库记忆**：`/memories/repo/navvel-p3.md`（P3 阶段全部事实与坑）、
   `/memories/repo/omnidrones-navvel-m2.md`（CBF/奖励核历史）。
4. `drones/NAVVEL_RETRAIN_GUIDE.md`（**多处与现状不符，plan 优先**）。

---

## 3. 当前状态（确凿事实，每条都有证据）

### 3.1 环境与工具（不要重新发明）

- Python：`/home/hybrid/miniconda3/envs/lz_env/bin/python`（torch 2.7.0+cu128）。
- Hydra：`train.py` / `eval_ckpt.py` / `pillar_layout_check.py` **必须从 `drones/OmniDrones/` 或
  `drones/OmniDrones/scripts/` 下运行**（`hydra.searchpath` 相对 cwd）。**跑 CPU 脚本也要用上面的
  python**（系统 python 没 torch）。
- 训练：`scripts/train.py`；批量：`scripts/train_batch.py`（含 `clear_gpu()`，硬限并发 2）。
- 验收：`scripts/acceptance_eval.py`（批量 runner）+ `scripts/eval_ckpt.py`（单体）。
- 汇总/门槛判定：`scripts/aggregate_acceptance_eval.py`（阶段 1/2 门槛**已分表**）。
- 布局 CPU 门禁：`scripts/pillar_layout_check.py`（`--layouts N --connectivity`，退出码非零 = 失败）。
- 几何单测：`scripts/cbf_test.py`、`scripts/pillar_geometry_test.py`、`scripts/obstacle_geometry_test.py`、
  `scripts/test_clearance_conventions.py`（**改验收口径前必跑**）。
- GPU：RTX 5090D 32 GB（31.36 GiB 可用）。训练实测 ≈ 650 s / 20M frames / run（`--parallel 2`）。

### 3.2 现有关键文件（先读再改）

| 文件 | 职责 |
|---|---|
| `omni_drones/envs/single/nav_vel.py` | NavVel 环境；obs 组装、奖励核、CBF 装配 |
| `omni_drones/envs/single/nav_vel_obstacles.py` | `ObstacleManager`（纯 torch，无 Isaac）；布局采样、`clearances()`、`build_obs()` |
| `omni_drones/utils/cbf.py` | `filter_velocity`（**闭式迭代投影，数学冻结，红线**）、`cbf_violation`、`CBFVelocityFilter`、`h_boundary_penalty` |
| `cfg/task/NavVel.yaml` | 默认 task 配置（⚠️ **默认 `n_pillars: 0` = 纯球**） |
| `cfg/profiles/*.yaml` | 自包含冻结 profile（A0–A4、P3-*） |
| `scripts/make_geometry_profile.py` | profile 生成器 |

### 3.3 当前 obs 布局（**你要改的就是它**）

```
obs = 62 维 = [0:30] 基础量（drone state + goal rel + time encoding）
            + [30:62] 障碍块 = K=8 槽 × 4 维
每槽 4 维 = [ rpos_x, rpos_y, rpos_z ] / obs_dist_norm  (clamp ±1)
          + [ radius ] / obs_radius_norm                (clamp [0,1])   ← 几何半径，非 CBF 半径
未激活槽 = 全部 0。柱形模式下另有 `_window_per_pillar`：一根柱塌缩成 1 槽（取最近那层球）。
```
⚠️ 第 4 维对柱形世界**几乎没有信息量**（所有柱共用 `pillar_radius`，是个常量）。

### 3.4 当前柱体实现（**要替换的**）

- `pillar_radius: 0.4243`（= 0.6 m 方柱的**外接圆**半径 = 0.6/√2）。
- 柱 = 沿 z 叠 `pillar_layers`（3–6）个**外接球**，覆盖 `[pillar_z_lo, pillar_z_hi] = [0.4, 2.6]`。
- ⇒ `M = n_pillars × pillar_layers`（2–8 柱 × 3–6 层 = 6–48 个物理球）。
- ⚠️ 已知后果：M 大 ⇒ 显存/算力吃紧。**上一轮 16 柱 × 6 层（M=96）在 384×1500 直接 OOM**，
  被迫把层数压到 3–4（M=64）才能跑。

### 3.5 当前奖励项（**`nominal_paper` 要关掉的就是这些**）

`cfg/task/NavVel.yaml` 的 `obstacle` 段里，**障碍 proximity 塑形项**（要关闭的）：

| 键 | 默认 | 含义 |
|---|---|---|
| `reward_obs_log_weight` | 1.5 | log 距离惩罚权重（× `reward_obs_log_scale` 0.3） |
| `reward_obs_log_mode` | `penalty` | 符号（`legacy`=历史错误符号，P3 起用 `penalty`） |
| `reward_near_slowdown_weight` | 0.5 | 近障减速项 |
| `reward_collision_edge` | 2.0 | 每次"新进入接触"的一次性惩罚 |

**碰撞类惩罚**（要保留的）：`reward_crash_penalty: 15`（碰障）、`reward_oob_penalty: 15`（碰墙/出界）。
**任务项**（保留）：`reward_fly_weight: 1.5`、`reward_zone_weight: 1.5`、`arrive_bonus: 40`、
`arrive_time_bonus: 40`、`reward_timeout_penalty: 60`、`reward_action_smoothness_weight: 0.2`。

> 论文 Table II 的 nominal = `r_goal 1.0` + `r_obstacle −1` + `r_wall −1` + `r_progress 20·Δd/(v_max·Δt)`
> + `r_alive 0.01` + `r_timeout −10`。本项目的任务项是它的等价物（数值不同、量纲不同，
> **不要照搬论文数值**，见 §8 反模式）。

### 3.6 验收协议（**已冻结，不许改**）

- 对齐列 `512×600`；收口列 **`384×1500`**（= 1 个完整 episode，判过/不过）。
- ⚠️ 两列数字**永远不许混进同一张对照表**，报告必须标注 `rollout_steps`。
- `set_seed = 1000 + train_seed`，ON/OFF 共用布局（用 `layout_fp` 验证）。
- ON = `+runtime_filter=true`（评估侧强制 p=1）；OFF = `+runtime_filter=false`
  （挂 **shadow** 滤波器：照算 `a_cbf` 但不写回动作）。
- 判定"跑成功"的**唯一**判据是日志里有 `[eval_metrics]` 行，**不是 `exit code == 0`**
  （本机 Isaac 退出时常 segfault，但产物是好的）。
- **P3b-1 建立的密度协议（本轮要沿用）**：`384×1500` + **d8**（`n_pillars_range=[8,8]`），
  因为 d4 下所有臂都饱和（OFF 列人人 ~0.99 到达 / 0 碰，无区分度）。

---

## 4. 任务（四步，每步都有验收门）

### 第 1 步：命名纠偏 `naive` → `obs_proximity`

- 改 `cfg/profiles/P3-naive*.yaml`（以及任何 `A*`/其它 profile 里带 `naive` 的命名）→ `obs_proximity*`。
- 改代码/文档里指代该臂的文字（`nav_vel.py` 注释、`cbf.py` 注释、plan、脚本里的 model-id 字符串）。
- **`cbf.mode: none` 这个语义不要改**（它描述的是"CBF 关闭"，是对的）。
- ⚠️ **不要动 wandb 里已跑的 run 名**（历史记录保持原样），只在**新**批次里用新名。
- 验收：`grep -rn "naive"` 的剩余命中都能解释（历史记录 / 论文引用 / 新名的一部分）。

### 第 2 步：实现解析圆柱障碍 + obs_v3（**这一步是重头**）

#### 2.1 几何：柱体 = 竖直圆柱（半径 = 外接圆，高度随机）

**决策（用户 2026-09-17，已确认）**：不再用"球堆"近似，改成**解析圆柱**：
- 半径 `R = 0.4243`（保留方柱外接圆的保守量；**这是有意的取舍**：外接圆让 CBF 回到圆几何，
  可完全复用现有 `filter_velocity`，且法向处处光滑，避免盒体的"面/棱/角"三分法）。
- **高度随机**（用户要求"覆盖障碍物多样性"）：柱体沿 z 占 `[z_lo, z_hi]`，`z_lo`、`z_hi` 随机
  采样（参考现有 `pillar_z_lo/hi/z_range`，但要给出**更宽的随机范围**，使得"矮柱可飞越"成立）。
- ⇒ `M = n_pillars + n_free`（**一根柱 = 一个物理障碍**），显存与算力大幅下降。

#### 2.2 CBF：用**有限高圆柱 SDF**，**不要**用二元 z 门

$$d_r=\|p_{xy}-c_{xy}\|-R,\qquad d_z=|p_z-c_z|-\tfrac{H}{2}$$
$$\mathrm{sdf}_{\text{cyl}}=\min\big(\max(d_r,d_z),0\big)+\big\|\big(\max(d_r,0),\,\max(d_z,0)\big)\big\|$$
$$h(p)=\mathrm{sdf}_{\text{cyl}}(p)-\big(r_{\text{drone}}+\text{inflation}+\text{rmargin}\big)$$

⚠️ **红线警告**：**绝不要**写成"若 $p_z\in[z_{lo},z_{hi}]$ 则激活、否则不激活" —— 那会让 $h$ 在
穿越柱顶时**跳变**，$\nabla h$ 不存在，CBF 数学直接坏掉。必须用上面这个连续 SDF
（它在柱顶/柱底的"边缘"处梯度仍可定义为一侧径向、一侧轴向）。

`∇h` 只有两种情形：**径向（水平，远离柱轴）或轴向（竖直，向上/向下离开柱端）**。

- **要求：`filter_velocity` 的数学不许动**（红线，改了必须重导 TorchScript + 离线对拍）。
  把它做成"圆柱等价于某个球/圆"的输入适配，或者新增一个**并列的**圆柱投影函数
  （新增函数可以，但必须与 `filter_velocity` 做**数值对拍**：圆柱退化成球时应逐位一致）。
- 单测：圆柱 SDF 的连续性（在柱顶上下扫 z，$h$ 不许跳变）、$\hat n$ 有界且单位长、
  "无人机在柱顶之上时 $h$ 为正且 $\hat n$ 指向上"。

#### 2.3 obs_v3：K=4 槽 × 7 维

```
obs = 30 + 4×7 = 58 维
[0:30]  基础量 —— 逐位不变
[30:58] 障碍块 = 4 槽 × 7 维，每槽：
          rpos_x, rpos_y, rpos_z = (p_obs_center − p_drone)/obs_dist_norm, clamp ±1
          sdf                    = sdf_cyl(p_drone)/sdf_norm, clamp ±1
          n_x, n_y, n_z          = 单位外法向 ∇sdf, clamp ±1
        未激活槽 = 全部 0（掩码）
```

- **K=4（用户 2026-09-17 决定）**：一根柱一个槽 ⇒ 4 槽覆盖最近的 4 根柱，用户认为足够。
- ⚠️ **必须保留三维量**（`rpos` 含 z、`sdf` 是三维 SDF、`n̂` 是三维法向）。理由：
  用户要求"矮柱可飞越、由策略自主决定"，而**策略要能决策就必须看得见柱顶在哪**；
  纯 $xy$ 投影视图会把这个信息抹掉。三维 `sdf` 天然编码"我在柱顶之上还是之下"
  （在顶上 ⇒ `sdf` 大、`n̂` 指向**上** ⇒ 直接告诉策略"往上走是最短出路"）。
- **一致性不变量（必须写测试钉住）**：obs 里的 `sdf` 通道 = `h + (r_drone+inflation+rmargin)`，
  即**与 CBF 用同一个几何**。否则策略看到的世界与它被判的世界不是同一个。
- **版本护栏（必须）**：obs `62 → 58` ⇒ 旧 ckpt（A0–A4、P3-*）**必须加载失败并显式报错**，
  绝不静默 mis-load。同时在文档里声明：**新环境的结论与 P3/P3a/P3b-1 不可比**。

### 第 3 步：新建 `nominal_paper` 臂并 from-scratch 训练

#### 3.1 臂定义（对齐论文 Table III 的 `Nominal`）

```
cbf.mode: none                      # 完全没有 CBF（无 filter、无 reward core）
obstacle.reward_obs_log_weight: 0   # 关掉 log 距离塑形
obstacle.reward_near_slowdown_weight: 0
obstacle.reward_collision_edge: 0
reward_crash_penalty: 15            # 保留：碰障惩罚（= 论文 r_obstacle）
reward_oob_penalty: 15              # 保留：碰墙/出界（= 论文 r_wall）
（任务项全部保留：fly/zone/arrive/timeout/smoothness）
```

- **必须 from-scratch**（用户 2026-09-17 决定）：**不要 warm-start 自 A4**。理由：A4 的策略是
  在"带 proximity 塑形"的奖励下训出来的，warm-start 会把"proximity 学会的避障"带进来，
  使"只用碰撞惩罚能否学会避障"这个命题失效。
- ⚠️ **from-scratch 风险已知**：项目历史上 from-scratch + 稀疏奖励曾出现"零学习 / 熵塌缩"
  （见 `/memories/repo/navvel-nr1.md`）。**必须盯** `entropy`、`std(a)`、`pos_error`、
  `arrival` 曲线；若 5M 帧内 `pos_error` 不下降 ⇒ 停，先做单变量诊断（不要在权重上瞎扫）。

#### 3.2 批次设计（建议，可按实况调整）

- **课程**：`n_pillars_range` 按 **2 → 4 → 8 → 16** 逐级提升（用户指定），
  沿用现成 `nav_curriculum`（`task.curriculum.levels` + `initial_level`），
  升档判据用现有 `success_rate_threshold` / `collision_rate_threshold`。
- **臂集合**（为了能回答"CBF 到底有没有用"，**至少要这 4 个**）：

| 臂 | CBF filter 执行 | 奖励 | 论文对应 |
|---|---|---|---|
| **`nominal_paper`** | 无 | 只有碰撞惩罚 | **Nominal** |
| `obs_proximity`（旧 naive 改名） | 无 | + 障碍 proximity 塑形 | 论文无此格 |
| `dual-p0` | 无（p=0） | + 完整 `r_cbf`（w1/w2） | **Reward Only**（上一轮已证实这是唯一撤-filter 达标的形态） |
| `dual-p1` | ✅（p=1） | + 完整 `r_cbf` | **Dual** |
| （可选）`filter_only-p1` | ✅ | 无 `r_cbf` | **Filter Only** |

- 每臂 **≥3 seed**（建议 5）；`total_frames` 与上一轮同量级（20M 起，按收敛情况调）。
- 训练用 `train_batch.py`（自建 profile，见 `make_geometry_profile.py`；命名建议
  `NP-nominal-paper`、`NP-obs-proximity`、`NP-dual-p0` …）。
- **每臂的 benchmark 问题（必须写进结论）**：
  1. `nominal_paper` 能不能从零学会避障？（对照 `obs_proximity` —— 差值就是 proximity 塑形的贡献）
  2. `dual-p0`（Reward Only）在**新圆柱环境**下是否仍是撤-filter 最优？（上一轮在球堆环境的结论）
  3. 撤 filter（OFF 列）时，有没有任何臂能同时满足"高到达 + 0 碰"？

### 第 4 步：双协议 + d8 密度验收 + 结论

- 用现成 `acceptance_eval.py` / `aggregate_acceptance_eval.py` 跑
  `512×600`（对齐）与 `384×1500`（收口），每 ckpt × ON/OFF。
- **另外跑 d8 协议**（`§0.5.28/§0.5.29` 建立：`384×1500` + `n_pillars_range=[8,8]`），
  因为 d4 饱和、无区分度。
- **课程最高档（16 柱）上必须测 `dropped_relevant_frac`**：K=4 时会有 12 根柱不在窗口内。
  若 `>1%` ⇒ 报告并提请用户裁决（升 K 还是降课程上限）。**不要自己改 K 或改门槛。**
- 结论写回 plan（新开 `§0.5.30`），**包括失败与"无法区分"的结论**。

---

## 5. 设计决策汇总（已拍板，不要再问）

| 项 | 决定 | 出处 |
|---|---|---|
| 柱体几何 | **解析圆柱**，半径 = 方柱外接圆 0.4243，**高度随机** | 用户 2026-09-17 |
| CBF 几何 | **有限高圆柱 SDF**（连续）；**禁止**二元 z 门 | 上面 §4.2.2 |
| 飞越 | **允许**（矮柱可从上方通过，由策略自主决定）⇒ obs 必须带三维信息 | 用户 2026-09-17 |
| obs 窗口 | **K = 4**（滑动窗口取最近 4 根柱） | 用户 2026-09-17 |
| obs 每槽 | **7 维**：`[rpos(3), sdf, n̂(3)]` | 上面 §4.2.3 |
| 课程 | **2 → 4 → 8 → 16** 柱 | 用户 2026-09-17 |
| actor/critic | **本轮只做对称 AC**（`n̂` 给 actor） | 用户 2026-09-17 |
| `nominal_paper` 初始化 | **from-scratch**（不 warm A4） | 用户 2026-09-17 |

### 5.1 第二阶段备选（**未启用，仅供未来参考**）：asymmetric actor-critic

- 项目**已有基础设施**：`ppo.py` 的 `algo.priv_actor` / `algo.priv_critic` 预设，走独立的 obs 键
  `("agents","intrinsics")`；**但 NavVel 没定义 `intrinsics` ⇒ 目前空转**。
- 论文只在**上楼梯**任务用 asymmetric AC：把 **1m×1.5m 高度扫描**（sim-only 地形）**只给 critic**。
  即 asymmetry 的正当理由是"**真机测不到的特权信息**"。
- ⚠️ **不要**把 `n̂` 只给 critic：`n̂` 可由 `rpos` + 已知柱几何推导，**不是特权信息**；
  而且 CBF 条件是 $\hat n\cdot v+\alpha h\ge0$，**最需要 `n̂` 的恰恰是 actor**。
- 若将来要做，critic 的特权内容应为**真正 sim-only** 的量：DR 随机化的质量/惯量/阻力，
  或**超出 K 窗口的全部柱**。actor 的 obs 保持可部署。

---

## 6. 失败判据（提前写死，先于数据）

- **H_prox（proximity 塑形是关键）**：若 `nominal_paper` 与 `obs_proximity` 在 d8/OFF 列的到达率
  差值 ≤ 种子离散度 ⇒ 说明"proximity 塑形"不是差异来源，需要回去查其它机制。
- **H_nominal（纯碰撞惩罚可学）**：若 `nominal_paper` from-scratch 在 5M 帧内 `pos_error` 不下降 ⇒
  稀疏碰撞奖励学不动；**此时不要加权重**，先做单变量诊断（课程密度 / 熵 / 奖励量级）。
- **H_det（可撤 filter）**：若新环境下**没有任何臂**在 d8/OFF 达到"高到达 + 0 碰" ⇒
  阶段 2 在新几何下未达标，如实记录。
- **H_K（K=4 够不够）**：若 16 柱档 `dropped_relevant_frac > 1%` ⇒ K=4 不足，提请裁决。

---

## 7. 硬约束与纪律（违反会毁掉数据或别人的工作）

1. **一切 GPU 作业串行**。训练批次进行中绝不跑 eval（已两次 OOM 把训练进程一起 OOM 杀掉）。
   跑 eval 前先 `nvidia-smi --query-compute-apps` 确认无 compute app。
2. **判"跑成功"的唯一判据是产物/`[eval_metrics]` 行**，不是 `exit code`。
3. **判"训练卡死"看三件事**：checkpoint 时间戳、日志字节增量、`ps -o stat=,etime=,%cpu=`
   （`Rl` + ~140% CPU = 在算）。**不要凭感觉估时间**。
4. **清场按 PID**：`train.py` 调 `setproctitle`，进程名会变成 wandb run 名 ⇒
   `pkill -f train.py` **匹配不到**。用 `nvidia-smi --query-compute-apps=pid` 拿 PID。
5. **`--parallel 2` 是硬上限**。M（=柱数）越大显存越吃紧：上一轮 M=96 在 `384×1500` 直接 OOM，
   M=64 才行。**新高 M 必须先冒烟**（单 ckpt、`--num-envs 384 --steps 1500`、看 `[eval_metrics]`）。
6. **不能重启服务器**。GPU 图形引擎有 Xid 31（`ENGINE GRAPHICS MMU Fault`），每个 eval 进程报一次，
   但 **CUDA 计算引擎健康**。已知绕过 = **降低 `--num-envs`**。`--gpu-reset` 被 `nxnode.bin` 挡住
   且会打断桌面会话，**不要试**。偶发 `Failed to create the raytracing pipeline` 卡住（重跑即可）。
7. **数字一律从 `agg.json` / 日志读**，不许凭记忆或推断。
8. **任何"X 比 Y 好"的断言必须配显著性检验**（至少给种子极差；跨臂比较用 Welch）。
   ⚠️ 上一轮的教训：`dual-p0` vs `dual-p1` 的均值差 n=3–5 下 **p=0.197 不显著**，
   能站住的是"`dual-p0` 5 seed 极差小 50 倍 + 0 碰"。**不要把分布形状的证据写成均值显著性。**
9. **门槛要下在"被考核对象能改变的量"上**。对着配置常量设阈值只会得到与策略无关的 PASS/FAIL。
10. **"指标没出现在表里"与"指标通过了"必须能区分**。新增指标**必须同步加入**
    `aggregate_acceptance_eval.py` 的 `METRIC_ORDER`，否则静默变 `None`。
11. **测试要钉住结论，不要钉住实现**（反例见 plan §0.5.24：一条断言"门槛读的是 `cbf_extra`"
    的测试在**错误的修法上也通过**）。
12. **改任何验收口径前先跑** `scripts/test_clearance_conventions.py`（当前 8/8）。
13. **提交纪律**：两个仓库 —— 外层 `/home/lz/lzspace/drones`（branch `main`）与子模块
    `drones/OmniDrones`（branch `feat/crazyflie-pidrate`）。**先提交子模块再提外层**。
    用 `git commit -F <file>`，**不要用 `-m` 带反引号**（会打断 shell）。
14. **安全白名单（训练期间可跑，纯 CPU）**：`pillar_layout_check.py`、`py_compile`、
    `aggregate_acceptance_eval.py`。**黑名单**：`train.py` / `eval_ckpt.py` /
    任何 `--cfg job`（会 import `omni_drones`，与训练争 GPU）。
15. **动手前先问用户**：改门槛取值、改验收协议、开新批次、或推翻已有结论 ⇒
    先给**证据 + 选项 + 建议**，等裁决。**不要自己改判据让它通过。**
16. **不要碰部署侧**（`navvel_deploy.yaml` / 导出适配 / K6 / NUC）——用户已明确排除。

---

## 8. 反模式清单（上一个 agent 犯过的，别重复）

| 反模式 | 后果 | 正确做法 |
|---|---|---|
| 照搬论文的奖励数值（`r_progress=20`、`w=100`） | 量纲/任务都不同，直接崩 | 论文用来**定方向**，数值必须在本项目重新标定 |
| 把 phase 1 的指标当 phase 2 的门槛 | 报出"phase 1 卡在零介入率"这种错话 | 两阶段门槛**故意不同**（plan §4.1） |
| 自己"拍"一个阈值 | 把门槛偷偷放宽几倍 | 阈值必须能溯源到 plan 或实测 |
| 用一个"单位换算"把 FAIL 变成 PASS | 口径不明时加回常数报 PASS | 口径不明时**并列报全部口径 + 显式标 UNRESOLVED** |
| 凭记忆写数字 | 比较结论写反 | 一律从 `agg.json` / 日志读 |
| 用均值排序当"更好" | 3 seed 看着干净，5 seed 就散了 | 配显著性检验；落在离散度内就说"未区分" |
| 新增指标没加进 `METRIC_ORDER` | 指标静默变 `None` | 加了新指标就跑一次聚合器确认它出现在表里 |
| 训练进行中并发跑 eval | OOM，把训练 seed 一起杀掉 | 一切 GPU 作业串行 |
| 在**饱和的协议**下下结论 | d4 下所有臂都 0.99/0 碰，"谁更好"无从谈起 | 先用密度/难度把协议推到**有区分度**（§0.5.28 的教训） |
| from-scratch 学不动就狂加权重 | 熵塌缩/更差 | 先做**单变量**诊断（课程密度、熵、奖励量级） |

---

## 9. 一句话起点

**P3b-1 证明了"项目里的 `naive` 其实是被 proximity 塑形喂出来的"，于是"CBF 有没有用"这个问题
从来没有被干净地问过。** 本轮要做的是：(a) 把那个臂正名为 `obs_proximity`；
(b) 造一个论文口径的 `nominal_paper`（**只有碰撞惩罚**）并 **from-scratch** 训练；
(c) 顺手把障碍物从"球堆近似"升级成**解析圆柱（高度随机）**，并把 obs 从
`[rpos, 半径]` 升级成 `[rpos, sdf, n̂]`（K=4）。

**第一步不要写训练代码**：先做 §4 第 1 步（改名）与第 2 步的几何/obs 实现 + CPU 单测，
把 `h`/`sdf`/`n̂` 的一致性不变量钉住，再谈训练。
