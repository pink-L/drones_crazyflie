# New1 规划：reward 重设计落地（reward_scheme: legacy|navgoal|r1）—— 根治「Hover 刷分」

> 创建：2026-09-06。**本文件 = 本阶段项目汇报总结文档**（延续 m1/m2/m3_plan 惯例，动手后回填文末「执行记录」）。
> wandb：项目 **`new_reward`**（2026-09-06 由用户新建，替换原 `CBFM3`；本阶段所有 run 均进 `new_reward`）。
> 仓库：`/home/lz/lzspace/drones/OmniDrones`；环境 `conda activate lz_env`，命令在 `OmniDrones/scripts/`。
> 上游方案文档：`drones/new_reward.md`（含 ★定案 + §R1 现行主方案）；输入：CBF-RL 论文 md、m3_plan.md、navvel_rl_interface.md §3。

---

## ⭐ 阶段性总结（2026-09-06 收官 · New1 完结 → 交接 New2）

**一句话**：New1 完成「F1 全新 reward 从零重训」，实现 **带 CBF filter 部署下 D2-16 ON joint 0.930（coll 0.9%）≫ legacy 0.743**；但 **internalize（撤 filter 也安全）经 3+4+1 组手段全失败**——reward-shaping 已探到极限，OFF 安全需 obs 结构级改造（加 CBF 边界余量 h / min_clearance 入 obs），已移交 **`drones/new2_plan.md`**（新 agent 从那里接手）。

### 时间线（2026-09-06 19:00–23:5x，单日）
| 阶段 | 时间 | 内容 | 结论 |
|---|---|---|---|
| 方案否决 | 19:0x–21:3x | navgoal（删 pose 纯 motion）/ R1（motion-gated 接近势核 k=1.6）from-scratch 探针 | ❌ 双死锁（远端引导≈0 + 悬停无持续代价 → PPO 学静止、熵塌 −6）|
| **F1 定稿** | 21:42–22:2x | 无核飞行主导 `w_f·relu(v·u_goal)/vmax`，w_s=0.2, ent0.05（无时间成本②先行）| ✅ 首个可学；w_f 单调加速：1.5→5% / 3→18% / 6→71% / 9→94% |
| 课程通关 | 22:28–22:4x | **F1 w_f=6.0 + curriculum [2,4,8,16]**，12M from-scratch | ✅ `pg6q5ji5` 到 16 障（arr 90.6% / coll 1.27%）|
| D2-16 确定性 eval | 22:5x | `pg6q5ji5` @600/1024，runtime filter ON/OFF | ✅ **ON joint 0.930（arr 0.936 / coll 0.9%）达标**；❌ OFF coll 41% 未 internalize |
| internalize 尝试 | 23:0x–23:2x | 主力续训(32M 平台) + I1/I2/I3（dual 0.3/0.5/near3）+ T1-T4（corr6 / reward_only / margin / combo）| ❌ 7 组全失败；仅 T2（无滤波真碰撞训练）OFF coll 30.7% 但 arrival 降 0.73 |
| D2-8 密度对照 | 23:4x | eval 障碍 16→8，5 模型 OFF 对照 | ❌ 8 障 OFF coll ~20–24% = M2-era 8 障 OFF 地板（19–23%）；internalize 组无一组分离 → 密度实验线关闭 |

### 交付物
- **配方**：F1 `w_f=6.0, w_s=0.2, ent0.05, arrive 30+30t, to40, edge4/near1, CBF hybrid dual 0.1σ0.5, curriculum [2,4,8,16]`
- **交付模型** = `pg6q5ji5`@12M（git tag `f1-d2e16-achieved`），部署口径 = 策略 + CBF runtime filter ON（D2-16 joint 0.930 / coll 0.9%）
- **配方/run 总表**：`drones/f1_recipe_and_runs.md`；仓库记忆 `/memories/repo/omnidrones-navvel-m2.md`

### 关键机制结论（写进 new2_plan，新 agent 必读）
1. **reward-core 全变体是早峰型**（~6.5M 峰后过训退化）→ 部署取 mid-ckpt，勿盲加帧。
2. **per-step 修正罚被 600 步开敞飞行 EMA 稀释**；filter 介入发生在穿障尾段（已太晚），纯 reward 无法提供「介入前前瞻信号」——这是 internalize 失败的根因。
3. **大系数必然保守塌陷**（w2≥6 或 dual≥0.3 → arrival 崩）：四旋翼动力学滞后 ⇒ 不存在「贴 CBF 边界高速飞且 filter 零介入」的解；论文 single-integrator 有。
4. **obs 绝不能加「filter 介入量」**：internalize 部署撤 filter ⇒ 该通道恒 0 ⇒ 训练/部署分布偏移自相矛盾；应加 **CBF 边界余量 `h = min(‖p−p_oi‖ − r_i^cbf)`**（首选：纯几何、训练/部署同源、直接告诉策略 filter 触发边界）或 **min_clearance**（保守版）。详见 new2_plan.md 设计。

---

## 0. TL;DR（一句话）

