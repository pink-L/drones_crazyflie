---
name: project-state-audit
description: Audit the current OmniDrones project state from the live worktree, configs, reports, and results before deciding the next stage; use for status or planning requests, not code implementation.
---

# Project state audit

Determine what is true **now** in `drones/OmniDrones`. This is a read-only planning skill.

1. Read `drones/AGENTS.md` and any applicable local instructions. From both `drones/` and its nested `OmniDrones/` repository, inspect `git status`, branch, HEAD, and uncommitted diff (including staged changes). Do not treat the outer submodule pointer as the inner worktree state.
2. Inspect the current design document, latest relevant phase reports, active configuration, and most recent relevant test/training/evaluation results. Use timestamps, run IDs, commands, seeds, checkpoints, and config/profile IDs to connect a result to the code it exercised. Sample large logs; preserve the exact evidence path.
3. Cross-check documentation against live code/config and results. Record conflicts and missing evidence. Old chats, roadmaps, file names, and an implementation claim alone cannot establish current behavior or validation.

Report each relevant capability or stage with an evidence path and one status: `planned`, `implemented`, `implemented but unverified`, `validated`, `failed`, `deprecated`, or `blocked`. Use `implemented` only for source/config presence when verification is not yet assessed; use `implemented but unverified` when the absence of applicable validation is established. Mark unknown evidence explicitly instead of forcing a status. Separate working-tree behavior from HEAD and identify which revision each result covers. End with the smallest set of unresolved facts needed to choose a next stage.
