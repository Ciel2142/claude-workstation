---
name: start
version: 2.4.2
description: >
  Create a beads task and choose your workflow entry point.
  TRIGGER: When starting any new work, or when the user describes a task.
---

# Start: Task Creation & Workflow Entry

Creates a beads task and lets the user choose between brainstorming
(clarify what to build) or planning (decompose into sub-tasks).

## Invocation

- `/claude-workstation:start "Add rate limiting to all API endpoints"`
- `/claude-workstation:start -p 0 "Critical production outage"`
- `/claude-workstation:start --side-quest "Found: tokens aren't rotated"`

## Flow

Execute these steps in order:

### Step 1: PARSE

Extract from arguments:
- **description**: The quoted task description
- **priority override**: `-p <0-4>` if provided (optional)
- **side-quest flag**: `--side-quest` if provided (optional)

### Step 2: CHECK FOR SIDE-QUEST

Before creating, check if this is a side-quest. A side-quest is detected when ANY of:
- Description starts with "Found:" or "Discovered:"
- The `--side-quest` flag was passed
- There is an active in-progress beads task (check `bd list --status=in_progress`) AND the new work would touch files not listed in the current task's beads description or plan (different files or different directory — even if causally related to the current task's changes)

**If side-quest detected**, skip to the SIDE-QUEST FLOW below.

### Step 3: CREATE

Create the beads task:

```bash
bd create --title="<description>" --type=task -p <priority-override-or-2>
```

If `bd create` fails (beads not initialized, offline, or command error), stop and tell
the user: "Failed to create beads task. Run `bd doctor` to diagnose, or `bd init` if
beads is not set up for this project."

Then set it to in-progress:
```bash
bd update <task-id> -s in_progress
```

### Step 4: ROUTE

Print confirmation and ask one question:

```
✓ Created: <task-id> (P<priority>)
→ 1) Brainstorm  2) Plan
```

Wait for user response.

- If the user chooses 1 (brainstorm): invoke `/superpowers:brainstorming`
- If the user chooses 2 (plan): invoke `/superpowers:writing-plans`

---

## SIDE-QUEST FLOW

When a side-quest is detected:

1. **Identify the current in-progress task:**
   ```bash
   bd list --status=in_progress
   ```

2. **Create the side-quest task:**
   ```bash
   bd create --title="<description>" --type=bug -p <priority-override-or-2>
   ```
   Type defaults to `bug` for all side-quests involving broken behavior. Only use `--type=feature` or `--type=task` if the discovery describes new functionality with no broken behavior.

3. **Link it:**
   ```bash
   bd dep add <new-task-id> <current-task-id> --type=discovered-from
   ```

4. **Print output:**
   ```
   ✓ Created: <new-task-id> (bug, P<priority>)
     Linked: <new-task-id> discovered-from <current-task-id>
   → Parked. Finish current task first, then bd ready.
   ```

5. **Do NOT invoke any skill.** Return control to the user to continue current work.
