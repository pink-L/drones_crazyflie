# wandb 使用与配置指导(OmniDrones / Isaac Sim 5.1)

> 本文档面向 **本仓库** 的 OmniDrones 分支(`isaacsim-5.1-blackwell`),
> 说明如何接入 [Weights & Biases (wandb)](https://wandb.ai) 做实验跟踪:
> 账号登录 → 配置字段 → 开启在线记录 → 查看指标/视频 → checkpoint 上传 → 断点恢复/云端回放。
>
> 配套环境:conda 环境 **`lz_env`**(非 `omnidrones`,见 `Build_drone.md` §0);wandb 0.29.0。

---

## 0. TL;DR(最快上手)

如果你已经有 wandb 账号,只需三步:

```bash
conda activate lz_env

# 1) 登录(浏览器打开给出的链接并粘贴 API Key,只需一次)
wandb login

# 2) 确认登录账号(本机已登录为 lz1470229071,团队 fly-hust)
wandb whoami

# 3) 开训练(本机已将 entity 默认配为团队 fly-hust,直接跑即可在线记录)
cd /home/lz/lzspace/drones/OmniDrones/scripts
python train.py task=Hover algo=ppo headless=true wandb.project=omnidrones
```

跑起来后,控制台会打印 `View run at https://wandb.ai/<entity>/<project>/runs/<run_id>`,
浏览器打开即可看 loss 曲线、rollout 视频和超参数。

---

## 1. 账号与登录

### 1.1 获取 API Key(一次性)

1. 浏览器登录 https://wandb.ai;
2. 右上角头像 → **Settings** → **API Keys** → 生成一个 key(形如 `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`)。

### 1.2 在机器上登录

```bash
conda activate lz_env
wandb login
# 粘贴 API Key 回车;成功后会写入 ~/.netrc
```

也可以不用交互,直接用环境变量(适合无头/CI):

```bash
export WANDB_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx   # 建议写入 ~/.bashrc
```

其它常用环境变量:

| 变量 | 作用 |
|---|---|
| `WANDB_ENTITY` | 默认实体(账户名),不写则用账户默认实体 |
| `WANDB_PROJECT` | 默认项目名 |
| `WANDB_MODE` | `online`(默认)/ `offline` / `disabled` |
| `WANDB_DIR` | 本地写入目录(默认 `./wandb`,训练输出也常落在 `/tmp/wandb`) |

### 1.3 换账号 / 检查状态

```bash
wandb login --relogin      # 换账号重新登录
wandb status               # 查看当前登录状态、默认实体、默认项目
wandb whoami               # 查看当前用户名
```

---

## 2. 项目是如何接入 wandb 的(原理)

本项目用 **Hydra 管配置 + wandb 做跟踪**,链路为:

```
train.py (Hydra 入口)
  └─ cfg:  hydra searchpath = ../cfg, 加载 scripts/train.yaml (内嵌 wandb: 段)
       └─ omni_drones/utils/wandb.py::init_wandb(cfg)
            ├─ 拼 run_name = "{cfg.wandb.run_name}/{MM-DD_HH-MM}"
            ├─ 传 project / group / entity / name / mode / tags 给 wandb.init(...)
            ├─ 未给 run_id  → 自动生成 id(新建 run)
            ├─ 给了 run_id  → id + resume="must"(恢复该 run)
            └─ 把整份 cfg 扁平化后写入 run.config(超参数自动归档)
  ├─ 训练循环中 run.log(info)   # 指标 / 视频 / checkpoint 路径
  └─ 结束:保存 checkpoint_final.pt → 打成 wandb Artifact → wandb.finish()
```

关键代码位置:

| 文件 | 作用 |
|---|---|
| `omni_drones/utils/wandb.py` | `init_wandb()` 统一初始化逻辑 |
| `scripts/train.py` / `train_lidar.py` | 训练入口,`run.log`、保存 checkpoint、`log_artifact` |
| `examples/demo_task.py` | 演示:从 wandb **Artifact 下载**已训练模型并回放 |
| `cfg/*.yaml`、`scripts/*.yaml`、`examples/demo_task.yaml` | wandb 字段声明(Hydra 配置) |

> 算法每个 update 返回的指标(如 PPO 的
> `policy_loss / value_loss / entropy / actor_grad_norm / critic_grad_norm / explained_var`)
> 也会在 `train.py` 里并入 `info`,随 `run.log` 上传。

---

## 3. wandb 配置字段详解

字段都在 Hydra 配置的 `wandb:` 段下(见 §4),也可用命令行覆盖(见 §5)。

| 字段 | 含义 | 说明 / 默认值 |
|---|---|---|
| `entity` | **实体(账户名或团队名)** | 本项目已默认配为团队 `fly-hust`;个人账户为 `lz1470229071`,可随时命令行覆盖 |
| `project` | 项目名 | 默认 `omnidrones`;建议按实验集分项目(如 `omnidrones`, `omnidrones-debug`) |
| `group` | 实验组 | 默认 `${task.name}`,把同任务的不同 run 归组便于对比 |
| `run_name` | run 前缀名 | 默认 `${task.name}-${algo.name}`;实际 run 名 = `{run_name}/{MM-DD_HH-MM}` |
| `job_type` | 任务类型标签 | 默认 `train`(仅作标注) |
| `mode` | 上传模式 | `online`(默认)/ `offline` / `disabled`(本地调试用 disabled) |
| `run_id` | 指定 run id | 空 = 新建;**非空 = 恢复该 id 的 run**(`resume="must"`) |
| `monitor_gym` | 是否监控 gym 渲染 | `True`(当前版本未实际用到,保留) |
| `tags` | 标签列表 | 空(可传 `[debug, ppo, rtx5090]` 之类) |
| `run_path` / `log_code` | 仅 `cfg/debug.yaml` 里有 | 代码自动上传开关等 |

---

## 4. 配置文件入口与默认值差异(注意坑)

项目里有 **4 份** 含 `wandb:` 段的 yaml,入口不同默认值也不同:

| 文件 | 谁在用它 | entity 默认 | project 默认 | algo 默认 |
|---|---|---|---|---|
| `scripts/train.yaml` | `scripts/train.py`、`train_lidar.py`、`play.py`(**日常训练用这份**) | `fly-hust` | `omnidrones` | `ppo` |
| `cfg/train.yaml` | `scripts_paper/train.py` 等(`CONFIG_PATH`→`cfg/` 目录) | `fly-hust` | `omnidrones` | `mappo` |
| `cfg/debug.yaml` | 调试用 | `fly-hust` | `gpu-onpolicy` | `mappo` |
| `examples/demo_task.yaml` | `examples/demo_task.py`(云端回放;示例指向上游公开项目) | `finani`(示例) | `omnidrones-public` | — |

> ✅ **本机已改好**:所有训练入口 yaml 的 `entity` 默认均统一为你的团队 **`fly-hust`**(见上表),
> 直接 `python train.py ...` 即可上传到团队空间。若想改到个人空间,
> 命令行带 `wandb.entity=lz1470229071` 即可,无需改文件。

官方文档建议:"In general, `YOUR_WANDB_ENTITY` is your wandb ID."(你的 wandb 用户名)。

---

## 5. 命令行覆盖(日常用法)

### 5.1 默认值(已配置为本机实际值)

本机已把各训练入口 yaml 的 `entity` 默认设为团队 `fly-hust`。如需调整,编辑
`OmniDrones/scripts/train.yaml`:

```yaml
wandb:
  ...
  entity: fly-hust       # ← 可改为 lz1470229071(个人)或其它团队
  project: omnidrones
```

### 5.2 不改文件,每次用 Hydra 覆盖

```bash
cd /home/lz/lzspace/drones/OmniDrones/scripts

# 在线记录(默认已配 entity=fly-hust;切个人空间时覆盖即可)
python train.py task=Hover algo=ppo headless=true
python train.py task=Hover algo=ppo headless=true wandb.entity=lz1470229071

# 自定义 run 组 / 标签 / 项目
python train.py task=Track algo=ppo headless=true \
    wandb.project=omnidrones wandb.group=track-sweep wandb.tags=[ppofinal,rtx5090]

# 本地调试:不开网络上传(metrics/视频/checkpoint 落在本地 /tmp/wandb)
python train.py task=Hover algo=ppo headless=true \
    wandb.mode=disabled max_iters=1
```

> 想长期保存结果的正式训练建议一次给足
> `total_frames=1_000_000 save_interval=100000 eval_interval=…`,配合在线 wandb 按帧自动存点。

---

## 6. 训练时 wandb 会记录什么

在线跑一次 `train.py` 后,在 wandb 页面你会看到:

**系统 / 配置区**
- `Overview`:`run_id`、run 名、`job_type=group`、标签、起止时间、硬件信息(GPU/显存等)。
- `Config`:整份 Hydra cfg(含 task、algo、sim、env 全部超参)。

**训练曲线(`train/…` + 算法指标,按 iter 滚动)**
- `env_frames`、`rollout_fps`(采集帧数与吞吐)。
- `train/…`:EpisodeStats 统计(各任务自带的 reward/进度等统计量)。
- 算法指标(PPO):`policy_loss`、`value_loss`、`entropy`、`actor_grad_norm`、`critic_grad_norm`、`explained_var`(其他算法见 `omni_drones/learning/*`)。

**评估 / 视频(每 `eval_interval` 触发一次)**
- `eval/stats.*`:一次完整 rollout 的评估指标。
- `recording`:把 Eval 渲染保存成 **mp4 视频**(`wandb.Video`,fps 由 `sim.dt * sim.substeps` 决定),直接在页面里播放,方便看策略行为。

**Artifacts(训练结束)**
- `wandb.Artifact(name=f"{task}-{algo}", type="model")`,内含 `checkpoint_final.pt`,metadata 记录了整套 cfg → 可 `examples/demo_task.py` 一键云端回放(见 §8)。

---

## 7. 断点续训(恢复某个 run)

`init_wandb` 支持通过 `run_id` **恢复**既有 run(同一 id 续写同一份曲线):

1. 从 wandb 页面 Overview 复制该 run 的 id(如 `gptmuz5h`,也见 URL `runs/<id>`);
2. 覆盖运行:

```bash
python train.py task=Hover algo=ppo headless=true \
    wandb.entity=fly-hust wandb.project=omnidrones \
    wandb.run_id=gptmuz5h        # → init_wandb 会 resume="must"
```

> 注意:代码在 `run.dir` 下按 `checkpoint_{frames}.pt` 存点,恢复训练请自行处理加载
> 上一份 checkpoint(`torch.load` + `policy.load_state_dict`),wandb 只负责把曲线续在同一 run 下。

---

## 8. 从云端 Artifact 下载模型并回放

`examples/demo_task.py` 演示了**直接从 wandb Artifact 下载权重**跑评估/回放:

1. 先确保训练 run 结束时成功 `log_artifact`(即 wandb 页面的 Artifacts 里有
   `{task}-{algo}` 且带版本号);
2. 配置 `examples/demo_task.yaml`:

```yaml
wandb:
  entity: fly-hust
  project: omnidrones
  artifact_name: Hover-ppo       # 与训练时 Artifact name 一致
  artifact_version: latest       # 或具体版本,如 v0
```

3. 运行:

```bash
cd /home/lz/lzspace/drones/OmniDrones/examples
python demo_task.py task=Hover algo=ppo headless=true
# 或带 GPU 界面:
python demo_task.py task=Hover algo=ppo headless=false
```

脚本内部 `run.use_artifact(f"{entity}/{project}/{artifact_name}:{artifact_version}")`
会把权重下载到本地 `artifacts/` 目录再加载。

> 若你只想离线回放本地 checkpoint(不联网),用 `scripts/play.py`:
> `python play.py task=Hover algo=ppo checkpoint=/path/to/checkpoint_final.pt headless=true`。

---

## 9. 本地调试:offline / disabled 模式

| mode | 行为 | 适用 |
|---|---|---|
| `offline` | 记录到本地 `wandb/` 目录,之后可 `wandb sync` 一次性上传 | 断网训练后补传 |
| `disabled` | 完全不记录,`run.dir` 落在 `/tmp/wandb/run-*/files` | 快速验证/冒烟 |

```bash
# offline:数据先落本地
python train.py task=Hover algo=ppo headless=true wandb.mode=offline \
    wandb.entity=fly-hust wandb.project=omnidrones
# 之后联网补传
wandb sync --include-globs "**/*" ./wandb/offline-run-*
```

> 注意 `mode=disabled` 时 checkpoint 会存到 **`/tmp/wandb/run-*/files/`**(重启即清空),
> 若想留存请及时拷贝,或直接开 online/offline。

---

## 10. 常见问题(含本机已修复项)

### 10.1 `AttributeError: module 'wandb.util' has no attribute 'generate_id'`
- 本机 wandb 0.29.0 已移除旧 API;本 fork 已在 `omni_drones/utils/wandb.py` 顶部做兼容导入:
  ```python
  try:
      from wandb.sdk.lib.runid import generate_id as _generate_id
  except ImportError:          # 旧版 wandb
      from wandb.util import generate_id as _generate_id
  ```
- 若仍报错,确认 import 的是上面这个文件(而非被覆盖的旧版本)。

### 10.2 `mode=disabled` 下 `RuntimeError: Parent directory …/files does not exist`
- 旧版训练在 `torch.save` 前没建目录;`scripts/train.py` / `train_lidar.py` 两处
  已加 `os.makedirs(os.path.dirname(ckpt_path), exist_ok=True)`。若改过脚本,记得保留。

### 10.3 上传失败 / 跑到别人的项目下
- 用 `wandb whoami` 确认已登录账号(本机:`lz1470229071` / 团队 `fly-hust`);
- 本项目默认 entity 已设为 `fly-hust`;若提示无权限/想传个人空间,换 `wandb.entity=lz1470229071`。

### 10.4 无网 / 受限网络(公司代理、GitHub 都连不上的那种)
- 用 `wandb.mode=offline` 训练,事后 `wandb sync`;
- 或临时 `export WANDB_MODE=offline`。

### 10.5 视频/上传很慢
- Eval 视频为 mp4 全量渲染(500 帧),属正常;可加大 `eval_interval` 减少上传频率。

---

## 11. 相关文件参考

- 本文档:仓库根 `/home/lz/lzspace/drones/wandb_config.md`
- 代码逻辑:`OmniDrones/omni_drones/utils/wandb.py`
- 训练入口(记录/存点/artifact):`OmniDrones/scripts/train.py`、`OmniDrones/scripts/train_lidar.py`
- 云端回放示例:`OmniDrones/examples/demo_task.py` + `examples/demo_task.yaml`
- 配置模板:`OmniDrones/scripts/train.yaml`、`OmniDrones/cfg/train.yaml`、`OmniDrones/cfg/debug.yaml`
- 官方文档:https://docs.wandb.ai  /  Hydra 配置系统:https://hydra.cc
