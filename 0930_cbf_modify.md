# NavAcc C3BF 与双项奖励修改方案：统一接口、解析求解器对照及规模实验

日期：2026-09-30。用途：交给后续 AI agent 执行的实现与实验计划。

本轮只保存 Git 基线并编写计划，没有实现新的控制/奖励算法，也没有启动训练。**用户已确定动作和奖励要求；最终求解器由实验决定。C2 不是最终障碍物规模，不能以 C2 的四障碍物结果直接选定长期方案。**

## 1. Role / objective — 角色与目标

你是本项目的实现 agent。先核对当前工作树与本文基线的差异，再按“检查 → 契约 → 实现 → 测试 → 交付”推进。

目标是建立独立版本的 NavAcc C3BF 实验链，在统一的状态、动作、奖励和执行接口下比较不同解析过滤方法，得到随并行环境数 E、障碍物数 N 变化的计算开销、约束满足率和训练表现。不要在实现时预先把某个求解器设为新的项目默认。

用户已确定：

1. PPO 策略映射得到的三维名义加速度满足 `||a_nom||_2 <= 2 m/s²`。
2. C3BF 修正量及修正后的加速度不再施加这个 2 m/s² 限制。
3. `r_cbf` 必须同时包含名义 CBF 负安全余量和 `exp(-||a_nom-a_filtered||²/sigma_a²)-1`。
4. 求解采用解析投影/有限解析候选，不在逐步训练路径调用通用数值 QP 或收敛型优化器。
5. 对求解方案的争论通过可复现实验解决，涵盖后续更大的障碍物规模。

“解析投影”允许有限个解析候选的批量生成、校验和选择；单半平面一次投影是待比较方案之一。固定轮数的顺序投影只能列为明确标注的对照，不得冒充一次闭式解。

## 2. Authoritative sources — 权威来源与回退基线

优先级：本次用户明确需求 > 实际代码及解析后的运行配置 > 本计划中的建议参数 > 历史摘要。

已保存的本地 Git 基线：

| 仓库 | 分支 | 修改前快照 commit |
|---|---|---|
| `/home/lz/lzspace/drones/OmniDrones` | `experiment/soft-boundary-10m` | `764da248e1e167f9fe3042d65148bad654e221a0` |
| `/home/lz/lzspace/drones` | `main` | `2ab0cf3a7bcaec51379f6c9c37c30d3771217de7` |

两仓库共同标签：`navacc-pre-cbf-modify-20260930T030142Z`。外层快照的 `OmniDrones` gitlink 已指向上述内层快照。本文将在外层另行提交，因此不属于修改前的空文档快照。

备份范围清单：`/home/lz/lzspace/experiment_artifacts/navacc_cbf_modify_git_backup_20260930T030142Z/backup_manifest.json`。快照包含既有已跟踪改动/删除，以及未跟踪的源码、配置、测试、项目技能和设计文档。大批未跟踪生成报告、日志、检查点及图表未加入 Git，原文件保留；该快照是代码基线，不是实验数据全集备份。

必须阅读：

- `AGENTS.md` 及 `.agents/skills/` 中适用的项目上下文、实施流程、测试规则。
- `MinerU_markdown_Yang_等_-_2026_-_CBF-RL_safety_filtering_reinforcement_learning_in_training_with_control_barrier_functions_2054593947461390336.md`：式 (19)—(23)、(24)—(25)，不要混淆论文和项目符号。
- `OmniDrones/cfg/task/NavAccC2CaptureRewardV1.yaml`、`NavAccC2RCBFAExploratoryV1.yaml` 及其继承链。
- 近期真实配置：`/home/lz/lzspace/experiment_artifacts/navacc_c2_w01_resume_to_4m_20260929_v1/protocol/resolved_training_config_runtime.yaml`。

## 3. Current verified state — 当前已核实状态

当前 C2 主链：

```text
PPO z_policy（概率动作）
  -> scale * tanh(z_policy)，当前逐轴 scale=2
  -> 对全部 2 静态 + 2 动态障碍物构建 C3BF 行
  -> 最多 10 轮：最严重归一化违反行投影 + XY 圆盘/Z 区间投影
  -> 未通过时 analytic_candidates_v1 二维候选回退
  -> 严格失败且定义域有效时 soft-all-v1
  -> fail-open 候选/保持分支
  -> 加速度到 RPYT -> 固件 PID -> 旋翼 -> PhysX
```

