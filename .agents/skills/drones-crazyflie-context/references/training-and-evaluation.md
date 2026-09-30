# Training and evaluation

The live entry scripts are `OmniDrones/scripts/train.py` and
`OmniDrones/scripts/eval_ckpt.py`. Both use Hydra with `config_path="."` and
`config_name="train"`, so run them from `OmniDrones/scripts/` (or use an
equivalent working directory that makes that config path resolve).

## Hydra composition

`cfg/train.yaml` composes:

```text
task: Hover by default, override with task=NavVel or task=<self-contained profile>
algo: mappo by default, override with algo=ppo
_self_
```

`cfg/task/NavVel.yaml` composes `base/env_base.yaml` and `base/sim_base.yaml`.
Frozen files under `cfg/profiles/` are self-contained task snapshots; use them
when an experiment requires historical geometry/config compatibility. Never
assume that a current default `NavVel.yaml` is compatible with an old checkpoint.

## Training

The entry flow is:

1. resolve Hydra/OmegaConf and start Isaac with `init_simulation_app`;
2. instantiate `IsaacEnv.REGISTRY[cfg.task.name]`;
3. add `InitTracker`, optional observation raveling, and the configured action
   transforms;
4. create `ALGOS[cfg.algo.name.lower()]` (PPO is
   `omni_drones.learning.ppo.PPOPolicy`);
5. collect batches, run `policy.train_op`, log W&B, and save checkpoints.

Safe command shape for an explicitly requested short run:

```bash
cd /home/lz/lzspace/drones/OmniDrones/scripts
python train.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
  max_iters=1 task.env.num_envs=8
```

This still starts Isaac and may require the configured CUDA/Isaac environment;
it is a smoke shape, not a guaranteed CPU command. Set `total_frames` or
`max_iters` deliberately—do not inherit the 250M-frame default accidentally.

## Evaluation/checkpoint loading

`eval_ckpt.py` constructs the same environment/action chain, creates PPO, checks
the expected observation width against 2-D checkpoint layer widths, and loads
the state dict. It runs deterministic `MODE` rollout and prints an
`[eval_metrics]` JSON record plus diagnostics.

Minimal command shape when a matching checkpoint exists:

```bash
cd /home/lz/lzspace/drones/OmniDrones/scripts
python eval_ckpt.py task=NavVel algo=ppo headless=true wandb.mode=disabled \
  +checkpoint=/absolute/path/checkpoint_final.pt +rollout_steps=100 \
  +runtime_filter=true +set_seed=1000
```

For strict fixed-point acceptance, use matching checkpoint/profile geometry and
explicit overrides such as `task.fixed_init`, `task.fixed_target`,
`task.soft_respawn=false`, `task.obstacle.max_collisions=1`, and
`task.curriculum.enabled=false`. To compare filter dependence, run identical
seed/distribution with `+runtime_filter=true` and `false`; the latter uses a
shadow filter for diagnostics when CBF is configured, so the action is passed
through while hypothetical intervention is measured.

`scripts/acceptance_eval.py` is the batch wrapper. It sets `set_seed=1000+seed`,
uses fixed points, and writes logs under its requested output directory; it
expects an existing checkpoint and a CUDA-capable environment.

## Seed, output, and compatibility rules

- Training calls `env.set_seed(cfg.seed)` after transform construction.
- Evaluation's `+set_seed` explicitly seeds Torch, Python `random`, and NumPy
  for comparable layouts/DR; `seed` also appears in emitted reports.
- Training writes through W&B run directories, including
  `checkpoint_<frames>.pt` and `checkpoint_final.pt`; `wandb.mode=disabled`
  keeps local debugging from uploading.
- Observation layout, obstacle shape/slot width, action transform, and relevant
  task geometry are checkpoint contracts. Cylinder (for example 58-wide) and
  sphere-stack (default 62-wide) checkpoints are not interchangeable.
- `headless=true` suppresses the viewer but does not remove Isaac/CUDA
  requirements. `render_eval=false` is useful for short training-side eval.

## Resource-aware verification

Rollout tensors are accumulated by the evaluation path. Start with low
`task.env.num_envs` and `+rollout_steps`; the acceptance script documents that
large 1024×1500 runs can OOM on the target GPU. Check emitted metrics, layout
fingerprints, and profile/seed before comparing results.
