---
name: tdd
description: 用于 drones 项目中可自动验证的 Python/Torch 行为修改：障碍几何、CBF 数学、课程、reward/observation/action 变换和 tensor 工具；按风险选择 CPU、集成、Isaac smoke 或回归层级。
metadata:
  short-description: Build test-first coverage at the cheapest useful layer
---

# TDD

Use test-first development when changing behavior that can be observed
deterministically. This is especially appropriate for pure Python/Torch code,
obstacle geometry, CBF math, curriculum logic, reward helpers, state
transformations, and tensor utilities.

This skill is adapted from the MIT-licensed `test-driven-development` skill in
OpenAI's public `openai/plugins` repository; the local `LICENSE` is retained.

## Choose the cheapest meaningful level

1. **Level 1 — CPU unit test:** pure Torch/Python with no Isaac import. Start
   with `obstacle_geometry_test.py`, `cbf_test.py`,
   `cylinder_geometry_test.py`, or `pillar_geometry_test.py` when the changed
   contract is theirs.
2. **Level 2 — targeted integration:** exercise config composition, transform
   wiring, or a small module boundary while keeping the fixture lightweight.
3. **Level 3 — Isaac Sim smoke:** use a small headless environment/step count
   when the changed behavior depends on prims, physics, reset, or controller
   integration. Do not pretend a CPU test covers this boundary.
4. **Level 4 — short training/evaluation regression:** compare fixed seed,
   profile, checkpoint, action/filter mode, and the relevant metrics for a
   short run.
5. **Level 5 — full training experiment:** reserve for an explicitly requested
   experiment or an acceptance criterion that cannot be observed earlier.

Do not impose strict unit TDD on all Isaac Sim behavior. Apply the strongest
test-first loop that is practical for the selected level and document the
uncovered simulator boundary.

## Red → Green → Refactor

1. Define one behavior/invariant and the smallest observable assertion.
2. Write the test before changing production code when feasible.
3. Run it and confirm a meaningful **RED** failure caused by the missing or
   wrong behavior, not a typo, import error, or bad fixture.
4. Implement the smallest coherent **GREEN** change; keep one variable under
   test and do not bundle cleanup.
5. Run the focused test, then the nearest regression checks. Only after green,
   refactor without changing behavior.

For existing bugs, a regression test should fail against the old behavior when
the bug can be reproduced safely. If that is impossible (for example, a long
or nondeterministic Isaac failure), capture the baseline command and evidence,
then state why the red phase was observational rather than automated.

Use real behavior and deterministic fixtures. Avoid asserting private
implementation details or mocking the boundary being tested; control seeds,
device, dtype, time, and external services explicitly. Read
[writing-good-tests.md](references/writing-good-tests.md) when designing a new
test.

## Project commands

From `OmniDrones/` (CPU-oriented, no Isaac startup):

```bash
python scripts/obstacle_geometry_test.py
python scripts/cbf_test.py
python scripts/cylinder_geometry_test.py
python scripts/pillar_geometry_test.py
python scripts/arena1_layout_check.py 256 0.25
```

Use `python scripts/test_clearance_conventions.py` for clearance-definition
changes. For training/evaluation, first read the context references and use
small `task.env.num_envs`, `+rollout_steps`, `headless=true`, and a fixed
seed/profile; never infer success from process exit alone—check the emitted
metrics.

## Evidence to report

State the selected level, the RED result or baseline evidence, focused and
broader commands, observed results, and what remains untested. Keep test
fixtures and generated outputs out of the source/submodule unless the task
explicitly requires them.
