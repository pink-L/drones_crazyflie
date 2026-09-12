# NavVel Isaac Sim 实飞可视化指南（demo_fly.py）

> 在 **NX 图形会话（GUI）** 里实时观看 RL 策略无人机飞行的脚本使用教程。
> 脚本：`OmniDrones/scripts/demo_fly.py`（headless=false 出窗口）
> 另有一个轻量版 `OmniDrones/scripts/play.py`（一次性飞行，无视角/轨迹控制，见 §8）。
> 日期：2026-09-08。模型为 geo2r 4-arm 确定性 eval 全达标那批（`run-20260908_153058-*`）。

---

## 0. 前置条件

- 已连上 **NX 图形界面**，在 NX 桌面的终端里执行（`export DISPLAY=:1001`）。
- 每次先激活环境：

```bash
source /home/hybrid/miniconda3/etc/profile.d/conda.sh && conda activate lz_env
export DISPLAY=:1001
cd /home/lz/lzspace/drones/OmniDrones/scripts
W=/home/lz/lzspace/drones/OmniDrones/scripts/wandb   # 后面 +checkpoint=$W/... 用它
```

- **GPU 只能同时跑一个 Isaac Sim 实例**：开新演示前先杀掉旧的：
  ```bash
  pkill -f "demo_fly.py" 2>/dev/null; pkill -f "play.py" 2>/dev/null; sleep 1
  ```
- 停止正在播放的演示：**在运行它的终端里 `Ctrl+C`**（脚本会干净关闭 Isaac）。

---

## 1. 快速开始（推荐：俯瞰走廊 + 轨迹拖影 + 正常速）

```bash
pkill -f "demo_fly.py" 2>/dev/null; sleep 1

source /home/hybrid/miniconda3/etc/profile.d/conda.sh && conda activate lz_env
export DISPLAY=:1001
cd /home/lz/lzspace/drones/OmniDrones/scripts
W=/home/lz/lzspace/drones/OmniDrones/scripts/wandb

python -u demo_fly.py task=NavVel algo=ppo headless=false wandb.mode=disabled \
  +eval_points=fixed \
  task.fixed_init=[-2.8,0.0,0.5] task.fixed_target=[2.8,0.0,1.0] \
  task.env.num_envs=1 task.action_transform=velocity \
  task.soft_respawn=false task.success_terminate=false task.reward_scheme=f1 \
  task.reward_fly_weight=1.5 task.reward_zone_weight=1.5 task.reward_pbrs_weight=0.0 \
  task.arrive_bonus=40 task.arrive_time_bonus=40 \
  task.reward_timeout_penalty=60 task.reward_crash_penalty=15 task.reward_oob_penalty=15 \
  task.obstacle.num_scene=16 'task.obstacle.spawn_xy_range=[[-3.0,-3.0],[3.0,3.0]]' \
  'task.curriculum.levels=[8]' task.curriculum.enabled=false \
  task.cbf.mode=filter_only task.cbf.use_brake_term=false +runtime_filter=true \
  +render_every=1 \
  +cam_mode=topdown +trail=true \
  +checkpoint=$W/run-20260908_153058-2h7m8969/files/checkpoint_final.pt
```

启动后你会看到：
1. 终端打印 `>>> episode 0: loaded model -> checkpoint_final.pt`（**必须出现**，否则权重没加载，见 §6.1）；
2. Isaac Sim 窗口弹出，**俯瞰整条 6×6 走廊**；
3. 无人机从 `(-2.8,0,0.5)` 起飞，**蓝色轨迹拖影**一路生长，绕障飞向目标并悬停；
4. 本轮结束（到达超时 / 坠毁）自动 **reset → 换一批随机障碍布局**再来一轮，无限循环。

---

## 2. 命令参数修改教程

`demo_fly.py` 基于 hydra 覆盖式传参：在默认 `train.yaml` 上叠加你给的 `key=value`。
下面按“改什么 → 动哪个参数 → 例子”。

### 2.1 看哪个模型（checkpoint）

