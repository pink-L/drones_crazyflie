# New2 规划：obs 结构级改造实现 internalize —— CBF 边界余量 h / min_clearance 入 obs + from-scratch 重训课程

> 创建：2026-09-07。**本文件 = New2 阶段项目汇报总结文档**（延续 new1_plan.md 惯例，动手后回填文末「执行记录」）。
> 仓库：`/home/lz/lzspace/drones/OmniDrones`（分支 `feat/crazyflie-pidrate`，HEAD `f9566f8` = New2-impl obs_safety 落地，起始 `3941a1b`，tag `f1-d2e16-achieved`）；环境 `conda activate lz_env`，命令在 `OmniDrones/scripts/`。
> wandb：项目 **`new_reward`**（fly-hust）；本阶段所有 run 均进 `new_reward`。
> 上游：`drones/new1_plan.md`（顶部阶段性总结，**新 agent 先读它**）、`drones/new_reward.md`（§F1 reward 方案）、`drones/f1_recipe_and_runs.md`（配方/run 总表）、`drones/navvel_rl_interface.md`（接口基线）。
> 动机来源：CBF-RL 论文（Yang 2026）Dual internalize 复现失败后的结构性新手段（用户 2026-09-06/07 拍板）。

---

## 0. TL;DR（一句话）

**New1 已交付「带 CBF filter 的 F1 策略」（pg6q5ji5@12M，ON joint 0.930 / coll 0.9%，tag `f1-d2e16-achieved`）；internalize（撤 filter 也安全 = OFF coll < legacy 34.1% 且 joint 不塌）经 reward-shaping 7+ 组全失败。New2 改走 obs 结构级改造：把「filter 触发边界」作为显式状态喂给策略（CBF 边界余量 $h=\min_i(\|p-p_{oi}\|-r^{cbf}_{s,i})$ 首选 / min_clearance 保守版），from-scratch 重训课程 2-4-8-16，验证 OFF internalize 是否首次出现。**

---

## 1. 背景：为什么 New1 结束在 internalize 失败，New2 为什么换 obs

### 1.1 New1 交付状态（2026-09-06 收官，完整见 new1_plan.md 顶部总结）
| 交付物 | 值 |
|---|---|
| 配方 | **F1 w_f=6.0, w_s=0.2, ent0.05, arrive 30+30t, to40, edge4/near1, CBF hybrid dual 0.1σ0.5, curriculum [2,4,8,16]** |
| 交付模型 | `pg6q5ji5`@12M（D2-16 确定性 eval） |
| ON（带 filter）| joint **0.930**（arr 0.936 / coll 0.9%）≫ legacy 0.743 |
| OFF（撤 filter）| joint 0.588 ≈ legacy 0.572，但 coll **41.0%** > legacy 34.1% ❌ 未 internalize |

### 1.2 internalize 已试全表（全部失败 → 本阶段换手段的根据）
| 批次 | 手段 | 结果 |
|---|---|---|
| I1/I2/I3 | dual 升权 0.3/0.5/near3（warm pg6q5ji5 +10M）| OFF coll 40.9–44.2% ❌ |
| T1 | corr6（w2=6≈w_f）| arrival 崩 0.44（保守塌陷）❌ |
| T2 | reward_only 无滤波训练 + edge8 | OFF coll 30.7%（唯一 <34.1%）但 arr 降 0.73 ⚠️ |
| T3/T4 | margin（danger1.2+near5+dual0.5）/ combo | ON viol 压到 0.008–0.023 但 OFF 仍 ~40% ❌ |
| D2-8 密度对照 | eval 障碍 16→8 五模型 | 8 障 OFF coll ~20–24% = M2-era 地板；internalize 组无一组分离 ❌ |

### 1.3 为什么 reward-shaping 必然失败（机制结论，写进本阶段的「设计理由」）
1. **per-step 修正罚被开敞步稀释**：T3/T4 的 `cbf_violation` 0.008–0.023 是 600 步整窗 EMA，~590 步开敞飞行 filter 不介入（罚=0），真正穿障尾段只占少数步 → 平均后梯度≈0。
2. **介入发生时已太晚**：filter 在穿障尾段（最后 ~0.5s）才介入，PPO 从 per-step 事后罚学不到「提前减速/绕行」的预测性行为 → 只能全局保守（T1）或钻空子（高 w_f 冲飞让 filter 背锅）。
3. **大系数保守塌陷**：w2≥6 / dual≥0.3 必崩 arrival（四旋翼动力学滞后 ⇒ 不存在「贴 CBF 边界高速飞且 filter 零介入」的解；论文 single-integrator 有）。
4. **结论**：filter 介入需要的是「**介入前的预测性状态特征**」，不是「介入后的事后惩罚」→ 必须把 filter 触发边界（CBF 几何量）放进 obs，让策略在 obs 层面学会「看到 h 收紧就提前减速」。

