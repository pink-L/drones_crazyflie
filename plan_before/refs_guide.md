# NavRL 与 SimpleFlight：先从哪个开始 + refs 只读参考目录指南

> 配套阅读：`how2use.md`（§3 三个项目调研、§4 整合路线、§5 移植坑）。
> 本文回答三个问题：
> 1. NavRL / SimpleFlight 该**先 clone 哪个、先从哪个开始移植**；
> 2. 在 `/home/lz/lzspace` 里**新建什么目录、怎么 clone** 最合理；
> 3. 两个项目内部都带 OmniDrones，**会不会重复、要不要管**。

---

## 0. 一句话结论

- **先 SimpleFlight，后 NavRL**：你的研究本质是"给导航策略换动作层 + 安全层"，SimpleFlight 是动作层（速度指令 / CTBR → 低层控制器 → Crazyflie 电机）**唯一现成、且结构与你 fork 完全同构**的实现，是地基；NavRL 提供的是"任务内容"（导航观测/奖励 + 动态障碍），属于**概念移植**，且代码离你的 fork 更远（旧 Orbit API），放后面。
- **会重复，但不用管**：两个项目各自内嵌了一份旧版 OmniDrones + 旧 torchrl/tensordict（NavRL 还带旧 orbit/warp）。它们都是"冻结快照"，**不能也不该在本机 5.1 上跑**，只作 diff/阅读的参考。
- **目录**：新建 `/home/lz/lzspace/refs/`（只读、不进 PYTHONPATH、不 setup），两个项目浅 clone 放进去；**永远只改 `/home/lz/lzspace/drones/OmniDrones/`（5.1 fork）这一份代码**。

---

## 1. "会重复"吗？——核实结果与对策

我实际核对了两个仓库的结构：

| | SimpleFlight | NavRL |
|---|---|---|
| 项目性质 | **OmniDrones 的直接 fork** | 基于 OmniDrones + 旧 **Orbit** 重写的训练框架 |
| 内嵌的 OmniDrones | 仓库根目录 `omni_drones/`（一整份 fork 快照）+ `cfg/task/{Hover,Track}.yaml` + `usd/` 资产 | `isaac-training/third_party/OmniDrones/` |
| 内嵌的旧框架 | `.gitmodules` → `third_party/torchrl`(btx0424/rl)、`third_party/tensordict`（**ssh 地址**） | `isaac-training/third_party/`：`orbit`(旧 Isaac Lab) + `rl` + `tensordict` + `warp` |
| 目标 Isaac Sim | 2022.2.0，torchrl 0.1.1 | 2023.1.0-hotfix.1，旧 orbit API |
| 与本机兼容 | ❌（5.1 + torchrl 0.11.1） | ❌ |
| 大头内容 | Python（99.9%） | **C++ 70%** = `ros1/` 部署仿真器（与训练无关） |

**结论**：
- 是的，两个项目内部都各自带了一份**旧版** OmniDrones —— 与你 `/home/lz/lzspace/drones/OmniDrones`（tshiamor fork, isaacsim-5.1-blackwell）同源于 `btx0424/OmniDrones`，但**版本差距巨大，物理上无法运行**。
- 所以它们不是"要装的环境"，而是**只读的参考资料**（相当于论文的"代码附录"）。重复的部分（omni_drones 源码、torchrl 老版本）恰恰是"参考快照"，不该被装进你的环境，也不该被 copy 进你的 fork。
- **唯一代码库原则**：你的可运行/可编辑工程永远只有一份 —— `drones/OmniDrones`。refs 里的东西只用来：读、grep、diff、抄公式、抄小段纯 torch 逻辑。

---

## 2. 建议的目录布局与 clone 命令

```
/home/lz/lzspace/
├── drones/            # 你的可运行主仓库（唯一改代码的地方）
│   ├── OmniDrones/    # Isaac 5.1 fork（活动代码）
│   └── how2use.md / refs_guide.md（本文）
└── refs/              # 【新增】只读参考（不 pip install、不 setup.sh、不进 PYTHONPATH）
    ├── SimpleFlight/
    └── NavRL/
```

执行（用你仓库同款的 ghfast 代理前缀；浅 clone 足够，因为只要最新快照）：

```bash
mkdir -p /home/lz/lzspace/refs && cd /home/lz/lzspace/refs

# SimpleFlight：不 init 子模块！third_party 是 ssh 地址的旧 torchrl/tensordict，本机用不上
git clone --depth 1 https://ghfast.top/https://github.com/thu-uav/SimpleFlight.git

# NavRL：默认全量浅 clone（含 ros2/ 里的感知+安全滤波参考，值得保留）；空间不够再稀疏化
git clone --depth 1 https://ghfast.top/https://github.com/Zhefan-Xu/NavRL.git
```