| 目标 | 参数 |
|---|---|
| 单个模型 | `+checkpoint=<绝对路径.pt>` |
| 同配置多模型逐轮轮换 | `'+ckpts=[ckpt_a.pt,ckpt_b.pt]'`（每轮 reset 后换下一个，见终端打印） |

⚠️ 一个模型对应一组训练配置（`cbf.mode / levels / num_scene / runtime_filter`），**换模型必须连这些一起换**。geo2r 四臂对照表：

| arm | ckpt run | 配套 `cbf.mode` | `+runtime_filter` | `curriculum.levels` | 说明 |
|---|---|---|---|---|---|
| **filter_only@8** | `...-2h7m8969` | `filter_only` | `true` | `[8]` | 推理期 CBF filter 硬保证 |
| **dual@8** | `...-ob5ko5as` | `hybrid` | `true` | `[8]` | 训练+推理都有 CBF |
| **reward_only@2** | `...-nfbiuvps` | `reward_only` | `false` | `[2]` | CBF 只进 reward，推理无 filter |
| **naive@2** | `...-dw0pydku` | `none` | `false` | `[2]` | 无 CBF，纯障碍 reward |

其中 run 前缀为 `$W/run-20260908_153058-<hash>/files/checkpoint_final.pt`。

### 2.2 随机 vs 固定起终点（决定“看什么”）

| 想看 | 写法 |
|---|---|
| 任意随机起终点（泛化演示，轨迹可能绕很大） | `+eval_points=train`（默认） |
| 固定穿越点，只让障碍随机（轨迹利落，推荐看绕障） | `+eval_points=fixed` + `task.fixed_init=[-2.8,0.0,0.5] task.fixed_target=[2.8,0.0,1.0]` |

注意：两种模式下**障碍布局每轮都会随机重采样**（由 `env.reset()` 内部完成），只是起终点不同。

### 2.3 障碍密度 / 布局范围

```bash
task.obstacle.num_scene=16                                  # 候选球总数
'task.obstacle.spawn_xy_range=[[-3.0,-3.0],[3.0,3.0]]'      # 障碍可放区域
'task.curriculum.levels=[8]'                                # 本轮实际激活障碍数（须与 ckpt 训练一致）
task.curriculum.enabled=false                               # demo 锁档不升级
```

想看低/高密度就把 `levels` 换成 `[2]` 或 `[12]`/`[16]`（但要 ckpt 是对应密度训的才有意义）。

### 2.4 一个画面几台机 / 同屏对比

```bash
task.env.num_envs=1     # 单机（推荐：俯瞰/跟随都清楚）
task.env.num_envs=4     # 4 个环境网格同屏，各自随机布局（适合一眼对比多种障碍）
```

> 俯瞰+轨迹只跟踪 **env0** 的无人机；num_envs 大时建议用多机网格同屏而不是轨迹。

### 2.5 播放速度（关键！GUI 默认极慢）

原因：GUI 每个物理步（0.01s）都渲染一帧，RTX 经 NX 渲染一帧要 0.3~1s 墙钟 → 近似慢放。

| 参数 | 效果 |
|---|---|
| `+render_every=0`（默认） | 每物理步都渲染，最卡 |
| `+render_every=30` | 明显加速，画面较流畅 |
| `+render_every=100` | ≈ 正常速度（多数场景推荐） |
| `+render_every=300` | 快进式浏览整轮轨迹 |

> 物理仍然每步都跑，只是画面每 N 步刷一帧。相机跟随/轨迹重绘会自动对齐到 N。

### 2.6 场景节奏（一轮多久 / 结束条件）

```bash
+per_ep_steps=1000      # 单轮步数上限（默认= max_episode_length=1000，即 10s 仿真）
+break_on_done=true     # 任一 env done（坠/出界/碰撞/超时）立即结束本轮换新场景
```

把 `+per_ep_steps` 调小（如 400）可让每轮更快换场景，适合快速扫不同布局。

### 2.7 一组必须与训练一致的 reward 键

下面的值决定 obs/几何口径与训练一致（**别乱改**，改的是演示同构性不是展示效果）：

