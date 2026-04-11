---
name: workflow
version: 2.5.1
description: >
  Full workflow ref: Beads + Superpowers + ECC.
  TRIGGER: Starting work, workflow unclear, or via /claude-workstation:workflow.
---

# Unified Development Workflow

## The Stack

| System | Role |
|--------|------|
| **Beads** | Task tracking (WHAT to work on) -- `bd` CLI |
| **Superpowers** | Dev methodology (HOW to work) -- rigid skills |
| **ECC** | Domain expertise (WHO helps) -- language/domain skills |

## The Flow

```
Task -> Brainstorm -> Plan -> Sub-tasks -> Implement (TDD) -> Review -> Verify -> Finish -> Close
```

All tasks follow full pipeline. Self-scales to complexity.

- **Brainstorm** produces spec in `docs/superpowers/specs/`
- **Plan** produces plan in `docs/superpowers/plans/`
- **Sub-tasks**: `bd create` for each + `bd dep add` for dependencies
- **Implement**: `bd ready` -> claim -> TDD (RED -> verify fail -> GREEN -> verify pass -> REFACTOR) -> commit
- **Verify**: run proving command fresh, read full output + exit code, verify supports claim

## Pre-Change Gate

Before any file change, verify in order:

1. **Task boundary** -- shifting discussion to action? `bd create` first.
2. **Task exists?** -- no task = no change. No exceptions.
3. **Scope confirmed this turn?** -- restate files/changes, get explicit "yes."

Exceptions: files in plan/sub-task description, `/start` invocations.

## Hard Rules

- No code without beads task
- No production code without failing test
- No completion claims without verification output
- No trusting subagent reports without own verification
- Query Context7 before implementing with any library/framework
- Invoke `/ecc:strategic-compact` every 3rd closed sub-task
- Outside scope = side-quest: `bd create -t bug` + `bd dep add new current --type=discovered-from`, finish current first

## Skill Invocation Priority

1. **Context7** -- fresh docs for any library/framework
2. **Process skills** -- brainstorming, debugging, verification
3. **Implementation skills** -- TDD, code-review, frontend-design
4. **ECC domain skills** -- language reviewers, build fixers

## Task Decomposition

Four dep types (only `blocks` affects `bd ready`):

| Type | Affects `bd ready` | Use when |
|------|-------------------|----------|
| **blocks** | YES -- blocked task hidden from `bd ready` | Sequential work, technical prereqs |
| **parent-child** | No | Epic -> sub-task structure |
| **related** | No | Connected but independent work |
| **discovered-from** | No | Side-quest found during impl |

**Direction rule:** "X needs Y" -> `bd dep add X Y`

**Ready Fronts:** Sub-tasks close -> blocked work auto-becomes ready. `bd ready` shows available NOW.

## Beads Quick Reference

ALL work MUST be tracked. No exceptions.

| Action | Command |
|--------|---------|
| Create epic | `bd create -t epic "High-level goal"` |
| Create sub-task | `bd create "Sub-task" -t task` + `bd dep add <sub> <epic> --type parent-child` |
| Find available work | `bd ready` |
| Claim task | `bd update <id> --claim` (atomic: sets in_progress + lock) |
| Close task | `bd close <id> --reason "Done"` (auto-unblocks dependents) |
| Clean memories | After closing epic/last sub-task: `bd memories` → `bd forget <key>` for session-scoped memories. Stale memories bloat every future session via `bd prime`. |
| Log side-quest | `bd create "Found: <issue>" -t bug` + `bd dep add <new> <current> --type discovered-from` |
| Session recovery | `bd list --status=in_progress` -> `bd show <id>` -> read notes |

**Multi-terminal:** Each terminal works on DIFFERENT issue (exclusive lock via `--claim`).

**Side-quest rule:** Finish current task first, then `bd ready` for parked issue. Fix size doesn't reduce ceremony.

## Context7: Fresh Docs (MANDATORY)

Query docs before implementing with ANY external library/framework/SDK.

