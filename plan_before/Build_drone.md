# Build_drone — OmniDrones 构建指导(Isaac Sim 5.1 + RTX 5090 Blackwell)

> 本文档基于仓库根目录 [`README.md`](./README.md)、[`setup_env.sh`](./setup_env.sh)
> 以及实际机器环境整理,给出从**拉取代码 → 搭建环境 → 验证 → 运行示例/训练**的完整、可复现步骤。
>
> 构建目标:在 **Linux x86_64 + NVIDIA Blackwell(RTX 5090)** 上运行
> **Isaac Sim 5.1 + OmniDrones(多旋翼无人机 RL 仿真平台)**。

---

## 0. 构建进度快照(2026-09-04  CST 更新)

> **一句话结论:全链路已打通 ✅**——渲染(NVIDIA 驱动 595.84→**580.173.02**,§7.9)、
> torchrl 0.11.1 适配(§7.8)、wandb(§7.10)、PPO 训练运行期适配(§7.11)全部完成。
> **`max_iters=1` 短训练完整跑通(EXIT=0)**:Hover/PPO 产出 policy/value loss、Final Eval 渲染
> 500 帧视频、成功保存 `checkpoint_final.pt`、Simulation App 正常关闭。当前可进入正式训练。
>
> ⚠️ **重要更正**:本文档及 `README.md` 中的 `conda activate omnidrones` 与实际不符——
> 本机实际环境名为 **`lz_env`**,所有包均已装入该环境。后续命令请用:
> `conda activate lz_env`(conda 位于 `/home/hybrid/miniconda3`)。

| 阶段 | 状态 | 说明 |
|---|---|---|
| §4.1 拉码 + 子模块 | ✅ 完成 | 顶层 `main@50df183`;OmniDrones 子模块 `688774c`(`isaacsim-5.1-blackwell`) |
| §4.2 conda 环境 | ✅ 完成 | Python 3.11.16,实际环境名 **`lz_env`**(17:28 创建) |
| §4.3 Isaac Sim | ✅ 完成 | `isaacsim 5.1.0`(pip,装入 `lz_env`) |
| §4.4 PyTorch + 依赖修复 | ✅ 完成 | `torch 2.7.0+cu128` / CUDA 12.8;torchrl **0.11.1**(§7.8) |
| §4.5 IsaacLab | ✅ 完成 | `./IsaacLab` v2.3.0(editable 装入 `lz_env`) |
| §4.6 OmniDrones | ✅ 完成 | `pip install -e .`(`0.1.1`)+ 兼容补丁(§7.8/§7.11) |
| §5 验证 import + CUDA | ✅ 通过 | RTX 5090 D;Capability `(12,0)` SM_120;import 全过 |
| §6.1 冒烟 demo | ✅ 通过(00:55) | headless 与 GUI 均正常,100/100 steps 正常退出 |
| §6.2 RL 训练 | ✅ 通过(01:29) | Hover/PPO `max_iters=1` 全链路 EXIT=0:训练 loss + Eval 500 帧视频 + checkpoint_final.pt(§7.11) |

**当前状态:短训练验证通过,可进入正式训练。** checkpoint 默认落在 wandb 本地目录
(`/tmp/wandb/run-*/files/checkpoint_final.pt`,disabled 模式)。正式训练建议带 `save_interval`
与 `total_frames`,并按需开启 wandb online(见 §7.11)。

---

## 1. 目录与版本一览

| 组件 | 版本 | 说明 |
|---|---|---|
| OS | Linux x86_64 | 不支持 Windows |
| GPU | RTX 5090 D(Blackwell, SM_120) | 32 GB |
| NVIDIA Driver | **580.173.02(实测 ✅)** | 5.1.0 官方配对 580.65.06;此前 595.84 过新致 RTX 渲染崩溃,降级后已解决(§7.9) |
| Python | 3.11 | Isaac Sim 5.1 要求 |
| Isaac Sim | 5.1.0 | pip 方式安装(`pypi.nvidia.com`) |
| PyTorch | 2.7.0 + cu128 | 需 CUDA 12.8 轮子以支持 SM_120 |
| torchrl | 0.11.1(**须固定**) | RL 库;勿被升级到 ≥0.13(spec 类改名会导致 ImportError,见 §7.8) |
| IsaacLab | v2.3.0 | **必需**:`forest.py` / `pinball.py` 会 `import isaaclab` |
| OmniDrones | 0.1.1(fork: `isaacsim-5.1-blackwell`) | 为 5.1 打过补丁的分支 |

