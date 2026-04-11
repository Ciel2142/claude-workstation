## Workflow: Beads + Superpowers + ECC

New task: `bd create --title="..." --type=task` then brainstorm or plan.
Reference: `/claude-workstation:workflow`
Orchestrator: `/claude-workstation:orchestrator`

> **RIGID REF:** Read `skills/workflow/SKILL.md` for hard rules, milestones,
> enforcement hooks, side-quest detection, and session recovery.
> Do not act on these from memory.

> **RIGID REF:** Read `skills/agent-roles/SKILL.md` § "How to use" before
> dispatching any subagent. Do not act on role mapping from memory.

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
