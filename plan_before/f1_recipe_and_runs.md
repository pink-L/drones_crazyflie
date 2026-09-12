# F1 配方速查 + 完整实验总表（new_reward 阶段）

> 创建：2026-09-06 23:1x。本文件是 **new_reward 阶段（根治「Hover 刷分」→ 重设计 reward）的速查/总表**，与 `new1_plan.md`（执行记录）、`new_reward.md`（方案文档）互补——前者随时间追加明细，本文件给「当前配方 + 全景时间线」。
> 仓库：`OmniDrones`（branch feat/crazyflie-pidrate）；wandb 项目 `new_reward`（entity fly-hust）；GPU RTX 5090 D 32GB；环境 `lz_env`。
> 依赖文档：上游 `new_reward.md`（navgoal/R1/F1 设计）、`new1_plan.md`（各批执行细节）、`m3_plan.md`（legacy/M2 基线背景）。

---

## 0. TL;DR（当前结论，2026-09-06 23:1x）

- **问题**：legacy reward（Hover 常驻正基座 pose+up+spin+effort + PBRS γ0.995）让模型刷 Hover 不前进（到达窗口 ~300 return 平台）。
- **解**：`reward_scheme: f1` = **无核飞行主导**（悬停=0，朝目标飞每步正，远端=近端同强）→ from-scratch 可学。
- **关键旋钮 `w_f`**：单调强加速（1.5→5% / 3→18% / 6→71% / 9→94% @0障10M）。
- **当前最佳 = F1 w_f=6.0 + curriculum [2,4,8,16]**：from-scratch 12M 通关 16 障，**D2-16 确定性 eval ON joint 0.930**（legacy 0.743，coll 0.9% vs 2.3%）。
- **遗留**：OFF（撤 filter）internalize 未达成（coll 41% vs legacy 34%）→ 三路 internalize 训练中（I1/I2/I3）。
> ⚠️ **23:1x 更新**：三路 internalize（dual0.3/0.5/+near3）**均未达成 OFF internalize**（OFF coll 40.9–44.2%）；主力续到 32M ON joint 0.920 ≈ 12M 的 0.930（平台）。**最终交付 = pg6q5ji5@12M + CBF filter ON（joint 0.930 / coll 0.9%）**。

---

## 1. 当前配方速查（F1 主力配方）

### 1.1 Reward 公式（`reward_scheme: f1`）

$$r_t=\underbrace{w_f\cdot\frac{\text{relu}(\mathbf v_t\cdot\hat{\mathbf u}_{goal})}{v_{max}}}_{①\text{ 飞行主导(无核, 悬停/远离=0)}}-\underbrace{w_s\lVert\Delta\mathbf a_t\rVert^2}_{④\text{ 平滑}}+\underbrace{[30+30(1-\tfrac{t_{arr}}{600})]\,\mathbb1[\text{arrive}]}_{③\text{ time-scaled 到达}}-\underbrace{40\,\mathbb1[\text{timeout}]}_{\text{600步未达}}+\underbrace{\text{⑥⑦}}_{\text{障碍+CBF dual}}$$

- $v_{max}=1.8$，$\mathbf v$=平动速度，$\mathbf u_{goal}$=指向目标单位向量（3D，不含 yaw）
- 悬停/静止/远离 → ①=0（**无刷分平台**）；正朝目标飞 → 每步按速度分量给正、**无距离衰减**
- 可选：时间成本 `reward_time_cost`(c_t) per-step（默认 0；强吸引子下才加成，密集障碍有害）

### 1.2 参数表（当前主力值）

