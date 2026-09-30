# 2026-09-27 当前奖励设计审查：NavAcc C1 SoftAll V1

> **后续实现状态：** 下文第 1–5 节记录的是 V1 奖励审查与当时的建议。之后已按独立任务 `NavAccC1SoftAllRewardV2` 实现新奖励 `c1_progress_brake_boundary_dwell_v1`；V1 历史结论仍作为旧任务基线，不应把 V2 公式或实现状态套用到 V1。实现与测试详情见本文第 6 节及 [V2 最终报告](/home/lz/lzspace/experiment_artifacts/navacc_c1_soft_all_reward_v2_20260927_v1/final_report.md)。

## 1. 结论摘要

**审查对象。** 当前分支 `experiment/soft-boundary-10m`、提交 `95a436a9b75d29b2aa7fd736a33c441044c7500d`；最近完成的正式训练与最终评估为 `navacc_c1_c3bf_soft_all_1500_20260927_v1`，任务 `NavAccC1SoftAllV1`。本报告只读核查代码、配置和既有工件；没有修改奖励、运行训练或仿真。工作区原有大量未提交改动，本报告只新增此文档。

**当前奖励实际鼓励的行为（代码已证实）：** 在目标 0.5 m 外沿目标方向高速飞行；进入 0.5 m 后，每步按距离领取 **1.5～3** 的位置奖励，即使速度为零也能领取；名义加速度指令变化越小越好；成功停留 50 步后领取随到达时间递减的事件奖励；首次碰撞、坠地、越界和超时受到事件惩罚。奖励没有直接评价 CBF 修正量、soft slack 或真实执行加速度。

**最高优先级问题（证据强度分开）：** 近目标正奖励可以被停滞持续领取，属于**代码与公式已证实的激励冲突**；策略是否真的这样停滞，**尚待轨迹验证**。最终 1024 局评估为成功 0、越界 737、CBF 失败 275、坠地 11、超时 1，这是**数据已证实的结果**，却不能单凭这些结果把失败归因于奖励。最值得先做的是对固定策略、固定轨迹建立逐步奖励台账，同时记录目标距离和动作链；然后才能做固定 critic 的逐项去除 GAE 诊断。

## 2. 当前基线与事实来源

| 项目 | 生效事实与出处 |
|---|---|
| 任务与时间 | 三维距离 `d≤0.2 m` 连续 **50** 个外环步为到达，没有速度门槛；外环上限 1500 步，`0.002 s × 5` 子步 = `0.01 s/步`，最多约 **15 s**。`OmniDrones/cfg/task/NavAccC1SoftAllV1.yaml:17-23,61-66`；`OmniDrones/omni_drones/envs/single/nav_acc_c0_logic.py:118-122`。 |
| 动作链 | PPO 对三维无量纲采样变量 `z_policy` 计算 log-prob/ratio；`a_nom = 2·tanh(z_policy)` 为世界系名义加速度，单位 m/s²。预决策状态进入原始加速度 collision-cone C3BF，先尝试严格解，失败时启用 soft-all；有效的 `a_safe` 转为保持起始 yaw 的 RPYT，再由 Crazyflie 低层控制和物理仿真执行。**没有独立 yaw 策略动作。** `OmniDrones/omni_drones/utils/torchrl/navacc.py:220-232,254-304`；`OmniDrones/cfg/task/NavAccC1SoftAllV1.yaml:34-40,67-78`；`OmniDrones/omni_drones/learning/ppo/ppo.py:343-353`。 |
| 奖励时序 | `a_nom,t` 来自本次决策；速度、三维目标距离、碰撞与终止原因来自本次物理动作后的 `t+1` 状态；`progress_buf` 先加 1 再结算奖励。`OmniDrones/omni_drones/envs/single/nav_acc_c1_sim_pilot.py:318-328,383-418`。 |
| 终止优先级 | 非有限状态 > 碰撞 > 坠地 > 越界 > CBF 失败 > 到达 > 超时；超时为 `truncated`，其余终止原因为 `terminated`。坠地：`z<0.15 m`；越界：`|x|>3 m` 或 `|y|>3 m` 或 `z>3 m`。`OmniDrones/omni_drones/envs/single/nav_acc_c0_logic.py:125-146`；`OmniDrones/omni_drones/envs/single/nav_acc_c1_sim_pilot.py:402-408`。 |
| 运行数据 | 正式训练 seed 5421、1024 并行环境、306 更新、10,027,008 collector 帧；最终 checkpoint SHA `de3a0b092d2e56e87635c08e15e05bd71a6ca73dffb021b75e7f7bc478d7efba`，固定评估语料 SHA `8876c78f7a4e5bd4e7cffdc591df69bfcc05a85986bf1459ca999d5909672c64`，ID 0–1023 各一次。1024 个 episode 均有结局，共 318,889 个外环步，平均 311.415 步；其中 480 局至少发生一次 soft 执行。`../experiment_artifacts/navacc_c1_c3bf_soft_all_1500_20260927_v1/formal_run/final_1024_audited/independent_audit.json` 与 `merged_episodes.json`。 |