---

## 2. New2 方案：obs 加什么、为什么、sim2real 影响

### 2.1 三个候选量对比（已分析定稿，勿再纠结）
| 候选 obs 通道 | 公式 | sim2real / internalize | 结论 |
|---|---|---|---|
| ❌ filter 介入量 | $\|v_{filt}-v_{nom}\|$ | 撤 filter 部署时恒 0 → 训练/部署分布偏移，自相矛盾 | **不用** |
| ✅ **CBF 边界余量 h**（首选）| $h=\min_i(\|p-p_{oi}\|-r^{cbf}_{s,i})$，$r^{cbf}_{s,i}=r_{s,i}+\text{cbf_extra}$ | 纯几何，训练/部署同源；真机有障碍地图/感知即可复算；不依赖 filter 在线；**直接告诉策略 filter 触发边界** | **主推** |
| ✅ min_clearance（保守版）| $\min_i(\|p-p_{oi}\|-r_{s,i})$（纯几何表面净空，不含制动余量）| 同上，更保守（不含 v_max/a_max 假设），但信息量少一个「filter 会在更远处介入」的提示 | 备选/可并列 |

> ⚠️ New2 实现上建议 h 与 min_clearance **都加**（各 1 维），让策略同时看到「几何净空」与「CBF 触发边界」两把尺子；若想单变量消融再拆开跑。**默认关（新 cfg 键），逐位兼容**旧 obs 62 维（不加 = 与 New1 完全一致）。

### 2.2 实现设计（代码落点）
- **cfg 键**（`cfg/task/NavVel.yaml` obstacle 或顶层段，需与现有命名风格一致）：
  - `task.obs_safety: none|clearance|cbf_margin|both`（默认 `none` = 62 维不变）
  - 或拆两个 bool：`task.obs_min_clearance` / `task.obs_cbf_margin`（默认 false）
  - 归一化分母可复用 `obstacle_danger_radius`(0.6) 或 cbf_extra 尺度
- **`nav_vel.py`**：
  - `_set_specs`：`observation_dim += n_safety`（当前 62 = 前 30 + time4 + 障碍块 K*4=32；h/min_clearance 各 +1）
  - `_compute_state_and_obs`：已有 `self._obs_dmin = self.obstacles.min_clearance(drone_pos)` (N,1) 与 `rcbf = self.obstacles.r_safe + self.cbf_extra`；追加计算并 cat 到 obs 尾部
  - ⚠️ obs 拼装是 `torch.cat(obs, dim=-1)` 且 rpos 等为 (N,1,3)，标量通道须 unsqueeze 成 (N,1,1) 对齐；**旧 ckpt 因维度变化不可 warm 续（New1 已有先例 30→62）**
- **无 filter 臂**（naive / cbf.mode=none）：h 无 cbf_extra，退化为 min_clearance；obs_safety=none 时完全不计算（保性能）
- **回归**：`cbf_test.py` CPU 全 PASS + GPU 冒烟 30k 帧（obs_safety=none 必须与 pg6q5ji5 逐位一致）

### 2.3 sim2real 影响（已在接口文档注明）
- h / min_clearance 都是**纯几何量**（障碍位置 + 确定性半径公式），真机用动捕已知地图或机载雷达/相机估计障碍位置即可复算（部署愿景见 `navvel_obstacle_migration_guide.md` §5.4）
- **不新增传感器需求**：依赖的「障碍位置」本来就已是 obs 62 维里障碍块的输入；只是多算一个 min 距离
- `r_cbf` 含 `a_max` 等动力学假设 → 真机标定若不同需保守值或 DR 覆盖（可选后续，非本轮阻塞）

---

## 3. 里程碑与验收

