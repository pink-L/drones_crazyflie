# Testing and validation map

There is no top-level `OmniDrones/tests/` suite in the inspected checkout. The
project's high-signal validation is primarily executable scripts under
`OmniDrones/scripts/`; several load pure Torch modules directly so Isaac is not
required.

Run commands from `/home/lz/lzspace/drones/OmniDrones` with the project's Python
environment. Before treating a command as a regression result, check its
header/arguments and the exit code.

## Levels

### Level 1 — pure Python/Torch CPU

Use for geometry, CBF, curriculum, reward helpers, and tensor contracts:

```bash
python scripts/obstacle_geometry_test.py
python scripts/cbf_test.py
python scripts/cylinder_geometry_test.py
python scripts/pillar_geometry_test.py
python scripts/test_clearance_conventions.py
```

Related layout gates:

```bash
python scripts/cylinder_layout_check.py --n 8 --radius 0.4243 --corridor-clearance 1.34
python scripts/pillar_layout_check.py
```

The exact profile/config used by layout checks matters. `arena1_layout_check.py`
reads `cfg/task/NavVel.yaml` and should be treated as a config-specific gate;
inspect its required fixed start/goal values before invoking it against a
profile with null `fixed_init`/`fixed_target`.

### Level 2 — targeted integration/static checks

For changed Python modules, first run:

```bash
python -m py_compile path/to/changed.py
```

Then exercise the smallest config/transform boundary that imports the changed
module. Use `scripts/cbf_hmin_diag.py` or the relevant geometry/layout checker
only when its CLI and profile match the change.

### Level 3 — small Isaac Sim smoke

Use `scripts/train.py` or a task demo with `headless=true`, very small
`task.env.num_envs`, and a bounded `max_iters`/step count. This requires Isaac
Sim, CUDA, and the project environment; a CPU-only environment cannot validate
the physics/controller boundary.

### Level 4 — short training/evaluation regression

Use a fixed profile/checkpoint/seed, low `task.env.num_envs`, and low
`+rollout_steps`. Compare the metric relevant to the change: arrival/success,
collision edges, OOB/crash, minimum clearance, CBF h-min/correction, reward
terms, or action smoothness. Keep filter ON/OFF and episode semantics identical
when comparing arms.

### Level 5 — full experiment

Run only when explicitly requested or required by acceptance criteria. Record
the exact profile, checkpoint lineage, seed set, GPU, W&B/output location, and
resource budget.

## Change-to-check routing

| Changed area | First check | Follow-up |
|---|---|---|
| Sphere/cylinder geometry or layout | obstacle/cylinder/pillar geometry test | matching layout gate, then Isaac smoke if prim wiring changed |
| CBF math/config/filter order | `scripts/cbf_test.py` | short ON/OFF rollout with h-min/correction metrics |
| Curriculum | `scripts/obstacle_geometry_test.py` | short training reset/promotion observation |
| Reward/termination | targeted pure helper test or a deterministic regression | short eval with the same episode semantics |
| Observation/action shape | static spec inspection and checkpoint-width guard | matching checkpoint smoke/eval |
| Controller/robot/physics | compile and pure controller test where possible | small headless Isaac smoke, then short eval |
| PPO/learning | policy/module unit test if feasible | short training/eval; full experiment only for final behavior |

Do not call a full training run “validation” when only a process started. Report
the actual command, exit code, metrics, and any environment/GPU limitation.