运行报告中的动作链与当前代码相符；报告给出了成功率与终止原因，**没有**给出完整逐步奖励分项台账或对应 critic 值。当前配置的 `reward.terminal_penalty: -20` 看似通用终止惩罚，但 C1 的覆盖实现没有读取它；不能把它算进现行奖励。配置中的 `soft_all.lambda_m_inv2: 1` 是求解器目标参数，**不是奖励权重**。`OmniDrones/cfg/task/NavAccC1SoftAllV1.yaml:72-78,118-130`；`OmniDrones/omni_drones/envs/single/nav_acc_c1_sim_pilot.py:383-419`。

## 3. 奖励清单与每步合计

记 `d_{t+1}` 为动作执行后无人机到目标的三维距离，`e_{t+1}` 为该位置指向目标的单位向量，`v_{t+1}` 为世界系线速度，`k_t` 为本步结束后的 episode 步数，`a_nom,t` 为本步世界系名义加速度。令 `clip(x,0,1)=min(1,max(0,x))`。所有下列数值均为**单环境、单个外环步**的无量纲 reward 数；各项没有再乘 `dt`。

| 类型与项 | 生效公式 / 触发 | 输入、实际鼓励与范围 | 代码 |
|---|---|---|---|
| 稠密：朝目标运动 / 目标区 | `d>0.5`: `1.5·clip((v·e)/1.8,0,1)`；`d≤0.5`: `1.5+1.5·(1-d/0.5)`。两个分支**互相替代**。 | 后继世界系速度 m/s、距离 m；区外鼓励向目标速度，反向速度无额外惩罚；区内只看位置，单步 `1.5～3`，不要求停稳。 | `nav_acc_c1_sim_pilot.py:384-393` |
| 稠密：名义动作平滑 | `-0.2·Σᵢ[(a_nom,t,i-a_nom,t−1,i)/2]²`；该 episode 第一决策为 0。 | 前后两次世界系名义加速度 m/s²，除以每轴 2 m/s² 后无量纲；惩罚**采样动作经 tanh 后的指令变化**，包括探索造成的变化，并非 `a_safe` 或真实运动。每步在 `(-2.4,0]`。 | `nav_acc_c1_sim_pilot.py:394-398`；复位 `:271-273` |
| 稀疏：首次碰撞 | 首次碰撞 `-2`，以后不再计该项。 | 三个障碍的 XY 净空与物理子步锁存；第一次事件。 | `nav_acc_c1_sim_pilot.py:308-316,402,411-413` |
| 稀疏：坠地 / 越界 | 若**选中的**终止原因为坠地 / 越界，分别 `-15 / -15`。 | 基于后继位置，只计终止帧。 | `nav_acc_c1_sim_pilot.py:403-415` |
| 稀疏：到达 | 若选中原因为到达，`40+40·clip(1-k_t/1500,0,1)`。 | 目标半径内连续 50 步；越早到达事件奖励越大，理论范围 40～80，按当前定义最早第 50 步约 78.667。 | `nav_acc_c1_sim_pilot.py:399-401,417-418` |
| 稀疏：超时 | 若选中原因为超时，`-60`。 | 第 1500 步若没有更高优先级终止原因。 | `nav_acc_c1_sim_pilot.py:405-418` |
| 终止但**没有直接事件项** | CBF 失败、非有限状态均没有专属加减项；非有限的**总 reward** 经 `nan_to_num` 时可被替换为 `-60`。 | CBF 失败仍因 episode 结束影响后续回报；不能把它记成配置里的 `-20`。运行故障须和碰撞分开。 | `nav_acc_c1_sim_pilot.py:406-419` |

