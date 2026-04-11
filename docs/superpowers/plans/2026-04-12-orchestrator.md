# Orchestrator & Task Scaffolder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new skills (task-scaffolder, orchestrator) and update protocol templates to support the full impl→review→fix cycle with rigid enforcement.

**Architecture:** Two independent skills — scaffolder creates beads task structure from plans, orchestrator drives the execution loop. Protocol templates updated so implementer stops at ready-for-review (never closes) and reviewer returns structured reports (never creates tasks). Orchestrator is the single decision-maker for task creation, side-quest routing, and closure.

**Tech Stack:** Bash (hooks), Markdown (skills/templates), YAML (test specs)

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `skills/task-scaffolder/SKILL.md` | Skill: reads plan, creates beads tasks + dependency graph |
| `skills/orchestrator/SKILL.md` | Skill: drives impl→review→fix loop per task (RIGID) |
| `tests/specs/task-scaffolder.yaml` | Behavioral spec for scaffolder |
| `tests/specs/orchestrator.yaml` | Behavioral spec for orchestrator |

### Modified files

| File | Change |
|------|--------|
| `templates/protocol-implementer.md` | Remove `bd close`, add `tdd:ready-for-review` |
| `templates/protocol-reviewer.md` | Replace with report-only protocol |
| `skills/agent-roles/SKILL.md` | Add orchestrator role awareness |
| `skills/workflow/SKILL.md` | Update milestone chain, add `tdd:ready-for-review`, replace controller protocol with orchestrator reference |
| `CLAUDE.md` | Add orchestrator + scaffolder to quick reference |
| `README.md` | Add new skills to commands table + project structure |
| `tests/validate-config.sh` | Add checks for new skills, updated templates |
| `tests/test-behaviors.sh` | Add implementer ready-for-review milestone test, reviewer report format test |
| `.claude-plugin/plugin.json` | Bump version |
| `.claude-plugin/marketplace.json` | Bump version |
| `skills/*/SKILL.md` (all) | Bump version |

---

### Task 1: Update protocol-implementer.md

**Files:**
- Modify: `templates/protocol-implementer.md`

- [ ] **Step 1: Read current file**

Run: `cat templates/protocol-implementer.md`

Current content has `bd close <id>` at the end. This must be removed and replaced with `tdd:ready-for-review` handoff.

- [ ] **Step 2: Replace protocol-implementer.md with updated content**

Write the full file:

```markdown
# Implementer Bead Protocol

You are implementing code changes. Follow the full TDD milestone chain.

## Before ANY Code Changes

```bash
bd create --title="<task-description>" --type=task -p 2
bd dep add <new-id> <parent-id> --type parent-child
bd update <new-id> --claim
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] task:created sub-task for <description>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] task:claimed work started"
```

## During TDD — Update After EACH Phase

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:red <what test you wrote>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:red-verified <how it failed>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:green <what you implemented>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:green-verified <test output summary>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:refactor <what you cleaned up>"
```

Multiple TDD cycles allowed — repeat red→green as needed, then one refactor at end.

## After TDD Complete — Hand Off to Orchestrator

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:ready-for-review implementation complete"
```

**Do NOT close the task.** Return control to the orchestrator. Only the orchestrator closes tasks.

## SKIP NONE OF THESE

Your work will be rejected if milestones are missing. The orchestrator verifies every milestone after you return.

<!-- BEAD-PROTOCOL-v1:implementer -->
```

- [ ] **Step 3: Verify sentinel is preserved**

Run: `grep 'BEAD-PROTOCOL-v1:implementer' templates/protocol-implementer.md`
Expected: `<!-- BEAD-PROTOCOL-v1:implementer -->`

- [ ] **Step 4: Verify bd close is NOT present**

Run: `grep -c 'bd close' templates/protocol-implementer.md`
Expected: `0`

- [ ] **Step 5: Verify ready-for-review is present**

