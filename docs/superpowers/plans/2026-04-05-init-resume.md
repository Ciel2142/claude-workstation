# Init Rename + Resume Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the `analyze` skill to `init` (with tier persistence), create a new `resume` skill for resuming open work, add a systematic debugging rule, and update all documentation.

**Architecture:** Five independent-ish tasks: (1) rename skill directory + update SKILL.md, (2) update all cross-references, (3) create resume SKILL.md, (4) add debugging rule + workflow section, (5) update README/CLAUDE.md for everything. Tasks 1→2 are sequential; 3 and 4 are independent; 5 depends on all others.

**Tech Stack:** Markdown skill files (SKILL.md), beads CLI (`bd`), git

---

### Task 1: Rename analyze skill to init

**Beads:** claude-workstation-9jm

**Files:**
- Delete: `skills/analyze/SKILL.md`
- Create: `skills/init/SKILL.md`

- [ ] **Step 1: Create the init skill directory**

```bash
mkdir -p skills/init
```

- [ ] **Step 2: Copy analyze SKILL.md to init and delete the original**

```bash
cp -f skills/analyze/SKILL.md skills/init/SKILL.md
rm -rf skills/analyze
```

- [ ] **Step 3: Update the frontmatter**

In `skills/init/SKILL.md`, change the YAML frontmatter from:

```yaml
---
name: analyze
version: 1.0.0
description: >
  Auto-assess task tier and start the right workflow. Takes a description,
  scores it, creates the beads task, and invokes the first skill.
  TRIGGER: When starting any new work, or when the user describes a task.
---
```

to:

```yaml
---
name: init
version: 1.1.0
description: >
  Auto-assess task tier and start the right workflow. Takes a description,
  scores it, creates the beads task, and invokes the first skill.
  TRIGGER: When starting any new work, or when the user describes a task.
---
```

- [ ] **Step 4: Update the title and all internal references**

In `skills/init/SKILL.md`, replace:

1. Title: `# Analyze: Auto-Tier Assessment & Workflow Routing` → `# Init: Auto-Tier Assessment & Workflow Routing`
2. All invocation examples: `/claude-workstation:analyze` → `/claude-workstation:init` (3 occurrences in the Invocation section)

- [ ] **Step 5: Add tier persistence to the ROUTE step**

In `skills/init/SKILL.md`, in Step 5 (CREATE), after the `bd update <task-id> -s in_progress` block, add:

```markdown
Then persist the computed tier for use by `/resume`:
```bash
bd update <task-id> --notes "tier: <trivial|small|medium+>"
```
```

- [ ] **Step 6: Verify the skill file**

```bash
head -5 skills/init/SKILL.md
# Expected: YAML frontmatter with name: init
grep -c "claude-workstation:init" skills/init/SKILL.md
# Expected: 3
grep -c "claude-workstation:analyze" skills/init/SKILL.md
# Expected: 0
test ! -d skills/analyze && echo "OK: old directory removed" || echo "FAIL: old directory still exists"
```

- [ ] **Step 7: Commit**

```bash
git add skills/init/SKILL.md
git rm -r skills/analyze/ 2>/dev/null || true
git add -A skills/analyze/
git commit -m "feat: rename analyze skill to init with tier persistence"
```

---

### Task 2: Update all cross-references from analyze to init

**Beads:** claude-workstation-j35
**Depends on:** Task 1

**Files:**
- Modify: `CLAUDE.md`
- Modify: `commands/workflow.md`

Note: README.md is handled in Task 5 along with the resume documentation.

- [ ] **Step 1: Update CLAUDE.md**

In `CLAUDE.md`, replace line 11:

```markdown
Run `/claude-workstation:analyze "description"` to auto-assess task tier, create the beads task, and start the right workflow in one step.
```

with:

```markdown
Run `/claude-workstation:init "description"` to auto-assess task tier, create the beads task, and start the right workflow in one step.
```

- [ ] **Step 2: Update commands/workflow.md**

