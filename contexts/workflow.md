# Workflow Context

All work follows a size-based flow: Beads (tracking) + Superpowers (process) + ECC (expertise).

## Beads-First Rule

Before invoking ANY Superpowers skill, create a beads task first. Sequence: `bd create` → then invoke skill. This applies to ALL work — design, planning, research, and code.

## Task Sizing

| Tier | Signal | Flow |
|---|---|---|
| **Trivial** | ≤1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | `bd create -t epic` → brainstorm → plan → sub-tasks → spike → worktree → TDD → review → verify → update-docs → finish → `bd close` |
| **Bug** | Any tier, type=bug | `bd create -t bug` → debug → TDD (regression test) → review → verify → `bd close` |

Escalation only upward — never downgrade.

## Hard Rules

- No work without a beads task
- No Superpowers skill invocation without an active beads task
- No production code without a failing test (Small/Medium+)
- No completion claims without verification output
- No trusting subagent reports without own verification

## Plugin Routing

- **Beads** → all persistent task/issue tracking (`bd` commands). No TodoWrite for persistent work.
- **Superpowers** → all development process (brainstorming, planning, TDD, code review, verification, debugging, parallel agents, finishing branches).
- **ECC** → all language-specific and domain-specific skills, agents, and patterns. Use within the Superpowers-driven process.

When both apply: Superpowers drives the process, ECC provides expertise within it.

## Research & Reuse

Before any new implementation:
1. GitHub code search first (`gh search repos`, `gh search code`)
2. Library docs second (Context7 or vendor docs)
3. Check package registries before writing utility code
4. Search for adaptable open-source implementations
5. Prefer proven approaches over net-new code

## Side Quests

Discover something unrelated mid-work:
```
bd create --title="Found: <issue>" --type=bug
bd dep add <new-id> <current-id> --type=discovered-from
```
Finish current task first, then `bd ready`.

Run `/help` for detailed step-by-step flows with full ceremony for each tier.