**重要:代码来源差异(与上游 README 不同)**

本仓库通过 **git 子模块**管理 OmniDrones,指向已适配 5.1/Blackwell 的 fork:

- 仓库位置:`/home/lz/lzspace/drones`
- 子模块 URL:https://github.com/tshiamor/OmniDrones.git
- 子模块分支:`isaacsim-5.1-blackwell`(当前 HEAD `688774c`)
- 注意:**不要**克隆上游 `btx0424/OmniDrones` 覆盖它,否则会丢失 5.1 兼容补丁。

### 仓库结构

```
/home/lz/lzspace/drones/            # 顶层仓库
├── README.md                       # 使用说明(英文)
├── Build_drone.md                  # 本文档(构建指导)
├── setup_env.sh                    # 一键环境搭建脚本
├── .gitmodules                     # OmniDrones 子模块声明
├── OmniDrones/                     # 子模块(fork, 5.1-blackwell 分支)
│   ├── examples/                   # 演示脚本(00_play_drones.py 等)
│   ├── scripts/                    # 训练脚本(train.py / play.py, Hydra)
│   ├── cfg/                        # Hydra 配置(algo/ task/ train.yaml)
│   ├── omni_drones/
│   │   ├── envs/                   # RL 环境(任务):single/ multi/ 下含 Forest 等
│   │   ├── robots/                 # 无人机模型(Hummingbird/Crazyflie/...)
│   │   ├── learning/               # RL 算法(ppo/sac/mappo/...)
│   │   ├── actuators/              # 旋翼动力学
│   │   ├── controllers/            # PID / Lee 控制器
│   │   ├── sensors/                # Camera / LiDAR
│   │   ├── views/                  # Isaac Sim Prim Views(5.1 补丁)
│   │   └── utils/torchrl/          # torchrl wrapper + 兼容层
│   ├── conda_setup/etc/conda/      # conda activate/deactivate hook
│   └── setup.py                    # pip 安装元数据(依赖见 §4.5)
└── IsaacLab/                       # (setup_env.sh 生成) IsaacLab v2.3.0
```

---

## 2. 前置条件检查

在开始前确认以下各项:

| 检查项 | 命令 | 通过标准 |
|---|---|---|
| GPU 与驱动 | `nvidia-smi` | 识别到 RTX 5090,驱动 ≥ 580 |
| conda | `conda --version` | miniforge / miniconda |
| 磁盘空间 | `df -h` | 建议预留 ≥ 50 GB(Isaac Sim + 缓存较大) |
| 网络 | 能访问 `pypi.nvidia.com`、`download.pytorch.org`、`github.com` | 下载依赖需要 |

> CUDA Toolkit 无需单独安装 —— 通过 PyTorch 的 **cu128 轮子**提供 CUDA 12.8 运行库。

### 代码目录写权限(重要)

`setup_env.sh`、子模块 checkout、IsaacLab clone 以及本文档都需要在仓库内写入。
若遇到 `Permission denied`(如 `could not lock config file .git/config`),说明当前用户不是仓库属主,执行:

```bash
# 把仓库所有权移交当前用户(需 sudo)
sudo chown -R "$USER":"$USER" /home/lz/lzspace/drones
```

若使用「加入属组」方案(`sudo usermod -aG <group> $USER`),**必须注销并重新登录**后组的补充权限才生效。

---

## 3. 一键构建(推荐路径)

```bash
cd /home/lz/lzspace/drones
source setup_env.sh
```

> ⚠️ 必须用 `source`(或 `.`)执行,脚本内部会 `conda activate`;
> 请从仓库根目录运行,使脚本内的 `$SCRIPT_DIR` 指向仓库本身。
> 第 2 步下载 Isaac Sim 体积很大(数 GB),整体耗时较长,请耐心等待。

脚本内部按序完成以下 6 步(`[1/6]`~`[6/6]`):