代码位置除特别说明外均位于 `OmniDrones/omni_drones/envs/single/`。关闭的通用 effort、action/motion smoothness 和 soft-boundary risk 不进入这段 C1 奖励；`reward_action_smoothness_weight: 0` **不等于**上表的 C1 `smoothness_coefficient: 0.2` 关闭。来源：`OmniDrones/cfg/task/NavAccC1SoftAllV1.yaml:30-32,118-131`。

**每步稠密 + 稀疏合计（实际代码顺序）：**

```text
r_dense,t  = r_move_or_zone,t − 0.2·I_prev·Σᵢ[(a_nom,t,i−a_nom,t−1,i)/2]²
r_sparse,t = −2·I_first_collision −15·I_reason=crash −15·I_reason=oob
             −60·I_reason=timeout
             +[40+40·clip(1−k_t/1500,0,1)]·I_reason=arrival
r_total,t  = nan_to_num(r_dense,t+r_sparse,t, nan=−60, posinf=−60, neginf=−60)
```

`I_reason` 各项互斥；首次碰撞指示器单独结算，不能把所有事件项当作互斥类别。普通非终止步在 `d>0.5` 时稠密合计处于 `(-2.4,1.5]`，在 `d≤0.5` 时处于 `(-0.9,3]`；实际下界还受本步距离约束。终止帧在该稠密合计上再叠加相应事件值，因此不能把 `-60` 或 `+80` 误写成该步总回报。未发生过的 CBF 失败、碰撞等事件在同一步贡献为零。

| **仅用于读公式的合成单步示例** | 稠密正项 | 平滑项 | 稀疏项 | 本步合计 |
|---|---:|---:|---:|---:|
| 区外 `d>0.5`，朝目标速度 `1.8 m/s`，名义动作不变，未终止 | +1.5 | 0 | 0 | **+1.5** |
| 区内 `d=0.3 m`，速度 0，名义动作不变，未终止 | +2.1 | 0 | 0 | **+2.1** |
| 区内 `d=0.1 m`，第 50 步达到连续停留门槛，动作不变 | +2.7 | 0 | 到达 `+78.667` | **+81.367** |
| 区外同首行条件，越界为选中终止原因 | +1.5 | 0 | 越界 `−15` | **−13.5** |
| 区外 `v·e≤0`，名义动作不变，因 CBF 失败终止 | 0 | 0 | 0 | **0** |
| 区外 `v·e≤0`，名义动作不变，第 1500 步超时 | 0 | 0 | 超时 `−60` | **−60** |

表中仅是代入公式的**合成状态**，不是已有运行的实际单步统计，也不保证每种状态在物理与控制约束下可达。成功示例需在此前 49 步始终处于 `d≤0.2 m`。

## 4. 审查发现：证据、影响与验证

| 优先级 | 发现与证据强度 | 影响及下一步核查 |
|---|---|---|
| P0 | **近目标停滞有持续正回报（代码已证实）；实际发生未知。** `d=0.3 m、v=0、Δa_nom=0` 每步 +2.1，却在成功半径外。 | 在完整轨迹上看 `0.2<d≤0.5` 的停留步数、速度、净进展、回报占比，再确认停滞是否真实可行。 |
| P0 | **导航未成功、主要以越界或 CBF 失败结束（数据已证实）。** 固定 1024 局：到达 0、碰撞 0、越界 737、CBF 失败 275、坠地 11、超时 1。 | 这不能区分奖励、起飞/跟踪能力、CBF 可行性、控制饱和或任务可达性。分类检查首次偏离、CBF 严格/soft/held 状态与实际运动；尤其 CBF 失败不能简单归责于策略。 |
| P1 | **配置与实际奖励不一致（代码已证实）。** `terminal_penalty=-20` 未进入 C1 奖励；CBF 失败没有直接罚分。 | 文档与监控不能报告“所有终止 −20”。先辨别求解器域失败、真实不可行、数值异常，再讨论是否需要明确的失败奖励。 |
| P1 | **平滑惩罚评价采样名义动作（代码已证实），学习影响未知。** 后继真实运动和 CBF 后动作可能不同。 | 逐步记录 `z_policy、a_nom、a_safe、RPYT` 与相邻差；检查探索噪声、必要制动与 CBF 修正时段的分项贡献。不得直接改用 actor mean；若加可微正则则属于 PPO 算法修改。 |
| P1 | **现有工件不支持逐项奖励量级或 GAE 归因（数据已证实）。** 最终 episode 明细含结局、步长、CBF slack 等，未含每步奖励分项和 critic。 | 无法可靠给出真实均值、绝对均值、标准差、分位数、非零率、每局折扣累计、固定轨迹逐项去除 GAE；这些数值本报告不编造。 |

