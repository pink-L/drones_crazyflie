---
name: implementation-workflow
description: 用于 drones 仓库中中大型功能或行为变更：先分析架构与修改面，再分步实现、定向验证、回归检查并汇报证据；不适用于仅解释或仅审查请求。
metadata:
  short-description: Drive medium and large changes through verification
---

# Implementation workflow

Use this skill for multi-file changes, behavior changes, and changes that cross
NavVel, obstacles, CBF, controllers, robots, learning, or training/evaluation.
For a one-line/local typo, use the smallest direct workflow instead.

This skill is adapted from the MIT-licensed `engineering-loop` skill in
`Phelan164/codex-howto` (source: https://github.com/Phelan164/codex-howto,
`skills/engineering-loop/`); the local `LICENSE` is retained.

## Required loop

1. **Requirement** — state the requested behavior, non-goals, acceptance
   criteria, and constraints. Preserve unrelated user changes.
2. **Architecture** — read the repository-local onboarding/context skill when
   the task touches OmniDrones. Confirm whether a path belongs to the outer
   repository or the nested `OmniDrones` submodule. Trace the live call path
   and configuration, not only project summaries.
3. **Change surface** — list the files, symbols, configs, tests, checkpoints,
   and metrics that may change. Separate pure Python/Torch work from Isaac Sim
   work and from expensive training/evaluation.
4. **Design** — choose the smallest coherent design and write down invariants
   that must stay true (tensor shapes/devices, action ordering, geometry
   convention, seed/config compatibility).
5. **Incremental implementation** — make one bounded change at a time. Keep
   the policy/action data flow explicit: policy action → optional CBF → optional
   DR noise → velocity/controller transform → rotor command → simulator.
6. **Targeted verification** — run the lowest-cost check that observes the
   changed behavior. Use the project tests and commands in the context skill.
7. **Regression check** — run neighboring pure tests, integration checks, or a
   short headless rollout when the change crosses a boundary. Do not start a
   full training run merely because the config can launch one.
8. **Review and summary** — inspect the complete diff, both repository states,
   config/checkpoint compatibility, and report commands, outcomes, residual
   risks, and unrun expensive checks.

## Repository-specific boundaries

- Work from the workspace root `/home/lz/lzspace/drones` unless a command is
  intentionally run from `OmniDrones/` or `OmniDrones/scripts/`.
- `OmniDrones/` is a nested Git repository/submodule. Check its status before
  and after changes; do not accidentally change the outer submodule pointer.
- Treat `nav_vel.py`, `nav_vel_obstacles.py`, `utils/cbf.py`,
  `utils/torchrl/transforms.py`, `scripts/train.py`, and `scripts/eval_ckpt.py`
  as separate layers. Read only the references needed for the current layer.
- Do not overwrite dirty user files, generated outputs, checkpoints, or
  experiment artifacts. Expensive GPU validation needs explicit task scope.

For long or high-risk work, use the focused templates and stop rules in:

- [loop-contract.md](references/loop-contract.md)
- [loop-policy.md](references/loop-policy.md)
- [hard-debugging.md](references/hard-debugging.md)
- [independent-review.md](references/independent-review.md)

## Completion contract

Finish only after stating:

- what changed and why;
- which files/configs and data-flow boundaries were affected;
- focused and broader verification commands with observed results;
- Git status for the outer repository and `OmniDrones`;
- limitations, unrun Isaac/training checks, and any blocker.