- 当前 `a_nom=2*tanh(z_policy)` 是逐轴限制，不是三维球限制。
- CBF 输入包括全部活动障碍物，没有威胁 top-k 预筛选；`p=p_obs-p_uav`、`w=v_obs-v_uav`，当前 `a_obs_hat=0`。
- `soft-all` 是平方 hinge 违反量惩罚，不是 soft-min barrier。其实现有逐环境循环、`2**N` 分区枚举和圆盘 KKT 最多 80 轮二分。
- 当前严格模式仍限制 `||a_xy||<=2`、`a_z in [-2,2]`；贪心找到可行点即返回，不保证完整链的全局最近投影。
- `r_cbf_A` 是最大归一化、截断后的名义行违反量，缺少指数修正项；无效行通过 valid mask 表示未知。
- `NavAccC2RCBFAExploratoryV1` 的约束遥测/spec/reshape 写死 N=4；现有环境、观测和布局校验固定容量 8，不能仅修改 `dynamic_count` 就运行 N>8。
- CBF/PPO 外层 100 Hz；物理及 PID 500 Hz；外层 RPYT 在五个 2 ms 子步间保持。
- 当前 fail-open 对正常 strict/soft 结果也有逐环境 RPYT 转换及 `.tolist()`，属于潜在吞吐瓶颈。
- 下游 RPYT 仍有 35° 倾角有效性检查和推力饱和。取消 CBF 层输出限幅不会移除这些约束。

这些是当前工作树事实，不是新方案的默认设计。

## 4. Single next-stage objective — 唯一的下一阶段目标

**先实现独立版本的比较框架，而不是立刻替换历史 NavAcc 或宣布优胜者。**

第一交付阶段包括：纯 Torch 动作/行构造/求解/双项奖励接口、确定性测试、离线 CPU/CUDA 快照比较，以及新 task/transform 的有界 Isaac 接入检查。先以 N<=8 集成现有观测尺寸，求解内核从第一天支持任意配置的 N 和 inactive mask。

N>8 的仿真场景/观测扩展与多 seed 正式训练属于后续阶段，详见第 9 节。不能用合成行 benchmark 冒充 N>8 的闭环训练验证。未来执行者应完成当前获授权阶段，明确报告尚未执行的后续实验；不得因最终 solver 未选择而停止搭建比较框架。

## 5. Files/code to inspect first — 首先检查的文件与接口

路径均相对 `OmniDrones/`，下表符号比静态行号更可靠。

| 层 | 当前文件/符号 | 需要处理的边界 |
|---|---|---|
| 动作映射 | `omni_drones/controllers/navacc_sim_pilot.py::NavAccPolicyAdapter.nominal_acceleration` | 保留 latent 映射，新增版本化三维球投影 |
| CBF 行/严格求解 | `omni_drones/utils/navacc_acceleration_c3bf_diagnostic.py::solve_acceleration_c3bf`、`_analytic_xy_candidates` | 解耦行构造、圆盘限制、候选求解、证书 |
| 定义域 | `omni_drones/utils/navacc_acceleration_c3bf_domain.py` | 活动行原因码、低速/近 rho/估计失效，不静默跳过 |
| soft 回退 | `omni_drones/utils/navacc_c3bf_soft_all_v1.py` | 历史对照保留；新主路径不隐式调用 |
| transform | `omni_drones/utils/torchrl/navacc.py::NavAccC3BFActionTransform`、build 函数 | 新版本分派、同一步快照、批量转换、失败状态 |
| 执行门 | `omni_drones/utils/navacc_fail_open.py` | 现有物理限幅不能沿用到新主路径 |
| 转换器 | `omni_drones/controllers/acceleration_to_rpyt.py::AccelerationToRPYT` | 倾角/推力诊断，不偷偷截断成安全动作 |
| 奖励 | `omni_drones/utils/navacc_c2_rcbf_A_reward.py` | 新增独立双项版本，保留 A v1 |
| 环境奖励调用 | `omni_drones/envs/single/nav_acc_c2_rcbf_A_exploratory_v1.py` | N=4 硬编码、info 到 reward 的时序、return 更新 |
| 场景与观测 | `nav_acc_c1_sim_pilot.py`、`nav_acc_c2_capture_reward_v1.py`、`nav_acc_c1_logic.py`、`nav_acc_c2_logic.py` | 场景/运动/碰撞/布局容量一致，不只改 tensor |
| PPO | `omni_drones/learning/ppo/ppo.py` | `agents.z_policy` 和 sample_log_prob 保持一致 |
| 入口/审计 | `scripts/train.py` 及 NavAcc eval/experiment 脚本 | transform 注册、冻结校验、动作重算、清单字符串、train/eval 对称 |

建议新增纯模块：`navacc_c3bf_rows_v2.py`、`navacc_c3bf_solvers_v2.py`、`navacc_cbf_dual_reward_v2.py`；新 transform/task 命名应包含 `experiment_v2`。这些是拟新增文件，不是声称已经存在。

## 6. Allowed scope — 允许的修改范围

- 新增版本化纯 Torch 模块、配置、测试和 benchmark/eval 工具。
- 为新任务增加最小注册、分派及遥测；旧配置必须保持旧行为。
- 在新路径中批量化投影、候选校验和转换诊断；必要时提取无行为变化的共享函数，必须跑旧用例回归。
- 新实验下移除 CBF 输出圆盘/Z 限制及相应旧物理门，不全局删除历史功能。
- 新配置显式使用类似 `solver_output_bound: none` 的语义，转换器/执行器包络另列；不向旧的“必须为正有限值”物理限制字段填巨大数或 infinity 来假装取消限制。
- 第一阶段新增统一 N<=8 实验 task；后续新增容量可配置场景和观测版本。
- 所有生成产物写 `/home/lz/lzspace/experiment_artifacts/<独立实验名>/`。