Run: `grep 'ready-for-review' templates/protocol-implementer.md`
Expected: matches on milestone line and section header

- [ ] **Step 6: Commit**

```bash
git add templates/protocol-implementer.md
git commit -m "feat: update implementer protocol — stop at ready-for-review, never close"
```

---

### Task 2: Update protocol-reviewer.md

**Files:**
- Modify: `templates/protocol-reviewer.md`

- [ ] **Step 1: Read current file**

Run: `cat templates/protocol-reviewer.md`

Current content has side-quest creation and milestone writing. Both must be removed. Reviewer becomes report-only.

- [ ] **Step 2: Replace protocol-reviewer.md with updated content**

Write the full file:

```markdown
# Reviewer Bead Protocol

You are reviewing code. Your ONLY output is a structured report. You do NOT create tasks, write milestones, or fix code.

## Self-Gather Context

Before reviewing, gather your own context:
- `git diff` to see what changed
- Read the spec file (path provided by orchestrator)
- Read modified files directly
- Check test coverage

## Structured Report Format

Return EXACTLY this format. The orchestrator parses it to decide next action.

```
REVIEW: <spec|quality>
TASK: <task-id>
VERDICT: PASS | BLOCKED

FINDINGS:
- [SEVERITY] category: description
```

### Severities

| Severity | Effect |
|----------|--------|
| CRITICAL | BLOCKED — security vulnerability, data loss risk |
| HIGH | BLOCKED — bug, significant quality issue |
| MEDIUM | BLOCKED — maintainability concern, test gap |
| LOW | PASS — minor suggestion, noted but not blocking |
| INFO | PASS — informational observation |

Any CRITICAL, HIGH, or MEDIUM finding → verdict MUST be BLOCKED.
Only LOW and INFO findings → verdict is PASS.
Zero findings → verdict is PASS with empty FINDINGS section.

### Categories

Use exactly one per finding: `code-bug`, `test-gap`, `style`, `design-flaw`, `architecture`, `security`

## Example: PASS Report

```
REVIEW: quality
TASK: claude-workstation-ab12
VERDICT: PASS

FINDINGS:
- [LOW] style: variable name `x` could be more descriptive in cache-utils.sh:45
- [INFO] code-bug: consider edge case when bd is unreachable (already handled by timeout)
```

## Example: BLOCKED Report

```
REVIEW: spec
TASK: claude-workstation-ab12
VERDICT: BLOCKED

FINDINGS:
- [HIGH] code-bug: milestone-gate does not check for ready-for-review phase
- [MEDIUM] test-gap: no test for cycle counter reset after successful review
- [LOW] style: inconsistent indentation in orchestrator skill lines 45-50
```

## Rules (Non-Negotiable)

1. **Report only.** Do NOT create beads tasks. Do NOT write milestones. Do NOT fix code.
2. **Use exact format.** Orchestrator parses your output. Free-text breaks the loop.
3. **Be specific.** "Code has issues" is not a finding. File, line, description required.
4. **Correct severity.** Do not inflate or deflate. MEDIUM means "should fix for maintainability."
5. **One category per finding.** Pick the most accurate one.

<!-- BEAD-PROTOCOL-v1:reviewer -->
```

- [ ] **Step 3: Verify sentinel is preserved**

Run: `grep 'BEAD-PROTOCOL-v1:reviewer' templates/protocol-reviewer.md`
Expected: `<!-- BEAD-PROTOCOL-v1:reviewer -->`

- [ ] **Step 4: Verify no bd create or bd dep add present**

Run: `grep -cE 'bd create|bd dep add' templates/protocol-reviewer.md`
Expected: `0`

- [ ] **Step 5: Verify report format is present**

Run: `grep 'VERDICT:' templates/protocol-reviewer.md`
Expected: multiple matches (format spec + examples)

- [ ] **Step 6: Commit**

```bash
git add templates/protocol-reviewer.md
git commit -m "feat: update reviewer protocol — report-only, no task creation"
```

