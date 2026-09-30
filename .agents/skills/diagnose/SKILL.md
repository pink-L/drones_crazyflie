---
name: diagnose
description: 用于系统化诊断 drones 项目中的代码缺陷、测试失败、训练回归、仿真行为变化和数值异常；先复现与取证，再验证假设、定位根因、做最小修复和回归验证。
metadata:
  short-description: Find root causes in code, training, and simulation
---

# Diagnose

Use this skill for failures or unexpected behavior in NavVel, obstacle
geometry, CBF safety, reward/success/collision metrics, controllers, PPO, or
Isaac Sim. Do not propose a fix before completing enough root-cause work to
distinguish the failing layer.

This skill is adapted from the MIT-licensed `systematic-debugging` skill in
OpenAI's public `openai/plugins` repository (source:
https://github.com/openai/plugins/tree/main/plugins/superpowers/skills/systematic-debugging/);
the local `LICENSE` is retained.

## Investigation sequence

1. **Reproduce** — record the exact script, Hydra overrides, seed, device,
   checkpoint/profile, input shape, and observed metric/error. Re-run only
   enough to establish whether the behavior is deterministic.
2. **Minimize** — reduce env count, steps, obstacle count, or data while
   preserving the failure. Prefer a pure Torch/CPU reproduction before an
   Isaac run. Preserve the original failure command and baseline output.
3. **Collect evidence** — inspect the full traceback/log, Git diffs in both
   repositories, tensor shapes/devices/dtypes, NaN/Inf counts, and boundary
   values. For training regressions capture success, collision, arrival,
   clearance/h-min, CBF correction/intervention, reward terms, and episode
   cause—not just total return.
4. **Trace the data flow** — for NavVel trace config → environment reset/layout
   → observation/reward/termination → policy action → CBF/DR/controller →
   rotor/simulator. Check whether the metric is computed before or after the
   filter and whether it covers all obstacles or only the observation window.
5. **Form one hypothesis** — state “X causes Y because Z”, identify a
   prediction that would falsify it, and test it with one minimal change or
   diagnostic. Do not bundle hypotheses.
6. **Identify root cause** — classify the result as product code, test,
   environment/dependency, configuration/checkpoint mismatch, or assumption.
7. **Regression test** — add the smallest deterministic failing test when the
   behavior is testable; use `$tdd` for pure Python/Torch and geometry/CBF
   changes. For Isaac-only behavior, use a targeted headless smoke test and
   record the expensive boundary explicitly.
8. **Minimal fix and verification** — change only the root cause, rerun the
   reproducer, the regression test, and the nearest broader checks. If two
   attempts fail for the same reason, stop retrying and revisit the evidence;
   after repeated cross-layer failures, question the architecture instead of
   adding another symptom fix.

## Drones-specific probes

- A success-rate drop: compare episode semantics (`soft_respawn`,
  `single_episode_per_window`, `arrive_hold_steps`, `term_cause`) before
  comparing rewards.
- A collision-rate or CBF anomaly: compare obstacle geometry/active masks,
  observation top-k versus all-`M` CBF inputs, `d_min`/`h_min`, filter
  intervention, and action order.
- A controller instability: check action units, velocity/yaw limits, the
  `VelController` → `LeePositionController` boundary, randomized mass/KF
  synchronization, and Crazyflie rotor/time-constant parameters.
- A tensor/device or NaN failure: isolate the pure function, print shape and
  device at each boundary, then test a single batch before launching Isaac.

Read only the supporting technique needed for the current failure:

- [root-cause-tracing.md](references/root-cause-tracing.md) for deep call/data
  flow failures;
- [defense-in-depth.md](references/defense-in-depth.md) for layered guards
  after the cause is known;
- [condition-based-waiting.md](references/condition-based-waiting.md) for
  asynchronous or readiness failures.

## Report

Report the reproducer, evidence, tested hypothesis, confirmed root cause,
minimal fix, regression command/results, and remaining uncertainty. Never hide
a failed check by weakening an assertion, changing acceptance criteria, or
silently switching profile/seed/metric semantics.