## 7. Explicit non-goals — 本阶段不做的事

- 不预选 top-1、soft-min 或全约束投影为最终方案，不依据未经测量的加速倍数作结论。
- 不修改 `nav_vel.py` 的既有方法，不把 NavVel 速度过滤代码当作 NavAcc 加速度过滤。
- 不改变 PPO 概率比定义、飞控增益、旋翼模型、物理步长来掩盖不可执行命令。
- 不自动放宽倾角或推力限制；不声称取消命令限幅等于实际加速度无界。
- 不把旧 C2 检查点当作新方法同分布、同奖励、同动作语义的精确续训。
- 不顺手解决新的零速 barrier 数学问题。先保留并报告定义域状态；另立设计阶段修复。
- 本文不是批准立即启动全部多 seed 长训练的命令；先交付有界实现和检查结果。

## 8. Frozen design decisions — 固定契约与实验参数

### 8.1 符号和动作数据流

本文用 `u` 表示加速度命令，避免与论文约束法向 `a_k` 混淆。

```text
z_policy -> u_raw = scale * tanh(z_policy)
         -> u_nom = Proj_{||u||_2<=2}(u_raw)
         -> solver(rows, u_nom) -> u_filtered
         -> converter/execution gate -> RPYT
```

当 `||u_raw||<=2` 时 `u_nom=u_raw`，否则 `u_nom=2*u_raw/||u_raw||`。零向量原样保留；非有限动作标记失败，不能用 nan_to_num 静默变成正常样本。

- `u_nom` 为三维球形限幅；绝不是逐轴 clamp 或仅 XY 圆盘。
- 新方法不限制 `||u_filtered||` 或 `||u_filtered-u_nom||`；不在后处理偷偷恢复该限制。
- 仅有水平圆柱 C3BF 时 `u_filtered,z=u_nom,z`，修改量按三维范数记录，数值等于 XY 范数。
- PPO 存储原始 `z_policy`，重算概率也用它；球形投影和 CBF 都属于环境动作映射，不改写 latent。
- 维持 `u_raw/u_nom/u_filtered/u_commanded` 分开记录；`u_commanded` 也不是测得的实际机体加速度。

### 8.2 C3BF 行与定义域

采用现有符号：

```text
p_i = p_obs_i - p_uav
w_i = v_obs_i - v_uav
rho_i = sqrt(||p_i||² - R_i²), s_i = ||w_i||
h_i = p_i·w_i + rho_i*s_i
q_i = p_i + rho_i*w_i/s_i
b_i = (s_i/rho_i + gamma)*h_i + q_i·a_obs_hat_i
      - ||q_i||*(epsilon_obs_i + epsilon_track)
constraint: q_i·u_xy <= b_i
margin_i(u) = b_i - q_i·u_xy
```

所有方法共享同一步的 `p,w,h,q,b`、固定单位和估计。不能为了让某方法更容易通过而改 gamma、R、误差界或低速阈值。第一轮沿用 C2 soft-all 实际阈值 `s>1e-4`、`rho²>1e-4`、`||q||>0.01`、age<=0.25 s；当前 gamma=1、a_obs_hat=0、epsilon 两项=0，必须标为 nominal simulation、非已验证鲁棒保证。

活动行无效与 inactive 完全不同：inactive 不参与，活动行无效使该样本完整行集合未知。禁止用任意分母加 epsilon、删除问题障碍物或归零 b 来伪造有效行。对有限输入的实现保护必须伴随相应 invalid 状态。

`N=0`/全 inactive 时约束为空、过滤为恒等、正常奖励两项为零；不能对空维调用无定义的 min/max/logsumexp。

### 8.3 双项奖励与公平对照

论文方向为 `a_paper^T v >= b_paper`；项目对应 `a_paper=-q_i`、`b_paper=-b_i`。单行负余量为 `min(b_i-q_i·u_nom_xy,0)`，不是 `min(q_i·u_nom_xy-b_i,0)`。

主对照采用明确命名的多障碍扩展 `common_all_rows_worst_margin_v2`：

```text
rv_common = min(min_i margin_i(u_nom), 0)       # 仅在全部活动行有效时定义
delta_u   = u_filtered - u_nom
rd        = expm1(-||delta_u||²/sigma_a²)
r_cbf     = weight_violation * rv_common + weight_correction * rd
```