In `commands/workflow.md`, replace line 17:

```markdown
**Or use `/claude-workstation:analyze`** to auto-assess the tier, create the task, and start the right flow in one step.
```

with:

```markdown
**Or use `/claude-workstation:init`** to auto-assess the tier, create the task, and start the right flow in one step.
```

- [ ] **Step 3: Verify no stale references remain (excluding historical docs)**

```bash
grep -r "claude-workstation:analyze" --include="*.md" . | grep -v "docs/superpowers/"
# Expected: no output (all references updated, historical docs excluded)
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md commands/workflow.md
git commit -m "refactor: update all analyze references to init"
```

---

### Task 3: Create the resume skill

**Beads:** claude-workstation-pyc

**Files:**
- Create: `skills/resume/SKILL.md`

- [ ] **Step 1: Create the resume skill directory**

```bash
mkdir -p skills/resume
```

- [ ] **Step 2: Write the resume SKILL.md**

Create `skills/resume/SKILL.md` with this content:

````markdown
---
name: resume
version: 1.0.0
description: >
  Resume open work. Lists tasks grouped by epic, loads context at tier-appropriate
  depth, detects workflow position, and routes to the correct next skill.
  TRIGGER: When starting a session with existing open work, or when the user
  wants to continue previous work.
---

# Resume: Continue Open Work

Lists open tasks and epics, lets the user pick one to continue, deep-loads all
related context, detects where the workflow left off, and routes to the correct
next skill.

## Invocation

- `/claude-workstation:resume` — auto-resume (picks most recent in_progress, or shows list)
- `/claude-workstation:resume --interactive` — always show list, suggest but don't auto-invoke
- `/claude-workstation:resume --dry` — show summary without invoking anything
- `/claude-workstation:resume <task-id>` — resume a specific task by ID (skip selection)

## Flow

Execute these steps in order:

### Step 1: PARSE

Extract from arguments:
- **task-id**: A beads task ID if provided directly (optional)
- **--interactive flag**: If present, always show list and wait for confirmation before invoking skills
- **--dry flag**: If present, show summary and suggested skill but do not invoke anything

### Step 2: SELECT

**If a task-id was provided**, skip to Step 3 with that task.

**Otherwise, gather open work:**

```bash
bd list --status=in_progress
bd list --status=open
```

**Auto-selection logic** (when not `--interactive`):

1. Exactly 1 `in_progress` task → auto-select it, skip to Step 3
2. Multiple `in_progress` tasks → show list, user picks
3. 0 `in_progress` but open tasks exist → show list, user picks
4. Nothing open → print: "Nothing to resume. Use `/claude-workstation:init` to start new work." and STOP

**Display format** (when showing the list):

Group tasks by epic. Show a "last active" shortcut if exactly 1 task is `in_progress`:

```
⏸ Last active: <task-id> — <title> (in_progress, <time> ago)
  → Press Enter to resume, or pick from the list below:

📦 <epic title> (<priority>, epic, <done>/<total> done)
   1. ✓ <closed sub-task title>
   2. ◐ <in_progress sub-task title> ← in progress
   3. ○ <open sub-task title>
   4. ● <blocked sub-task title> (blocked by #2, #3)

─── Standalone Tasks ───
   5. ○ <task title> (<priority>, <type>)

Pick [1-N] or Enter for last active:
```

**Display rules:**
- "Last active" shortcut only appears if exactly 1 task is `in_progress`. If 0 or multiple, omit it.
- Epic progress shows `done/total` count from sub-task statuses.
- Sub-task indicators: `✓` closed, `◐` in_progress, `○` open, `●` blocked.
- `← in progress` annotation on the active sub-task within each epic.
- Blocked tasks show what blocks them in parentheses.
- Standalone section only appears if there are tasks not linked to any epic.
- Epics are grouping headers, not selectable — user picks a specific sub-task or standalone task.

**To build this display:**