---

### Task 3: Create task-scaffolder skill

**Files:**
- Create: `skills/task-scaffolder/SKILL.md`

- [ ] **Step 1: Create skill directory**

Run: `mkdir -p skills/task-scaffolder`

- [ ] **Step 2: Write the task-scaffolder skill**

Write `skills/task-scaffolder/SKILL.md`:

```markdown
---
name: task-scaffolder
version: 2.5.7
description: >
  Reads a plan and creates beads tasks with full dependency graph.
  TRIGGER: After plan is written, before implementation begins.
---

# Task Scaffolder

Transforms a plan document into a complete beads task structure. Does NOT execute anything.

## Type

**RIGID.** Follow every step. Do not skip. Do not rationalize.

## Input

Path to plan file (from `docs/superpowers/plans/`).

## Flow

Execute steps in order:

### Step 1: READ PLAN

Read the plan file. Identify:
- Plan title (from `# heading`)
- All `### Task N: <name>` sections
- Dependencies implied by task ordering (Task N+1 depends on Task N unless plan says otherwise)
- File paths in each task's `**Files:**` section to determine role

### Step 2: CREATE EPIC

```bash
bd create --type=epic --title="<plan title>"
```

Store the epic ID.

### Step 3: CREATE SUB-TASKS

For each `### Task N` in the plan:

```bash
bd create --type=task --title="Task N: <task name>"
bd dep add <sub-task-id> <epic-id> --type parent-child
```

Determine role from task content:
- Task modifies code files (`.sh`, `.py`, `.ts`, `.js`, `.go`, `.rs`, etc.) → `role:implementer`
- Task only modifies docs/config (`.md`, `.json`, `.yaml`, `.txt`) → `role:default`

Tag in notes:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <sub-task-id> "[M] task:created role:<role>"
```

### Step 4: WIRE DEPENDENCIES

For sequential tasks (Task N+1 depends on Task N):
```bash
bd dep add <task-N+1-id> <task-N-id> --type=blocks
```

If the plan specifies non-sequential dependencies (e.g., "Task 5 depends on Task 2"), wire those instead.

### Step 5: PRINT SUMMARY

Print the full task graph:

```
✓ Scaffolded: <epic-id> — <plan title>

Tasks:
  1. <task-1-id> — Task 1: <name> (role:implementer)
  2. <task-2-id> — Task 2: <name> (role:implementer)
  3. <task-3-id> — Task 3: <name> (role:default)
  ...

Dependencies:
  <task-2-id> blocked-by <task-1-id>
  <task-3-id> blocked-by <task-2-id>
  ...

→ Ready to implement. Choose:
  1) Subagent-driven (/superpowers:subagent-driven-development)
  2) Inline (/superpowers:executing-plans)
  3) Orchestrator (/claude-workstation:orchestrator)
```

### Step 6: RETURN CONTROL

Do NOT execute any task. Do NOT dispatch any agent. Return control to user.

## Does NOT

- Execute any task
- Dispatch any agent
- Choose implementation strategy
- Modify any files
- Write any code

## Anti-Rationalizations

| Thought | Answer |
|---------|--------|
| "I can see what needs to be done, let me start" | Create tasks only. Do not execute. |
| "This plan is simple, I'll skip the epic" | Every plan gets an epic. No exceptions. |
| "These tasks don't need dependencies" | Wire them. Sequential unless plan says otherwise. |
| "I'll assign roles later" | Tag now. Every task gets a role in notes. |
```

- [ ] **Step 3: Verify frontmatter**

Run: `head -7 skills/task-scaffolder/SKILL.md`
Expected: YAML frontmatter with name: task-scaffolder, version: 2.5.7

- [ ] **Step 4: Verify skill contains key sections**

Run: `grep -c '### Step' skills/task-scaffolder/SKILL.md`
Expected: `6`

- [ ] **Step 5: Commit**