| 步骤 | 操作 | 说明 |
|---|---|---|
| 1 | `conda create -n omnidrones python=3.11` | 已存在则跳过 |
| 2 | `pip install "isaacsim[all,extscache]==5.1.0"` | 需 `--extra-index-url https://pypi.nvidia.com`,下载量大 |
| 3 | 安装 `torch==2.7.0 +cu128` 等 | CUDA 12.8 轮子,支持 SM_120 |
| 3b | 回滚被强装破坏的依赖 | `numpy==1.26.0 filelock==3.13.1 fsspec==2024.6.1 markupsafe==2.1.3 networkx==3.3 sympy==1.13.3 Pillow==11.3.0 typing_extensions==4.12.2` |
| 4 | 克隆 **IsaacLab v2.3.0** 到 `./IsaacLab` 并 `echo Yes | ./isaaclab.sh --install` | 首次不存在才 clone |
| 5 | `cd OmniDrones && pip install -e .` | 见 §4.5 依赖;子模块需已初始化(见 §4.1) |
| 6 | 自动验证 import + CUDA | 打印 PyTorch/CUDA/GPU/Compute Capability |

> ⚠️ **顺序陷阱**:`setup_env.sh` 第 5 步以「目录是否存在」判断是否 clone OmniDrones。
> 若子模块**未初始化**(`OmniDrones/` 为空但目录存在),脚本会静默跳过 clone,
> 随后 `pip install -e .` 因目录为空而失败。
> **因此必须先在 §4.1 初始化子模块,再运行本脚本。**

---

## 4. 手动分步构建(排查 / 复现用)

> 适合单独复现脚本中的某一步,便于定位失败原因。顺序与 §3 一致。

### 4.1 拉取代码并初始化子模块

```bash
cd /home/lz/lzspace/drones

# 主仓已含 OmniDrones 子模块声明,初始化并拉取(会 checkout 到记录的分支提交)
git submodule update --init --recursive

# 从 detached HEAD 切到开发分支(推荐,便于跟踪 fork 更新)
cd OmniDrones
git checkout isaacsim-5.1-blackwell
cd ..
```

验证:

```bash
git submodule status
# 期望输出(无前导 '-'/'+' 表示干净):
#  688774c... OmniDrones (heads/isaacsim-5.1-blackwell)
```

后续拉取 fork 更新:

```bash
git -C OmniDrones pull origin isaacsim-5.1-blackwell
# 主仓记录新提交(在顶层仓库)
git add OmniDrones && git commit -m "Update OmniDrones submodule"
```

### 4.2 创建 conda 环境

```bash
conda create -n omnidrones python=3.11 -y
conda activate omnidrones
pip install --upgrade pip -q
```

### 4.3 安装 Isaac Sim 5.1.0(pip 方式)

```bash
pip install "isaacsim[all,extscache]==5.1.0" \
    --extra-index-url https://pypi.nvidia.com
```

- pip 安装后 `isaacsim` 可直接 import,**无需** `ISAACSIM_PATH` 或
  `setup_conda_env.sh`(见 fork 自带 `conda_setup/.../activate.d/env_vars.sh`)。
- 下载体积大、耗时长;失败重试同一命令即可(有缓存)。

### 4.4 安装 PyTorch cu128 + 修复依赖

```bash
pip install --force-reinstall torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 \
    --index-url https://download.pytorch.org/whl/cu128

# isaacsim 会同时拉入 torch 的 CPU 版或错误 CUDA 版;force-reinstall 会破坏部分依赖版本,需回滚:
pip install numpy==1.26.0 filelock==3.13.1 fsspec==2024.6.1 markupsafe==2.1.3 \
    networkx==3.3 sympy==1.13.3 Pillow==11.3.0 typing_extensions==4.12.2
```

### 4.5 安装 IsaacLab v2.3.0

```bash
cd /home/lz/lzspace/drones
git clone --branch v2.3.0 https://github.com/isaac-sim/IsaacLab.git IsaacLab
cd IsaacLab
echo "Yes" | ./isaaclab.sh --install
```

> IsaacLab 是**运行依赖**而非可选:`omni_drones/envs/single/forest.py` 与
> `pinball.py` 会 `import isaaclab`,缺失时运行 `task=Forest/Pinball` 会 ImportError。

### 4.6 安装 OmniDrones