**M3-B DR 阶段模型被放弃**；本阶段落地 **`reward_scheme: legacy|navgoal`**（默认 `legacy` 逐位不变）把 reward 改为论文式 motion-based（progress γ=1 + action-diff 平滑 + time-scaled 到达 + timeout 40 + CBF dual），但 **from-scratch 死锁 + warm 无增益 → navgoal 否决**。
> ⚠️ **2026-09-06 更新**：现主方案 = **R1（`reward_scheme: r1`，motion-gated 接近引导，见 new_reward.md §R1）**——保留「靠近就正」稠密引导但悬停=0。0 障 from-scratch 探针进行中。
> ⚠️⚠️ **2026-09-06 22:00 再更新**：R1 0 障 from-scratch 10M 也死锁（见下执行记录，接近势核远端≈0）→ 按用户反馈（"起飞吸引力不够，重新设计 reward"）重设计 **F1（`reward_scheme: f1`，无核飞行主导 + 可选时间成本，new_reward.md §F1）**。**F1 纯① 0 障 from-scratch 10M 首个可学**（arrival 5.3%、pos_error 3.75→2.49、熵 -1.6 不塌）——证实"核远端死区"是元凶；但 10M 到达完成度仍低，续跑/加时间成本候选待定。

## 1. ★ 已定案决策（用户 2026-09-06 确认，详见 new_reward.md §7）
| 决策 | 定案 |
|---|---|
| 到达结算 ④ | **time-scaled**：30 + 30·(1−t_arr/600)，需加 `first_arrival_step` stat |
| `success_terminate` | **false（保持）**，多命/课程口径不变 |
| 训练起点 | **from-scratch 低密度探针（2 障 5–10M）→ 升密度** |
| 平滑 ② | **速度指令层 action-diff 负项** −w_s·‖a_t−a_{t-1}‖² |
| 姿态/能耗 | **全删**（up/spin/effort 不设项） |

## 2. 里程碑与验收
| # | 内容 | 验收 |
|---|---|---|
| NR-1-impl | `reward_scheme` 并存实现（默认 legacy 不变）+ navgoal 分支（删 pose/up/spin/effort + ①②④⑦ + action-diff 平滑 + time-scaled 到达 + stat） | cbf_test CPU 全 PASS + GPU 冒烟无 NaN |
| NR-1-probe | from-scratch 低密度（2 障）收敛探针 5–10M（wandb `new_reward`） | arrival 可学、`time_to_arrive` 下探、无悬停平台、熵健康 |
| NR-1-main | 升密度主训 + §4.4 小网格 | ON arrival/joint≥0.75；OFF coll 显著 < M2 基线 36–41% |
| **R1-impl** | `reward_scheme: r1` 实现（motion-gated 接近引导主项 + time-scaled 到达 + smooth + ⑥⑦ 复用） | cbf_test CPU PASS + GPU 冒烟无 NaN/形状错 |
| **R1-probe** | 0 障 from-scratch 10M（w_g=15, ent0.02）验证可学性 | arrival 爬升、pos_error 下探、**无悬停**（对比 navgoal 死锁）→ 通过后升密度对照 legacy |

## 3. 实现口径（new_reward.md §6）
- #1 `reward_scheme: legacy|navgoal`（默认 legacy）→ nav_vel.py cfg 解析
- #2 navgoal 分支重写 `_compute_reward_and_done` 主项（删 pose/up/spin/effort(正)，加 ①②④⑦；⑥⑨ 逻辑复用）
- #3 平滑 = `-w_s·‖a_t−a_{t-1}‖²`（速度指令层，policy/prev action）
- #4 首达步 `first_arrival_step`（progress_buf）+ time-scaled bonus
- #5 `pbrs_gamma=1.0`（navgoal 内默认；纯差分悬停=0）
- #6 新 stat：`first_arrival_step`、`mean_action_diff`
- 权重新默认（navgoal）：pbrs w=8 / γ=1.0；smooth w_s=1.0；arr 30+time30；to 40；edge 4；near 1.0；log 1.5·0.3；CBF dual w1=w2=0.1 σ0.5（起点，再标定）；crash/oob/early/survival 0

---

## 执行记录（回填用）

### NR-1 实现（2026-09-06，§6 #1–#6）
| 时间 | 事项 | 产物 / run |
|---|---|---|
| 20:4x | **实现 `reward_scheme: legacy\|navgoal`**（默认 legacy 逐位不变）：cfg 解析 `reward_scheme`/`arrive_time_bonus`；`_set_specs` 仅 navgoal 追加 `first_arrival_step`/`mean_action_diff` stat（legacy stats_spec 不变）；`_pre_sim_step` 缓存 `prev_policy_actions`；`_compute_reward_and_done` 主 reward 分支——navgoal = progress(γ 由 CLI)+time-scaled arrival+action-diff 平滑（policy_action 滤波前指令），删 pose/up/spin/effort 正基座；⑥⑦ 障碍/CBF 复用；NavVel.yaml 注释与 `reward_scheme: legacy` 默认 | 改动 nav_vel.py + NavVel.yaml |
| 20:4x | CPU 回归 `cbf_test.py` 全 PASS；get_errors 无错 | — |
| 20:4x | **GPU 冒烟 3 轮**：第1/2 轮发现 `adiff` 3D `(N,1,1)` 与 2D `(N,1)` stats 广播崩 `(N,N,1)` → 修 `norm(dim=-1)`（去 keepdim）得 `(N,1)`；第3轮 navgoal 30k 帧干净完成（Final Eval+ckpt）；另跑 legacy 默认回归 8k 帧干净 | /tmp/navvel_navgoal_smoke3.log、legacy_smoke.log |
| 20:48 | **收敛探针启动**：from-scratch、2 障锁级、navgoal w8γ1.0+s1.0+ab30+t30+to40+edge4+near1、hybrid/dual w1=w2=0.1 σ0.5、ent0.02、10M、save_interval=100 | wandb **`new_reward`** run **`aea0kdlc`**（URL https://wandb.ai/fly-hust/new_reward/runs/aea0kdlc）；日志 /tmp/navvel_nr1_probe_2obs.log |

