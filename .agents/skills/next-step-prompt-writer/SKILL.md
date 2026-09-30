---
name: next-step-prompt-writer
description: Turn an evidence-backed OmniDrones next-stage decision into a self-contained Prompt for a new Codex implementation conversation; use after the state and gate are established.
---

# Next-step prompt writer

Write one copyable Prompt for the **single** next implementation stage. Planning and Prompt writing are this skill's scope; it does not implement, refactor, train, or modify core project code.

Use current repository evidence, the relevant experiment gate, and a change-impact review. If the next stage, acceptance gate, or a critical algorithmic decision is unresolved, report that gap instead of inventing an implementation Prompt. Distinguish frozen decisions from details the implementation agent must adapt after inspecting local code. Include only history that changes this stage's decision.

Produce a self-contained Prompt with these headings, in order:

1. Role / objective
2. Authoritative sources
3. Current verified state
4. Single next-stage objective
5. Files/code to inspect first
6. Allowed scope
7. Explicit non-goals
8. Frozen design decisions
9. Required implementation
10. Tests
11. Acceptance gates
12. Required logging/evidence
13. Regression requirements
14. Git/worktree discipline
15. Deliverables
16. Stop conditions
17. Required final report format

Supply concrete paths, interfaces, algorithms/formulas or authoritative design references, configuration, metrics, thresholds, and commands when established. For unknowns that the implementation agent can safely resolve from local code, say exactly what to inspect and what must stay invariant. Do not require chat memory or ask the agent to guess a key algorithm. State that it must preserve unrelated dirty changes, inspect both Git repositories, and avoid commits, pushes, resets, cleans, or submodule-pointer changes unless separately authorized.
