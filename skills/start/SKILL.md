---
name: start
version: 1.2.2
description: >
  Auto-assess task tier and recommend the right workflow. Takes a description,
  assesses tier, creates the beads task, and presents workflow options with reasoning.
  TRIGGER: When starting any new work, or when the user describes a task.
---

# Start: Auto-Tier Assessment & Workflow Routing

Takes a task description, assesses its complexity tier, creates the appropriate
beads task, and recommends the first workflow skill with reasoning — letting
the user choose before invoking.

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
- There is an active in-progress beads task (check `bd list --status=in_progress`) AND the new work would touch files not listed in the current task's beads description or plan (different files or different directory — even if causally related to the current task's changes)

**If side-quest detected**, skip to the SIDE-QUEST FLOW below.

### Step 3: TIER

Walk four gates in order. The **first gate that fires** determines the tier.

**Domains** (for counting): API, database, auth, frontend, backend, CI/CD, infrastructure, testing, security, config.

#### Gate 1 — ESCALATION
- Description contains **"new system"** or **"new component"** → **Medium+**
- Primary intent is architecture (**design, architect, migrate**) → **Medium+**
- Description mentions **security** or **migration** (not as primary intent) → set **floor = Small**, continue

#### Gate 2 — SCOPE
- Breadth words present (**all, every, across, entire, global**) → **Medium+**
- **3+ domains** touched → **Medium+**
- **Rewrite** or **overhaul** mentioned → **Medium+**

#### Gate 3 — SIZE
- **2+ domains** touched → **Small**
- Feature intent (**add, create, implement, new**) → **Small**

#### Gate 4 — DEFAULT
- → **Trivial** (or floor from Gate 1 if set)

#### Claude Override

You may override the gate result **upward only** (never downward). If you know from project context that a seemingly small task actually spans many files, bump it up. Downward overrides require human approval. Log: `tier-override: <computed> → <new> — <reason>`

### Step 4: CREATE

Create the beads task:

**Determine task type:**
- Trivial or Small: `--type=task`
- Medium+: `--type=epic`

**Determine priority** (if no `-p` override):
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

### Step 5: ROUTE

**Print the analysis output, then recommend a workflow and wait for user choice.**

Do NOT auto-invoke any skill. Present the recommendation and let the user decide.

```
📊 Analysis: "<description>"
   Gate: <which gate fired> | Domains: <domain_count>
   Tier: <tier>

   ✓ Created: <task-id> (<type>, P<priority>)
   → Recommended: <recommended skill>
```

**Then present a recommendation table with reasoning:**

For each tier, there is a default recommendation and alternatives. Present ALL options
with a brief explanation of why each fits or doesn't fit this specific task.

| Tier | Default Recommendation | Reasoning to Show |
|---|---|---|
| Trivial | No skill needed — "Go fix it. Then verify and `bd close <task-id>`." | Explain: single-file, no behavior change, ceremony would slow you down. |
| Small | `/superpowers:test-driven-development` | Explain: single-concern change benefits from RED-GREEN-REFACTOR to catch regressions. |
| Medium+ | `/superpowers:brainstorming` | Explain: multi-file/cross-cutting work needs requirements exploration before code. |

**Format the recommendation as a choice table:**

| Option | Skill | Why it fits | Why it might not |
|---|---|---|---|
| **A (recommended)** | `<default for tier>` | `<specific reason for THIS task>` | `<honest caveat>` |
| **B** | `<alternative 1>` | `<when this would be better>` | `<why it's not the default>` |
| **C** | `<alternative 2 if applicable>` | `<when this would be better>` | `<why it's not the default>` |

Alternatives to consider (pick 1-2 relevant ones):
- `/superpowers:brainstorming` — when scope is ambiguous or requirements need exploration
- `/superpowers:test-driven-development` — when behavior change needs regression safety
- `/superpowers:systematic-debugging` — when the task is investigating a bug
- Direct edit + manual verify — when the task is truly trivial and ceremony is overhead
- `/superpowers:writing-plans` — when the task needs architectural planning before TDD

End with: **"My recommendation: Option A — `<one-sentence reason>`. Which would you like?"**

**Wait for user response. Do NOT invoke any skill until the user picks an option.**

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
   📊 Analysis: "<description>"
      Detected: Side-quest (current task: <current-task-id>)

      ✓ Created: <new-task-id> (bug, P<priority>)
      ✓ Linked: <new-task-id> discovered-from <current-task-id>
      → Parked. Finish current task first, then bd ready.
   ```

5. **Do NOT invoke any skill.** Return control to the user to continue current work.
