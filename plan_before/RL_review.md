# RL 训练判读复习手册（RL_review）

> 创建时间：2026-09-04
> 内容来源：一次关于「如何通过指标判断 RL 训练好坏 / PPO 优化指标含义 / PPO loss 本质」的问答对话总结。
> 配套实战背景：M1 NavVel 随机目标导航训练的十几轮失败与最终突破（见附录）。
> 用途：快速复习用，不长篇大论，重点是可复用的**判读框架**与**公式**。

---

## 0. 全篇一句话

**RL 日志有两类指标，必须分开看：**

| 类 | 回答的问题 | 例子 |
|---|---|---|
| 环境/任务指标 | 策略做得好不好 | `return / pos_error / arrival / episode_len / success_rate` |
| 优化过程指标 | 更新健不健康、在不在学 | `policy_loss / value_loss / entropy / actor_grad_norm / critic_grad_norm` |

> ⚠️ **优化指标健康 ≠ 任务在学**。梯度下降可以在一个"坏任务"上完美自洽地优化
> （案例：200M 帧"全程下坠"的 run，loss/熵曲线多半看起来正常，因为它成功学会了"下坠→终止"这条退化路线）。
> 判问题要靠任务侧指标或直接看视频，判"该不该续命"则要靠优化指标。

---

## 1. 判断一次训练好坏：三层判读框架

按顺序放行，红灯在哪层就在哪层修，**加帧数永远修不好机制层问题**。

### 🚦 第 0 层：机制健康（学没学会"活着/会飞"）
> 红灯时任何帧数都救不了，先修环境/终止/重置机制。

| 指标 | 健康 | 红灯（立即止损） |
|---|---|---|
| `episode_len` 均值 | 接近 max_episode_length | ≪ max → 提前死亡主导（如 ~82 vs 600） |
| `vel_norm` | 物理合理（Crazyflie 巡航 ~1-2 m/s） | ~3.5 且 ep_len 短 = 自由落体/坠地 |
| `return` | 正值、量级稳定 | 负很大 → 惩罚压过一切正信号 |

> 教训：vel_norm≈3.5 其实是**自由落体速度**不是"飞太快"。**play.py 看 5 分钟视频能发现，别等 2 亿帧。**

### 🚦 第 1 层：任务进展（学没学会"逼近目标"）
> 第 0 层绿灯后才看。**看趋势曲线不是单个终点**（eval 单点噪声大，如 pos_error std≈1.2）。

| 指标 | 信号 |
|---|---|
| `pos_error`（用 eval 曲线） | 持续下探离开平台期 |
| `arrival` / `success_rate` | 首次 >0 且爬升（徘徊在 ~0.002 只算"偶发碰到"） |

### 🚦 第 2 层：收敛/达标（是否值得继续）
| 指标 | 含义 |
|---|---|
| `entropy` | 降没问题；**降到很低而任务没改善 = 策略坍缩到次优解，配置到顶** |
| `actor_grad_norm` | 稳定、有界（~2-3 量级），不常顶截断值 |
| 确定性 eval（eval_ckpt） | 最终只认这个（到达率 ≥80% 等验收） |

### 三个止损规则
1. **机制红灯 = 立即停**。ep_len 不涨 / vel_norm 是自由落体 → 改终止/存活/重置机制（如 soft_respawn），加帧零收益。
2. **任务平台 + 熵坍缩 = 配置到顶，别续命**。横盘超过"每 env 数万帧"且熵掉到很低 → 当前奖励最优点已是次优行为，需要换干预（课程/势场/奖励重构），不是加帧。
3. **首次信号 → 只给 2-3 倍预算确认斜率**，别一上来甩 50M。

### 指标会"饱和失效"
`episode_len` 顶满、`vel_norm` 回物理合理区后就不再是诊断信号 → **每次改机制后要问"哪个指标还活着能反映好坏"**。

---

## 2. PPO 优化指标逐个含义（对照仓库 `learning/ppo/ppo.py`）