两点说明：
- **不要** `git submodule update --init`（SimpleFlight 的 .gitmodules 用 `git@github.com:...` ssh 地址，无 ssh key 会直接失败；而且那些老 torchrl/tensordict 源码你并不需要）。
- 若想省空间，NavRL 可只取训练部分（跳过占 70% 的 ros1 C++ 部署代码）：

  ```bash
  cd /home/lz/lzspace/refs
  git clone --depth 1 --filter=blob:none --sparse https://ghfast.top/https://github.com/Zhefan-Xu/NavRL.git
  cd NavRL
  git sparse-checkout set isaac-training
  ```

> ⚠️ 提醒：refs 下的两个项目都**不要跑它们自己的 setup.sh / pip install -e .** —— 那会尝试装 2022.2/2023.1 时代的依赖，污染你的 `lz_env`。

---

## 3. 先做哪个？—— 先 SimpleFlight，再 NavRL

### 3.1 为什么先 SimpleFlight

1. **你的研究路线本质 = "换动作层 + 安全层"，而动作层只有 SimpleFlight 给了现成实现。**
   `how2use.md §4` 里，Step1（速度指令）、Step3（CTBR 三阶 CBF）都要求"策略输出 → 低层控制器 → 转子"这条管线；仓库自带 RL 主循环默认是转子级动作、没接 controller（§1.3/§5.2）。SimpleFlight 的 **`action_transform: PIDrate` + `cf2x_pid.py`(DSLPIDControl) + Crazyflie SysID 参数** 正是这条管线的唯一完整参考。

2. **结构与你 fork 100% 同构，diff 最小、最好抄。**
   SimpleFlight 就是 OmniDrones fork：同样 `omni_drones/envs/single/hover.py`、`cfg/task/Hover.yaml`、`scripts/train.py` 布局。它的**增量小而集中**（Track 任务 + PIDrate + crazyflie.yaml + eval.py），逐文件移植的边界非常清楚；NavRL 则把训练侧用旧 Orbit 重写了（`NavigationEnv`、障碍管理器、feature_extractor），结构离你远。

3. **能立刻验证、建立地基。**
   SimpleFlight 的验收 = 在你的 fork 里让 Crazyflie 用 PIDrate 跑通 Hover/Track（对应 `how2use §4.5` 的 M1/M4）。这块打通后，"速度指令"和"CTBR"两条路共用同一低层，**避免先用仓库自带 LeeController、后面又换 PIDrate 的返工**。

4. **版本鸿沟按文件可控。**
   SimpleFlight 的控制器 / 机器人参数是纯 torch / yaml，不依赖旧 Isaac API；真正要适配的只有旧 torchrl import（走你 `utils/torchrl/compat.py` 即可）。

### 3.2 什么时候才轮到 NavRL / 何时其实可以先不看它

- 等到你要做 **Step2 动态障碍**（M3）时再看 NavRL —— 取它的：动态障碍运动模型（随机游走/换目标/重采速度）、"最近 N 障碍(位置+速度+尺寸)"观测编码、导航奖励与终止设计。这些是**设计参考**，最终按 `how2use §4.2` 用你自己的纯 torch 障碍管理器重写。
- 变通：如果你的 M1 只想用"速度指令 + 仓库自带 LeeController + 静态障碍"快速验证 CBF1，**其实一开始可以不 clone/不读 NavRL**；但既然 Step3 终局是 CTBR + Crazyflie，仍建议低层一开始就统一成 SimpleFlight 的 PIDrate 管线。

---

## 4. 每个项目"真正值得看/移植的文件"清单

### 4.1 SimpleFlight（先读这些）

| 文件（refs/SimpleFlight/ 下） | 用途 → 对应你的落点 |
|---|---|
| `omni_drones/controllers/cf2x_pid.py` | **DSLPIDControl**（CTBR/速度 → 电机 RPM/PWM，crazyflie 固件风格 PID）→ 移植到 `drones/OmniDrones/omni_drones/controllers/cf2x_pid.py` |
| `cfg/task/Track.yaml` | `action_transform: PIDrate` 配置范式 + `use_eval/eval_traj` → 你的 `NavVel/NavCTBR.yaml` |
| `omni_drones/robots/assets/usd/crazyflie.yaml` | Crazyflie **SysID 参数**（mass 0.0321、惯量、force/moment constants、`time_constant: 0.025` 电机一阶滞后）→ 与你 fork 里 Crazyflie 参数核对/覆盖 |
| `omni_drones/envs/single/track.py` | 策略输出 CTBR 的任务写法、动作管线接法 → 你新任务 env 的骨架 |
| `scripts/train.py` / `eval.py` | action_transform 在训练入口如何按名字实例化 → 扩展你 `drones/OmniDrones/scripts/train.py` 的 transform 分支 |
| `models/deploy.pt` | 官方跟踪权重（仅对照用） |
| （可顺带看）`omni_drones/envs/single/hover.py`、`utils/torchrl/transforms.py` | 对照：SimpleFlight 在 hover 上如何接 transform |

