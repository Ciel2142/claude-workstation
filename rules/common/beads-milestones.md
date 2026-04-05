# Beads Milestone Updates

After completing each workflow milestone, update the beads task so progress
survives session crashes and context compaction.

## When to Update

- After brainstorming: note the spec path and key design decisions
- After writing a plan: note the plan path and number of sub-tasks
- After each sub-task TDD cycle: note what was implemented and that tests pass
- After verification: append the verification output block
- At session end: note where you stopped and what's next

## How to Update

```
bd update <id> --notes "<milestone>: <path-or-summary>"
```

## Examples

```
bd update claude-workstation-x7k --notes "Spec: docs/superpowers/specs/2026-04-05-analyze-design.md"
bd update claude-workstation-x7k --notes "Plan: docs/superpowers/plans/2026-04-05-analyze.md, 7 tasks"
bd update claude-workstation-r3m --notes "Tests passing: auth validation, 4 tests green"
bd update claude-workstation-x7k --notes "Stopped at: Task 5 of 7 complete, resuming with Task 6 (setup updates)"
```

## What NOT to Do

- Don't update after every micro-step (each brainstorming question, each test run)
- Don't duplicate the full spec/plan content — just reference the file path
- Don't update if nothing meaningful changed since last update