| # | 内容 | 验收 |
|---|---|---|
| New2-impl | obs_safety 实现（none 逐位兼容 + clearance/cbf_margin/both 通道） | cbf_test CPU 全 PASS + GPU 冒烟无 NaN/形状错；obs_safety=none 与 New1 逐位一致 |
| New2-probe | from-scratch 低密度（0→2 障 10M）收敛探针 | arrival 可学、h/clearance 通道有信息量（warm 试看是否更快学会规避）|
| **New2-main** | from-scratch 课程 [2,4,8,16]（w_f=6.0 同 New1 配方 + obs_safety） | 通关 16 障；**OFF 确定性 eval coll < legacy 34.1%** 且 OFF joint 不塌（≥~0.6）→ internalize 首次出现 |
| 对照 | 同 ckpt 三口径 eval：ON / OFF / OFF+perturb | OFF internalize 是核心判据；ON 不低于 New1 太多（joint ≥ ~0.85 可接受）|

**验收判据细则（internalize 成功 = 三者同时）**：
1. `runtime_filter=false` OFF 确定性 eval @D2-16：coll < **34.1%**（legacy 基线），目标 ~<25%
2. OFF arrival / joint 不塌（OFF joint ≥ ~0.6，接近 ON 的 ~70–80%）
3. 不牺牲 ON 部署太多（ON joint ≥ ~0.85 量级，target ~0.9）

---

## 4. 训练 / 评估协议

### 4.1 训练（from-scratch，与 New1 pg6q5ji5 同配方，只加 obs_safety）
```bash
cd /home/lz/lzspace/drones/OmniDrones/scripts
conda activate lz_env
python -u train.py task=NavVel algo=ppo headless=true \
  wandb.mode=online wandb.project=new_reward wandb.run_name=NavVel-F1-obsCbfMargin-curriculum \
  task.reward_scheme=f1 task.reward_fly_weight=6.0 \
  task.arrive_bonus=30 task.arrive_time_bonus=30 task.reward_timeout_penalty=40 \
  task.reward_action_smoothness_weight=0.2 \
  task.obstacle.obs_safety=cbf_margin \        # ← New2 新键（默认 none）
  task.cbf.mode=hybrid task.cbf.use_brake_term=false \
  task.cbf.penalty_src=dual task.cbf.reward_weight=0.1 \
  task.cbf.correction_weight=0.1 task.cbf.correction_sigma=0.5 \
  algo.entropy_coef=0.05 total_frames=12_000_000 \
  'task.curriculum.levels=[0,2,4,8,16]' task.curriculum.enabled=true \
  save_interval=100 +render_eval=false 2>&1 | tee /tmp/navvel_new2_obsCbfMargin.log
```

### 4.2 确定性 eval（与 legacy / New1 同口径）
```bash
python -u eval_ckpt.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
  task.reward_scheme=f1 task.reward_fly_weight=6.0 \
  task.arrive_bonus=30 task.arrive_time_bonus=30 task.reward_timeout_penalty=40 \
  task.reward_action_smoothness_weight=0.2 \
  task.obstacle.num_scene=16 'task.obstacle.spawn_xy_range=[[-2.2,-2.2],[2.2,2.2]]' \
  'task.curriculum.levels=[16]' task.curriculum.enabled=false \
  task.obstacle.reward_collision_edge=4 task.obstacle.reward_near_slowdown_weight=1.0 \
  task.cbf.mode=hybrid task.cbf.use_brake_term=false task.cbf.penalty_src=dual \
  task.cbf.reward_weight=0.1 task.cbf.correction_weight=0.1 task.cbf.correction_sigma=0.5 \
  +checkpoint=<ckpt> +rollout_steps=600 +runtime_filter=false | grep -iE 'arrival|collision|joint'
# runtime_filter=true 也要跑一份对照
```
> ⚠️ eval 的 obs_safety 键必须与训练一致；`+runtime_filter=false`（internalize 判据）/ `true`（ON 对照）。

### 4.3 时间预算
- GPU：RTX 5090 D 32GB；单 run ~6–7GB → 可并行 4 个
- 课程 12M ≈ ~10–20 min/run（New1 pg6q5ji5 实测 ~12M from-scratch 通关）

---

## 5. 关键坑与注意事项（继承 New1/M2/M3，防重踩）

