## Workflow: Beads + Superpowers + ECC

Before starting ANY task, invoke `/claude-workstation:start "description"` to assess and route.
For the full workflow reference, invoke `/claude-workstation:workflow`.

### Quick Reference (scale ceremony to complexity)

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
- Query Context7 before implementing with any library/framework
- Escalation upward only -- if work grows, re-assess tier, never downgrade
- Invoke `/ecc:strategic-compact` every 3rd closed sub-task
- Outside scope = side-quest: `bd create -t bug` + `bd dep add new current --type=discovered-from`, finish current first

### Session

- **Resume:** `bd list --status=in_progress` -> `bd show <id>` -> read notes for spec/plan paths
- **Validate:** `/claude-workstation:test`

### Prerequisites

Install each plugin following its own documentation:
- [Beads](https://github.com/steveyegge/beads) -- task tracking
- [Superpowers](https://github.com/obra/superpowers) -- development methodology
- [ECC](https://github.com/affaan-m/everything-claude-code) -- domain expertise