```bash
git add skills/task-scaffolder/SKILL.md
git commit -m "feat: add task-scaffolder skill — plan-to-tasks transformer"
```

---

### Task 4: Create orchestrator skill

**Files:**
- Create: `skills/orchestrator/SKILL.md`

- [ ] **Step 1: Create skill directory**

Run: `mkdir -p skills/orchestrator`

- [ ] **Step 2: Write the orchestrator skill**

Write `skills/orchestrator/SKILL.md`:

```markdown
---
name: orchestrator
version: 2.5.7
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
```

- [ ] **Step 3: Verify frontmatter**

Run: `head -7 skills/orchestrator/SKILL.md`
Expected: YAML frontmatter with name: orchestrator, version: 2.5.7

- [ ] **Step 4: Verify all 13 rigid rules present**

Run: `grep -c '^[0-9]\+\.' skills/orchestrator/SKILL.md`
Expected: `13` (under Rigid Rules section)

- [ ] **Step 5: Verify all 8 anti-rationalizations present**

Run: `grep -c '"' skills/orchestrator/SKILL.md | head -1`
Expected: at least 8 rows in anti-rationalization table

- [ ] **Step 6: Commit**

```bash
git add skills/orchestrator/SKILL.md
git commit -m "feat: add orchestrator skill — rigid impl→review→fix cycle"
```

---

### Task 5: Update agent-roles skill

**Files:**
- Modify: `skills/agent-roles/SKILL.md`

- [ ] **Step 1: Read current file**

Run: `cat skills/agent-roles/SKILL.md`

- [ ] **Step 2: Add orchestrator context to the skill**

After the existing `## Examples` section, add a new section:

```markdown

## Orchestrator Context

When the orchestrator skill (`/claude-workstation:orchestrator`) is active, it dispatches all agents. The orchestrator:

- Dispatches **implementer** agents with `templates/protocol-implementer.md`
- Dispatches **reviewer** agents with `templates/protocol-reviewer.md`
- Dispatches **planner** agents with `templates/protocol-planner.md` (for design-flaw/architecture findings)
- Dispatches **build-fixer** agents with `templates/protocol-build-fixer.md`

The orchestrator itself uses `BEAD-ROLE:default` — it reads skills but does not match implementer/reviewer/planner/build-fixer roles.
```

- [ ] **Step 3: Verify the new section exists**

Run: `grep 'Orchestrator Context' skills/agent-roles/SKILL.md`
Expected: `## Orchestrator Context`

- [ ] **Step 4: Commit**

```bash
git add skills/agent-roles/SKILL.md
git commit -m "feat: add orchestrator context to agent-roles skill"
```

---

### Task 6: Update workflow skill

**Files:**
- Modify: `skills/workflow/SKILL.md`

- [ ] **Step 1: Read current enforcement milestones section**

Run: `sed -n '/## Enforcement Milestones/,/## /p' skills/workflow/SKILL.md`

- [ ] **Step 2: Add `tdd:ready-for-review` to milestone chain**

In the Enforcement Milestones table, add a new row after `tdd:refactor`:

```
| `tdd:ready-for-review` | tdd:refactor | Handed off to orchestrator for review |
```

The full table becomes:

| Phase | Prerequisite | Detail |
|-------|-------------|--------|
| `task:created` | — | Sub-task bead exists |
| `task:claimed` | task:created | Work started (`bd update --claim`) |
| `tdd:red` | task:claimed | Failing test written |
| `tdd:red-verified` | tdd:red | Test fails correctly |
| `tdd:green` | tdd:red-verified | Implementation passes |
| `tdd:green-verified` | tdd:green | All tests pass |
| `tdd:refactor` | tdd:green-verified | Cleanup complete |
| `tdd:ready-for-review` | tdd:refactor | Handed off to orchestrator for review |
| `review:spec` | tdd:ready-for-review | Spec compliance passed |
| `review:quality` | review:spec | Code quality review passed |
| `verified` | review:quality | Verification-before-completion done |