- 这是论文两项结构的多障碍扩展，不声称论文已经规定了该聚合。
- 所有 solver 主比较使用同一 common 第一项、同一权重、同一 sigma_a；第二项必须来自该 solver 本次实际提出并可执行的过滤结果，不能借用另一 solver 的修改量。
- 单约束/soft-min 的原生负余量另记 `rv_native`。原生奖励训练属于独立消融轴，不与主比较混合；soft-min 的 H/Q/B 约束与逐行条件不同，不能直接比较不同奖励 return 判定更优。
- `rd` 在 [-1,0]，第一项没有固定下界，整个 r_cbf 也没有 -1 下界。默认不对 raw margin 除以 ||q|| 或截断到 [0,1]；如做归一化，必须另建 reward 版本。
- `sigma_a` 单位 m/s²；`weight_violation` 负责 raw margin 单位/尺度。初始候选可用 sigma_a∈{0.5,1,2} m/s²、两个权重均0.1，**仅是待校准建议，不是用户已经冻结的最优超参**。先在训练集固定快照上校准分布并锁定，再跨 solver 比较；不得按测试集调参。
- 保留既有 task reward、height/capture 系数、终止奖励；新 r_cbf 只加一次，替换新 task 的旧 A 项，避免叠加两份 CBF reward。
- 失败时无过滤目标，不存在有效 delta reward。有限占位零必须配 `reward_defined=false`，并计入独立 failure penalty/终止规则，不能得到“安全零惩罚”。

具体失败奖励契约：任何活动行无效或 u_nom 非有限时，完整 rv_common 未定义，不能在剩余有效行子集上构造训练奖励。solver 有有效结果但转换失败时，数学 rv/delta 可保留为离线诊断，执行用双项奖励仍标未定义。只有下节 `execution_eligible=true` 才令 `reward_defined=true` 并添加上述双项；否则 `r_cbf_added=0` 是不适用占位，另添加一次失败过渡惩罚并置 `failure_penalty_applied=true`。汇总时未定义样本不得计入 valid-zero 比例。N=0/全inactive且名义动作与转换有效时是正常恒等过滤，reward_defined=true、两项为0。

### 8.4 失败与执行契约

分开输出 `domain_valid`、`method_constraint_pass`、`all_rows_pass`、`finite_output`、`converter_valid`、`thrust_saturated`、`execution_mode`，不能只返回一个 `safe=true`。

执行资格显式为：

```text
execution_eligible = domain_valid & finite(u_nom) & output_defined
                     & method_constraint_pass & finite_output
                     & converter_valid & ~thrust_saturated
reward_defined = execution_eligible
```

其中 A1 的 method_constraint_pass 检查选中半平面（全部名义满足时为true）；A2 检查其组合半平面；A3 检查全部原始行。`all_rows_pass` 不额外加入 A1/A2 的执行门，避免暗中把方法改成全约束过滤；任一活动行无效必令domain_valid=false，完整all_rows_pass=false且完整残差记未知，不能把子集通过记成“全部通过”。

新对照默认不继承旧 soft-all/fail-open。建议的有界实验执行协议：有方法有效且转换可执行的结果就执行；top-1 的其他行残差、soft-min 的逐行残差只作完整记录，不能额外调用全约束修复而改变算法。方法本身无解/未验证、定义域失败、转换拒绝或推力饱和则统一记录原因，使用既有 episode 内 held RPYT 完成一次终止过渡并只 reset 对应环境。保持动作不是安全证明。各 arm 必须同一协议。

失败过渡的 CBF 专用 penalty 可先设 -20（单独配置、标注建议值），不得再重复叠加同义 cbf_failure penalty；collision/crash 等已有原因的优先级按新任务显式固定。后续若研究 fail-open/soft rescue，作为独立因素、独立日志比较，不混入主求解器对照。

held-RPYT 的终止过渡和auto-reset不能重复添加失败惩罚；不存在一个连续episode每个物理子步都加一次-20的行为。NaN诊断不能进入训练reward tensor，failure penalty必须为有限值。

对有限候选搜索失败，返回 `NO_VERIFIED_CANDIDATE`；只有独立证书复核成功才叫 `INFEASIBLE_PROVEN`。旧“半平面+2m/s²圆盘”不可行证书不能复用于已取消圆盘的问题。

## 9. Required implementation — 实施顺序与实验方案

### 阶段 A：纯接口、算法候选与离线证据

先拆开 row builder 与 solver，采用例如以下契约（可适配 TensorDict 外壳，字段语义不变）：

```text
inputs:
  u_nom[E,3], p/w/a_obs_hat[E,N,2]
  active/estimate_valid[E,N], age[E,N], config
rows:
  h[E,N], q[E,N,2], b[E,N], row_valid[E,N], reason[E,N]
result:
  u_filtered[E,3], correction[E,3], objective[E]
  output_defined[E], method_constraint_pass[E], all_rows_pass[E]
  execution_eligible[E], reward_defined[E]（由执行层补齐）
  status[E], selected_id[E]（无选中=-1）
  raw_residual_max[E], normalized_residual_max[E]
  candidate_count[E], projection_rounds[E]
  native_margin_nominal[E], aggregate_H/Q/B（仅适用方法）
```

