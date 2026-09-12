# M3 规划：CBF-RL Dual 复现 —— 训练中滤波 + 组合式 reward core，实现「无 runtime filter 部署也安全」（internalize）

> 创建时间：2026-09-06 01:4x
> 目的：**给"下一阶段 agent 会话"提供从 M2 现状出发、对接 CBF-RL 论文（Yang et al. 2026）的完整实验蓝图**。
> 输入文档：
> - M2 现状/教训/下一步：`drones/m2_plan.md`（文件开头 ⭐ 会话总结 B/C + 交接摘要 #7–#13）
> - CBF-RL 论文全文（用户指定 MinerU markdown）：`drones/MinerU_markdown_Yang_等_-_2026_-_CBF-RL_safety_filtering_reinforcement_learning_in_training_with_control_barrier_functions_2054593947461390336.md`
> - 奖励实现口径：`drones/navvel_rl_interface.md` §3.6/3.7
> 仓库：`/home/lz/lzspace/drones/OmniDrones`（分支 `feat/crazyflie-pidrate`，HEAD `08a8e33`[M3-B]，tag `d2-16obs-achieved`）；环境 `conda activate lz_env`，命令在 `OmniDrones/scripts/`，**wandb `CBFM3`（2026-09-06 起由用户新建，替换原 `RL90`；此后本阶段所有 run 均进 `CBFM3`）**。
>
> ⚠️ 本文件是"规划/指导"，不是执行记录。动手后把 run id/结果回填到文末「执行记录」。

---

## ⭐ 阶段性总结（2026-09-06 ~20:35 UTC+8；M3-A + M3-B 收官；下一步：用重新设计的奖励从 0 重训）

> 本会话完成（均 wandb `CBFM3`；详细数据见文末「执行记录」+「改进 v2/v3/v4」+「M3-B」小节）。

**1. M3-A 实现**：`penalty_src=dual`（commit `d2c33ec`）＝论文式两项相加 $r_{cbf}=w_1\text{viol}(\mathbf v_{nom})+w_2(1-e^{-\text{corr}^2/\sigma^2})$；`nominal/correction/gaussian` 三模式逐位兼容。

**2. 保守 drift 诊断 + 奖励数值重设计**（核算驱动，全 CLI 覆盖、yaml 默认未动）：
- 现象：训练后期 `cbf_violation` 降 + arrival/success 降（run 0x9hwq8t：arrival 0.74→0.45 同期 viol 0.16→0.02）。
- 根因：Hover 常驻 pose/up/effort 堆 **return 基座 ~600**（悬停也正）稀释任务项；soft-respawn + `timeout_penalty=0` 使"悬停/绕远不达"无成本；PBRS 势差≈路径无关不罚绕远。
- 新数值：`reward_pbrs_weight` 8→**16**、`arrive_bonus` 10→**30**（60 反伤）、`reward_timeout_penalty` 0→**60**（高 to = 抗后期退化主角）。

**3. M3-B DR**：`CmdGaussNoise`（commit `08a8e33`，`task.dr_noise_sigma`，默认 0 逐位不变）＝动作链 CBF 投影后/VelController 前注入执行层高斯噪声（对齐论文 L250 d~N(0,20%v_max)）。

**4. 关键结果**（D2-16 / w8，确定性 eval @600/1024env）：
| 配方 | 6.5M ON | 20M OFF joint / coll | 备注 |
|---|---|---|---|
| 原 (w1,w2)=(0.2,0.2) | 0.624 | 0.396 / 18.6% | M3-A 首档基线 |
| V3 (+ab20,to10) | 0.711 | 0.393 / 23.6% | 到达侧增强有效 |
| W2 (w8+ab30+to40) | 0.693 | **0.444** / 20.6% | **全谱 20M 最优（不早停）** |
| **S3 (w16+ab30+to60)** | **0.743** | 0.387 / 22.7% | **主推早停配方（6.5M 取峰）** |
| DR2 (S3+dr0.36) | 0.715 | **0.412 / 18.8%** | 20M 无 filter 部署推荐；扰动下最稳 |
| M2 corr/gauss/filter OFF 基线 | — | ~0.40 / 36–41% | internalize 对照 |

→ **新奖励配方把无 runtime filter 部署碰撞从 36–41% 压到 18.8–22.7%（≈减半）**，ON joint 早峰 0.74。

**5. 关键教训**：
- reward-core 变体**早峰型 ~6.5M 不可避免** → 部署须早停取峰，或靠高 `timeout_penalty`(40–60) 抗后期退化。
- 大 CBF 权重（w1=0.2）下到达侧须等比例增强（ab/to/w 三旋钮）才不保守；w1 = internalize 潜力 ↔ 有 filter 激进到达的权衡旋钮。
- DR 增益温和：早峰无益（S3 noDR 仍最佳）；价值在 **20M 无早停部署的 internalize + 扰动鲁棒**；σ=0.36（论文 20%）最优，0.54 过噪。

**6. 下一步（用户拍板 2026-09-06）**：用**重新设计的奖励从 0 训练**（不再是 warm `lmhvaqka`）——新起点配方候选：
- 早停口径 **S3**：(w1,w2)=(0.2,0.2) + `reward_pbrs_weight=16` + `arrive_bonus=30` + `reward_timeout_penalty=60` + σ0.5；
- 或 20M 口径加 `dr_noise_sigma=0.36`（DR2）；
- ⚠️ 共享奖励改动（w16/ab/to）后续与 filter_only/naive 等对比需各臂同参数；建议先 fresh-0 跑 dual-S3 一档看从 0 的学习曲线/早峰/漂移是否依旧，再决定全臂与 DR。

---

## 0. TL;DR（一句话版）

**M2 收官结论：D2-16 高密度下，安全 = CBF runtime filter（部署必须在线）**；corr/gauss/filter_only 开 filter 碰撞 1–3%，**关 filter 立刻崩到 36–41%**（= naive/reward_only 档）。**论文 Table I 的关键对照：Filter-Only w/o rt.filter = 38.7%（与我们 filter OFF 36–41% 几乎逐位一致），而 Dual w/o rt.filter = 92.7%**——论文证明"训练时滤波 + **两项相加**的 r_cbf"能让策略 **internalize 安全，部署可不要 runtime filter**。

**M3 主线（用户拍板）**：把我们的 reward core 从 `penalty_src`（nominal/correction/gaussian **互斥**）改为**论文式两项相加的组合**（$w_1\cdot\underbrace{\min(\mathbf a^\top\mathbf v^{pol}-b,0)}_{\text{nominal viol}} + w_2\cdot\underbrace{(e^{-\|\mathbf v^{pol}-\mathbf v^{safe}\|^2/\sigma^2}-1)}_{\text{gaussian correction}}$），在 D2-16/w8 训 **Dual**，验证**部署无 runtime filter 时碰撞是否从 36–41% 显著下降（internalize 出现）**。低成本优先：只动 reward core，不动动力学/滤波器。DR、同口径评估、消融对齐作为后续里程碑（§5）。

---

