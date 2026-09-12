# M2 实施规划：静态障碍避障导航 + CBF1 训练期接入（naive vs CBF 双模型对比）

> 创建时间：2026-09-04
> 目的：**给"新的 agent 会话"做 M2 阶段项目构建的自包含执行蓝图**。
> 输入文档（重要程度排序）：
> - 前置经验：`drones/m1_navvel_plan.md`（M1 已达成，**必须先把它的教训带到 M2**，见 §1）
> - 障碍设计参考：`drones/navvel_obstacle_migration_guide.md`（M2 障碍机制详细设计/公式/风险，**引用为主、不重复抄全文**）
> - CBF-RL 方法参考：`drones/how2use.md` §3.3 / §4.1 / §4.5（CBF-RL 论文 ICRA2026、arXiv:2510.14959、闭式滤波 + reward core、4 臂消融模板）
> 仓库：`/home/lz/lzspace/drones/OmniDrones`（分支 `feat/crazyflie-pidrate`，HEAD=`75e5ed3`，tag=`m1-achieved`）
> 运行：`conda activate lz_env`，命令在 `OmniDrones/scripts/`，wandb 项目 `fly-hust/RL90`
>
> ⚠️ **本文件是"规划/实施指导"，不是执行记录**。命令为"待执行"，动手后把 run id / 结果 / 状态回填到 §11。

---

## ⭐ 会话总结与下一步（2026-09-05 23:0x 追加；D2-16 CBF reward 调优全链路收官——新会话先读这一节，再按需查 §11/#7-#10）

### A. 本次 agent 会话做了什么（19:0x→23:0x，全部用户拍板推进）
1. **问题链**：D2-16（16 障/±2.2m/obs 最近-8）四臂 80M 后 hybrid 避撞放弃到达 → 一路迭代：`penalty_src=correction`（罚滤波纠偏量，commit `deb97b7`）→ 20M λ 扫描 → **shaping 增强（B）**：`reward_pbrs_weight` 2→8 探针/网格 → w8 全臂公平重训 → w8 λ 网格 → CBF-RL 论文 Table II 对照（`navvel_rl_interface.md` §3.6/3.7）→ **论文式高斯平滑 correction**（`penalty_src=gaussian`，commit `afc6fa2`）→ **用户 value_loss→0 峰值提问 → mid-ckpt 重测 → 推翻"corr 追不上 filter"误判** → 峰值公平终表 + 轨迹图 `figures/d2_peak_trajectory.png`。
2. **终局交付候选（peak 口径 vs final 口径，二者 joint 无显著差）**：
   - filter_only w8 @20M（`204342-vaa0vtzz` final）：0.806/2.2%/0.789 —— **爬升型**，final 即峰、无需早停；
   - corr-hybrid w8 λ0.05 @6.5M（`204342-mu9vegr8` ckpt_6586368）：0.798/1.7%/0.786 —— **早峰型**，需早停取 6.5M，训练量仅 1/3、碰撞更低。
3. **git 收尾**：`feat/obs-window`（含 obs-window/num_scene、render_eval、penalty_src nominal/correction/gaussian、plot 脚本）已并入 `feat/crazyflie-pidrate`，tag=`d2-16obs-achieved`（本轮执行）。

### B. RL 训练经验教训（本会话新沉淀，值得固化）
1. **reward-core（软罚/纠偏类）是"早峰快退"型**：确定性峰值出现在 ~6.5M，之后过训退化（λ0.2 gaussian：6.5M 0.763→20M 0.631）。**必须周期 mid-ckpt eval + 早停取峰值**；只 eval 20M final 会系统性漏判（本会话差点把 corr 判成"追不上 filter"）。
2. **value_loss→0 ≠ policy 收敛/最优**：critic 训练早期即收敛（0.8→0.0002），policy 后期仍漂移（熵缓降、shaping 单向驱动、reward-core 信号后期稀疏）→ 后期看"策略漂移/过训窗口"而非 value 拟合度。
3. **强 shaping(w) 是"推力主源"，与"罚滤波纠偏的 reward-core"抢同一自由度**（shaping 奖励猛冲、correction 罚被拦）→ **臂序随 w 反转**：w2 下 corr hybrid(0.669)>filter_only(0.627)；w8 下 filter_only(0.789)≈corr@6.5M(0.786)、>corr@20M(0.708)。纯滤波 + 强前向 shaping 是最优组合之一。
4. **shaping 权重有甜点**（w=8 peak，w≥10 回落）；w 加大主要利好 filter_only（0.627→0.789，+16pt）。
5. **correction 惩罚形状**：线性 λ·corr 对大纠偏过罚；**论文式高斯核** λ(1−e^{−corr²/σ²}) 饱和到 λ 更稳（同 λ +8~11pt）；σ=0.5（≈0.28·v_max）标定合理。
6. **CBF 权重"小 λ 微调"**（0.05–0.1）而非论文式 ×100：四旋翼 + D2 高频下大 λ 保守塌陷（arrival 卡 0.44–0.49 加长救不回）。
7. **单点 eval 有 ~3–5pt run 间方差** → 同配方复跑 + 邻点(19.7M vs 20M)一致性判断，勿单点定论。
8. **运维**：多会话并发同一 GPU/仓库会撞车（他人用 `penalty_sigma` 键先启动、实际跑 nominal，须 kill 重跑）；4 训练并行 Final-Eval 渲染 OOM → `+render_eval=false`；确定性 eval ~18GB 只能串行（勿与训练并行）；hydra 参数勿塞 shell 双引号变量（单引号变字面→LexerNoViableAltException）。
9. **一以贯之**：取"峰值 ckpt"而非"final"是本项目最稳实践（熵塌缩别盲加帧 + reward-core 早停取峰同源）。

### C. 下一步实验方向启发（来自本会话 + CBF-RL 论文对照）
1. **训练管线改造**：reward-core 短训场景内置"周期性 mid-ckpt eval + 自动选峰/早停"（save_interval 降到 ~3M，每 3M 确定性 eval，训练结束自动取峰值 ckpt 上传）→ 避免再次系统性漏峰。
2. **reward-core 部署策略**：corr-hybrid λ0.05 w8 @6.5M 作为"轻量/低碰撞"交付模板（3× 训练效率）。
3. **论文式两项组合 reward core**：`viol（nominal 项）+ gaussian correction 项` 同时启用（现为互斥的 penalty_src），比例可配——还原 CBF-RL r_cbf 完整形式；σ/λ 用本次标定值起步。只动 CBF 项 → 无需全臂。
4. **r_progress 归一化**（÷v_max·Δt）重标定 shaping 与罚面相对尺度（论文 r_cbf×100 能撑的前提是 progress 每步 +20）——动共享奖励 → 需 4 臂同步重训。
5. **鲁棒性验证（论文卖点）**：扰动/风扰/初始化扰动下 CBF 滤波 vs naive 的碰撞鲁棒性；min_clearance 分布对比。
6. **爬升型上限**：filter_only w8 加长 40M 看是否 >0.789（filter 无 reward-core 退化机制，可能仍升）；w2/w8 中间档 shaping 扫描补全 w-joint 曲面。
7. **D2 产物落袋后**：obs 滑动窗口/num_scene 已并入主线 → 后续 M3（动态/编队）或鲁棒性实验可直接在其上做；naive 在 D2-16 高密度已被证死（纯 PPO 密度上限），主线叙事 = "滤波安全层 + shaping/进度塑形驱动性能"。

---

## 0. TL;DR 与核心决策回答

**先回答你的问题——「同时实现障碍+CBF，还是先实现静态障碍？」**

> **推荐：先实现"纯 PPO 静态障碍导航"（= naive / 无 CBF 模型），再把 CBF1 作为"可插拔安全层"接入训练、训出第二个模型（CBF 组），两模型在相同难度下对比。不要"一上来就同时实现"。**

理由（不只是进度考虑，也是实验设计本身的要求）：
1. **CBF 组的对照物（naive）本身就是"纯障碍 PPO 基线"**——你想要的"两个模型一个带 CBF 一个不带"，其"不带"的那个就是必须先做出来并验证的静态障碍基线。顺序天然如此，不是可选项。
2. **CBF 滤波与 reward core 的输入 = 障碍机制产出的真值**（$p_o,r_o$、激活槽、几何距离）。没有障碍 env，CBF 无米下锅；两个功能必须解耦但 CBF 依赖障碍。
3. **归因干净**：先让"障碍机制 + 无 CBF"单独收敛（排除 env bug），再加 CBF 看增量；否则机制问题会被误算成"CBF 无效"。这也正是 cbf-rl-demo 把 `naive` 设为第一臂的原因。
4. **不必等 8 障全收敛才上 CBF**：障碍机制冒烟通过 + 2~4 障基线稳定后，即可在同难度下同时训 naive 与 CBF 两臂（各自走课程或锁级），省时且对比有效。

**对比怎么突出 CBF 价值（实验设计要点，勿做"简单场景对比"）**：
- 在 **2 障这种简单场景**，naive 可能也 100% 无碰撞 → CBF 增益不明显。**主战场放在 4–8 障 / 窄缝 / 目标紧贴障碍后方**的难度上；
- 除成功率/碰撞率外，加测对 **CBF 敏感**的指标：**CBF 违反次数、最小净空(min_clearance)分布、贴障保守度、以及"扰动/初始化扰动下的碰撞率"**（CBF-RL 声称对不确定性更鲁棒 → 用随机起点/风扰验证）；
- CBF-RL 论文还声称 reward core **提速收敛** → 记录两臂"达到同一成功率所需帧数"，作为附加亮点。

**双模型 vs 4 臂**：主线 = **A(naive) vs B(hybrid: 滤波+reward core)**（你的需求，也最贴近部署形态）；若时间允许，再按 cbf-rl-demo 扩成 4 臂 `naive / filter_only / reward_only / hybrid`（config 已按开关设计，见 §5.4）。

---

## 1. 前置经验要点（M1 的教训，M2 必须继承，别重复踩坑）

> 对应 `m1_navvel_plan.md` §9 执行记录（2026-09-04 晚已全部收敛）。

### 1.1 必须直接复用/已修复的事实
- **✅ Crazyflie Lee 控制器增益已修复**（commit `75e5ed3` / tag `m1-achieved`）：`lee_controller_crazyflie.yaml` 已调低 attitude/angular-rate 增益（`[0.0014,0.0014,0.0022]` / `[0.00028,0.00028,0.00043]`）。**M2 直接用，不要再动**（除非发现新的稳定问题）。
- **✅ 已被证明有效的"收敛配方"（fixctl-B，run `9eb3e923`，arrival 99%）**：
  `soft_respawn=true` + `survival_penalty_weight=0.1` + `reward_pbrs_weight=2.0/γ=0.995` + **死亡惩罚全 0**（crash/oob/timeout/early_death=0）+ `vel_limit.max_vel=1.8`。
  ⚠️ **重要**：当前 `cfg/task/NavVel.yaml` 里那 4 个惩罚键仍是 `20/20/10/2`（M1 早期实验值），fixctl-B 是靠 CLI 清零跑的。**M2 第一步要把 yaml 默认值改成上述"已验证配方"**（§7.1），否则新会话/新 run 会默认带惩罚重演 Stage0-fix 的失败（return=−110、熵不降）。
- **✅ vel_limit 已实现**：`VelController` 的模长限幅(max_vel=1.8)+yaw 限幅早已落地（commit `69b50ad`，`train.py/play.py/eval_ckpt.py` 三处装配）。**迁移指南 §8.3 描述的"尚未实现"已过时，无需再做**。
- **✅ 调试/验证工具已入库**：`scripts/{expert_probe,vel_probe,motor_hover_probe}.py`（控制链分层探针）。M2 加障碍后可用 `expert_probe` 验证"无碰撞直飞路径存在时专家能否通过"（控制链回归）。

### 1.2 M1 方法论教训（M2 继续用）
1. **软重置(soft_respawn) + 多命 vs 一次性大惩罚冲突**：600 步内多次重生时，大的一次性死亡惩罚会堆积成 return≈−110、淹没导航信号。M2 的**障碍碰撞惩罚同理要保守标定**（每 edge 小惩罚即可，见 §4.3/§5.3）。
2. **成功率/课程门槛只看"真终止原因"，不看 return**（`EpisodeStats` 只统计真终止；随机目标大多 truncated）。
3. **eval 用 `eval_ckpt.py` 确定性评估**（固定 rollout_steps、锁级、CLI 覆盖与训练一致的奖励键），别只看 train 打印；`|rpos|<0.1`、`inside radius` 等原始计数比均值更有判别力。
4. **新增 obs 维度 = 旧 checkpoint 不可续**：障碍 obs 会把 30 维 → 62 维，M1 的 ckpt 无法 load（正常，重训）。
5. 速度层实际能较好跟踪（Lee 修复后）：`+X 1.2m/s` 实测 `vx≈1.03`、方向对齐 93% → **CBF 作用于"速度指令"才有意义**（内环能跟得上被投影后的速度）。

---

## 2. 目标与验收

### 2.1 阶段划分（避免与迁移指南/ how2use 的编号混淆，本 plan 用 M2-x）

| 里程碑 | 内容 | 验收（量化） |
|---|---|---|
| **M2-0** | 把 M1 已验证配方 bake 进 `NavVel.yaml` 默认值（§1.1/§7.1） | 无障碍冒烟 1 iter 无错；等价 fixctl-B 复跑（可选 2M 验证 pos_error↓） |
| **M2-1** | 障碍机制实现（spawn/obs/奖励/碰撞/终止/课程）+ 冒烟（§4/§7） | 2 障 `max_iters=1` 无错、stats 全出；几何/物理碰撞一致 |
| **M2-2** | **naive（无 CBF）纯障碍导航收敛**：课程 2→4→8 障（§7） | 2 障到达率≥80%、碰撞率<5%；8 障到达率≥80%（协商可 ≥60%，见 §11）；`min_clearance` 分布合理、无 NaN |
| **M2-3** | CBF1 实现 + 单元/探针验证（§5） | 单测/探针证明：危险速度被投影、安全速度不变；`mode=none` 与 naive 行为逐位一致 |
| **M2-4** | **双模型同难度对比：A(naive) vs B(hybrid)**（§5.6/§8） | 同难度锁级评估：B 碰撞率↓/成功率≥A；CBF 违反≈0；报告成功率/碰撞/到达时间/保守度/鲁棒性 |
| M2-5（可选） | 扩 4 臂 naive/filter_only/reward_only/hybrid | 见 how2use §4.5（M2）：`naive < filter_only ≈ hybrid` 的合理趋势 |

### 2.2 对比报告指标（A vs B 同表）
成功率、碰撞率（episode 级+edge 事件数）、到达时间均值/分布、平均速度、**CBF 违反次数**、**min_clearance**（最小净空均值/分布，衡量保守度）、扰动鲁棒性（随机起点/初始姿态/风扰下碰撞率）、到达同一成功率所需帧数（CBF-RL 收敛提速论点）。

---

## 3. 总体架构

```mermaid
flowchart LR
    subgraph env (nav_vel.py + 子模块)
      O[ObstacleManager<br/>spawn/布局/碰撞/obs] -->|p_o,r_o,active| R
      C[Curriculum<br/>0->2->4->8 成功率门槛] --> O
      R["_compute_reward_and_done<br/>导航奖励 + 障碍项 + 碰撞终止"]
    end
    subgraph 动作管线
      P[PPO 策略 v∈R4] --> F[CBF1 滤波(可选 cbf.mode≠none)]
      F --> V[VelController(限幅1.8)]
      V --> L[Lee(增益已修) → 转子]
    end
    R --> P
    P -.pre-filter 违反量.-> R[reward core r_cbf]
```

**模块划分（延续迁移指南 §5.4 要求：obs 拼装 与 碰撞判定 分离，为感知化预留）**
- `omni_drones/envs/single/nav_vel.py`：接入 obstacle block / CBF 开关 / 课程。
- `omni_drones/envs/single/nav_vel_obstacles.py`（推荐新模块，纯逻辑可单测）：布局采样、碰撞/净空、obs 拼装。**CBF 也消费它暴露的 `p_obs/r_safe/active`**。
- `omni_drones/utils/nav_curriculum.py`（推荐新模块）：课程调度（引用迁移指南 §7）。
- `omni_drones/utils/cbf.py`（**M2 新增核心**）：一阶 CBF 滤波（闭式/迭代）+ reward-core 工具（§5）。
- `cfg/task/NavVel.yaml`：`obstacle:`/`curriculum:`/`cbf:` 段 + bake-in M1 配方（§7.1）。

---

## 4. 静态障碍机制实现（M2-1/M2-2）

> **设计细节、公式、风险全部以 `navvel_obstacle_migration_guide.md` §3–§8 为准**，本节只给"相对该指南的更新/修正 + 落地清单"，避免重复。

### 4.1 相对迁移指南的更新（因为它写于 M1 未收敛时）
1. **指南 §1 的"Stage 0 无障碍收敛修复"已过时**（M1 已收敛）→ M2 跳过其 Stage0，直接用 M1 配方（§1.1）作为基础奖励，障碍项叠加其上。
2. **指南 §8.3 vel_limit 已实现** → 无需再做（§1.1）。
3. 指南 §8.2 的 `obstacle:`/`curriculum:` 配置段可直接采用（见 §7.1），但 **reward 默认值在其基础上调整为"软重置兼容"的量级**（§4.3）。
4. 指南 §4.3 的 `drone_radius=0.15`、`inflation=0.05`、`collision_margin=0.05`、`danger_radius=0.6`、`max_collisions=2`、`radius_fixed=0.30`、`K=8` 等**沿用**。
5. obs：现有 `30` 维 + 8 槽 `(3+1)×8=32` → **62 维**（指南 §5）。新增距离量按指南 §5.2 归一化（距离/5 截 [−1,1]、半径/0.5 截 [0,1]）。

### 4.2 落地清单（文件级）
| 项 | 落点 | 备注 |
|---|---|---|
| 障碍物理球 | `nav_vel._design_scene` 循环 K 个 `create_obstacle("/World/envs/env_0/obstacle_{i}", "Sphere", ...)` | kinematic + collision on；GridCloner 复制；`RigidPrimView` 形状需冒烟确认是 `(N,K)` |
| 布局采样 | `nav_vel_obstacles.py::sample_layout(pos, goal)` | 迁移指南 §4.2：候选网格 + 端点 margin + 互距约束，batch 化、兜底放宽；未激活槽移出场外 |
| obs 拼装 | `nav_vel_obstacles.py::build_obs(drone_pos)` → 归一化 K 槽 | **与碰撞函数分开**（§5.4 防感知化重构） |
| 奖励 | `_compute_reward_and_done` 叠加 §4.3 各项；每项原始贡献写进 stats（`term_obs_log/collision_edge/...`） | 标定方法论见迁移指南 §6.3 |
| 碰撞/终止 | `nav_vel_obstacles.py::collision_edge(...)`；`cumulative_collisions≥max_collisions` 时**软重置**并记 episode 结局=collision（见 §4.3） | 与坠地/OOB 一致走 soft_respawn，避免破坏 M1 收敛配方 |
| 课程 | `nav_curriculum.py` + `_reset_idx` 结算 | 迁移指南 §7（success=arrival 且本 episode 0 碰撞；滚动窗口；升档最少帧数） |
| stats | `collision_count/collision_rate/min_clearance/success_rate/curriculum_level/term_*` | 进 wandb / eval |

### 4.3 障碍奖励默认值（修正迁移指南为"软重置兼容"）
> 迁移指南 §6.2 的 `reward_crash/oob/timeout/early_death=20/20/10/2` 等是为"硬终止、一次性死亡"设计的——**M1 已证明与 soft_respawn 多命冲突**。故 M2 基础奖励 = M1 配方（惩罚 0），障碍专属项默认保守：

