---
name: project-onboarding
description: Quickly understand the drones repository before making code changes. Use when starting work in this project, investigating an unfamiliar module, or preparing an implementation plan; do not use as a substitute for task-specific coding, testing, or review workflows.
metadata:
  short-description: Build a concise, evidence-based map of the drones project
---

# Project onboarding

Build a concise, evidence-based project map before proposing or implementing changes in this repository.

## Workflow

1. Establish the repository boundary and current state.
   - Identify the repository root, active branch, recent commits, and existing working-tree changes.
   - Do not reset, clean, or overwrite unrelated user changes.

2. Read the high-signal entry points first.
   - `README.md`
   - `setup_env.sh`
   - top-level configuration and dependency files
   - relevant `AGENTS.md` files and project documentation
   - `IsaacLab/` and `OmniDrones/` when the task involves simulation, environments, training, or navigation

3. Map the codebase with targeted search.
   - Find Python package roots, launch/train/evaluation scripts, environment definitions, policies, models, and tests.
   - Trace the requested feature from its public entry point through the main call path and configuration.
   - Prefer `rg` and `rg --files`; avoid reading large generated artifacts, logs, datasets, videos, and model checkpoints unless directly relevant.

4. Identify how to work safely.
   - Record environment setup, runtime prerequisites, test commands, lint/type-check commands, and any expensive commands.
   - Separate commands that are safe to run from commands that may require GPUs, downloads, long training runs, or external services.
   - Never launch a long-running training job or alter environments without explicit user intent.

5. Produce an onboarding brief with these sections:
   - **Project purpose and stack**
   - **Repository map**
   - **Relevant execution path**
   - **Configuration and dependencies**
   - **Validation commands**
   - **Important conventions**
   - **Risks, unknowns, and assumptions**
   - **Recommended next files to inspect**

## Evidence and accuracy

- Cite file paths and, when useful, line numbers for important claims.
- Distinguish facts observed in the repository from inferences.
- Do not invent missing commands, architecture, APIs, or runtime behavior.
- If documentation and code disagree, report the discrepancy and prefer executable code/configuration as evidence.
- Keep the result compact enough to use as working context; include details only when they affect implementation decisions.

## Change boundary

Onboarding is read-only by default. Do not edit source files, install dependencies, initialize submodules, change environment variables, or run destructive commands while producing the brief unless the user separately requests that action.
