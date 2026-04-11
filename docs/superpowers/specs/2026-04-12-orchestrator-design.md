# Orchestrator & Task Scaffolder Design

**Date:** 2026-04-12
**Task:** claude-workstation-gghs
**Status:** Approved via brainstorming

---

## Problem

Current workflow has gaps:

1. **No automated task creation from plans.** After planning, tasks are created manually. No dependency graph wiring.
2. **Implementer closes tasks prematurely.** Protocol tells implementer to `bd close` before review happens.
3. **Reviewer creates side-quests directly.** No single point of control for task creation decisions.
4. **`discovered-from` deps don't block.** Review bugs float as disconnected side-quests. Nothing prevents parent task completion.
5. **No impl→review→fix cycle.** When reviewer finds bugs, no mechanism sends work back to implementer.
6. **No context survival across compaction.** Orchestration state lost when strategic-compact runs.

## Solution

Two new skills:

1. **Task Scaffolder** (`skills/task-scaffolder/SKILL.md`) — reads plan, creates beads tasks with full dependency graph. Runs once after planning, before implementation.
2. **Orchestrator** (`skills/orchestrator/SKILL.md`) — drives the impl→review→fix cycle per task. Picks ready tasks, dispatches agents, analyzes reports, creates side-quests, re-dispatches. Rigid protocol.

Plus protocol template updates to match.

---

## Skill 1: Task Scaffolder

### Purpose

Transforms a plan document into a complete beads task structure. Does NOT execute anything.

### Trigger

After plan is written (`docs/superpowers/plans/`), before user chooses subagent-driven-dev or inline implementation.

### Input

Path to plan file.

### Output

- Epic task (parent)
- Sub-tasks with `parent-child` deps to epic
- `blocks` deps between sub-tasks based on plan ordering
- Each task tagged in notes with role: `[M] task:created role:<role>` (implementer for code tasks, default for docs/config)

### Behavior

1. Read plan file
2. Parse sub-tasks and their dependencies
3. Create epic: `bd create --type=epic --title="<plan title>"`
4. For each sub-task:
   - `bd create --type=task --title="<sub-task title>"`
   - `bd dep add <sub> <epic> --type parent-child`
5. Wire `blocks` deps between sub-tasks per plan ordering
6. Tag each task with role in notes
7. Print summary of created tasks and dependency graph
8. Return control to user for implementation choice

### Does NOT

- Execute any task
- Dispatch any agent
- Choose implementation strategy

---

## Skill 2: Orchestrator

### Purpose

Drives the full implementation→review→fix cycle for each task. Single point of control for all dispatching, task creation, and closure decisions.

### Type

**RIGID.** Every step mandatory. No rationalization. No shortcuts. Same enforcement level as TDD skill.

### First Action

Activate caveman full mode: `/caveman full`. All orchestrator output compressed. Exception: beads titles/descriptions stay normal (human-scannable).

### Loop Per Task

```
1. bd ready → pick task
2. bd update <id> --claim
3. Dispatch implementer
   → TDD: red→green→refactor→ready-for-review (STOP)
4. Dispatch spec reviewer
   → Returns structured report
   → Orchestrator analyzes report
   → BLOCKED: create side-quest bugs, route + fix + re-review
   → PASS: continue
5. Dispatch quality reviewer
   → Same analysis pattern
   → BLOCKED: create side-quest bugs, route + fix + re-review
   → PASS: close task
6. bd close <id>
7. Increment closure counter
8. If counter % 3 == 0: persist state → /ecc:strategic-compact
9. bd ready → next task
```

### Reviewer Report Format

Reviewers return structured reports. Orchestrator parses these to decide next action.

```
REVIEW: <spec|quality>
TASK: <task-id>
VERDICT: PASS | BLOCKED

FINDINGS:
- [CRITICAL] <category>: <description>
- [HIGH] <category>: <description>
- [MEDIUM] <category>: <description>
- [LOW] <category>: <description>
- [INFO] <category>: <description>
```

**Categories:** `code-bug`, `test-gap`, `style`, `design-flaw`, `architecture`, `security`

**Verdict rules (rigid):**

| Severity | Effect |
|----------|--------|
| CRITICAL, HIGH, MEDIUM | BLOCKED |
| LOW, INFO | PASS (noted, not blocking) |

Any CRITICAL, HIGH, or MEDIUM finding → verdict MUST be BLOCKED. Orchestrator MUST NOT override.

Zero findings → PASS with empty FINDINGS section.

### Finding Routing (Rigid)

| Category | Routes to |
|----------|-----------|
| `code-bug`, `test-gap`, `style`, `security` | implementer |
| `design-flaw`, `architecture` | planner |

### Side-Quest Blocking Mechanics

When orchestrator creates bug side-quests from BLOCKED findings:

1. `bd create --title="Found: <description>" --type=bug`
2. `bd dep add <parent-task> <bug-id> --type=blocks`
3. Dispatch appropriate agent (implementer or planner) for bug task
4. Bug tasks are sequential — one at a time, not parallelized
5. Bug fixes go through full TDD cycle (red→green→refactor→ready-for-review)
6. After all bug side-quests closed → re-dispatch same review type on parent
7. Re-review either passes or creates new side-quests (new cycle)