**轨迹回报的公式自检，不是实测行为。** 假设某 episode 能在 `d=0.3 m`、零速度和零平滑代价保持 1500 步，终帧仅受 `−60` 超时惩罚，则未折扣合计 `1500×2.1−60=3090`，以 `γ=0.99` 从该段起点折扣约 `210.000`。另假设一条不同状态下的 50 步轨迹始终 `d=0.1 m`，第 50 步成功且平滑代价为 0，则未折扣合计约 `213.667`，折扣约 `154.723`。两条合成轨迹**起点、长度和可行性不同**，只能说明持续占位奖励可能压过一次性成功奖励；不能据此断言当前策略真的在“刷分”，也不能把它当成严格同起点策略比较。

**GAE/PPO 的实际链条（代码已证实）。** `γ=0.99、λ_GAE=0.95`；价值先经 ValueNorm 反归一化，再由总奖励计算未归一化 GAE；`terminated` 关闭 bootstrap，`truncated` 仍可 bootstrap，但轨迹递推在 episode 边界截断；优势随后在整个训练批次归一化，return 经 ValueNorm 归一化供 critic 拟合，PPO ratio 对 `z_policy` 计算并以 0.1 裁剪。见 `OmniDrones/omni_drones/learning/ppo/ppo.py:194-200,290-326,343-353` 和 `OmniDrones/omni_drones/learning/ppo/common.py:28-64`。因此上面的单步数值与合成折扣回报**不是**某奖励项的 actor 梯度占比。只有完整同轨迹、同 critic、同 mask 与归一化口径下的去项重算，才能称作“固定轨迹上的直接 GAE 敏感度”。现有最终评估仅 1 局超时；但超时是否应作为任务内有限时域终止以及 bootstrap 所用最终观测是否为自动复位前状态，仍需在专门的采样轨迹中核查。

## 5. 设计建议与下一步一个验证

**先做一个只读验证：固定策略逐步奖励台账。** 对现有最终 checkpoint 和同一固定语料，若已有可重放逐步轨迹则只做离线重算；现有工件若不足，需另行授权一次**只评估不训练**的逐步采集。最低字段：episode/step 与 pre/post-reset 标识、`d_t,d_{t+1},v_{t+1}`、`z_policy,a_nom,t,a_nom,t−1,a_safe`、strict/soft/held 与失败子类、首次碰撞/终止原因、每项原始和加权 reward、`r_total`、`terminated/truncated`、`V_t,V_{t+1}`、ValueNorm 状态和采样时的 mask。优先覆盖全部 1024 个固定 episode；若只取子集，报告 ID、抽样方式、完整 episode 与截断片段数量，不混算。按正常导航、接近目标、越界、CBF 失败分层给出每项均值、平均绝对值、标准差、p5/p50/p95、非零比例及每局未折扣/折扣贡献；检查分项和与存储总 reward 是否逐步一致。随后在**固定轨迹与 critic**上逐项去除、按原流程重算未归一化 GAE，报告差值，不宣称重训因果效果。接受标准：逐步合计与环境 reward 在数值容差内一致，reset 后前一动作无泄漏，并能明确回答有多少局进入 `0.2<d≤0.5` 且发生停滞。**本验证未执行。**