无效结果可存 NaN 于离线数据，但送入策略观测/奖励/执行前必须通过有效性门；不能让无效分母经 `where` 未选分支仍污染梯度或输出。纯奖励及 rollout 过滤默认 no_grad；标准 PPO 不需要对投影反传。

必须实现/比较的三个新方法：

**A1 `top1_violation_closed_form`**

- `k=argmax_i [q_i·u_nom_xy-b_i]_+/||q_i||`；并列用稳定实体 ID 决定，不用瞬时 slot 顺序。
- `u_filtered_xy=u_nom_xy-[q_k·u_nom_xy-b_k]_+ q_k/||q_k||²`。
- 全部行名义满足时恒等，无需选择；投影一次后不增加其他修正。
- 全量复核只作指标，不作为隐式第二轮。不能宣称覆盖全部障碍。

**A2 `softmin_closed_form`**

- 设固定 beta>0，`H=-logsumexp(-beta*h_i)/beta`，只计活动且已确认有效的行。不要把 sum 改 mean。
- `lambda_i=softmax(-beta*h_i)`、`Q=sum lambda_i*q_i`、`B=sum lambda_i*(b_i-gamma*h_i)+gamma*H`。
- `Q·u_xy<=B`，对该半平面投影一次。不能简单使用 `B=sum lambda_i*b_i`。
- gamma、beta 为本次对照固定参数，不临时随 N 调整；beta 单位为 h 的倒数。beta sweep 需单独记录。
- `H<=min h_i`，满足 H>=0 才能用其保守集合论证；记录 H<0 初始状态。H>=0 不自动保证组合 CBF 可行。
- Q≈0 且 B<0 是方法退化/失败，不能除以 epsilon 制造巨大伪解；Q=0 且 B>=0 恒等。小非零 Q 的数值处理需明确阈值和误差检验。
- N 增加带来 `log(N)/beta` 级集合偏移；重复行、传感器拆分与 mask 数量均影响它。报告这些敏感性，不把 soft-min 看成原多约束 QP 的等价求解器。

**A3 `all_halfplanes_candidates`**

- 无输出圆盘。候选：名义 XY 点；每条直线正交投影；每两条非平行直线交点。
- 无padding且全部N行活动有效时 `K=1+N+N*(N-1)/2`，N=4 时11，N=8 时37。容量N含padding时，每环境M条活动有效行只有 `1+M+M*(M-1)/2` 个候选槽上限；平行等情形再减少可用数。允许按容量N批量生成并mask无效候选，但日志区分allocated/generated/usable候选数，inactive不能参与校验或argmin。
- 候选在理想非空交集下覆盖二维欧氏投影；近平行、浮点容差、cast 回执行 dtype 必须重新验收。
- 朴素校验 O(E*N³)，不能为 N=64 构造无预算的巨大 `[E,K,N]` 临时量；实现固定候选分块/流式最小值归约，记录块大小和峰值内存。
- 障碍物遍历/候选生成使用张量索引，缓存 pair 索引。不要逐环境 Python 循环调用小线性求解。

补充对照（不替代三主方法）：

- `legacy_exact_profile`：完整旧 C2 配置作为历史参考，明确其动作限幅、奖励和失败策略均不同，不能归因成纯 solver 差异。
- `greedy_fixed_rounds_no_output_bound`：如需比较，固定 R∈{1,2,4,10}，逐轮最严重行投影，无圆盘。严格标成有限轮近似，无完整可行性/最优性保证；不能以大批量中最难环境驱动所有环境 host while。
- `hardmin_h_closed_form`：论文结构参考，可后加；选择 argmin h 与最大违反选择不同；碰撞锥 h 也不是论文距离 h。并列分支要记录，不能宣称任取一个便有严格多障碍保证。

取消圆盘后，旧 soft-all 的单个 hinge 区域可解 2x2 线性系统，不再需要圆盘二分，但总区域数仍为 2**N。该方法最多作为小 N 的独立软约束救援消融，不作为可扩展主算法。

离线输入必须有两类：任意合法半平面几何（覆盖空集/退化）和真实/合成 `p,w` 经同一 row builder 得到的 C3BF 行；不能只测试随机 q,b 就推断闭环效果。记录输入快照 hash、active ID 和所有状态。

### 阶段 B：新版本训练/评估接入与 N 扩展