```yaml
obstacle:
  # ... 几何参数沿用迁移指南 §8.2 ...
  reward_obs_log_weight: 1.5      # 指南给 2.0；先小点看是否过度保守
  reward_obs_log_scale: 0.3
  reward_collision_edge: 2.0      # 每次新进入接触的边沿一次性惩罚(每步 O(1)量级, 别学 kaiwu 的 -2500)
  reward_early_death_weight: 0.0  # M1 证明与多命冲突 → 默认关; 如碰撞率不降再按指南公式小开(<1)
  reward_near_slowdown_weight: 0.5 # 近障朝障飞惩罚(可选, 默认小开)
```
- 碰撞超过 `max_collisions=2` 的 episode：软重置重生（**不硬终止**，保持 M1 收敛配方），但把该 episode 结局记为 `collision`（课程按此判失败）。
- 若发现软重置下"碰撞零后果导致策略穿障"（碰撞 edge 惩罚 2.0 不够），再上调 edge 惩罚或临时启用终止（保留两种开关在 yaml，便于 A/B 快速试）。

---

## 5. CBF1 设计与训练期接入（M2-3/M2-4，本 plan 的核心新增）

> 依据 how2use §3.3（CBF-RL 思想）与 §4.1（一阶 CBF 数学）。指南对 CBF 只留了 §11.1 接口占位——本 plan 把 CBF1 从"M3 占位"提前为"M2 内实现并训练期接入"，用于双模型对比。

### 5.1 一阶 CBF 数学（速度指令层，静态障碍 $v_o=0$）
安全集与距离函数（对激活障碍 $i$，判定半径 $r_{s,i}^{cbf}$ 见 §5.3）：
$$h_i(p)=\lVert p-p_{o,i}\rVert-r_{s,i}^{cbf},\qquad n_i=\frac{p-p_{o,i}}{\lVert p-p_{o,i}\rVert},\qquad \dot h_i=n_i^\top v$$
一阶 CBF 约束：$\dot h_i+\alpha h_i\ge 0 \iff n_i^\top v\ge -\alpha h_i$（静态），即**半空间**约束。

**闭式单障碍投影**（CBF-RL 离散闭式解；多障碍用迭代投影或小 QP，见 §5.2）：
$$v^\ast = v_{\text{nom}}+ \max\big(0,\; -\big(n^\top v_{\text{nom}}+\alpha h\big)\big)\,n$$

### 5.2 多障碍处理（batch、全向量化）
- 有 8 槽但激活 L 个 → 约束矩阵 $A\in\mathbb R^{L\times3},\ b=-\alpha h$（只取 active 槽）；
- 方案1（推荐初版）： **按最近距离降序的迭代闭式投影**（每次对最危险的未满足约束投影，重复 ≤3–5 次，`torch` 向量化，detach 中间梯度） 
- 方案2：小 **QP** `min_v ||v−v_nom||² s.t. A v ≥ b, ||v||≤v_max`（torch 可解或用固定迭代），多约束严格可行；
- 速度幅值本身已有 `VelController.max_vel=1.8` 兜底 → CBF 不必重复限幅，但投影后若超速交给 VelController。
- 全部对 active 槽操作；**active mask 从 `radius>0` 得出**，与 obs 同一来源，避免不一致。

### 5.3 安全半径（速度层必须含"内环带宽/制动"裕量）
由于低层是速度指令 → Lee（有控制滞后、非瞬间实现 $v$），CBF 判定半径应比几何碰撞半径大：
$$r_{s,i}^{cbf}=r_{drone}+r_{o,i}+r_{margin}+\underbrace{\frac{v_{\max}^2}{2\,a_{\max}}}_{\text{制动/内环裕量}},\qquad v_{\max}=1.8,\ a_{\max}\approx 2\,\text{m/s}^2(\text{实测/可调})$$
- `r_margin` 与制动项作为可调参数（yaml `cbf.r_safety_margin / cbf.use_brake_term`）；
- **注意**：观测/碰撞用几何半径（迁移指南 §6），CBF 滤波/奖励用 `r_s^{cbf}`——两套半径分开，文档里讲清楚避免混淆。

### 5.4 训练期接入的三种模式（= cbf-rl-demo 的臂），config 开关
```yaml
cbf:
  mode: none        # none | filter_only | reward_only | hybrid
  alpha: 1.0        # 收敛率(需调, 0.5~5)
  r_safety_margin: 0.1
  use_brake_term: true
  reward_weight: 1.0        # reward core 权重 λ
  filter_grad: detach       # detach | through (CBF-RL 两种都试过, 先 detach 稳定)
```
- **filter_only**：策略输出 $v_{\text{nom}}$ → CBF 投影成 $v^\ast$ → 进 VelController；投影只做安全修正，不改奖励。
- **reward_only / soft-CBF（reward core）**：不滤波，但在奖励里惩罚"违反"：
  $$r_{\text{cbf}}=\lambda\sum_{i\in\text{active}}\min\big(0,\ \dot h_i+\alpha h_i\big)$$
  用"滤波前"的 $v_{\text{nom}}$ 算违反量（否则策略学不到被罚的是自己输出）。也可在 $h<0$（已侵入）时额外罚。
- **hybrid**（= 模型 B 主线）：滤波 + reward core 同时开——对应 cbf-rl-demo 的 `--use_cbf_action_filtering --use_cbf_reward_penalty`。

### 5.5 落点（滤波插在哪）
- **推荐**：把 CBF 做成独立可导/可 detach 的函数模块 `utils/cbf.py::filter_velocity(p, v_nom, p_obs, r_safe, active, alpha) -> v_safe`，然后：
  - 训练/回放/评估共用同一函数；
  - 挂接点在**动作到达 VelController 之前**。两个可选实现位：
    - (a) 在 `nav_vel.py` 的 `_pre_sim_step` 里先读策略原始动作再投影（简单，天然 vectorized；能拿到 drone_state/target/障碍真值）；
    - (b) 做成 torchrl `Transform`（`CBFVelocityFilter` 放在 VelController 之前），复用性好、可记录滤波量，但需处理 `in_keys`/状态缓存，工作量大。
  - 建议 **先 (a)** 打通并出对比结果，若效果好/要正式化再抽 (b)。**滤波输入障碍用真值**（同 8 槽真值 obs 的数据源）；感知化留 M2 之后（迁移指南 §5.4）。
- reward core 的违反量在 `_compute_reward_and_done` 内用同一 `cbf.py` 计算（**用滤波前 v_nom**）。

### 5.6 双模型实验设计（M2-4）
- 两个 run 共享除 `cbf.mode` 外**一切**：seed、障碍难度（锁级或各自同课程）、奖励、超参、帧数；
- 建议对比在 **4 或 8 障 / 窄缝 / 目标紧贴障后** 的难度下做（简单场景 naive 也安全，看不出差异）；
- run 命名：`NavVel-obs-L{lev}-naive-{N}M` vs `NavVel-obs-L{lev}-cbfhybrid-{N}M`（wandb RL90）；
- 报告见 §2.2 指标表，含 CBF 违反次数与扰动鲁棒性。

---

## 6. 障碍 vs CBF 的观测/几何接口（一致性要求）

- CBF、奖励、碰撞**三者必须用同一份"激活障碍真值"**（`ObstacleManager` 暴露 `p_obs (N,L,3), r_safe (N,L), active (N,L)`），只是各自用不同判定半径（几何 vs $r^{cbf}$）；
- 策略 obs 的 8 槽 **不带 CBF 半径**（obs 喂原始 $r_o$），避免策略对"安全滤波器内部参数"过拟合；
- 归一化量（距离/5、半径/0.5）只在拼 obs 时做，CBF/奖励用原始米制量。

---

## 7. 配置与代码实施清单

### 7.1 `cfg/task/NavVel.yaml`
1. **M2-0（先做）**：把死亡惩罚默认改成 0（`reward_crash/oob/timeout/early_death=0.0`），与 fixctl-B 一致（软重置配方）。可留注释说明"要硬终止惩罚时 CLI/此处开，M1 已证与软重置冲突"。
2. 新增 `obstacle:`（迁移指南 §8.2 + §4.3 修正默认值）、`curriculum:`（迁移指南 §8.2：levels [0,2,4,8]、initial_level 0、门槛 0.80、窗口 3000、min_frames 2M）、`cbf:`（§5.4）。

### 7.2 `nav_vel.py` / 子模块改造点
| 方法 | 改动 |
|---|---|
| `__init__` | 读 obstacle/curriculum/cbf；建 ObstacleManager/Curriculum/CBF 句柄；stats_spec 增键；obs 维度 30→62 |
| `_design_scene` | K 个 kinematic Sphere（§4.2） |
| `_set_specs` | observation 62 维；stats 增 `collision_count/collision_rate/min_clearance/success_rate/curriculum_level/cbf_violation/term_*` |
| `_reset_idx` | 采起点/目标 → level → sample_layout → 摆位/移出 → 重置碰撞计数与课程结算（结算在重置前消费上一 episode done reason） |
| `_compute_state_and_obs` | 追加障碍块（§4.1-5） |
| `_pre_sim_step` 或动作路 | `cbf.mode!=none` 时先滤波再交 VelController（§5.5） |
| `_compute_reward_and_done` | 叠加障碍奖励 + reward core（filter 前 v_nom）+ 碰撞边沿；结局 reason 缓存供课程 |

### 7.3 训练命令模板（from `OmniDrones/scripts/`）
```bash
# M2-0 冒烟(无障碍, 验证 bake-in 配方)
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=disabled max_iters=1

# M2-1 障碍机制冒烟(锁 2 障=level 1)
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
    task.curriculum.initial_level=1 max_iters=1

# M2-2 naive 课程从 level1 起正式训(让它自己升 2->4->8)
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=online wandb.project=RL90 \
    wandb.run_name=NavVel-obs-naive-L0-10M task.curriculum.initial_level=1 \
    total_frames=10_000_000 save_interval=50

# M2-4 CBF hybrid(同难度同帧数, 只加 cbf.mode=hybrid)
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=online wandb.project=RL90 \
    wandb.run_name=NavVel-obs-cbfhybrid-L1-10M task.curriculum.initial_level=1 \
    cbf.mode=hybrid total_frames=10_000_000 save_interval=50

# 锁级评估(8障=level3) —— 注意 eval 也传 cbf.mode 与训练一致
python -u eval_ckpt.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
    task.curriculum.initial_level=3 cbf.mode=hybrid \
    +checkpoint=/path/to/checkpoint_final.pt +rollout_steps=600
```
> `eval_ckpt.py`/`play.py` 也需在装配 VelController 前按 `cbf.mode` 套 CBF（与 train 同一函数），否则评估与训练不一致。

---

## 8. 执行顺序（新 agent 会话按此推进，逐步回填 §11）

1. **M2-0**：bake-in M1 配方（yaml 惩罚→0）→ 冒烟 →（可选）2M 复跑对照 fixctl-B。
2. **M2-1**：实现障碍机制（§4 + 迁移指南 §4–§8）→ 2 障冒烟 → 用探针/几何单测验证"碰撞判定/布局不重叠/obs 槽位"。
3. **M2-2**：naive 训练走课程 2→4→8（必要时锁级续训）→ 到 4 障先做一次确定性 eval（作为 naive 对照基准）。
4. **M2-3**：实现 `cbf.py`（§5）→ **单测/探针**：构造"朝障碍直飞"的危险速度，验证滤波把它投影到切向/远离；`mode=none` 时输出 == 输入（回归）→ 冒烟 `cbf.mode=filter_only/hybrid` 各 1 iter。
5. **M2-4**：在**与 naive 相同的 4/8 障难度**上训 CBF（hybrid），跑确定性 eval，产出 §2.2 对比报告。
6. **M2-5（可选）**：补 filter_only / reward_only 两臂，画 4 条曲线。
7. 每步通过后 git commit；全部达标后 **tag `m2-achieved`**。

---

## 9. 风险与坑（迁移指南 §10 相关项 + M1 新增）

1. ~~M1 未收敛~~（已解除，见 §1.1）—— 新风险集中在 **CBF 与软重置/障碍几何的交互**。
2. **数值照抄 kaiwu 会崩**（碰撞 −2500 量级）→ 障碍惩罚每步 O(1)、edge 小惩罚（§4.3）；reward core 的 λ 也要从 0.5–1.0 起试。
3. **CBF 半径 vs 几何碰撞半径错位**：obs/奖励/碰撞用几何，CBF 用含裕量的 $r^{cbf}$；写死一个常量两处引用会造成"obs 说没障、滤波器却说有"。统一从 `ObstacleManager` 出。
4. **CBF 过度保守**：$r^{cbf}$ 太大 / α 太小 → 到达率下降、绕远。用 `min_clearance`/到达时间监控；α 与 margin 做小网格扫描（探针最快）。
5. **策略穿障（filter_only 无 reward core）**：滤波只挡当步速度，策略可能学出"贴障高速"以对抗投影 → 需要 reward core 或 edge 惩罚配合（这正是 hybrid 优于 filter_only 的机理，报告里会呈现）。
6. **课程统计在软重置下的定义**：success=arrival 且 0 碰撞按"episode"计（跨重生累计碰撞），别按"条命"计（迁移指南 §7 + M1 §8.2-7）。
7. **RigidPrimView 形状 / 未激活槽移出写法** 需冒烟确认；不行就退化为 K 个单槽 view（迁移指南 §10.2-5）。
8. **8 障 × 1024 env 显存/物理**：超了就降 env 或按 level 复用模板（迁移指南 §10.2-6）。
9. **obs 维度变化 = 旧 ckpt 失效**（重训，正常）；课程跨 0/2/4/8 维度不变可续。
10. **CBF 梯度**：先 `detach` 求稳；如想"策略对滤波有梯度感知"再试 `through`（可导滤波）——两者都保留在 `cbf.filter_grad`。

---

## 10. 决策日志

| 决策 | 结论 | 依据 |
|---|---|---|
| 是否同时上障碍+CBF | **先静态障碍(纯 PPO/naive)，后 CBF 训练期接入** | §0：naive 是对照且 CBF 依赖障碍真值；归因干净 |
| 对比形态 | **主线 A(naive) vs B(hybrid)**；可选扩 4 臂 | cbf-rl-demo（how2use §3.3） |
| 主战场难度 | 4–8 障 / 窄缝 / 目标贴障后 | 简单场景 naive 也安全，CBF 增益不可见 |
| CBF 训练期接入 | 滤波(可选)+reward core(可选)，`cbf.mode` 开关；先 detach | CBF-RL（how2use §4.1） |
| 基础奖励 | M1 fixctl-B 配方（soft_respawn+survival+PBRS+惩罚0）bake-in | m1_navvel_plan §9 / run 9eb3e923 |
| 障碍碰撞后果 | 软重置+edge 小惩罚，课程记 episode 结局；不硬终止（除非不降） | M1 多命惩罚冲突教训 |
| 障碍参数/obs/课程 | **naive 已落地（见 §11 执行记录）**：多尺寸半径档 `[0.2,0.3,0.4]`（用户确认，替换固定 r_fixed=0.30）、NavRL 式可达性净空、K=8/0→2→4→8 沿用 | navvel_obstacle_migration_guide + NavRL 调研（2026-09-04） |
| 升 8 障碰撞门 | **先路1：`collision_rate_threshold` CLI 放宽到 0.10 放行升 8（yaml 默认仍 0.05）；8 障 success<~0.9 再退路2 提避障惩罚(edge 2→4~5)** | L4 碰撞 7–10% 平台难自行 ≤5%（奖励权衡、加帧无效）；用户 2026-09-04 拍板先到 8 再引 CBF（见 §11.2c） |

---

## 11. 本文件状态跟踪（完成后更新）

- [x] **M2-0 bake-in M1 配方 + 冒烟** —— ✅ 2026-09-04（惩罚默认清零；冒烟 level0 通过 145k fps）
- [x] **M2-1 障碍机制实现 + 冒烟** —— ✅ 2026-09-04（commit `aed2b1b`；单测全过 + 锁 2 障冒烟 + eval_ckpt 输出）
- [ ] **M2-2 naive 课程 2→4→8 收敛** —— 进行中：L2/L4 已达标；**8 障 naive 到顶**：路1 `a32os839`（arrival 0.814/joint 0.706/coll 0.155）为最佳；路C 续训 30M `fs1umcz2` 反而更差（0.643）。→ **naive-8 密度上限≈0.65–0.71，加帧无用**；建议以 `a32os839` final 为 A 臂基线进 M2-3 CBF（详见 §11.1/§11.2d）
- [ ] **M2-2b 路2（锁 L4 压碰撞 ≤5% 再升 8）** —— ✅ 完结（00:55）：四条 L4 加码路线均未 ≤5%（证伪，最优 `se8c08en` coll 6.6%）；Run-4 `lmhvaqka`(edge4+near1,20M) 升 8 障得基线 **arrival 0.824/joint 0.721/coll 0.165**；**Run-5/6 续训到 200M 级（`uc1t78uz`70M 中断 + `fg7sdmla`150M）确定性 eval 零改善**（0.824/0.718/0.161，熵塌缩 −4.8）→ **naive 8 障彻底穷尽，A 臂基线冻结=`lmhvaqka` final，下一步只剩 M2-3 CBF**（§11.2e）。⚠️ A/B 若用 edge4+near1，CBF hybrid 须同配置。
- [x] **M2-3 CBF1 实现 + 单测/冒烟** —— ✅ 2026-09-05 13:36（分支 `feat/cbf`，4 commits `62cf35a`→`4da896a`→`592998c`→`c7aebed`；单测全过 + none/filter_only/hybrid 三模式冒烟 + eval_ckpt 装配验证；`c7aebed` 修复 reward-core 符号 bug；见 §11.2f）
- [x] **M2-4 双模型 A/B 对比（同难度）** —— ✅ **Run-8/9 完成（14:10–14:13 确定性 eval）**：放宽（关 brake + ent0.02）后 **CBF 两臂 8 障全面碾压 A 臂**——Run-8 hybrid `ax7fs7gh` = arrival 0.916/joint 0.913/coll 0.006；Run-9 filter_only `orzg9g8f` = arrival 0.910/joint 0.907/coll 0.005；A 臂 `lmhvaqka` = 0.824/0.721/0.165 → **joint +19pt、coll ↓97%**、危险擦碰 217→10~21/1024、熵不塌缩。**hybrid≈filter_only（reward core 边际很小）**。回退链：Run-7（默认 brake）0.537/0.535/0.004 → 保守度诊断 → Run-8/9 达标（§11.2f）。**待用户决策：merge `feat/cbf`→`feat/crazyflie-pidrate` + tag `m2-achieved`，或补 reward_only 臂/加帧 filter_only**
- [ ] （可选）M2-5 4 臂矩阵 —— 待做
- [ ] （可选）M2-5 4 臂矩阵 —— 待做

### 11.1 执行记录（naive 静态障碍，2026-09-04）

**仓库**：`/home/lz/lzspace/drones/OmniDrones`，分支 `feat/crazyflie-pidrate`，HEAD=`aed2b1b`（M2 naive，7 文件 +1097 行）。happo/mappo.yaml 的 2 行改动为他人既有未提交内容，**未纳入本次提交**。