> ⚠️ 冒烟踩坑记录：torchrl/TensorDict stats 是 2D `(N,1)`（非 per-env 额外 agent 维），凡对 3D `(N,1,K)` 量做 `norm(dim=-1, keepdim=True)` 会得 `(N,1,1)` 并与其相加产生灾难广播 `(N,N,1)`；reward 层所有量必须保持 2D `(N,1)`。

### NR-1 探针结果（10M 完成，run `aea0kdlc`，2026-09-06 20:51）

**训练统计**（wandb new_reward/aea0kdlc）：
| 指标 | ~3M | ~6.6M | ~10M(final) | 判读 |
|---|---|---|---|---|
| train/stats.return | -19.6 | -19.1 | -15.6 | 大多数窗 ≈ 悬停 −40（timeout）+ 个别到达 +60 |
| episode_len | 599 | 599 | 599 | 恒 600 窗 → 几乎无成功终止 |
| pos_error | 3.465 | 3.404 | 3.453 | 恒 ≈ 初始距离 → **几乎未向目标移动** |
| vel_norm | 0.179 | 0.183 | 0.170 | 极低（v_max 1.8）→ **策略输出≈静止/悬停** |
| arrival / success_rate | 0.29% | 0.49% | 0.29% | ≈0（个别随机到达） |
| entropy | -4.31 | -4.57 | -4.60 | **确定性塌缩**（TanhNormal 差分熵 <0 = 近确定性） |
| mean_action_diff | 0.21 | 0.20 | 0.20 | 动作变化小（与静止一致） |
| cbf_violation | 0.0017 | 0.0011 | 0.002 | CBF 几乎不激活（没飞近障碍） |

**结论：收敛探针失败（from-scratch 10M 零学习）**——navgoal 把「悬停刷分平台」删了（悬停窗 return −40，目标达成 ✓），但代价是新 reward 下 **from-scratch 学不动**：策略塌缩到「确定性输出≈0 悬停」局部陷阱，arrival≈0。

**机制诊断（为什么没学会飞向目标）**：
1. **稀疏 + 弱稠密引导**：navgoal 只靠 progress（w8 ⇒ 每步全速 credit ≈0.14）+ 稀疏到达（30–60）+ timeout(−40)。四旋翼有底层控制/惯量延迟、d0≈3.4m 需 ~240 步连续精准直飞才到 → from-scratch 随机探索几乎触发不到「到达」稀疏正（M1/M2 靠 legacy `pose` 径向势——越近越大，把「靠近」逐步稠密化才学得动）。
2. **熵塌缩到静止**：负回报主导下 PPO 找到「确定性输出 0 = 悬停 −40」这一比乱飞更优的平凡解，且从零探索极稀 → 困死。
3. 对照：legacy 的 `pose` 正是「靠近就正」的引导，把策略从静止陷阱拉向目标（代价 = 悬停也刷分）；navgoal 删除后需要**替代性稠密引导**（更强的运动 progress + 更高熵/探索 + 足够长/分阶段），而非只剩稀疏到达。

**下一步候选（待用户拍板）**：
- **Opt-A（推荐先试）**：强化运动稠密引导——progress `reward_pbrs_weight` 8→**24~32**（每步 credit ~0.43–0.58，直飞势和 ≈ w·d0 达 ~80–110 ≫ timeout 40，使「飞向目标」明显优于「悬停」）；可同步 `entropy_coef` 0.02→0.03 防过早塌缩；from-scratch 10–20M 复测。
- **Opt-B（分阶段）**：navgoal 先 **0 障** from-scratch 学到「到达」（无障碍最易，M1 路径），再开 2/8/16 障升密度。
- **Opt-C（保留近程势但禁悬停刷分）**：加一个**只在到达圈附近(如 d<1m)才激活**的窄接近势（远处=0，不构成悬停平台），本质是给「最后入圈」阶段补稠密引导（治 pos_error 收尾难）。
- **Opt-D（仅调参续跑）**：w8+更长 20–40M（M1 from-scratch 也要 ~50M；成本高，收益存疑）。

> 备注：悬停刷分已确认被消除（探针无一个悬停正平台），NR-1 的「删基座」目标达成；失败点在「from-scratch 可学性/稠密引导」，属实现后的训练配方问题，不是 reward 结构错。

### Opt-A+B 执行与结果（2026-09-06 21:00；0 障 from-scratch 高 w）

- 配方：0 障（`levels=[0]`、锁 0）、navgoal、progress w=**24 与 32**、ent 0.03、各 10M 并行。
- run：w24 = **`w52wuwj9`**（URL https://wandb.ai/fly-hust/new_reward/runs/w52wuwj9）；w32 **启动失败**（后台 job 未继承 `cd` → `train.py not found`），w24 代表结论。
- **w24 结果：❌ 依旧零学习**——arrival≈0、success≈0.001、pos_error 恒 ~3.6、vel_norm 0.13、entropy -5.8→-6.0（更塌）。**Opt-A（提 w 3-4×）+ Opt-B（0 障）均无效**。
- **根因深化（PPO 结构级）**：PPO actor 用 `IndependentNormal`（`actor_std` 初值 `exp(0)=1`，4 维正常熵 ≈ **+5.7**），10M 内塌到差分熵 **-5.8**（≈每维 std 0.09）→ 锁死「输出≈0 静止」。机制 = navgoal 删 passive pose 后，**所有「静止」状态每步 reward=0（value 与离目标远近无关）**，只有「移动」才产生 progress 差；from-scratch 随机探索多为净负（乱飞难达 + 平滑罚 + timeout −40），PPO 把 std 压回静止 → 永远拿不到「持续朝目标移动→progress 正」的样本。论文 single-integrator 能 work 因每步必能精确朝目标（progress 每步净正）；**四旋翼 from-scratch + 无「靠近即正」引导学不动（w8/24 全证）**。
- 结论：**「from-scratch + navgoal（无被动势）」在当前 PPO+四旋翼下不收敛**，不是权重问题，是引导结构问题 → 需换方向。

