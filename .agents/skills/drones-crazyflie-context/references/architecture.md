# Architecture and live data flow

This map is based on the current files under `OmniDrones/`, not only on
`project_summary.md`. Line numbers are anchors for the inspected revision and
should be rechecked after source changes.

## Repository boundary

- Workspace root: `/home/lz/lzspace/drones` (outer Git branch `main`).
- `OmniDrones/` is a nested Git repository recorded by the outer
  [`.gitmodules`](../../../../.gitmodules) as
  `git@github.com:pink-L/Omnidrones_crazyflight_obs.git`, branch
  `isaacsim-5.1-blackwell`.
- The nested checkout has its own branch/history and working-tree changes.
  Always run `git status --short` at both roots; a dirty nested checkout is not
  evidence that the outer pointer should be changed.

## Package and entry modules

`OmniDrones/setup.py` installs the `omni_drones` package. The simulator
environment registry is defined in `omni_drones/envs/isaac_env.py`; importing
`omni_drones.envs.single` registers `NavVel` from
`omni_drones/envs/single/nav_vel.py`.

| Layer | Live path | Important symbols | Responsibility |
|---|---|---|---|
| Hydra train entry | `scripts/train.py` | `main`, `ALGOS` lookup | Starts Isaac app, builds env/transforms/policy/collector, updates PPO, logs W&B, saves checkpoints |
| Hydra eval entry | `scripts/eval_ckpt.py` | `main`, `_AcceptanceCb` | Builds deterministic rollout, loads checkpoint, optionally filters/shadows CBF, emits metrics/diagnostics |
| Task environment | `omni_drones/envs/single/nav_vel.py` | `NavVel`, `_pre_sim_step`, `_compute_state_and_obs`, `_compute_reward_and_done` | Owns target/reset, observation, reward, termination, episode stats, obstacle/CBF inputs |
| Obstacle geometry | `omni_drones/envs/single/nav_vel_obstacles.py` | `ObstacleManager`, `scene_slot_count`, `sphere_sdf_and_normal`, `cylinder_sdf_and_normal` | Pure Torch layout, active masks, clearances, observation window, geometry-to-CBF adapter |
| CBF layer | `omni_drones/utils/cbf.py` | `filter_velocity`, `cbf_violation`, `CBFVelocityFilter`, `build_cbf_filter` | Projects velocity commands, computes reward-core violation and diagnostics |
| Curriculum | `omni_drones/utils/nav_curriculum.py` | `ObstacleCurriculum` | Global density level promoted by rolling success/collision/margin gates |
| Action transforms | `omni_drones/utils/torchrl/transforms.py` | `VelController`, `PIDRateController` | Converts policy action to controller input and then rotor command |
| Position/attitude control | `omni_drones/controllers/lee_position_controller.py` | `LeePositionController`, `AttitudeController`, `RateController`, `PIDRateController` | Converts desired velocity/attitude/rate to four rotor commands |
| Robot base | `omni_drones/robots/drone/multirotor.py` | `MultirotorBase` | Loads state, rotor actuator, physics views, dynamics/randomization |
| Crazyflie model | `omni_drones/robots/drone/crazyflie.py`, `robots/assets/usd/crazyflie.yaml` | `Crazyflie` | USD asset and model parameters; current YAML includes 4 rotors and a 0.05 s motor time constant |
| PPO | `omni_drones/learning/ppo/ppo.py` | `PPOPolicy`, `Actor`, `make_batch` | Lazy MLP actor/critic, GAE, PPO update, optimizer/checkpoint state |

## Policy-to-simulator action path

For `task.action_transform=velocity`, `scripts/train.py` and
`scripts/eval_ckpt.py` create the same high-level chain:

```text
PPO policy action [vx, vy, vz, yaw]
  -> CBFVelocityFilter (optional; operates on xyz, preserves yaw)
  -> CmdGaussNoise (train only, optional)
  -> VelController (speed/yaw limits)
  -> LeePositionController.compute()
  -> MultirotorBase.apply_action()
  -> rotor actuator / Isaac physics
```

TorchRL inverse transforms execute in reverse append order. Therefore the CBF
transform is appended after `VelController` so it executes before it. The
environment writes `info.drone_state`, `info.obstacle_cbf`, and action tracking
keys; do not change a key or shape without checking both the transform and
`NavVel._set_specs()`.

`PIDrate` is a separate path: policy CTBR action → `PIDRateController` transform
→ firmware-style rate PID/mixer → rotors. Do not mix velocity-action and
CTBR/PIDrate assumptions in one experiment.

## NavVel state path

`NavVel.__init__` parses `task.obstacle`, `task.curriculum`, velocity limits,
and CBF settings before `IsaacEnv.__init__` constructs the scene/specs. On reset
it samples start/goal, samples an obstacle layout, commits it to
`ObstacleManager`, moves the physical views, and resets episode counters.

Each step:

1. `_pre_sim_step()` receives the transformed action and applies it to the
   drone; it also captures `info.prev_action` and the pre-filter policy action.
2. `_compute_state_and_obs()` reads `drone.get_state()`, builds target-relative
   state plus time encoding and obstacle observation, and publishes all-`M`
   CBF geometry through `info.obstacle_cbf` when enabled.
3. `_compute_reward_and_done()` computes reward terms, collision-edge and
   curriculum bookkeeping, CBF reward core, crash/OOB/collision termination,
   and `stats` metrics.

The same environment object is used by training and evaluation; differences in
filter execution, seeds, fixed points, and rollout instrumentation come from
the entry script/CLI overrides.
