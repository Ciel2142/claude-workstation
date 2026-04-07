---
name: start
version: 1.2.0
description: >
  Auto-assess task tier and start the right workflow. Takes a description,
  scores it, creates the beads task, and invokes the first skill.
  TRIGGER: When starting any new work, or when the user describes a task.
---

# Start: Auto-Tier Assessment & Workflow Routing

Takes a task description, assesses its complexity tier, creates the appropriate
beads task, and auto-invokes the first workflow skill for that tier.

## Invocation

The user provides a description and optional flags:

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

Before scoring, check if this is a side-quest. A side-quest is detected when ANY of:
- Description starts with "Found:" or "Discovered:"
- The `--side-quest` flag was passed
- There is an active in-progress beads task (check `bd list --status=in_progress`) AND the new work would touch files outside the confirmed scope of the current task (different files, different directory, or different concern — even if causally related to the current task's changes)

**If side-quest detected**, skip to the SIDE-QUEST FLOW below.

### Step 3: SCORE

Evaluate the description against six weighted dimensions. Score each 0.0-1.0, then compute the weighted sum.

#### Scoring Matrix

| Dimension | Weight | How to Score |
|---|---|---|
| **task_type** | 0.20 | Match signal words to type. `fix/bug/broken/error/crash` = bug (0.3). `add/create/implement/new` = feature (0.5). `refactor/rename/move/clean` = refactor (0.4). `design/system/migrate/architecture` = architecture (0.9). `docs/readme/config/typo/comment/format` = docs (0.1). If multiple match, use the highest. If none match, use 0.4 (generic task). |
| **scope_keywords** | 0.25 | Check for breadth signals. `all/every/across/entire/global` = 1.0. `most/many/several` = 0.7. No breadth words = 0.2. |
| **domain_count** | 0.25 | Count distinct domains mentioned in the description: API, database, auth, frontend, backend, CI/CD, infrastructure, testing, security, config. 1 domain = 0.2. 2 domains = 0.5. 3+ domains = 1.0. |
| **change_signal** | 0.15 | Check magnitude words. `typo/tweak/bump/rename` = 0.1. `update/improve/enhance` = 0.4. `new system/new component/rewrite/overhaul` = 1.0. No magnitude words = 0.3. |
| **complexity_markers** | 0.05 | `step by step/multiple phases/depends on/coordination/integration` = 1.0. None = 0.0. |
| **forced_escalation** | 0.10 | Binary. Any of: security, architecture, migration, "new system", "new component" mentioned = 1.0. Otherwise = 0.0. |

Compute: `total = sum(dimension_score * weight for each dimension)`

#### Forced Escalation Override

After computing the total:
- If `forced_escalation` fired (1.0): minimum tier is **Small** regardless of total score.
- If `forced_escalation` fired AND `domain_count` score was 1.0 (3+ domains): minimum tier is **Medium+**.

#### Claude Override

You have freedom to override the numerical score when context clearly warrants it. The matrix is a guide, not a cage. If you know from project context that a seemingly small task actually spans many files, bump it up.

### Step 4: ASSESS

Map the final score to a tier:

| Score | Tier |
|---|---|
| < 0.25 | Trivial |
| 0.25 - 0.39 | Small |
| >= 0.40 | Medium+ |

### Step 5: CREATE

Create the beads task:

**Determine task type:**
- Trivial or Small: `--type=task`
- Medium+: `--type=epic`

**Determine priority** (if no `-p` override):
- Forced escalation fired (security, architecture): P1
- Medium+: P1
- Small: P2
- Trivial: P3

**Run:**
```bash
bd create --title="<description>" --type=<task|epic> -p <priority>
```

If `bd create` fails (beads not initialized, offline, or command error), stop and tell
the user: "Failed to create beads task. Run `bd doctor` to diagnose, or `bd init` if
beads is not set up for this project."

Then set it to in-progress:
```bash
bd update <task-id> -s in_progress
```

Then persist the computed tier for use by `/resume`:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "tier: <trivial|small|medium+>"
```

### Step 6: ROUTE

**Print the analysis output:**
```
📊 Analysis: "<description>"
   Type: <task_type> | Scope: <domains> (<domain_count> domains)
   Score: <total> → <tier>

   ✓ Created: <task-id> (<type>, P<priority>)
   → Starting: <next skill>
```

**Then auto-invoke the first skill for the tier:**

| Tier | Action |
|---|---|
| Trivial | Print: "Go fix it. Then verify and `bd close <task-id>`." Do NOT invoke any skill. |
| Small | Invoke: `/superpowers:test-driven-development` |
| Medium+ | Invoke: `/superpowers:brainstorming` |

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
   Type defaults to `bug`. If the side-quest is clearly a feature or task, use `--type=feature` or `--type=task` instead.

3. **Link it:**
   ```bash
   bd dep add <new-task-id> <current-task-id> --type=discovered-from
   ```

4. **Print output:**
   ```
   📊 Analysis: "<description>"
      Detected: Side-quest (current task: <current-task-id>)

      ✓ Created: <new-task-id> (bug, P<priority>)
      ✓ Linked: <new-task-id> discovered-from <current-task-id>
      → Parked. Finish current task first, then bd ready.
   ```

5. **Do NOT invoke any skill.** Return control to the user to continue current work.
