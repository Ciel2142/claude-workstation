---
name: continue
version: 1.5.1
description: >
  Continue open work. Lists tasks grouped by epic, loads context at tier-appropriate
  depth, detects workflow position, and routes to the correct next skill.
  TRIGGER: When starting a session with existing open work, or when the user
  wants to continue previous work.
---

# Continue Open Work

Lists open tasks and epics, lets the user pick one to continue, deep-loads all
related context, detects where the workflow left off, and routes to the correct
next skill.

## Invocation

- `/claude-workstation:continue` — auto-resume (picks most recent in_progress, or shows list)
- `/claude-workstation:continue --interactive` — always show list, suggest but don't auto-invoke
- `/claude-workstation:continue --dry` — show summary without invoking anything
- `/claude-workstation:continue <task-id>` — resume a specific task by ID (skip selection)

## Flow

Execute these steps in order:

### Step 1: PARSE

Extract from arguments:
- **task-id**: A beads task ID if provided directly (optional)
- **--interactive flag**: If present, always show list and wait for confirmation before invoking skills
- **--dry flag**: If present, show summary and suggested skill but do not invoke anything

### Step 2: SELECT

**Pre-check:** If `bd` is not available or errors on `bd list`, stop and tell the user:
"Cannot reach beads. Run `bd doctor` to diagnose, or `bd init` to initialize."

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
4. Nothing open → print: "Nothing to continue. Use `/claude-workstation:start` to start new work." and STOP

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

1. Check beads notes for `"tier: <value>"` (set by `/start`)
2. If not found, infer:
   - Task is under an epic → medium+
   - Task type is epic → medium+
   - Task has notes with `"plan:"` but no `"spec:"` → medium (plan without spec = no brainstorming)
   - Task has notes referencing spec files (contains `"spec:"`) → small
   - Otherwise → **default to small** (ensures minimum TDD + review; can escalate if needed)

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
# Read spec file if referenced in notes (extract path after "spec: ")
# MANDATORY FALLBACK: If no "spec:" in notes, you MUST search by convention:
#   grep -rl "<epic-id>\|<task-id>" docs/superpowers/specs/ 2>/dev/null
#   ls docs/superpowers/specs/ 2>/dev/null
# If multiple spec files match, read all of them — coverage gaps hide in any.
# If any spec file is found, read it. Then persist the path for future sessions:
#   bd-notes-append <id> "spec: <found-path>"
# If the directory does not exist, skip silently (no spec to recover).
# Skipping this search means spec content is lost after compaction — permanently.
# Read plan file if referenced in notes (extract path after "plan: ")

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
  tier:        trivial | small | medium | medium+
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
| 1 (highest) | `"docs-updated:"` | post-update-docs |
| 2 | `"verification:"` | post-verification |
| 3 | `"completed:"` | mid-implementation |
| 4 | `"planned-tasks:"` | post-decomposition |
| 5 | `"plan:"` | post-planning |
| 6 | `"spec:"` | post-brainstorming |
| 7 | `"debug:"` | mid-debugging |
| 8 (lowest) | `"tier:"` only (no other milestones) | start |

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
| start | epic (medium+) | `/superpowers:brainstorming` |
| start | epic (medium) | `/superpowers:writing-plans` |
| start | task (small) | `/superpowers:test-driven-development` |
| start | task (trivial) | No skill — "Go fix it. Then verify and `bd close <id>`." |
| start | bug (any tier) | `/superpowers:systematic-debugging` |
| mid-debugging | bug | `/superpowers:systematic-debugging` (continue) |
| post-brainstorming | any | `/superpowers:writing-plans` |
| post-planning | any | Create sub-tasks from plan, then continue |
| post-decomposition | medium | `/superpowers:subagent-driven-development` |
| post-decomposition | medium+ | `/superpowers:test-driven-development` (next ready sub-task) |
| mid-implementation | medium | `/superpowers:subagent-driven-development` (continue) |
| mid-implementation | medium+ | `/superpowers:test-driven-development` (next ready sub-task) |
| post-verification | any | `/ecc:update-docs` |
| post-update-docs | any | `/superpowers:finishing-a-development-branch` |

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