```bash
cd /home/lz/lzspace/drones/OmniDrones
pip install -e .
```

`setup.py` 声明的依赖:`hydra-core`、`omegaconf`、`wandb`、`imageio`、`plotly`、
`einops`、`pandas`、`moviepy`、`av`、`torchrl>=0.6.0`(fork 已为 torch 2.7 更新)。

### 4.7 conda hook(推荐,可选)

fork 自带 conda hook,用于在激活 `omnidrones` 时自动设置
`TORCH_CUDA_ARCH_LIST="12.0"`(SM_120 架构码),对需要编译/运行部分扩展的场景有帮助:

```bash
# 把 hook 同步进环境(激活 omnidrones 时生效)
cp -r /home/lz/lzspace/drones/OmniDrones/conda_setup/etc/conda/* \
      "$CONDA_PREFIX/etc/conda/"
```

或手动(每个新 shell,本机实际环境为 `lz_env`):

```bash
conda activate lz_env
export TORCH_CUDA_ARCH_LIST="12.0"
```

---

## 5. 验证安装

```bash
conda activate lz_env
python -c "
import torch
assert torch.cuda.is_available(), 'CUDA not available'
print('PyTorch:', torch.__version__)
print('CUDA  :', torch.version.cuda)
print('GPU   :', torch.cuda.get_device_name(0))
print('Capability:', torch.cuda.get_device_capability(0))   # 期望 (12, 0) = SM_120 (Blackwell)
import omni_drones
print('OmniDrones: OK')
"
```

期望结果:

```
PyTorch: 2.7.0+cu128
CUDA  : 12.8
GPU   : NVIDIA GeForce RTX 5090 D
Capability: (12, 0)
OmniDrones: OK
```

> 注:RTX 50 系列 Blackwell(SM_120)的 compute capability 为 **(12, 0)**;若出现 SM_120 警告或 capability 不符,说明 cu128 轮子被覆盖,见 §7.3。

---

## 6. 运行示例与训练

> 每次新开终端先 `conda activate lz_env`(本机实际环境名,见 §0)。
> 首次启动会编译着色器缓存,较慢属正常。

### 6.1 冒烟测试(无人机飞行演示)

```bash
cd /home/lz/lzspace/drones/OmniDrones/examples
python 00_play_drones.py headless=true steps=100
```

- `headless=true` 无界面;去掉则弹出 GUI(需显示器)。
- 可用示例(均在 `examples/`):

| 脚本 | 内容 |
|---|---|
| `00_play_drones.py` | 4 架 Hummingbird 圆形轨迹飞行;可 `drone_model.name=Crazyflie` / `drone_model.controller=LeePositionController` 覆盖 |
| `01_drones_with_cams.py` | 带机载相机传感器 |
| `demo_downwash.py` | 多机下洗流效应 |
| `demo_task.py` | 单个 RL 任务环境(默认 Hover) |
| `demo_transport.py` | 多机协同运输(另见 `demo_transport_lissajous.py` 李萨如轨迹) |
| `test_att_controller.py` / `test_rate_controller.py` | 姿态 / 角速率控制器测试 |
| `test_dragon.py` | 铰接式 Dragon 无人机 |

### 6.2 训练策略(Hydra + W&B)

> ✅ **本机已打通(2026-09-04 01:29)**:`task=Hover algo=ppo headless=true wandb.mode=disabled max_iters=1`
> 完整跑通(EXIT=0),训练产出 loss、Final Eval 渲染 500 帧视频并保存 checkpoint(运行期适配见 §7.11)。

**快速验证**(推荐先跑,约 1–2 分钟出结果):
```bash
conda activate lz_env
cd /home/lz/lzspace/drones/OmniDrones/scripts
python train.py task=Hover algo=ppo headless=true wandb.mode=disabled max_iters=1
```

**正式训练**(建议先小规模确认稳定,再逐步放大):
```bash
python train.py task=Hover algo=ppo headless=true wandb.mode=disabled \
    total_frames=1_000_000 save_interval=100000
```

- 任务(`task=`):单智能体 `Hover/Track/FlyThrough/Payload*/InvPendulum*/Forest/Pinball`;
  多智能体 `Platform*/Transport*/Formation` 等。