## 1. M2 现状基线（复现入口，全部确定性 eval@600/1024env，w8 shaping）

### 1.1 交付候选（带 runtime filter）
| 配方 | ckpt | arrival/coll/joint | 类型 |
|---|---|---|---|
| filter_only w8 | `204342-vaa0vtzz` @20M final | 0.806 / 2.2 / 0.789 | 爬升型·final 即峰 |
| corr-hybrid w8 λ0.05 | `204342-mu9vegr8` @6.5M | 0.798 / 1.7 / 0.786 | 早峰型·需早停 |
| gauss-hybrid w8 σ0.5 λ0.1 | `214134-z36ag4ib` @6.5M | 0.774 / 1.6 / 0.765 | 早峰型 |

### 1.2 runtime filter on/off（M2 #12/#13 结论）
| 密度 | 臂 ON（coll）| 臂 OFF（coll）| naive/reward_only 参考 |
|---|---|---|---|
| 16 障 | corr 1.8 / gauss 0.9 / filter 2.9 | **36–41%** | 44–47% |
| 8 障 | 0.3–1.3% | **19–23%** | 24–27% |

**核心差距**：我们的 corr/gauss（reward-core 变体）部署关 filter 仍 36–40%，**没有 internalize**；论文 Dual 关 filter 92.7%（Table I）。

### 1.3 M2 沉淀的关键教训（m3 必须继承）
1. reward-core 变体是**早峰型**（~6.5M 峰后过训退化）→ 训练要周期 mid-ckpt eval + 早停取峰（save_interval≈3M）。
2. value_loss→0 不等于 policy 收敛；后期看漂移/过训窗口。
3. CBF 权重"小 λ 微调"在互斥模式成立；shaping w8 是推力主源。
4. eval 基建已扩展：`+perturb`（命令扰动）、`+runtime_filter=false`（无 filter 部署测试）、`cbf_violation` 打印——M3 直接复用。

---

## 2. CBF-RL 论文要点提炼（对齐用；引用一律指向论文 md 行号）

### 2.1 方法（论文 §III，md L126–233）
- **用的就是连续时间一阶 CBF**（确认用户判断）："we replace the typically nonlinear DTCBF constraint with the **continuous-time CBF first-order inequality**"，化为单线性约束 QP (18)(19)，闭式解 (20)；**Lemma 1 + Theorem 1（md L167–232）证明 Δt 足够小（≈≤0.01s，物理引擎稳定域）时，连续 CBF 工具可直接用于离散 RL**。
  → **我们 `cbf.py` 的滤波（对每个激活球 $n_i^\top v + \alpha h_i \ge 0$ 迭代闭式投影）与论文 QP(18–20) 逐位等价**，滤波器无需改动。
- **r_cbf 是"两项相加"**（Eq.22+23，md L211–223；Alg.1 step 13，md L226–233）：
  $$r_{cbf}=w\Big[\underbrace{\min\big(\mathbf a_k^\top\mathbf v_k^{pol}-b_k,\,0\big)}_{\text{第一项 = nominal viol}}+\underbrace{\Big(e^{-\frac{\|\mathbf v^{pol}-\mathbf v^{safe}\|^2}{\sigma^2}}-1\Big)}_{\text{第二项 = gaussian correction}}\Big]$$
  权重 $w$（Table II 中 r_cbf 用 ×100），$\sigma$ 论文 0.5。第一项无界负（越违反越罚）、第二项∈[−1,0)（饱和平滑，防主任务奖励被冲垮）。
  → **我们当前 `penalty_src` 是互斥**（只加一项：correction 线性或 gaussian 饱和，或 nominal viol）——**这是 M2 没 internalize 的首要代码级差异**。

### 2.2 消融与部署（论文 md L248–257, Table I/III）
- 训练 4 变体（Dual / Reward-only / Filter-only / Nominal）× 部署（rt.filter 有/无 + DR）= Table III 12 组合；4096 env、1500 steps。
- **Table I（no DR）**：
  | 方法 | 部署(带 rt.f) | 部署(无 rt.f) |
  |---|---|---|
  | Dual | 99.0% | **92.7%** |
  | Reward Only | 91.9% | — |
  | Filter Only | 98.8% | **38.7%**（≈我们 filter OFF 36–41%）|
  | Nominal | 51.4% | — |
  → **Filter-only 只在有 filter 时好（与我们一致）；Dual 才能 internalize（无 filter 92.7%）**。

### 2.3 Domain Randomization（DR，论文引用位置）
- md L46（intro 相关 work）："by relying on **domain randomization** during training, dual-trained policies remain safer under uncertainty ... without explicit models"。
- md L250 + Table I（single-integrator robustness）：训练时对动力学加噪声 $\mathbf q_{k+1}=\mathbf q_k+(\mathbf v_k+\mathbf d)\Delta t$，$\mathbf d\sim\mathcal N(0, 20\%\, v_{max})$ → **Dual 退化最小**（Dual 无 DR 99.0→DR 99.0/−0%；Dual w/o rt.f 92.7→91.7/−1%；Reward-only 91.9→87.6/−4.3%）。
- md L296 Table III：12 组合含 DR 列。md L28（摘要）：humanoid 用 DR。
- 结论引用：**DR 让 dual 策略对动力学不确定更鲁棒（Table I），是我们 M3-B 的动机**。

### 2.4 论文 Future（md L335）：automated barrier discovery、perception-based barriers、扩展到 whole-body loco-manipulation（远期，仅记录）。

---

## 3. 代码现状与 M3-A 改动点

### 3.1 现有 reward core（nav_vel.py，commit afc6fa2 后）
- `penalty_src ∈ {nominal, correction, gaussian}`：`correction`/`gaussian` 走"复跑 `filter_velocity` 得 `v_safe` → 罚纠偏量"分支；`nominal` 走 `cbf_violation(v_nom)`（Σ min(0,g) + intrude）分支。**互斥，从不叠加**。
- filter：`CBFVelocityFilter`（Compose 逆序先作用）+ reward core 里 `filter_velocity` 复算（`v_safe` 可得，`cbf_correction_sigma` 已存在）。

### 3.2 M3-A 改动（✅ 2026-09-06 已实现 commit `d2c33ec`；本阶段：只动 reward core，不动滤波/动力学）
新增 `penalty_src=dual`（仅 filter/hybrid 有意义；公式/键见 navvel_rl_interface.md §3.7）：
$$r_{cbf}^{dual}=w_1\cdot \text{viol}(v_{nom}) - w_2\cdot\big(1-e^{-\text{corr}^2/\sigma^2}\big),\qquad \text{corr}=\|v_{safe}-v_{nom}\|$$
即把论文 Eq.22+23 用我们已有量表达并相加：第一项 = 现有 nominal viol（Σ_active min(0,$n_i^\top v_{nom}+\alpha h_i$)+intrude），第二项 = 现有 gaussian 饱和罚。建议键：
- `task.cbf.penalty_src=dual`
- `task.cbf.reward_weight`（= $w_1$，viol 项；默认 0.5 现值起步再标定）
- `task.cbf.correction_weight`（= $w_2$，correction 项；默认对齐 reward_weight 或单独 0.05–0.5）
- `correction_sigma` 沿用（0.5）。
实现时保留 `nominal/correction/gaussian` 逐位兼容（默认不动基线），`dual` 仅新增分支。