- [ ] **Step 3: Replace Controller Protocol with Orchestrator reference**

Replace the `## Controller Protocol` and `## Controller Verification (MANDATORY)` sections with:

```markdown
## Orchestrator Protocol

For automated execution, use `/claude-workstation:orchestrator`. The orchestrator:

- Dispatches implementer → waits for `tdd:ready-for-review`
- Dispatches spec reviewer → analyzes report
- Dispatches quality reviewer → analyzes report
- Creates blocking side-quests for MEDIUM+ findings
- Routes bugs to implementer, design flaws to planner
- Closes task only after both reviews pass
- Compacts every 3rd closure (persists state via `bd remember` first)

See `skills/orchestrator/SKILL.md` for the full rigid protocol.

For manual execution (subagent-driven-dev or inline), the main agent takes the orchestrator role and follows the same rules.
```

- [ ] **Step 4: Update reviewer description in Subagent Protocol table**

Change the reviewer row from:
```
| `protocol-reviewer.md` | Code review (findings + side-quests) |
```
To:
```
| `protocol-reviewer.md` | Code review (structured report only) |
```

- [ ] **Step 5: Verify changes**

Run: `grep 'ready-for-review' skills/workflow/SKILL.md`
Expected: matches in milestone table

Run: `grep 'Orchestrator Protocol' skills/workflow/SKILL.md`
Expected: section header present

Run: `grep -c 'Controller Protocol' skills/workflow/SKILL.md`
Expected: `0` (replaced)

- [ ] **Step 6: Commit**

```bash
git add skills/workflow/SKILL.md
git commit -m "feat: update workflow skill — add ready-for-review milestone, orchestrator protocol"
```

---

### Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read current CLAUDE.md**

Run: `cat CLAUDE.md`

- [ ] **Step 2: Add orchestrator and scaffolder to quick reference**

In the Quick Reference numbered list, after step 3 (Plan), add:

```
4. **Scaffold** -- `/claude-workstation:task-scaffolder` (create tasks from plan)
```

Renumber remaining steps (old 4→5, old 5→6, etc.). After the last step (Close), add:

```
   Or use `/claude-workstation:orchestrator` to automate steps 5-9.
```

- [ ] **Step 3: Update milestone chain in Milestone Format section**

Add `tdd:ready-for-review` between `tdd:refactor` and `review:spec`:

```
Phases: task:created → task:claimed → tdd:red → tdd:red-verified → tdd:green → tdd:green-verified → tdd:refactor → tdd:ready-for-review → review:spec → review:quality → verified
```

- [ ] **Step 4: Verify changes**

Run: `grep 'task-scaffolder' CLAUDE.md`
Expected: match

Run: `grep 'orchestrator' CLAUDE.md`
Expected: match

Run: `grep 'ready-for-review' CLAUDE.md`
Expected: match in milestone chain

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add orchestrator and task-scaffolder to CLAUDE.md quick reference"
```

---

### Task 8: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read current README.md**

Run: `cat README.md`

- [ ] **Step 2: Add new skills to commands table**

In the `## Commands & Skills` table, add two rows:

```
| `/claude-workstation:task-scaffolder` | Read plan, create beads tasks with dependency graph |
| `/claude-workstation:orchestrator` | Automated impl→review→fix cycle (rigid protocol) |
```

- [ ] **Step 3: Add new skill directories to project structure**

In the `## Project Structure` tree under `skills/`, add:

```
│   ├── orchestrator/SKILL.md  # /orchestrator -- automated impl→review→fix cycle
│   ├── task-scaffolder/SKILL.md # /task-scaffolder -- plan-to-tasks transformer
```

- [ ] **Step 4: Verify changes**

Run: `grep 'task-scaffolder' README.md`
Expected: matches in commands table and project structure