### Cycle Limit

**Max 3 cycles per review type per task.** Cycle = fix round → re-review.

- Cycle 1: initial review → blocked → fix → re-review
- Cycle 2: re-review → blocked again → fix → re-review
- Cycle 3: re-review → blocked again → fix → re-review
- Cycle 4: STOP. `bd human <id>` → escalate to human. Do not continue.

### Strategic Compact Integration

**Every 3rd task closure, orchestrator MUST compact.**

```
Orchestrator closes task → counter++
If counter % 3 == 0:
  1. Persist state via bd remember (BEFORE compacting)
  2. Invoke /ecc:strategic-compact
```

### Pre-Compaction State Persistence

Before compacting, orchestrator MUST save full state:

```bash
bd remember "orchestrator-state: plan=<plan-path> epic=<epic-id> completed=[<closed-ids>] current=<task-id> next=[<ready-ids>] cycle-counts={<task-id>:<N>} closure-count=<N>"
```

**What's saved:**
- Plan file path
- Epic task ID
- Which tasks are done (closed IDs)
- Current task being worked
- What's next in the queue (ready IDs)
- Cycle counters per review type per task
- Total closure counter (for compact trigger)

**On resume after compaction:**

```bash
bd memories orchestrator
bd show <epic-id>
bd ready
```

Reconstructs full state from beads memory + task graph.

**Rigid.** Orchestrator MUST NOT compact without persisting state first.

### Orchestrator Milestones

```
[M] orchestrator:dispatched-impl:<task-id>
[M] orchestrator:dispatched-review-spec:<task-id>
[M] orchestrator:dispatched-review-quality:<task-id>
[M] orchestrator:review-passed:<task-id> <type>
[M] orchestrator:review-blocked:<task-id> <type> <N findings>
[M] orchestrator:side-quest-created:<bug-id> blocks <task-id>
[M] orchestrator:cycle:<N>:<task-id> re-dispatching after fix
[M] orchestrator:escalated:<task-id> max cycles reached
[M] orchestrator:closed:<task-id> all reviews passed (closure #N)
[M] orchestrator:compact triggered at closure #N
```

---

## Protocol Template Changes

### protocol-implementer.md

- Remove `bd close <id>` at the end
- After `tdd:refactor`, implementer writes: `[M] tdd:ready-for-review`
- Add: "Return control to orchestrator. Do NOT close the task."
- Implementer milestone chain: `task:claimed → tdd:red → tdd:red-verified → tdd:green → tdd:green-verified → tdd:refactor → tdd:ready-for-review`

### protocol-reviewer.md

- Remove all side-quest creation (orchestrator's job)
- Remove milestone writing (orchestrator tracks milestones)
- Reviewer's only output: structured report in the format specified above
- Reviewer self-gathers context (git diff, reads files, checks spec)
- Reviewer MUST NOT create tasks, write milestones, or fix code

---

## Rigid Rules (All Non-Negotiable)

1. Every task gets spec review → quality review. No exceptions.
2. MEDIUM+ findings = BLOCKED. Orchestrator MUST NOT downgrade or ignore.
3. Side-quests use `blocks` dep. Not `discovered-from`. Not `related`. Bugs block.
4. Max 3 cycles per review type. Hit 3 → `bd human` → stop.
5. Implementer never closes tasks. Only orchestrator closes.
6. Reviewer never creates tasks. Only orchestrator creates.
7. Reviewer never fixes code. Report only.
8. Orchestrator never writes code. Dispatches only.
9. Sequential reviews. Spec first, quality second. No parallel.
10. Bug fixes get full TDD. No "small fix, just patch it."
11. Strategic compact every 3rd closure. Rigid counter.
12. Persist state before every compaction. No compacting without `bd remember`.
13. Orchestrator activates caveman full mode as first action.

## Anti-Rationalizations

| Thought | Answer |
|---------|--------|
| "This task is too simple for review" | Every task. No exceptions. |
| "It's just one MEDIUM finding" | BLOCKED. Create side-quest. |
| "I can fix this faster than dispatching" | You dispatch. Period. |
| "The reviewer already knows the fix" | Reviewer reports. Implementer fixes. |
| "Three cycles is wasteful, it's almost done" | Escalate to human. |
| "This bug is trivial, skip TDD" | Full TDD. No shortcuts. |
| "Context is fine, skip bd remember" | Persist state. Then compact. |
| "Caveman mode wastes time activating" | First action. Non-negotiable. |

---

## Scope

### In scope

- `skills/task-scaffolder/SKILL.md` — new skill
- `skills/orchestrator/SKILL.md` — new skill
- `templates/protocol-implementer.md` — update (remove close, add ready-for-review)
- `templates/protocol-reviewer.md` — update (report-only, no task creation)
- `skills/agent-roles/SKILL.md` — add orchestrator awareness
- `skills/workflow/SKILL.md` — update milestone chain, reference orchestrator
- `tests/validate-config.sh` — add checks for new skills
- `tests/test-behaviors.sh` — add orchestrator milestone validation

### Out of scope

- Parallel task execution (sequential for v1)
- Security review as third review type (future)
- Custom review sequences per task type (all tasks same flow)
- Automatic plan parsing heuristics (scaffolder reads structured plans)