1. **torchrl 形状坑**：env stats/scalar reward 是 **2D (N,1)**；drone_state/rpos/policy_actions 是 **3D (N,1,K)**。reduce 必须 keepdim=False 得 2D；用 2D 除/乘 3D 会灾难广播 (N,N,1) 崩在 `stats["return"] += reward`。新 obs 标量通道追加到 cat 时注意维数对齐。
2. **reward-core 早峰型**：F1 课程 from-scratch 会快速收敛（~12M 即平台）；`save_interval=100`（~3.3M ckpt 粒度），mid-ckpt 也要确定性 eval 取峰，勿盲加帧（New1 主力 32M ≈ 12M 平台）。
3. **训练内置 Final Eval 是随机采样假回落**：以 eval_ckpt 确定性为准（New1 32M 显示 0.641 实为 eval_ckpt 0.920）。
4. **obs_safety=none 必须逐位回归**：加通道逻辑用独立 cfg 门控，default none 分支不碰现有 cat 路径，防污染 New1 基线。
5. **h 的归一化**：cbf_extra ≈ margin0.1 + brake 项（若开）；用 danger_radius(0.6) 或类似尺度 clamp 到合理范围；h 可为负（进入 CBF 球内），clamp 下限注意不要剪掉「负余量=危险」的信息（或用 relu + 独立负标志）。
6. **并行 eval 注意**：eval_ckpt 峰值 ~18GB，勿与训练进程并行（会 CUDA OOM）；GPU 空闲串行 eval。
7. **多会话并发 GPU/仓库会撞车**：键名统一、确认无他人 run 再动。

---

## 6. 执行记录（回填用）

### New2-impl 代码落地 + 回归 + 冒烟（2026-09-07 00:2x-00:4x）
- **实现 commit `f9566f8`**（分支 feat/crazyflie-pidrate，HEAD 3941a1b→f9566f8，未打 tag）：
  - `utils/cbf.py` + `safety_obs_channels(dmin, extra, norm, add_clearance, add_cbf_margin)` 纯 CPU 函数 → list[(N,1,1)]。h = min_i(‖p-p_oi‖-r_si^cbf) = **dmin - cbf_extra**（cbf_extra 为标量，故 min 可提；naive/无 CBF 传 0 → 退化为 min_clearance）；clamp[-1,1] 保负余量信息；无活动障碍 dmin=inf → +1（完全安全）。
  - `nav_vel.py`：`task.obstacle.obs_safety = none|clearance|cbf_margin|both`（默认 none）；`obs_safety_norm`（默认 danger_radius 0.6）。_set_specs 62→63/64；_compute_state_and_obs 障碍块后 cat（通道 unsqueeze(1) 成 (N,1,1) 对齐 3D obs）。
  - `cfg/task/NavVel.yaml` 新键+注释；`scripts/cbf_test.py` 加 **t7** CPU 回归（inf/+1、clearance、cbf_margin=(dmin-extra)/norm、both 顺序、clamp±1、负 h 保留）。全 PASS。
  - ⚠️ 用 `cbf_margin` 而非 filter 介入量（后者撤 filter 恒 0 → 分布偏移，§2.1 已否决）。
- **回归验收**：cbf_test.py 全 PASS（含 t7）+ obstacle_geometry_test.py 全 PASS。
- **GPU 冒烟**：① obs_safety=none 默认 + eval_ckpt 加载 pg6q5ji5(62 维) 成功运行 = **none 位兼容**（62 维策略正常 forward，无形状错）；② obs_safety=cbf_margin train 1iter/32k 帧 → **obs (1024,1,63) 正确**、无 NaN/形状错、EXIT0、checkpoint_final 落盘。
- **坑记录**：把长训管道接 `| head` 会因 SIGPIPE 提前杀掉训练（日志停 startup）；长训一律 `> log 2>&1` 完整重定向。

### New2-probe = from-scratch 课程探针（2026-09-07 00:4x 启动，01:0x 完成）
- run：wandb `new_reward`，**`NavVel-F1-New2-obsCbfMargin-curriculum` = run `3x4p3ryw`**，log `/tmp/navvel_new2_curriculum_obsCbfMargin_12M.log`。
- 配方 = **忠实复现 New1 pg6q5ji5 解析后配置**（num_scene=16、spawn ±2.2、edge4、near1、curriculum [2,4,8,16] enabled from-scratch、cbf hybrid dual 0.1/0.1 σ0.5 brake-off、wf6、arrive 30+30t、to40、smooth0.2、ent0.05、12M、save_interval=100、render_eval=false）+ 唯一新增 `task.obstacle.obs_safety=cbf_margin`。
- **训练结果**：from-scratch 课程 **2→4→8→16 全通关**（~12M 达 16 障，节奏 ≈ pg6q5ji5）。obs (1024,1,63) 正常、无 NaN。
- **确定性 eval @D2-16（16 障, rollout 600, obs_safety=cbf_margin）**：
  | ckpt | ON arr/coll/joint | OFF arr/coll/joint |
  |---|---|---|
  | final(11.99M) | 0.926 / 1.0% / **0.920** | 0.912 / **41.6%** / 0.581 |
  | 9.86M | 0.920 / 0.9% / 0.917 | 0.893 / 43.3% / 0.564 |
  | 6.58M | 0.924 / 0.6% / 0.920 | 0.924 / 40.0% / **0.600** |