- 算法(`algo=`):`ppo sac td3 mappo matd3 qmix dqn` 等(`cfg/algo/`)。
- 开启 W&B 记录:去掉 `wandb.mode=disabled`,或 `wandb.entity=YOUR_ENTITY`。
- LiDAR 训练:`python train_lidar.py task=Forest algo=ppo headless=true wandb.mode=disabled`。

常用 Hydra 覆盖:

| 参数 | 说明 | 默认 |
|---|---|---|
| `headless=true/false` | 是否无界面 | 训练默认 true |
| `steps=N` / `total_frames=N` | 步数 / 总训练帧 | `150000000` |
| `sim.dt=0.016` | 物理步长 | `0.016` |
| `sim.device=cuda:0` | 计算设备 | `cuda:0` |
| `wandb.mode=disabled` | 关闭 W&B | online |

### 6.3 回放已训练策略

> checkpoint 位置:wandb `mode=disabled` 时保存在本地 run 目录
> `/tmp/wandb/run-*/files/checkpoint_*.pt`(如 `checkpoint_final.pt`);**建议及时拷贝留存**(`/tmp` 重启会清空)。

```bash
cd /home/lz/lzspace/drones/OmniDrones/scripts
python play.py task=Hover algo=ppo checkpoint=/tmp/wandb/run-*/files/checkpoint_final.pt headless=true
```

---

## 7. 常见问题与排错

### 7.1 git 权限:`could not lock config file .git/config: Permission denied`

仓库属主不是当前用户所致。将仓库移交当前用户:

```bash
sudo chown -R "$USER":"$USER" /home/lz/lzspace/drones
```

或加入属组后**注销重登**(组权限不会在当前会话自动刷新)。

### 7.2 子模块处于 detached HEAD

`git submodule update --init` 默认 checkout 到记录提交而非分支,属正常。
如需跟踪分支:

```bash
cd OmniDrones && git checkout isaacsim-5.1-blackwell
```

### 7.3 PyTorch SM_120 警告 / 计算能力不是 (12,0)

说明 cu128 轮子被其他包覆盖,强制重装:

```bash
pip install --force-reinstall torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 \
    --index-url https://download.pytorch.org/whl/cu128
```

### 7.4 首次运行 / 启动很慢

- Isaac Sim 首次运行编译着色器(shader cache),一次性耗时,之后变快。
- 若 `omni.client` 反复连接本地端口失败,属资源服务器慢,耐心等待或检查网络。

### 7.5 `task=Forest/Pinball` ImportError: isaaclab

IsaacLab 未安装或未注册。回到 §4.5 安装 v2.3.0。

### 7.6 想把 IsaacLab 排除出版本管理

`setup_env.sh` 会在仓库内生成体积很大的 `IsaacLab/`,建议加入 `.gitignore` 防止误提交:

```bash
echo "IsaacLab/" >> /home/lz/lzspace/drones/.gitignore
```

### 7.7 GitHub 无法访问 / 安装时 `git clone` TLS 错误(GnuTLS recv error)

安装 IsaacLab 等依赖时会从 GitHub 拉取 `rl_games` 等仓库,在受限网络下常报:

```
fatal: unable to access 'https://github.com/...': GnuTLS recv error (-110)
```

根因通常是 `github.com` 被 DNS 解析到不通的节点(如亚太 `20.205.*`),而某些北美节点间歇可用。处理:

**① 验证是否为 DNS 指向问题**:

```bash
getent ahosts github.com        # 若指向 20.205.x 且不通,继续下面步骤
curl -skI --resolve github.com:443:140.82.114.3 https://github.com   # 测可用 IP
```

**② 固定可用 IP(可选,需 sudo)**——把可直连的 IP 追加进 `/etc/hosts`:

```bash
sudo sh -c 'printf "140.82.114.3 github.com\n140.82.116.3 github.com\n140.82.121.3 github.com\n" >> /etc/hosts'
```

> 该方法时好时坏(GitHub 对这些 IP 的封锁是间歇性的),若仍失败用下面镜像方案。

**③ 走 GitHub 镜像加速(推荐,最稳定)**——通过 git 全局 URL 重写,让所有 GitHub clone(含 pip 内部的)自动走镜像:

