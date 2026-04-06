---
name: beads-milestones
version: 1.0.0
description: >
  Structured checkpoint format for beads milestone notes. Standardized
  key-value pairs for workflow progress tracking.
  TRIGGER: When updating beads task notes at workflow milestones.
---

# Beads Milestone Updates

After completing each workflow milestone, update the beads task so progress
survives session crashes and context compaction.

## When to Update

- After brainstorming: note the spec path
- After writing a plan: note the plan path and sub-task count
- After creating sub-tasks: note the planned count
- After spike: note findings
- After each sub-task: note progress
- After verification: note results
- After updating docs: note what was updated
- At session end: note where you stopped

## Standardized Format

Use one key-value pair per `bd update --notes` call. Keys are lowercase with colon separator.

| Key | Written when | Example |
|---|---|---|
| `tier:` | After `/start` scores the task | `tier: medium+` |
| `spec:` | After brainstorming writes the spec | `spec: docs/superpowers/specs/2026-04-06-auth-design.md` |
| `plan:` | After writing-plans saves the plan | `plan: docs/superpowers/plans/2026-04-06-auth.md` |
| `planned-tasks:` | After sub-tasks created from plan | `planned-tasks: 8` |
| `spike:` | After spike completes | `spike: lightweight` |
| `spike-confirmed:` | Spike findings | `spike-confirmed: file paths valid, interfaces match` |
| `spike-revised:` | Spike found wrong assumption | `spike-revised: config key renamed foo -> bar` |
| `spike-risks:` | Spike identified risks | `spike-risks: large file, consider splitting` |
| `completed:` | After each sub-task closes | `completed: 1,2,3` |
| `current:` | When claiming a sub-task | `current: 4` |
| `micro-tier:` | When claiming a sub-task | `micro-tier: micro-small` |
| `spec-amendment:` | When spec is updated | `spec-amendment: minor -- renamed userId to user_id` |
| `scope-check:` | After scope health triggers | `scope-check: warning -- 8/5 tasks (1.6x)` |
| `debug:` | After debugging identifies root cause | `debug: root cause -- stale cache in session-start hook` |
| `verification:` | After verification runs | `verification: tests 47/47, build clean, lint clean` |
| `docs-updated:` | After /ecc:update-docs completes | `docs-updated: README, API docs refreshed` |
| `stopped:` | At session end | `stopped: Task 5 of 8, resuming with Task 6` |

## How to Update

```
bd update <id> --notes "<key>: <value>"
```

## Rules

- One key-value per `bd update --notes` call (beads appends, doesn't replace)
- Keys are lowercase, colon-separated, no quotes needed
- `/resume` matches by prefix — consistent format makes detection reliable
- Backward compatible with older free-text notes

## What NOT to Do

- Don't update after every micro-step (each brainstorming question, each test run)
- Don't duplicate full spec/plan content — just reference the file path
- Don't update if nothing meaningful changed since last update
- Don't invent new keys — use the table above