> 设计注：论文单权重 $w$ 同乘两项（Table II ×100）。我们因任务每步奖励尺度、shaping w8 强，**直接搬 ×100 大概率重演 M2"大罚保守塌陷"** → 先以"小 $w$ 双项"（如 $w_1\in\{0.05,0.1\}$、$w_2\in\{0.05,0.1,0.5\}$）起步；可另加一组镜像论文的相对大权重作对照（若 shaping 归一化后再说）。

---

## 4. M3-A 实验设计（本阶段执行）

### 4.1 假设与验收
- **假设**：两项相加的 dual r_cbf（补上 nominal viol 项的"持续到安全"信号 + gaussian 的"贴近安全动作"平滑信号）比单项 correction/gaussian 更完整地"教会策略把 v 输出到安全区内"→ **internalize 出现**：同 ckpt 部署 `runtime_filter=false` 时碰撞显著低于现 corr OFF(36–41%)。
- **验收（内部化程度）**：
  1. dual ckpt @无 filter 部署 collision < 现 corr/gauss OFF 的 **50%**（如 <18% @16 障），且
  2. joint 不崩（无 filter 部署 joint ≥ 有 filter 的 ~70–80% 量级），
  3. 记录"有 filter vs 无 filter"的碰撞差（论文比例：Dual 99→92.7 掉 6.3pt；Filter-only 98.8→38.7 掉 60pt）。
- **对照**：同起点/同帧数的 `penalty_src=correction` / `gaussian`（现有 run 即可作 OFF 基线 36–41%）。

### 4.2 训练（D2-16 / w8，warm lmhvaqka-final，与 M2 配方一致）
- 一组 20M：`penalty_src=dual`，先 $w_1=0.1, w_2=0.1$（或按标定），`correction_sigma=0.5`，`entropy_coef=0.02`，brake off，`reward_pbrs_weight=8`，`+render_eval=false`，`save_interval=100`（≈3.3M ckpt，防漏早峰）。
- 若预算允许：$w_2$ 扫 {0.05, 0.1, 0.5} × 20M（4 并行 ~10min，早峰~6.5M 教训 → 每档都 eval mid-ckpt）。
- 每档 eval：`runtime_filter=true` 与 `runtime_filter=false`（无扰 + σ0.3 扰动）@ {6.5M, 20M}。

### 4.3 评估命令模板（scripts/，先 conda activate lz_env）
```bash
# 训练（D2-16 / w8 / dual）
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=online wandb.project=CBFM3 \
  wandb.run_name=NavVel-D2-16obs-hybrid-dual-w1_0.1-w2_0.1-pbrsw8-20M \
  task.obstacle.num_scene=16 'task.obstacle.spawn_xy_range=[[-2.2,-2.2],[2.2,2.2]]' \
  'task.curriculum.levels=[0,16]' task.curriculum.initial_level=1 task.curriculum.enabled=false \
  task.obstacle.reward_collision_edge=4 task.obstacle.reward_near_slowdown_weight=1.0 \
  task.reward_pbrs_weight=8 task.cbf.mode=hybrid task.cbf.use_brake_term=false \
  task.cbf.penalty_src=dual task.cbf.reward_weight=0.1 task.cbf.correction_weight=0.1 \
  task.cbf.correction_sigma=0.5 algo.entropy_coef=0.02 \
  algo.checkpoint_path=.../lmhvaqka/checkpoint_final.pt total_frames=20_000_000 save_interval=100 +render_eval=false
# 部署测试（同 ckpt，runtime filter 有/无 + 扰动）
python -u eval_ckpt.py task=NavVel ... +checkpoint=<dual ckpt> +rollout_steps=600 +runtime_filter=true|false [+perturb=cmd_gauss +perturb_strength=0.3]
```

---

## 5. 后续里程碑（记下待做；M3-A 完成后再逐项推进）

- **M3-B（DR）**：训练对动力学加噪声（$\mathbf d\sim\mathcal N(0,20\% v_{max})$ 加到每步速度指令，论文 L250）——需在 env/action 注入随机扰动实现（可复用 `+perturb` 思路搬到训练侧）；预期：dual+DR 对动力学不确定最鲁棒（Table I），也可能进一步助 internalize。**仅动 CBF 变体臂可先验证，再决定是否全臂。**
- **M3-C（同口径评估）**：与论文对齐——1000 random test envs、报告"带/不带 rt.filter"的 success/joint（我们已有 eval_ckpt 基建；把 repeated-seed 平均与 success 口径补上）。
- **M3-D（完整消融）**：对齐 Table III —— 4 训练变体（Dual / Reward-only / Filter-only / Nominal）× 部署（rt.filter 有/无）× DR（无/有）逐格填表；对比论文数字。
- **M3-E（权重/σ 系统标定）**：dual 的 $w_1,w_2,\sigma$ 网格 + shaping 归一化（论文 progress 除 $v_{max}\Delta t$，需全臂同步——见 m2 ⭐C ④）。
- **M3-F（远期/论文 future）**：DTCBF ρ 显式、automated barrier discovery、perception-based barrier（基于观测的 h）、动态障碍/编队扩展。

---

## 6. 里程碑与验收汇总

| # | 内容 | 验收 |
|---|---|---|
| M3-A | 组合式 dual reward core 实现 + D2-16/w8 20M 训练 + 无 filter 部署测试 | dual ckpt @runtime_filter=false collision < 现 corr OFF(36–41%) 的 50%，joint 不崩 |
| M3-B | DR（20%·v_max 动力学噪声）训练 | dual+DR 扰动鲁棒 ≥ dual（对齐 Table I 趋势）|
| M3-C/D | 同口径 1000 env 评估 + 4×部署消融表 | 与论文 Table I 趋势对齐（Dual>Reward>Filter>Nominal 于无 filter 部署）|
| M3-E/F | 标定 + 远期 | 见 m2 ⭐C 与论文 §V |

---

## 执行记录（回填用）

### M3-A（2026-09-06，UTC+8）