**下一步候选（待用户拍板）**：
| 选项 | 做法 | 验证点 |
|---|---|---|
| **N1（推荐先试，快）** | **warm-start 验证 navgoal 属性**：从已会到达的 legacy/dual D2 ckpt（如 m3 V3 `rka11wiz` / S3 `dbch537s` / W2）warm 切 `navgoal` 微调 5–10M | 已会导航之上 navgoal reward 是否带来「更快 / 更平滑 / 不悬停刷分」且不掉到达（规避 from-scratch 引导死结，专注验证 reward 属性） |
| **N2** | 改 return 分布稳定 critic：去 timeout、改 per-step 时间成本 / 给极小 alive，降低 600 步大方差 | 熵是否不再塌、能否学到移动 |
| **N3** | 训练稳定化：`entropy_coef` 0.03→0.05~0.1、或给 `actor_std` 下限（防 std→0.09 死锁） | std/熵维持在探索区间 |
| **N4** | 保留「窄接近势」（仅 d<~1m 激活，远处=0）补 from-scratch 引导 | 治 from-scratch 但需新 reward 项（代码改动） |

### N1+N3（warm legacy→navgoal + ent↑）执行与结果（2026-09-06 21:10）

- 配方：warm S3 `dbch537s`@6.5M（legacy 已会到达）→ 切 `navgoal` 微调；D2-16 同场景；w16/γ1.0/smooth1.0/ab30+t30/to60/dual0.2；`entropy_coef` **0.05 与 0.10** 两档；各 10M。
- run：ent0.05 = **`qeorposc`**、ent0.10 = **`re9dbg3i`**（wandb new_reward）。
- 训练信号：arrival 保持 0.60–0.71（**未塌悬停 ✓**）、pos_error 0.70–0.77（在移动）、first_arrival_step 240–285 步、熵 -1.5~-2.9（未极端塌）。warm 起效——N1 的核心担忧（warm 后 navgoal 崩回悬停）**未发生**。
- **确定性 eval@600/1024 D2-16（与 S3@6.5M legacy 同口径）**：
  | 配方 | ON arrival/joint | OFF arrival/joint/coll_ep |
  |---|---|---|
  | legacy S3@6.5M（warm 起点） | — / **0.743** | — / 0.572 / **34.1%** |
  | navgoal **ent0.05** final | 0.687 / 0.681 | 0.726 / 0.520 / 35.3% |
  | navgoal **ent0.10** final | 0.615 / 0.612 | 0.629 / 0.468 / 32.5% |
- **判定：N1 部分成立（warm 保持到达）但 navgoal 无净增益 ❌**：ON joint 0.68/0.61 **< legacy 起点 0.743**；OFF internalize 无改善（coll 32–35% ≈ legacy 34%）；ent0.10 更差 → **N3(ent↑) 未带来 internalize 提升**。
- 综合（**from-scratch 死锁 + warm 无增益**）：**navgoal（删 pose 的纯 motion-based reward）方案在当前 PPO+四旋翼下不可行/不优** → 按用户约定（"不行再回来重新设计 reward"）回到 reward 重设计。

### Reward 重设计草案（下一步，待用户拍板）
| 方向 | 思路 | 说明 |
|---|---|---|
| **R1（推荐）** | **保留接近引导但 motion-gated**：把 legacy `pose` 类径向「接近正」改成**仅当朝目标运动（v·u_goal>0）时按当前距离给正**；悬停（v≈0）=0、远离=负 → 同时保住 from-scratch 可学性与「不悬停刷分」；配合 ⑥ CBF dual + 到达/timeout 结算 | 需要新 reward 项（代码改动），可从现有 `heading_alignment`/`pos_error` 组合实现 |
| **R2** | 在 **legacy 框架上**修「悬停刷分」：保留 pose 稠密引导，把 pose/up/spin/effort 常驻正项降权或对「长时间无有效前进」加惩罚 | m3 已探权重到顶（W4≈V3、S 饱和），可选微调但增益存疑 |
| **R3** | 维持 warm+navgoal 继续调优（更长/更多权重）直到超过 legacy | 本次已证 10M 无增益且训练更不稳，成本高、证据不支撑 |

### R1 实现 + 0 障 from-scratch 10M 探针（执行与结果，2026-09-06 21:30）

- 实现：`reward_scheme: r1`（motion-gated 接近引导）——主项 `w_g·relu(v·u_goal)/v_max·1/(1+(k·d)²)` + time-scaled 到达 + action-diff 平滑 + ⑥⑦ 复用；`reward_gate_weight`/`reward_distance_scale` 入 cfg。**踩坑 2（形状）**：`u_goal = rpos/pos_error(2D)` 灾难广播 (N,N,3)；`appro=sum(keepdim=True)` 得 (N,1,1)×2D pose → (N,N,1)；修复 = 除 `rpos.norm(dim=-1,keepdim=True).clamp_min(1e-6)`、`sum(dim=-1)` 无 keepdim（r1 改动未 commit，待定方向后一并提交）。
- 配方：0 障锁级、r1、w_g=15、k=1.6、arr 30+t30、to 40、smooth w_s=1.0、CBF hybrid/dual w1=w2=0.1 σ0.5、ent 0.02、10M。
- run：**`ht30t6tm`**（NavVel-R1-0obs-wg15-ent0.02，wandb new_reward）；日志 /tmp/navvel_r1_0obs_wg15.log。

