---
name: research-verifier
description: Verify an external technical fact needed for an OmniDrones planning decision, such as firmware, Isaac Sim, TorchRL/PPO, CBF literature, or an upstream paper; skip when local evidence suffices.
---

# Research verifier

Use only when the current audit, gate decision, impact review, or next-stage Prompt depends on a fact outside this repository. Verify the exact question against official documentation, original papers, or upstream source; include version, publication/commit date, and direct citation when relevant. Do not perform broad background research.

Label each consequential claim `repository fact`, `external verified fact`, `inference`, or `unknown`. A repository fact needs a local path/revision; an external verified fact needs a source link and applicable version. If sources disagree or do not cover the project's version, state the uncertainty. External material cannot override an explicit frozen project design decision; report the conflict for the planner to resolve. Return only facts that affect the present decision, without editing code or launching experiments.