```bash
# 让 https://github.com/ 前缀的 clone 全部改写为镜像地址
# 镜像可选: ghfast.top / gh-proxy.com / ghproxy.net 等
GIT_MIRROR=https://ghfast.top/https://github.com/
git config --global url."${GIT_MIRROR}".insteadOf "https://github.com/"

# 验证(应成功且走镜像)
git ls-remote https://github.com/isaac-sim/rl_games.git HEAD

# 安装完成后如需取消
# git config --global --unset-all url."https://ghfast.top/https://github.com/".insteadOf
```

**④ 环境要点**:请**先确认在目标 conda 环境**(含 Isaac Sim 5.1)中再跑安装,避免装到错误的 Python 环境。

### 7.8 `ImportError: cannot import name 'CompositeSpec' from 'torchrl.data'`(train.py 等)

**症状**:
```bash
python train.py task=Hover algo=ppo headless=true wandb.mode=disabled
# ImportError: cannot import name 'CompositeSpec' from 'torchrl.data' (site-packages/torchrl/data/__init__.py)
```
训练/回放脚本(`train.py` / `play.py` / `train_lidar.py`)与部分 RL 算法(`sac/td3/matd3/mappo`)在 import 阶段失败。

**根因**:torchrl ≥ 0.6 将 spec 类**改名**并最终删除旧名(`CompositeSpec→Composite`,
`UnboundedContinuousTensorSpec→UnboundedContinuous` …)。本机 `torchrl` 在装 IsaacLab 期间(约 21:54)
被**升级到 0.13.3**,超出本 fork `compat.py`(适配 0.3→0.11.x)的范围;而 `scripts/*.py` 及部分
`learning/*.py` 仍**直接** `from torchrl.data import <旧名>`,未走 fork 自带的兼容层
(`omni_drones/utils/torchrl/compat.py`),于是 import 失败。另外 `learning/mappo_new.py` 有一处
`make_functional` 导入被误插入未闭合的 `from tensordict.nn import (` 括号内,导致 **SyntaxError**。

**解决(两步,本机已完成)**:

① 把 torchrl 回锁到 fork/README 适配的 **0.11.1**(会自动把 tensordict 降到 0.11.0):
```bash
conda activate lz_env
pip install "torchrl==0.11.1"
python -c "import torchrl, tensordict; print(torchrl.__version__, tensordict.__version__)"  # 0.11.1 0.11.0
```

② 把漏改的直接导入统一改为走 compat 层(即使 0.11.1 也建议如此,防再次漂移):
- `scripts/train.py`、`scripts/play.py`:
  `from torchrl.data import CompositeSpec` → `from omni_drones.utils.torchrl.compat import CompositeSpec`
- `scripts/train_lidar.py`:
  `from torchrl.data import CompositeSpec, TensorSpec` → `from omni_drones.utils.torchrl.compat import CompositeSpec, TensorSpec`
- `examples/demo_task.py`(示例脚本,同款残留,2026-09-04 一并修复):
  `from torchrl.data import CompositeSpec` → `from omni_drones.utils.torchrl.compat import CompositeSpec`
- `omni_drones/learning/{mappo,sac,td3,matd3}.py`:
  `from torchrl.data import UnboundedContinuousTensorSpec as UnboundedTensorSpec`
  → `from omni_drones.utils.torchrl.compat import UnboundedContinuousTensorSpec as UnboundedTensorSpec`
  (行内同时导入的 `TensorDictReplayBuffer` 仍从 `torchrl.data` 导入)
- `omni_drones/learning/mappo_new.py`:把误插入 `from tensordict.nn import (` 括号内的
  `from omni_drones.utils.tensordict_compat import make_functional` **移到括号闭合之后**(修正 SyntaxError)。

**验证**:训练脚本顶部全部 import 通过,不再报 torchrl 相关错误。
> 📌 渲染崩溃问题已另行解决(见 §7.9);渲染通过后训练又遇到 wandb API 变更(见 §7.10)。

### 7.9 ✅ 已解决:NVIDIA 驱动 595.84 过新 → Isaac Sim 5.1 RTX 渲染初始化崩溃(复盘)