```bash
task.soft_respawn=false task.success_terminate=false task.reward_scheme=f1 \
task.reward_fly_weight=1.5 task.reward_zone_weight=1.5 task.reward_pbrs_weight=0.0 \
task.arrive_bonus=40 task.arrive_time_bonus=40 \
task.reward_timeout_penalty=60 task.reward_crash_penalty=15 task.reward_oob_penalty=15
```

（它们来自 geo2r 训练脚本；不同训练轮的 ckpt 要带对应那组的键。）

---

## 3. 视角切换教程

脚本支持两套镜头，外加轨迹拖影与手动拖拽，互不冲突。

### 3.1 俯瞰整条走廊（默认 `+cam_mode=topdown`）

```bash
+cam_mode=topdown
+topdown_eye=[0.2, -7.0, 6.2]    # 相机位置 (x,y,z)，默认斜 45° 高空
+topdown_look=[0.0, 0.0, 0.6]    # 看的目标点
```

- 默认是 **斜 45° 俯瞰**（能看到高度变化、z 下潜绕障）。
- 想**纯正俯视**（只看 xy 绕障平面）：
  ```bash
  +topdown_eye=[0.0,0.0,9.0] +topdown_look=[0.0,0.0,0.0]
  ```
- 想拉近看细节，把 eye 的 z 从 6.2 降到 4 左右。
- 相机在每轮开始设一次；之后你可以在窗口里手动拖动。

### 3.2 相机跟随无人机（`+cam_mode=follow`）

```bash
+cam_mode=follow
```

镜头锁定在 **env0 无人机斜后方**（`y-2.6, z+1.7` 处朝前看），无人机到哪镜头跟到哪。
适合单机、想看清姿态/贴近障碍的表现。可调 `+cam_interval`（默认 3，越小越跟得紧）。

### 3.3 轨迹拖影（默认开 `+trail=true`）

```bash
+trail=true
+trail_len=1500    # 保留最近 1500 个物理步的轨迹（默认足够覆盖整轮 1000 步）
```

- 用场景里的 **DebugDraw 蓝色折线**画出 env0 无人机飞过的路径，随飞行“生长”；
- 配合俯瞰，一眼看出绕障绕了几道弯、从哪侧绕、是否下潜；
- 每轮 reset 自动清空重新画；`+trail=false` 可关。

### 3.4 窗口内手动操作（任何模式都可用）

- 鼠标 **滚轮**：缩放；
- **Alt + 左键拖拽**：旋转视角；
- **Alt + 右键拖拽**：平移。
- （若脚本每轮把 topdown 视角重置了，用上面方式调过后下轮会被复位——这是设计，保证每轮视角一致。）

### 3.5 终端里看实时位置（调试用）

```bash
+verbose_progress=100   # 每 100 步打印一行无人机位置 [cam] t=... pos=(x,y,z)
```

---

## 4. 每轮终端输出怎么看

```text
>>> episode 0: loaded model -> checkpoint_final.pt          # 权重已加载（必须出现）
[ep   0] checkpoint_final.pt  arrival= 1/1  collided= 0/1  mean|rpos|=0.089
```

| 字段 | 含义 |
|---|---|
| `arrival=x/N` | 本轮到过目标并保持 ≥50 步的 env 数 |
| `collided=x/N` | 本轮发生几何碰撞边沿的 env 数 |
| `mean|rpos|` | 结束时刻距目标的平均距离（越小越近） |

- `arrival=1` 且 `collided=0`：成功到达，刚才那轮是“飞到悬停”。
- `collided=1`：坠/碰后硬终止（单命）。
- 两者都 0：没到也没碰，无人机悬停原地 —— 该布局下的真实失败模式（CBF 挡路 / 找不到可行绕路）。

---

## 5. 快速命令库（直接复制改）

**filter_only@8 固定穿越 + 俯瞰 + 轨迹（推荐）** —— 见 §1。