| 键 | 值 | 角色 / 备注 |
|---|---|---|
| `task.reward_scheme` | `f1` | legacy \| navgoal \| r1 \| f1（默认 legacy 逐位不变）|
| `task.reward_fly_weight`(w_f) | **6.0** | ①权重 = 「起飞吸引力」；课程通关靠它（3 穿不动密集，6 通关，9 更快但需重标安全比）|
| `task.reward_action_smoothness_weight`(w_s) | 0.2 | ④ 动作差分罚；legacy/R1 用 1.0 压死探索 |
| `task.arrive_bonus` | 30 | 到达 flat |
| `task.arrive_time_bonus` | 30 | +30·(1−t_arr/600)，越快越多 |
| `task.reward_timeout_penalty` | 40 | 600 步未达一次性 |
| `task.reward_time_cost`(c_t) | 0（默认）| ② per-step 时间成本；密集障碍下有害，暂关 |
| `task.obstacle.num_scene` | 16 | 场景障碍数 M（max_slots K=8 滑动窗口）|
| `task.obstacle.spawn_xy_range` | [[-2.2,-2.2],[2.2,2.2]] | 球心采样（D2-16 口径，与 legacy 对比一致）|
| `task.obstacle.reward_collision_edge` | 4 | ⑥ 碰撞边沿一次性罚 |
| `task.obstacle.reward_near_slowdown_weight` | 1.0 | ⑥ 近障减速（internalize I3 探 3.0）|
| `task.cbf.mode` | hybrid | none \| filter_only \| reward_only \| hybrid |
| `task.cbf.penalty_src` | dual | nominal \| correction \| gaussian \| dual |
| `task.cbf.reward_weight` / `correction_weight` | 0.1 / 0.1 | ⑦ CBF dual 罚（internalize 探 0.3/0.5）|
| `task.cbf.correction_sigma` | 0.5 | |
| `task.cbf.use_brake_term` | false | |
| `algo.entropy_coef` | 0.05 | 防 PPO 熵塌缩（navgoal/R1 曾塌到 -6）|
| curriculum | `levels=[2,4,8,16]`, 成功≥0.8 且 coll≤0.05 进阶 | 主力训练用；确定性 eval 锁 16 障 |
| eval | @600 步 / 1024 env / runtime_filter ON/OFF | 与 legacy 同口径 |

### 1.3 代码 commit 记录（本阶段）
- `4ff5206` — reward_scheme legacy\|navgoal（navgoal 已否决，保留对照）
- `3f8f282` — reward_scheme r1（motion-gated 接近引导，已否决：核远端≈0 死区）
- `754c29a` — reward_scheme f1（无核飞行主导）
- `3941a1b` — f1 可选 per-step 时间成本 reward_time_cost（默认 0）

### 1.4 形状坑（改 reward/stats 必读）
- torchrl env 的 stats/reward 是 2D `(N,1)`；对 3D `(N,1,K)`（rpos/drone_state/policy_action）reduce 必须 `keepdim=False` 得 2D
- 用 2D 量除/乘 3D 量，或 keepdim 保留 3D，都会灾难广播 `(N,N,1)` 崩在 `stats["return"] += reward`
- 单位向量用 `rpos / rpos.norm(dim=-1, keepdim=True).clamp_min(1e-6)`（N,1,1 除数），`sum(dim=-1)` 不带 keepdim

### 1.5 并行启动坑（bash）
- `cd X && (A) & (B)`：`&` 把 `cd X && (A)` 整体后台化 → B 在错目录 `train.py not found`
- `A && (B) & (C)`：同理 C 无 conda 激活 → `hydra not found`
- **并行必须每个 run 一个独立前台终端**，命令内 `source ~/.bashrc && conda activate lz_env && cd <abs>/scripts && python ...`

---

## 2. 完整实验时间线（wandb `new_reward`，2026-09-06）

> 列：时间(约) / run id / 配方 / 帧 / 结果(eval arrival 或关键指标) / 结论。
> 全程口径：0 障/2 障/课程均 from-scratch（除标注 warm）；确定性 eval 另注明。

### 阶段 A：navgoal（论文式纯 motion）—— ❌ 否决
| 时间 | run | 配方 | 结果 | 结论 |
|---|---|---|---|---|
| ~20:5x | `aea0kdlc` | navgoal w8, 2障, 10M | arrival≈0, pos_error 恒 3.4, 熵塌 -4.6 | from-scratch 零学习 |
| ~21:05 | `w52wuwj9` | navgoal w24, 0障, 10M | arrival≈0, 熵塌 -6.0 | 提高 w 无效 |
| 21:06-21:1x | `qeorposc`/`re9dbg3i` | warm S3→navgoal ent0.05/0.10, D2-16 | ON joint 0.681/0.612 < legacy 0.743 | warm 无净增益 → **navgoal 否决** |