```bash
# 1. Resolve library ID
npx ctx7@latest library <name> "<your question>"

# 2. Fetch current docs using the ID from step 1
npx ctx7@latest docs <libraryId> "<your question>"
```

**When:** Any library -- Next.js, Supabase, React, Tailwind, Zod, Prisma, BullMQ, LangChain, etc.

**Who:** Main agent, subagents, skills -- all query Context7 before writing impl code.

**Why:** Training data stale. APIs change. Context7 gives current docs.

**Never write impl code from memory alone. Verify with Context7 first.**

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

Update beads notes — preserve context across sessions + compaction.

| Key | When | Key | When |
|-----|------|-----|------|
| `spec:` | After brainstorming | `completed:` | Sub-task closes |
| `plan:` | After writing plan | `current:` | Claiming sub-task |
| `planned-tasks:` | Sub-tasks created | `debug:` | Root cause found |
| `stopped:` | Session end / compact | `verification:` | After verification |
| `active-skill:` | Skill invoked | | |

Write via: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "key: value"`

## Enforcement Milestones

TDD milestone chain — each requires predecessors:

| Phase | Prerequisite | Detail |
|-------|-------------|--------|
| `task:created` | — | Sub-task bead exists |
| `task:claimed` | task:created | Work started (`bd update --claim`) |
| `tdd:red` | task:claimed | Failing test written |
| `tdd:red-verified` | tdd:red | Test fails correctly |
| `tdd:green` | tdd:red-verified | Implementation passes |
| `tdd:green-verified` | tdd:green | All tests pass |
| `tdd:refactor` | tdd:green-verified | Cleanup complete |
| `review:spec` | tdd:refactor | Spec compliance passed |
| `review:quality` | review:spec | Code quality review passed |
| `verified` | review:quality | Verification-before-completion done |

Multiple TDD cycles allowed. Special: `paused <reason>` accepted by stop-gate.

Write milestones: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:red wrote failing test for X"`

## Subagent Protocol

ALL subagents MUST include a protocol template from `templates/`:

| Template | Agent Type |
|----------|-----------|
| `protocol-implementer.md` | Code changes (full TDD chain) |
| `protocol-reviewer.md` | Code review (findings + side-quests) |
| `protocol-planner.md` | Planning (plan milestones) |
| `protocol-build-fixer.md` | Build fixes (fix milestones) |

Each ends with `<!-- BEAD-PROTOCOL-v1:<type> -->` sentinel. The agent-gate hook blocks dispatch without it.

Research-only agents: add `BEAD-EXEMPT:research` or `BEAD-EXEMPT:exploration` to prompt.

## Controller Protocol

The main/controller agent tracks its own orchestration milestones:

```
[M] dispatch:impl:<sub-task-id> dispatched implementer
[M] dispatch:review-spec:<sub-task-id> dispatched spec reviewer
[M] dispatch:review-quality:<sub-task-id> dispatched quality reviewer
[M] controller:milestone-check:<sub-task-id> verified milestones present
[M] controller:rejected:<sub-task-id> missing milestones, re-dispatching
```

## Controller Verification (MANDATORY)

After ANY subagent returns, the controller MUST:

1. `bd show <sub-task-id>` — check expected milestones are present
2. Verify side-quest beads created for any CRITICAL/HIGH review findings
3. If milestones missing → reject work, re-dispatch or fix directly
4. Only AFTER milestone validation → dispatch next reviewer/task

Never trust subagent reports at face value. Always verify with `bd show`.

## Side Quests

Problem outside confirmed scope -- even if your change caused it:

```
bd create --title="Found: <issue>" --type=bug
bd dep add <new-id> <current-id> --type=discovered-from
```

Finish current task first, then `bd ready`. Fix size doesn't reduce ceremony.

## Anti-Patterns

- Skip brainstorming -> "just code it"
- Write code before failing test
- Claim "fixed" without verification output
- Work without beads task
- Multiple fixes simultaneously
- Trust subagent reports without own verification
- Qualifier language ("should work", "probably fixed")
- Implement with library without querying Context7

