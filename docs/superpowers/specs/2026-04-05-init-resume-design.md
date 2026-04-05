# `/claude-workstation:init` + `/claude-workstation:resume` — Design Spec

**Epic:** claude-workstation-ap1
**Date:** 2026-04-05
**Status:** Approved

## Overview

Two changes to claude-workstation skills:

1. **Rename `analyze` → `init`** — the skill initializes the workflow process (assesses tier, creates beads task, routes to first skill). "init" reflects this better than "analyze."
2. **New `resume` command** — lists open work grouped by epic, lets the user pick a task to continue, deep-loads all related context, detects workflow position, and routes to the correct next skill.

Together, `init` and `resume` form the two entry points into the workflow: start new work or pick up existing work.

---

## Part 1: `init` Rename

### Changes

- **Directory:** `skills/analyze/` → `skills/init/`
- **Frontmatter:** `name: analyze` → `name: init`
- **Title:** "Analyze: Auto-Tier Assessment & Workflow Routing" → "Init: Auto-Tier Assessment & Workflow Routing"
- **Examples:** all `/claude-workstation:analyze` → `/claude-workstation:init`
- **New behavior:** After creating the beads task, `init` persists the computed tier in the notes:
  ```bash
  bd update <id> --notes "tier: trivial|small|medium+"
  ```

### Files to Update

| File | Change |
|---|---|
| `skills/analyze/SKILL.md` | Rename dir to `skills/init/`, update frontmatter + title + examples |
| `CLAUDE.md` | Update Quick Start reference |
| `README.md` | Update feature list, commands table, examples, project structure |
| `commands/workflow.md` | Update the "Or use `/analyze`" note |

Historical docs (`docs/superpowers/specs/` and `docs/superpowers/plans/`) are left as-is — they're point-in-time snapshots.

---

## Part 2: `resume` Command

### Invocation

```bash
# Default: auto-resume
/claude-workstation:resume

# Interactive: always show list, suggest but don't auto-invoke next skill
/claude-workstation:resume --interactive

# Resume a specific task by ID (skip selection)
/claude-workstation:resume claude-workstation-pyc

# Dry run: show summary without invoking anything
/claude-workstation:resume --dry
```

### Auto-Selection Logic

When no ID is provided and `--interactive` is not set:

1. Exactly 1 `in_progress` task → auto-select it
2. Multiple `in_progress` tasks → show list, user picks
3. 0 `in_progress` but open tasks exist → show list, user picks
4. Nothing open → print: "Nothing to resume. Use `/claude-workstation:init` to start new work."

### Display Format

The selection list uses grouped-by-epic format with a "last active" shortcut:

```
⏸ Last active: claude-workstation-j35 — Update all references (in_progress, 2h ago)
  → Press Enter to resume, or pick from the list below:

📦 Rename analyze→init and create resume command (P1, epic, 2/4 done)
   1. ✓ Rename analyze skill directory
   2. ◐ Update all references ← in progress
   3. ○ Design and implement resume skill
   4. ● Update README/CLAUDE.md (blocked by #2, #3)

📦 Notification system overhaul (P1, epic, 0/5 done)
   5. ○ Design webhook handler
   6. ○ Implement retry logic
   7. ○ Add dead letter queue
   8. ○ Write integration tests
   9. ○ Update API docs

─── Standalone Tasks ───
  10. ○ Fix token rotation (P2, bug)
  11. ○ Add rate limiting to /health (P3, task)

Pick [1-11] or Enter for last active:
```

**Display rules:**

- "Last active" shortcut only appears if exactly 1 task is `in_progress`
- Epic progress shows `done/total` count from sub-task statuses
- Sub-task indicators: `✓` closed, `◐` in_progress, `○` open, `●` blocked
- `← in progress` annotation on the active sub-task within each epic
- Blocked tasks show what blocks them in parentheses
- Standalone section only appears if there are tasks not linked to any epic
- User picks a specific sub-task or standalone task (epics are grouping headers, not selectable)

### Context Loading (Tier-Based Depth)

**Step 1: Determine tier**

1. Check beads notes for `"tier: <value>"` (set by `init`)
2. If not found, infer:
   - Task is under an epic → medium+
   - Task type is epic → medium+
   - Task has notes referencing spec/plan files → small
   - Otherwise → trivial

**Step 2: Load by depth**

| Depth | What's loaded | Tier |
|---|---|---|
| **Shallow** | `bd show <id>` — description, notes, deps | Trivial |
| **Medium** | Shallow + git log for commits mentioning task ID + related test files from those commits + file references in beads notes | Small |
| **Deep** | Medium + read spec file from notes + read plan file from notes + compute sub-task progress across epic + `git worktree list` for active worktrees + scan `~/.claude/sessions/` for session files referencing the task/epic ID | Medium+ |