| 里程碑 | 结果 |
|---|---|
| M2-0 bake-in | `NavVel.yaml` 4 个死亡惩罚默认 `20/20/10/2 → 0`（=fixctl-B run `9eb3e923` 配方）；冒烟 `max_iters=1` @level0 ✅ 145k fps、无错、checkpoint 保存 |
| M2-1 实现 | 新文件：`envs/single/nav_vel_obstacles.py`（ObstacleManager 纯逻辑）、`utils/nav_curriculum.py`（课程）、`scripts/obstacle_geometry_test.py`（单测）；改造：`nav_vel.py`（obs 30→62、布局/碰撞/奖励/stats/课程）、`views/__init__.py`（RigidPrimView Isaac5.1 `usd` kwarg 修复）、`eval_ckpt.py`（障碍/到达率评估） |
| M2-1 验证 | 纯逻辑单测全过：L=0/2/4/8 各 2048 env **布局 0 失败**（激活数/在场内/端点净空/互距全满足）、obs 形状(8,1,32)+归一化+零填充、碰撞边沿穿球恰 1 次、课程"成功/碰撞双门控 + min_frames"正确 |
| M2-1 冒烟 | 锁 2 障（`initial_level=1, enabled=false`）`max_iters=1` ✅（rollout + 600 步 eval 无错）；`eval_ckpt` @2 障打印到达率/碰撞边沿/min_clearance/联合成功正常 |
| M2-2 短训信号 | **锁 2 障 fresh 2M 帧**（wandb `RL90` run **`20ss823w`**，https://wandb.ai/fly-hust/RL90/runs/20ss823w）：61 iter 全程稳定（rollout_fps≈1.6e5，无 NaN/崩溃）；训练 stats：`curriculum_level=2`、`collision_episodes` 1–2%、`collision` EMA ~0.001–0.009、`min_clearance`~2.2（健康）；`eval_ckpt`（checkpoint_1671168，300 步）：pos_error 3.42、arrival 0、碰撞边沿 11/307k 步、1% env 触碰。⚠️ 2M 内**未开始导航属预期**（M1 收敛需 ~50M 帧 + 障碍任务更难）→ 需长训收敛。运行末尾 wandb artifact 上传报 `service process is busy`（网络/服务瞬时故障，非代码问题，训练/评估已完整完成） |
| M2-2 课程长训 10M | **锁 2 障 fresh 10M 帧**（wandb `RL90` run **`t65eww3z`**，https://wandb.ai/fly-hust/RL90/runs/t65eww3z，21:16–21:19）：全程 `curriculum_level=2` **未升档**；训练窗口 `success_rate` 0→0.01→0.10→0.34→0.45→**0.54** 持续上升（碰撞门控未卡：窗口 `collision_episodes`~1%，`min_clearance`~1.9–2.3 健康）；`eval_ckpt` @L2/600 步（checkpoint_final）：**arrival_rate 0.589、collision_episodes 0.049（贴着 5%）、joint success 0.564**、pos_error 0.714、min_clearance mean 1.08（<0.1 仅 66/1024）→ **路线可行，离 L2 的 0.8 门槛还差一截，续训即可**。⚠️ 10M 对 2 障尚未到 0.8 属预期（M1 无障需 ~50M；障碍任务更久），勿误判为机制问题。 |
| M2-2 续训 50M(ws) | **warm-start 50M**（wandb `RL90` run **`qf3wq4kh`**，https://wandb.ai/fly-hust/RL90/runs/qf3wq4kh；run_name 写 ws-20M 但实为 50M）：1525 iter ~9.7min 完整跑完。轨迹：L2 `success` 0.60→0.81，**~8M 帧处自动升 L4**（L2 达标点）；L4 段 success 0.81→**0.66 走低**、arrival EMA 0.83→0.69、collision_episodes **~0.08（>0.05 门）**、entropy +2.99→**−1.1（TanhNormal 差分熵可为负=策略近确定性/探索塌缩）**。确定性 eval（600 步）：L2@升档前 ckpt(6586368@6.5M) **arrival 0.835✅/collision 0.050/joint 0.802**（L2 门槛达成）；L4@final **arrival 0.708/collision 0.086/joint 0.662**/pos_error 0.476(<0.5 能停)/min_clearance 0.77（飞得更贴）。L4@1200 步 arrival 0.703≈600 步 0.708 → **4 障下 600 窗口仍非瓶颈**。诊断：L4 掉点主要是**碰撞 8.6%（success 要求整窗 0 碰撞）+ 熵塌缩无法探索更安全路径**，不是导航到不了也不是超时。 |
| M2-2 路径B L4 熵恢复 | **恢复探索重训 L4**（wandb `RL90` run **`giogxhh9`**，https://wandb.ai/fly-hust/RL90/runs/giogxhh9；先让 `entropy_coef` 可配 commit `e2b08bd`）：从 6.5M 未塌缩 ckpt warm-start + `algo.entropy_coef=0.01` + 锁 4 障 15M。结果：**entropy 稳定在 +2.2（不再塌缩）**；`eval_ckpt` @L4/600：**arrival 0.968、joint success 0.896、pos_error 0.249（<0.1 计数 128/1024）**、collision_episodes 0.085（仍 >5% 升 8 障门）、min_clearance mean 0.735。→ **证实此前 L4 0.66 是熵塌缩早熟收敛，非真实上限**；恢复探索后 naive L4 可达 ~0.9 联合成功。碰撞仍 ~8.5%（贴障/到达后游荡擦碰）→ 升 8 障需碰撞≤5%，见 §11.2。 |
| M2-2 路1 升8(30M) | **放宽碰撞门升 8**（wandb `RL90` run **`a32os839`**，https://wandb.ai/fly-hust/RL90/runs/a32os839，30M）：从 `giogxhh9` final warm-start + `collision_rate_threshold=0.10` + 课程开 + entropy 0.01，**~2.5M 帧升到 8 障**；L8 段(~27M) success 0.84→**0.71 走低**、arrival 0.92→0.80、collision_episodes **0.14→0.16 平台**；entropy +2.2 健康。`eval_ckpt` @8障/600：**arrival 0.814✅ / joint success 0.706 / collision_episodes 0.155 / pos_error 0.360 / min_clearance mean 0.45**。→ **8 障已激活**（arrival 达标 0.81），但 **joint success 0.71 未到 0.9**（碰撞 15.5% 是主因）→ 按用户规则"未到 0.9 退路2"触发，或直接在此 8 障引入 CBF（见 §11.2d 决策）。 |
| M2-2 路C naive-8 续训(30M) | **naive-8 继续加训 30M**（wandb `RL90` run **`fs1umcz2`**，https://wandb.ai/fly-hust/RL90/runs/fs1umcz2）：从 `a32os839` final 续训锁 8 障，默认奖励 + entropy 0.01。窗口 success **0.69→0.60 继续走低**（arrival 0.79→0.71、collision_episodes~0.16 平台）；`eval_ckpt` @8障/600：**arrival 0.729 / joint success 0.643 / collision 0.149**（均比路1 final 更差）。→ **naive 在 8 障密度已到上限（joint≈0.65–0.71），续训不回升反而缓降**；**8 障最佳 A 臂基线 = 路1 的 `a32os839` final（arrival 0.814/joint 0.706）**。 |

**相对本文档/迁移指南默认的落地差异（有意为之，均已记录在 yaml 注释）**：
1. **障碍半径多尺寸档** `radius_choices: [0.20,0.30,0.40]`（你 2026-09-04 确认，替换迁移指南固定 `r_fixed=0.30`）；物理球半径固定=最大档 0.40（避免 reset 时逐 prim 改 USD 半径），逻辑半径（obs/奖励/碰撞）≤物理 → 几何判定半径 `r_s≥` 物理球，检测一致。
2. **可达性净空改为按障碍实际半径的自适应公式**（NavRL 思路，因你指出"终点到达可能与障碍生成冲突"）：`dist(球心,起/终点) ≥ r_s + init_clearance(0.15)/goal_clearance(0.35)`，`dist(球心,球心) ≥ r_oi+r_oj+min_gap(0.25)`。迁移指南 §4.2 与 §8.2 的固定 margin（0.35）自相矛盾且会生成"到达保持区被吞"的不可达布局。
3. `views/__init__.py` **RigidPrimView 补 IsaacSim5.1 `usd` kwarg monkey-patch**（与既有 ArticulationView 同款）——否则任何 obstacle env 构造即崩。
4. curriculum 增加 `enabled` 开关（`false`=锁级）与**碰撞率门控**（`success≥0.8 AND collision≤0.05 AND min_frames 2M`），`allow_demote` 默认关。
5. 奖励默认按 m2 §4.3 soft-respawn 兼容量级（collision_edge=2.0/early_death=0），代码已留 obstacle 早死开关（默认 0）。

### 11.2 决策与下一步（2026-09-04，L4 naive 经路径B 达标）

**路径 A（推荐）= 以 L4 naive 为 A 臂基线 → 进 M2-3 CBF**（详见 §11.2b）。

**路径 B（已完成）——恢复探索把 naive 救出 L4 塌缩谷**：把 ppo 的 `entropy_coef` 从硬编码(0.001)改为可配（commit `e2b08bd`，默认仍 0.001 不变）；从 6.5M 未塌缩 ckpt warm-start + `algo.entropy_coef=0.01` + 锁 L4(4障) 训 15M（run `giogxhh9`）→ **L4 arrival 0.968 / joint success 0.896**（此前塌缩态仅 0.66），熵稳定 +2.2。→ **证实此前 L4 掉点 = 熵塌缩早熟收敛，非 naive 上限**。

```bash
# L4 naive 基线（路径B 产物）确定性复核命令
python -u eval_ckpt.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
    task.curriculum.initial_level=2 task.curriculum.enabled=false \
    +checkpoint=/home/lz/lzspace/drones/OmniDrones/scripts/wandb/run-20260904_215248-giogxhh9/files/checkpoint_final.pt +rollout_steps=600
```

### 11.2b 决策与下一步（L4 naive 已达标；进 M2-3 CBF，2026-09-04）

**现状**：L2 达标并升 L4；**L4 naive（路径B）= arrival 0.968 / joint success 0.896 / collision 0.085 / entropy +2.2**。碰撞 episode ~8.5% 仍 >5%（升 8 障门），但联合成功已远超 80%。

**决策（推荐）**：**以路径B 的 L4 naive 为 A 臂基线（arm-A reference），进 M2-3 CBF1 → M2-4**。理由：①naive L4 已 0.9，是合格基线；②若继续冲 8 障，需要把碰撞压到 ≤5%（增碰撞惩罚/开早死），属**改奖励→会破坏 A/B 同奖励前提**，应在 A/B 定稿后再说；③M2-4 让两臂从**同一 L2-naive 起点**（`.../run-20260904_212924-qf3wq4kh/files/checkpoint_6586368.pt` @6.5M）锁 L4 续训、**同一 `algo.entropy_coef=0.01`**、仅差 `cbf.mode`，得到干净的 CBF 增量。

> 备注：①`entropy_coef` 现已可配（commit `e2b08bd`），**M2-4 两臂必须用同一 entropy_coef（建议 0.01）**，否则不可比。②若日后想 push naive 到 8 障（需碰撞≤5%），可试：`obstacle.reward_collision_edge` 2→3~4 或 obstacle early_death 小开(<1)，但必须 naive/CBF 同步重训。③600 步窗口在 L2/L4 均验证非瓶颈（§11.3 Q1），保持。④run 命名：`NavVel-obs-L{1,2,3}-naive/-cbfhybrid-{N}M`（L2=4 障，level idx=2）。

### 11.2c 升 8 决策：先路1(放宽碰撞门) → 不达标再退路2(提避障惩罚)（2026-09-04）

- **现象/根因**：L4 naive 15M(run `giogxhh9`) 内 `collision_episodes` 0.101→0.070，**平台 7–10%**（>5% 升 8 门未过）；success≈0.9/arrival≈0.95 已稳。根因 = **奖励权衡**：单次擦碰只扣 `collision_edge=2.0`，绕行/减速代价更高 → 策略接受 ~7-8% 轻擦碰更划算，**加帧难以自行压到 ≤5%**。
- **目标（用户 2026-09-04 拍板）**：先"升到 8 障（激活）"再引 CBF，naive 作 8 障 A 臂基线。
- **路1（先试，本次跑）**：课程碰撞门放宽 `task.curriculum.collision_rate_threshold=0.10`（**仅 CLI 覆盖，yaml 默认仍 0.05 未改**）；从 `giogxhh9` final warm-start + `curriculum.enabled=true initial_level=2` + `algo.entropy_coef=0.01`，训 30M（L4 success≥0.8 即自动升 8，随后在 8 障开训）。
- **路2（若 8 障 success 未达 ~0.9 再退）**：提高避障压力先把 L4 碰撞压到 ≤5% 再升 8：`obstacle.reward_collision_edge 2→4~5` + `obstacle.reward_near_slowdown_weight 0.5→1.0`（可选 obstacle early_death 小开 0.3），从 `giogxhh9` final 锁 L4 训 5–10M 验证 ≤5% 后再放课程。⚠️ 改的是**奖励** → 之后 8 障 A/B 须同配置（naive/CBF 同步）。
- **回退准备（无需改代码）**：路1/路2 全是**配置/CLI 覆盖**（不进代码、不改 yaml 默认）；git 基线干净（HEAD=`e2b08bd`，happo/mappo 为他人改动未纳入）。**回退 = 去掉对应 CLI 覆盖用默认（collision 0.05 / edge 2.0）重跑即可**；路1→路2 切换可直接从路1 checkpoint 续训，但标注 reward 配置不同（严格 A/B 需同配置 fresh）。

```bash
# 路1（本次执行）
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=online wandb.project=RL90 \
    wandb.run_name=NavVel-obs-8obs-naive-ws-ent0p01-col10-30M \
    task.curriculum.initial_level=2 task.curriculum.enabled=true \
    task.curriculum.collision_rate_threshold=0.10 \
    algo.checkpoint_path=/home/lz/lzspace/drones/OmniDrones/scripts/wandb/run-20260904_215248-giogxhh9/files/checkpoint_final.pt \
    algo.entropy_coef=0.01 total_frames=30_000_000 save_interval=50

# 路2（备用，先锁 L4 压碰撞；改的是 obstacle 奖励覆盖）
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=online wandb.project=RL90 \
    wandb.run_name=NavVel-obs-L4obs-naive-pen-edge4-15M \
    task.curriculum.initial_level=2 task.curriculum.enabled=false \
    obstacle.reward_collision_edge=4 obstacle.reward_near_slowdown_weight=1.0 \
    algo.checkpoint_path=/home/lz/lzspace/drones/OmniDrones/scripts/wandb/run-20260904_215248-giogxhh9/files/checkpoint_final.pt \
    algo.entropy_coef=0.01 total_frames=15_000_000 save_interval=50
```

### 11.2d 路1 结果与决策点（2026-09-04）

- **路1 完成**：8 障已激活（arrival 0.81✅）；naive L8 = **arrival 0.814 / joint success 0.706 / collision 0.155**（run `a32os839`，见 §11.1）。
- joint success 0.71 **未到 0.9** → 触发用户预设"退路2"。但两点需先确认：
  1. **路2 = 提避障惩罚（edge 2→4~5 / near_slow 0.5→1.0）= 改 A 臂奖励** → 之后 A/B（naive vs CBF）必须同配置重训/重基线；
  2. **naive 在 8 障密度下 joint success 冲 0.9 很可能到顶**（m2 验收本就"8 障 ≥60% 协商"）；CBF 的 reward core/filter 正是为高密度压碰撞/提 joint 设计，8 障碰撞 15.5% 恰是 CBF 价值最该体现的场景（§0 主战场）。
- **待拍板**：A=按规则退路2（先锁 L4 压碰撞≤5% 再升 8，代价=改奖励+重基线）；B=以 naive-8 为 A 臂基线直接进 M2-3 CBF；C=继续 naive-8 加训看能否到 0.8+（趋势 0.84→0.71 走低，预计到顶难）。

- **路C 已执行（2026-09-04，run `fs1umcz2`）**：naive-8 续训 30M **未回升反降**（joint 0.71→0.64）→ **确认 naive-8 密度上限 ≈ joint 0.65–0.71，加帧无用**。**8 障 A 臂基线锁定 = `a32os839` final**（arrival 0.814 / joint 0.706 / collision 0.155 / entropy +2.2）。路2（提惩罚压碰撞）仍未执行——它改奖励、需重基线，且 naive-8 到 0.9 大概率仍不可行；**结论：按 m2 §0 主战场思路，建议在 8 障直接引入 CBF（hybrid）对比该 naive-8 基线**，CBF 的 reward core/filter 正是为此设计。

### 11.2e 路2 执行记录（2026-09-04 23:35 启动；用户拍板走 §11.2c 路2）

**前置修复（23:34）**：上次 §11.2c 路2 命令 exit 1 的**双根因**：①run 所在 shell **未激活 `lz_env`**（`ModuleNotFoundError: hydra`）；②覆盖前缀缺 `task.`（应 `task.obstacle.*`，顶层无 obstacle key）。修复 = 命令内显式 `source ~/miniconda3/etc/profile.d/conda.sh && conda activate lz_env` + `task.` 前缀（dry-run + 真实 train 已验证可解析）。

**Run-1（23:35–23:38，10M）**：`edge 2→4` + `near_slowdown 0.5→1.0`（early_death 暂关，留作可选第二步）；从 `giogxhh9` final warm-start + `entropy_coef=0.01`，锁 L4（`initial_level=2 enabled=false`）。wandb `RL90` run **`se8c08en`**（https://wandb.ai/fly-hust/RL90/runs/se8c08en，run_name=`NavVel-obs-L4obs-naive-pen-edge4-near1-10M`）。

**Run-1 结果（确定性 eval @L4/600，验收口径）**：arrival **0.969** / joint success **0.912** / collision_episodes **0.066** / pos_error 0.229 / min_clearance mean 0.787（<0.1: 93/1024）。对比 `giogxhh9` 基线（arrival 0.968 / joint 0.896 / coll 0.085）：**碰撞 8.5%→6.6%（↓~2pt，仍未 ≤5%）、joint 0.896→0.912**。熵全程 ~2.18–2.20 健康。→ **edge4+near1 单独 10M 不足以把碰撞压到 ≤5%，触发叠加"可选"`obstacle.reward_early_death_weight=0.3` 续训**（Run-2）。

**Run-2（23:39–23:42，+10M，叠加 early_death 0.3）**：`edge4 + near1 + obstacle.reward_early_death_weight=0.3`，从 Run-1 `se8c08en` final warm-start。wandb `RL90` run **`6n4le99c`**（run_name=`NavVel-obs-L4obs-naive-pen-edge4-near1-ed03-10M`）。**确定性 eval @L4/600：arrival 0.960 / joint success 0.898 / collision_episodes 0.076 / pos_error 0.201**——**比 Run-1 反而更差**（coll 0.066→0.076、joint 0.912→0.898）。训练中 entropy 2.18→2.33（early_death 惩罚使策略更探索→擦碰回升）。→ **early_death=0.3 在 warm-start 上反效果，弃用该旋钮**。

**路2 阶段性结论（23:42）**：三次 warm-start 尝试 giogxhh9(8.5%) → `se8c08en`(6.6%) → `6n4le99c`(7.6%) 表明——**naive 锁 L4 提惩罚（edge4+near1±ed03）只能把碰撞压到 ~6.6% 平台，≤5% 难达；继续加压反伤 joint/arrival**。最佳配置 = **Run-1 `se8c08en`（edge4+near1，coll 0.066 / joint 0.912 / arrival 0.969）**，作为"新奖励配置"下的 L4 基态。是否按用户预案"≤5% 才放课程"继续加码，或改以 `se8c08en` 直接放课程升 8（collision 门 CLI 放宽），**待用户拍板（见 §11.2d/§11.2e 末尾）**。

**Run-3（23:48–23:51，用户拍板选 B=继续加码）**：`edge 4→6` + `near_slowdown 1.0→2.0`（early_death 弃用，Run-2 已证反效果）；从 Run-1 `se8c08en` final（coll 最低 6.6%）warm-start + `entropy_coef=0.01`，锁 L4 训 10M。wandb `RL90` run **`y16p3d9o`**（run_name=`NavVel-obs-L4obs-naive-pen-edge6-near2-10M`）。**确定性 eval @L4/600：arrival 0.929 / joint success 0.869 / collision_episodes 0.077 / pos_error 0.241（<0.1 count 210/1024）**——**碰撞 0.077 未 ≤5%，且 arrival(0.969→0.929)/joint(0.912→0.869) 显著下降（过度保守/绕远）**。→ edge6+near2 更差，**提惩罚路线到此证伪**。

**路2 最终结论（23:52）**：四条 warm-start 路线汇总——giogxhh9(默认 edge2)：coll 0.085/joint 0.896；**`se8c08en`(edge4+near1)：coll **0.066**/joint **0.912**（最优）**；`6n4le99c`(+ed03)：coll 0.076/joint 0.898（反效果）；`y16p3d9o`(edge6+near2)：coll 0.077/joint 0.869（过度保守）。→ **naive 锁 L4 warm-start 无论怎么提避障惩罚，碰撞都压不到 ≤5%**（平台 ~6.6–7.7%），加码只会更伤 arrival/joint。这从实验上坐实 §11.2d 判断：**"整窗 0 碰撞"是 naive（奖励权衡 + 密度）的固有上限，不是超参问题**——正是 CBF reward core/filter 设计来解决的场景。**8 障 A/B 若采用"新奖励配置"路线，唯一合理基态 = `se8c08en`（edge4+near1）**；是否冻结默认奖励（edge2）走 §11.2d 方案 C，待用户再次拍板。

