# Design: Add /ecc:refactor-clean After Verification

**Date:** 2026-04-11
**Task:** claude-workstation-tnye

## Problem

After a task passes verification, the agent moves straight to `bd close`. No cleanup or simplification step exists. Code written under TDD pressure often has opportunities for consolidation that only become visible after the full implementation is done.

## Solution

Add `/ecc:refactor-clean` as a soft workflow step between `[M] verified` and `bd close`. The agent always runs it — no conditional logic, no gating.

## Milestone Chain (Updated)

```
task:created → task:claimed → tdd:red → tdd:red-verified → tdd:green
→ tdd:green-verified → tdd:refactor → review:spec → review:quality
→ verified → /ecc:refactor-clean → bd close
```

## Behavior

1. Agent sets `[M] verified` as normal.
2. Agent invokes `/ecc:refactor-clean`.
3. If refactor-clean produces changes, agent commits them before `bd close`.
4. If refactor-clean finds nothing, agent proceeds to `bd close`.

## What Changes

| File | Change |
|------|--------|
| `skills/workflow/SKILL.md` | Add refactor-clean step after verified, before bd close |
| `CLAUDE.md` | Update Quick Reference to mention the step |

## What Does NOT Change

- No new hooks or gates.
- No new milestone phase (refactor-clean is not milestone-tracked).
- No labels, tags, or conditional logic.
- `stop-gate` unchanged (still checks `[M] verified`).

## Enforcement

Soft — workflow text only. Agent follows it because the skill says to. No `exit 2` blocking.