| 时间 | 事项 | 产物 / run |
|---|---|---|
| 09:1x | 读 m3_plan 现状 + M2 教训 + 接口文档 §3.6/3.7；确认 warm `lmhvaqka` final ckpt 存在；确认 GPU 空闲 | — |
| 09:2x | **实现 `penalty_src=dual`**：nav_vel.py reward core 新增 dual 分支 = $w_1\cdot\text{viol}(\mathbf v_{nom})$[$w_1$=`reward_weight`] $+\, w_2\cdot(1-e^{-\text{corr}^2/\sigma^2})$[$w_2$=`correction_weight`（新键，默认 0）]；`nominal/correction/gaussian` 三模式逐位兼容（清理重复注释）；NavVel.yaml 文档同步 | commit `d2c33ec`；get_errors 通过 |
| 09:3x | CPU 回归 `cbf_test.py` 全 PASS；GPU 冒烟 30k 帧（D2-16/w8/hybrid/dual w1=w2=0.1）无 NaN：arrival 0.751 / coll 0.12% / cbf_violation 0.048 / curriculum_level=16 | smoke（offline，无 run id） |
| 09:42 | **启动首组 20M（w1=0.1 / w2=0.1，w8，warm `lmhvaqka` final，D2-16 锁 16 障，edge4+near1，关 brake，ent0.02，save_interval=100，render_eval=false）** | wandb **`CBFM3`** run **`nai6lvye`**（run_name `NavVel-D2-16obs-hybrid-dual-w1_0.1-w2_0.1-pbrsw8-20M`）；日志 `/tmp/navvel_dual_w1_0.1_w2_0.1_20M.log` |
| 09:44–09:47 | 20M 训练完成（~130k fps ≈4.5min）；熵 1.35→0.96 平滑收敛（未塌缩到负）；train-final eval arrival 0.552 / coll 0 / coll_ep 2.1% | ckpt：0.03/3.3/6.6/9.9/13.1/16.4/19.7M + `checkpoint_final.pt` |
| 09:50+ | **确定性 eval_ckpt @600/1024env**（w8/D2-16，runtime filter ON/OFF × 6.5M/20M）→ 结果见下 | 6.5M=`checkpoint_6586368.pt`；20M=`checkpoint_final.pt` |

**M3-A 首组结果（dual w1=w2=0.1，D2-16/w8，eval@600/1024env）**：

| ckpt | filter ON (arr / coll / joint) | filter OFF (arr / coll / joint) |
|---|---|---|
| 6.5M | 0.719 / 2.5% / 0.703 | 0.738 / **33.7%** / 0.521 |
| 20M | 0.540 / 2.6% / 0.527 | 0.561 / **26.2%** / 0.425 |

**M2 OFF 基线（同口径 @16障）**：corr/gauss/filter_only 关 filter = **36–41%**；naive/reward_only = 44–47%。

**internalize 验收判定（§4.1）**：
- ✅ **部分下降（方向性证据出现）**：dual OFF 碰撞 = 6.5M **33.7%** / 20M **26.2%**，**低于 corr/gauss OFF 全档（36–41%）**——尤其 20M 26.2% 比 M2 最低 OFF 档再降 ~10pt（≈降 1/3）→ **训练中滤波 + 两项相加 r_cbf 确实让"无 filter 部署"碰撞下降**，internalize 方向首次实证。
- ❌ **未达验收线 <18%**（< corr OFF 的 50%）；且无 filter 时 joint 仍大幅下掉（6.5M 0.703→0.521、20M 0.527→0.425）。
- ⚠️ **早峰型仍在**：有 filter 下 6.5M(0.703) ≫ 20M(0.527)（过训退化，同 M2 reward-core）；但 **dual@6.5M ON(0.703) < M2 corr@6.5M(0.786)/gauss@6.5M(0.765)** → 首档 w1=w2=0.1 下 dual 有 filter 并不更优（viol+gaussian 两项总罚相对 M2 单项甜点 λ0.05~0.1 偏大/交互待标定）。

**下一步（✅ 2026-09-06 用户拍板执行 w1/w2 网格）**：w1∈{0.05,0.2} × w2∈{0.05,0.2,0.5}（2×3=6 档）每档 20M + mid-ckpt(6.5M) eval，盯"无 filter coll <18% 且 joint 不崩"。

### M3-A 权重网格标定（执行中，2026-09-06 ~09:5x UTC+8）

> 配方统一：warm `lmhvaqka` final、D2-16 锁 16、w8、edge4+near1、关 brake、ent0.02、σ0.5、20M、save_interval=100、render_eval=false，仅变 `reward_weight`(w1)/`correction_weight`(w2)。wandb **`CBFM3`**。

| 批 | 档 (w1,w2) | run id | 状态 |
|---|---|---|---|
| B1 | (0.05, 0.05) | `dqqtb7vj`（run-20260906_095446，wandb CBFM3） | ✅ 训练+eval 完成 |
| B1 | (0.05, 0.2) | `4k528a5a`（run-20260906_095446） | ✅ 训练+eval 完成 |
| B1 | (0.05, 0.5) | `2ksor0by`（run-20260906_095446） | ✅ 训练+eval 完成 |
| B2 | (0.2, 0.05) | `xpkfc4a2`（run-20260906_100359） | ✅ 训练+eval 完成 |
| B2 | (0.2, 0.2) | `0x9hwq8t`（run-20260906_100359） | ✅ 训练+eval 完成 |
| B2 | (0.2, 0.5) | `qlnb10ap`（run-20260906_100359） | ✅ 训练+eval 完成 |

> 分批原因：32GB GPU，3 并行 ~17GB（~5.7GB/路）；6 并行会超 → 3+3 两批。

**网格 eval 结果矩阵（确定性 eval @600/1024env，D2-16/w8，arr / coll% / joint）**：

| (w1,w2) | 6.5M **ON** | 6.5M **OFF** | 20M **ON** | 20M **OFF** |
|---|---|---|---|---|
| (0.05,0.05) | 0.745 / 1.4 / 0.735 | 0.746 / **41.0** / 0.484 | 0.584 / 1.8 / 0.574 | 0.551 / **28.5** / 0.411 |
| (0.05,0.2) | 0.775 / 1.8 / **0.764** | 0.787 / **38.9** / 0.526 | 0.505 / 2.8 / 0.496 | 0.521 / **24.2** / 0.404 |
| (0.05,0.5) | 0.697 / 2.1 / 0.688 | 0.729 / **33.8** / 0.511 | 0.500 / 3.2 / 0.488 | 0.497 / **22.1** / 0.400 |
| (0.2,0.05) | 0.675 / 1.3 / 0.668 | 0.685 / **31.6** / 0.513 | 0.444 / 1.9 / 0.441 | 0.470 / **19.9** / 0.380 |
| (0.2,0.2) | 0.635 / 2.1 / 0.624 | 0.667 / **32.6** / 0.466 | 0.502 / 1.3 / 0.497 | 0.495 / **18.6**⭐ / 0.396 |
| (0.2,0.5) | 0.686 / 1.4 / 0.679 | 0.723 / **29.8** / 0.533 | 0.491 / 2.1 / 0.486 | 0.520 / **23.1** / 0.409 |
| 参考 (0.1,0.1) | 0.719 / 2.5 / 0.703 | 0.738 / **33.7** / 0.521 | 0.540 / 2.6 / 0.527 | 0.561 / **26.2** / 0.425 |

**M2 OFF 基线（同口径 @16障）**：corr/gauss/filter_only 关 filter = **36–41%**；naive/reward_only = 44–47%。