1. Run `bd list --status=open` and `bd list --status=in_progress` to get all active tasks.
2. For each task, run `bd show <id>` to get type, dependencies, and blocked-by info.
3. Identify epics (type=epic) and their sub-tasks (tasks that depend on the epic, or that the epic's plan references).
4. Group sub-tasks under their parent epic. Tasks with no epic parent go to "Standalone Tasks."
5. Sort epics by priority (P0 first), then by most recently updated.
6. Within each epic, sort sub-tasks by dependency order (ready first, blocked last).
7. Number all selectable items sequentially across all groups.

Wait for the user to pick a number or press Enter.

### Step 3: LOAD CONTEXT

After selecting a task, load context at a depth determined by the original tier.

**Determine tier:**

1. Check beads notes for `"tier: <value>"` (set by `/init`)
2. If not found, infer:
   - Task is under an epic → medium+
   - Task type is epic → medium+
   - Task has notes referencing spec/plan files (contains `"Spec:"` or `"Plan:"`) → small
   - Otherwise → trivial

**Load by depth:**

**Shallow (trivial):**
```bash
bd show <id>
```
Extract: description, notes, dependencies. Done.

**Medium (small):**
Everything from Shallow, plus:
```bash
# Find commits mentioning this task ID
git log --all --oneline --grep="<task-id>"

# For each commit, get changed files
git show --stat <commit-hash>
```
Extract: commit list, changed file paths, test file paths.

**Deep (medium+):**
Everything from Medium, plus:
```bash
# Read spec file if referenced in notes (extract path after "Spec: ")
# Read plan file if referenced in notes (extract path after "Plan: ")

# Get sub-task statuses for the parent epic
bd list --status=open
bd list --status=in_progress
bd list --status=closed

# Check for active worktrees
git worktree list

# Scan session files for references to this task/epic ID
grep -rl "<task-id>" ~/.claude/sessions/ 2>/dev/null
grep -rl "<epic-id>" ~/.claude/sessions/ 2>/dev/null
```
Extract: spec contents, plan contents, sub-task progress, worktree path, session file contents.

**Assemble context object:**
```
context = {
  task:        bd show output (always)
  tier:        trivial | small | medium+
  commits:     related commits (medium, deep)
  files:       changed files from commits (medium, deep)
  spec:        spec file contents (deep)
  plan:        plan file contents (deep)
  subtasks:    list with statuses (deep, epics)
  worktree:    path if active (deep)
  session:     session file contents if found (deep)
  milestones:  extracted from beads notes (always, may be empty)
}
```

### Step 4: DETECT POSITION

Using the context object, determine where in the workflow the task left off.

**Check milestones in beads notes (primary signal):**

Scan notes for milestone patterns. The latest (highest-priority) match wins:

| Priority | Pattern in notes | Position |
|---|---|---|
| 1 (highest) | `"Verification:"` | post-verification |
| 2 | `"Tests passing:"` or `"Tests green:"` | mid-implementation |
| 3 | `"Plan:"` | post-planning |
| 4 | `"Spec:"` | post-brainstorming |
| 5 | `"Debug:"` or `"Bug:"` or `"Root cause:"` | mid-debugging |
| 6 (lowest) | `"tier:"` only (no other milestones) | start |

**Artifact fallback (when no milestone patterns found):**

If the notes have no recognizable milestone patterns (task created manually, or session crashed before notes were updated):

1. Check sub-task statuses:
   - Some sub-tasks closed → `mid-implementation`
   - Sub-tasks exist but all open → `post-planning`
2. Check for files (match by task ID or epic ID in filename, or grep file contents for the ID):
   - Plan file found in `docs/superpowers/plans/` → `post-planning`
   - Spec file found in `docs/superpowers/specs/` → `post-brainstorming`
3. Check git log:
   - Commits referencing task ID that include test files → `mid-implementation`
4. Nothing found:
   - Epic → `start` (needs brainstorming)
   - Bug → `start` (needs systematic debugging)
   - Task → `start` (needs TDD or just do it)

### Step 5: ROUTE

**Map position to next skill:**

| Position | Task type | Next skill |
|---|---|---|
| start | epic | `/superpowers:brainstorming` |
| start | task (small) | `/superpowers:test-driven-development` |
| start | task (trivial) | No skill — "Go fix it. Then verify and `bd close <id>`." |
| start | bug (any tier) | `/superpowers:systematic-debugging` |
| mid-debugging | bug | `/superpowers:systematic-debugging` (continue) |
| post-brainstorming | any | `/superpowers:writing-plans` |
| post-planning | any | `/superpowers:test-driven-development` (next ready sub-task) |
| mid-implementation | any | `/superpowers:test-driven-development` (next ready sub-task) |
| post-verification | any | `/superpowers:finishing-a-development-branch` |

**Print the summary:**

```
📋 Resuming: <task title> (<type>, <tier>)

<2-3 sentence narrative: what this is, where you left off, what's next>

  Status:    <position label> (<sub-task progress> if epic)
  Tier:      <trivial | small | medium+>
  Spec:      <path>
  Plan:      <path>
  Worktree:  <path>
  Files:     <N files changed across M commits>
  Next task: <task-id> — <title>

  → Starting: <next skill name>
```

Only show fields that have values. No "none" clutter for trivial tasks.

**Then act based on mode:**

- **Default:** Set the task to `in_progress` (`bd update <id> -s in_progress`) and auto-invoke the suggested skill.
- **`--interactive`:** Print `→ Suggesting: <skill>. Proceed? [Y/n/other]` and wait for user confirmation. If the user says yes or presses Enter, set task to `in_progress` and invoke the skill. If the user says no or provides an alternative, follow their direction.
- **`--dry`:** Print `→ Would invoke: <skill> (dry run, not invoking)` and STOP. Do not set status or invoke anything.

**Edge cases:**

- **Post-verification, all sub-tasks closed:** Print `"All work complete. Run verification and close the epic: bd close <epic-id>"`. Do not invoke a skill.
- **No clear next step** (open task, no tier, no milestones, no artifacts): Show `bd show` output and ask the user what they'd like to do. Do not invoke a skill.
````

- [ ] **Step 3: Verify the skill file**

```bash
test -f skills/resume/SKILL.md && echo "OK: resume skill exists" || echo "FAIL: missing"
head -5 skills/resume/SKILL.md
# Expected: YAML frontmatter with name: resume
grep -c "claude-workstation:resume" skills/resume/SKILL.md
# Expected: 4 (invocation examples)
grep -c "claude-workstation:init" skills/resume/SKILL.md
# Expected: 1 (the "nothing to resume" fallback message)
```

- [ ] **Step 4: Commit**

```bash
git add skills/resume/SKILL.md
git commit -m "feat: add resume skill for continuing open work"
```

---

### Task 4: Add systematic debugging rule and workflow section

**Beads:** claude-workstation-qxn

**Files:**
- Create: `rules/common/debugging.md`
- Modify: `commands/workflow.md`
- Modify: `rules/common/unified-workflow.md`

- [ ] **Step 1: Create the debugging rule**

Create `rules/common/debugging.md` with this content:

```markdown
# Debugging

## Debugging-First Protocol

When working on a bug (task type `bug`), ALWAYS invoke `superpowers:systematic-debugging` before attempting a fix.

## Process

1. **Root cause** — read error messages, reproduce the issue, check recent changes
2. **Pattern analysis** — find working examples of similar code, compare with broken code
3. **Hypothesis** — form a single-variable hypothesis, test it
4. **Fix with test** — write a failing regression test that reproduces the bug, then fix (feeds into TDD)
5. **Stop after 3 failed attempts** — if three hypotheses fail, question the architecture. The bug may be a symptom of a deeper design issue.

## Workflow

Bugs follow this path regardless of tier (trivial/small/medium+):

```
bd create --title="..." --type=bug
→ superpowers:systematic-debugging (root cause)
→ superpowers:test-driven-development (regression test + fix)
→ superpowers:requesting-code-review
→ superpowers:verification-before-completion
→ bd close <id>
```

## Anti-Patterns

- Do NOT skip straight to a fix without understanding root cause
- Do NOT write the regression test before identifying the root cause
- Do NOT keep trying random fixes — 3 strikes and reassess
```

- [ ] **Step 2: Add Bug Path section to commands/workflow.md**

In `commands/workflow.md`, insert a new section after the "Small Path" section (after line 57, before the "Medium+ Path" section). Insert between the `---` separator and the `## Medium+ Path` heading:

```markdown

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

```

- [ ] **Step 3: Add bug type to unified-workflow.md Task Sizing table**

In `rules/common/unified-workflow.md`, replace the Task Sizing table:

```markdown
## Task Sizing

| Tier | Signal | Flow |
|---|---|---|
| **Trivial** | ≤1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | `bd create -t epic` → brainstorm → plan → sub-tasks → worktree → TDD → review → verify → finish → `bd close` |
```

with:

```markdown
## Task Sizing

| Tier | Signal | Flow |
|---|---|---|
| **Trivial** | ≤1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | `bd create -t epic` → brainstorm → plan → sub-tasks → worktree → TDD → review → verify → finish → `bd close` |
| **Bug** | Any tier, type=bug | `bd create -t bug` → debug → TDD (regression test) → review → verify → `bd close` |
```

- [ ] **Step 4: Add debugging to the Plugin Roles table in commands/workflow.md**

In `commands/workflow.md`, replace the Plugin Roles table row for Superpowers:

```markdown
| **Superpowers** | Process: brainstorm, plan, TDD, review, verify, debug, finish | Small, Medium+ |
```

with:

```markdown
| **Superpowers** | Process: brainstorm, plan, TDD, review, verify, debug, finish | Small, Medium+, Bug |
```

- [ ] **Step 5: Update setup skill to copy the new rule**

In `skills/setup/SKILL.md`, in Step 3 (Copy Custom Rules), add `debugging.md` to the file list in the for loop. Replace:

```bash
for file in unified-workflow.md plugin-routing.md development-workflow.md verification-template.md beads-milestones.md; do
```

with:

```bash
for file in unified-workflow.md plugin-routing.md development-workflow.md verification-template.md beads-milestones.md debugging.md; do
```

- [ ] **Step 6: Verify**

```bash
test -f rules/common/debugging.md && echo "OK: debugging rule exists" || echo "FAIL: missing"
grep -c "systematic-debugging" rules/common/debugging.md
# Expected: 2
grep -c "Bug Path" commands/workflow.md
# Expected: 1
grep -c "Bug" rules/common/unified-workflow.md
# Expected: 1 (in the table)
grep -c "debugging.md" skills/setup/SKILL.md
# Expected: 1
```

- [ ] **Step 7: Commit**

```bash
git add rules/common/debugging.md commands/workflow.md rules/common/unified-workflow.md skills/setup/SKILL.md
git commit -m "feat: add systematic debugging rule and bug path to workflow"
```

---

### Task 5: Update README and CLAUDE.md for all changes

**Beads:** claude-workstation-akb
**Depends on:** Tasks 1, 2, 3, 4

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md Quick Start section**

In `CLAUDE.md`, replace the Quick Start section (the init reference was already updated in Task 2). Add resume alongside it. Replace:

```markdown
## Quick Start

Run `/claude-workstation:init "description"` to auto-assess task tier, create the beads task, and start the right workflow in one step.
```

with:

```markdown
## Quick Start

- **New work:** `/claude-workstation:init "description"` — assess tier, create task, start workflow
- **Resume work:** `/claude-workstation:resume` — pick up open tasks, load context, continue workflow
```

- [ ] **Step 2: Update README.md — What's Included**

In `README.md`, replace line 8:

```markdown
- **Auto-Tier Assessment** — `/analyze` scores task descriptions and routes to the right workflow automatically
```

with:

```markdown
- **Auto-Tier Assessment** — `/init` scores task descriptions and routes to the right workflow automatically
- **Resume Work** — `/resume` lists open tasks, loads context at tier-appropriate depth, and continues the workflow
- **Bug Path** — systematic debugging rule ensures root cause analysis before fixes
```

- [ ] **Step 3: Update README.md — Commands & Skills table**

In `README.md`, replace the commands table:

```markdown
| Command | What it does |
|---|---|
| `/claude-workstation:analyze` | Auto-assess task tier, create beads task, start the right workflow |
| `/workflow` | Show the full development playbook |
| `/claude-workstation:setup` | Install dependencies and configure environment |
| `/claude-workstation:test` | Validate configuration and run scenarios |
```

with:

```markdown
| Command | What it does |
|---|---|
| `/claude-workstation:init` | Auto-assess task tier, create beads task, start the right workflow |
| `/claude-workstation:resume` | Resume open work — load context, detect position, continue workflow |
| `/workflow` | Show the full development playbook |
| `/claude-workstation:setup` | Install dependencies and configure environment |
| `/claude-workstation:test` | Validate configuration and run scenarios |
```

- [ ] **Step 4: Update README.md — Quick Start examples section**

Replace the entire `/analyze` quick start section (lines 57-73):

```markdown
### `/analyze` — Quick Start

```bash
/claude-workstation:analyze "Fix the login validation bug"
# → Scores description → Small → creates task → starts TDD

/claude-workstation:analyze "Design a new notification system"
# → Scores description → Medium+ → creates epic → starts brainstorming

/claude-workstation:analyze "Fix typo in README"
# → Scores description → Trivial → creates task → "Go fix it"

/claude-workstation:analyze --side-quest "Found: tokens aren't rotated"
# → Detects side-quest → creates bug → links to current task → parks it
```
```

with:

```markdown
### `/init` — Start New Work

```bash
/claude-workstation:init "Fix the login validation bug"
# → Scores description → Small → creates task → starts TDD

/claude-workstation:init "Design a new notification system"
# → Scores description → Medium+ → creates epic → starts brainstorming

/claude-workstation:init "Fix typo in README"
# → Scores description → Trivial → creates task → "Go fix it"

/claude-workstation:init --side-quest "Found: tokens aren't rotated"
# → Detects side-quest → creates bug → links to current task → parks it
```

### `/resume` — Continue Open Work

```bash
/claude-workstation:resume
# → Shows grouped task list → pick one → loads context → continues workflow

/claude-workstation:resume --interactive
# → Always shows list, suggests next skill but waits for confirmation

/claude-workstation:resume claude-workstation-pyc
# → Resumes specific task directly, skipping selection

/claude-workstation:resume --dry
# → Shows what would happen without invoking anything
```
```

- [ ] **Step 5: Update README.md — Project Structure**

Replace the skills line in the project structure tree:

```markdown
│   ├── analyze/SKILL.md      # /analyze — auto-tier assessment
```

with:

```markdown
│   ├── init/SKILL.md          # /init — auto-tier assessment & workflow start
│   ├── resume/SKILL.md        # /resume — continue open work
```

And add the debugging rule to the rules section. Replace:

```markdown
│   └── beads-milestones.md
```

with:

```markdown
│   ├── beads-milestones.md
│   └── debugging.md
```

- [ ] **Step 6: Verify no stale analyze references remain (excluding historical docs)**

```bash
grep -r "claude-workstation:analyze" --include="*.md" . | grep -v "docs/superpowers/"
# Expected: no output

grep -r "/analyze" README.md CLAUDE.md commands/workflow.md
# Expected: no output (all replaced with /init)
```

- [ ] **Step 7: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: update README and CLAUDE.md for init, resume, and debugging"
```
