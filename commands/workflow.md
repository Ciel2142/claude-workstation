---
description: Show the unified development workflow (Beads + Superpowers + ECC)
---

# Unified Development Workflow

## Step Zero: Create a Beads Task

**BEFORE anything else — before sizing, before invoking any skill:**

```
bd create --title="..." --type=task|bug|feature|epic
```

The beads task is the anchor. Everything else flows from it. No exceptions — design work, research, planning, and code all get tracked.

**Or use `/claude-workstation:start`** to auto-assess the tier, create the task, and start the right flow in one step.

---

## Then Size Your Task

| Tier | Signal | Examples |
|---|---|---|
| **Trivial** | ≤1 file, no behavior change | Typo, config tweak, formatting, comment |
| **Small** | 1-3 files, single concern | Bug fix, small feature, focused refactor |
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | New feature, API, architectural change |

---

## Trivial Path

```
1. TASK     bd create --title="..." --type=task
2. FIX      Make the change
3. VERIFY   Run relevant check (build, lint, etc.)
4. COMMIT   Conventional commit
5. CLOSE    bd close <id>
```

No brainstorming, no TDD, no code review. Just track it and do it.

---

## Small Path

```
1. TASK     bd create --title="..." --type=bug|task
2. TDD      superpowers:test-driven-development
             RED: write failing test
             GREEN: minimal implementation to pass
             REFACTOR: clean up, tests still pass
3. REVIEW   superpowers:requesting-code-review
4. VERIFY   superpowers:verification-before-completion
5. COMMIT   Conventional commit
6. CLOSE    bd close <id>
```

---

## Bug Path

```
1. TASK     bd create --title="..." --type=bug
2. DEBUG    superpowers:systematic-debugging
             Root cause → reproduce → hypothesis → verify
3. TDD      superpowers:test-driven-development
             RED: write regression test that reproduces the bug
             GREEN: fix the bug, test passes
             REFACTOR: clean up
4. REVIEW   superpowers:requesting-code-review
5. VERIFY   superpowers:verification-before-completion
6. COMMIT   Conventional commit
7. CLOSE    bd close <id>
```

All bugs follow this path regardless of tier. Systematic debugging before TDD ensures you
understand the root cause before writing the fix.

---

## Medium+ Path

```
1. EPIC       bd create --title="..." --type=epic
2. BRAINSTORM superpowers:brainstorming
               Output: design doc in docs/superpowers/specs/
               bd update <epic-id> --notes "spec: <path>"
3. PLAN       superpowers:writing-plans
               Output: plan in docs/superpowers/plans/
               bd update <epic-id> --notes "plan: <path>"
4. SUB-TASKS  For each plan step:
               bd create --title="Step N: ..." --type=task
               bd dep add <sub-id> <epic-id>
               bd dep add <sub-id> <prev-sub-id>  (only if genuinely sequential)
               bd update <epic-id> --notes "planned-tasks: N"
5. SPIKE      Task 0: validate architecture assumptions (see spike-phase rule)
               bd update <epic-id> --notes "spike: <lightweight|deep>"
6. ISOLATE    superpowers:using-git-worktrees
7. IMPLEMENT  bd ready → claim ALL ready tasks (not just one)
               For independent ready tasks: dispatch parallel agents
               (superpowers:dispatching-parallel-agents)
               For each sub-task:
               ├─ Assess micro-tier (see Sub-task Micro-tiers rule)
               ├─ bd update <sub-id> --notes "micro-tier: <tier>"
               ├─ TDD per micro-tier (micro/full)
               ├─ Commit after each green
               ├─ Code review per micro-tier (individual/batch)
               └─ bd close <sub-id>
               Scope health check every 3 closed sub-tasks.
               Repeat until bd ready shows no more sub-tasks.
8. VERIFY     superpowers:verification-before-completion
9. FINISH     superpowers:finishing-a-development-branch
10. CLOSE     bd close <epic-id>
```

### Sub-task Dependencies

When creating sub-tasks from the plan:
- Default to independent (no deps between sub-tasks) unless one task genuinely
  needs another's output
- Only add `bd dep` when Task B literally cannot start without Task A's artifacts
  (schema it reads, interface it imports, config it loads)
- "Conceptually related" is NOT a dependency. Two endpoints that share a database
  table can be built in parallel — the table creation is the dependency, not the
  endpoints on each other

---

## Escalation

If work grows beyond current tier, stop and escalate:

- **Trivial → Small:** Add TDD and review before continuing.
- **Small → Medium+:** Stop. Create an epic, brainstorm, plan, decompose into sub-tasks. Then continue from step 6 (IMPLEMENT).

Never skip tiers downward.

---

## Side Quests

Discover something unrelated mid-work:

```
bd create --title="Found: <issue>" --type=bug
bd dep add <new-id> <current-id> --type=discovered-from
```

Don't context-switch. Finish current task, then `bd ready`.

---

## Plugin Roles

| Plugin | Role | Tiers |
|---|---|---|
| **Beads** | Task lifecycle: create, claim, dep, close | All |
| **Superpowers** | Process: brainstorm, plan, TDD, review, verify, debug, finish | Small, Medium+, Bug |
| **ECC** | Language/domain expertise within Superpowers process | All (as needed) |

Superpowers drives the process. ECC provides expertise within it.

---

## Anti-Patterns

- No code without a beads task
- No production code without a failing test (Small/Medium+)
- No completion claims without verification output
- No skipping tiers downward
- No trusting subagent reports without own verification
- No qualifier language ("should work", "probably fixed")