**Run-4（23:55–00:00，用户拍板选 A=以 `se8c08en` 新配置升 8 障；已完成）**：保持 `edge4+near1`，放课程（`curriculum.enabled=true initial_level=2`，碰撞门 CLI 放宽 `collision_rate_threshold=0.10`），从 `se8c08en` final warm-start + `entropy_coef=0.01`，训 20M（~2-3M 帧自动升 8 障，L8 段 ~17M）。wandb `RL90` run **`lmhvaqka`**（run_name=`NavVel-obs-8obs-naive-pen-edge4-near1-col10-ws-20M`）。

**Run-4 结果（确定性 eval @8障/600，验收口径）**：arrival **0.824** / joint success **0.721** / collision_episodes **0.165** / pos_error 0.461（<0.1: 164/1024）/ min_clearance 0.459。对比默认 edge2 的 `a32os839`（arrival 0.814 / joint 0.706 / coll 0.155）：**joint 略升（0.706→0.721）但碰撞反而略高（0.155→0.165）**——**edge4+near1 在 L4 的压碰撞优势（8.5→6.6%）没有转化到 8 障**（碰撞回到 ~16%，与默认几乎一样甚至略高）。→ **坐实最终结论：8 障高密度下 naive 碰撞 ~15-16% 是密度 + 整窗 0 碰撞定义的固有上限；L4 上的提惩罚技巧到 8 障失效。8 障"新奖励配置"A 臂基线 = `lmhvaqka` final（arrival 0.824 / joint 0.721 / coll 0.165）**（与默认 edge2 的 `a32os839` 相当，joint 略好；后续若 A/B 用 edge4+near1，则 CBF hybrid 须同配置）。

**Run-5/Run-6（2026-09-05 00:05–00:52，用户自行续训 200M 级长跑；用户反馈"效果不好"——已复核确认）**：
- **Run-5 `uc1t78uz`**（00:05 启动，run_name=`NavVel-obs-8obs-naive-pen-edge4-near1-lmhvaqka-ws-200M` = 上会话给出的 `total_frames=180M` 续训命令）：从 `lmhvaqka` final ws、锁 8 障（L3/enabled=false）、edge4+near1、entropy 0.01。**跑到 ~70.5M 被中断**（无 checkpoint_final/config 收尾，止于 `checkpoint_70483968`）。
- **Run-6 `fg7sdmla`**（00:22 启动，run_name=`...-ws-120M`）：从 Run-5 `checkpoint_70483968`(70.5M) ws、同配置，`total_frames` 用户改 120M，实际跑到 **~150M**（Final Eval @149,979,136）。至此 lmhvaqka 线**累计经历 ~220M**（20+70+150）。
- **Run-6 结果（确定性 eval @8障/600，验收口径）**：arrival **0.824** / joint success **0.718** / collision_episodes **0.161** / pos_error 0.346。对比 `lmhvaqka`(20M)：**arrival 0.824=0.824、joint 0.718 vs 0.721（略降）、coll 0.161 vs 0.165（基本不变）→ +200M 帧零改善**。训练内 **entropy 塌缩到 −4.8**（TanhNormal 负熵=策略近确定性），train/eval `collision_episodes` 0.157/0.172 平台、`min_clearance` 未见改善。
- **结论（用户判断正确；naive-8 第三次坐实"加帧无用"）**：8 障 naive 即使加帧到 **200M 级**，确定性 eval 与 20M 的 `lmhvaqka` **逐位持平**；长训只让策略**熵塌缩成确定性**（丧失探索→无法突破碰撞权衡），碰撞/联合成功不降不升。再次验证 m2 §9/交接教训"熵塌缩=早熟收敛，别在 final ckpt 盲加帧"。→ **8 障 A 臂基线冻结 = `lmhvaqka` final（20M：arrival 0.824 / joint 0.721 / coll 0.165）**；naive 在 8 障已穷尽（配置 edge2/edge4+near1/edge6+near2 × 帧数 20M~220M 全部验证），**下一步只剩 M2-3 CBF（reward core/filter）**。

```bash
# Run-1（已跑，10M）
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=online wandb.project=RL90 \
    wandb.run_name=NavVel-obs-L4obs-naive-pen-edge4-near1-10M \
    task.curriculum.initial_level=2 task.curriculum.enabled=false \
    task.obstacle.reward_collision_edge=4 task.obstacle.reward_near_slowdown_weight=1.0 \
    algo.checkpoint_path=<giogxhh9 final> algo.entropy_coef=0.01 \
    total_frames=10_000_000 save_interval=50

# Run-2（续训，叠加 early_death 0.3）
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=online wandb.project=RL90 \
    wandb.run_name=NavVel-obs-L4obs-naive-pen-edge4-near1-ed03-10M \
    task.curriculum.initial_level=2 task.curriculum.enabled=false \
    task.obstacle.reward_collision_edge=4 task.obstacle.reward_near_slowdown_weight=1.0 \
    task.obstacle.reward_early_death_weight=0.3 \
    algo.checkpoint_path=<se8c08en final> algo.entropy_coef=0.01 \
    total_frames=10_000_000 save_interval=50
```

### 11.2f M2-3 CBF1 实现（2026-09-05 13:36，分支 `feat/cbf`）

**git 版本基线**：tag `m2-naive-achieved` @`e2b08bd`（A 臂 naive 代码态）；从 `e2b08bd` 分出 **`feat/cbf`** 隔离开发（`feat/crazyflie-pidrate` 保持 naive 主线不动）。三次原子提交：
1. `62cf35a` — `omni_drones/utils/cbf.py` + `scripts/cbf_test.py`：一阶 CBF 闭式/迭代投影 + reward core 纯函数 + `CBFVelocityFilter`(Transform) + config plumbing。
2. `4da896a` — `NavVel.yaml` 增 `cbf:` 段 + `nav_vel.py` 接入：`info.obstacle_cbf (n,K,4)` 通道、`stats.cbf_violation`、reward core（用滤波前 `policy_action[...,:3]`）。
3. `592998c` — `train/play/eval_ckpt` 三处装配 `CBFVelocityFilter`（append 在 VelController **之后**——torchrl `Compose._inv_call` 逆序执行 → CBF 先于 VelController 处理速度指令）。

**实现要点**：
- 滤波数学（静态球，外法向 $n_i=(p-p_{o,i})/\lVert\cdot\rVert$）：$g_i=n_i^\top v+\alpha h_i$，违反 $g_i<0$ 时 `v += −g_i·n_i`，每轮只修最违反槽、迭代 `filter_iterations` 轮；CBF 判定球 $r_{s,i}^{cbf}=r_s+margin+v_{max}^2/(2a_{max})$（在几何 $r_s$ 上叠裕量+制动），只进滤波/reward core、**不进策略 obs**。
- `mode=none` = 不装配 Transform + reward core 关闭 → 与 naive 逐位一致（回归已冒烟）。
- reward core 违反量 $\lambda\sum\min(0,g_i)$（`penalty_intrude` 时 $h_i<0$ 追加）→ `reward -= λ·viol`。
- CPU 单测全过：半径数值 / 头对直飞被刹到临界接近率 $\alpha h$ / 远离与切向不变 / 多球同时违反被迭代满足且不放大速度 / reward-core 符号与 intrude / config plumbing。

**冒烟（锁 2 障 1 iter，全过）**：`mode=none` 回归（新增 info/stats 不破坏 naive）、`filter_only`、`hybrid`、`eval_ckpt`+`hybrid` 装配验证。⚠️ CLI 覆盖 cbf 须用 **`task.cbf.*`**（cbf 段在 task 命名空间）。

**待做（M2-4）**：同一起点（推荐 A 臂 `lmhvaqka` final）锁 8 障 + 同 `entropy_coef=0.01`，仅差 `task.cbf.mode=hybrid`（若对齐 `lmhvaqka` 的 edge4+near1 则同样 CLI 覆盖），训 ~20-30M；确定性 eval 对比 A 臂（arrival/joint/coll/**cbf_violation**/min_clearance）。达标后 merge `feat/cbf`→`feat/crazyflie-pidrate` + tag `m2-achieved`。

**Run-7 hybrid（2026-09-05 13:39 启动，20M 完成 13:50）**：A 臂 `lmhvaqka` final warm-start、锁 8 障（L3/enabled=false）、**edge4+near1 同 A 臂** + `task.cbf.mode=hybrid`（默认 alpha=1.0/margin=0.1/**brake**/reward_weight=0.5/penalty_intrude/iter=3）、`entropy_coef=0.01`、20M。wandb `RL90` run **`5e5u6ibo`**（= run_name `NavVel-obs-8obs-cbfhybrid-edge4near1-ws-20M`；13:47 重发一次误以为是中断，产出 v2 run `c8abjzd9`，指标与 5e5u6ibo 一致，无影响）。

**Run-7 结果（确定性 eval @8障/600，`5e5u6ibo` final ckpt，同默认 cbf 参数）**：
| 指标 | **hybrid `5e5u6ibo`** | A 臂 `lmhvaqka` | 判读 |
|---|---|---|---|
| arrival | **0.537** (550/1024) | 0.824 | ❌ 减半 |
| joint success | **0.535** | 0.721 | ❌ 减半 |
| collision(envs≥1 edge) | **0.004** (4/1024) | 0.165 | ✅ 几乎清零 |
| cbf_violation | 0.153 | — | 滤波仍频繁介入 |
| min_clearance <0.1 | 9/1024 | 217/1024 | ✅ 净空大幅改善 |
| entropy(训末) | **−0.83（塌缩）** | −4.8(已塌) | ⚠️ warm-start 后再度塌缩 |

**保守度诊断（同 ckpt、仅 eval 时改 CBF 判定半径，无重训）**：
- 关 brake（`use_brake_term=false`）+ margin 0.1：joint **0.745** / coll 8/1024 (0.008)
- 关 brake + margin 0.0：joint **0.756** / coll 18/1024 (0.018)

**分析结论**：①CBF 滤波本身有效——碰撞 0.165→0.004 且净空大幅改善，reward-core 符号修复（`c7aebed`）后 return 正常；②**arrival 减半的元凶 = brake 制动项** $r_{brake}=v_{max}^2/(2a_{max})=1.8^2/4=0.81\,m$，把判定球从 ~0.6 撑到 **1.41 m**——8 障高密场里几乎堵死走廊/触发远距离减速，warm-start 策略（习惯了 0.824 arrival 的高速穿行）被滤波频繁刹车→到达失败；③**同一已塌缩 ckpt 仅关 brake，joint 0.535→0.75+、coll 仍 ≤0.02**（≪ A 臂 0.165），坐实瓶颈是参数过度保守而非滤波原理；④20M 训中熵塌缩（−0.83）说明在保守滤波下 warm-start 策略无探索余量、已陷局部。**→ 不建议续训 `5e5u6ibo`**；下一步 = 从熵健康的 `lmhvaqka` 重启 hybrid + 放宽 CBF 参数（见勾选清单 M2-4）。

**Run-8 / Run-9（2026-09-05 14:03–14:04 启动，双路并行 GPU 共享 ~88k fps/路）**：按用户拍板 (a)+(c)+加跑(e)，均从 A 臂 `lmhvaqka` final warm-start、锁 8 障（L3/enabled=false）、edge4+near1 同 A 臂、`total_frames=20M`、`save_interval=50`，**统一放宽 = `use_brake_term=false` + `entropy_coef=0.02`**：
- **Run-8 (a)+(c)**：`task.cbf.mode=hybrid`（reward core 开）。wandb `RL90` run **`ax7fs7gh`**（run dir `run-20260905_140348-ax7fs7gh`，run_name=`NavVel-obs-8obs-cbfhybrid-nobrake-ent02-ws-20M`）。
- **Run-9 (e) filter_only 对照臂**：`task.cbf.mode=filter_only`（无 reward core，隔离其作用）。wandb `RL90` run **`orzg9g8f`**（run dir `run-20260905_140420-orzg9g8f`，run_name=`NavVel-obs-8obs-cbffilteronly-nobrake-ent02-ws-20M`）。
- 预期对照：Run-8 vs Run-9 之差 = reward core 增量；两者 vs A 臂 `lmhvaqka`(0.824/0.721/0.165) = CBF 全增量。

**Run-8/9 结果（确定性 eval @8障/600，2026-09-05 14:10–14:13，同训练 cbf 配置）**：
| 指标 | **Run-8 hybrid `ax7fs7gh`** | **Run-9 filter_only `orzg9g8f`** | A 臂 `lmhvaqka` |
|---|---|---|---|
| arrival | **0.916** (938/1024) | **0.910** (932/1024) | 0.824 |
| joint success | **0.913** (935/1024) | **0.907** (929/1024) | 0.721 |
| collision (envs≥1 edge) | **6/1024 (0.006)** | **5/1024 (0.005)** | 165/1024 (0.165) |
| return | 699 | 748 | ~740(naive) |
| min_clearance <0.1 | 10/1024 | 21/1024 | 217/1024 |
| entropy (训末) | 0.47（收敛） | 2.36（仍探索） | −4.8(塌缩) |

**分析**：放宽 brake + entropy 0.02 后，**CBF 两臂在 8 障全面碾压 A 臂 naive**——joint 0.721→0.91（**+19pt**）、collision 0.165→0.005~0.006（**↓97%**）、危险擦碰 217→10~21/1024，且熵不再塌缩。**Run-8 hybrid vs Run-9 filter_only 几乎持平**（joint 0.913 vs 0.907、coll 6 vs 5）→ 该难度/帧数/warm-start 下 **reward core 边际增量很小**（与 cbf-rl-demo "filter_only≈hybrid" 预期一致）；filter_only 训末熵仍 2.36（探索未收敛），加帧或可再涨。**M2-4 主目标达成**（碰撞↓ 且 成功率≥A 臂）。待用户决策：merge `feat/cbf`→`feat/crazyflie-pidrate` + tag `m2-achieved`，或补 reward_only 臂/加帧 filter_only。

### 11.3 设计问题快答（2026-09-04，naive 10M 数据支持）

**Q1：600 步窗口对导航是否太短？** —— **当前难度下不是瓶颈，保持 600。** 数据：同一 10M checkpoint @L2，eval rollout 600 步 arrival=0.589 vs 1200 步(12s) arrival=0.595（仅 +0.6%），且 1200 步 collision_episodes 0.049→0.068（更长滞留反增碰撞）。说明 ~41% 未到达不是"时间不够"，而是"未收敛到 0.5m 入圈保持"（mean pos_error≈0.71 已贴近 arrive_radius=0.5 却未稳定保持）。M1 无障同窗口能到 99% → 机制会随帧数补上。**若 L4/L8 因绕行真正出现超时上限**再议（届时改 `max_episode_length` 需 naive/CBF 两臂同步重训，是 M2-4 前要定的重训决策）。

**Q2：障碍全建成球形是否合理？** —— **对 v1 + CBF1 阶段合理，继续用。** 依据：①障碍 obs 槽=球心+单半径，与球体逐位精确匹配，无朝向歧义；②碰撞/奖励/obs 共用同一球-球几何（含膨胀），不会出现"obs 半径≠物理半径"错位；③CBF1 需要解析有符号距离 h=‖p−p_o‖−r_s 与法向 n（球最干净，闭式投影成立）；④多尺寸半径档/课程/未来动态障碍与感知（检测框→球估计）都天然兼容。局限：球无法表达 NavRL 那种"2D 高柱不可越 vs 3D 矮块可越"的真实类别（球总是三向对称、可绕可越），包围球对柱/墙会高估占用。**建议**：naive vs CBF 两臂 A/B 全程保持球（几何一致才可比）；"障碍类型化(柱/矮块)+半径/净空第二难度旋钮"作为 M2 之后的独立阶段（obs 槽位与布局采样都留了口子）。

**Q3：L4 训练中 entropy 上下跳动而非缓慢下降，有问题吗？** —— **正常，不是问题。** 数据(giogxhh9，entropy_coef=0.01)：entropy 全程窄带 **[1.89,2.24] 小幅锯齿**（60-iter 滑动半振幅仅 ~0.05–0.07、方向翻转 ~34 次/100 iter），均值缓升 1.96→2.13。成因：`loss = policy_loss − entropy_coef·mean(entropy)`，entropy_coef 从 0.001 提到 0.01（10×）后，熵正则的"向上推力"与策略梯度的"趋确定性向下推力"在平衡点(~2.0)拉锯，每次 minibatch/换批小幅往复。对比默认 0.001：熵力弱 10× → 只单调塌缩（即此前跑到 −1）。结论：**振幅小、均值稳 = 保持了探索、未塌缩，正是想要的**；若后期想更收敛可把 entropy_coef 降到 0.005 或做退火（暂未实现）。

- 时间戳：2026-09-04（创建）；**最近更新 2026-09-05 14:15（M2-4 达标回填：Run-8 hybrid `ax7fs7gh` = arrival 0.916/joint 0.913/coll 0.006、Run-9 filter_only `orzg9g8f` = 0.910/0.907/0.005，均远超 A 臂 `lmhvaqka` 0.824/0.721/0.165——joint +19pt、coll ↓97%、熵不塌缩；hybrid≈filter_only 即 reward core 边际小；待决策 merge+tag，见 §11.2f/勾选清单）**；此前要点：Run-8/9 双路 20M 完成（14:03/14:04 启动、14:09/14:10 结束）；Run-7 hybrid（`5e5u6ibo`）默认 brake 结果 0.537/0.535/0.004 + 保守度诊断坐实 brake 0.81m 过保守；M2-3 CBF1 已实现（分支 `feat/cbf`，`c7aebed` 含 reward-core 符号修复）；naive 8 障穷尽（Run-5/6 长训 200M 级零改善，A 臂冻结=`lmhvaqka` final，见 §11.2e）；M1 前置经验见 `m1_navvel_plan.md`，障碍机制细节见 `navvel_obstacle_migration_guide.md` + `NavVel.yaml` 注释，CBF 设计见 §5。

---

# 会话交接摘要（2026-09-05 14:20，UTC+8；本段由本会话生成，供新会话直接接续）

> **一句话现状**：**M2-4 主目标已达成**——naive-8（A 臂 `lmhvaqka`，arrival 0.824/joint 0.721/coll 0.165）已被 CBF 全面超越：**Run-8 hybrid `ax7fs7gh` = 0.916/0.913/0.006**、**Run-9 filter_only `orzg9g8f` = 0.910/0.907/0.005**（确定性 eval @8障/600，joint +19pt、coll ↓97%、熵不塌缩）。**待用户决策 3 方案**：merge+tag `m2-achieved` / 补 reward_only 凑 4 臂 / filter_only 加帧（见 §4）。

## 1. 本阶段完成事项（时间线，全量到 2026-09-05 14:15）