### 阶段 B：R1（motion-gated 接近引导，带核）—— ❌ 否决
| 时间 | run | 配方 | 结果 | 结论 |
|---|---|---|---|---|
| 21:28 | `0uudesls` | r1（appro 修复前）| 崩溃空 | 修复形状坑 |
| 21:30-33 | `ht30t6tm` | r1 wg15 k1.6, 0障, 10M | arrival 0, pos_error 恒3.6, 熵 -6.07 | from-scratch 死锁（核远端≈0）→ **R1 否决** |

### 阶段 C：F1（无核飞行主导）—— ✅ 可学 → 最强
| 时间 | run | 配方 | eval arrival(0障) | 结论 |
|---|---|---|---|---|
| 21:42-45 | `emy1u3ow` | f1 w_f=1.5, 0障, 10M | **5.3%**（pos_error 2.40）| 首个 from-scratch 可学 |
| 21:47-53 | `gbnax8a7` | f1 w_f=1.5 延 30M | 49.7%（pos_error 0.65）| 10M 平台只是早段 |
| 21:50-53 | `1m2npshx` | f1 w_f=1.5+c0.1, 10M | 5.0% | 弱吸引子下②无益 |
| 21:54-57 | `ngycl4pc` | f1 **w_f=3.0**, 10M | **18.4%**（pos_error 0.62）| w_f 是加速旋钮 |
| 21:55-58 | `4heskptf` | f1 到达 60/60, 10M | 2.6% | 大稀疏 bonus 更差 |
| 22:10-1x | `dkbtuzj2` | f1 w_f=3.0 延 30M | 48.2% | w_f 主要加速前期非提上限 |
| 22:11 | `0tjlxy7c` | f1 **w_f=6.0**, 10M | **71.4%**（pos_error 0.40, success 1.0）| 单调加速验证 |
| 22:11 | `4fjm3il8` | f1 w_f=3.0+c0.1, 10M | **56.9%** | ②在强吸引子上加成显著 |
| 22:18 | `2d8ym5yt` | f1 w_f=6.0 延 30M | 64.4% | <10M 的 71%，长训不如高 w_f |
| 22:19 | `12hf3149` | f1 **w_f=9.0**, 10M | **93.9%**（pos_error 0.33）| w_f 单调到 9 仍涨，0障一次学会 |
| 22:19 | `s2xprexh` | f1 w_f=3.0, **2障**, 10M | **80.4% / 0 collision** | 有障碍可学且安全 |

### 阶段 D：课程 2→4→8→16（四变体）—— 通关
| 时间 | run | 配方(12M, curriculum [2,4,8,16]) | 进阶到 | eval arrival / collision | 结论 |
|---|---|---|---|---|---|
| 22:28 | `abtuaqix` | w_f=3.0 | **2**(卡) | 78.0% / 0.49% | 弱吸引子穿不动密集 |
| 22:29 | `pg6q5ji5` | **w_f=6.0** | **16** ✅ | **90.6% / 1.27%** | **通关配方** |
| 22:29 | `p0fza06w` | w_f=3.0+c0.1 | 4(卡) | 75.3% / 0.39% | ②救不了弱吸引子 |
| 22:29 | `lreeuqw5` | w_f=6.0+c0.1 | 16 | 67.8% / 1.46% (CBF干预0.15) | 密集下②有害 |

### 阶段 E：D2-16 确定性 eval（pg6q5ji5 @600/1024）
| 口径 | arrival | collision_ep | joint | vs legacy S3@6.5M |
|---|---|---|---|---|
| **ON**（filter 在） | 0.936 | 0.9% | **0.930** | ≫ legacy 0.743（coll 2.3%）✅ |
| **OFF**（filter 去） | 0.942 | 41.0% | 0.588 | ≈ legacy 0.572；OFF coll 未 internalize ❌ |

### 阶段 F（23:0x–23:1x，完成）
| run | 基座 | 配方 | 结果 | 判定 |
|---|---|---|---|---|
| `c6yxszpb` 主力 ext20M | warm pg6q5ji5 | wf6 锁16 +20M | ON joint 0.920（arr 0.924, coll 0.8%）| ≈ 12M 0.930 → 平台，长训不增 |
| I1 `l8lsd5rd` | warm pg6q5ji5 | dual0.3 +10M | OFF coll 43.0% / OFF joint 0.558 | ❌ 未 internalize |
| I2 `h8qz5hb6` | warm pg6q5ji5 | dual0.5 +10M | OFF coll 44.2% / OFF joint 0.555 | ❌ 未 internalize |
| I3 `cc7liz0x` | warm pg6q5ji5 | dual0.3+near3 +10M | OFF coll 40.9% / OFF joint 0.590 | ❌ 微降仍 ≫ 34.1% |

