---
name: drones-crazyflie-context
description: 用于修改本 drones workspace 的 OmniDrones、NavVel、Crazyflie、障碍/CBF、PPO/RL 或训练评估代码时，提供经本地代码确认的架构、入口、配置、数据流和验证路径。
metadata:
  short-description: Project-specific architecture and validation map
---

# Drones Crazyflie context

Use this project-only context before changing OmniDrones, NavVel, Crazyflie
flight/control behavior, obstacles, collision logic, CBF, PPO/RL behavior,
reward/observation/action, or training/evaluation. It records facts that affect
implementation decisions; it is not a Python, Torch, or Isaac Sim tutorial.

First establish the boundary from the live repository: the workspace is
`/home/lz/lzspace/drones`, while `OmniDrones/` is a nested Git repository and
the outer `.gitmodules` declares it as a submodule. Check both Git states and
do not change the outer submodule pointer accidentally.

Use progressive disclosure. Read only the reference that matches the task:

- [architecture.md](references/architecture.md) for module ownership and the
  policy-to-simulator call/data flow;
- [navvel.md](references/navvel.md) for NavVel observations, actions, reward,
  termination, obstacle/CBF/curriculum behavior, and feature-to-file routing;
- [training-and-evaluation.md](references/training-and-evaluation.md) for
  Hydra composition, train/eval entry points, checkpoint/seed semantics, and
  safe lightweight commands;
- [testing.md](references/testing.md) for the repository's actual validation
  layers and test scripts.

When docs and code disagree, prefer executable code/configuration and record
the discrepancy. Before editing a core layer, identify its upstream input,
downstream consumer, config keys, tensor shape/device contract, and the lowest
cost check that can observe the change.