**Step 3: Build context object**

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

### Workflow Position Detection (Hybrid: Milestones + Artifact Fallback)

**Step 1: Check milestones in beads notes**

Scan notes for milestone patterns in reverse order — latest found is current position:

| Pattern in notes | Position |
|---|---|
| `"Verification:"` | post-verification |
| `"Tests passing:"` or `"Tests green:"` | mid-implementation |
| `"Plan:"` | post-planning |
| `"Spec:"` | post-brainstorming |
| `"Debug:"` or `"Bug:"` or `"Root cause:"` | mid-debugging |
| `"tier:"` only (no other milestones) | start |

**Step 2: Artifact fallback (when milestones are sparse)**

If no milestone patterns found (task created manually, or session crashed):

```
Check sub-task statuses:
  - Some closed → mid-implementation
  - All open but exist → post-planning

Check for files (match by task ID or epic ID in filename, or grep file contents for the ID):
  - Plan file in docs/superpowers/plans/ → post-planning
  - Spec file in docs/superpowers/specs/ → post-brainstorming

Check git log:
  - Commits referencing task ID with test files → mid-implementation

Nothing found:
  - Epic → start (needs brainstorming)
  - Task → start (needs TDD or just do it)
```

**Step 3: Map position to next skill**

| Position | Task type | Next skill |
|---|---|---|
| start | epic | `/superpowers:brainstorming` |
| start | task (small) | `/superpowers:test-driven-development` |
| start | task (trivial) | No skill — "Go fix it." |
| start | bug (any tier) | `/superpowers:systematic-debugging` |
| mid-debugging | bug | `/superpowers:systematic-debugging` (continue) |
| post-brainstorming | any | `/superpowers:writing-plans` |
| post-planning | any | `/superpowers:test-driven-development` (next ready sub-task) |
| mid-implementation | any | `/superpowers:test-driven-development` (next ready sub-task) |
| post-verification | any | `/superpowers:finishing-a-development-branch` |

### Summary Output

After context loading and position detection:

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

**Conditional fields:** `Spec`, `Plan`, `Worktree`, `Files`, `Next task` only shown when they exist. No "none" clutter for trivial tasks.

**Routing behavior:**

| Mode | Behavior |
|---|---|
| Default | Auto-invoke suggested skill, set task to `in_progress` |
| `--interactive` | Print `→ Suggesting: <skill>. Proceed? [Y/n/other]`, wait |
| `--dry` | Print `→ Would invoke: <skill> (dry run)`, stop |

**Edge cases:**

- Post-verification with all sub-tasks closed: suggest `"All work complete. Run verification and close the epic: bd close <epic-id>"`
- No clear next step (open task, no tier, no milestones, no artifacts): show `bd show` output and ask the user what they'd like to do

---

## Part 3: Systematic Debugging Rule

A new rule added to `rules/common/` and a new section in `commands/workflow.md`.

### Rule: `rules/common/debugging.md`

Defines the debugging-first protocol for bugs:

1. Always invoke `superpowers:systematic-debugging` before attempting a fix
2. Root cause first — read errors, reproduce, check recent changes
3. Pattern analysis — find working examples, compare
4. Hypothesis — single-variable test
5. Fix with a failing test first (feeds into TDD)
6. Stop after 3 failed attempts → question architecture

### Workflow Addition: Bug Path

New section in `commands/workflow.md` between the Small and Medium+ paths:

```
## Bug Path

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

This applies regardless of tier — all bugs go through systematic debugging first.

---

## Sub-Tasks

| ID | Task | Depends on |
|---|---|---|
| claude-workstation-9jm | Rename analyze skill dir + SKILL.md → init | — |
| claude-workstation-j35 | Update all references across plugin | 9jm |
| claude-workstation-pyc | Design and implement resume skill | — |
| claude-workstation-qxn | Add debugging rule to workflow and rules | — |
| claude-workstation-akb | Update README/CLAUDE.md for all commands | j35, pyc, qxn |

## Decisions

1. **Naming:** `init` + `resume` (over kickoff/start/begin + continue/pickup)
2. **Display:** Grouped by epic with "last active" shortcut
3. **Context depth:** Tier-based — trivial=shallow, small=medium, medium+=deep
4. **Position detection:** Hybrid — milestones first, artifact fallback
5. **Summary format:** Brief narrative + structured reference data
6. **Routing:** Auto-invoke by default, `--interactive` and `--dry` flags for control
7. **Bug routing:** Always through systematic-debugging before TDD