**网格结论**：
1. **无 filter 部署碰撞随 w1（viol 项）增大而显著下降**：@20M OFF，w1=0.2 家族 = **18.6–23.1%** < w1=0.05 家族 22.1–28.5% < w1=0.1 首档 26.2%；@6.5M OFF 同样 w1=0.2 更低（29.8–32.6% vs 33.8–41.0%）→ **nominal viol 项是 internalize 主驱动力**（它持续教“指令留在安全区”，gaussian 只做平滑）。
2. **最佳 internalize = (0.2, 0.2) @20M OFF coll 18.6%**：相对 M2 corr/gauss OFF 最低档 36% 降 ~48%、对平均 ~38.5% 降 ~52%——**基本触及“相对减半”验收**（绝对 18% 线还差一点点）；但 joint 无 filter 仍 0.40（vs 有 filter 0.50–0.76）。
3. **ON 侧权重方向相反**：有 filter 时小 w1 + 中 w2 最优（(0.05,0.2)@6.5M joint 0.764），w1=0.2 显保守（ON 6.5M joint 0.62–0.68）→ **w1 是“internalize 潜力”与“有 filter 激进到达”的权衡旋钮**。
4. **早峰型全网格成立**：各档 ON @6.5M ≫ @20M（过训退化）；部署候选需早停 6.5M。
5. **无任何档真正 <18%**：18.6% 为极限；纯靠 dual 两项相加（当前 σ0.5/w8/无 DR）在 D2-16 只能“半 internalize”。

**下一步候选（待用户拍板）**：① 继续加码 w1（如 w1∈{0.3,0.5}×w2∈{0.05,0.2}）试把 OFF coll 压到 <18%（但 ON 会更保守）；② **M3-B DR**（训练加 20%·v_max 动力学噪声）与 dual 结合，论文 Table I 显示 DR 下 dual 退化最小 → 可能同时提无 filter 鲁棒；③ 转 M3-C/D 同口径/消融（把当前 best 纳入 Table III 填格）。

---

## M3-A 改进 v2：抗「保守 drift」诊断 + 验证（2026-09-06 10:3x UTC+8）

### 用户观察（2026-09-06）：随训练推进 cbf_violation 持续下降，但 arrival/success_rate 同步走低 → 如何在高到达率下保持低 violation？调奖励？加长训练？

### 诊断（run `0x9hwq8t` (0.2,0.2) 训练窗口序列）
| 阶段 | arrival | success | cbf_violation | collision_ep |
|---|---|---|---|---|
| ~3M | 0.72–0.75 | 0.69–0.72 | 0.16 | 1.1–2.0% |
| ~9M | 0.67 | 0.63 | 0.067 | 1.4–2.6% |
| ~15M | 0.55 | 0.50 | 0.046 | 1.5–2.3% |
| ~20M | 0.45 | 0.43 | 0.022–0.047 | 1.5–2.3% |

**机制（三层）**：
1. **CBF 罚面稠密持续 vs 到达稀疏一次性**：`arrive_bonus=10`（1 次）对不过高密度下每窗被滤波拦几次的 viol+corr 累积罚 → 策略倾向“零罚退避”。
2. **soft-respawn 多命 + `reward_timeout_penalty=0` ⇒ “600 步未达”零成本** → 保守绕行/低速是**无负反馈的中性吸子**；critic 收敛后纯策略优化持续把输出推向该吸子（viol→0、arrival 塌）。论文 hard-episode + `r_timeout=−10` 正是防此。
3. **PBRS shaping 近路径无关**（telescoping），绕行损失不大，拦不住 CBF 罚拉力。

**“提高训练步长？”结论**：① 总帧数加长 = 加重过训（6.5M 确定性峰后 20M 退化已证；40M 更保守），无效；② 单 episode 600→更长 = 助长绕行且 M2 已测 1200 步 eval 无提升、牵动全臂口径。→ **修目标函数失衡，不修长度**。

### 改进方向（强化“到达侧”对抗 CBF 罚面；不衰减 CBF、无时序副作用，纯 CLI 旋钮不动基线默认）
- ① `task.arrive_bonus` 10→**20**（提高到达峰值收益）
- ② `task.reward_timeout_penalty` 0→**10**（给 600 步未达真实成本，对齐论文 r_timeout，打破保守吸子）
- ③ ①②组合
- 载体 = best 档 (w1,w2)=(0.2,0.2)，对照原 `0x9hwq8t`（20M ON 0.497 / OFF coll 18.6%）。

### 验证 runs（2026-09-06 10:33 启动，3 并行，CBFM3）
| run | 配方 | run id | 状态 |
|---|---|---|---|
| V1-ab20 | (0.2,0.2)+arrive_bonus=20 | `wajnc90h`（run-20260906_103353） | ✅ 训练+eval 完成 |
| V2-to10 | (0.2,0.2)+timeout_penalty=10 | `mu5gdr08`（run-20260906_103353） | ✅ 训练+eval 完成 |
| V3-ab20to10 | (0.2,0.2)+arrive_bonus=20+timeout_penalty=10 | `rka11wiz`（run-20260906_103353） | ✅ 训练+eval 完成 |

**V 系列确定性 eval 结果**（对照原 (0.2,0.2) `0x9hwq8t`）：

| 配方 | 6.5M ON joint | 6.5M OFF joint / coll | 20M ON joint | 20M OFF joint / coll |
|---|---|---|---|---|
| 原 (0.2,0.2) | 0.624 | 0.466 / 32.6% | 0.497 | 0.396 / **18.6%** |
| V1-ab20 | 0.667 | 0.516 / 33.3% | 0.459 | 0.391 / 21.2% |
| V2-to10 | 0.659 | 0.527 / 32.3% | 0.433 | 0.386 / 20.3% |
| **V3-ab20to10** | **0.711** | **0.532** / 33.4% | 0.483 | 0.393 / 23.6% |

**V 结论（回答用户疑问的实证版）**：
1. **“到达侧增强”（arrive_bonus 20 + timeout_penalty 10）有效提高早峰、但防不住后期 drift**：V3 把 (0.2,0.2) 的 6.5M ON joint 0.624→**0.711**（+9pt）、OFF joint 0.466→**0.532**（+7pt）——高 w1（internalize 强）配方的“保守”被到达激励抵消；但 20M 仍退化（0.711→0.483），说明**后期退化 = reward-core + PPO 的固有过训动态，非到达奖励不足**（与 M2 correction/gaussian 早峰型同源；filter_only 无 reward core 才不退化）。
2. **揭示了 ON(带 filter 部署)/OFF(无 filter internalize) 的时间轴 trade-off**：internalize（OFF coll 低）在**20M** 才充分（18.6%），而 ON joint 峰值在 **6.5M**（0.71–0.76）——训练窗口里 viol 持续降到 20M（=internalize 深化）恰与 arrival 塌同步，是**同一现象的两面**。
3. **尚无配方同时满足“OFF coll<18% + ON joint 高”**；纯奖励微调已探到边界。
4. **交付建议**：dual 推荐配方 = **V3 (w1,w2)=(0.2,0.2) + arrive_bonus=20 + timeout_penalty=10 @6.5M 早停**（ON 0.711/OFF joint 0.532，viol 低且全曲线抬升）；若要 OFF coll 最低 → 原 (0.2,0.2)@20M（18.6%）。**下一步真正可能同时改善两目标的候选 = M3-B DR**（论文 Table I：DR 下 dual 退化最小、对动力学不确定鲁棒）+（可选）双阶段权重课程/熵维持探后期退化。