> **✅ 解决(2026-09-04 00:55)**:把 NVIDIA 驱动从 **595.84 降级到 580.173.02**(Isaac Sim 5.1.0
> 官方配对 580.65.06 系列)后,**headless 与 GUI 均恢复正常**:无头冒烟成功;有头(`headless=false`)
> 正常弹出窗口、不闪退,跑完 `100/100 steps` 后正常退出。
> 根因 = **驱动版本过新**(595.84 是给 Isaac 6.x 验证的),与 OmniDrones 代码、headless/GUI、双 GPU 均无关。

**症状(当时)**:
- headless 与 GUI 崩溃栈一致(GUI 见 `/tmp/gui1.log`,EXIT=139):
  ```
  [Fatal] librtx.scenedb.plugin.so … carbOnPluginStartup
  [Fatal] libcarb.scenerenderer-rtx.plugin.so … carbOnPluginShutdown
  [Fatal] libomni.hydra.rtx / libomni.usd / libcarb.tasking …
  ```
- 无声崩溃(无 Error 日志);GUI 表现为"窗口一闪即退",无头/有头均复现。

**已排除**:shader/kit 缓存、Vulkan 枚举(kit `systemInfo` 能枚举到 5090)、强制 `VK_ICD_FILENAMES`、
`multi_gpu=False`、`anti_aliasing`、PRIME render offload、内核/用户态驱动不匹配(DKMS 干净 595.84)、
内存/磁盘、双 GPU 显示归属。

**根因**:Isaac Sim 5.1.0 官方测试驱动 = **580.65.06**(见官方 Requirements);
595.84(2026-06)是为最新 Isaac **6.x**(配对 595.58.03)验证的,超出 5.1.0 支持范围
→ RTX 渲染器(scenerenderer-rtx / librtx.scenedb)初始化崩溃。5.1.0 已 EOL,勿升 6.x(OmniDrones fork 面向 5.1)。

**解决(已验证)**:
```bash
sudo apt install nvidia-driver-580-open   # 降到 580 系列;装完 reboot
nvidia-smi                                # 580.173.02 ✅
```

**经验**:安装/升级 NVIDIA 驱动后务必核对 Isaac Sim 官方 Requirements 的配对驱动版本;
驱动过新或过旧都可能引发无声的原生崩溃,与项目代码无关。

### 7.10 `AttributeError: module 'wandb.util' has no attribute 'generate_id'`(训练 init_wandb)

**症状**:渲染修复后跑 `python train.py task=Hover algo=ppo …`(任何调用 `init_wandb` 的脚本),
Isaac Sim 已正常启动到 `Simulation App Startup Complete`,随后在 `omni_drones/utils/wandb.py` 的
`kwargs["id"] = wandb.util.generate_id()` 处报 `AttributeError`。

**根因**:本机 wandb 为 **0.29.0**,已移除 `wandb.util.generate_id`(迁移到
`wandb.sdk.lib.runid.generate_id`);fork 代码仍用旧 API。

**解决(已在本机修复)**:`omni_drones/utils/wandb.py` 顶部做兼容导入并在 `init_wandb` 中使用:
```python
try:
    from wandb.sdk.lib.runid import generate_id as _generate_id
except ImportError:          # 旧版 wandb
    from wandb.util import generate_id as _generate_id
# ... init_wandb 内:
kwargs["id"] = _generate_id()
```

**经验**:fork 面向较老 wandb;升级 wandb 后若遇 `wandb.util` / `wandb.run` 相关 `AttributeError`,
多为 API 迁移,按新版路径改即可。

### 7.11 ✅ PPO 训练运行期适配(torchrl 0.11.1 / Isaac Sim 5.1,短训练 EXIT=0)

**背景**:渲染/import/wandb 修复后,`python train.py task=Hover algo=ppo headless=true wandb.mode=disabled max_iters=1`
仍反复 segfault(EXIT=139)。逐一排查共 **4 个运行期问题**——注意:每个 Python 异常都会被**退出/关闭时的
二次原生崩溃(omni.syntheticdata / omni.graph 清理)掩盖**,必须从运行日志 `grep -iE "Traceback|Error"`
才能看到真凶。

