---
name: workflow
version: 2.2.0
description: >
  Full workflow reference: Beads + Superpowers + ECC.
  TRIGGER: When starting work, when workflow is unclear, or via /claude-workstation:workflow.
---

# Unified Development Workflow

## The Stack

| System | Role |
|--------|------|
| **Beads** | Task tracking (WHAT to work on) -- `bd` CLI |
| **Superpowers** | Development methodology (HOW to work) -- rigid skills |
| **ECC** | Domain expertise (WHO helps) -- language/domain skills |

## The Flow

```
Task -> Brainstorm -> Plan -> Sub-tasks -> Implement (TDD) -> Review -> Verify -> Finish -> Close
```

Not every task needs every step. `/claude-workstation:start` assesses complexity and suggests where to enter.

- **Brainstorm** produces spec in `docs/superpowers/specs/`
- **Plan** produces plan in `docs/superpowers/plans/`
- **Sub-tasks**: `bd create` for each + `bd dep add` for dependencies
- **Implement**: `bd ready` -> claim -> TDD (RED -> verify fail -> GREEN -> verify pass -> REFACTOR) -> commit
- **Verify**: run proving command fresh, read complete output + exit code, verify it supports the claim

## Pre-Change Gate

Before any file change, verify in order:

1. **Task boundary** -- shifting from discussion to action? `bd create` first.
2. **Task exists?** -- no task = no change. No exceptions.
3. **Scope confirmed this turn?** -- restate files/changes, get explicit "yes."

Exceptions: files listed in plan/sub-task description, `/start` invocations.

## Hard Rules

- No code without a beads task
- No production code without a failing test
- No completion claims without verification output
- No trusting subagent reports without own verification
- Query Context7 before implementing with any library/framework
- Escalation upward only -- if work grows, re-assess tier, never downgrade
- Invoke `/ecc:strategic-compact` every 3rd closed sub-task
- Outside scope = side-quest: `bd create -t bug` + `bd dep add new current --type=discovered-from`, finish current first

## Skill Invocation Priority

1. **Context7** -- fresh docs for any library/framework being used
2. **Process skills** -- brainstorming, debugging, verification
3. **Implementation skills** -- TDD, code-review, frontend-design
4. **ECC domain skills** -- language-specific reviewers, build fixers

## Task Decomposition

Four dependency types (only `blocks` affects `bd ready`):

| Type | Affects `bd ready` | Use when |
|------|-------------------|----------|
| **blocks** | YES -- blocked task hidden from `bd ready` | Sequential work, technical prerequisites |
| **parent-child** | No | Epic -> sub-task structure |
| **related** | No | Connected but independent work |
| **discovered-from** | No | Side-quest found during implementation |

**Direction rule:** Think "X needs Y" -> `bd dep add X Y`

**Ready Fronts:** As sub-tasks close, blocked work automatically becomes ready. Use `bd ready` to see what's available NOW.

## Beads Quick Reference

ALL work MUST be tracked. No exceptions.

| Action | Command |
|--------|---------|
| Create epic | `bd create -t epic "High-level goal"` |
| Create sub-task | `bd create "Sub-task" -t task` + `bd dep add <sub> <epic> --type parent-child` |
| Find available work | `bd ready` |
| Claim a task | `bd update <id> --claim` (atomic: sets in_progress + lock) |
| Close a task | `bd close <id> --reason "Done"` (auto-unblocks dependents) |
| Log a side-quest | `bd create "Found: <issue>" -t bug` + `bd dep add <new> <current> --type discovered-from` |
| Session recovery | `bd list --status=in_progress` -> `bd show <id>` -> read notes |

**Multi-terminal:** Each terminal works on a DIFFERENT issue (exclusive lock via `--claim`).

**Side-quest rule:** Finish current task first, then `bd ready` to pick up the parked issue. Size of fix does not reduce ceremony.

## Context7: Fresh Docs (MANDATORY)

Before implementing with ANY external library, framework, or SDK -- query docs first.

```bash
# 1. Resolve library ID
npx ctx7@latest library <name> "<your question>"

# 2. Fetch current docs using the ID from step 1
npx ctx7@latest docs <libraryId> "<your question>"
```

**When:** Any library -- Next.js, Supabase, React, Tailwind, Zod, Prisma, BullMQ, LangChain, etc.

**Who:** Main agent, subagents, and skills -- everyone queries Context7 before writing implementation code.

**Why:** Claude's training data is stale. APIs change. Context7 gives current docs.

**Never write implementation code based on memory alone. Always verify with Context7 first.**

## Key Skills Reference

| Skill | When | Type |
|-------|------|------|
| `brainstorming` | Before any creative/feature work | Rigid |
| `writing-plans` | After brainstorm approval | Rigid |
| `test-driven-development` | During all implementation | Rigid |
| `systematic-debugging` | Any bug or test failure | Rigid |
| `verification-before-completion` | Before claiming done | Rigid |
| `requesting-code-review` | After implementation | Flexible |
| `receiving-code-review` | When getting feedback | Rigid |
| `using-git-worktrees` | Non-trivial feature isolation | Flexible |
| `subagent-driven-development` | Executing plans, independent tasks | Flexible |
| `executing-plans` | Following pre-written plans | Flexible |
| `finishing-a-development-branch` | Tests pass, ready to merge | Rigid |
| `dispatching-parallel-agents` | 2+ independent problems | Flexible |

## Milestone Notes

Update beads notes to preserve context across sessions and compaction.

| Key | When | Key | When |
|-----|------|-----|------|
| `tier:` | After `/start` | `completed:` | Sub-task closes |
| `spec:` | After brainstorming | `current:` | Claiming sub-task |
| `plan:` | After writing plan | `debug:` | Root cause found |
| `planned-tasks:` | Sub-tasks created | `verification:` | After verification |
| `stopped:` | Session end / compact | `active-skill:` | Skill invoked |

Write via: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "key: value"`

## Side Quests

Problem outside your confirmed scope -- even if your change caused it:

```
bd create --title="Found: <issue>" --type=bug
bd dep add <new-id> <current-id> --type=discovered-from
```

Finish current task first, then `bd ready`. Size of fix does not reduce ceremony.

## Anti-Patterns

- Skip brainstorming -> "just code it"
- Write code before failing test
- Claim "fixed" without verification output
- Work without beads task
- Multiple fixes simultaneously
- Trust subagent reports without own verification
- Qualifier language ("should work", "probably fixed")
- Implement with library without querying Context7