核心更新：`loss = policy_loss + entropy_loss + value_loss` 一次 backward，actor/critic 梯度各自 clip 到 5。
（GAE γ=0.99, λ=0.95；adv 做 (adv−mean)/std 归一化；return 走 value_norm 归一化。）

### policy_loss（策略替代目标）
$$-E\big[\min(rA,\ \mathrm{clip}(r,1\pm\epsilon)A)\big]\cdot d,\qquad r=e^{\log\pi_{new}-\log\pi_{old}},\ \epsilon=0.1$$

- 意义：这一批数据下新策略相对旧策略"踩中高优势动作"的程度。**是替代目标，不是真实损失**。
- 健康形态：窄带内**上下震荡**，随收敛趋于 0 正常。
- 只在剧变时有诊断价值（突然大跳水 + grad 爆 = 更新步太长不稳定）。

### value_loss（价值回归损失）
$$\max\big(\mathrm{Huber}(R^\lambda_t, V),\ \mathrm{Huber}(R^\lambda_t, V_{\rm clip})\big)$$
- 意义：critic 拟合 GAE 的 λ-return 的误差，衡量**价值函数学没学会回报结构**。
- 健康：下降后入低平台。**value_loss 低 + 任务不动 = 回报可平凡预测（无方向性梯度）→ 重设计奖励**。

### entropy（策略熵）
- 意义：动作分布熵。初值大（~5.7）≈ 均匀探索；小（~1-2）= 基本确定化。
- 健康：随学习**逐渐**下降，但**不该在任务进步前崩到近 0**。
- 两个危险病征：
  1. **熵快速坍缩 + 任务横盘** = 过早收敛到次优/退化策略（B-50M：熵→1.23、pos_error 钉 3.4）。
  2. **熵长期不降 + 任务不动** = 更新没在吃奖励信号（lr/奖励尺度问题）。

### actor_grad_norm / critic_grad_norm
- 意义：各自参数梯度 L2 范数（代码返回的是 **clip 前**范数，偶 >5 是截断标志）。
- actor 与 critic 量级天然不同，**别互比绝对值**，各自看趋势。
- 病征：长期顶截断值 = 更新不稳（降 lr/剪 reward 离群）；爆极大 = 常先有 reward/dynamics 数值爆炸；critic_grad≈0 但 value_loss 高 = 价值更新断了。

### 代码算了但常忘看的两个
- `ratio`：新旧策略比，常远离 1 = 单 epoch 策略漂移大。
- `explained_var = 1 − MSE(V,R)/Var(R)`：价值解释回报方差比例。**>0.9 健康；≈0 或负 = critic 没学到回报结构**（强烈建议加进 wandb，判断"奖励有无可学结构"最直接）。

---

## 3. 通用 RL 运动控制：组合症候表 + 排查顺序

**单看任一指标是噪声；有诊断意义的是"联合形态"。**

| 症候 | 推断 | 动作 | 案例 |
|---|---|---|---|
| ✅ 熵缓降 + value_loss 入低平台 + grad 有界 + 任务同步改善 | 健康学习 | 继续 | PIDrate 悬停收敛 |
| ⚠️ 熵快坍缩 + 任务横盘 + 各项 loss 都"正常" | 收敛到次优/退化解 | 改奖励/课程/探索，不加帧 | B-50M |
| ⚠️ value_loss 低 + explained_var 高 + 任务不动 | 回报无方向梯度 | 重设计势场/加进度项 | 平台期各 run |
| 🔴 grad_norm 长期顶截断 / policy_loss 剧变 | 更新不稳定 | 降 lr、剪 reward 离群、查 GAE | — |
| 🔴 任一项 NaN | 数值死亡 | 立即停，查数值源 | 冒烟 NaN 检查 |
| 🔴 value_loss 高且涨 + return 噪声大 | 价值目标不一致（罕见事件主导奖励） | 加 env、拉长 horizon、平滑奖励 | stage0-fix return −110 |

**30 秒排查顺序**：① 查 NaN → ② 查 grad_norm 是否顶 clip → ③ 查"熵曲线 vs 任务曲线"这对 → ④ 查 value_loss / explained_var → ⑤ 最后才看 policy_loss（孤立时最没信息量）。