**dual@8**（换 3 处即可，其余同 §1）：
```bash
  'task.curriculum.levels=[8]' task.curriculum.enabled=false \
  task.cbf.mode=hybrid task.cbf.use_brake_term=false +runtime_filter=true \
  +checkpoint=$W/run-20260908_153058-ob5ko5as/files/checkpoint_final.pt
```

**naive@2（无 CBF，纯策略自己绕）**：
```bash
  'task.curriculum.levels=[2]' task.curriculum.enabled=false \
  task.cbf.mode=none task.cbf.use_brake_term=false +runtime_filter=false \
  +checkpoint=$W/run-20260908_153058-dw0pydku/files/checkpoint_final.pt
```

**reward_only@2**：
```bash
  'task.curriculum.levels=[2]' task.curriculum.enabled=false \
  task.cbf.mode=reward_only task.cbf.use_brake_term=false +runtime_filter=false \
  +checkpoint=$W/run-20260908_153058-nfbiuvps/files/checkpoint_final.pt
```

**随机起终点 + 4 机同屏**（把 §1 的 `+eval_points=fixed ...fixed_init/target` 换成）：
```bash
  +eval_points=train task.env.num_envs=4 \
```

**把模型调成“撤销 CBF filter 看 internalize”**（对 dual/filter_only 模型）：
```bash
  +runtime_filter=false
```

**同配置多轮次模型逐轮自动轮换**：
```bash
  '+ckpts=[ckpt_A.pt, ckpt_B.pt]'
```

---

## 6. 常见坑（踩过，必读）

### 6.1 权重没加载 → 无人机乱飞/下沉/崩溃
终端启动后**必须看到** `>>> episode 0: loaded model -> ...`。没有就说明 `+checkpoint` 路径错了
（`$W` 未定义 / 路径不存在）。权重没加载 = 随机策略在飞，现象是：缓慢乱飘、沉底触地、甚至让 Isaac
崩掉（之前修掉的 bug：单 checkpoint 漏 load，现已在脚本内保证首轮必加载）。

### 6.2 换 arm 忘了换配套参数
naive/reward_only 的 ckpt 若带上 `runtime_filter=true` 或 `levels=[8]`，obs/几何与训练不一致，
表现会变差。用 §5 的表逐条对上。

### 6.3 画面极慢 / 几乎不动
不是没在飞，是 GUI 每步渲染拖慢。用 `+render_every=100~300`（§2.5）。也可开 `+verbose_progress`
看位置确实在变。

### 6.4 一个 Isaac 实例占满 GPU
新开演示前 `pkill -f demo_fly.py`，否则第二个 Isaac Sim 抢 GPU/显示会崩或看不到窗口。

### 6.5 停了但窗口还在
`Ctrl+C` 后等几秒 `Simulation App Shutting Down` 出现即已退出；必要时 `pkill -f demo_fly.py`。

---

## 7. 之后想做的事（附：headless 轨迹图工具）

想**离线出轨迹图（不含 GUI）** 看整轮 xy/z 曲线，用另一个脚本：

```bash
python -u vis_traj.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
  task.env.num_envs=32 +eval_points=fixed \
  task.fixed_init=[-2.8,0.0,0.5] task.fixed_target=[2.8,0.0,1.0] ...同配置... \
  +rollout_steps=1000 +checkpoint=$W/run-.../checkpoint_final.pt
# 输出 /home/lz/lzspace/drones/figures/vis_traj.png
```

---

## 8. 附：轻量版 play.py

只做“加载一个 ckpt 飞一次/一段时间、不换场景、无镜头控制”：

```bash
python -u play.py task=NavVel algo=ppo headless=false wandb.mode=disabled \
  task.env.num_envs=1 task.action_transform=velocity \
  task.fixed_init=[-2.8,0.0,0.5] task.fixed_target=[2.8,0.0,1.0] ...同配置... \
  total_frames=6000 +checkpoint=$W/run-.../checkpoint_final.pt
```

> play.py 用 torchrl collector 驱动，不是逐轮 reset；要看“不断换随机场景 / 跟拍 / 轨迹”，用 demo_fly.py。
