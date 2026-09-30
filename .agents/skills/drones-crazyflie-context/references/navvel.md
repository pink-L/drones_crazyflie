# NavVel task context

Authoritative implementation: `OmniDrones/omni_drones/envs/single/nav_vel.py`.
Authoritative default task config: `OmniDrones/cfg/task/NavVel.yaml`.

## Current default contract

- Environment name: `NavVel`; one Crazyflie agent.
- Sim timestep: `0.01` s; default `num_envs=1024`,
  `max_episode_length=1000` in `NavVel.yaml` (frozen profile files may use
  different values, such as 1500).
- Training start/goal sampling defaults to `episode_sampler=edge`: start at
  the negative-x edge band and target at the positive-x edge band. Explicit
  `fixed_init`/`fixed_target` take precedence and are normally evaluation
  overrides.
- Room bounds are the circular `bound_xy` check plus optional box
  `arena_bound=[3,3]`; z must stay between `z_min` and `z_max=3.0` in the
  current default task.
- Default action transform is `velocity`; action is `[vx, vy, vz, yaw]` before
  the transform. `vel_limit` defaults to 1.8 m/s and 1.5 rad/s.

## Observation and info

`_set_specs()` exposes `agents.observation`, `agents.intrinsics`, and
`agents.action`. With the default sphere-stack world (`max_slots=8`, 4 values
per obstacle slot, time encoding enabled), the documented observation width is
62. The analytic-cylinder path uses a 7-value slot
`[relative position, SDF, normal]`; cylinder profiles may therefore use a
different width (for example 58 at `K=4`). The checkpoint must match the exact
layout/shape.

The observation is built from:

1. target-relative position;
2. drone state excluding absolute position;
3. target-heading relative to drone heading;
4. optional four-value normalized time encoding;
5. obstacle block from `ObstacleManager.build_obs()`;
6. optional `obs_safety` clearance/CBF-margin channels.

`info` includes `drone_state`, `prev_action`, `policy_action`, and when CBF is
enabled all-`M` `obstacle_cbf` entries `[center_xyz, r_cbf]`. The policy
observation may contain only the nearest `K` window; CBF, collision, and reward
logic use the full active scene geometry. Keep this distinction when debugging
“seen but not filtered” or “filtered but not observed” behavior.

## Obstacle system

`ObstacleManager` is pure Torch and deliberately has no Isaac dependency.
Sphere-stack geometry uses logical radius
`r_safe = obstacle_radius + drone_radius + inflation`; surface clearance is
center distance minus `r_safe`. Collision and danger thresholds are controlled
by `collision_margin` and `danger_radius`. Layout sampling enforces start/goal
clearance and inter-obstacle gap, with keepout and fallback/relaxation rules.

The alternative `shape=cylinder` path represents each pillar as a finite
vertical cylinder and uses one shared SDF for observation, collision/reward,
and CBF geometry. A virtual-sphere adapter in `cbf_geom()` lets the frozen CBF
projection reuse the same SDF normal without a second projection algorithm.

## Reward and termination

`reward_scheme` selects `legacy`, `navgoal`, `r1`, or `f1`. Shared terms include
arrival/hold logic, optional PBRS, action smoothness, obstacle log/edge/near-
slowdown terms, and optional time/failure terms. CBF modes are `none`,
`filter_only`, `reward_only`, and `hybrid`; `penalty_src` changes whether the
reward core uses nominal violation, correction, Gaussian correction, or dual.
The reward-core violation must use the pre-filter policy action.

Termination observes crash/NaN, box/circular OOB, collision-exceed, timeout,
and optional success termination. `soft_respawn=false` is strict single-life;
`single_episode_per_window=true` additionally freezes an ended env for a rollout.
Metrics and `term_cause` are stateful—compare identical episode semantics before
comparing experiment numbers.

## Curriculum

`ObstacleCurriculum` is updated when completed episodes reset during training.
The active global level advances only after the configured rolling success and
collision gates, minimum frame spacing, and optional margin gate. Cylinder
profiles are locked-density paths; the curriculum level is inert there.

## Feature → likely files

| Change | Inspect first | Then check |
|---|---|---|
| Obstacle placement/shape | `nav_vel_obstacles.py`, `NavVel.yaml` | `NavVel._reset_idx`, physical prim setup, obs window, `obstacle_geometry_test.py`/cylinder tests |
| Collision semantics | `ObstacleManager.clearances/shape_sdf_normal`, `NavVel._compute_reward_and_done` | `collision_margin`, edge counters, `soft_respawn`, `term_cause`, layout tests |
| CBF behavior | `utils/cbf.py`, `NavVel.cbf_geom`/info wiring | `train.py`/`eval_ckpt.py` transform order, `cbf_test.py`, h-min/correction metrics |
| Observation | `NavVel._set_specs/_compute_state_and_obs`, `ObstacleManager.build_obs` | checkpoint input width, normalization, top-k/all-`M` distinction |
| Reward | `NavVel._compute_reward_and_done`, `NavVel.yaml` | stats term keys, episode semantics, reward sign and pre/post-filter action |
| Curriculum | `utils/nav_curriculum.py`, `NavVel._reset_idx` | rolling window, promotion gates, active level and layout count |
| Velocity control | `transforms.py:VelController`, `lee_position_controller.py` | action units/limits, drone state shape, controller sync under DR |
| Crazyflie model | `robots/drone/crazyflie.py`, `robots/assets/usd/crazyflie.yaml` | USD asset, mass/inertia/KF/KM, rotor time constant and controller config |
| PPO/network/checkpoint | `learning/ppo/ppo.py`, `learning/__init__.py` | observation width, `algo/ppo` config, state dict compatibility |
