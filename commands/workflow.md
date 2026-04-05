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

**Or use `/claude-workstation:analyze`** to auto-assess the tier, create the task, and start the right flow in one step.

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

## Medium+ Path

```
1. EPIC       bd create --title="..." --type=epic
2. BRAINSTORM superpowers:brainstorming
               Output: design doc in docs/superpowers/specs/
               bd update <epic-id> --notes "Spec: <path>"
3. PLAN       superpowers:writing-plans
               Output: plan in docs/superpowers/plans/
               bd update <epic-id> --notes "Plan: <path>, N sub-tasks"
4. SUB-TASKS  For each plan step:
               bd create --title="Step N: ..." --type=task
               bd dep add <sub-id> <epic-id>
               bd dep add <sub-id> <prev-sub-id>  (if sequential)
5. ISOLATE    superpowers:using-git-worktrees
6. IMPLEMENT  bd ready → pick next → bd update <sub-id> -s in_progress
               For each sub-task:
               ├─ superpowers:test-driven-development
               ├─ Commit after each green
               ├─ bd update <sub-id> --notes "Tests passing: <summary>"
               ├─ superpowers:requesting-code-review
               └─ bd close <sub-id>
               Repeat until bd ready shows no more sub-tasks.
7. VERIFY     superpowers:verification-before-completion
8. FINISH     superpowers:finishing-a-development-branch
9. CLOSE      bd close <epic-id>
```

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
| **Superpowers** | Process: brainstorm, plan, TDD, review, verify, debug, finish | Small, Medium+ |
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