- 新建 task/transform 配置，不修改冻结 C1/C2 的断言来允许新行为。优先使用明确的新类和共享无状态 helper；若复用父类，检查所有父类构造、admission 和 reward 路径。
- 新的 constraint info/spec/reshape 从配置容量构造，不能把 N=4 换成另一个常量。
- 先在 N∈{1,2,4,8} 的新实验场景验证。C2 固定几何只作其中一个命名场景；不要假装改一个 YAML 数值就能让既有 C2 类支持其他 N。
- N>8 必须同步扩展实体生成、障碍运动、tracker、reset 布局、碰撞和最近净空计算。区分 `N_world`、`N_cbf`、`K_observation`；主实验要求 `N_cbf=N_world_active`，不能以策略只观察 K 个为理由截断过滤输入。
- 第一种完整观测扩展可用新版本 `16+8*K_observation` 展平输入，并令 K 覆盖该组实验容量；改变宽度需新 policy/checkpoint schema，不能声称旧80维检查点精确兼容。若改为固定 K 局部观测或集合编码，应成为另一个观测实验轴，不与 solver sweep 同时改变。
- 每个 N 的所有 solver 必须使用相同观测、场景分布和网络；跨 N 的总吞吐包含观测/网络成本，另外报告固定输入的纯求解耗时。
- `u_filtered` 先批量转换，按每环境 valid mask 执行；避免 `.tolist()`、逐环境 try/except 和逐环境 converter。保留旧转换器参数，不取消倾角/推力真实边界。
- 第一阶段若大量超出转换包络，不加回2m/s²限幅、不扩大飞控包络、不继续无限训练：输出命令幅值/转换失败分布，进入后续“执行可实现性”设计决策。
- 复位 held 命令必须 episode 内隔离。初始 admission 不可继续暗中调用带2m/s²圆盘的旧 strict solver。

初始分布公平性：使用同一固定布局/速度 corpus，不分别按各 solver 接受能力重新采样。分别报告：全部方法共同适用的域；原始逐行可行但 H<0 的域；失效/不可行压力域。soft-min 额外的初始 H>=0 条件作为适用率呈现，不把不适用局静默删除。

### 阶段 C：求解器 benchmark（先测，后训练筛选）

建议矩阵：E∈{256,1024,4096}；N∈{0,1,2,4,8,16,32,64}。N=64 为压力点，设备不足时标记 OOM/预算超限，不遗漏不报。

每个点覆盖：全部名义可行、单行主导、两行共同主导、多行冲突、近乎平行、相反法向、低速/近 rho、不同 active padding、不同静动态比例，以及真实 C2 回放。障碍排列置换、批量混入困难样本必须独立检查。

增加固定策略的反事实回放：同一决策状态、同一 u_nom 分别送入各 solver 与转换器，只比较输出而不推进各自轨迹。它与在线闭环实验分开，避免把状态访问分布不同误当成求解器算术差异。

- 分别计时：动作映射、row builder、solver、reward、converter、完整 env.step、PPO update。
- 使用 CUDA Events 做正确异步计时，外层墙钟捕获 Python/同步成本；预热与正式采样分开。建议预热100次、测量500次，过慢方法可设统一墙钟预算并报告实际次数。
- 报 mean/median/p95、每批延迟、聚合 env-step/s、临时峰值显存、失败比例。不要把每批延迟除以 E 当单环境实时控制延迟。
- 同一 GPU/ dtype/软件栈；无并发训练干扰；记录 eager/compile 设置与编译开销，所有方法公平使用或分表列出。
- GPU 热路径避免 `.item()`、`bool(tensor)`、`.cpu()`、`.numpy()`、`.tolist()` 和显式同步；计时边界的同步除外。容许固定候选 chunk 的 Python 调度，但报告启动开销。
- 验证 float32 运行与 float64 离线 oracle 的误差、状态一致性、近退化行为。不要为跑得快而只放松某 arm 的验收容差。

### 阶段 D：有界闭环与正式训练

先新 task 小规模 smoke（例如64环境、256外层步，再1次32步 rollout/PPO update）；所有 solver 相同场景/seed，验证 action/log_prob、奖励和 reset 时序。规模及运行命令在执行前写入 manifest，不能在报告中事后修改成功标准。

通过后再固定正式协议。建议至少3个独立训练 seed；候选 seed=93001/93002/93003，验证集与最终测试集使用不同布局 ID/seed。正式帧数和资源预算在短试验后冻结；本计划不编造当前未运行的训练命令或结果。

- 按 N 分层，不只训练 C2；N>8 正式实验必须在阶段B扩展通过后开展。
- 区分固定场地增大 N（密度也上升）与保持近似障碍密度、相应扩大场地的实验；场地/目标距离变化只在同一层所有 solver 间共享。不能把增大 N 导致的任务难度变化全部归因给 solver 规模开销。
- 单 solver 比较固定同一 dual reward；再对候选方法做 `{无CBF, filter-only, reward-only, dual}` 消融。reward-only 可计算反事实投影目标但执行 u_nom，反事实计算必须计入成本并标识失败。
- `无CBF` 也保留相同名义球限幅；不把旧盒限幅 baseline 当新消融对照。
- 每组同时报告等训练帧数结果和达到目标的墙钟成本；同一评估 corpus、确定性/随机策略设置、episode规则和故障处理。
- 评估 filter ON；如研究论文的内化能力，再评估同一checkpoint filter OFF。不得由训练ON无碰撞推断OFF安全。
- 以到达、碰撞、crash/OOB、失败模式、修改量、命令可执行率、训练稳定性和吞吐构成 Pareto 比较。不仅按 return 或纯 kernel 速度排名；允许不同 N 下有不同优选方法，不强行选唯一赢家。

