# Repository instructions

## Project Skills

Project skills are located under:

`.agents/skills/`

Important existing skills:

- `.agents/skills/drones-crazyflie-context/SKILL.md`
  - Project-specific OmniDrones / Crazyflie / RL / CBF context.
  - Use when a task depends on project architecture, controller semantics,
    training/evaluation conventions, or safety-layer assumptions.

- `.agents/skills/project-onboarding/SKILL.md`
  - Repository structure, entry points, call paths, configuration and interface discovery.
  - Use before planning work in an unfamiliar or recently changed part of the repository.

- `.agents/skills/implementation-workflow/SKILL.md`
  - Standard project implementation workflow.
  - Planners should use it to make generated implementation prompts compatible
    with the expected Inspect → Contract → Implement → Test → Delivery workflow.

Agents must inspect the current `.agents/skills/` directory rather than assume
this list is exhaustive.

Do not copy or move the existing skills to another directory.

## Workspace layout

This repository root is `drones/`.

The primary development code is under:

`drones/OmniDrones/`

`OmniDrones` is a git submodule / nested repository. Do not change its
submodule pointer unless explicitly requested.

Repository-specific Codex skills are stored under:

`.agents/skills/`

Do not install project skills inside `OmniDrones/.agents/skills`.

When a task spans the outer repository and `OmniDrones`, start Codex from
the `drones/` root so these repository instructions and skills are loaded.

## Experiment outputs

Generated CBF and Phase experiment results belong in
`/home/lz/lzspace/experiment_artifacts/` (relative to this repository:
`../experiment_artifacts/`). Keep the `/home/lz/lzspace/` top level limited to
the existing project entries and this artifact directory. Do not create new
`phase_*` results or logs at the workspace top level.

The Phase scripts in `OmniDrones/scripts/` use that artifact directory when an
output argument is omitted. When specifying `--output`, `--output-dir`, or
`--output-root`, choose a unique path there. Put shell-redirected process logs
there too. Update code and documentation references when moving artifacts;
preserve historical logs and reports as records of their original runs.
The archive's `README.md` and `MIGRATION_MANIFEST.json` describe the move.

## Project context

For OmniDrones / Crazyflie / NavVel development, use the
`drones-crazyflie-context` skill when applicable.

For unfamiliar repository exploration, use `project-onboarding`.

For non-trivial feature development, use `implementation-workflow`.

For systematic debugging and regressions, use `diagnose`.

For testable Python/Torch logic, use `tdd` when appropriate.

Use `skill-creator` only when creating or updating a Skill. Use `visualize`
when an interactive visualization materially improves understanding.

## Editing rules

Before modifying code:

1. Inspect the relevant implementation and config.
2. Determine the affected layer and change surface.
3. Prefer targeted changes over unrelated refactoring.
4. Use the cheapest meaningful verification first.

Do not modify:

- `.gitmodules`
- submodule pointers
- environment/bootstrap scripts
- unrelated experiment files

unless the task explicitly requires it.

Do not run `git commit`, `git push`, `git reset`, or `git clean`
unless explicitly requested.

Preserve unrelated worktree changes. Before reporting completion, state the
verification performed and call out any pre-existing dirty files that remain.


# OmniDrones Multi-Agent Routing

## Orchestrator

The primary Codex agent is the orchestrator.

Preferred runtime:

- model: `gpt-6-astra`
- reasoning effort: `high`

The orchestrator owns:

- task decomposition;
- delegation;
- deciding when escalation is necessary;
- integrating evidence from child agents;
- deciding whether a code change should proceed;
- final validation strategy;
- final response to the user.

The orchestrator should avoid spending expensive reasoning on mechanical
repository scans, log inspection, or routine test execution when a specialized
child agent can do that work.

Only the orchestrator should delegate work to child agents.

Child agents must not recursively spawn other agents.

---

## Available agents

### `explorer`

Model:

`gpt-5.6-luna` / `xhigh`

Use for:

- repository exploration;
- locating code;
- tracing call paths;
- mapping interfaces;
- finding entry points;
- understanding configuration;
- gathering file/symbol evidence.

Read-only.

Do not use it for implementation.

### `watcher`

Model:

`gpt-5.6-luna` / `high`

Use for:

- logs;
- runtime output;
- git diff/status monitoring;
- training metrics;
- warnings/exceptions;
- detecting regressions or anomalies.

Read-only.

### `test_runner`

Model:

`gpt-5.6-luna` / `medium`

Use for:

- targeted tests;
- smoke tests;
- import checks;
- static checks;
- minimal reproductions;
- validation commands.

Do not use it for implementation.

Avoid expensive training/GPU jobs unless explicitly justified.

### `reviewer`

Model:

`gpt-5.6-terra` / `high`

Use for:

- correctness review;
- regression analysis;
- API/interface review;
- numerical risks;
- RL/control semantics;
- missing tests;
- post-implementation review.

Read-only.

### `implementer`

Model:

`gpt-5.6-sol` / `high`

Use for:

- normal code implementation;
- bounded fixes;
- normal features;
- refactors;
- test additions.

This is the normal write-capable coding agent.

### `architect`

Model:

`gpt-6-astra` / `medium`

Use selectively for:

- CBF theory or implementation design;
- reinforcement-learning architecture;
- policy observation/action semantics;
- controller architecture;
- Crazyflie/PX4 integration assumptions;
- dynamics-model assumptions;
- safety filter design;
- cross-module architecture;
- difficult algorithmic root-cause analysis.