- **对照 pg6q5ji5（同配方无 obs_safety）**：ON joint 0.930/coll 0.9%；OFF joint 0.588/coll **41.0%**。
- **判定：❌ internalize 未出现**。OFF coll 40.0–43.3% ≈ 基线 41.0%（无分离），OFF joint 0.56–0.60 ≈ 基线 0.588；ON 完全复现（0.92，≥0.85 达标但非新增）。**obs_safety=cbf_margin 通道单独（hybrid dual 训练, runtime filter 在）不足以触发 OFF 安全** → 机制确认：训练中 filter 仍是"安全背锅"，给 h 通道无梯度压力让它去守边界（filter 在临界处兜底 → 策略无动机避 h<0）。
- **下一步候选（待用户拍板）**：① hybrid 训练但**禁 runtime filter**（= 让 unsafe 真撞, h 通道 + edge 罚成唯一安全反馈；观察 F1 强 shaping 下是否学守 h 而非塌）② 在 reward core 直接罚 `relu(-h)`（把 CBF 边界余量变成梯度目标, 强于仅入 obs）③ obs 课程 gate（h 收紧才升密度）④ 接受带 filter 交付（同 New1）。建议先 ②（量级小、直接给 h 梯度）或 ①（撤 filter from-scratch 复训短探针）。

### New2 E1/E2/E3 三路并行（2026-09-07，用户拍板「1,2,3 同时进行 + GPU 多进程；E3 加长帧数」）
- **代码 commit `ac87dd8`**（叠加 f9566f8 之上）：
  - **E1 基础**：`nav_vel.py` reward core 加 `task.cbf.h_penalty_weight`(默认 0)：罚 `w_h*relu(-h)`, h=dmin-cbf_extra(0 穿越=filter 介入边界) → 守边界梯度(治 filter 兜底下 obs 通道无压力)。
  - **E3 基础**：`utils/nav_curriculum.py` + `nav_vel.py` 加 curriculum **margin gate**(默认关)：`task.curriculum.margin_gate` + `margin_frac`(0.5) + `margin_clearance`(0.1)。提升除 success/collision 外还要求窗口 margin_ok_rate≥margin_frac；margin_ok=整窗 ep_min_clearance≥0.1(≈cbf_extra→h≥0=从未进 filter 介入区=internalize 语义)。`_reset_idx` 在 commit_layout 重置前读 ep_min_clearance。nav_curriculum 环形缓冲三路折叠 + margin_ok_rate 属性。
  - `NavVel.yaml` 新键；`obstacle_geometry_test.py` margin gate CPU 回归(阻塞/提升/关不受影响)。CPU cbf_test+obstacle_geometry_test 全 PASS；GPU 组合冒烟(hybrid+hpen40+margin_gate 1iter/32k) obs 63 无 NaN/EXIT0。
- **三路并行启动（wandb `new_reward`，全 from-scratch 课程 [2,4,8,16] + obs_safety=cbf_margin + num_scene16/±2.2 同 pg6q5ji5 配方）**：
  | 探针 | 变体(相对探针 3x4p3ryw) | 帧数 | wandb 名(待回填 id) | log |
  |---|---|---|---|---|
  | E1 | + `task.cbf.h_penalty_weight=40` (hybrid dual 不变) | 12M | NavVel-F1-New2-E1-hpen40 | /tmp/navvel_new2_E1_hpen40_12M.log |
  | E2 | cbf.mode=**reward_only**(训练无 runtime filter) + edge8 + reward_weight=0.5 | 12M | NavVel-F1-New2-E2-noFilter-ro-edge8 | /tmp/navvel_new2_E2_noFilter_edge8_12M.log |
  | E3 | + curriculum **margin_gate**(frac0.5/clearance0.1) | **30M(加长)** | NavVel-F1-New2-E3-marginGate-30M | /tmp/navvel_new2_E3_marginGate_30M.log |
  - GPU：3 进程 ~15GB/32GB。对照 = 探针 3x4p3ryw(obs_cbf_margin 无附加, OFF coll 41.6%) 与 pg6q5ji5(none, OFF coll 41.0%)。
  - 验收：跑完 §4.2 确定性 eval ON/OFF @D2-16(obs_safety=cbf_margin 一致) + 中间 ckpt 取峰；internalize = OFF coll <34.1% 且 OFF joint≥~0.6。