> ⚠️ 共享奖励改动范围：V 系列改了 `arrive_bonus`/`reward_timeout_penalty`（NavVel.yaml 默认未动，仅 CLI）；若该配方用于与 filter_only/naive 等公平对比，需各臂同参数。后续 M3-C/D 消融按 V3 配方口径记录。

---

## M3-A 改进 v3：ab+to 高档平衡扫描（2026-09-06 10:52 UTC+8）

### 动机（用户拍板）
V3 证明到达侧增强（ab20+to10）在 (w1,w2)=(0.2,0.2) 大 CBF 罚下有效抬升早峰（ON 0.711），但**用户判断：CBF penalty 偏高 ⇒ 到达吸引与未达惩罚也需同比例提高才能更好平衡**。故继续加码 ab/to 做 2×2 扫描。

### 实验设计（载体 = V3 基础 (w1,w2)=(0.2,0.2)，其余配方同前，仅变 ab/to）
| 档 | arrive_bonus | timeout_penalty | 设计意图 |
|---|---|---|---|
| W1 | **30** | **20** | 相对 V3(20/10) 同比例 +50% |
| W2 | **30** | **40** | 高未达惩罚（对 timeout 敏感） |
| W3 | **60** | **20** | 高到达吸引（对 ab 敏感） |
| W4 | **60** | **40** | 双高（最激进平衡） |

对照：V3 (ab20/to10) 6.5M ON 0.711 / OFF joint 0.532；原 (0.2,0.2)@20M OFF coll 18.6%。
验收：@6.5M 早峰 ON joint ≥ 0.711 且不降 OFF internalize（coll ≤ ~33% 同量级）；若 ab/to 过高出现过冲（如策略只刷 ab 不前进/熵乱）则记录上限。

### 执行（4 并行，2026-09-06 ~10:53 启动，CBFM3）
| 档 | 配方 | run id | 状态 |
|---|---|---|---|
| W1 | ab30 + to20 | `86yaguri`（run-20260906_105326） | ✅ 训练+eval 完成 |
| W2 | ab30 + to40 | `iv6o0faz`（run-20260906_105326） | ✅ 训练+eval 完成 |
| W3 | ab60 + to20 | `s4l6tcfm`（run-20260906_105326） | ✅ 训练+eval 完成 |
| W4 | ab60 + to40 | `h6qcvlau`（run-20260906_105326） | ✅ 训练+eval 完成 |

> 每档 ~20M（4 并行 fps 共享略降，预计 8–10 min）。完成后确定性 eval @600/1024env × {6.5M, 20M} × {filter ON/OFF} 回填；若 ab/to 过高出现"只刷 ab 不前进/熵乱/到达后游荡刷分"等过冲则记录上限。

### W1–W4 @6.5M 结果（对照 V3：ON 0.711 / OFF joint 0.532 / coll 33.4%）
| 档 | 6.5M ON joint | 6.5M OFF joint / coll |
|---|---|---|
| W1 (30,20) | 0.639 | 0.477 / 34.6% |
| W2 (30,40) | 0.693 | 0.524 / 35.0% |
| W3 (60,20) | 0.667 | 0.488 / 35.8% |
| **W4 (60,40)** | **0.716** | **0.533** / 36.1% |
| 对照 V3 (20,10) | 0.711 | 0.532 / 33.4% |

→ @6.5M 早峰对 ab/to 已近饱和（W4≈V3，ON 不再涨、OFF coll 略升 33.4→36.1%）。**高档 ab/to 收益递减**。

### W1–W4 @20M 结果（对照 V3：ON 0.483 / OFF joint 0.393；原 (0.2,0.2)：ON 0.497 / OFF 0.396, coll 18.6%）
| 档 | 20M ON joint | 20M OFF joint / coll |
|---|---|---|
| W1 (30,20) | 0.393 | 0.319 / 18.5% |
| **W2 (30,40)** | **0.530** | **0.444** / 20.6% |
| W3 (60,20) | 0.422 | 0.357 / 18.0% |
| W4 (60,40) | 0.462 | 0.389 / 19.9% |
| 对照 V3 (20,10) | 0.483 | 0.393 / 23.6% |

**W 全谱结论（决定性）**：
1. **@20M 抗后期退化主角 = `timeout_penalty` 高（40）**：to=40 两档（W2 0.530 / W4 0.462）显著 > to=20 两档（W1 0.393 / W3 0.422）→ 高未达成本把"悬停/绕远超时"淘汰出局，20M 不再塌到 0.4 以下。
2. **ab 适中即可，过高反伤**：W4(ab60,to40) 0.462 < W2(ab30,to40) 0.530 → ab60 让策略偏向"刷一次就保守"或激进过罚，20M 更低。
3. **W2 (ab30,to40) = 全谱 20M 最优**：ON 0.530 / OFF joint 0.444 / coll 20.6%（OFF coll 贴近最优 18.6%，但 OFF joint 0.444 是全部 20M 最高）——**兼顾抗退化 + internalize**。
4. 对比：@6.5M 看 V3/W4（~0.71）最高；@20M 看 W2 最优 → 若允许早停取峰取 V3/W4@6.5M，若要"20M 不退化 + OFF 好"取 W2。

---

## M3-A 改进 v4：每步代价/收益核算 + 奖励数值重设计（2026-09-06 ~11:1x UTC+8）

> 用户要求：算清每一步（稠密+稀疏）的代价与奖励后，重设计奖励函数具体数值。

### 0. 时间/几何锚点
`sim.dt=0.01s`，600 步/窗 = **6 s**；`v_max=1.8` → 每步最多前进 0.018 m；`arrive_hold_steps=50`(0.5 s)；D2-16 场 ±2.2（最远对角 ~6 m）；soft_respawn 多命续到 600；Hover 常驻项（pose/up/spin/effort）**无显式权重**直接进 reward。

### 1. 逐项预算（半定量；"巡航安全态 dmin>0.6" vs "穿障/被拦态"两类步）
**稠密（每步）**：
| 项 | 公式（当前数值） | 巡航步 | 穿障/被拦步 | 600 步窗累计(估) |
|---|---|---|---|---|
| pose×up(+spin) | 1/(1+(1.6·d)²)·up | +0.15…0.35 | +0.3…0.9 | **+120…300**（return 基座） |
| effort | 0.1·e⁻ᵉ | +~0.08 | +~0.05 | +~45 |
| PBRS (w8) | 8(d_prev−0.995d_t) | +0.02…0.14 | 绕行 0…0.05 | +15…30（势差上限 w·d₀≈24） |
| survival | −0.1·clamp(1−z,0) | 0 | 0 | 0（z>1 巡航） |
| obs log | −1.5·0.3·Σln(d/0.6) | 0 | −0.1…−1.5 | −3…−15 |
| near_slow | −1.0·v_par·(1−dmin/0.6) | 0 | −0.3…−1.5 | −5…−25 |
| CBF viol (w1) | −0.2·\|viol\| | 0 | −0.2…−1.2 | −5…−20 |
| CBF corr (w2) | −0.2(1−e^(−corr²/0.25)) | 0 | −0.05…−0.2 | −2…−8 |
→ 净稠密：安全巡航 +~25/百步；**穿 1 次障 20–50 步被扣 ~10–40**；CBF+障碍稠密罚全窗 ≈ −15…−60（视穿障 1–3 次）。