Run: `grep 'orchestrator' README.md`
Expected: matches in commands table and project structure

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add orchestrator and task-scaffolder to README"
```

---

### Task 9: Create behavioral spec files

**Files:**
- Create: `tests/specs/task-scaffolder.yaml`
- Create: `tests/specs/orchestrator.yaml`

- [ ] **Step 1: Write task-scaffolder spec**

Write `tests/specs/task-scaffolder.yaml`:

```yaml
id: task-scaffolder
name: Task Scaffolder
source_rule: skills/task-scaffolder/SKILL.md
version: "1.0"

steps:
  - id: read_plan
    description: "Read plan file and identify task sections"
    required: true
    detector:
      description: "Skill reads plan file, extracts Task N sections"

  - id: create_epic
    description: "Create epic task as parent"
    required: true
    detector:
      description: "bd create --type=epic with plan title"
      after_step: read_plan

  - id: create_subtasks
    description: "Create sub-task for each plan task with parent-child dep"
    required: true
    detector:
      description: "bd create + bd dep add parent-child for each task"
      after_step: create_epic

  - id: wire_blocks
    description: "Wire blocks dependencies between sequential tasks"
    required: true
    detector:
      description: "bd dep add --type=blocks for task ordering"
      after_step: create_subtasks

  - id: tag_roles
    description: "Tag each task with role in notes"
    required: true
    detector:
      description: "[M] task:created role:<role> in notes"
      after_step: create_subtasks

  - id: print_summary
    description: "Print task graph summary"
    required: true
    detector:
      description: "Output lists all tasks, deps, and execution options"
      after_step: wire_blocks

  - id: no_execution
    description: "Does not execute any task or dispatch any agent"
    required: true
    detector:
      description: "Skill returns control to user without executing"

scoring:
  threshold_promote_to_hook: 0.8
```

- [ ] **Step 2: Write orchestrator spec**

Write `tests/specs/orchestrator.yaml`:

```yaml
id: orchestrator
name: Orchestrator Loop
source_rule: skills/orchestrator/SKILL.md
version: "1.0"

steps:
  - id: activate_caveman
    description: "Activate caveman full mode as first action"
    required: true
    detector:
      description: "/caveman full invoked before any other action"

  - id: pick_task
    description: "Pick ready task from bd ready"
    required: true
    detector:
      description: "bd ready → select first available task"
      after_step: activate_caveman

  - id: dispatch_implementer
    description: "Dispatch implementer with protocol template"
    required: true
    detector:
      description: "Agent dispatched with protocol-implementer.md content"
      after_step: pick_task

  - id: verify_implementer
    description: "Check implementer left tdd:ready-for-review milestone"
    required: true
    detector:
      description: "bd show <id> → check [M] tdd:ready-for-review present"
      after_step: dispatch_implementer

  - id: dispatch_spec_review
    description: "Dispatch spec reviewer with protocol template"
    required: true
    detector:
      description: "Agent dispatched with protocol-reviewer.md, type=spec"
      after_step: verify_implementer

  - id: analyze_spec_report
    description: "Parse spec review report, route findings"
    required: true
    detector:
      description: "Parse VERDICT, create side-quests for MEDIUM+ findings"
      after_step: dispatch_spec_review

  - id: dispatch_quality_review
    description: "Dispatch quality reviewer with protocol template"
    required: true
    detector:
      description: "Agent dispatched with protocol-reviewer.md, type=quality"
      after_step: analyze_spec_report

  - id: analyze_quality_report
    description: "Parse quality review report, route findings"
    required: true
    detector:
      description: "Parse VERDICT, create side-quests for MEDIUM+ findings"
      after_step: dispatch_quality_review

  - id: close_task
    description: "Close task after both reviews pass"
    required: true
    detector:
      description: "bd close <id> only after spec + quality PASS"
      after_step: analyze_quality_report

  - id: compact_trigger
    description: "Check compact trigger every 3rd closure"
    required: true
    detector:
      description: "closure_counter % 3 == 0 → bd remember + /ecc:strategic-compact"
      after_step: close_task

  - id: cycle_limit
    description: "Max 3 cycles per review type before escalation"
    required: true
    detector:
      description: "cycle > 3 → bd human <id>, stop task"

  - id: side_quest_blocks
    description: "Side-quests use blocks dep, not discovered-from"
    required: true
    detector:
      description: "bd dep add <parent> <bug> --type=blocks"