## 10. Tests — 必须覆盖的测试

纯测试优先，新增脚本应可在不导入 Isaac 的条件下运行。

1. 三维球限幅：零值、边界、对角线、大值、非有限值；例如 (2,2,2) 限幅到 (2/sqrt(3),2/sqrt(3),2/sqrt(3))；latent 原样保留。
2. 无输出限幅：构造需要 `u_x>=3` 的单行，结果应允许 x=3，不得被旧圆盘或 fail-open 物理门改回2。
3. 单行符号：约束 `u_x<=0`、u_nom=(1,0,0)，margin=-1、投影=(0,0,0)、delta范数=1；安全侧奖励0。
4. 两行例：`u_x<=0,u_y<=0`、u_nom=(1,1,0)，全约束解=(0,0,0)、delta²=2；top1 留另一行违反，测试必须显式看到差异。
5. 全约束候选：内部、单边、角点、平行条带、重复行、矛盾行、退化q、近平行、大命令，输出cast后全量复核；与独立float64离线参考比对，参考优化器只允许离线测试使用。
6. soft-min：手算H/Q/B、不能漏掉gamma修正项、与有限差分的方向导数一致；sum与mean反例；Q抵消、H<0、N=0、inactive无穷/NaN屏蔽、beta变化、重复行敏感性。
7. reward：两项均存在、sigma单位正确、修改量用u_nom而非z/u_raw、原始符号正确、expm1在小修正下稳定、失败sentinel不会被计成valid-zero。
8. 批量隔离：同一环境单独执行/混入困难环境结果一致；active mask不同；ID tie-break；行正比例缩放不改变几何投影，但raw-margin reward尺度会变，不能错误要求其尺度不变。
9. 时序：reward使用决策时刻同一快照的q,b,u_nom,u_filtered，而不是下一状态重算的行；每100Hz外层步只加一次，五子步不重复；终止/auto-reset不串episode。
10. PPO：更新前用记录z重算log_prob比率为1（数值容差内），CBF修正或球限幅不改写采样动作；验证info/next-info对齐。
11. 执行：超过2但在转换包络内的命令正常通过；超过倾角/推力能力的命令显式失败/饱和，不能伪装成已执行安全动作。
12. N扩展：N=0,1,4,8,16,32的纯接口、内存预算、形状和mask；N>8场景另做实体数/运动/碰撞/观测一致性测试。

已有回归入口可从以下命令起步（工作目录 `OmniDrones`，使用项目已安装Python环境）：

```bash
python -m pytest -q scripts/test_navacc_c3bf_analytic_solver.py scripts/test_navacc_c2_rcbf_A_reward.py
python -m pytest -q scripts/test_navacc_fail_open_contract.py scripts/test_navacc_sim_pilot_contract.py
```

执行前核对依赖和脚本测试形式；缺失 Isaac/CUDA 时报告未验证范围，不更换环境或安装大型依赖。新测试文件与 benchmark CLI 必须由实现者提供实际可运行命令，本文拟议文件名不能充当已完成证据。

## 11. Acceptance gates — 验收门

G1 契约：名义3D球限幅、CBF不后限幅、双项reward、z概率一致、时间对齐，所有确定性用例通过。

G2 数学/数值：A3在独立参考可行案例中找到通过原始行容差的最近候选；A1/A2只声明其方法条件，完整残差如实记录。初始沿用raw row绝对容差1e-6；与oracle的动作比较另定dtype/尺度相关阈值（建议普通条件下float32 atol/rtol=1e-5），近退化单独报告，不能以调宽容差消除失败。

G3 性能：至少给出 E=1024、N=4/8/16/32 的三方法计时与峰值内存；无法完成的点明确原因。证明新正常热路径没有逐环境host循环，没有隐式soft-all或圆盘二分。

G4 接入：小规模Isaac无跨环境/episode污染；动作可执行性和失败协议可观察；旧任务回归通过。缺硬件时停在纯模块交付并标明G4未验证。

G5 选型：只有跨N、跨seed、统一协议的闭环与训练证据才能推荐部署/训练默认。纯kernel最快、单个C2 seed成功、旧报告数据均不能单独通过本门。

G1—G4通过表示“实验框架可用于下一阶段”，不等于证明闭环安全。当前误差界和采样执行假设尚未闭合。

## 12. Required logging/evidence — 日志与证据

每次输出 manifest：两个Git SHA、工作树diff/hash、完整resolved config、任务/solver/reward/observation版本、E/N/static/dynamic、dtype、GPU与软件版本、seed和布局ID、checkpoint来源、训练帧数、墙钟预算、命令与退出码。

