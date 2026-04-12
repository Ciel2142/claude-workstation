## Workflow: Beads + Superpowers + ECC

### Intent Detection (ALWAYS ACTIVE)

When the user expresses intent to **build, create, add, implement, plan, design,
fix, refactor, or change** something — that is a workflow trigger. You MUST
activate the workflow below before writing any code.

**Trigger phrases include but are not limited to:**
- "build me ...", "create a ...", "add ...", "implement ..."
- "I want to ...", "let's make ...", "we need ..."
- "plan ...", "design ...", "architect ..."
- "fix ...", "refactor ...", "change ...", "update ..."
- Any request that implies producing or modifying code

**Route by intent:**

| Intent | First step |
|--------|------------|
| New feature / creative work | `bd create` → `/superpowers:brainstorming` → plan → implement |
| Bug fix / specific issue | `bd create -t bug` → `/superpowers:systematic-debugging` |
| Refactor / cleanup | `bd create` → plan scope → implement |
| Planning only (no code yet) | `bd create` → `/superpowers:brainstorming` |
| Resuming work | `bd list --status=in_progress` → `bd show <id>` → continue |

**The rule:** If the user's message would lead to code changes, create a beads
task FIRST. No exceptions. Even "quick fixes" get tracked.

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