### E1/E2/E3 训练完成情况（2026-09-07，初步）
- **E1（h_penalty=40, hybrid dual, 12M）run `rhs4ex42`**：课程 **2→4→8→16 通关**（h 罚不阻收敛）。train Final Eval(随机)@16: arrival 0.741/coll_ep 1.07%。
- **E2（reward_only 无滤波, edge8, w1=0.5, 12M）run `hulaimgx`**：**卡 2 障**（整窗 curriculum_level 恒 2.0，从未升 4）→ 无滤波 from-scratch 学不动高密度(2 障 eval arrival 0.76/coll_ep 6.3%)。印证 M2-era「reward_only 弱、需 warm」；E2 在 12M from-scratch 预算下不可达 16 障 → internalize 无法在此臂检验。
- **E3（margin gate frac0.5/clearance0.1, hybrid dual, 30M）run `9wyijocs`**：30M 完成，课程 **2→4→8→16 通关**（margin_frac=0.5 门不严, 16 障 ~33 窗）；final eval arrival 0.706/coll_ep 1.07%(随机)。

### E1/E2/E3 确定性 eval @D2-16 判定 ❌ internalize 仍未出现（2026-09-07）
| run(变体) | ckpt | ON arr/coll/joint | OFF arr/coll/joint |
|---|---|---|---|
| pg6q5ji5(none 基线) | final | 0.936/0.9%/0.930 | ~/41.0%/0.588 |
| 3x4p3ryw(cbf_margin) | final | 0.926/1.0%/0.920 | 0.912/41.6%/0.581 |
| **E1**(+hpen40) | final | 0.918/0.9%/0.911 | 0.953/**38.3%**/0.614 |
| E1 | 6.58M | 0.939/1.2%/0.928 | 0.916/42.6%/0.573 |
| E3(margin gate) | final | 0.936/1.0%/0.932 | 0.897/**44.3%**/0.556 |
| E3 | 16.4M | 0.881/1.1%/0.876 | 0.889/41.3%/0.585 |
| E2(reward_only,卡2障) | final | 0.927/1.0%/0.920(带filter) | 0.917/41.2%/0.588 |
- **判定**：三路全 < 34.1% 目标。**E1(final) = 轻微最佳 OFF（coll 38.3%, joint 0.614, OFF arrival 0.953 全表最高）**，较 41.0-41.6% 基线降 ~3pt 但远未内化；E3(final) OFF coll 44.3% 更差（margin_frac 0.5 门太松 + 长训过训）；E2 卡 2 障不可比。**结论收敛：h 罚/margin gate/obs 通道 + filter 兜底各自都不足以让策略在撤 filter 后安全（ON coll ~1% vs OFF 38-44% = filter 仍 ~40× 决定性组件）**。E1 方向（给 h 梯度）唯一微降 OFF coll，值得 E1-v2 强化（罚窗加 buffer + 更大 w_h）。
- **E1-v2 候选**：relu(-h) 只在 h<0 才罚(fire 少, filter 兜底几乎不让 h 深负) → 改成罚 relu(h_keep−h)（h_keep≈0.1-0.2, 提前在接近 filter 边界时给梯度, 类似 CBF 版 near_slowdown）或直接罚 relu(r_keep−dmin) 且 w_h 加大 + 配 E3 margin gate(frac 提高)。

