## Workflow: Beads + Superpowers + ECC

Any task → `/claude-workstation:start "description"` first.
Full ref → `/claude-workstation:workflow`.

### Quick Reference

1. **Task** -- `bd create "Goal"` (every change gets tracked)
2. **Brainstorm** -- `superpowers:brainstorming` (design before code)
3. **Plan** -- `superpowers:writing-plans` (decompose into sub-tasks)
4. **Sub-tasks** -- `bd create` for each + `bd dep add` (parent-child, blocks)
5. **Implement** -- `bd ready` -> pick -> `bd update --claim` -> TDD (RED -> GREEN -> REFACTOR)
6. **Review** -- `superpowers:requesting-code-review`
7. **Verify** -- `superpowers:verification-before-completion` (evidence before claims)
8. **Finish** -- `superpowers:finishing-a-development-branch`
9. **Close** -- `bd close <id>`

### Hard Rules

- No code without a beads task
- No production code without a failing test
- No completion claims without verification output
- No trusting subagent reports without own verification
- Query Context7 before any library/framework impl
- `/ecc:strategic-compact` every 3rd closed sub-task
- Outside scope = side-quest: `bd create -t bug` + `bd dep add new current --type=discovered-from`, finish current first

### Enforcement Hooks

Hooks block (`exit 2`) when workflow steps are skipped:

| Gate | Trigger | Blocks unless |
|------|---------|---------------|
| milestone-gate | Edit/Write | Active sub-task with `[M] task:claimed` |
| agent-gate | Agent dispatch | Prompt contains protocol template or `BEAD-ROLE:default` (see `agent-roles` skill) |
| commit-gate | git commit | `[M] review:quality` present |
| stop-gate | Session end | All tasks have `[M] verified` or `[M] paused` |

### Milestone Format

`[M] <phase> <freetext>` — append via `bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] phase detail"`

Phases: task:created → task:claimed → tdd:red → tdd:red-verified → tdd:green → tdd:green-verified → tdd:refactor → review:spec → review:quality → verified

### Subagent Protocol

Before dispatching any subagent, check the `agent-roles` skill for the correct role and template.
Five roles: implementer, reviewer, planner, build-fixer, default (add `BEAD-ROLE:default` to prompt).

### Session

- **Resume:** `bd list --status=in_progress` -> `bd show <id>` -> read notes for spec/plan paths
- **Validate:** `bash tests/validate-config.sh`

### Prerequisites

Install per plugin docs:
- [Beads](https://github.com/steveyegge/beads) -- task tracking
- [Superpowers](https://github.com/obra/superpowers) -- dev methodology
- [ECC](https://github.com/affaan-m/everything-claude-code) -- domain expertise

### Caveman Mode Rules

Default: **lite**. Code/commits/security: always normal.
Escalate to **full** for: beads ops (responses + note content), pre-compaction context.
Beads titles/descriptions: stay **normal** (human-scannable).

**Pre-compaction** (when `/ecc:strategic-compact` suggests, and safe):
1. Identify essential context not yet in beads
2. Compress via caveman full → `bd update <id> --notes "..."`
3. Then compact
