# OmniDrones - Isaac Sim 5.1 + RTX 5090 (Blackwell)

Reinforcement learning platform for multi-rotor drone simulation, ported to Isaac Sim 5.1 with Blackwell (SM_120) GPU support.

## System Requirements

| Component | Version |
|---|---|
| GPU | NVIDIA RTX 5090 (or Blackwell arch) |
| Driver | 580+ |
| CUDA | 12.8+ (via PyTorch wheels) |
| OS | Linux x86_64 |
| conda | miniforge / miniconda |

## Quick Start

```bash
# Activate the environment
conda activate omnidrones

# Run the basic drone flight demo
cd ~/drones/OmniDrones/examples
python 00_play_drones.py headless=true steps=100
```

## Installed Stack

| Package | Version | Notes |
|---|---|---|
| Python | 3.11 | Required by Isaac Sim 5.1 |
| Isaac Sim | 5.1.0 | pip-installed |
| PyTorch | 2.7.0+cu128 | CUDA 12.8 for SM_120 |
| torchrl | 0.11.1 | RL library |
| IsaacLab | v2.3.0 | Isaac Sim extensions |
| OmniDrones | 0.1.1 | Patched for 5.1 compat |

## Examples

All examples are in `OmniDrones/examples/`. Activate the env first:

```bash
conda activate omnidrones
cd ~/drones/OmniDrones/examples
```

### Drone Flight Demo

Spawns 4 Hummingbird drones flying a circular trajectory:

```bash
python 00_play_drones.py headless=true steps=500
```

Override the drone model or controller:

```bash
python 00_play_drones.py headless=true drone_model.name=Crazyflie drone_model.controller=LeePositionController
```

### Drones with Cameras

Spawns drones with onboard camera sensors:

```bash
python 01_drones_with_cams.py headless=true
```

### Downwash Simulation

Demonstrates multi-drone downwash effects:

```bash
python demo_downwash.py headless=true
```

### Task Demo

Runs a single RL task environment (Hover by default):

```bash
python demo_task.py headless=true
```

### Transport Demo

Multi-drone cooperative transport:

```bash
python demo_transport.py headless=true
```

### Controller Tests

Test the attitude and rate controllers:

```bash
python test_att_controller.py headless=true
python test_rate_controller.py headless=true
```

### Dragon Drone

Test the articulated Dragon drone:

```bash
python test_dragon.py headless=true
```

## Training

Training scripts are in `OmniDrones/scripts/`. They use [Hydra](https://hydra.cc/) for config and [W&B](https://wandb.ai/) for logging.

```bash
conda activate omnidrones
cd ~/drones/OmniDrones/scripts
```

### Train a Policy

```bash
# Train PPO on the Hover task (headless)
python train.py task=Hover algo=ppo headless=true wandb.mode=disabled

# Train on a different task
python train.py task=Track algo=ppo headless=true wandb.mode=disabled

# Train with W&B logging
python train.py task=Hover algo=ppo headless=true wandb.entity=YOUR_ENTITY
```

### Available Tasks

**Single-agent:** Hover, Track, FlyThrough, PayloadHover, PayloadTrack, PayloadFlyThrough, InvPendulumHover, InvPendulumTrack, InvPendulumFlyThrough, Forest, Pinball

**Multi-agent:** PlatformHover, PlatformTrack, PlatformFlyThrough, TransportHover, TransportTrack, TransportFlyThrough, Formation

### Available Algorithms

`ppo`, `sac`, `td3`, `mappo`, `matd3`, `qmix`, `dqn`

### Play a Trained Policy

```bash
python play.py task=Hover algo=ppo checkpoint=/path/to/checkpoint.pt headless=true
```

### Train with LiDAR

```bash
python train_lidar.py task=Forest algo=ppo headless=true wandb.mode=disabled
```

## Common Options

All scripts accept Hydra overrides:

| Option | Description | Default |
|---|---|---|
| `headless=true/false` | Run without GUI | `true` for training |
| `steps=N` | Number of simulation steps (examples) | `1000` |
| `sim.dt=0.016` | Physics timestep | `0.016` |
| `sim.device=cuda:0` | Compute device | `cuda:0` |
| `task=TaskName` | RL task to run | `Hover` |
| `algo=name` | RL algorithm | `ppo` |
| `wandb.mode=disabled` | Disable W&B logging | `online` |
| `total_frames=N` | Total training frames | `150000000` |

## Project Layout

```
~/drones/
├── README.md               # This file
├── setup_env.sh            # Environment setup script
├── IsaacLab/               # Isaac Lab v2.3.0
└── OmniDrones/
    ├── examples/           # Demo scripts
    ├── scripts/            # Training scripts
    ├── cfg/                # Hydra task/algo configs
    ├── omni_drones/
    │   ├── envs/           # RL environments (tasks)
    │   ├── robots/         # Drone models (Hummingbird, Crazyflie, etc.)
    │   ├── learning/       # RL algorithms (PPO, SAC, MAPPO, etc.)
    │   ├── actuators/      # Rotor dynamics
    │   ├── controllers/    # PID / Lee controllers
    │   ├── sensors/        # Camera, LiDAR configs
    │   ├── views/          # Isaac Sim prim views (patched for 5.1)
    │   └── utils/
    │       ├── torchrl/    # torchrl wrappers + compat shim
    │       └── tensordict_compat.py  # make_functional replacement
    └── setup.py
```

## Troubleshooting

**First run is slow:** Isaac Sim compiles shader cache on first launch. Subsequent runs are faster.

**PyTorch SM_120 warning:** If you see "not compatible with the current PyTorch installation", the cu128 wheels were overwritten. Reinstall:
```bash
pip install --force-reinstall torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 \
    --index-url https://download.pytorch.org/whl/cu128
pip install numpy==1.26.0 filelock==3.13.1 fsspec==2024.6.1 markupsafe==2.1.3 \
    networkx==3.3 sympy==1.13.3 Pillow==11.3.0 typing_extensions==4.12.2
```

**Deprecation warnings from `omni.isaac.core`:** These are expected. Isaac Sim 5.1 ships backward-compatible shims that print warnings. They do not affect functionality.