**条件性的最小设计修改（建议，未实施）。** 如果台账证实目标区占位回报与导航目标冲突，优先只替换目标区 `1.5+1.5(1-d/0.5)` 的每步占位项；保留区外项、现有终止定义和其他奖励，用有界距离进展提供目标区反馈。若追求势函数塑形，应明确写成 `F(s_t,s_{t+1})=γΦ(s_{t+1})−Φ(s_t)`，并处理真实终止状态势值、超时 bootstrap 和有限时域状态；**不能**把普通 `d_t−d_{t+1}` 直接称为保持最优策略的塑形。权重暂不定值：先用真实目标区位移和回报贡献确定物理尺度，再用同起点的有效到达、停滞、绕行、失败轨迹比较折扣回报。风险是削弱 50 步停留所需的导航反馈，或放大高频进出边界；若固定语料评价的成功率、到达时间、越界/坠地/碰撞/CBF 失败率与进展没有改善，则回滚该**单项**替换。任何在线训练对照须另获授权，并冻结 CBF、控制链、任务分布、episode 上限、训练预算与种子安排；更换奖励后建立新实验 lineage，明确 critic/ValueNorm 初始化，不能把它称作目标不变的严格续训。

**其他前提仍待验证：** 当前控制器在该 15 s、该障碍分布和 CBF 模式下能否稳定起飞、悬停、跟踪并到达目标；CBF 失败中各子类的占比；最终观测是否在自动 reset 前用于 GAE bootstrap。缺少这些证据时，不把“0/1024 成功”归因于奖励设计。

## 6. 后续实现：NavAccC1SoftAllRewardV2

### 6.1 任务隔离与目标

新增训练任务 `NavAccC1SoftAllRewardV2`，奖励版本键为 `task.reward.version=c1_progress_brake_boundary_dwell_v1`。它沿用 V1 的 C1 场景、动作 transform、C3BF strict/soft-all 求解器与 λ=1、`0.0001 m/s` 低速阈值、R1 reset 准入、1024 环境配置、1500 外环步上限，以及三维距离 `≤0.2 m` 连续 50 步的无速度门槛成功条件。CBF 失败仍按旧合同 held-RPYT 并终止。

新任务和 checkpoint scope 独立于 V1。旧 V1 与既有无 CBF 制动奖励任务实现均未修改；V2 不接受旧 checkpoint warm-start。旧配置中的 `goal_zone_radius_m=0.5` 为继承的验证器兼容键，V2 最终奖励不使用 V1 的 0.5 m 区域占位正奖励。

### 6.2 V2 每步奖励

设 `d_pre` 为本次物理动作前的目标距离、`d_post` 为动作后的目标距离，`p_post` 和 `v_post` 为步后位置与世界系速度，`dt=0.01 s`。以下均为每个环境、每个外环步的 reward 数值：

| 分项 | 公式 | 含义与边界 |
|---|---|---|
| 有符号进展 `r_progress` | `1.5 · clamp((d_pre-d_post)/(1.8·dt), -1, 1)` | 朝目标进展为正，停滞为 0，远离目标为负；取代 V1 朝目标速度 / 0.5 m 圈内占位二选一正奖励。 |
| 目标制动 `r_brake` | `v_in=max(0, v_post·unit(goal-p_post))`；`gap=max(d_post-0.2,0)`；`v_allow=min(1.8,sqrt((a_ref·tau)^2+2·a_ref·gap)-a_ref·tau)`；`-2·clamp((v_in-v_allow)/1.8,0,1)^2` | 只惩罚过高的朝目标径向速度；切向速度本身不受罚，目标中心处方向数值稳定。`a_ref=0.7310784151477199 m/s²`、`tau=0.01 s`。`a_ref` 来自旧无 CBF 仿真探针，仅为奖励塑形参考值，不是当前 CBF/控制链的认证制动界。 |
| 边界预判 `r_boundary` | 对 `+x,-x,+y,-y,top,bottom` 六面计算 `v_out=max(朝外速度,0)`、`s_stop=v_out·tau+v_out²/(2·a_ref)`、`risk=clamp((s_stop+0.2-gap_face)/0.5,0,1)`；奖励为 `-2·max_face(risk²)` | 使用最大面风险避免角落重复计罚。是启发式奖励塑形，不是边界安全证明。 |
| 驻留 `r_dwell` | `0.2·1[d_post≤0.2]` | 只有成功半径内领取；0.2–0.5 m 区域没有持续位置占位奖励。不限制圈内总速度，允许切向环绕满足位置驻留。 |
| 名义动作平滑 | 保留旧项 `-0.2·Σ((a_nom,t-a_nom,t-1)/2)^2` | 仅平滑项继续沿用旧合同。 |

