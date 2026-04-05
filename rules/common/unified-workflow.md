# Unified Workflow

All work follows a size-based flow connecting Beads (tracking) + Superpowers (process) + ECC (expertise).

## Beads-First Rule

Before invoking ANY Superpowers skill (brainstorming, writing-plans, TDD, code-review, debugging, verification, etc.), create a beads task first. The beads task is the anchor — skills are the process. Sequence: `bd create` → then invoke skill. This applies to ALL work, including design and planning — not just code.

## Task Sizing

| Tier | Signal | Flow |
|---|---|---|
| **Trivial** | ≤1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | `bd create -t epic` → brainstorm → plan → sub-tasks → worktree → TDD → review → verify → finish → `bd close` |
| **Bug** | Any tier, type=bug | `bd create -t bug` → debug → TDD (regression test) → review → verify → `bd close` |

**Escalation only upward.** If work grows beyond current tier, stop and escalate — never downgrade.

## Rules

- No work without a beads task — not just code, ALL work (design, planning, research)
- No Superpowers skill invocation without an active beads task
- No production code without a failing test (Small/Medium+)
- No completion claims without verification output
- No trusting subagent reports without own verification

## Side Quests

Discover something unrelated mid-work:
```
bd create --title="Found: <issue>" --type=bug
bd dep add <new-id> <current-id> --type=discovered-from
```
Finish current task first, then `bd ready`.

Run `/workflow` for detailed step-by-step flows.
