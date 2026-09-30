---
name: experiment-gate-review
description: Review OmniDrones Phase or Stage experiments against their stated hypothesis, controls, metrics, and acceptance gate; use when deciding whether a stage passed or what experiment comes next.
---

# Experiment gate review

Review the selected Phase/Stage from its design, run configuration, and actual result artifacts. This skill judges experiment evidence, not code quality or implementation scope.

For each candidate stage, record: `Phase / Stage`, `hypothesis`, `changed variable`, `controlled variables`, `metrics`, `result`, `gate condition`, `gate status`, `blocker`, and `justified next step`. Give source paths and run/revision identifiers for the gate and result. Check that comparison runs really hold the declared controls fixed, including seed, checkpoint, profile, environment, duration, and evaluation mode when relevant.

Set `gate status` to `PASS` or `FAIL` only when the recorded result can be compared with an explicit condition. If a critical condition, measurement, baseline, or run identity is absent, write `NOT YET ESTABLISHED` and name the missing evidence. If execution is prevented, use `BLOCKED` with the concrete blocker. Code presence, a launched run, or an encouraging metric without its required comparison does not pass a gate. Recommend only the next experiment or decision supported by this evidence; do not implement or launch training by default.
