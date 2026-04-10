---
name: start
version: 2.4.3
description: >
  Create beads task, choose workflow entry point.
  TRIGGER: Starting new work or user describes task.
---

# Start: Task Creation & Workflow Entry

Creates beads task. User picks brainstorming (clarify what to build) or planning (decompose into sub-tasks).

## Invocation

- `/claude-workstation:start "Add rate limiting to all API endpoints"`
- `/claude-workstation:start -p 0 "Critical production outage"`
- `/claude-workstation:start --side-quest "Found: tokens aren't rotated"`

## Flow

Execute steps in order:

### Step 1: PARSE

Extract from arguments:
- **description**: Quoted task description
- **priority override**: `-p <0-4>` if provided (optional)
- **side-quest flag**: `--side-quest` if provided (optional)

### Step 2: CHECK FOR SIDE-QUEST

Check if side-quest. Detected when ANY of:
- Description starts with "Found:" or "Discovered:"
- `--side-quest` flag passed
- Active in-progress beads task exists (`bd list --status=in_progress`) AND new work touches files not in current task's description/plan (different files/directory — even if causally related)

**If side-quest detected**, skip to SIDE-QUEST FLOW below.

### Step 3: CREATE

Create beads task:

```bash
bd create --title="<description>" --type=task -p <priority-override-or-2>
```

If `bd create` fails (not initialized, offline, command error), stop and tell user: "Failed to create beads task. Run `bd doctor` to diagnose, or `bd init` if beads is not set up for this project."

Set to in-progress:
```bash
bd update <task-id> -s in_progress
```

### Step 4: ROUTE

Print confirmation, ask one question:

```
✓ Created: <task-id> (P<priority>)
→ 1) Brainstorm  2) Plan
```

Wait for user response.

- User chooses 1 (brainstorm): invoke `/superpowers:brainstorming`
- User chooses 2 (plan): invoke `/superpowers:writing-plans`

---

## SIDE-QUEST FLOW

When side-quest detected:

1. **Identify current in-progress task:**
   ```bash
   bd list --status=in_progress
   ```

2. **Create side-quest task:**
   ```bash
   bd create --title="<description>" --type=bug -p <priority-override-or-2>
   ```
   Defaults to `bug` for broken behavior. Use `--type=feature` or `--type=task` only if discovery describes new functionality with no broken behavior.

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

5. **Do NOT invoke any skill.** Return control to user to continue current work.