到达、首次碰撞、坠机、OOB、timeout 稀疏事件系数不变；不新增 CBF 失败惩罚。逐帧写入 `info/stats` 的字段包括 progress、brake、boundary、dwell、smoothness、dense total、稀疏事件合计、总奖励、前后目标距离、径向速度、允许速度、最大边界风险和对应边界面。Isaac smoke 核验 `dense + sparse events = total = agents.reward`，最大误差均为 0。

### 6.3 奖励时序与 reset 隔离

实际执行顺序为：V2 在外环 `_step` 开始时读取当前位姿与当前目标并缓存 `d_pre`；父类执行 5 个 2 ms 子步；步后更新无人机状态与 `rpos`；计算 `d_post` 和奖励；transition 返回后 TorchRL 对终止环境做选择性 reset。V2 的 `_reset_idx` 只清零被 reset 环境的 `d_pre` 缓存。配对 smoke 从同一目标快照和动作前/后的物理位姿独立重算 `d_pre/d_post`，两者匹配；被选择性 reset 的环境缓存清零，其他环境保留。

### 6.4 接线、回归与门槛

V2 新增纯 Torch 奖励模块和测试、独立 YAML 与环境类；扩展环境注册、现有 soft-all transform 工厂的任务白名单，以及训练入口的 CBF/soft-all collector 检查和 checkpoint sidecar。sidecar 包含任务名、奖励版本、完整 reward config 与 canonical SHA-256、Hydra 配置哈希、17 个源码哈希、动作链、到达规则和独立兼容范围 `NavAccC1SoftAllRewardV2-only`。奖励配置 SHA-256：`b7a7fd6048c23584aca3baceb6999b722d64094cb16cbdc4e8b8644c23462e39`。

已通过：纯 Torch CPU/CUDA 公式与合成轨迹排序；V2 四环境 Isaac wiring；旧 V1 与 V2 配对动作、RPYT、rotor、步后状态、终止原因及子步数量一致；reset 与前后状态时序核验；旧制动奖励、soft-all wiring/solver、CBF action-chain 和 PPO metrics 回归；Hydra 配置组成；metadata sidecar fixture 检查。验收结果均为代码接线门槛，不说明导航改善或安全性。

collector→PPO smoke 使用 4 环境、128 collector 帧、W&B disabled，完成一次 PPO 更新。首批 `z_policy` ratio 均值 1.0、最大偏离 `9.54e-7`，动作链重算误差为 0，策略动作、reward 和 PPO 指标有限。训练入口在更新后自动进入 `Final Eval`；该钩子在输出评估结果前被手动中断，没有保存模型 checkpoint。其 sidecar 结构以 dummy checkpoint fixture 独立验证。

**状态与限制：** 未启动正式 PPO 训练、未开启 W&B、未产生导航评估结果；V2 导航效果尚未建立。训练脚本自动 final-eval 钩子被短暂触发并在结果前中断，此偏差已记录，未重复运行。旧 V1 replay 记录 0/1024 到达、737 OOB、275 CBF 失败；之前无 CBF 制动奖励实验为 0/256 到达，未显示导航改善。因此新公式仅是隔离候选，不宣称有效。之后若请求正式训练，任务名必须为 `NavAccC1SoftAllRewardV2`，并校验 `task.reward.version=c1_progress_brake_boundary_dwell_v1`、`task.ppo.probability_action_key=z_policy`，从新策略初始化。

工件目录：`/home/lz/lzspace/experiment_artifacts/navacc_c1_soft_all_reward_v2_20260927_v1/`。最终实现报告为 `final_report.md`，机器可读哈希清单为 `sha256_manifest.json`，其 SHA-256 为 `e603e78ed22e2228a424a393fa2d9e02b8a322459d95adfd95e4622f2e67fe18`。两层 `git diff --check` 均通过；外层 `main` HEAD `8388713b36d52d82389c5acf9636218b00914628`、内层 `experiment/soft-boundary-10m` HEAD `95a436a9b75d29b2aa7fd736a33c441044c7500d`，既有 dirty/untracked 内容保留，未改子模块指针。
