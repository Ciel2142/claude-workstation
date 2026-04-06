---
name: status
version: 1.2.0
description: >
  Show current work state without taking action. Displays active task,
  workflow position, next ready work, and suggested next skill.
  TRIGGER: When the user asks "where am I", "what's active", "status",
  "what was I working on", or after compaction/session resume.
---

# Status: Current Work Orientation

Read-only view of active work. Never takes action, never sets status,
never invokes skills.

## Invocation

`/claude-workstation:status`

## Flow

### Step 1: GATHER

```bash
bd list --status=in_progress
```

If nothing in progress:
```bash
bd list --status=open
```

If nothing at all, print:
```
No active work. Use /claude-workstation:start to begin.
```
And STOP.

### Step 2: INSPECT

For the active task (prefer in_progress over open):
```bash
bd show <id>
```

Extract: title, type, priority, status, notes.

### Step 3: DETECT POSITION

Scan notes for milestone patterns. Highest-priority match wins:

| Priority | Pattern | Position |
|---|---|---|
| 1 | `docs-updated:` | post-update-docs |
| 2 | `verification:` | post-verification |
| 3 | `completed:` | mid-implementation |
| 4 | `plan:` | post-planning |
| 5 | `spec:` | post-brainstorming |
| 6 | `debug:` | mid-debugging |
| 7 | `tier:` only | start |

### Step 4: CONTEXT

Gather optional context (skip any that error):
```bash
bd ready                    # Next available task
git worktree list           # Active worktrees
git log --oneline -1        # Last commit
```

### Step 5: SUGGEST

Map position to suggested skill (same as /resume routing):

| Position | Suggestion |
|---|---|
| start (epic) | `/superpowers:brainstorming` |
| start (task, small) | `/superpowers:test-driven-development` |
| start (task, trivial) | Go fix it, then verify and `bd close <id>` |
| start (bug) | `/superpowers:systematic-debugging` |
| mid-debugging | `/superpowers:systematic-debugging` |
| post-brainstorming | `/superpowers:writing-plans` |
| post-planning | `/superpowers:test-driven-development` |
| mid-implementation | `/superpowers:test-driven-development` |
| post-verification | `/ecc:update-docs` |
| post-update-docs | `/superpowers:finishing-a-development-branch` |

### Step 6: PRINT

Show only fields that have values:

```
Active:     <id> -- "<title>" (<tier>, <status>)
Position:   <position> (<milestone detail>)
Next ready: <id> -- "<title>"
Worktree:   <path>
Last commit: <relative time> -- "<message>"

Suggested: <skill>
```

**Rules:**
- Omit any field that has no value
- Never set task status
- Never invoke a skill
- If the user wants to act on the suggestion, they can run `/resume`