| 指标 | 早期 ~0.5–1.5M | ~5M | ~10M(final/eval) | 判读 |
|---|---|---|---|---|
| return | -3019 → -191 | -41.4 | **-5.15** | 单调爬升（实为「学静止减罚」，非到达成效）|
| arrival / success_rate | 0.10–0.40% | 0 | **0**（eval 0.0） | 早期个别随机到达后归零 |
| pos_error | 3.60–3.79 | 3.69 | 3.60 | **恒 ≈ 初始 d0 → 未接近目标** |
| vel_norm | 0.38 → 0.58 | 0.18 | **0.13** | 单调降 → 学到静止 |
| mean_action_diff | 1.56 → 0.61 | 0.25 | **0.14** | 动作变化单调塌缩 |
| entropy | -5.47 | -5.98 | **-6.07** | 差分熵持续降（std→~0.05 级）|

**结论：R1 from-scratch 10M 失败（与 navgoal 同型）❌**。悬停刷分平台确已删（悬停窗 return≈-40，尾段 -5），但策略学到的是「把 adiff/速度压到 0」以最小化平滑罚 + timeout，而非飞向目标。

**机制诊断（量化）**：
1. **接近势核远端死区**：`k=1.6` ⇒ spawn 距离 d≈3.6 处 pose=1/(1+(1.6·3.6)²)≈**0.029（≈3% 峰值）**；episode 前 90% 时间在 d>2m，每步朝目标收益 ≤ w_g·0.055≈0.8/步（通常远低）→ R1 远场实际≈navgoal。「越近越强」保住收尾却抹平 from-scratch 最需要的「远端拉起」梯度。
2. **smooth 罚 vs 朝目标收益失衡**：初始 std=1 ⇒ adiff≈1.5 ⇒ smooth 罚 w_s·1.5²≈**2.3/步** ≫ 远场收益上限 ≈0.8/步 → 乱飞全程净负；PPO 唯一能稳定降低的是 adiff → std 塌 → 静止。return -3019→-5.15 正是「压 adiff 减罚」的学习曲线。
3. 对照 legacy：常驻正（survival + pose·(up+spin) + effort ~0.1+/步）全程兜底 → 乱飞不致命、PBRS 可学；R1/navgoal 删基座后乱飞期无正项 → **结构级不可学（同一根因；R1 的「保留稠密」被核的远端衰减抵消）**。

**下一步候选（待用户拍板）**：
| 选项 | 做法 | 验证点 |
|---|---|---|
| **R1-warm（推荐先试，快）** | warm legacy S3 `dbch537s`@6.5M → 切 `r1` 微调 5–10M（已会到达，规避 from-scratch 死结） | 已会导航上 r1 是否消除远端 loiter/悬停刷分、更快更平滑、不掉到达 |
| **R1-v2（from-scratch）** | 核展平 k 1.6→~0.45（d=3.6 处 pose 0.16≈+5×）+ smooth w_s 1.0→0.3 + ent 0.05，from-scratch 复测 | 远端每步收益 ≥ smooth 罚 → 是否可学 |
| **R2** | 回 legacy 框架修悬停刷分（降 pose/常驻正、加滞留惩罚） | 增益存疑（m3 已到顶，W4≈V3/S 饱和） |

### F1 实现 + 0 障 from-scratch 10M 探针（执行与结果，2026-09-06 21:42）

- 实现：`reward_scheme: f1`（无核飞行主导）——`w_f·relu(v·u_goal)/v_max`（**无距离核**，远端=近端同强）+ time-scaled 到达；复用 r1 的 stat/smooth/⑥⑦ 结构；`reward_fly_weight` 入 cfg。用户选定**先不加时间成本②**（纯净隔离①）。
- 配方：0 障锁级、f1、w_f=1.5、w_s=0.2（smooth 降到不压死探索）、arr 30+t30、to 40、CBF hybrid/dual w1=w2=0.1、ent 0.05、10M。
- run：**`emy1u3ow`**（NavVel-F1-0obs-wf1.5-ent0.05，wandb new_reward）；日志 /tmp/navvel_f1_0obs_wf15.log。

| 快照(顺序) | return | pos_error | arrival/success | vel_norm | adiff | entropy |
|---|---|---|---|---|---|---|
| 0 | -600 | 3.75 | 0 / 0 | 0.34 | 1.57 | (早段高) |
| 5 | -7.1 | 3.36 | 0.1% / 0.3% | 0.23 | 0.57 | |
| 10 | +56 | 2.84 | 2.7% / 2.6% | 0.29 | 0.42 | |
| 14 | +97 | 2.54 | 5.3% / 9.0% | 0.34 | 0.42 | |
| 15(final/eval) | +98 | 2.49 | 5.2%(eval 5.7%) | 0.32 | 0.41 | **-1.6 稳定** |

**结论：✅ F1 纯① from-scratch 10M 首个可学（三无基座方案中唯一不死的）**——pos_error 单调降（在接近目标）、return 转正 +98、entropy 稳定 -1.6（无塌缩）、arrival 爬至 ~5%。**证实 R1 失败主因 = 接近势核 `k=1.6` 远端≈0 死区（d≈3.6 处 pose≈0.03）；去掉核+纯运动主导（action-local，reward 是速度指令直接函数）+ smooth 降档 = from-scratch 可学**。悬停平台=0 保持（悬停 return 0-(-40)）。