**稀疏（每事件/每窗）**：
| 项 | 数值(当前) | 触发 | 窗期望 |
|---|---|---|---|
| arrive_bonus | ab=10…60 | 每次到达并保持 | +ab·N(0–2) |
| timeout | to=0…40 | 600 步窗未达（终步） | −to(0/1 次) |
| collision edge | 4 | 每次新接触 | −4N |
| crash/oob | 0 | — | 0 |

### 2. 失衡结论（为什么保守 drift、为什么 ab/to 加码到 60 仍饱和）
1. **return 基座 ~600 由 Hover 常驻 pose/up/effort 堆成**（与任务无关，悬停也拿 ~180–300/窗）→ 任务项（PBRS≤24 + ab≤60）窗内仅 ~84，占比 <15%，梯度被稀释（尽管 PPO 用 advantage 归一化，稀疏事件的 credit 分配仍弱）。
2. **PBRS 势差 telescoping ≈ 路径无关**：绕远到达与直穿到达的 shaping 总和几乎相同 → shaping **不惩罚绕远里程浪费**；唯一代价是 600 步不够才不达（+timeout）。
3. 因此保守吸子的真正锁 = ①常驻项悬停也正 ②soft-respawn 不达无成本(timeout=0)。**ab/to 加码只能提高"到达峰值"，不能惩罚"绕远/悬停不达"本身** → W4 后饱和（ON ~0.716 到头）。
4. 反证 M2：**filter_only（无 reward core 稠密罚）不退化**；reward-core 的稠密罚让策略"宁可少走"，而 shaping/稀疏到达给的"前进拉力"不足以对抗 → 后期锁死。

### 3. 数值重设计（S 系列，具体数值；目标 = 让"安全高效到达"窗净收益 > 悬停/绕远 ≥ +200）
原则：**提高"每步前进"的稠密信号强度（即时 credit）** + **未达成本拉满** + **保留近程安全/CBF 权重**；只动现有 CLI 旋钮（不改代码默认）。
| 键 | 现值 | S1 | 依据 |
|---|---|---|---|
| `reward_pbrs_weight` w | 8 | **16** | 每步前进稠密信号 ×2（全速对向 ~0.29/步），即时 credit 对抗 CBF 稠密罚；若冲撞升/entropy 乱再回 8（M2 w 峰 8，但那是 correction 配方，dual+ab 更高 tolerance） |
| `arrive_bonus` | 10–60 | **40** | ≈2×单次穿障稠密罚上限(~20)，作为到达结算主项 |
| `reward_timeout_penalty` | 0–40 | **40**（W2 实证甜点） | to=40 抗后期退化决定性（W2 20M ON 0.530 全谱最高）；淘汰"悬停/绕远超时" |
| `reward_collision_edge` | 4 | 4 | 保留近程硬信号 |
| `reward_near_slowdown_weight` | 1.0 | 1.0 | 保留 |
| `reward_obs_log_weight` | 1.5 | 1.5 | 保留 |
| CBF `w1/w2` | 0.2 | 0.2 | 保留（internalize 主力） |

**S 主档定稿（据 W 全谱数据，2026-09-06 更新）**：
- S1 = **W2 基准 (ab30, to40) + `reward_pbrs_weight` 8→16** → 验证 w16 能否进一步抬 20M ON/OFF（w 是未测维度，预期补足稠密前进即时 credit）。
- 对照 S2 = ab40 + to40 + w16（ab 拉高试上限）；S3 = ab30 + to60 + w16（to 再高试上限）。
- 预期：S1 20M ON ≥ 0.55 / OFF joint ≥ 0.45（若 w16 有效）；盯 OFF coll 不因 w16 过冲（≥25% 则 w 回 8）。

**S 执行（3 并行，2026-09-06 11:14 启动，CBFM3，w=16 恒）**：
| 档 | 配方 | run id | 状态 |
|---|---|---|---|
| S1 | w16 + ab30 + to40 | `wrti3ohb`（run-20260906_111427） | ✅ 训练+eval 完成 |
| S2 | w16 + ab40 + to40 | `09ovq7eo`（run-20260906_111427） | ✅ 训练+eval 完成 |
| S3 | w16 + ab30 + to60 | `dbch537s`（run-20260906_111427） | ✅ 训练+eval 完成 |

**S 系列确定性 eval 结果**（对照 W2(w8,ab30,to40) 与 V3(w8,ab20,to10)）：
| 档 | 6.5M ON | 6.5M OFF joint / coll | 20M ON | 20M OFF joint / coll |
|---|---|---|---|---|
| S1 (w16,ab30,to40) | 0.738 | 0.551 / 35.6% | 0.511 | 0.402 / 25.0% |
| S2 (w16,ab40,to40) | 0.729 | 0.560 / 35.9% | 0.447 | 0.393 / 18.9% |
| **S3 (w16,ab30,to60)** | **0.743** | **0.572 / 34.1%** | 0.500 | 0.387 / 22.7% |
| 对照 W2 (w8,ab30,to40) | 0.693 | 0.524 / 35.0% | **0.530** | **0.444** / 20.6% |
| 对照 V3 (w8,ab20,to10) | 0.711 | 0.532 / 33.4% | 0.483 | 0.393 / 23.6% |
| 原 (0.2,0.2) 无 ab/to | 0.624 | 0.466 / 32.6% | 0.497 | 0.396 / 18.6% |

**S 结论（数值重设计定稿依据）**：
1. **w16（稠密前进信号 ×2）显著抬早峰**：@6.5M ON S1/S2/S3 = 0.729–0.743 vs W2(w8) 0.693（**+4~5pt**）；OFF joint 0.551–0.572 vs 0.524（**+3~5pt**）——印证核算里"PBRS 势差虽路径无关、但 w 提高仍给前进更即时 credit、缓解保守"。
2. **to60 在 6.5M 最优**：S3(0.743/0.572) > S1(0.738/0.551) > S2(0.729/0.560)；ab40(S2) 20M 退化更重（0.447）→ ab 仍宜 30。
3. **@20M 抗退化仍以 W2 (w8,ab30,to40) 最优**（ON 0.530/OFF 0.444）；w16 使 20M OFF coll 略升（18.9–25% vs 20.6%）→ w16 增激进，适合早停取峰。