**最终交付模型 = `pg6q5ji5`@12M（F1 w_f=6.0 + curriculum[2,4,8,16]）+ CBF filter ON**：D2-16 ON joint **0.930**（arr 0.936 / coll 0.9%）。internalize（OFF）未达成（依赖运行时 filter，同 legacy/M3；如需可作独立后续）。
> ⚠️ **23:2x 更新（internalize 新机制 T1-T4 全试）**：T1 corr6(过度保守崩 arrival) / T2 reward_only无滤波(唯一 OFF coll 30.7%<34.1% 但 arr 0.73) / T3 margin & T4 combo(ON viol 压到 0.008–0.023 但 OFF 仍 ~40%)。**7 组 internalize 均未在保持高到达下达成 OFF 安全** → 交付口径 = 带 filter（ON joint 0.93）；OFF 安全需代码级新手段（filter 介入量入 obs / margin 课程），非 reward-shaping 可及。

### 阶段 H：D2-8 OFF 密度对照（2026-09-06 23:4x，eval 障碍 16→8，判 internalize 是否被密度掩盖）
| 模型 | D2-16 OFF arr/coll/joint | **D2-8 OFF** arr/coll/joint | 判定 |
|---|---|---|---|
| 基座 `pg6q5ji5` | 0.942 / 41.0% / 0.588 | **0.979 / 21.5% / 0.784** | 降密到 8 障 OFF coll 41→21.5%（≈M2-era 8障 OFF 19–23% 地板）|
| I3 `cc7liz0x` | 0.920 / 40.9% / 0.590 | 0.930 / 22.9% / 0.748 | ≈ 基座同密度，无 internalize 增益 |
| T2 `c3ga7ko2` | 0.73 / 30.7% / 0.589 | 0.598 / **19.5%** / 0.516 | coll 最低但 arrival 崩(0.60) |
| T3 `5f8ik6rs` | 0.91 / 39.9% / 0.592 | 0.866 / 23.6% / 0.697 | ≥ 基座 coll，无增益 |
| T4 `h9ge2cl3` | ~0.78 / 41.1% / 0.574 | 0.767 / 24.4% / 0.617 | ≥ 基座 coll，无增益 |
- **判定：internalize 未因密度下降而显现 ❌**——8 障下所有臂 OFF coll 都落到 ~20–24%（≈M2-era 8 障 OFF 地板 19–23%，纯障碍变少的统计效应），且 internalize 组(I3/T3/T4) **coll ≥ 基座**（22.9/23.6/24.4 vs 21.5%），无一组分离出优势；仅 T2(无滤波真碰撞训练) coll 略低(19.5%)但 arrival 毁。→ **低密度只是让一切变好，不是 internalize 出现**；reward-shaping 手段在 8 障与 16 障同样失败。下一步 = obs 结构级改造（filter 介入量/最小净空入 obs），非调密度可解。|

---

## 3. 里程碑 / 判定速览

| # | 节点 | 判定 |
|---|---|---|
| M1 | Crazyflie Lee 控制器增益修复（本阶段之前的根因，commit `...m1` + tag `m1-achieved`）| 0障 arrival 99% |
| — | navgoal（删 pose 纯 motion）| ❌ from-scratch 死锁 + warm 无增益 |
| — | R1（motion-gated + 接近势核 k=1.6）| ❌ 核远端≈0 → from-scratch 死锁 |
| **F1** | 无核飞行主导 w_f·relu(v·u_goal) | ✅ 可学；w_f=9 0障 94%@10M |
| **D2-16** | F1 w_f=6 + curriculum [2,4,8,16]（pg6q5ji5）| ✅ ON joint 0.930（legacy 0.743）|
| 遗留 | OFF internalize | ⏳ I1/I2/I3 训练中（判据 OFF coll < legacy 34.1%）|

---

## 4. 下一步（运行中批次完成后）