scoring:
  threshold_promote_to_hook: 0.8
```

- [ ] **Step 3: Verify both specs are valid YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('tests/specs/task-scaffolder.yaml')); print('valid')" && python3 -c "import yaml; yaml.safe_load(open('tests/specs/orchestrator.yaml')); print('valid')"`
Expected: `valid` twice

- [ ] **Step 4: Commit**

```bash
git add tests/specs/task-scaffolder.yaml tests/specs/orchestrator.yaml
git commit -m "test: add behavioral specs for task-scaffolder and orchestrator"
```

---

### Task 10: Update validate-config.sh

**Files:**
- Modify: `tests/validate-config.sh`

- [ ] **Step 1: Read current skill directory checks**

Run: `grep -n 'skill_dir\|skill_name\|SKILL.md' tests/validate-config.sh | head -20`

Identify the loops that check skill directories (sections 8, 9, 13b, 14).

- [ ] **Step 2: Add new skills to section 8 (Skill directories)**

Change the loop from:
```bash
for skill_dir in start workflow; do
```
To:
```bash
for skill_dir in start workflow task-scaffolder orchestrator agent-roles; do
```

This appears in both section 8 and section 9. Update both.

- [ ] **Step 3: Add new spec files to section 24 (Behavioral spec files)**

Change the loop from:
```bash
for spec_name in bd-notes-append scope-health start; do
```
To:
```bash
for spec_name in bd-notes-append scope-health start task-scaffolder orchestrator; do
```

- [ ] **Step 4: Add implementer protocol check**

After section 12.4 (sentinel checks), add:

```bash
# 12.9 protocol-implementer.md does NOT contain bd close
if grep -q 'bd close' "$PLUGIN_ROOT/templates/protocol-implementer.md"; then
    fail "12.9 protocol-implementer.md still contains 'bd close'"
else
    pass "12.9 protocol-implementer.md does not contain 'bd close'"
fi

# 12.10 protocol-implementer.md contains ready-for-review
if grep -q 'ready-for-review' "$PLUGIN_ROOT/templates/protocol-implementer.md"; then
    pass "12.10 protocol-implementer.md contains 'ready-for-review'"
else
    fail "12.10 protocol-implementer.md missing 'ready-for-review'"
fi

# 12.11 protocol-reviewer.md does NOT contain bd create
if grep -qE 'bd create|bd dep add' "$PLUGIN_ROOT/templates/protocol-reviewer.md"; then
    fail "12.11 protocol-reviewer.md still contains task creation commands"
else
    pass "12.11 protocol-reviewer.md is report-only (no task creation)"
fi

# 12.12 protocol-reviewer.md contains VERDICT format
if grep -q 'VERDICT:' "$PLUGIN_ROOT/templates/protocol-reviewer.md"; then
    pass "12.12 protocol-reviewer.md contains structured report format"
else
    fail "12.12 protocol-reviewer.md missing VERDICT report format"
fi
```

- [ ] **Step 5: Run validation**

Run: `bash tests/validate-config.sh 2>&1 | tail -10`
Expected: all new checks pass (some may fail until all tasks complete)

- [ ] **Step 6: Commit**

```bash
git add tests/validate-config.sh
git commit -m "test: add validation checks for orchestrator, scaffolder, updated protocols"
```

---

### Task 11: Update test-behaviors.sh

**Files:**
- Modify: `tests/test-behaviors.sh`

- [ ] **Step 1: Read end of current test file for insertion point**

Run: `tail -30 tests/test-behaviors.sh`