---

## 4. PPO loss 本质：三个目标辨析（含常见误解纠正）

PPO 单个 loss = **四个力量**（不是三个）：

$$\mathcal{L}=\underbrace{-E[\min(rA,\mathrm{clip}(r)A)]}_{\text{① 策略改进}}+\underbrace{\mathrm{Huber}(R^\lambda,V_{\rm clip})}_{\text{② 价值拟合}}+\underbrace{-\epsilon_c H(\pi)}_{\text{③ 探索正则}}+\underbrace{\epsilon=0.1\ \text{裁剪}}_{\text{④ 信任域}}$$

### 误解纠正表

| 你的理解 | 纠正后 |
|---|---|
| ① policy：看当前策略是否优于平均策略 | **同状态下"该动作 vs 当前策略平均动作"（$A=Q−V$，$V$ 是当前策略期望）**；不是跨策略全局比较。`clip` = 第 4 个隐含目标（信任域，限制每步别改太多），这是 PPO 的核心。 |
| ② value：V 接近 actor 实际 action 的 return | **$V(s)$ 是状态价值（从 $s$ 出发按当前策略的期望回报），不是某次动作的 return**（那是 $Q$/MC，高方差样本）；critic 看不到动作。目标是用 GAE λ-return（bootstrap 降方差），且带值裁剪。 |
| ③ entropy：开始大保探索，随训练逐渐降低 | **熵项 `−εc·H` 是"往上推"的探索正则**，对抗自然坍缩；**熵下降是涌现结果不是目标**，也没有主动 schedule（εc=0.001 常数）。任务没进步就崩 = 坏信号；最优策略本身随机时熵该保持高位。 |

### 关键因果链
**value 准 → advantage 才可信 → policy 才往对的方向走**。value_loss 降不只是"critic 自己学好"，更是给 policy 可信基线（所以 ② 是 ① 的前提）。

---

## 5. 速查命令（本地看 run，秒回）

```bash
cd /home/lz/lzspace/drones/OmniDrones/scripts
# 1) 全程趋势（抽条看形态而非单点）
grep -E "train/stats.(pos_error|arrival|episode_len|vel_norm|return|entropy)" \
    /tmp/<run>.log | awk 'NR%12==1' | head -45
# 2) 终点 summary
python3 -m json.tool wandb/run-<ts>-<run_id>/files/wandb-summary.json
# 3) 看优化过程指标（loss/grad/entropy）
grep -E "policy_loss|value_loss|entropy|actor_grad_norm|critic_grad_norm" \
    /tmp/<run>.log | awk 'NR%16==1' | head -30
# 4) 列出全部 run
ls -t wandb/ | grep run-
```

---

## 附录：案例结局（对话之外的实际进展，供对照）

- 对话中所有失败 run（基线/200M/soft-respawn/Stage0/B-50M/curv0）的**真正根因后来查明**：
  **Crazyflie 的 Lee 控制器姿态环增益是从 hummingbird 拷贝的**（0.7/0.1）。代码里乘了 $I^{-1}$，而 Crazyflie 转动惯量极小（~1.4e-5）→ 得到 ~5e4 rad/s² 的命令，远超电机能给的 ~800 rad/s² → 姿态环饱和失稳 → **纯悬停速度指令下也下坠（vz≈−2.3 m/s）**。
- 修复：姿态增益重标定（`attitude_gain≈[0.0014,...]`、`angular_rate_gain≈[0.00028,...]`），电机 hover 探测 vz→−0.05 m/s。
- 重训（B 风格 50M，run `9eb3e923`）：**eval arrival 0.99、pos_error 0.19-0.24、return ~770 → M1 达标**（到达率≥80%、pos_error<0.3），tag `m1-achieved`。
- **对照本手册的教训**：这十几轮失败全部属于"第 0 层机制红灯"（下坠/提前终止），却因优化指标"看起来正常"而被误判为样本/超参问题，浪费了数百万帧。**低层控制器链路（actuator→attitude→velocity）的物理正确性，是一切 RL 运动控制训练的前提——先用 probe 脚本验证控制链，再谈训练。**
