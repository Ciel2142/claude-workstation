---
name: spike-phase
version: 1.2.0
description: >
  Architecture validation before Medium+ implementation. Lightweight or
  deep spike to confirm assumptions and identify risks.
  TRIGGER: During Medium+ epic, after planning, before first implementation task.
---

# Spike Phase

## When

After the plan is written and sub-tasks are created, before the first implementation
task. Required for all Medium+ epics.

## Conditional Depth

**Lightweight (default):** Research artifact only. Validate integration points, confirm
assumptions, identify risks. No throwaway code. ~10-15 minutes.

**Deep (auto-escalate when ANY plan task description contains):** API, integration,
library, SDK, migrate, external. Produces the research artifact plus a minimal
proof-of-concept for the riskiest integration. Code is discarded after findings are
documented. ~30-60 minutes.

## Process

1. Create the spike sub-task:
   ```
   bd create --title="Task 0: Spike" --type=task
   bd dep add <spike-id> <epic-id> --type=parent-child
   ```
   All other sub-tasks should depend on the spike (add `bd dep add <sub-id> <spike-id>`
   for Layer 1 tasks, or let dependency chains handle it).

2. Determine depth: scan plan task descriptions for escalation keywords. If any match,
   use deep. Otherwise use lightweight.

3. Execute the spike:
   - Read the spec and plan
   - For each integration point: verify the file paths exist, the interfaces match
     what the plan assumes, and the data flows as described
   - For deep spikes: build a minimal proof-of-concept for the riskiest integration
     (pick the one with the most unknowns, the least-familiar external dependency,
     or the highest blast radius if it fails), then discard the code

4. Record findings in the epic's beads notes:
   ```
   spike: <lightweight|deep>
   spike-confirmed: <assumption1>, <assumption2>
   spike-revised: <assumption that was wrong> -> <correction>
   spike-risks: <risk1>, <risk2>
   ```

5. Gate check: if any `spike-revised` entry is material (changes architecture,
   drops/adds features, changes API shape), trigger the spec amendment protocol
   before proceeding. Minor revisions (naming, paths) can be self-corrected.

6. Close the spike task:
   ```
   bd close <spike-id>
   ```

## What Lightweight Validates

- File paths referenced in the plan actually exist
- Interfaces (function signatures, types, config keys) match what the plan assumes
- Integration points (imports, API calls, database access) work as described
- No blocking unknowns in the dependency chain

## What Deep Adds

- Working proof-of-concept for the riskiest integration
- Verified that external APIs/libraries behave as documented
- Performance or compatibility concerns surfaced before full implementation
