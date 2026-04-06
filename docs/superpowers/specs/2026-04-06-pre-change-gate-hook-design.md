# Pre-Change Gate Hook

## Problem

The workflow requires a beads task before any file modification (Pre-Change Gate rule in `contexts/workflow.md`). In practice, agents skip `bd create` and tier assessment, jumping straight to editing files. The rule is enforced by system prompt text the agent can rationalize around.

## Solution

A PreToolUse hook on Edit and Write that checks for an active beads task and tier assessment before every file modification. The hook warns but never blocks — a "smart nudge" that appears in-context at the moment the agent is about to act.

## Design

### New File: `hooks/pre-change-gate`

Bash script, ~30 lines. Runs on every Edit/Write tool call.

**Logic flow:**

1. **Guard: beads initialized?** Check for `.beads/` directory (project-local or `$HOME/.beads`). If neither exists, exit 0 silently.
2. **Guard: `bd` available?** If not in PATH, print warning and exit 0.
3. **Cache check.** Read `/tmp/.beads-gate-${USER}`. If file exists and is less than 60 seconds old, use cached values. Otherwise, query `bd` and write new cache.
4. **Query (on cache miss).** Run `bd list --status=in_progress`, count matching issues. If any found, extract the first task ID and run `bd show <id>` to check its notes for a `tier:` string. If multiple tasks are in-progress, checking the first one is sufficient — the goal is "did the agent assess tier at all," not "did every task get assessed."
5. **Warn if no active task.** Print:
   ```
   No active beads task. Create one before modifying files:
      bd create --title="..." --type=task
   ```
6. **Warn if no tier assessment.** Print:
   ```
   Active task has no tier assessment. Run /claude-workstation:start to assess.
   ```
7. **Always exit 0.** Never blocks the Edit/Write operation.

**Cache format** (`/tmp/.beads-gate-${USER}`):

```
TASK_COUNT=<n>
HAS_TIER=<yes|no>
```

TTL-based invalidation only (60 seconds). No explicit invalidation on `bd create` or `bd close` — after 60 seconds the next check picks up the new state. Acceptable lag for simplicity.

### Modified File: `hooks/hooks.json`

Add a `PreToolUse` key with two entries:

```json
"PreToolUse": [
  {
    "matcher": "Edit",
    "hooks": [
      {
        "type": "command",
        "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pre-change-gate\""
      }
    ]
  },
  {
    "matcher": "Write",
    "hooks": [
      {
        "type": "command",
        "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pre-change-gate\""
      }
    ]
  }
]
```

Existing SessionStart and Stop entries are unchanged.

### Modified File: `hooks/stop`

Add cache cleanup at the end of the script, before the final reminder line:

```bash
rm -f "/tmp/.beads-gate-${USER}"
```

### Modified File: `tests/validate-config.sh`

Add validation checks:

1. `hooks.json` contains PreToolUse entries with matchers for Edit and Write.
2. `hooks/pre-change-gate` exists and is executable.
3. `hooks/pre-change-gate` exits 0 when run outside a beads-initialized project (guard clause works).

## Scope

| Deliverable | Type |
|---|---|
| `hooks/pre-change-gate` | New file (~30 lines) |
| `hooks/hooks.json` | Modified — add PreToolUse |
| `hooks/stop` | Modified — add cache cleanup |
| `tests/validate-config.sh` | Modified — add new hook validation |

## What This Does NOT Do

- Does not block any tool calls (always exit 0)
- Does not gate Bash commands (only Edit and Write)
- Does not unify the verification entry points (separate future work)
- Does not upgrade the stop hook to gate on verification (separate future work)
- Does not add a Ralph-style re-injection loop (separate future work)

## Success Criteria

- Agent that tries to Edit/Write without a beads task sees the warning in context
- Agent that has an in-progress task without tier assessment sees the tier warning
- Hook adds no more than ~300ms to Edit/Write calls (cache keeps repeat calls fast)
- Hook never blocks or breaks existing workflows
- Existing tests pass, new validation checks pass
