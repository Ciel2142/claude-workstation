# Pre-Change Gate Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a PreToolUse hook on Edit/Write that warns the agent when no beads task is active or when the active task has no tier assessment.

**Architecture:** Single bash script (`hooks/pre-change-gate`) registered in `hooks/hooks.json` for Edit and Write matchers. Uses a 60-second file-based cache to avoid repeated `bd` queries. Stop hook cleans up cache on session end.

**Tech Stack:** Bash, beads CLI (`bd`), existing hooks.json plugin hook system.

---

### Task 1: Add validation checks to test suite

**Files:**
- Modify: `tests/validate-config.sh:386` (before the Summary section)

- [ ] **Step 1: Write the failing validation checks**

Add a new section 15 to `tests/validate-config.sh`, inserted before the `# --- Summary ---` line (line 388):

```bash
# --- 15. Pre-change gate hook ---
echo "15. Pre-change gate hook"

# 15a. hooks.json has PreToolUse entries
if python3 -c "
import json
d = json.load(open('$PLUGIN_ROOT/hooks/hooks.json'))
hooks = d['hooks']
assert 'PreToolUse' in hooks, 'PreToolUse not found'
entries = hooks['PreToolUse']
matchers = [e['matcher'] for e in entries]
assert 'Edit' in matchers, 'Edit matcher not found'
assert 'Write' in matchers, 'Write matcher not found'
for e in entries:
    for h in e['hooks']:
        assert 'type' in h, 'hook entry missing type'
        assert 'command' in h, 'hook entry missing command'
        assert 'pre-change-gate' in h['command'], 'command does not reference pre-change-gate'
" 2>/dev/null; then
    pass "hooks.json has PreToolUse entries for Edit and Write"
else
    fail "hooks.json MISSING PreToolUse entries for Edit and Write"
fi

# 15b. pre-change-gate script exists and is executable
if [[ -f "$PLUGIN_ROOT/hooks/pre-change-gate" ]]; then
    pass "hooks/pre-change-gate exists"
    if [[ -x "$PLUGIN_ROOT/hooks/pre-change-gate" ]]; then
        pass "hooks/pre-change-gate is executable"
    else
        fail "hooks/pre-change-gate is NOT executable"
    fi
else
    fail "hooks/pre-change-gate MISSING"
fi

# 15c. pre-change-gate exits 0 outside a beads project (guard clause)
if (cd /tmp && bash "$PLUGIN_ROOT/hooks/pre-change-gate") 2>/dev/null; then
    pass "hooks/pre-change-gate exits 0 outside beads project"
else
    fail "hooks/pre-change-gate does NOT exit 0 outside beads project"
fi

# 15d. stop hook cleans up cache file
if grep -q 'beads-gate' "$PLUGIN_ROOT/hooks/stop" 2>/dev/null; then
    pass "hooks/stop includes cache cleanup for beads-gate"
else
    fail "hooks/stop MISSING cache cleanup for beads-gate"
fi

echo ""
```

- [ ] **Step 2: Run the validation to verify checks fail**

Run: `CLAUDE_PLUGIN_ROOT=/home/igi21/work/claude-workstation bash /home/igi21/work/claude-workstation/tests/validate-config.sh 2>&1 | grep -A2 "15\. Pre-change"`
Expected: FAIL on all 4 checks (15a-15d) since the hook doesn't exist yet.

---

### Task 2: Create the pre-change-gate script

**Files:**
- Create: `hooks/pre-change-gate`

- [ ] **Step 1: Create the hook script**

Create `hooks/pre-change-gate` with the following content:

```bash
#!/usr/bin/env bash
# Pre-change gate: nudges agent to create beads task before file edits.
# Registered as PreToolUse hook for Edit and Write in hooks.json.
# Always exits 0 — warns but never blocks.

set -euo pipefail

# --- Guards ---

# Only run if beads is initialized (project-local or global)
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
BEADS_DIR="${GIT_ROOT:+$GIT_ROOT/.beads}"

if [ -z "$BEADS_DIR" ] || { [ ! -d "$BEADS_DIR" ] && [ ! -d "$HOME/.beads" ]; }; then
    exit 0
fi

# Check bd availability
if ! command -v bd >/dev/null 2>&1; then
    exit 0
fi

# --- Cache ---

CACHE="/tmp/.beads-gate-${USER}"

if [ -f "$CACHE" ]; then
    CACHE_MOD=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if [ $(( NOW - CACHE_MOD )) -lt 60 ]; then
        cat "$CACHE"
        exit 0
    fi
fi

# --- Check ---

OUTPUT=""
LISTING=$(bd list --status=in_progress 2>/dev/null || echo "")
TASK_ID=$(echo "$LISTING" | grep -v 'No issues' | awk 'NF>0{print $1; exit}')

if [ -z "$TASK_ID" ]; then
    OUTPUT=$(printf '%s\n%s' \
        "WARNING: No active beads task. Create one before modifying files:" \
        "   bd create --title=\"...\" --type=task")
else
    NOTES=$(bd show "$TASK_ID" 2>/dev/null || echo "")
    if ! echo "$NOTES" | grep -q 'tier:'; then
        OUTPUT="WARNING: Active task ($TASK_ID) has no tier assessment. Run /claude-workstation:start to assess."
    fi
fi

# --- Cache and output ---

printf '%s' "$OUTPUT" > "$CACHE"

if [ -n "$OUTPUT" ]; then
    echo "$OUTPUT"
fi

exit 0
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x /home/igi21/work/claude-workstation/hooks/pre-change-gate`

- [ ] **Step 3: Verify the script exits 0 outside a beads project**

Run: `(cd /tmp && bash /home/igi21/work/claude-workstation/hooks/pre-change-gate); echo "exit: $?"`
Expected: No output, `exit: 0`

---

### Task 3: Update hooks.json with PreToolUse entries

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Add PreToolUse entries to hooks.json**

Replace the entire `hooks/hooks.json` content with:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/stop\""
          }
        ]
      }
    ],
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
  }
}
```

- [ ] **Step 2: Validate JSON is well-formed**

Run: `python3 -c "import json; json.load(open('/home/igi21/work/claude-workstation/hooks/hooks.json')); print('valid')"`
Expected: `valid`

---

### Task 4: Add cache cleanup to stop hook

**Files:**
- Modify: `hooks/stop:37` (before the final reminder line)

- [ ] **Step 1: Add cache cleanup line to hooks/stop**

Insert the following line before `echo "---"` (line 37) in `hooks/stop`:

```bash
# Clean up pre-change-gate cache
rm -f "/tmp/.beads-gate-${USER}"
```

- [ ] **Step 2: Verify stop hook still runs without error**

Run: `bash /home/igi21/work/claude-workstation/hooks/stop 2>/dev/null; echo "exit: $?"`
Expected: `exit: 0`

---

### Task 5: Run full validation suite

**Files:**
- None (verification only)

- [ ] **Step 1: Run the full validation suite**

Run: `CLAUDE_PLUGIN_ROOT=/home/igi21/work/claude-workstation bash /home/igi21/work/claude-workstation/tests/validate-config.sh 2>&1 | tail -20`
Expected: Section 15 shows all PASS. Summary shows 0 failures.

- [ ] **Step 2: Verify the existing section 10 (stop hook) still passes**

Run: `CLAUDE_PLUGIN_ROOT=/home/igi21/work/claude-workstation bash /home/igi21/work/claude-workstation/tests/validate-config.sh 2>&1 | grep -A5 "10\. Stop"`
Expected: All checks PASS, including "hooks/stop runs without error".

---

### Task 6: Commit

**Files:**
- All changed files from tasks 1-4

- [ ] **Step 1: Stage all changes**

```bash
git add hooks/pre-change-gate hooks/hooks.json hooks/stop tests/validate-config.sh
```

- [ ] **Step 2: Commit**

```bash
git commit -m "feat: add pre-change-gate hook to nudge beads task creation before file edits"
```
