---
name: orchestrator
version: 2.6.0
description: >
  Drives the impl→review→fix cycle per task. RIGID protocol.
  TRIGGER: After task-scaffolder creates tasks, user chooses orchestrator mode.
---

# Orchestrator

Drives the full implementation→review→fix cycle for each task. Single point of control for all dispatching, task creation, and closure decisions.

## Type

**RIGID.** Every step mandatory. No rationalization. No shortcuts. Same enforcement level as TDD skill. Read every word. Follow every rule.

## First Action

Activate caveman full mode BEFORE anything else:

```
/caveman full
```

All orchestrator output compressed. Exception: beads titles/descriptions stay normal (human-scannable).

## Main Loop

Repeat until `bd ready` returns no tasks:

### Step 1: PICK TASK

```bash
bd ready
```

Pick the first available task. If no tasks ready, the plan is complete — go to COMPLETION below.

### Step 2: CLAIM TASK

```bash
bd update <task-id> --claim
```

Initialize cycle counters: `spec_cycles=0`, `quality_cycles=0`.

### Step 3: DISPATCH IMPLEMENTER

Read `templates/protocol-implementer.md`. Include its full content in the subagent prompt along with:
- Task ID
- Task description (from `bd show <task-id>`)
- Spec path (from epic notes or plan file)

Dispatch implementer subagent. Wait for return.

Log milestone:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:dispatched-impl:<task-id>"
```

### Step 4: VERIFY IMPLEMENTER

After implementer returns:

```bash
bd show <task-id>
```

Check notes contain `[M] tdd:ready-for-review`. If missing:
- Log: `[M] orchestrator:rejected:<task-id> missing ready-for-review`
- Re-dispatch implementer (Step 3). This does NOT count toward cycle limit.

### Step 5: DISPATCH SPEC REVIEWER

Read `templates/protocol-reviewer.md`. Include its full content in the subagent prompt along with:
- Task ID
- Review type: `spec`
- Spec path

Dispatch reviewer subagent. Wait for return.

Log milestone:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:dispatched-review-spec:<task-id>"
```

### Step 6: ANALYZE SPEC REVIEW REPORT

Parse the reviewer's structured report.

**If VERDICT: PASS:**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:review-passed:<task-id> spec"
```
Continue to Step 7.

**If VERDICT: BLOCKED:**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:review-blocked:<task-id> spec <N> findings"
```
Increment `spec_cycles`. Check cycle limit (see CYCLE LIMIT below).

For each CRITICAL, HIGH, or MEDIUM finding:

1. Route based on category:
   - `code-bug`, `test-gap`, `style`, `security` → implementer
   - `design-flaw`, `architecture` → planner

2. Create blocking side-quest:
   ```bash
   bd create --title="Found: <finding description>" --type=bug
   bd dep add <task-id> <bug-id> --type=blocks
   bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:side-quest-created:<bug-id> blocks <task-id>"
   ```

3. Dispatch appropriate agent for each bug (sequentially, one at a time):
   - Implementer bugs: full TDD cycle (dispatch with protocol-implementer.md)
   - Planner bugs: dispatch with protocol-planner.md

4. After ALL bug side-quests closed → re-dispatch spec reviewer on parent task (back to Step 5).

### Step 7: DISPATCH QUALITY REVIEWER

Same as Step 5 but with review type: `quality`.

Log milestone:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:dispatched-review-quality:<task-id>"
```

### Step 8: ANALYZE QUALITY REVIEW REPORT

Same logic as Step 6 but using `quality_cycles` counter.

**If VERDICT: PASS:**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:review-passed:<task-id> quality"
```
Continue to Step 9.

**If VERDICT: BLOCKED:** Same routing as Step 6. After all bugs fixed → re-dispatch quality reviewer (back to Step 7).

### Step 9: CLOSE TASK

```bash
bd close <task-id>
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:closed:<task-id> all reviews passed (closure #<N>)"
```

Increment `closure_counter`.

### Step 10: CHECK COMPACT TRIGGER

```
If closure_counter % 3 == 0:
  → Go to COMPACT below
Else:
  → Go to Step 1 (next task)
```

---

## CYCLE LIMIT

**Max 3 cycles per review type per task.**

After incrementing a cycle counter, check:

```
If spec_cycles > 3 OR quality_cycles > 3:
  bd human <task-id>
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] orchestrator:escalated:<task-id> max cycles reached"
  STOP. Do not continue with this task. Move to next task (Step 1).
```

---

## COMPACT

Before invoking strategic-compact, persist full state:

```bash
bd remember "orchestrator-state: plan=<plan-path> epic=<epic-id> completed=[<closed-ids>] current=<task-id> next=[<ready-ids>] cycle-counts={spec:<N>,quality:<N>} closure-count=<N>"
```

Log milestone:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <epic-id> "[M] orchestrator:compact triggered at closure #<N>"
```

Then invoke:
```
/ecc:strategic-compact
```

## RESUME AFTER COMPACTION

```bash
bd memories orchestrator
bd show <epic-id>
bd ready
```

Reconstruct: plan path, epic ID, completed tasks, cycle counters, closure counter. Continue from Step 1.

---

## COMPLETION

When `bd ready` returns no tasks:

```bash
bd show <epic-id>
```

Verify all sub-tasks are closed. If any are open/blocked/escalated, report to user.

If all closed:
```
✓ Plan complete. All tasks implemented and reviewed.
  Epic: <epic-id>
  Tasks closed: <N>
  Cycles used: <summary>
```

---

## Rigid Rules (All Non-Negotiable)

1. Every task gets spec review → quality review. No exceptions.
2. MEDIUM+ findings = BLOCKED. MUST NOT downgrade or ignore.
3. Side-quests use `blocks` dep. Not `discovered-from`. Not `related`.
4. Max 3 cycles per review type. Hit 3 → `bd human` → stop.
5. Implementer never closes tasks. Only orchestrator closes.
6. Reviewer never creates tasks. Only orchestrator creates.
7. Reviewer never fixes code. Report only.
8. Orchestrator never writes code. Dispatches only.
9. Sequential reviews. Spec first, quality second. No parallel.
10. Bug fixes get full TDD. No "small fix, just patch it."
11. Strategic compact every 3rd closure. Rigid counter.
12. Persist state before every compaction. No compacting without `bd remember`.
13. Activate caveman full mode as first action.

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