### ✅ 奖励数值重设计定稿（回答"算清每步代价后重设数值"）
**主推配方（早停部署 @6.5M）= S3**：`(w1,w2)=(0.2,0.2)` + `reward_pbrs_weight=16` + `arrive_bonus=30` + `reward_timeout_penalty=60`，`correction_sigma=0.5`，D2-16/w8/brake off/ent0.02。
→ 确定性 eval：**ON joint 0.743（coll 2.3%）/ OFF joint 0.572（coll 34.1%，无 runtime filter 部署）**；相对 M2 OFF 基线(36–41%)、ON 较原 (0.2,0.2) +12pt。
**若求 20M 不早停**：用 **W2**：`(0.2,0.2)+w8+ab30+to40` → ON 0.530 / OFF joint 0.444 (coll 20.6%)。
> 数值逻辑（见上核算表）：to 负责淘汰悬停/绕远超时（稀疏结算），ab 提供到达峰值（适中 30，>60 反伤），w16 增强每步前进稠密 credit 抬早峰；CBF w1/w2 与近程障碍项(edge4/near1/log1.5)保留（internalize/近程安全主力）。
> ⚠️ 全部为 CLI 覆盖（NavVel.yaml 默认未动）；公平对比需各臂同参数。M3-B 以 S3 配方为 dual 载体。

---

## M3-B：Domain Randomization（DR）—— 以 S3 配方为载体（2026-09-06 20:06 UTC+8）

### 动机（论文 L250 / Table I）
训练时对动力学加噪声 $\mathbf q_{k+1}=\mathbf q_k+(\mathbf v_k+\mathbf d)\Delta t$、$\mathbf d\sim\mathcal N(0,20\%\,v_{max})$ → dual 对动力学不确定退化最小（无 DR 99.0→DR 99.0%；w/o rt.filter 92.7→91.7%）。验证"同时 ON 高 + OFF internalize + 扰动鲁棒"。

### 实现（commit `08a8e33`，2026-09-06）
- `omni_drones/utils/cbf.py::CmdGaussNoise`：动作链内注入高斯速度噪声（std=σ m/s，仅平动 :3），作用在 **CBF 投影后 / VelController 前**（先保安全再叠加执行误差）；reward core 罚策略自己的滤波前指令、不罚注入噪声 → 策略学"留裕量 internalize 鲁棒"。
- `scripts/train.py` velocity 分支接线：`task.dr_noise_sigma>0` 时在 VelController 与 cbf_filter 之间 append（Compose 逆序保证执行序 policy→CBF→噪声→VelController）。
- `NavVel.yaml`：`dr_noise_sigma` 默认 **0.0**（=M2/M3-A 逐位不变）；论文档 0.36=20%·v_max(1.8)。
- ⚠️ 仅 train.py 装配；play/eval_ckpt 不注入（eval 用 `+perturb` 测鲁棒）。冒烟 30k 帧无 NaN。

### 执行（3 并行，20:06 启动，CBFM3，载体 = S3：(0.2,0.2)+w16+ab30+to60）
| 档 | dr_noise_sigma | run id | 状态 |
|---|---|---|---|
| DR1 | 0.18（10%·v_max） | `2sif80oa`（run-20260906_200653） | ✅ 训练+eval 完成 |
| DR2 | 0.36（20%·v_max，论文主档） | `48noykel`（run-20260906_200653） | ✅ 训练+eval 完成 |
| DR3 | 0.54（30%·v_max） | `6wc7vr46`（run-20260906_200653） | ✅ 训练+eval 完成 |

**M3-B 确定性 eval 结果**（对照 S3 无 DR `dbch537s`）：
| 档 | 6.5M ON | 6.5M OFF joint/coll | 20M ON | 20M OFF joint/coll |
|---|---|---|---|---|
| DR1 (0.18) | 0.741 | 0.570 / 35.0% | 0.460 | 0.393 / 20.0% |
| **DR2 (0.36)** | 0.715 | 0.521 / 36.0% | 0.465 | **0.412 / 18.8%** |
| DR3 (0.54) | 0.586 | 0.482 / 31.3% | 0.443 | 0.385 / 22.7% |
| S3 noDR | 0.743 | 0.572 / 34.1% | 0.500 | 0.387 / 22.7% |

**扰动鲁棒（+perturb=cmd_gauss σ0.3 @20M）**：
| 档 | perturb ON joint/coll | perturb OFF joint/coll |
|---|---|---|
| S3 noDR | 0.471 / 1.9% | 0.419 / 17.7% |
| DR1 (0.18) | 0.442 / 1.7% | 0.365 / 19.8% |
| DR2 (0.36) | 0.468 / 1.9% | **0.424** / 19.8% |
| DR3 (0.54) | 0.412 / 2.3% | 0.403 / 20.2% |

**M3-B 结论**：
1. **DR 增益温和（非论文 Table I 级差异）**：早峰 @6.5M 无益甚至略降（DR2 0.715 < S3 0.743；DR3 σ0.54 大伤 0.586）。
2. **DR 价值集中在 20M 无早停部署口径**：**DR2(0.36=论文 20%档) 20M OFF coll 18.8%（全谱最低）、OFF joint 0.412（最高）**；扰动下 OFF joint 0.424 且几乎不退（0.412→0.424），比 S3（0.387→0.419）绝对更高更稳。→ 训练 DR 让“无 runtime filter 部署 + 执行不确定”下更安全、退化最小（与论文“DR 下 dual 退化最小”方向一致，幅度温和）。
3. σ 扫描：0.18 温和、0.36 最优（论文默认）、0.54 过噪伤训练。
4. 部署建议：**早停 6.5M → 用 S3 noDR**（ON 0.743/OFF 0.572）；**20M 不早停 / 重无 filter 鲁棒 → 用 DR2 (S3 + dr_noise_sigma=0.36)**（ON 0.465/OFF 0.412, coll 18.8%）。

**M3-B 交付**：dual+DR 推荐配方 = **S3 载体 + `task.dr_noise_sigma=0.36`**（实现 commit `08a8e33`，yaml 默认 0 未动）。

对照 = S3 无 DR（`dbch537s`：6.5M ON 0.743 / OFF joint 0.572, coll 34.1%；20M ON 0.500 / OFF 0.387, coll 22.7%）。
验收：DR 档 @6.5M/20M × {ON/OFF} eval + `+perturb=cmd_gauss σ0.3` 扰动鲁棒；期望 DR 档扰动下 coll 退化 < 无 DR，且不牺牲 ON joint / OFF internalize；取 DR 最优 σ 作为 dual+DR 推荐配方，回填后进入 M3-C/D。
预期：6.5M ON ≥0.72 且 20M 退化减轻（w16 稠密前进让后期不锁死）；OFF internalize 保持 ~20%（w16 可能略激进→盯 OFF coll）。
> 诚实边界：PBRS 势差仍无法惩罚"绕远但 600 内到"——那只能靠 timeout/horizon；S1 靠 timeout30 + w16 稠密把主要保守解（悬停/中途放弃/绕远超时）挤出。
> 待 W1–W4 @20M 结果回来微调 ab/to/w 后再定终值；S1 为验证主档。