- [ ] **Step 2: Add implementer protocol tests before the summary section**

Before the `=== Behavioral Test Summary ===` line, add:

```bash
echo ""

# ---------------------------------------------------------------------------
# Section 17: Protocol template content validation
# ---------------------------------------------------------------------------
echo "17. Protocol template content"

# 17a. protocol-implementer.md does NOT contain bd close
if grep -q 'bd close' "$PLUGIN_ROOT/templates/protocol-implementer.md"; then
    fail "17a. protocol-implementer.md still contains 'bd close'"
else
    pass "17a. protocol-implementer.md has no 'bd close' (implementer never closes)"
fi

# 17b. protocol-implementer.md contains ready-for-review milestone
if grep -q 'tdd:ready-for-review' "$PLUGIN_ROOT/templates/protocol-implementer.md"; then
    pass "17b. protocol-implementer.md contains tdd:ready-for-review milestone"
else
    fail "17b. protocol-implementer.md missing tdd:ready-for-review milestone"
fi

# 17c. protocol-reviewer.md does NOT contain bd create or bd dep add
if grep -qE 'bd create|bd dep add' "$PLUGIN_ROOT/templates/protocol-reviewer.md"; then
    fail "17c. protocol-reviewer.md still contains task creation commands"
else
    pass "17c. protocol-reviewer.md is report-only (no task creation)"
fi

# 17d. protocol-reviewer.md contains VERDICT format
if grep -q 'VERDICT: PASS | BLOCKED' "$PLUGIN_ROOT/templates/protocol-reviewer.md"; then
    pass "17d. protocol-reviewer.md contains structured VERDICT format"
else
    fail "17d. protocol-reviewer.md missing structured VERDICT format"
fi

# 17e. protocol-reviewer.md contains all severity levels
for sev in CRITICAL HIGH MEDIUM LOW INFO; do
    if grep -q "$sev" "$PLUGIN_ROOT/templates/protocol-reviewer.md"; then
        pass "17e. protocol-reviewer.md contains severity $sev"
    else
        fail "17e. protocol-reviewer.md missing severity $sev"
    fi
done

# 17f. protocol-reviewer.md contains all categories
for cat in code-bug test-gap style design-flaw architecture security; do
    if grep -q "$cat" "$PLUGIN_ROOT/templates/protocol-reviewer.md"; then
        pass "17f. protocol-reviewer.md contains category $cat"
    else
        fail "17f. protocol-reviewer.md missing category $cat"
    fi
done
```

- [ ] **Step 3: Run behavioral tests**

Run: `bash tests/test-behaviors.sh 2>&1 | tail -15`
Expected: new tests pass (17a-17f)

- [ ] **Step 4: Commit**

```bash
git add tests/test-behaviors.sh
git commit -m "test: add protocol template behavioral tests"
```

---

### Task 12: Version bump and final verification

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `skills/*/SKILL.md` (all 5)

- [ ] **Step 1: Bump version in all locations**

Current: 2.5.7 → New: 2.6.0 (minor bump: new skills + behavioral changes)

```bash
sed -i 's/"version": "2.5.7"/"version": "2.6.0"/g' .claude-plugin/plugin.json .claude-plugin/marketplace.json
for f in skills/*/SKILL.md; do sed -i "s/^version: 2.5.7/version: 2.6.0/" "$f"; done
```

- [ ] **Step 2: Verify version sync**

Run: `bash tests/validate-config.sh 2>&1 | grep -E "version|Summary|Passed|Failed"`
Expected: all skills match plugin version 2.6.0

- [ ] **Step 3: Run full test suite**

Run: `bash tests/validate-config.sh 2>&1 | tail -5`
Expected: all checks pass

Run: `bash tests/test-behaviors.sh 2>&1 | tail -5`
Expected: all behavioral tests pass

- [ ] **Step 4: Commit and push**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json skills/*/SKILL.md
git commit -m "chore: bump version to 2.6.0"
git push
```