**未收敛点 / 观察**：10M 尾段趋平——arrival ~5%、pos_error 2.49（仍未 <1）、平均速度 0.32（偏慢）；「学会朝目标飞但完成/加速不足」。可能原因：① 纯① 无「完成到达」的 per-step 压力（只有稀疏 arrival +30/60）；② 10M 预算短（legacy M1 到 99% 用了 ~50M）。

**下一步候选（待用户拍板）**：
| 选项 | 做法 | 验证点 |
|---|---|---|
| **F1-延训** | 同配方续到 30M 看 arrival 上限 | 是否继续爬升达可用(≥60-70%?) |
| **F1+时间成本②** | 补加 c_t per-step（治 loiter、推快/完成），10M 复测 | 到达完成度是否显著提升 |
| **F1-warm** | warm legacy S3@6.5M 切 f1 微调 + D2-16 确定性 eval | 已会导航上 f1 是否更快/更平滑/不掉到达 |
| **F1-vary w_f** | w_f 1.5→2~3 或加近程入圈叠加项 | 加速/完成是否有改善 |

### F1 延训 30M + 三组调参（执行与结果，2026-09-06 21:47–21:58）

- **F1-延训（gbnax8a7）**：从 emy1u3ow final ckpt 续训 20M（累计 30M），同配方。**eval arrival 49.7%**、pos_error 0.65、success_rate 0.997、vel 1.15、熵 -0.55 → **10M 的 ~5% 平台只是训练早段，纯①到 30M 持续强学到 ~50% 到达**（返程曲线：~20M arrival 0.31 / ~24M 0.45 / ~26M 0.53）。
- **F1-c0.1（1m2npshx）**：+时间成本② c_t=0.1/步，10M from-scratch。eval arrival **5.0%**（≈纯① 5.3%，未加速）、pos_error 2.75、熵 -2.4（更塌）→ **② 在 10M 内未带来加速**（可能需更长或与 w_f 搭配）。
- **F1-wf3（ngycl4pc）**：w_f=1.5→**3.0**，10M from-scratch。eval arrival **18.4%**（3.5× 纯①）、pos_error **0.62**、success_rate 0.996、vel 0.65、熵 0.20（健康）→ **w_f 是加速 from-scratch 收敛的关键旋钮：3.0 时 10M ≈ 纯① 20M+ 的水平**。
- **F1-ab60（4heskptf）**：到达奖励 30→**60/60**，10M from-scratch。eval arrival **2.6%**（比纯①差）、pos_error 2.45 → **加大稀疏到达奖励无帮助（甚至略差，诱使守株待兔式等个别成功）**。
- ⚠️ 启动坑（记）：`cd X && (A) & (B)` 的 `&` 会把 `cd X && (A)` 整个当后台任务，前台 shell 不 cd → B 在错目录 `train.py not found` 静默失败。**并行必须每个子 shell 内各自 `cd` 绝对路径**（或独立终端）。
- **结论**：当前最优配方 = **F1 w_f=3.0**（arrival/pos_error 收敛最快）；时间成本②、加大到达奖励 在 10M 口径未见益。下一步候选：wf3 延训 30M（冲高到达）、w_f 再探 4.5–6、wf3+② 组合、或直接升密度(2 障/D2-16) 对照 legacy 0.743。

### 第二批：wf3ext30M / wf6 / wf3+②（执行与结果，2026-09-06 22:11–22:2x）

| 配方 | run | 帧 | eval arrival | pos_error | success | 熵 | 判读 |
|---|---|---|---|---|---|---|---|
| wf3 续 20M(总30M) | `dkbtuzj2` | 30M | **48.2%** | 0.54 | 1.0 | -0.24 | **w_f=3 到 30M ≈ 纯① 30M(~50%) → w_f 主要加速前期非提上限** |
| **wf6 (w_f=6.0)** | `0tjlxy7c` | 10M | **71.4%** | **0.40** | 1.0 | **+0.97** | **w_f 单调强加速: 1.5→5% / 3→18% / 6→71%**；熵正(仍在探索) |
| **wf3 + c0.1** | `4fjm3il8` | 10M | **56.9%** | 0.49 | 0.66 | -0.50 | **时间成本②在强吸引子上显著加成(w3: 18→57%)**；此前 w1.5+c0.1 无益=吸引子太弱 |

- **结论**：w_f 是 from-scratch 收敛的主导旋钮，且高 w_f 比长训练更有效（wf6@10M 71% > wf3@30M 48% > 纯①@30M 50%）。**当前最强 = F1 w_f=6.0**。
- ⚠️ **升密度隐患**：w_f=6 ⇒ 朝目标每步最高 +6/步，相对安全项（edge 4、near 1.0、log、CBF dual 0.1–0.2）会**淹没安全信号** → 上 2 障/D2-16 时需重新标定 ⑥⑦（升权）或降 w_f，否则策略会穿障。
- 坑记录 2：多后台并行 `( ) &` 时 conda 激活必须**在每个子 shell 内部** `source+activate`（`A && (B) & (C)` 的 & 会把 `A && (B)` 整体后台化，C 无激活 → hydra not found）。
- 下一步候选：wf6 延 30M（0obs 上限）/ wf9 探上限 / wf6+② / **升 2 障**（重标安全权重比）。

### 第三批：wf6ext30M / wf3-2障 / wf9（执行与结果，2026-09-06 22:19–22:3x）