Read-only.

Architect provides decisions and implementation boundaries.
Implementer performs the actual code changes.

---

## Default routing policy

Do not automatically use every agent.

Choose the smallest useful workflow.

### A. Simple factual repository question

Use:

`explorer → orchestrator`

Example:

- Where is the reward calculated?
- Where is velocity command sent?
- Which class creates the environment?

No reviewer or architect unless needed.

### B. Runtime/log/training anomaly

Prefer parallel evidence gathering:

`explorer + watcher`

Then:

`reviewer`

If it is an ordinary code bug:

`implementer → test_runner`

If it becomes a fundamental algorithm/control/design issue:

`architect → implementer → test_runner → reviewer`

### C. Normal implementation task

Use when necessary:

`explorer → implementer → test_runner`

For meaningful or risky changes add:

`reviewer`

Result:

`explorer → reviewer → implementer → test_runner → reviewer`

The second reviewer pass is especially useful for nontrivial changes.

### D. Core algorithm task

Examples:

- CBF formulation;
- safety constraints;
- quadrotor dynamics assumptions;
- RL observation/action-space redesign;
- reward redesign;
- velocity-loop assumptions;
- Crazyflie/PX4 control semantics;
- sim-to-real control interface changes.

Use:

`explorer → architect → reviewer → implementer → test_runner → reviewer`

Explorer gathers the real implementation first.

Architect reasons about the theory/design.

Reviewer challenges correctness and implementation risks.

Implementer writes the code.

Test Runner validates it.

Reviewer performs final review.

### E. Tiny obvious edit

For a trivial local edit with no meaningful ambiguity, the orchestrator may use
`implementer` directly and avoid unnecessary delegation.

Do not create multi-agent overhead for a typo or obvious one-line change.

---

## Escalation policy

Escalate from Explorer/Watcher/Test Runner when evidence indicates:

- unclear ownership across multiple modules;
- conflicting interfaces;
- nontrivial numerical behavior;
- unexplained training instability;
- controller/state/action semantic mismatch.

Escalate to Reviewer for normal engineering reasoning.

Escalate to Architect when the issue involves fundamental assumptions such as:

- mathematical correctness;
- system dynamics;
- control architecture;
- CBF feasibility/invariance;
- RL formulation;
- coordinate-system design;
- policy/controller interface semantics;
- major cross-module architecture.

Do not use Architect merely because a task is long.

Use Architect because the reasoning itself is difficult or high-impact.

---

## Evidence-first rule

Before editing nontrivial code, establish what the current system actually does.

Prefer:

`explorer/watcher evidence → reasoning → implementation`

over:

`guess → edit → see what breaks`

When reporting evidence, agents should prefer:

- exact file paths;
- classes/functions;
- relevant line ranges;
- executed commands;
- actual exception messages;
- measured behavior.

Do not paste enormous files or logs into the parent context.

Summarize and quote only relevant portions.

---

## Separation of responsibilities

Explorer:
- investigates;
- does not edit.

Watcher:
- monitors;
- does not edit.

Test Runner:
- executes validation;
- does not intentionally edit source.

Reviewer:
- reviews;
- does not edit.

Architect:
- designs/reasons;
- does not edit.

Implementer:
- edits code.

Orchestrator:
- coordinates and makes the final workflow decision.

This separation should be maintained unless the user explicitly requests a
different workflow.

---

## Parallelism

Parallelize only independent work.

Good:

`explorer + watcher`

because source tracing and log inspection can often happen independently.

Potentially good:

multiple explorer tasks for clearly separate subsystems.

Bad:

running reviewer, architect, and implementer simultaneously on the same
unresolved design question.

Do not allow two write-capable agents to edit overlapping files concurrently.

The project hard limit is:

`6 child threads`

but normal use should usually remain around 2–4 concurrent child agents.
Use the full limit only when the work is genuinely independent.

---

## Context-efficiency rules

Child-agent reports should be concise.

Return:

1. conclusion;
2. strongest evidence;
3. relevant files/symbols;
4. commands/tests if applicable;
5. unresolved questions;
6. recommended next routing step.

Avoid:

- repeating the entire user prompt;
- dumping full source files;
- dumping full logs;
- explaining obvious project context repeatedly.

The orchestrator should pass only the minimum required context between agents.

---

## OmniDrones-specific review priorities

When modifying RL, simulation, controller, or safety code, explicitly verify
when applicable:

- observation ordering;
- action ordering;
- tensor dimensions;
- batch dimensions;
- dtype;
- CPU/GPU device;
- normalization;
- clipping/saturation;
- units;
- coordinate frames;
- world/body frame conversion;
- axis definitions;
- sign conventions;
- radians vs degrees;
- timestep `dt`;
- physics frequency;
- control frequency;
- policy frequency;
- reset state;
- termination state;
- reward timing;
- actuator/controller latency;
- velocity setpoint semantics;
- attitude/thrust semantics;
- CBF state/control definitions;
- CBF relative degree;
- constraint direction;
- feasibility assumptions.

Do not change these semantics casually.

---

## Git safety

Agents must assume other work may already exist in the working tree.

Never:

- reset unrelated changes;
- checkout over user changes;
- delete files merely because they are untracked;
- use destructive Git commands to obtain a clean tree;
- revert another agent's concurrent changes.

Before implementation, inspect:

`git status`

After implementation, report the exact files changed.

Do not commit or push unless explicitly requested by the user.
