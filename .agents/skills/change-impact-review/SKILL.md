---
name: change-impact-review
description: Map the effects and regression checks of a proposed OmniDrones next-stage change before writing its implementation Prompt; use for planning, not editing code.
---

# Change impact review

Given one proposed next-stage change, inspect the live code/config and identify affected interfaces and preserved behavior. This is a read-only planning review.

Check: shared modules; action spec; observation spec; reward semantics; checkpoint compatibility; train/eval symmetry; config/profile compatibility; timing/frequency; reset semantics; logging/statistics; and baseline regression risk. Where relevant, trace callers and consumers across policy, safety filter, controller, environment, and scripts. Mark an item `unknown` when evidence is insufficient; do not assume compatibility from unchanged file names.

Output three sections: `Affected`, `Must remain unchanged`, and `Regression tests required`. In each, cite the relevant path/interface and state the concrete risk or invariant. Distinguish cheap deterministic checks from simulator or training checks; specify a fixed baseline/profile/checkpoint when comparison requires one. Hand these constraints to the Prompt writer, without changing the project.