1. I1/I2/I3 各跑 **OFF deterministic eval**（runtime_filter=false @600/1024 D2-16）：看 OFF coll 是否 < 34.1% 且 OFF joint 不塌（internalize 成功 = 撤 filter 也安全）。
2. 主力 ~32M 后跑完整 ON/OFF + T_arr / timeout / mean_action_diff 报告（用户 4 目标：到达/时间短/平滑/安全低碰）。
3. 定稿主力配方 → 同步更新 `new1_plan.md`/`new_reward.md`/本文件 + repo memory；git tag（如 `f1-d2e16-achieved`）。

---

# ===== 2026-09-07 F1 四臂公平对比（dual/filter_only/reward_only/naive, obs_safety=none）=====
> 用户拍板：基于**当前 F1 reward 设计**补齐四臂机制对比；obs_safety=none(62维, obs 与 cbf.mode 解耦 → naive 也能公平带 filter eval)；dual 复用 pg6q5ji5(final,62)；后三臂无模型 → 并行 from-scratch 训练；reward_only 保持同配方、若卡密度如实记录；**暂不引入 DR**；eval 分 8obs/16obs。
- 四臂同配方 = pg6q5ji5 全配置（num_scene=16、spawn ±2.2、edge4、near1、curriculum [2,4,8,16] from-scratch、wf6、arrive 30+30t、to40、smooth0.2、penalty_src=dual w1=0.1 w2=0.1 σ0.5、brake-off、ent0.05、12M、save_interval=100、render_eval=false），**仅 cbf.mode 不同**：
  - dual(hybrid) = **pg6q5ji5 final**（既有，ON joint 0.930/0.9%; OFF 0.588/41.0% @16）
  - filter_only = run `scvypn2v`（训练中, log /tmp/navvel_f1_4arm_filterOnly.log）
  - reward_only = run `clqz6lyn`（训练中, log /tmp/navvel_f1_4arm_rewardOnly.log）
  - naive(none) = run (待 id)（训练中, log /tmp/navvel_f1_4arm_naive.log）
- 注：filter_only reward core off(配方 penalty 键自然无效)、naive 无 CBF、reward_only dual→退化为仅 w1·viol(0.1)。同 CLI 公平。
- eval 协议（待三臂跑完）：四臂 × {ON=cbf.mode=hybrid+runtime_filter=true, OFF=runtime_filter=false} × {8obs=num_scene8/levels[8], 16obs=num_scene16/levels[16]} @rollout600/1024; obs_safety 不设(62)。


### F1 四臂 eval 结果（确定性 @rollout600/1024, obs 62, 2026-09-07；ON=cbf.mode=hybrid 带 filter 部署, OFF=runtime_filter=false）
训练轨迹：dual/filter_only 通关 2→4→8→16；reward_only(clqz6lyn)/naive(rlf9l0bn) **卡 2 障**(12M from-scratch 无滤波学不动高密度)。
| 密度 | 臂 | ON arr/coll/joint | OFF arr/coll/joint |
|---|---|---|---|
| 8obs | **dual**(pg6q5ji5) | 0.983/0.3%/**0.981** | 0.974/21.4%/0.786 |
| 8obs | filter_only(scvypn2v) | 0.981/0.5%/0.978 | 0.964/24.7%/0.752 |
| 8obs | reward_only | 0.941/0.5%/0.939 | 0.955/23.9%/0.757 |
| 8obs | naive | 0.916/0.2%/0.914 | 0.964/23.9%/0.760 |
| 16obs | **dual** | 0.931/0.9%/**0.927** | 0.942/**39.5%**/0.604 |
| 16obs | filter_only | 0.938/1.0%/0.929 | 0.909/45.2%/0.544 |
| 16obs | reward_only | 0.876/1.3%/0.870 | 0.889/46.5%/0.529 |
| 16obs | naive | 0.800/2.0%/0.784 | 0.906/46.7%/0.531 |
- **结论**：①**部署口径(ON)**：8obs 四臂 ~0.91-0.98（filter 决定性, 甚至把训练只到 2 障的 ro/naive 策略救到 0.94/0.91）；16obs dual≈fo≈0.93 > ro 0.87 > naive 0.78（ro 的 w1·viol 让策略更自保 → 优于 naive）。②**OFF(撤 filter)**：dual 一致最佳（16obs joint 0.604/coll 39.5% 最低），fo 撤 filter 崩更狠(0.544/45.2%, 无 reward core → 纯靠 filter 兜底没内化), ro/naive ~0.53(46-47%)。→ **runtime filter 仍决定性；dual 的 reward core 让其 OFF 相对最稳，但 internalize(OFF coll<34.1%)仍未达**。③reward_only/naive 12M from-scratch 课程无法升密度=本身结论。