逐步统计至少包括：nominal限幅比例；u_nom/u_filtered范数及delta分位数；rv_common/rv_native/rd/总r_cbf；domain reason；method/all-row通过率；最终raw/normalized残差；Q范数与H初始适用率；候选数/轮数；solver及转换失败；倾角/推力饱和；hold/fallback比例；碰撞、最小净空、到达/crash/OOB/timeout。

保存少量固定ID的完整决策快照用于复核，正常训练避免每步把全E×N张量传CPU。统计归约在GPU完成，低频flush；benchmark单独测量关闭诊断和开启诊断的开销。

失败分母必须完整：不得删除不可行、H<0、定义域失败、超转换包络episode后只报告剩余成功率。共同适用子集与原始分布分别报告样本数量和覆盖率。

## 13. Regression requirements — 影响面与回归要求

**Affected：** 新动作映射、新solver/reward、新task注册和spec、训练/eval分派与telemetry、admission、N扩展场景与checkpoint元数据。

**Must remain unchanged：** 旧版本NavAcc/NavVel默认行为；原始z概率接口；100/500Hz时序；坐标单位/正负方向；历史奖励/失败协议；飞控和旋翼模型；历史文件与实验产物。

**Regression tests required：** 旧strict/soft-all/fail-open/奖励A单测，新旧transform分派隔离，旧checkpoint按旧配置可加载；新配置使用新checkpoint lineage。新旧即使同80维也不是相同动作/奖励语义，旧权重最多作显式warm-start对照，不宣称精确resume。

train.py现有冻结任务白名单、manifest动作链文本、由z重算a_nom的审计、ON/OFF动作路径都须逐一检查。不能只更新实际transform却留下旧审计公式；不建议继续在train.py堆大量按任务名复制分支，优先有限的版本化工厂，但不要无关重构。

## 14. Git/worktree discipline — Git 与恢复

本次用户明确授权的保存已完成；后续实现agent仍须先检查两仓库状态，保护其后新改动。除非后续用户另行授权，不自行commit/push/reset/clean或移动外层gitlink。不要因基线已提交而认定工作树以后永远干净。

查看基线：

```bash
git -C /home/lz/lzspace/drones show --stat navacc-pre-cbf-modify-20260930T030142Z
git -C /home/lz/lzspace/drones/OmniDrones show --stat navacc-pre-cbf-modify-20260930T030142Z
```

安全恢复检查优先在新目录创建独立工作树，不覆盖当前开发目录。例如需要代码基线时，选择不存在的目录执行：

```bash
git -C /home/lz/lzspace/drones/OmniDrones worktree add --detach /home/lz/lzspace/experiment_artifacts/navacc_pre_cbf_code_review_20260930 764da248e1e167f9fe3042d65148bad654e221a0
```

外层文档可另建外层worktree到2ab0cf3；外层仓库只保存子模块commit指针，不自动复制独立子模块代码/未跟踪实验数据。正式原位回退前先保存后续工作，不能直接照抄 `reset --hard` 覆盖。

## 15. Deliverables — 交付物

1. 新版本可切换solver、名义球投影、行构造与双项reward纯模块。
2. 独立task/config与批量执行接入；旧路径不变；N扩展边界清楚。
3. 确定性测试及CPU/CUDA参考验证结果。
4. 冻结快照corpus、benchmark脚本与跨E/N表格，包括失败和内存。
5. 小规模Isaac/PPO smoke证据；后续多seed训练配置及尚未执行清单。
6. 变更文件、实际命令、Git状态、残余问题和下一实验阶段建议。最终方法未选定也是有效实验结论，不能捏造赢家。

## 16. Stop conditions — 需要报告并收敛范围的情况

- 未能保证raw z与log_prob一致，或reward使用了错误时间快照：暂停相关训练，先修契约。
- 改动需要放宽飞控倾角/推力、换barrier修复零速，或改变观测架构：完成已独立可做的内核/离线证据，将该项列为下一设计决策；不要静默扩大范围。
- N>8场景/观测未扩展：仍完成任意N纯solver实验，但明确禁止声称已完成大N闭环实验。
- 候选数/临时张量超预算：使用分块或报告预算超限；禁止偷偷丢弃障碍物。
- 缺设备/环境或完整训练预算未冻结：交付已验证内容及可运行入口，不把未启动/未结束的实验写成成功。

## 17. Required final report format — 实现agent最终报告

按以下顺序报告：

1. 完成的阶段与未完成的阶段。
2. 实际动作、约束、奖励、失败执行链及与旧版本的差异。
3. 修改文件与版本化配置；是否改变观测/checkpoint契约。
4. 测试命令、退出码、基准硬件、E/N及性能/正确性结果。
5. 全部失败模式与覆盖率，尤其soft-min不适用、top1漏约束、全约束未找到可行候选、转换拒绝。
6. 基于证据的下一步；不能只说“解析所以更快”或“奖励下降所以更安全”。
7. 两仓库Git状态、未触碰的用户改动、产物路径和回退基线。

本计划的核心决策是固定比较契约和实验方法，而不是提前固定最终求解器。