### New2 E1-v2（2026-09-07，用户拍板「跑 E1-v2，并做好记录」）
- **代码 commit `7bd2d3d`**：`utils/cbf.py` 加 `h_boundary_penalty(dmin, extra, buffer, weight)=weight*relu(buffer-h)`, h=dmin-extra（buffer=0 → E1 原版 relu(-h) 逐位兼容；buffer>0 → 软墙在 dmin<extra+buffer 提前罚, 类 CBF 版 near_slowdown）。`nav_vel.py` reward core 改调该函数 + `task.cbf.h_penalty_buffer`(默认 0)。`NavVel.yaml` 新键。`cbf_test.py` 加 **t8** CPU 回归（buffer0 兼容/提前 fire/软墙边界 0/无障 inf→0）全 PASS。GPU 冒烟(hpen60+buf0.15,1iter) obs63 EXIT0。
- **两变体并行启动（wandb `new_reward`, from-scratch 课程 [2,4,8,16] + obs_safety=cbf_margin, 12M, 其余同 E1 配方）**：
  | 变体 | h_penalty_weight | h_penalty_buffer | run(待回填) | log |
  |---|---|---|---|---|
  | E1v2-a | 40 | 0.1 | xlfgrtwk | /tmp/navvel_new2_E1v2a_hpen40_buf0.1_12M.log |
  | E1v2-b | 60 | 0.15 | (待回填) | /tmp/navvel_new2_E1v2b_hpen60_buf0.15_12M.log |
  - 对照：E1(rhs4ex42) OFF coll 38.3%/joint0.614 为当前最佳；基线 41.0-41.6%。
  - 验收：跑完 §4.2 确定性 ON/OFF @D2-16 取峰；internalize = OFF coll <34.1% 且 OFF joint≥~0.6。

### E1-v2a/b 确定性 eval @D2-16 判定 ❌ 未超 E1（2026-09-07）
| run(变体) | ckpt | ON arr/coll/joint | OFF arr/coll/joint |
|---|---|---|---|
| E1(hpen40 buf0) | final | 0.918/0.9%/0.911 | 0.953/**38.3%**/0.614 ⭐当前最佳 OFF |
| E1v2-a(hpen40 buf0.1) `xlfgrtwk` | final | 0.918/1.9%/0.904 | 0.921/43.8%/0.560 |
| E1v2-a | 9.86M | 0.926/1.7%/0.915 | 0.928/42.9%/0.570 |
| E1v2-a | 6.58M | 0.918/1.8%/0.907 | 0.918/41.4%/0.584 |
| E1v2-b(hpen60 buf0.15) `v4idr5vv` | final | 0.911/1.4%/0.904 | 0.927/**39.2%**/0.606 |
| E1v2-b | 9.86M | 0.891/1.1%/0.882 | 0.915/40.6%/0.591 |
| E1v2-b | 6.58M | 0.919/0.9%/0.912 | 0.930/40.9%/0.589 |
- **判定**：buffer 变体未超 E1（E1v2-a final OFF 43.8% 更差; E1v2-b 39.2% ≈ E1 略逊）。**加 buffer 提前罚在有 filter 训练下反而略增 OFF coll**（策略贴软墙飞行, 撤 filter 仍依赖 filter 兜底）。**E1 家族最佳仍 = E1 (hpen40/buf0) OFF coll 38.3%/joint 0.614, 全部 < 34.1% 目标未达 → internalize 依旧不出现**。
- **New2 全谱收敛结论（obs 通道 + h 罚 ±buffer + margin 课程 + reward_only 无滤波 from-scratch 均失败）**：带 filter 训练时策略学不会"撤 filter 也安全"——filter 兜底是根本障碍。若要再试 internalize，方向需**训练期随机 filter dropout**（部分 episode 撤 filter 让 unsafe 真撞产生强梯度）或**接受带 filter 交付**（ON 0.90-0.93/coll~1% 稳定口径）。

<!-- 动手后按时间追加：日期/时间、run、配方、结果、判定 -->

---

## 7. 交接给下一个 agent 的「先读清单」
1. `drones/new1_plan.md` **顶部阶段性总结**（New1 全貌 + 机制结论）
2. `drones/f1_recipe_and_runs.md`（配方速查 + run 时间线总表 + 里程碑表）
3. 本文件 §2 设计（obs 加什么 / 为什么 / 代码落点）+ §3 验收 + §4 协议
4. 代码：`nav_vel.py::_set_specs`（obs spec 维度）+ `_compute_state_and_obs`（obs 拼装）+ `_compute_reward_and_done`（reward core/f1）；`nav_vel_obstacles.py::min_clearance/build_obs`；`cfg/task/NavVel.yaml`（默认键）；`utils/cbf.py`（safety_radius_extra/cbf_safety_radius）
5. repo memory：`/memories/repo/omnidrones-navvel-m2.md`（完整 run 时间线/结论/坑）
