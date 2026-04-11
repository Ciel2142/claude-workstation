---
name: agent-roles
version: 2.5.5
description: >
  Subagent role registry. Check before dispatching any Agent.
  TRIGGER: Before any Agent dispatch, or when agent-gate blocks a subagent.
---

# Agent Roles

Before dispatching any subagent, match its purpose to a role from this table. Include the corresponding protocol template in the prompt. If nothing matches, use **research** (default).

Do not invent roles outside this table.

| Role | Template to include | Use when agent... |
|------|---------------------|-------------------|
| **implementer** | `templates/protocol-implementer.md` | writes or edits code (Edit/Write tools) |
| **reviewer** | `templates/protocol-reviewer.md` | reviews code, logs findings |
| **planner** | `templates/protocol-planner.md` | creates implementation plans |
| **build-fixer** | `templates/protocol-build-fixer.md` | fixes build or test errors |
| **research** | *exempt* — add `BEAD-EXEMPT:research` to prompt | reads, searches, explores **(default)** |

## How to use

1. Decide what the subagent will **do** (not what it's called)
2. Find the matching role above
3. If role has a template → read that template file, include its content in the prompt
4. If role is research → add the text `BEAD-EXEMPT:research` anywhere in the prompt
5. If unsure → use research (exempt). Safe default.

## Examples

**Dispatching an Explore agent** (reads codebase):
→ Role: research → add `BEAD-EXEMPT:research` to prompt

**Dispatching a code-reviewer agent** (reviews code):
→ Role: reviewer → include `templates/protocol-reviewer.md` in prompt

**Dispatching a general-purpose agent to implement a feature**:
→ Role: implementer → include `templates/protocol-implementer.md` in prompt

**Dispatching a build-error-resolver agent**:
→ Role: build-fixer → include `templates/protocol-build-fixer.md` in prompt

**Dispatching a planner or architect agent**:
→ Role: planner → include `templates/protocol-planner.md` in prompt
