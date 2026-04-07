---
name: scope-health
version: 1.2.0
description: >
  Scope creep detection for Medium+ epics. Warning at 1.5x, gate at 2.0x
  planned tasks. Escalation ladder with re-plan/split/continue options.
  TRIGGER: After every 3rd sub-task completion within a Medium+ epic.
---

# Scope Health Check

## When

After closing any sub-task within a Medium+ epic, query `bd list --status=closed`
count for the epic. If `count % 3 == 0`, invoke this skill. Do not self-count —
always query beads for the actual count.

## Baseline

After all sub-tasks are created from the plan, record the original count:
```
bd update <epic-id> --notes "planned-tasks: N"
```
This is the denominator for all future ratio calculations.

## Measurements

- **Task ratio:** `(total created sub-tasks) / (planned-tasks from notes)` — e.g., 12 actual / 8 planned = 1.5x
- **Discovery count:** Sub-tasks created after the initial plan (total - planned)

## Escalation Ladder

| Trigger | Ratio | Response |
|---|---|---|
| **Warning** | >= 1.5x | Print stats, continue. Log: `scope-check: warning -- N/M tasks (ratio)` |
| **Gate** | >= 2.0x | Print stats, stop, ask human. Log: `scope-check: gate -- N/M tasks (ratio), decision: <choice>` |

## Warning Format

```
Scope check (after task N):
   Planned: M tasks | Actual: X tasks (ratio)
   Discovered: Y new tasks since plan
   Warning: scope growing. Consider whether remaining tasks need re-planning.
```

## Gate Format

```
Scope check (after task N):
   Planned: M tasks | Actual: X tasks (ratio)
   Discovered: Y new tasks since plan
   Scope exceeded 2x. Options:
      1. Re-plan remaining work (update plan, re-estimate)
      2. Split epic (carve off discovered work into a new epic)
      3. Continue as-is (acknowledge scope growth, keep going)

   Pick [1-3]:
```

## After Gate Decision

- **Re-plan:** Update the plan document, create/close sub-tasks as needed, update `planned-tasks:` baseline
- **Split epic:** Create new epic for discovered work, move relevant sub-tasks, reset baseline for both
- **Continue:** Acknowledge and log, no further gates until next 3-task interval