| 时间(UTC+8) | 事项 | 产物/run / commit |
|---|---|---|
| 09-04 21:00–22:40 | **M2-0/1/2**：障碍机制+课程落地；naive L2/L4 达标、路径B 熵恢复（`giogxhh9` L4 0.968/0.896）；路1 放宽碰撞门升 8 障（`a32os839` 0.814/0.706/0.155）；路C 续训反降 → naive-8 到顶 | commits `aed2b1b`/`e2b08bd`；tag `m2-naive-achieved`@`e2b08bd`；runs `20ss823w`/`t65eww3z`/`qf3wq4kh`/`giogxhh9`/`a32os839`/`fs1umcz2` |
| 09-04 23:35–00:00 | **路2（锁 L4 压碰撞 ≤5% 再升 8）证伪**：edge4+near1（`se8c08en` coll 6.6% 最优）±early_death（`6n4le99c` 反效果）、edge6+near2（`y16p3d9o` 过度保守）——**naive 锁 L4 碰撞压不到 ≤5%**；Run-4 `lmhvaqka`（edge4+near1）放课程升 8 障 | runs `se8c08en`/`6n4le99c`/`y16p3d9o`/`lmhvaqka` |
| 09-05 00:05–00:52 | **naive-8 长训穷尽**：Run-5 `uc1t78uz`(~70M 中断)+Run-6 `fg7sdmla`(~150M) 累计 ~220M **确定性 eval 零改善**（0.824/0.718/0.161，熵塌缩 −4.8）→ **A 臂冻结=`lmhvaqka` final** | runs `uc1t78uz`/`fg7sdmla` |
| 09-05 13:00–13:36 | **M2-3 CBF1 实现 + 单测/冒烟全过**：`feat/cbf` 分支 4 commits：`62cf35a`(cbf.py+单测) → `4da896a`(yaml+nav_vel 接入) → `592998c`(train/play/eval 装配) → `c7aebed`(**修复 reward-core 符号 bug**：`reward += λ·viol`，此前 `-=` 把惩罚变奖励) | branch `feat/cbf`@`c7aebed`（从 `e2b08bd`/tag `m2-naive-achieved` 分出） |
| 09-05 13:39–13:50 | **Run-7 hybrid 默认 brake 20M**（`5e5u6ibo`）：coll 0.004✅ 但 arrival 0.537 减半 + 熵塌缩 −0.83 → **保守度诊断**（同 ckpt 仅 eval 关 brake → joint 0.535→0.75+、coll≤0.02）坐实元凶 = brake 制动项 0.81m | run `5e5u6ibo`（+重复 v2 `c8abjzd9`） |
| 09-05 14:03–14:10 | **Run-8/9 双路（关 brake + ent 0.02 + warm `lmhvaqka`，20M）**：Run-8 hybrid=`ax7fs7gh`、Run-9 filter_only=`orzg9g8f`（GPU 共享 ~88k fps/路） | runs `ax7fs7gh`/`orzg9g8f` |
| 09-05 14:10–14:15 | **M2-4 达标回填**：确定性 eval @8障/600 = Run-8 **0.916/0.913/0.006**、Run-9 **0.910/0.907/0.005**（详见 §11.2f）；hybrid≈filter_only（reward core 边际小） | 文档 §11.2f / 勾选清单 M2-4 ✅ |

## 2. 关键结论 / 教训（新会话必读，别再重复踩）

1. **naive 8 障高密度 = 真实上限**（整窗 0 碰撞太严）：coll ~15-16% 是密度+奖励权衡的固有值；**加帧(220M)/加避障惩罚(L4 四条路线)均无用** → 只能靠 CBF 类硬约束/滤波突破（已被 Run-8/9 证实）。
2. **熵塌缩(≈−1 甚至 −4.8)= 早熟收敛，不是真实上限**：恢复探索 = 从**未塌缩早期 ckpt** warm-start + `algo.entropy_coef=0.01~0.02`。**别在已塌缩 final ckpt 上盲加帧**。
3. **CBF 默认参数过保守的元凶 = brake 制动项** $r_{brake}=v_{max}^2/(2a_{max})=0.81\,m$（判定球 0.6→1.41m，8 障堵走廊）→ **`task.cbf.use_brake_term=false`（或 a_max↑）是 CBF 可用的前提**；保守度可用"同 ckpt 仅 eval 改 `task.cbf.*` 半径"零成本扫描（无需重训）。
4. **reward-core 符号**：`cbf_violation≤0`（越负越危险），正确 = `reward += λ·viol`（commit `c7aebed`）。
5. **hybrid ≈ filter_only**（本难度/帧数/warm-start 下 reward core 边际很小，与 how2use "filter_only≈hybrid" 预期一致）；filter_only 训末熵仍 2.36（未收敛），reward core 的"收敛提速/防穿障"论点需 reward_only 臂或加帧进一步检验。
6. 环境/命令坑：**conda 需显式激活**（`source ~/miniconda3/etc/profile.d/conda.sh && conda activate lz_env`，否则 hydra 报错）；**hydra 覆盖须 `task.cbf.*` / `task.obstacle.*`**（cbf/obstacle 段在 task 命名空间）；600 步窗口非瓶颈（保持）；obs 维度变更=旧 ckpt 失效（重训正常）；wandb 收尾偶发 `service process is busy`（瞬时，用 `tee` 留日志）。

## 3. 交接状态（当前 git / checkpoint / 基线 / 配置）

- **OmniDrones git**：分支 **`feat/cbf`**，HEAD=`c7aebed`（自 `e2b08bd`/tag `m2-naive-achieved` 分出 4 commits）；`feat/crazyflie-pidrate` 停在 `e2b08bd`（naive 主线）。仅 happo/mappo.yaml 为他人未提交改动（**勿纳入提交**）。
- **CBF 代码态**：`utils/cbf.py`（`filter_velocity` 迭代投影 + `cbf_violation` reward core + `CBFVelocityFilter` Transform + `safety_radius_extra`）；`nav_vel.py` 接入 `info.obstacle_cbf(n,K,4)`/`stats.cbf_violation`/reward core（用滤波前 `policy_action`）；`train/play/eval_ckpt` 三处装配；`NavVel.yaml` 增 `cbf:` 段（默认 mode=none → 与 naive 逐位一致）；`scripts/cbf_test.py` CPU 单测全过。
- **A 臂（naive）8 障基线（冻结）**：`scripts/wandb/run-20260904_235551-lmhvaqka/files/checkpoint_final.pt`（edge4+near1）→ **arrival 0.824 / joint 0.721 / coll 0.165**。
- **B 臂（CBF 达标，放宽配置 = `use_brake_term=false` + `entropy_coef=0.02`，edge4+near1 同 A 臂）**：
  - **Run-8 hybrid（最优）** `.../run-20260905_140348-ax7fs7gh/files/checkpoint_final.pt` → **0.916/0.913/0.006**（entropy 0.47 收敛）；
  - Run-9 filter_only `.../run-20260905_140420-orzg9g8f/files/checkpoint_final.pt` → **0.910/0.907/0.005**（entropy 2.36 仍探索）。
- **可复用中间起点**：L2 健康 6.5M = `.../run-20260904_212924-qf3wq4kh/files/checkpoint_6586368.pt`；L4 强 = `.../run-20260904_215248-giogxhh9/files/checkpoint_final.pt`。
- **验收口径（eval_ckpt 确定性 @8障/600，非 train 打印）**：arrival=600 步内触发 arrival(hold 50) 占比；collision=≥1 edge env 占比；joint=arrival 且 0 碰撞。

## 4. 待决策的下一步（3 方案 + 理由）

**方案 A（推荐）—— merge `feat/cbf` → `feat/crazyflie-pidrate` + tag `m2-achieved`，出 §2.2 对比报告**
- 理由：①M2-4 主目标（碰撞↓ 且成功率≥A 臂）**已达成且有 2 路独立证据**（hybrid + filter_only 都远超 naive，排除了单 run 偶然）；②代码态稳定（CPU 单测 + 三模式冒烟 + 多次确定性 eval 复现）；③先**落袋锁定成果**，后续任何消融/扩展都基于已 tag 的干净基线，避免分支越拖越脏；④§11.2f 既定收尾动作，成本≈0。
- 动作：`git checkout feat/crazyflie-pidrate && git merge feat/cbf && git tag m2-achieved`（happo/mappo 不纳入）→ 用 Run-8 数据出 A/B 对比报告。

**方案 B（推荐次选，若想报告更完整）—— 先补 `reward_only` 臂（+可选 filter_only 加帧）凑齐 4 臂矩阵，再 merge**
- 理由：①当前只有 naive/hybrid/filter_only 三臂，**缺 reward_only** → 无法完整检验"软约束单独"的收敛提速/防穿障价值（CBF-RL 与 how2use §4.5 的核心论点），也难解释为何 hybrid≈filter_only；②reward_only 直接回答"reward core 到底有没有用"，对 §2.2 报告与后续 M3 都重要；③成本低（~10-20 分钟 GPU：warm `lmhvaqka` + 关 brake + ent 0.02 + `mode=reward_only` 20M）；④filter_only 训末熵 2.36，可顺带加帧看 joint 能否 >0.91。
- 动作：`task.cbf.mode=reward_only`（同 Run-8/9 其余配置）→ 确定性 eval → 补齐 4 臂曲线 → 再 merge + tag。

**方案 C —— filter_only 加帧（先验证"未收敛策略加帧能否再涨"）再 merge**
- 理由：Run-9 训末熵 2.36（远未塌缩）→ 理论上还有提升空间，加帧可能把 joint 推到 >0.91，给 B 臂留一个"最高分"checkpoint；也顺带验证 CBF 下"加帧有效"（与 naive 加帧无效形成对照亮点）。
- 缺点：①收益不确定（hybrid 已收敛 0.47，同 ckpt 加帧大概率无益）；②会推迟 merge/报告；③即便加帧，仍需回来做方案 A 或 B。

## 5. 常用命令速查（`OmniDrones/scripts/`，先 `source ~/miniconda3/etc/profile.d/conda.sh && conda activate lz_env`）

```bash
# CBF CPU 单测（快）
python cbf_test.py

# 冒烟（锁 8 障=level3，mode 可换）
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
    task.curriculum.initial_level=3 task.curriculum.enabled=false \
    task.cbf.mode=hybrid max_iters=1

# 8 障确定性评估（验收口径；eval 的 cbf 配置须与训练一致）
python -u eval_ckpt.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
    task.curriculum.initial_level=3 task.curriculum.enabled=false \
    task.cbf.mode=hybrid task.cbf.use_brake_term=false \
    +checkpoint=<ckpt> +rollout_steps=600

# CBF 训练模板（达标配方：关 brake + ent 0.02 + warm lmhvaqka + 20M）
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=online wandb.project=RL90 \
    wandb.run_name=<name> task.curriculum.initial_level=3 task.curriculum.enabled=false \
    task.obstacle.reward_collision_edge=4 task.obstacle.reward_near_slowdown_weight=1.0 \
    task.cbf.mode=hybrid task.cbf.use_brake_term=false \
    algo.checkpoint_path=/home/lz/lzspace/drones/OmniDrones/scripts/wandb/run-20260904_235551-lmhvaqka/files/checkpoint_final.pt \
    algo.entropy_coef=0.02 total_frames=20_000_000 save_interval=50 2>&1 | tee /tmp/<name>.log
```

## 6. 回退 / 决策说明
- 所有训练/评估差异均为 **纯 CLI 覆盖**（edge4+near1、collision 门、`task.cbf.*` 全系）——`NavVel.yaml` 默认保持 `cbf.mode=none` + edge2，**回退 = 去掉覆盖重跑**即与 naive 逐位一致。
- 若走方案 A：merge 前确认工作区仅剩他人 happo/mappo.yaml 未提交（勿纳入），merge 后打 tag `m2-achieved` 并把勾选清单 M2-4 改为"已 merge"。
- 交接时间：2026-09-05 14:20（UTC+8）——生成于 m2_plan 本文件的编辑会话（本会话完成 M2-3 实现 + Run-7 诊断 + Run-8/9 达标）。

---

# 会话交接摘要 #2（2026-09-05 17:05，UTC+8；补 D1 4 臂 + obs 滑动窗口功能）

> **一句话现状**：D1(8障/5.6m) 4 臂已补齐（naive/hybrid/filter_only/reward_only），filter_only 40M 追平 hybrid；hybrid≈filter_only 主因是 **CBF 几乎不被激活**（cbf_violation 仅 0.01–0.06）。据此**按你的方案实现了"更多场景障碍 + obs 最近-8 滑动窗口"**（`feat/obs-window`，CPU+env 冒烟通过）。**下一步待你拍板 D2 增密参数后，跑 40M/臂的 4 臂 D2 对比 + 出图**。

## 1. 本会话新增（时间线 2026-09-05 16:30–17:05）

| 时间 | 事项 | 产物/run / commit |
|---|---|---|
| 16:31–16:44 | **D1 reward_only 冒烟 + Run-10 20M**（warm `lmhvaqka`、关 brake、ent 0.02、edge4+near1，只差 `cbf.mode=reward_only`） | smoke ✅；run **`saqki32o`**（train-final eval arrival **0.580**/coll_episodes **0.109**/cbf_violation 0.017/熵 2.14） |
| 16:47–16:53 | **Run-11 filter_only 续训 +20M（→40M 总量）**（从 Run-9 `orzg9g8f` final 续） | run **`pf0u94t1`**（train-final eval arrival **0.934**/coll_episodes **0.015**/熵 2.88 → 追平 hybrid Run-8 0.916/0.913） |
| 16:44–17:00 | **实现 obs 滑动窗口**：`num_scene`(M) 与 `max_slots`(K=8) 解耦 | branch **`feat/obs-window`** commits `bee6a17`(功能) + `…`(fix obs_window None-safe) |
| 17:00 | **CPU 校验全过**：固定槽模式(默认 M=K) 与旧语义一致（尾槽补零）；窗口模式 M16/K8 obs=最近8升序（距离 maxdiff 0.0）+ L8<M16 全真实 + CBF over M=16 形状正确 | importlib 纯 torch |
| 17:02–17:04 | **env 冒烟**：num_scene=16 + `curriculum.levels=[0,16]`(initial 1) + hybrid | 115k fps、600 步 eval 无错、ckpt 保存 ✅（先抓到并修复 obs_window null bug） |

## 2. D1 四臂确定性结果汇总（8障/5.6m；eval_ckpt @600 为验收口径，其余为 train-final eval 参考）

| 臂 | run | 帧数 | train-final eval (arrival/coll_ep) | 备注 |
|---|---|---|---|---|
| naive (A) | `lmhvaqka` | 20M | 0.824 / 0.165（确定性 eval：joint 0.721） | 冻结基线，edge4+near1 |
| hybrid | `ax7fs7gh` | 20M | 0.916 / 0.006 | 确定性 eval joint 0.913 |
| filter_only | `orzg9g8f`(20M)+`pf0u94t1`(40M) | 40M | 0.934 / 0.015 | 40M 收敛后 ≈ hybrid（熵 2.88 未塌缩） |
| reward_only | `saqki32o` | 20M | **0.580 / 0.109** | **明显弱**——只有软约束、无硬滤波，D1 下既压不住碰撞也掉到达率 |

**结论**：D1 下顺序 ≈ **hybrid≈filter_only(0.91) > naive(0.72) > reward_only(~0.58)**。reward_only 弱于 naive 是重要发现：单独 reward core（λ=0.5）惩罚太软，策略宁接受惩罚也不愿减速绕行；这正是"滤波不可省"的证据，也说明 **reward core 的价值必须在滤波频繁介入、且 reward_only 有滤波"兜底对比"时才能体现**。→ D1 上 hybrid≈filter_only 与 reward_only 弱的根因一致：**滤波几乎不出力**（cbf_violation 极小）→ 需要 D2 增密。

## 3. obs 滑动窗口实现（用户拍板方向：场景放更多障碍 + obs 实时取最近 8 个）

**接口**（全部纯 config，默认向后兼容 M2/D1）：
- `task.obstacle.num_scene` = M（每 env 场景物理障碍数，缓冲/prim 数）；默认 null → M=K=8（固定槽旧语义，D1 ckpt 不受影响）。
- `max_slots`=K=8 仍是 **obs 窗口**（obs 恒 62 维；改 K 才改 obs 维度，不要动）。
- M>K 时自动开 `obs_window`：每步 `build_obs` 从全部激活障碍取**最近 K 个按距离升序**填入；不足 K 补零。
- **碰撞/奖励/CBF 仍作用于全部 M 个**（`obstacle_cbf` 通道 (n,M,4)，CBF 不看 obs 窗口 → 安全不被"只看 8 个"限制）。
- `curriculum.levels` 最大值须 ≤ M（例 `[0,16]` 锁 16 或 `[0,8,16]` 渐进）。

**改文件**：`nav_vel_obstacles.py`（K/M/obs_window + build_obs 双路径）、`nav_vel.py`（M 解析、view 形状 (N,M)、_design_scene 建 M prim、info.obstacle_cbf spec (n,M,4)）、`NavVel.yaml`（注释+示例）。
**坑**：yaml `obs_window: null` 会盖掉 `M>K` 自动默认 → 已做 None-safe（`bool(M>K) if None`）。

## 4. D2 增密实验（下一步，待你拍板参数）

**可行性已 CPU 验证**（2048 env, 0 布局失败/0 端点净空违反；最窄球面缝 <0.3m 占比 14%→最高 40%）：
- 纯缩场（K=8 不变，半径/gap 不变）：场 [-2.0,2.0] → 缝<0.3m 24%、最窄中位 0.40m（D2b）
- 或 加 num_scene=16 + 场 [-2.2,2.2]：缝<0.3m ~同量级但 16 个球全都要躲（CBF/碰撞作用于 16）
- 或 更强：num_scene=16 + 场[-2.0,2.0] + 半径档[0.3,0.4,0.5] + gap0.2

**推荐 D2 起点**（示例命令，40M/臂，4 臂从同一 ckpt warm，`scripts/` 下先激活 lz_env）：

```bash
# D2 冒烟（num_scene=16 滑动窗口 + hybrid）
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
    task.obstacle.num_scene=16 'task.curriculum.levels=[0,16]' task.curriculum.initial_level=1 \
    task.curriculum.enabled=false task.cbf.mode=hybrid task.cbf.use_brake_term=false max_iters=1

# D2 4 臂模板（40M；naive/hybrid/filter_only/reward_only 只差 cbf.mode；warm 起点见下）
python -u train.py task=NavVel algo=ppo headless=true wandb.mode=online wandb.project=RL90 \
    wandb.run_name=NavVel-D2-16obs-<arm>-40M \
    task.obstacle.num_scene=16 'task.curriculum.levels=[0,16]' \
    task.curriculum.initial_level=1 task.curriculum.enabled=false \
    task.obstacle.reward_collision_edge=4 task.obstacle.reward_near_slowdown_weight=1.0 \
    task.cbf.mode=<none|hybrid|filter_only|reward_only> task.cbf.use_brake_term=false \
    algo.checkpoint_path=<D1 起点 ckpt> algo.entropy_coef=0.02 \
    total_frames=40_000_000 save_interval=50 2>&1 | tee /tmp/d2_<arm>.log

# D2 确定性评估（同训练 obstacle/cbf 配置）
python -u eval_ckpt.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
    task.obstacle.num_scene=16 'task.curriculum.levels=[0,16]' task.curriculum.initial_level=1 \
    task.curriculum.enabled=false task.obstacle.reward_collision_edge=4 \
    task.obstacle.reward_near_slowdown_weight=1.0 \
    task.cbf.mode=<与训练一致> task.cbf.use_brake_term=false \
    +checkpoint=<ckpt> +rollout_steps=600
```

**D2 起点建议**：4 臂都从 **A 臂 `lmhvaqka` final** warm-start 最公平（与 D1 同法）；obs 语义从"固定 8"变"最近 8"会有分布偏移，warm-start 只是起步，靠 40M + ent 0.02 适应。**eval 口径**：D2 也需确定性 eval_ckpt @600（train-final 仅参考）。
**预计效果（待验证）**：D2 密度下 naive 应明显退化、filter 频繁触发（cbf_violation↑）→ filter_only vs reward_only vs hybrid 三者才可能出现可观测差异（reward core 的防"贴障高速/对抗滤波"价值）。若 16 障仍分不开，可再抬 max_vel 或降 margin/α 做难度扫描。

## 5. git / 交接备注
- 分支：**`feat/obs-window`**（HEAD=`bee6a17`，基于 `feat/cbf`@`2ebad61`=c7aebed+注释汉化；D1 代码 = `feat/cbf` 原样，Run-10/11 与 D1 eval 不受影响）。`feat/crazyflie-pidrate` 仍未 merge CBF。
- 工作区仅剩他人 happo/mappo.yaml 未提交（勿纳入）。
- 待决策：①D2 增密参数（num_scene/场/半径/gap，见 §4 推荐）；②是否先 merge CBF（方案 A）或直接 D2 4 臂；③D1/D2 四臂对比图脚本（`scripts/` 写一个读取 eval 打印/汇总即可，数据源在 wandb summary + /tmp 日志）。
---

# 会话交接摘要 #3（2026-09-05 17:10，UTC+8；merge+tag 落袋 + D2-16 四臂 80M 已并行启动）

> **一句话现状**：**M2 已 tag `m2-achieved`**（`feat/cbf` → `feat/crazyflie-pidrate`@`2ebad61`）；**D2-16 四臂（naive/hybrid/filter_only/reward_only）× 80M 于 17:06–17:08 并行启动**（单卡 32GB、4 进程 ~18GB/64% util 安全），预计 ~30min（~45k fps/臂）。待完成 → 确定性 eval → 4 臂对比表/图。

## 1. 完成事项（含时间点）