### F1 四臂 严格单命口径 eval（soft_respawn=false = 坠毁/出界/碰撞超限即 terminated 不复活, 2026-09-07）
> 用户验收口径：「一次飞行失败即失败」。eval 命令只需加 `task.soft_respawn=false`（环境侧无需改代码；配合 eval auto_reset=False = 单命窗口）。
| 密度 | 臂 | ON arr/coll/joint(单命) | OFF arr/coll/joint(单命) |
|---|---|---|---|
| 8obs | dual | 0.974/0.3%/0.971 | 0.951/18.1%/0.787 |
| 8obs | fo | 0.986/0.6%/**0.980** | 0.958/19.8%/0.771 |
| 8obs | ro | 0.951/0.3%/0.949 | 0.942/19.1%/0.764 |
| 8obs | naive | 0.920/0.3%/0.917 | 0.954/21.0%/0.755 |
| 16obs | **dual** | 0.947/0.4%/**0.944** | 0.911/33.2%/0.616 |
| 16obs | fo | 0.939/1.0%/0.932 | 0.914/31.4%/**0.626** |
| 16obs | ro | 0.885/1.1%/0.880 | 0.891/37.2%/0.565 |
| 16obs | naive | 0.835/1.6%/0.820 | 0.908/28.7%/0.641 |
- 结论：①**ON 单命**：dual/fo @16 ~0.93-0.94 最佳(dual 0.944 > fo 0.932 略, 噪声内≈打平; 8obs fo 0.980 最高), ro 0.880, naive 0.820(未训过16)。filter 把碰撞压到 <2%, 故单命 ON ≈ 多命 ON(多命反而因复活多撞略降)。②**OFF 单命**：fo/dual ~0.62-0.63 最佳, ro 0.565, naive 0.641(数字低意义: 未训密度+单命)。→ **严格口径下 internalize 依旧不成立(OFF 单命 joint 0.56-0.64 远低 ON 0.93+), runtime filter 决定性确认**。③ro/naive 未训到 16 密度, 其 16obs 数字仅参考。


### ⭐ 标准 eval 模板（默认严格单命口径, 固化 2026-09-07）
> eval_ckpt.py 顶部注释已固化该模板。验收评估一律 `task.soft_respawn=false`（一次飞行失败即失败）；
> 窗口多命(soft_respawn 默认 true)只在需要与训练同构口径时才用并须标注。指标 arr/coll/joint 语义见 eval_ckpt.py 注释。
```bash
# 验收 ON（带 CBF filter 部署）@16obs
cd /home/lz/lzspace/drones/OmniDrones/scripts && conda activate lz_env
python eval_ckpt.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
  task.soft_respawn=false task.reward_scheme=f1 task.reward_fly_weight=6.0 \
  task.arrive_bonus=30 task.arrive_time_bonus=30 task.reward_timeout_penalty=40 \
  task.reward_action_smoothness_weight=0.2 \
  task.obstacle.num_scene=16 'task.obstacle.spawn_xy_range=[[-2.2,-2.2],[2.2,2.2]]' \
  'task.curriculum.levels=[16]' task.curriculum.enabled=false \
  task.obstacle.reward_collision_edge=4 task.obstacle.reward_near_slowdown_weight=1.0 \
  task.cbf.mode=hybrid task.cbf.use_brake_term=false task.cbf.penalty_src=dual \
  task.cbf.reward_weight=0.1 task.cbf.correction_weight=0.1 task.cbf.correction_sigma=0.5 \
  +checkpoint=<ckpt> +rollout_steps=600 +runtime_filter=true
# OFF(撤 filter, internalize 判据): 换 +runtime_filter=false
# 8obs: 换 num_scene=8 + levels=[8]; obs_safety 须与训练一致(无则不加)
```