| 配方 | run | 帧/密度 | eval arrival | pos_error | success | collision | 熵 | 判读 |
|---|---|---|---|---|---|---|---|---|
| **wf9 (w_f=9)** | `12hf3149` | 10M 0障 | **93.9%** | 0.33 | 1.0 | 0 | +1.75 | **w_f 单调到底: 1.5→5 / 3→18 / 6→71 / 9→94% @10M**；0 障基本一次学会 |
| **wf3-2障** | `s2xprexh` | 10M 2障 | **80.4%** | 0.34 | 0.966 | **0(eval)** | 0.52 | **f1 有障碍仍可学且安全**（edge4/dual0.1 默认足够，w_f=3 未淹安全项） |
| wf6 延 30M | `2d8ym5yt` | 30M 0障 | 64.4% | 0.45 | 0.999 | 0 | +0.96 | 低于 wf6@10M(71%) → **长训不如直接高 w_f** |

- **结论**：0 障最优 = **F1 w_f=9.0 @10M = 94% 到达**（w_f 主导，单调到 9 仍在涨，可能更高）；2 障验证通过（w_f=3, 80% arrival / 0 collision）。
- ⚠️ 高 w_f 安全比：2 障稀疏 OK；**D2-16 密集需验证 w_f 相对 ⑥⑦ 的比例**（w_f=9 每步最高 +9 vs edge 4 / dual 0.1 会被淹）→ D2-16 宜 w_f=3~6 或同步升安全权重。
- **下一步（核心里程碑）**：**D2-16（16 障固定）对照 legacy**——ON joint 基线 0.743、OFF coll 基线 34%（internalize）。候选：w_f=3 与 w_f=6 两档 from-scratch 10–20M（含 curriculum 0→16 或固定 16），看 ON joint / OFF coll。

### 课程学习 2-4-8-16 四变体（执行与结果，2026-09-06 22:28–22:4x）

- 配置：`curriculum.levels=[2,4,8,16]` enabled（success≥0.8 且 coll≤0.05 进阶）、num_scene=16、arena [[-2.2,2.2]]、edge4/near1.0、CBF hybrid/dual 0.1、12M from-scratch；变体 = w_f∈{3,6} × c_t∈{0,0.1}。
| 变体 | run | 进阶到(level) | eval arrival | pos_error | success | collision_ep | cbf_viol | 判读 |
|---|---|---|---|---|---|---|---|---|
| wf3 | `abtuaqix` | **2**（卡住）| 78.0% | 0.43 | 0.83 | 0.49% | 0.0006 | w_f=3 到 2 障后 gate 不过（密集下吸引力不足）|
| **wf6** | `pg6q5ji5` | **16** | **90.6%** | **0.34** | 0.93 | **1.27%** | 0.12 | **通关且 16 障 90.6%/1.3%——最佳配方** |
| wf3+c0.1 | `p0fza06w` | 4（卡住）| 75.3% | 0.44 | 0.96 | 0.39% | 0.004 | 时间成本救不了弱吸引子 |
| wf6+c0.1 | `lreeuqw5` | 16 | 67.8% | 0.45 | 0.92 | 1.46% | **0.15** | 时间成本催速撞障(CBF 干预多)、arrival 降 |
- **结论：F1 w_f=6.0 + curriculum [2,4,8,16]（无时间成本）是课程通关配方**——12M from-scratch 到 16 障，90.6% arrival / 1.27% collision（纸面超 legacy ON joint 0.743）。时间成本在密集障碍有害；wf3 穿不动密集。**待办：确定性 ON/OFF eval（同 legacy 0.743/34% 口径）正式对比**。

### F1 wf6 D2-16 确定性 eval（ON/OFF，同 legacy 口径 @600/1024，2026-09-06 22:5x）

- ckpt `pg6q5ji5`（wf6 课程 final），eval 固定 16 障、CBF hybrid dual、runtime_filter ON/OFF。
| 口径 | arrival | collision_ep | joint | vs legacy |
|---|---|---|---|---|
| **ON**（filter 在） | 0.936 | 0.9% | **0.930** | **≫ legacy 0.743（coll 2.3%）✅ 大胜** |
| **OFF**（filter 去=internalize） | 0.942 | **41.0%** | 0.588 | ≈ legacy 0.572；coll 41% > legacy 34.1% ❌ 未 internalize |
- **判定**：带 filter 部署下 F1 远胜 legacy（joint 0.93 vs 0.74、coll 0.9% vs 2.3%，且 from-scratch 12M vs legacy 50M+）；**但 OFF（撤 filter）仍 41% 碰撞 = 未实现 internalize（与 legacy/M3 同样卡在这）**。按 CBF-RL 论文预设（filter 运行时保安全），ON 即部署口径 → **F1 达标**；internalize（OFF 也安全）仍是可选后续（需升 dual 权重，M3-B 已示难）。

### 决策（2026-09-06 23:0x，用户）：主力续训 + 三路 OFF-internalize（均 warm pg6q5ji5@12M）
- **主力**：pg6q5ji5 同配方（wf6 + 课程 [2,4,8,16]）续 **20M**（累计 ~32M）打磨；**internalize 无需等主力**——三路 I 直接 warm pg6q5ji5 final ckpt（已 16 障会导航的强策略），同基座并行。
- **I1** `wf6-intdual0.3`：dual reward/correction 0.1→**0.3/0.3**（锁 16 障 10M）
- **I2** `wf6-intdual0.5`：dual →**0.5/0.5**（锁 16 障 10M）
- **I3** `wf6-intdual0.3-near3`：dual **0.3/0.3** + 近障 near_slowdown 1.0→**3.0**（锁 16 障 10M）
- 判据：OFF deterministic eval coll 是否 < legacy 34.1%（internalize 成功 = 撤 filter 也低碰）且 OFF joint 不塌。

### 阶段 F 结果（2026-09-06 23:1x，internalize 三路 + 主力 32M）