| 时间(UTC+8) | 事项 | 结果 |
|---|---|---|
| 17:00–17:01 | **merge `feat/cbf` → `feat/crazyflie-pidrate`（fast-forward 到 `2ebad61`）+ tag `m2-achieved`** | `git tag -a m2-achieved`（说明含 D1 A/B 数字）；已切回 `feat/obs-window`@`3891356` 做 D2；工作区仅剩他人 happo/mappo |
| 17:02 | **CPU 探针排障**：初判 D2-16(场±2.2) 重叠 → 实为**探针对角 bug**；修正后 **M=16 布局健康**：0/2048 env 违反 nominal gap、最小球心距 0.65=理论下限、起终点净空 0 违反（场 ±2.0/2.2/2.4/2.6/2.8 全过） | D2-16 场 ±2.2 相对 D1(8球/5.6m) **密度约 ×3.3/m²** |
| 17:06–17:08 | **D2-16 四臂并行启动（80M/臂，warm `lmhvaqka` final，edge4+near1，关 brake，ent 0.02）** | 见 §2 run 表；单进程 ~7GB → 4 并行 ~18GB/32GB OK |
| 17:10 | naive 早期信号：arrival ~0.74–0.79 / **collision_episodes ~0.37–0.43**（vs D1 naive 稳态 0.165）→ **16 障密度对 naive 是显著升级**；熵 2.0→2.45 健康 | 分布偏移初期，等 80M 收敛再判 |

## 2. D2-16 运行配置（与 D1 相同奖励/超参，只改密度 + obs-window）

```text
obstacle:  num_scene=16(场景球数M)  max_slots=8(obs窗口K, 62维不变)  spawn_xy_range=[[-2.2,-2.2],[2.2,2.2]]
           radius_choices=[0.2,0.3,0.4]  min_gap_between=0.25  (几何探针确认 0 重叠/0 净空违反)
curriculum: levels=[0,16]  initial_level=1  enabled=false(锁16球)
obstacle 奖励: reward_collision_edge=4  reward_near_slowdown_weight=1.0   (与 A 臂 D1 同)
cbf:      mode per-arm; use_brake_term=false (所有臂同, 只有 mode 不同)
warm:     lmhvaqka final checkpoint;  entropy_coef=0.02;  total_frames=80_000_000;  save_interval=100
```

**run 表（wandb RL90）**：
| 臂 | run_name | run id | run dir |
|---|---|---|---|
| naive | NavVel-D2-16obs-naive-80M | `6q88ie60` | run-20260905_170612-6q88ie60 |
| hybrid | NavVel-D2-16obs-hybrid-80M | `dek234pt` | run-20260905_170714-dek234pt |
| filter_only | NavVel-D2-16obs-filteronly-80M | `fkzo2y0o` | run-20260905_170742-fkzo2y0o |
| reward_only | NavVel-D2-16obs-rewardonly-80M | (见 run 名) | run-20260905_1708?? |

日志：`/tmp/d2_{naive,hybrid,filteronly,rewardonly}_80M.log`（已 grep 过滤，含 train/stats + 每 iter 熵）。

## 3. 待办（训练完成后执行，本会话将自动被通知）
1. **确定性 eval**（4 臂各一次，@600 步；配置必须与训练一致，含 num_scene=16 / 场±2.2 / level1 / brake off / 各自 cbf.mode）：
```bash
# 模板（scripts/，先激活 lz_env）
python -u eval_ckpt.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
    task.obstacle.num_scene=16 'task.obstacle.spawn_xy_range=[[-2.2,-2.2],[2.2,2.2]]' \
    'task.curriculum.levels=[0,16]' task.curriculum.initial_level=1 task.curriculum.enabled=false \
    task.obstacle.reward_collision_edge=4 task.obstacle.reward_near_slowdown_weight=1.0 \
    task.cbf.mode=<与训练一致> task.cbf.use_brake_term=false \
    +checkpoint=<.../checkpoint_final.pt> +rollout_steps=600
```
2. 汇总 4 臂 arrival/joint/collision/min_clearance/cbf_violation/熵，与 D1 同口径出对比表；写 4 臂对比图脚本。
3. 若 naive 在 D2 崩太狠（collision 高企不降）也**保留**——正是"高密度 naive 到顶、CBF 显价值"的主战场叙事；reward_only vs filter_only vs hybrid 在 D2 的差异是本次要回答的核心问题。
4. 结果回填到 §2 表 + 收尾决策（merge obs-window / tag 等）。

---

# 会话交接摘要 #4（2026-09-05 18:00，UTC+8；D2-16 四臂 80M 训练收官 + 确定性 eval + 绘图）

> **一句话现状**：D2-16 四臂 ×80M 全部跑完（17:06→17:50），确定性 eval 完成。**filter_only 一枝独秀但末期严重退化**（39M 峰值 arrival 0.639/coll 3.3% → 80M final arrival 0.401/coll 53%）；**naive(纯PPO) 与 reward_only 在 D2 彻底失败**（arrival≈0，coll env≈85–94%）；**hybrid(λ0.5) 熵塌缩后保守但可用**（arrival 0.318/coll 10.6%）。**重要运维教训：4 训练进程同时进最终 eval(600步渲染)会 CUDA OOM**（naive/hybrid 崩，无 checkpoint_final）。

## 1. 时间线（17:06–17:57）

| 时间(UTC+8) | 事项 | 结果 |
|---|---|---|
| 17:06–17:08 | 4 臂并行启动 80M（warm `lmhvaqka`，ent0.02，edge4/near1，brake off，各自 cbf.mode） | run：naive `6q88ie60` / hybrid `dek234pt` / filter_only `fkzo2y0o` / reward_only `h9kwxv4g`；日志 `/tmp/d2_*_80M.log` |
| ~17:19–17:45 | 训练全程观察（详见 §2） | hybrid 早崩（~19M 熵塌缩）；filter_only 中段最好、>60M 退化 |
| 17:48–17:50 | 4 进程先后到 80M，同时进 Final Eval(600步渲染) | **naive 与 hybrid 于最终 eval 阶段 CUDA/vulkan OOM 崩溃，未保存 `checkpoint_final.pt`**；filter_only(17:49)/reward_only(17:50) 完整保存 final ✓ |
| 17:51 | 清残留进程、确认 GPU 空闲 | hybrid 残留 pid 200124 kill 释放 7.5GB |
| 17:52–17:57 | **确定性 eval @600（eval_ckpt.py，1024 env）**：naive/hybrid 用 `checkpoint_78675968.pt`(~78.7M)，filter/reward 用 final；filter_only 补评中段 39/46/52M | 结果见 §3 |
| 17:57 | 出图 `scripts/plot_d2_ablation.py` | `figures/d2_ablation.png`（FigA 4臂终值 / FigB filter 退化 / FigC D1vsD2） |

## 2. 训练全程定性观察（四臂命运）
- **naive（纯 PPO）**：熵发散 ~2→16+，collision_episodes ~0.87–0.90、success≈0、arrival≈0.001 —— 16 球+最近-8 obs 远超纯 PPO 上限，彻底失败。
- **reward_only**：arrival/success≈0、collision ~0.82–0.86、cbf_violation ~0.55–0.71 —— CBF 惩罚信号在 D2 无法被学习消化，策略死亡。
- **hybrid（λ=0.5）**：~19M 起熵塌缩(log_std→确定性, entropy→-1.0+)，arrival ~0.28–0.33、collision 仅 4–6%（滤波+保守策略保平安）——**学习崩了但靠滤波"兜底"不撞**。
- **filter_only**：中段(≈25–55M) arrival 0.50–0.70/coll 1–4%/熵 2.7 健康；**>60M 末期退化**：熵发散至 ~4.9、collision 升 ~20→54%、cbf_violation>1.5 → 终值并非最优（下文 eval 证实）。

## 3. D2-16 确定性 eval 结果（eval_ckpt@600 / 1024env；与训练 obstacle/cbf 配置一致）
| 臂 | mode | ckpt(M) | arrival | joint success | coll env% | min_clear(m) |
|---|---|---|---|---|---|---|
| naive | none | 78.7 | **0.001** | 0.000 | **94.0** | -0.102 |
| reward_only | reward_only | 80.0 | **0.002** | 0.000 | **85.4** | -0.071 |
| hybrid | hybrid | 78.7 | 0.318 | 0.312 | **10.6** | 0.210 |
| filter_only(final) | filter_only | 80.0 | 0.401 | 0.343 | **53.2** | 0.095 |
| **filter_only(39M 峰值)** | filter_only | **39.0** | **0.639** | **0.627** | **3.3** | 0.279 |