### 4.2 NavRL（后读这些）

| 文件（refs/NavRL/ 下） | 用途 → 对应你的落点 |
|---|---|
| `isaac-training/training/scripts/env.py` | **NavigationEnv**：观测设计（目标系自身状态 8 维 + LiDAR + 最近 N 动态障碍各 10 维）、奖励、终止、**动态障碍随机游走** → 你的 `dynamic_obstacles.py` + 导航奖励 |
| `isaac-training/training/cfg/` | 静态/动态障碍数量、尺寸、速度范围等场景参数 |
| `isaac-training/training/scripts/ppo.py` | 处理 `dyn_obs_num` 动态障碍特征的 feature_extractor + actor |
| `isaac-training/training/scripts/train.py` | 训练规模/入口写法（对照即可） |
| `ros2/navigation_runner/`（可选） | 部署期感知 + **safe_action 安全滤波**，做"部署时估计 p_o/v_o 喂给 CBF"的参考 |
| `third_party/OmniDrones`、`third_party/orbit` | **不需要读**——就是它锁定的旧版快照，与训练设计无关 |

---

## 5. 对接你的研究路线（里程碑 ↔ 项目 ↔ 动作）

| 你的里程碑（how2use §4.5） | 主要参考项目 | 动作 |
|---|---|---|
| M1：Crazyflie + **速度指令**任务跑通（无 CBF） | **SimpleFlight** | 移植 PIDrate 管线，先只输出 3D 速度指令(或 +yaw_rate) |
| M4：Crazyflie + **PIDrate(CTBR)** 管线 | **SimpleFlight** | 策略改输出 4D CTBR，验证 Track 级表现 |
| M3：**动态障碍**（Step2） | **NavRL** | 移植障碍管理器 + 障碍观测/奖励（概念级） |
| M2/M5/M6：CBF1 滤波消融 / CBF3 滤波 / 鲁棒性 | （CBF-RL 范式为主，不在此二 repo） | `omni_drones/utils/cbf.py` / `cbf3.py` |

推进顺序建议：**refs 浅 clone（半天）→ 移植 SimpleFlight PIDrate 并在你 fork 里跑通 Hover/Track（地基）→ 建速度指令导航任务 + CBF1（M1/M2）→ 此时再深入 NavRL 做动态障碍（M3）→ CTBR + CBF3（M4/M5）**。

---

## 6. 注意事项 / 坑（浓缩版）

1. **refs = 只读**：不 `setup.sh`、不 `pip install -e .`、不 `git submodule update`（SimpleFlight 的 third_party 子模块是 ssh 地址，会直接失败；NavRL 的 third_party 全是旧版，装了会毁掉 `lz_env` 的 torchrl 0.11.1）。
2. **不整目录复制**：别把 refs 里的 `omni_drones/` 拷进你的 fork —— 版本差了几代。要"文件级移植 + 逐行适配 5.1 API"。
3. **对比增量的小技巧**：SimpleFlight / NavRL 与你的 fork 同源于 `btx0424/OmniDrones`，可用 `git diff` 找"它们到底改了上游什么"；不过更实用的是直接按 §4 清单读文件，因为增量集中在那几处。
4. **动作语义**：确认 `env.action_spec` 与 `_pre_sim_step` 之间插入了低层控制器（`drone.apply_action` 只认转子指令），否则维度/物理语义全错（how2use §5.2）。
5. **版本相关 import**：一律走 `omni_drones.utils.torchrl.compat`，别直接 `from torchrl.data import CompositeSpec`（how2use §5.3）。
6. **NavRL 别被 ros1 吓到**：C++ 占 70% 全是 ROS1/Gazebo 部署仿真，训练代码只在 `isaac-training/training/`，纯 Python。
7. **磁盘**：`/` 分区剩 1.5T，两个浅 clone 无压力（不必 sparse，除非在意下载时间）。

---

## 7. 参考

- 本仓库：`drones/OmniDrones`（tshiamor fork，isaacsim-5.1-blackwell），上游 `btx0424/OmniDrones`
- SimpleFlight：`github.com/thu-uav/SimpleFlight`（fork 自 btx0424/OmniDrones；`omni_drones/` 内嵌）
- NavRL：`github.com/Zhefan-Xu/NavRL`（`isaac-training/third_party/OmniDrones` 内嵌）
- 你的整合路线：`how2use.md` §3–§5