**① `ValueError: not enough values to unpack (expected 2, got 1)`(`ppo.py:101`)**
- 根因:torchrl ≥0.6 中 `CompositeSpec.shape` **只含 batch 维**(`.expand(num_envs)` 后 = `[num_envs]`);
  旧代码 `self.n_agents, self.action_dim = action_spec.shape[-2:]` 解包失败。
- 修:叶子 spec 带完整形状 → 取 `action_spec[("agents","action")].shape[-2:]`(= `[n_agents, act_dim]`);
  同类 `reward_spec[("agents","reward")].shape[-2:]` 给 `ValueNorm1`(已改 `ppo.py`,见下提醒)。

**② `KeyError: 'sample_log_prob'`(`ppo.py` `_update`)**
- 根因:torchrl 0.11 的 `ProbabilisticActor` 在 `out_keys=[('agents','action')]`(嵌套 key)时,
  log_prob 被写到**嵌套** `('agents','action_log_prob')`,而旧代码读**顶层** `sample_log_prob`。
- 修:给各 actor 构造加 `log_prob_key="sample_log_prob"`(实测会把 log_prob 写回顶层),共 6 处:
  `learning/ppo/{ppo,ppo_rnn,ppo_adapt,mappo}.py`、`learning/mappo_new.py`、`scripts/train_lidar.py`。

**③ `isaac_env.render` 崩溃(`IndexError` → `ValueError: zero-size array`)**
- 根因:Isaac Sim 5.1 的 `"rgb"` annotator 返回 shape/就绪时序与旧版不同(离屏首帧可能为空/扁平)。
- 修(`omni_drones/envs/isaac_env.py` `render`):统一转 uint8、兼容扁平缓冲
  (按 `cfg.viewer.resolution` reshape)、**空数据返回黑帧占位**,避免崩溃。

**④ `RuntimeError: Parent directory …/files does not exist`(`torch.save` checkpoint)**
- 根因:wandb `mode=disabled` 时 `run.dir`(`/tmp/wandb/run-*/files`)未创建。
- 修:`scripts/train.py` 两处 `torch.save` 前加 `os.makedirs(os.path.dirname(ckpt_path), exist_ok=True)`。

**验证(01:29)**:`max_iters=1` → **EXIT=0**;训练产出 `policy_loss/value_loss`;`Final Eval` 渲染
500 帧视频;checkpoint 保存到 `/tmp/wandb/run-*/files/checkpoint_final.pt`;`Simulation App Shutting Down` 正常。

**提醒**:
- `ppo_rnn/ppo_adapt/mappo/mappo_new` 里仍有同款 `spec.shape[-2:]` 写法,跑这些算法时需按 ① 处理;
- 正式训练建议:设 `total_frames`(如 `1_000_000`)+ `save_interval=N`;要长期保留 checkpoint 可自行从
  wandb run 目录拷贝,或改用 wandb online(`wandb.entity=…`)。

---

## 8. 快速参考(常用命令串)

```bash
# 初始化子模块并切分支
cd /home/lz/lzspace/drones && git submodule update --init --recursive
cd OmniDrones && git checkout isaacsim-5.1-blackwell && cd ..

# 一键搭建
source /home/lz/lzspace/drones/setup_env.sh

# 验证(注意:实际环境名是 lz_env,不是 omnidrones)
conda activate lz_env
python -c "import torch; print(torch.cuda.get_device_capability(0), torch.__version__)"

# 示例
cd /home/lz/lzspace/drones/OmniDrones/examples
python 00_play_drones.py headless=true steps=100

# 训练 / 回放
cd /home/lz/lzspace/drones/OmniDrones/scripts
python train.py task=Hover algo=ppo headless=true wandb.mode=disabled
python play.py task=Hover algo=ppo checkpoint=/path/to/checkpoint.pt headless=true
```

---

## 9. 参考链接

- 顶层使用说明:[`README.md`](./README.md)
- 一键脚本:[`setup_env.sh`](./setup_env.sh)
- OmniDrones 上游:https://github.com/btx0424/OmniDrones(文档:https://omnidrones.readthedocs.io/)
- 本仓使用的 5.1 fork:https://github.com/tshiamor/OmniDrones(`isaacsim-5.1-blackwell`)
- IsaacLab v2.3.0:https://github.com/isaac-sim/IsaacLab
- Isaac Sim pip 安装:https://pypi.nvidia.com