**filter_only 退化轨迹**（确定性 eval）：39M 0.639/3.3% → 46M 0.599/3.7% → 52M 0.502/7.6% → 80M 0.401/**53.2%**。**峰值 ckpt = `checkpoint_39354368.pt`(≈39M)**。

**D1 vs D2-16 到达率对照**（D1=20–40M train-final；D2=确定性）：
naive 0.824→0.001、reward_only 0.580→0.002、hybrid 0.916→0.318、filter_only 0.934→(final 0.401 / 峰值 0.639)。

## 4. 结论
1. **CBF 滤波是高密度唯一能「学会+保住安全」的载体**：filter_only 峰值 coll 3.3%（滤波 16 球全监督）；naive/reward_only 全灭 → 密度×3.3/m² 处纯 PPO 与「软惩罚」都到顶，滤波硬约束成为分水岭（D2 终于把 D1 拉不开的四臂劈开）。
2. **hybrid(λ0.5) 熵塌缩**是失败（超参），但塌缩后仍靠滤波把 coll 压到 10.6% —— 说明滤波是"安全下限"提供者；hybrid 价值要在 λ 更小(0.1–0.2)且熵不塌缩时才能体现（可选补跑 hybrid-v2）。
3. **filter_only 末期退化（>60M）**是本次最意外发现：PPO 在后期熵重新发散导致策略劣化，最终 checkpoint 显著差于中段。**部署应取 39M 峰值 ckpt，或加熵/早停控制**。报告务必「终值 vs 峰值」双口径诚实呈现。
4. 运维：**勿再 4 进程并行做带渲染的最终 eval**（OOM 崩 2/4）。教训记录见 repo 记忆。

## 5. git / 下一步
- 分支仍是 `feat/obs-window`@`3891356`（未 merge/tag，D2 全部在其上进行）；`feat/cbf`→`feat/crazyflie-pidrate` 已 merge，`m2-achieved`@`2ebad61` 不变。
- 待决策：①merge `feat/obs-window` + tag（本次 D2-16 用 obs-window 产物，建议落袋，tag 如 `d2-16obs-achieved`）；②可选 hybrid-v2 补跑（λ=0.1–0.2，目标在 D2 找到不塌缩的 hybrid）；③报告：D1/D2 对比表 + 图已出（`figures/d2_ablation.png`），本摘要 §3 表可直接引用。
- 工作区仅剩他人 happo/mappo.yaml 未提交（勿纳入）。

---

# 会话交接摘要 #5（2026-09-05 19:50，UTC+8；CBF reward_weight λ 扫描 + hybrid 加长，定 λ 结论）

> **一句话现状**：针对「hybrid 避撞而放弃到达」问题，扫 λ（6 组 ×20M）+ hybrid 三档加长至 40M + λ0.05 续至 60M。**结论：①λ 越小越不保守（arrival 随 λ↓ 升）；②hybrid λ0.05 @40M = arrival 0.647 / coll 2.3% / joint 0.634，全面超过 filter_only 39M 峰值(0.639/3.3%/0.627)——CBF reward core 价值首次兑现；③~40M 是此任务 PPO 甜点，>40M 熵塌缩必然退化（λ0.05@60M 掉到 0.372、filter_only@80M 0.401 同机制）。**

## 1. 时间线（18:35–19:50）
| 时间 | 事项 | 结果 |
|---|---|---|
| 18:35 | train.py 加 `render_eval` 开关（commit `19e0ebb`）：false 时跳过最终 eval 渲染（并行多臂训练不再 OOM） | 6 组并行短训全程无 OOM，final ckpt 全保存 |
| 18:39–18:53 | **批1 4 组×20M**（warm D1 naive lmhvaqka-final，D2-16，ent0.02）：hybrid λ0.05/0.10/0.20 + reward_only λ0.10 | run 6gl6fe5l/tg5gg4yg/oftnar2h/lhdhukek |
| 18:44–18:59 | **批2 2 组×20M**：reward_only λ0.20/0.50 | run pw9zv1ay/tulelcvd |
| 18:52 | 曾尝试与训练并行 eval → **CUDA OOM 教训**：eval_ckpt 峰值 ~18GB，不能与训练进程并行（需 GPU 空闲串行，~35s/组） | — |
| 19:04–19:20 | 6 组确定性 eval（GPU 空闲串行）；GPU 空闲后选 λ | 见 §2 表 |
| 19:04–19:20 | **hybrid 三档各续 +20M → 总40M**（warm 各自 20M final） | run 190420-lncme4xw(0.05)/6g41ery4(0.10)/183i4uva(0.20) |
| 19:20–19:35 | **λ0.05 续至 60M**（warm 40M final） | run 191553-cpn9a7gm |
| 19:35–19:50 | 40M/60M eval + 曲线诊断 + 出图 `figures/d2_lambda.png` | 定 λ0.05@40M 为 hybrid 最佳 |

## 2. λ 扫描确定性 eval（@600/1024env；20M=warm 后短训，40M=续训，均为各自 final ckpt）
| 臂/λ | 帧数 | arrival | coll env% | joint success | 备注 |
|---|---|---|---|---|---|
| hybrid 0.05 | 20M | 0.558 | 2.6 | 0.546 | λ 越小越不保守 |
| hybrid 0.10 | 20M | 0.502 | 2.2 | 0.490 | |
| hybrid 0.20 | 20M | 0.460 | 1.9 | 0.452 | coll 最低但 arrival 低（保守偏置）|
| reward_only 0.10 | 20M | 0.662 | **45.3** | 0.436 | 无滤波 → 高到达高碰撞，不可用 |
| reward_only 0.20 | 20M | 0.543 | 43.4 | 0.390 | |
| reward_only 0.50 | 20M | 0.371 | 35.2 | 0.287 | 80M 长训更全灭 0.002 |
| **hybrid 0.05** | **40M** | **0.647** | **2.3** | **0.634** | **≥ filter_only 39M 峰值** |
| hybrid 0.10 | 40M | 0.539 | 2.7 | 0.531 | |
| hybrid 0.20 | 40M | 0.494 | 3.4 | 0.486 | 加长也救不回（λ 太保守）|
| hybrid 0.05 | 60M | **0.372** | 7.5 | 0.356 | 熵塌缩退化（entropy 1.46→1.03）|

**对照（上轮）**：filter_only 39M=0.639/3.3%/0.627（峰值）；filter_only 80M=0.401/53%（退化）；naive 78.7M=0.001/94%。

## 3. 核心结论（回答「避撞放弃到达 / 是否加长 / 如何调奖励」）
1. **机制实证**：CBF penalty(λ) 在 D2 高频触发下制造保守偏置——λ0.2 把 `cbf_violation` 压到 0.04（策略完全绕开罚区=放弃穿缝，arrival 卡 0.44-0.49 加长救不回）；λ0.05 保持 0.08-0.10 违例（接受适度罚区穿行）+ 滤波兜底 → 到达率持续升。
2. **λ 结论**：λ 必须小到「微调」而非「主导」。**hybrid λ0.05 @40M（run 190420-lncme4xw final）为 D2-16 最佳 CBF 臂**：arrival 0.647 / coll 2.3% / joint 0.634，全面 ≥ filter_only 39M 峰值 → **reward core（软 CBF 引导）在滤波兜底下的增益首次可观测**。
3. **加长价值**：20M→40M 有效（arrival 0.558→0.647）；**40M 是此任务 PPO 甜点**——λ0.05 续 60M 熵塌缩(entropy 1.46→1.03)导致退化 0.372，与 filter_only >60M 退化(39M 峰值/80M 崩)同机制。**勿再盲目加长；部署取 40M 峰值 ckpt**。
4. **reward_only 判死刑**：无滤波注定高碰撞（20M coll 35-45%），80M 长训全灭(0.002)。不做其长训。
5. 若还想推高：reward 层可试「罚滤波纠偏量 ||v_f-v_nom||」变体（仅动 CBF 项、不动共享奖励），或目标进度 shaping（动共享奖励则需 naive/filter 同步重训）——本轮未做（用户先看加长数据）。

## 4. git / 产物 / 下一步
- HEAD `feat/obs-window`（含 `19e0ebb` render_eval 开关 + plot 脚本）；工作区仅他人 happo/mappo 未提交。
- 图：`figures/d2_lambda.png`（A: 20M λ 扫描 / B: hybrid 加长轨迹-40M 甜点 / C: arrival-coll trade-off）；`figures/d2_ablation.png`（前一轮 D1/D2）。
- 脚本：`scripts/plot_d2_lambda.py`、`scripts/plot_d2_ablation.py`（数据内嵌可复现）。

# 会话交接摘要 #6（2026-09-05 20:15，UTC+8；penalty_src=correction 20M λ 扫描 + 40M 续训，定方案 A 结论）

> **一句话现状**：实现并验证「罚滤波纠偏量」reward 变体（`task.cbf.penalty_src=correction`，commit `deb97b7`，默认 nominal 基线不动）。4×20M λ 扫描 + λ0.05/0.10 续至 40M。**结论：①方案 A 成功——correction λ0.05 @20M = arrival 0.682 / coll 2.1% / joint 0.669，D2-16 迄今最佳 CBF 臂，超 nominal λ0.05@40M(0.634) 与 filter_only 39M(0.627)；②correction 甜点在 ~20M，加长到 40M 反而退化（与 nominal 相反）→ 取 20M 峰值 ckpt，勿加长；③下一步候选 = 方案 B（强化目标进度 shaping）快速探针。**

## 1. 时间线（20:00–20:15）
| 时间 | 事项 | 结果 |
|---|---|---|
| 20:00 | **实现 `penalty_src`**（nav_vel.py + NavVel.yaml，commit `deb97b7`）：reward core 复跑 `filter_velocity`，correction 模式罚 `||v_filtered−v_nom||`（`reward −= λ·corr`）；不新增 info key/spec；reward_only 自动回退 nominal | cbf_test.py 全 PASS + GPU 冒烟无错 |
| 20:05–20:07 | **correction 4×20M 并行扫描**（warm lmhvaqka-final，D2-16，ent0.02，render_eval=false）：λ0.05/0.10/0.20/0.50 | run 194105-d0c3otz5/gv7qekih/5d4gw9ke/owq21gzo |
| 20:07 | 4 组确定性 eval | 见 §2 |
| 20:08–20:12 | **λ0.05/0.10 各续 +20M → 40M**（warm 各自 20M final） | run 195900-uipsb1vj(0.05)/iiaia2eq(0.10) |
| 20:13 | 40M final + 39.7M 邻点 eval | 见 §2（均退化）|

## 2. penalty_src=correction 确定性 eval（@600/1024env）
| 变体/λ | 帧数 | arrival | coll env% | joint | 备注 |
|---|---|---|---|---|---|
| corr 0.05 | 20M | **0.682** | 2.1 | **0.669** | **全场最佳 = 方案 A 交付** |
| corr 0.10 | 20M | 0.531 | 2.0 | 0.524 | |
| corr 0.20 | 20M | 0.509 | 1.5 | 0.503 | |
| corr 0.50 | 20M | 0.368 | 1.4 | 0.363 | |
| corr 0.05 | 39.7M | 0.575 | 3.3 | 0.562 | 加长退化 |
| corr 0.05 | 40M | 0.521 | 3.4 | 0.503 | 加长退化 |
| corr 0.10 | 40M | 0.442 | 5.1 | 0.432 | 加长退化 |

**对照**：nominal λ0.05@20M=0.558/2.6%/0.546；nominal λ0.05@40M=0.647/2.3%/0.634；filter_only 39M=0.639/3.3%/0.627（峰值）；naive/reward_only 长训全灭(<0.01/85%+)。

## 3. 核心结论
1. **方案 A 验证成立（用户选择正确）**：correction 在同 20M 训练量下全线超 nominal（λ0.05 arrival +12.4pt、λ0.10 +2.9、λ0.20 +4.9），碰撞同低。罚「滤波实际纠偏量」消除「远离罚区」保守偏置，策略学会安全近穿。
2. **correction 甜点在 ~20M（与 nominal 的 40M 相反）**：加长到 40M arrival −16pt、coll 2.1→3.4%、min_clearance<0.1 count 57→159 —— 机制：一旦学会安全近穿，correction 罚几乎恒 0（滤波不拦就不罚），后期无信号约束 → 策略被 shaping 推向越贴越狠的冒险区，探索耗尽后擦边碰撞反弹。**correction = 快速收敛型配方：20M 即 peak，勿加长（部署取 d0c3otz5 final）。**
3. **当前 D2-16 最佳 = corr λ0.05 @20M**（run `194105-d0c3otz5` final，path `scripts/wandb/run-20260905_194105-d0c3otz5/files/checkpoint_final.pt`）：arrival 0.682 / coll 2.1% / joint 0.669。

## 4. 方案 B 决策建议（目标进度 shaping 强化，用户要求准备）
- **可扫键**：`task.reward_pbrs_weight`（NavVel.yaml 顶层，默认 2.0，0=关）+ `pbrs_gamma` 0.995；reward core `w·(d_{t-1}−γd_t)`。B 动共享奖励 → 公平需 4 臂(naive/filter_only/hybrid/reward_only) 同 w 同步重训（成本 4×~20-40M）。
- **推荐两段式（省成本）**：①探针：仅 hybrid corr λ0.05 + `reward_pbrs_weight∈{4,8}` ×20M（2 并行 ~10min）看 shaping 增益是否显著（joint ≥+3pt 才值得全臂）；②若显著 → 对关键基线（naive/filter_only + 同 w）同步重训出公平终表。候选 w 也可取 {3,5,8,10}。⚠️ w 大 → 前向 shaping 与 obstacle penalty 面竞争，可能诱导冲撞，盯 collision/cbf_violation。
- **判断前提**：A 已把 CBF joint 推到 0.669（arrival 0.682），超 filter_only +6.7pt。若此幅度已够叙事收尾（D2-16 高密度下 CBF-variant 优势显著 + reward-core 变体方向实证），可不再上 B；若追求更高到达率再上探针。
- 待决策：①merge `feat/obs-window` + tag（建议 `d2-16obs-achieved`，D2 全程产物）；②是否按 §3.5 试 reward 变体推高；③报告引用 §2/§3 表 + 两图。

# 会话交接摘要 #7（2026-09-05 21:40，UTC+8；B(shaping) 全链路收官 + w8 λ 网格定论 + 转向论文式高斯 correction）

> **一句话现状**：按两段式把 B（强化目标进度 shaping）做到底——w8 全臂公平重训 + w8 下 hybrid/reward_only λ 网格。**结论：①D2-16 当前最佳 = filter_only w8@20M（run `vaa0vtzz`）= 0.806/2.2%/0.789（shaping 增强对"纯滤波 + 强前向引导"组合最优）；②w8 下 hybrid corr 随 λ 增大单调下降（0.05≈0.72→0.1=0.615→0.2=0.49），更大 λ 无法追回 filter_only——强 shaping 驱动猛冲→滤波频繁纠偏→correction 罚大→拽回 hybrid，filter_only 无 reward-core 罚项所以 shaping 无阻力（臂序随 shaping 反转）；③reward_only 任意 λ 均高碰撞 38–46% 不可用；④已对照 CBF-RL 论文 Table II（navvel_rl_interface.md §3.6/3.7）——我们 correction 是论文 r_cbf 第二项(高斯核 exp(-d²/σ²)-1)的线性版，拍板实现 `penalty_src=gaussian` 做 hybrid 短训对照。**

## 1. 时间线（20:42–21:40）
| 时间 | 事项 | 结果 |
|---|---|---|
| 20:42–20:54 | **4 臂全臂公平重训（w8×20M，warm lmhvaqka）** | run 204342-suhpvg5q(naive)/vaa0vtzz(filter)/mu9vegr8(hybrid)/5m9d89kj(reward) |
| 20:54–21:00 | 4 臂 eval | **filter_only w8=0.789 反超 hybrid corr λ0.05=0.708–0.720**（关键反转）|
| 21:03–21:22 | **w8 λ 网格 4 组**（hybrid corr λ0.1/0.2 + reward_only λ0.1/0.2） | run 211103-vqgydmgz/6elcn0ao/3u5aksb9/9ysxhunl |
| 21:2x | λ 网格 eval | 见 §2（hybrid λ↑ 单调降；reward_only 全灭）|
| 21:30–21:40 | CBF-RL 论文对照 → 更新 `navvel_rl_interface.md` §3.6/3.7/§4/§5；拍板实现论文式高斯 correction | 本文档 §4 |

## 2. w8 λ 网格确定性 eval（@600/1024env，20M final）
| 臂/λ | arrival | coll env% | joint | 结论 |
|---|---|---|---|---|
| hybrid corr 0.05 | 0.723–0.766 | 1.1–2.1 | 0.708–0.757 | λ0.05 最优（含最优复现 72hwe717）|
| hybrid corr 0.1 | 0.618 | 1.4 | 0.615 | λ↑ arrival↓（19.7M 0.599）|
| hybrid corr 0.2 | 0.498 | 2.8 | 0.490 | 更保守（19.7M 0.502）|
| reward_only 0.05 | 0.743 | 43.4 | 0.500 | 无滤波高碰撞 |
| reward_only 0.1 | 0.672 | 46.0 | 0.441 | 同上（19.7M 0.477）|
| reward_only 0.2 | 0.577 | 39.6 | 0.411 | 同上（19.7M 0.438）|
| **filter_only w8（对照）** | **0.806** | **2.2** | **0.789** | **D2-16 当前最佳** |

## 3. 核心结论
1. **D2-16 最佳 = filter_only w8@20M（`204342-vaa0vtzz` final）**：arrival 0.806 / coll 2.2% / joint 0.789，超此前全部（含 hybrid corr w8 0.757）。shaping 增强把 filter_only 从 w2 的 0.627 推到 0.789（+16pt）。
2. **w8 下 hybrid corr λ 网格 = 单调下降**：更大 λ（0.1/0.2）无法追回 filter_only。机制：强 shaping 驱动猛冲→滤波频繁纠偏→correction 罚（=纠偏量）大→拽回 hybrid；filter_only 无罚项，shaping 无阻力生效。→ correction reward-core 的增益在弱 shaping（w2）为正、在强 shaping（w8）被冲淡甚至反转为负。
3. **reward_only 判死（w8 下也成立）**：任意 λ 无滤波都 coll 38–46%，shaping 只拉高 arrival（0.58–0.74）不解决碰撞。
4. **论文对照结论**（详见 `navvel_rl_interface.md` §3.6）：我们 correction = 论文 $r_{cbf}$ 第二项（高斯核 $e^{-\|\mathbf v_p-\mathbf v_s\|^2/0.5^2}-1\in[-1,0)$）的线性版；论文高斯形状**0 纠偏不罚、σ 内几乎无感、大纠偏饱和**——比线性 λ·corr 更稳，可能缓解 w8 下"correction 罚大拽回 hybrid"。**已拍板实现 `penalty_src=gaussian`（σ/λ 标定）做 hybrid 短训对照**，看能否让 hybrid 在强 shaping 下追回 filter_only。

## 4. 下一步（2026-09-05 21:40 拍板，用户指令）
1. **实现论文式高斯平滑 correction**（nav_vel.py reward core 加 `penalty_src=gaussian` + `correction_sigma`；NavVel.yaml 文档）。
2. **4×20M hybrid 短训对照（w8）**：gaussian λ∈{0.05,0.1,0.2}×σ0.5 + λ0.1×σ1.0（σ 变体）→ eval 对照 filter_only w8(0.789) / linear corr(0.72–0.76)。权重/σ 是否再调等首轮结果再定。
3. 结果回填：若 gaussian 能让 hybrid 追回/超 filter_only → 收尾 D2 报告 + 待决策①merge/tag；若仍不行 → 接受"强 shaping 下纯滤波最优"，以 filter_only w8 为交付，归档。

# 会话交接摘要 #8（2026-09-05 22:00，UTC+8；论文式高斯平滑 correction（`penalty_src=gaussian`）σ/λ 扫描）

> **一句话现状**：实现并验证论文式高斯平滑 correction（CBF-RL Table II $r_{cbf}$ 第二项，commit `afc6fa2`）。**结论：①高斯核有效——w8 下相对 linear correction 同 λ 提升 λ0.1: 0.615→0.700–0.732(+8~11pt)、λ0.2: 0.49→0.63，坐实"线性大纠偏过罚"假设；②σ 标定 σ0.5(论文默认)最优(0.70–0.73)、σ0.3 略低、σ1.0 过宽容近无 reward-core(0.60–0.65)；③gaussian 最佳(σ0.5 λ0.1 ≈0.732@19.7M, coll 1.1%)仍低于 filter_only w8(0.789)——reward-core 家族在 w8 强 shaping 下都追不回纯滤波。用户拍板：补 hybrid gaussian λ0.05/λ0.2 档再验。**

## 1. 时间线（21:38–22:00）
| 时间 | 事项 | 结果 |
|---|---|---|
| 21:38 | **实现 `penalty_src=gaussian`**（nav_vel.py + NavVel.yaml，commit `afc6fa2`）：$\text{pen}=\lambda(1-e^{-\text{corr}^2/\sigma^2})\in[0,\lambda)$，σ=`correction_sigma` 默认 0.5 | get_errors 通过 |
| 21:36 | ⚠️ 发现 GPU 已被另一起并行会话/用户用 `penalty_sigma` 键启动 4 个 gaussian 进程（早于实现→实跑 nominal）| 按用户拍板 kill；键名统一为 `correction_sigma`（教训：多会话并发同一 GPU/仓库会撞车）|
| 21:41–21:52 | **gaussian-v2 网格 4×20M（w8，warm lmhvaqka）**：σ0.3/0.5/1.0×λ0.1 + σ0.5×λ0.2 | run 214135-ve4b8ywt / 214134-z36ag4ib / 7aserinl / r6isvs8p |
| 21:52–21:58 | 8 次确定性 eval（final + 19.7M）| 见 §2 |
| 22:00 | 用户拍板：回填本文档 + 补 hybrid gaussian λ0.05/λ0.2 档 | 进行中 |

## 2. gaussian-v2 确定性 eval（@600/1024env，w8，20M）
| σ | λ | 20M final (arr/coll/joint) | 19.7M 邻点 |
|---|---|---|---|
| 0.3 | 0.1 | 0.695 / 2.7 / 0.683 | 0.659 |
| **0.5** | **0.1** | 0.716 / 2.5 / 0.700 | **0.738 / 1.1 / 0.732** ⭐ |
| 1.0 | 0.1 | 0.620 / 2.2 / 0.604 | 0.645 |
| 0.5 | 0.2 | 0.636 / 1.3 / 0.631 | 0.604 |

**对照（w8，20M）**：linear correction λ0.1=0.615、λ0.2=0.49、λ0.05(最优复现)=0.757；filter_only=**0.789**；naive/reward_only coll 43–49%。

## 3. 核心结论
1. **高斯平滑 = reward-core 的正确升级**：线性 correction 对"大纠偏"线性放大 → w8 强 shaping 下滤波频繁纠偏时过罚、拽回 hybrid；高斯核大纠偏饱和到 λ → 缓解过罚（λ0.1 +8~11pt、λ0.2 +14pt）。
2. **σ0.5（论文默认 ≈0.28·v_max）标定合理**：σ 小(0.3)更敏感=罚更多略降；σ 大(1.0)过宽容≈关 reward-core 明显降。
3. **reward-core 家族（nominal/linear-corr/gaussian）在 w8 强 shaping 下均追不回 filter_only（0.789）** → 机制已坐实：强 shaping 与"罚滤波纠偏"的 reward-core 在抢夺同一自由度（猛冲 vs 被拦）；filter_only 无罚项所以 shaping 无阻力。
4. **D2-16 终局（当前证据）**：filter_only w8=0.789 为最高 joint；reward-core 侧 best = gaussian σ0.5 λ0.1≈0.732。
5. **下一步（用户 22:00 拍板）**：补 hybrid gaussian **λ0.05 与 λ0.2**（λ0.2 σ0.5 复跑确认方差 + λ0.05 补 σ 网格 {0.3,0.5,1.0}），看 λ0.05 能否借高斯形状逼近 filter_only。

# 会话交接摘要 #9（2026-09-05 22:15，UTC+8；gaussian-v3（λ0.05/λ0.2 补档）+ reward-core 大结论 + value_loss→0 峰值问题）

> **一句话现状**：gaussian λ0.05/λ0.2 补档跑完（22:12）。**结论：①gaussian peak = σ0.3/λ0.05 ≈0.748@19.7M（final 0.727）≈ linear corr λ0.05(0.757)，仍未超 filter_only w8(0.789)；②reward-core 大结论坐实——弱 shaping(w2) 下 corr hybrid(0.669)>filter_only(0.627)，强 shaping(w8) 下 filter_only(0.789) 领先全部 reward-core 变体(~0.75)；③value_loss 训练早期即趋 0（critic 收敛快），后期 policy 仍漂移 → mid-ckpt 常为真实峰值（本项目一贯"取峰值 ckpt"实践）；④filter_only 最优机制 = 强 shaping 全部转前向收益 + 滤波硬兜底无罚，reward-core 的"罚纠偏"与 shaping 抢同一自由度（猛冲 vs 被拦）。**

## 1. 时间线（22:00–22:15）
| 时间 | 事项 | 结果 |
|---|---|---|
| 22:00 | 用户拍板：先回填文档 + 补 gaussian λ0.05/λ0.2 | — |
| 22:01–22:12 | **gaussian-v3 4×20M（w8）**：λ0.05×(σ0.3/0.5/1.0) + λ0.2 σ0.5 复跑 | run 220116-kr42d3g8/220117-1fto9qrg/wi1c7a6b/4aeuie39 |
| 22:12–22:15 | 8 次确定性 eval | 见 §2；用户提问 value_loss→0 峰值价值 → §3/§4 |

## 2. gaussian-v3 确定性 eval（@600/1024env，w8，20M）
| σ | λ | 20M final (arr/coll/joint) | 19.7M 邻点 |
|---|---|---|---|
| **0.3** | **0.05** | 0.736 / 1.3 / 0.727 | **0.767 / 2.3 / 0.748** ⭐ |
| 0.5 | 0.05 | 0.670 / 2.0 / 0.658 | 0.683 |
| 1.0 | 0.05 | 0.738 / 2.1 / 0.723 | 0.744 |
| 0.5 | 0.2 | 0.616 / 2.0 / 0.608 | 0.613（复跑 v2 0.631 → 方差小 ✓）|

**gaussian 家族全网格小结（w8）**：peak ≈0.748(σ0.3 λ0.05) / 0.744(σ1.0 λ0.05) / 0.732(σ0.5 λ0.1) —— λ0.05 档略好、σ 交互有噪声；λ0.2 一律 0.61–0.63（λ 大保守）。**仍 < filter_only 0.789（~4pt）**。

## 3. 用户提问①：value_loss→0 后训练中出现的（arrival/性能）峰值有价值吗？
- **答：有价值——这正是本项目反复使用的"取峰值 ckpt"实践的依据**（filter_only 39M peak 而非 80M final；correction/gaussian 取 ~19.7M/20M peak；nominal λ0.05@40M peak 而非 60M 熵塌缩）。价值_loss→0 只说明 **critic 已把当前价值拟合到近 0 残差**（或 return 分布收窄/过拟合），**不代表 policy 已最优**；PPO 后期 policy 仍会持续漂移（非平稳目标权衡、熵下降、shaping 单向驱动），final 常非最优。
- **判定要点**：mid 峰值要可信需 (a) **确定性 eval 验证**（train-stats/单 rollout 峰值含探索噪声，仅参考）；(b) **邻点一致性**（19.7M vs 20M 双点看趋势，本项目已做）；(c) 与机制自洽（峰值通常出现在"策略还没被 shaping 推到过激/或还没塌缩"的窗口）。用户观察 corr_w8_hybrid@187step 与 gauss-sig0.5-lam0.1@168step 的最优 arrival（wandb train-stats 峰值）若落在 ~6M(≈187 iter×32.8k) 附近早于 19.7M ckpt → 建议对该 run 的早期 ckpt（checkpoint_6586368@6.5M 附近）补做确定性 eval 验证是否真是更优部署点。
- 补充：value_loss 在本任务**训练早期就趋 0**（实测 v3 前数 iter 0.80→0.33→0.25→0.14→0.05），因此"趋 0 后"几乎覆盖整个后期 → 该阶段看的是 policy 漂移 + 熵/exploration 而非 critic 拟合度。

## 4. 用户提问②：为什么现在 filter_only 是最优的？（机制）
1. **强 shaping(w8) 是"推力"主源**：per-step 前向进度奖励远大于障碍/生存罚 → 策略被强力驱动直飞目标；shaping 越强收益越高（w2→w8 filter_only 0.627→0.789）。
2. **唯一拦"危险猛冲"的是 CBF 滤波（硬约束，无梯度）**：filter_only = shaping 全力驱动 + 滤波只做物理安全兜底 → 无冲突、无罚 → 到达率最高且碰撞被硬约束压住。
3. **reward-core（nominal/corr/gaussian）与 shaping 抢同一自由度**：shaping 奖励"猛冲拿进度"；correction/gaussian 惩罚"被滤波拦下（纠偏量）"。二者方向相反 → hybrid 只能在中间妥协（到达低于 filter_only 的全力 shaping）。w8 下滤波频繁拦截（强 shaping 驱动猛冲）→ reward-core 罚被频繁触发 → hybrid 被拽回。这是 w2 下 corr hybrid(0.669)>filter(0.627) 但在 w8 反转(0.789>~0.75) 的原因。
4. **后期（value_loss→0 后）reward-core 信号更稀**：hybrid 学会"安全近穿"后滤波少拦 → corr/gaussian 罚≈0 → 后期 shaping 独大，行为趋向 filter_only，但被早期"避免被拦"的妥协惯性 + 已降熵拖累 → 追不上从一开始就无 reward-core 的 filter_only。
5. **总结**：D2-16 高密度 + 强 shaping 下，安全由"滤波硬约束"保证、性能由"shaping"驱动，二者在 filter_only 中正交不冲突 → 最优；reward-core 把安全也塞进奖励梯度，与 shaping 目标冲突 → 次优。**filter_only w8（`204342-vaa0vtzz` final）= D2-16 交付**（0.806/2.2%/0.789）。

## 5. 待用户决策（收尾）
①merge `feat/obs-window` + tag（如 `d2-16obs-achieved`）；②对用户提到的早期峰值 ckpt（corr_w8_hybrid≈6M / gauss≈5.5M 附近）补确定性 eval 验证是否更优；③出 D2 最终对比图 + 报告（含 reward-core 家族结论与 filter_only 最优机制）。

## 6. 🔴 峰值重测修正（2026-09-05 22:2x，用户提问触发——"value_loss→0 后 mid 峰值有价值吗" → 实测：极有价值，此前漏判）
用户从 wandb 观察到 corr_w8_hybrid@187step / gauss-sig0.5-lam0.1@168step 的 train-arrival 峰值（≈6.1M/5.5M 帧），触发对**早期 ckpt 的确定性 eval 重测**。三者 mid-ckpt 轨迹（确定性 eval@600 joint）：

| 帧 | corr-w8-hybrid(`mu9vegr8`) | gauss σ0.5 λ0.1(`z36ag4ib`) | filter_only(`vaa0vtzz`) |
|---|---|---|---|
| 6.5M | **0.786** (arr0.798/coll1.7%) | **0.765** (0.774/1.6%) | 0.734 (0.742/1.1%) |
| 9.9M | 0.721 | 0.746 | 0.729 |
| 13.1M | 0.746 | 0.681 | 0.748 |
| 16.4M | 0.710 | 0.663 | 0.786 |
| 19.7M | 0.720 | 0.714 | 0.774 |
| 20M(final) | 0.708 | 0.700 | **0.789** |

**修正结论**：
1. **reward-core 变体（corr/gaussian）是"早峰型"**：~6.5M 即到确定性峰（corr 0.786 / gauss 0.765），此后过训震荡退化到 0.70-0.72。用户 wandb 看到的 train-arrival 峰值（168-187 iter）**被确定性 eval 证实为真实部署峰值**——此前只 eval 19.7M/20M 是**系统性漏判**（把 reward-core 判成"只有 0.72-0.75 追不上 filter"是错的）。
2. **filter_only 是"爬升型"**：无 reward-core 罚信号 → shaping 持续驱动 → 单调爬升到 20M 仍高位（0.789 稳定）。
3. **按"各自峰值"公平对比：corr-w8-hybrid@6.5M (0.786, coll1.7%) ≈ filter_only@20M (0.789, coll2.2%) —— 几乎打平**，且 reward-core 用 **1/3 训练量**、碰撞更低。→ "filter_only 全面最优"需修正为：**20M 单点/收敛稳定性口径下 filter_only 最优；峰值/效率口径下 corr-hybrid@6.5M 与之持平甚至更优**。
4. **教训**：reward-core（correction/gaussian）必须在**训练早期（~6M）评估/早停**取峰值 ckpt（value_loss 趋 0 后 mid 峰值真实且有价值）；按 nominal/filter 的 20M 节奏会漏峰。这与本项目早年"熵塌缩别盲加帧、取峰值"教训一致，现扩展为"reward-core 早峰快退，需早停"。
5. 待决策更新：交付候选 = filter_only w8@20M(0.789, 稳定) **或** corr-hybrid w8@6.5M(0.786, 早停 1/3 训练量)；是否对 gaussian 全网格与其他 reward-core run 统一重扫 6.5M 峰值做最终公平表。

## 7. 🔵 峰值公平终表（2026-09-05 22:45，统一重扫全部 reward-core 变体 @6.5M）

**6.5M ckpt 确定性 eval（@600/1024env，w8，全部 reward-core run）：**

| 变体 | run | @6.5M (arr/coll/joint) | 该 run 已测最高点 |
|---|---|---|---|
| **corr λ0.05** | `mu9vegr8` | 0.798 / 1.7 / **0.786** ⭐ | 6.5M（20M 掉 0.708）|
| corr λ0.05 | `72hwe717` | 0.779 / 1.4 / 0.772 | 6.5M |
| gauss σ0.5 λ0.1 | `z36ag4ib` | 0.774 / 1.6 / 0.765 | 6.5M |
| gauss σ0.5 λ0.2 | `r6isvs8p` | 0.771 / 1.2 / 0.763 | **6.5M**（20M 掉 0.631！λ0.2 是早峰典型）|
| gauss σ0.5 λ0.2 v3 | `4aeuie39` | 0.763 / 1.6 / 0.754 | 6.5M（20M 掉 0.608）|
| gauss σ0.5 λ0.05 | `1fto9qrg` | 0.753 / 1.7 / 0.741 | 6.5M |
| gauss σ1.0 λ0.05 | `wi1c7a6b` | 0.738 / 1.2 / 0.733 | 19.7M=0.744（非单调）|
| gauss σ0.3 λ0.05 | `kr42d3g8` | 0.733 / 1.6 / 0.725 | 19.7M=0.748（非单调）|
| gauss σ0.3 λ0.1 | `ve4b8ywt` | 0.735 / 1.8 / 0.724 | 6.5M |
| gauss σ1.0 λ0.1 | `7aserinl` | 0.726 / 2.0 / 0.712 | 6.5M |
| **filter_only（对照）** | `vaa0vtzz` | 0.742 / 1.1 / 0.734 | **20M=0.789**（爬升型）|

**峰值公平终表（各取已测最高点）：**

| 排名 | 配方 | peak joint | 所需帧 | coll | 类型 |
|---|---|---|---|---|---|
| 1 | filter_only w8 | **0.789** | 20M | 2.2% | 爬升型·final 即峰 |
| 1≈ | **corr λ0.05 w8 (`mu9vegr8`)** | **0.786** | **6.5M** | **1.7%** | 早峰型·需早停 |
| 3 | corr λ0.05 w8 (`72hwe717`) | 0.772 | 6.5M | 1.4% | 早峰型 |
| 4 | gauss σ0.5 λ0.1 | 0.765 | 6.5M | 1.6% | 早峰型 |
| 5 | gauss σ0.5 λ0.2 | 0.763 | 6.5M | 1.2% | 早峰型 |

**结论（修正完成）**：
1. **peak 口径下 corr-hybrid w8 λ0.05 @6.5M(0.786, coll1.7%) ≈ filter_only @20M(0.789, coll2.2%)**——reward-core 不再"追不上"，而是**持平 + 碰撞更低 + 训练量 1/3**。
2. reward-core（尤其 λ0.2 gaussian）普遍**早峰明显、late 深退化**（σ0.5 λ0.2: 6.5M 0.763 → 20M 0.631），证实必须早停取 ~6.5M。
3. gaussian σ 大(1.0)或 λ 极端时有非单调（个别 run 19.7M 略高于 6.5M），但整体早峰在 6.5M。
4. **交付叙事建议**：若强调"收敛稳定性/简单训练节奏"→ filter_only w8@20M；若强调"峰值性能 + 低碰撞 + 训练效率"→ corr-hybrid w8@6.5M（`mu9vegr8` ckpt_6586368）。两者 joint 0.786-0.789 无统计显著差。
5. 教训已两次验证：**reward-core 需早期(~6.5M)峰值选择**（详见 §6）。

# 会话交接摘要 #10（2026-09-05 23:1x，UTC+8；轨迹图 + D2-16 收官 merge/tag）

> **一句话现状**：出轨迹图 `figures/d2_peak_trajectory.png`（corr-hybrid / filter_only / gauss 三条确定性 eval 轨迹）并把图与解读并入本文档；`feat/obs-window` 已并入 `feat/crazyflie-pidrate` 并 tag `d2-16obs-achieved`。**D2-16 收官：交付二选一（无显著差）——filter_only w8@20M（0.789，爬升/稳定）或 corr-hybrid w8 λ0.05@6.5M（0.786，早峰/低碰撞/1/3 训练量）；核心经验 = reward-core 早峰快退需早停取峰值（详见文件开头 ⭐ 会话总结 B/C）。**

## 1. 轨迹图（figures/d2_peak_trajectory.png）

![D2-16 peak trajectory](figures/d2_peak_trajectory.png)

图：三条确定性 eval（@600/1024env）训练轨迹（x=帧 M，实线 joint / 虚线 arrival）：
- 🔴 corr-hybrid λ0.05 w8（`mu9vegr8`）：**早峰 0.786 @6.5M** → 过训震荡退到 20M 0.708；
- 🔵 filter_only w8（`vaa0vtzz`）：**爬升 0.734@6.5M → 0.789@20M**（final 即峰，无 reward-core 退化）；
- 🟢 gauss σ0.5 λ0.1 w8（`z36ag4ib`）：**早峰 0.765 @6.5M** → 跌到 16.4M 0.663 再回升。
- 灰色竖带 = early-peak window（~6.5M）；两条 reward-core 峰都落在其中，而 filter_only 在窗口内反而是低点（0.734）。峰值处碰撞：corr 1.7% < filter 2.2%。

## 2. 图解读（并入报告口径）
1. **13–16M 交叉后分道扬镳**：reward-core 早峰→过训退化；filter_only 后程反超→平台高位。**"谁最优"取决于取模窗口**：各自峰值 corr 0.786≈filter 0.789；都看 20M final 则 filter 0.789≫corr 0.708。
2. **设计含义**：reward-core 的价值 = 更快（1/3 帧数）到高 joint + 更低碰撞，代价是要早停选峰；filter_only 的价值 = 训练节奏简单（final 即峰）、收敛稳定。
3. 综合奖励设计（对报告/后续）：安全由 **CBF 滤波硬约束**保证；性能由 **shaping 前向驱动**；reward-core（correction/gaussian）在弱 shaping 时加速"学会安全近穿"、在强 shaping 时与推力抢自由度 → 权衡清晰。

## 3. D2-16 收官清单（git）
- ✅ commit `scripts/plot_d2_peak_trajectory.py`（轨迹图脚本，数据内嵌可复现）；
- ✅ `feat/obs-window` → `feat/crazyflie-pidrate`（fast-forward 并入，含 obs-window/num_scene、render_eval 开关、penalty_src nominal/correction/gaussian、plot 脚本）；
- ✅ tag `d2-16obs-achieved`；
- 工作区他人 happo/mappo 未动。图与结论已并入本摘要 + 文件开头 ⭐ 会话总结。

## 4. 待决策（交付叙事口径，二选一）
- ① 稳定/简单：filter_only w8@20M（`204342-vaa0vtzz` final）为 D2-16 代表；
- ② 效率/低碰撞：corr-hybrid w8 λ0.05@6.5M（`204342-mu9vegr8` ckpt_6586368）为轻量交付 + reward-core 价值代表。
- 后续实验启发见文件开头 ⭐ C（论文式两项组合 reward core / progress 归一化 / 鲁棒性验证 / filter_only 加长等）。

# 会话交接摘要 #11（2026-09-06 00:1x，UTC+8；CBF 敏感指标加测（阶段 A）——扰动鲁棒性曲线）

> **一句话现状**：给 `eval_ckpt.py` 加可选命令空间扰动（`+perturb=none|cmd_gauss|cmd_pulse` + `+perturb_strength`，注入在**策略原始 action 上、CBF runtime filter 之前**）+ 打印 `stats.cbf_violation`；对 4 臂 × 4 扰动档做确定性 eval，出 `figures/d2_cbf_robustness.png`。**结论：有 CBF runtime filter 的三臂（corr-hybrid/gauss-hybrid/filter_only）在全部扰动档把碰撞压在 ~1–3% 平台；reward_only（无 runtime filter）恒 ~44% 高位 → runtime CBF 滤波把"被扰动成不安全"的指令拦回，实证 CBF-RL"对不确定性鲁棒"主张。**

## 1. 工具扩展（eval_ckpt.py，2026-09-06 00:0x，默认行为不变）
- 新键：`+perturb=cmd_gauss|cmd_pulse`（`none` 默认）、`+perturb_strength`（默认 0.3）。`_PerturbWrapper` 包装 policy：`cmd_gauss`=每步高斯噪声加在 `action[...,:3]`；`cmd_pulse`=阵风脉冲（随机方向 ±strength、持续 5–8 步）。因 CBF filter 在 Compose 中先于 VelController 作用，扰动加在原始 action → **有 filter 的臂会被 CBF 拦回**，reward_only（do_filter=False）/naive（无 transform）不受拦 → 直测 runtime filter 兜底价值。
- eval 额外打印 `stats.cbf_violation`（per-step EMA，仅 filter/hybrid 臂有意义；=策略原始指令的 CBF 违反量，扰动越大拦得越多）。

## 2. 阶段 A 结果（确定性 eval@600/1024env，w8，collision env%）
| 臂（runtime filter） | none | gauss σ0.3 | gauss σ0.6 | pulse 0.6 |
|---|---|---|---|---|
| **corr-hybrid λ0.05** @6.5M（`mu9vegr8`）| 1.8 | 2.1 | 1.4 | 1.1 |
| **gauss σ0.5 λ0.1** @6.5M（`z36ag4ib`）| 0.9 | 1.7 | 1.1 | 1.2 |
| **filter_only** @20M（`vaa0vtzz`）| 2.9 | 2.7 | 1.7 | 1.8 |
| **reward_only（无 filter）** @20M（`5m9d89kj`）| 44.0 | 41.9 | 43.6 | 45.5 |

arrival/joint 也基本稳定（滤波臂 arrival 0.73–0.80 / joint 0.73–0.79 全档）；reward_only joint ≤0.51。`cbf_violation` 随扰动上升（filter_only σ0.6 达 0.37、hybrid 0.25、gauss 0.24 —— 滤波在扰动下拦得更多）；reward_only 报 ~0.15–0.28 但无物理兜底。

## 3. 解读（图 figures/d2_cbf_robustness.png，左=有 filter 放大 0–6%、右=reward_only 0–50%）
1. **④ 扰动鲁棒性**：命令扰动（σ0.3→0.6 高斯 / 阵风脉冲）下，三个带 CBF runtime filter 的臂碰撞保持在 **~1–3% 平台**（σ0.6 甚至略降，噪声打乱局部极小值 + 采样波动）；reward_only 恒 **~44%** → 滤波把不安全指令拦回，**无 filter 与有 filter 相差 ~15–20×**。
2. **① CBF 违反量**随扰动升（滤波拦截更多）→ 说明安全由滤波主动承担，非策略碰巧安全。
3. **②③ min_clearance**：reward_only 均值 0.13/<0.1 count ~550；滤波臂 ~0.35–0.39/<0.1 count ~30–50（gauss σ0.6 下最低 26）→ 贴障保守度分布强区分。
4. gauss-hybrid 无扰碰撞最低（0.9%）且全档平台最稳 → reward-core 变体 + 滤波组合在鲁棒性上不劣于纯 filter_only。

## 4. 待做（阶段 B，用户已确认）
实现 `+runtime_filter=false`（eval 强制跳过 CBFVelocityFilter transform，策略原指令直通）→ 同 ckpt 有/无 runtime filter 扰动对比（corr/gauss/filter_only/reward_only + naive 无 filter 基线）→ 量化 runtime filter 自身贡献。产出后回填 #12。

# 会话交接摘要 #12（2026-09-06 00:5x，UTC+8；阶段 B——runtime filter 有无对比，量化其安全贡献）

> **一句话现状**：给 `eval_ckpt.py` 加 `+runtime_filter=false`（eval 跳过 CBFVelocityFilter transform，策略原指令直通）。**结论：同 ckpt 关掉 runtime filter 后，corr/gauss/filter_only 的碰撞从 ~1–3% 飙到 ~36–41%（达到 naive/reward_only 的 ~44–47% 档）→ CBF runtime filter 是部署安全的决定性组件；三臂策略训练时把滤波当"安全背锅"，自身原指令并不安全（即使无扰动、关滤波也崩到 37–40%）。**

## 1. 工具扩展（eval_ckpt.py）
- 新键 `+runtime_filter=true|false`（默认 true=现状不变）：false 时装配段跳过 `build_cbf_filter` → 无 CBFVelocityFilter，policy 原指令直通 VelController。get_errors 通过。

## 2. 阶段 B 结果（确定性 eval@600/1024env，w8；collision env%）
| 臂 | runtime | none | gauss σ0.3 | gauss σ0.6 |
|---|---|---|---|---|
| **corr-hybrid λ0.05** @6.5M（`mu9vegr8`）| ON | 1.8 | 2.1 | 1.4 |
| | **OFF** | **38.4** | 36.5 | 37.1 |
| **gauss σ0.5 λ0.1** @6.5M（`z36ag4ib`）| ON | 0.9 | 1.7 | 1.1 |
| | **OFF** | **39.4** | 36.5 | 36.3 |
| **filter_only** @20M（`vaa0vtzz`）| ON | 2.9 | 2.7 | 1.7 |
| | **OFF** | **37.6** | 39.2 | 40.5 |
| reward_only（无 filter，对照）| — | 44.0 | 41.9 | 43.6 |
| naive（无 CBF，对照）| — | 47.0 | 47.9 | 45.7 |

off 时 arrival 反而升（corr 0.80/0.82、filter 0.86 vs on 0.79——不滤波冲更猛）但 joint 崩（0.54–0.57 vs on 0.77–0.79）；`cbf_violation` off 时降 ~0.006（无拦截）。

## 3. 解读（图 figures/d2_runtime_filter.png，log y；ON 实线 vs OFF 虚线 vs naive/reward 参考点线）
1. **runtime filter = 决定性安全组件**：同一策略开/关滤波，碰撞 1–3% → 36–41%（**>15×**），off 后与 naive(47%)/reward_only(44%) 同级 → 策略在滤波下训练、把滤波当"安全背锅"，自身指令不足以保证几何安全。
2. **即使无扰动、关滤波也崩**（corr 38.4% / gauss 39.4% / filter 37.6% @none-off）→ 说明训练出的策略依赖 runtime filter 才能部署，与 CBF-RL"滤波是部署必需的安全层"论点一致。
3. 扰动对 off 组影响小（已崩到顶，36–41% 波动）；扰动主要威胁 ON 组但被滤波吸收（平台保持）。
4. 三臂 off 碰撞(36–41%)仍略低于 naive(47%)/reward_only(44%) → 滤波下训练让策略指令带上部分安全几何，但远不够独立部署。

## 4. 结论（并入报告）
- **D2-16 部署形态 = 策略 + CBF runtime filter 必须同时在线**；无论 reward-core 变体（corr/gauss）还是纯滤波（filter_only），其安全都来自 runtime filter 而非策略本身。这正面回答"eval 是否也调用 cbf（runtime filter）"——是的，且它贡献了 ~15–30× 的碰撞压降。
- git 提交：`eval_ckpt.py`（perturb + runtime_filter + cbf_violation 打印扩展）+ `plot_d2_cbf_robustness.py` + `plot_d2_runtime_filter.py`。

# 会话交接摘要 #13（2026-09-06 01:2x，UTC+8；8 障密度下 runtime filter on/off 评估——隔离密度影响）

> **一句话现状**：把 eval 障碍数从 16 降到 8（num_scene=8、±2.2m、obs K=8 全窗，同批 ckpt），重做 runtime filter on/off。**结论：即使密度减半、策略天然更安全（8 障 ON 时 joint 0.83–0.89、碰撞 <1.5%），关掉 runtime filter 后碰撞仍从 <1.5% 飙到 ~19–23%（~15–20×），略低于 16 障的 36–41%（密度依赖），但仍只比 naive(27%)/reward_only(24%) 好一点 → CBF runtime filter 在 8 障下依旧决定性。**

## 1. 8 障 eval（collision env%，确定性 eval@600/1024env，w8，num_scene=8/±2.2/levels[0,8]）
| 臂 | runtime | none | gauss σ0.3 |
|---|---|---|---|
| **corr-hybrid λ0.05** @6.5M（`mu9vegr8`）| ON | 0.7 | 0.6 |
| | **OFF** | **20.0** | 20.6 |
| **gauss σ0.5 λ0.1** @6.5M（`z36ag4ib`）| ON | 0.9 | 0.3 |
| | **OFF** | **20.2** | 19.1 |
| **filter_only** @20M（`vaa0vtzz`）| ON | 1.3 | 0.3 |
| | **OFF** | **19.6** | 23.2 |
| reward_only（无 filter，对照）| — | 23.8 | — |
| naive（无 CBF，对照）| — | 27.0 | — |

8 障 ON 时 joint：corr 0.846–0.849 / gauss 0.834–0.850 / filter 0.862–0.887（arrival 0.84–0.89，密度低易达标）；OFF 时 arrival 反升但 joint 崩到 0.70–0.73。扰动 gauss0.3 下 ON 更稳（corr 0.6/gauss 0.3/filter 0.3%）。

## 2. 图（figures/d2_runtime_filter_8obs.png，log y；ON 实线 <1.5% vs OFF 虚线 19–23%，naive/reward 参考横线）
- ON 组 0.3–1.3% 底部平台；OFF 组 19–23% 高位平坦；naive 27%/reward_only 23.8% 参考线略高于 OFF。
- **8 vs 16 障对比**：OFF 碰撞 16 障 36–41% → 8 障 ~20%（密度依赖：障碍少→策略/滤波压力都小）；但 **ON 始终把碰撞压到 <1.5%** → filter 的"决定性贡献"与密度弱相关、始终成立。

## 3. 解读
1. **runtime filter 在 8 障依旧决定性**：on <1.5% vs off ~20%（~15–20×）；off 后 CBF 臂(~20%)只比 naive(27%)/reward_only(24%) 略好——滤波下训练带来的"部分安全几何"有限，独立部署仍远不够。
2. 密度依赖体现在 OFF 档绝对高度（16 障 36–41% → 8 障 ~20%），而非 filter 相对贡献（两种密度下都是 ~15–20× 压降）。
3. 印证 CBF-RL：安全 = runtime filter 硬约束（对密度鲁棒地提供），reward-core/策略前向只决定到达/效率。

## 4. git
- 提交 `plot_d2_runtime_filter_8obs.py`（数据内嵌可复现）。