| 模型 | 配方 | OFF arrival | OFF coll | OFF joint | 判定 |
|---|---|---|---|---|---|
| 基座 pg6q5ji5@12M | wf6 | 0.942 | 41.0% | 0.588 | 基准 |
| I1 `l8lsd5rd` | dual0.3 | 0.887 | 43.0% | 0.558 | ❌ 未 internalize |
| I2 `h8qz5hb6` | dual0.5 | 0.911 | 44.2% | 0.555 | ❌ 未 internalize（ON cbf_viol 降 0.057 但 OFF 无益）|
| I3 `cc7liz0x` | dual0.3+near3 | 0.920 | 40.9% | 0.590 | ❌ 微降但仍 ≫ legacy 34.1% |
| 主力 `c6yxszpb`@32M | wf6 锁16 续20M | — | — | **ON joint 0.920** | ≈ pg6q5ji5 0.930（长训不增）|

- **判定**：**internalize（OFF 安全）三路均未达成**——升 dual(0.3/0.5) 或近障罚(×3) 都不能把 OFF coll 压到 legacy 34.1% 以下（40.9–44.2%）。确认策略依赖运行时 CBF filter（与 M3-B 同结论）；**按 CBF-RL 部署前提（filter ON），交付 = pg6q5ji5@12M + filter**。
- **主力结论**：确定性 eval ON joint 0.920 ≈ 12M 的 0.930 → **F1 收敛快（~12M 即平台），无需长训**（train.py 内置 Final Eval 的 0.641 为随机采样假回落，以确定性 eval_ckpt 为准）。
- **最终交付**：**F1 w_f=6.0 + curriculum[2,4,8,16]，pg6q5ji5@12M，D2-16 ON joint 0.930 / coll 0.9%**（vs legacy 0.743 / 2.3%）。

### 阶段 G：internalize 新机制 T1-T4（2026-09-06 23:0x–23:2x，warm pg6q5ji5 +10M 锁16）

| 机制 | run | 训练 ON eval | OFF 确定性 eval | 判定 |
|---|---|---|---|---|
| T1 corr6 (w2=6≈w_f) | `vubrtdql` | arrival 0.44(collapsed) | coll 41.8% / joint 0.441 | ❌ 过度保守，arrival 崩 |
| T2 reward_only (无滤波训练, edge8) | `c3ga7ko2` | —（无 filter）| **coll 30.7%** / joint 0.589 / arr 0.73 | ⚠️ **唯一 OFF coll < legacy 34.1%**，但 arrival 降(0.73) |
| T3 margin (danger1.2+near5+dual0.5) | `5f8ik6rs` | arr 0.845 / viol 0.023 | coll 39.9% / joint 0.592 / arr 0.91 | ❌ ON 留余量但 OFF 仍 ~40% |
| T4 combo (corr3+danger1.0+near3) | `h9ge2cl3` | arr 0.779 / viol 0.008 | coll 41.1% / joint 0.574 | ❌ 同上 |

- **关键观察**：T3/T4 训练 ON 把 `cbf_violation` 压到 0.008–0.023（filter 平均干预极低、arrival 保持 0.78–0.85），**但 OFF 仍 40% 碰撞** → 低平均 violation 来自「多数开敞飞行步」；**穿障尾段仍需 filter，撤掉就撞**。corr6(T1) 能逼出余量但让 arrival 崩。
- **T2（reward_only 无滤波训练）是唯一 OFF coll < 34.1%（30.7%）的**——训练期真碰撞教会自保，但到达降到 0.73。
- **结论：internalize（OFF 也安全且保持高到达）经 7 组（I1-I3 + T1-T4）仍未达成**——策略总会把安全余量吃回去冲飞 reward，只有硬 filter（或 T2 式真碰撞）能拦住。**按 CBF-RL 预设，交付口径 = 带 filter（ON joint 0.93）**；如需 OFF 安全需代码级新手段（如把 filter 介入量/最小净空加入 obs、margin 课程 gate），非本轮 reward-shaping 可及。

### 阶段 H：D2-8 OFF 密度对照（2026-09-06 23:4x，用户：先降 eval 障碍到 8 再考虑 obs 改造）
| 模型 | D2-16 OFF arr/coll/joint | **D2-8 OFF** arr/coll/joint | 判定 |
|---|---|---|---|
| 基座 `pg6q5ji5` | 0.942 / 41.0% / 0.588 | **0.979 / 21.5% / 0.784** | 降密 16→8：coll 41→21.5%（纯障碍变少的统计效应）|
| I3 `cc7liz0x` | 0.920 / 40.9% / 0.590 | 0.930 / 22.9% / 0.748 | ≈基座，无 internalize 增益 |
| T2 `c3ga7ko2` | 0.73 / 30.7% / 0.589 | 0.598 / **19.5%** / 0.516 | 唯一 coll 略低(真碰撞训练)但 arrival 崩 0.60 |
| T3 `5f8ik6rs` | 0.91 / 39.9% / 0.592 | 0.866 / 23.6% / 0.697 | ≥基座 coll，无增益 |
| T4 `h9ge2cl3` | ~0.78 / 41.1% / 0.574 | 0.767 / 24.4% / 0.617 | ≥基座 coll，无增益 |
- **判定：internalize 未因降密度而显现**——8 障下所有臂 OFF coll ~20–24% = M2-era 8 障 OFF 地板(19–23%，障碍少→碰撞机会少)，**internalize 组(I3/T3/T4) coll ≥ 基座**，无一组分离；仅 T2 略低但 arrival 毁。**低密度只是让一切变好，非方法奏效** → reward-shaping 在 8/16 障同样失败，锁死结论：OFF 安全需 obs 结构级改造（filter 介入量/最小净空入 obs），下一步据此设计 + 重训。|




