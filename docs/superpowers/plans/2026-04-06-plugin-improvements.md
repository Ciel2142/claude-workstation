# Plugin Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four independent improvements to claude-workstation: bd-notes-append wrapper, behavioral tests, Medium+ simplification, /status skill.

**Architecture:** Each task is fully independent — no ordering dependencies. All changes are bash scripts and markdown files within the existing plugin structure.

**Tech Stack:** Bash, Markdown, jq-free parsing (keep existing dependency profile)

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| Create | `hooks/bd-notes-append` | Append-safe wrapper for bd update --notes |
| Create | `tests/test-behaviors.sh` | Behavioral tests for hooks and position detection |
| Create | `skills/status/SKILL.md` | Read-only orientation skill |
| Modify | `skills/beads-milestones/SKILL.md` | Reference bd-notes-append instead of cumulative pattern |
| Modify | `skills/start/SKILL.md` | Use bd-notes-append for tier note |
| Modify | `commands/help.md` | Restructure Medium+ into core + optional |
| Modify | `contexts/workflow.md` | Update Medium+ flow string |
| Modify | `skills/test/SKILL.md` | Add behavioral tests section, update skill count |
| Modify | `tests/validate-config.sh` | Add status skill to checks |
| Modify | `README.md` | Add /status to commands table, update structure |

---

### Task 1: bd-notes-append wrapper

**Files:**
- Create: `hooks/bd-notes-append`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Append a line to beads task notes without losing existing content.
# Usage: bd-notes-append <task-id> "key: value"
# Reads current notes from bd show, appends new line, writes back.
# Always exits 0 on success, 1 on failure.

set -euo pipefail

TASK_ID="${1:-}"
NEW_LINE="${2:-}"

if [ -z "$TASK_ID" ] || [ -z "$NEW_LINE" ]; then
    echo "Usage: bd-notes-append <task-id> \"key: value\"" >&2
    exit 1
fi

if ! command -v bd >/dev/null 2>&1; then
    echo "error: bd not found in PATH" >&2
    exit 1
fi

# Extract current notes from bd show output.
# Notes section starts after "NOTES" line and runs to end of output
# (or next section header like DEPENDENCIES, DESIGN, etc.)
CURRENT_NOTES=$(bd show "$TASK_ID" 2>/dev/null \
    | sed -n '/^NOTES$/,/^[A-Z][A-Z]*$/p' \
    | sed '1d;$d' \
    | sed '/^$/d')

if [ -z "$CURRENT_NOTES" ]; then
    bd update "$TASK_ID" --notes "$NEW_LINE"
else
    bd update "$TASK_ID" --notes "${CURRENT_NOTES}
${NEW_LINE}"
fi
```

- [ ] **Step 2: Make executable**

Run: `chmod +x hooks/bd-notes-append`

- [ ] **Step 3: Verify it runs without error (no-op check)**

Run: `bash hooks/bd-notes-append 2>&1 || true`
Expected: Usage message to stderr, exit 1

- [ ] **Step 4: Commit**

```bash
git add hooks/bd-notes-append
git commit -m "feat: add bd-notes-append wrapper for safe milestone updates"
```

---

### Task 2: Update beads-milestones skill to use wrapper

**Files:**
- Modify: `skills/beads-milestones/SKILL.md`

- [ ] **Step 1: Replace the "How to Update" section**

Replace the current section that teaches the cumulative `bd update --notes` pattern with:

```markdown
## How to Update

```
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
bash "$PLUGIN_ROOT/hooks/bd-notes-append" <id> "key: value"
```

The wrapper reads current notes and appends — no need to include previous
milestones manually.

If the wrapper is not available, fall back to cumulative update:
```
bd update <id> --notes "<all previous lines>
<new line>"
```
Each `bd update --notes` call **replaces** previous notes, so include all
milestone state in the fallback.
```

- [ ] **Step 2: Remove the warning about replacement**

Remove or simplify the "replaces previous notes" warning in the Rules section — the wrapper handles it. Keep a brief note about fallback behavior.

- [ ] **Step 3: Commit**

```bash
git add skills/beads-milestones/SKILL.md
git commit -m "docs: update beads-milestones to use bd-notes-append wrapper"
```

---

### Task 3: Update start skill to use wrapper

**Files:**
- Modify: `skills/start/SKILL.md`

- [ ] **Step 1: Replace the notes update in Step 5 (CREATE)**

Find the line in Step 5:
```markdown
bd update <task-id> --notes "tier: <trivial|small|medium+>"
```

Replace with:
```markdown
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
bash "$PLUGIN_ROOT/hooks/bd-notes-append" <task-id> "tier: <trivial|small|medium+>"
```

- [ ] **Step 2: Commit**

```bash
git add skills/start/SKILL.md
git commit -m "docs: update start skill to use bd-notes-append wrapper"
```

---

### Task 4: Behavioral tests — bd-notes-append

**Files:**
- Create: `tests/test-behaviors.sh` (first section)

- [ ] **Step 1: Write test harness and bd-notes-append tests**

```bash
#!/usr/bin/env bash
# Behavioral tests for claude-workstation hooks and skills.
# Tests actual hook behavior using mocked bd commands.
set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "=== Claude Workstation Behavioral Tests ==="
echo ""

# --- Setup: create temp dir for mocks ---
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT

# Helper: create a mock bd script that returns canned output
setup_mock_bd() {
    local show_output="$1"
    local list_output="${2:-No issues found.}"
    cat > "$MOCK_DIR/bd" <<MOCK_EOF
#!/usr/bin/env bash
case "\$1" in
    show)
        cat <<'SHOW_EOF'
$show_output
SHOW_EOF
        ;;
    list)
        cat <<'LIST_EOF'
$list_output
LIST_EOF
        ;;
    update)
        # Capture the --notes value for assertion
        for arg in "\$@"; do
            case "\$arg" in
                --notes=*) echo "\${arg#--notes=}" > "$MOCK_DIR/last_notes" ;;
            esac
        done
        # Also handle --notes "value" (space-separated)
        CAPTURE_NEXT=false
        for arg in "\$@"; do
            if \$CAPTURE_NEXT; then
                echo "\$arg" > "$MOCK_DIR/last_notes"
                CAPTURE_NEXT=false
            fi
            if [ "\$arg" = "--notes" ]; then
                CAPTURE_NEXT=true
            fi
        done
        echo "✓ Updated"
        ;;
    *)
        echo "mock: unknown command \$1" >&2
        ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/bd"
}

# --- 1. bd-notes-append tests ---
echo "1. bd-notes-append"

# 1a. Empty notes — should write just the new line
setup_mock_bd "◐ test-123 [TASK] · Test task   [● P2 · IN_PROGRESS]
Owner: user · Type: task
Created: 2026-04-06 · Updated: 2026-04-06

DESCRIPTION
Test description

NOTES
"
PATH="$MOCK_DIR:$PATH" bash "$PLUGIN_ROOT/hooks/bd-notes-append" test-123 "tier: small" >/dev/null 2>&1
LAST_NOTES=$(cat "$MOCK_DIR/last_notes" 2>/dev/null || echo "")
if [ "$LAST_NOTES" = "tier: small" ]; then
    pass "bd-notes-append: empty notes writes new line only"
else
    fail "bd-notes-append: empty notes — expected 'tier: small', got '$LAST_NOTES'"
fi

# 1b. Existing notes — should append
setup_mock_bd "◐ test-123 [TASK] · Test task   [● P2 · IN_PROGRESS]
Owner: user · Type: task
Created: 2026-04-06 · Updated: 2026-04-06

DESCRIPTION
Test description

NOTES
tier: small"
PATH="$MOCK_DIR:$PATH" bash "$PLUGIN_ROOT/hooks/bd-notes-append" test-123 "plan: docs/plan.md" >/dev/null 2>&1
LAST_NOTES=$(cat "$MOCK_DIR/last_notes" 2>/dev/null || echo "")
EXPECTED="tier: small
plan: docs/plan.md"
if [ "$LAST_NOTES" = "$EXPECTED" ]; then
    pass "bd-notes-append: existing notes appends correctly"
else
    fail "bd-notes-append: existing notes — expected preserved + appended"
fi

# 1c. No arguments — should exit 1 with usage
if PATH="$MOCK_DIR:$PATH" bash "$PLUGIN_ROOT/hooks/bd-notes-append" 2>/dev/null; then
    fail "bd-notes-append: no args should exit 1"
else
    pass "bd-notes-append: no args exits 1"
fi

echo ""
```

- [ ] **Step 2: Make executable**

Run: `chmod +x tests/test-behaviors.sh`

- [ ] **Step 3: Run and verify**

Run: `bash tests/test-behaviors.sh`
Expected: 3/3 passing for bd-notes-append section

- [ ] **Step 4: Commit**

```bash
git add tests/test-behaviors.sh
git commit -m "test: add behavioral tests — bd-notes-append"
```

---

### Task 5: Behavioral tests — pre-change-gate

**Files:**
- Modify: `tests/test-behaviors.sh`

- [ ] **Step 1: Add pre-change-gate tests after the bd-notes-append section**

```bash
# --- 2. Pre-change-gate tests ---
echo "2. Pre-change-gate"

# Must clear cache between tests
BEADS_PATH="$PLUGIN_ROOT/.beads"
PROJECT_HASH=$(printf '%s' "$BEADS_PATH" | md5sum 2>/dev/null | cut -c1-8 || printf '%s' "$BEADS_PATH" | md5 2>/dev/null | cut -c1-8 || echo "default")
GATE_CACHE="/tmp/.beads-gate-${USER:-$(id -un)}-${PROJECT_HASH}"

# 2a. No task in progress — should warn
setup_mock_bd "" "No issues found."
rm -f "$GATE_CACHE"
GATE_OUT=$(cd "$PLUGIN_ROOT" && PATH="$MOCK_DIR:$PATH" bash "$PLUGIN_ROOT/hooks/pre-change-gate" 2>/dev/null || echo "")
if echo "$GATE_OUT" | grep -q "WARNING.*No active beads task"; then
    pass "pre-change-gate: warns when no task in progress"
else
    fail "pre-change-gate: should warn when no task — got: $GATE_OUT"
fi

# 2b. Task exists but no tier — should warn about tier
setup_mock_bd "◐ test-456 [TASK] · Test   [● P2 · IN_PROGRESS]
Owner: user · Type: task

DESCRIPTION
Test

NOTES
" "  test-456  IN_PROGRESS  Test task"
rm -f "$GATE_CACHE"
GATE_OUT=$(cd "$PLUGIN_ROOT" && PATH="$MOCK_DIR:$PATH" bash "$PLUGIN_ROOT/hooks/pre-change-gate" 2>/dev/null || echo "")
if echo "$GATE_OUT" | grep -q "WARNING.*no tier"; then
    pass "pre-change-gate: warns when task has no tier"
else
    fail "pre-change-gate: should warn about missing tier — got: $GATE_OUT"
fi

# 2c. Task exists with tier — should be silent
setup_mock_bd "◐ test-456 [TASK] · Test   [● P2 · IN_PROGRESS]
Owner: user · Type: task

DESCRIPTION
Test

NOTES
tier: small" "  test-456  IN_PROGRESS  Test task"
rm -f "$GATE_CACHE"
GATE_OUT=$(cd "$PLUGIN_ROOT" && PATH="$MOCK_DIR:$PATH" bash "$PLUGIN_ROOT/hooks/pre-change-gate" 2>/dev/null || echo "")
if [ -z "$GATE_OUT" ]; then
    pass "pre-change-gate: silent when task has tier"
else
    fail "pre-change-gate: should be silent — got: $GATE_OUT"
fi

echo ""
```

- [ ] **Step 2: Run and verify**

Run: `bash tests/test-behaviors.sh`
Expected: 6/6 passing (3 bd-notes-append + 3 pre-change-gate)

- [ ] **Step 3: Commit**

```bash
git add tests/test-behaviors.sh
git commit -m "test: add behavioral tests — pre-change-gate"
```

---

### Task 6: Behavioral tests — position detection

**Files:**
- Modify: `tests/test-behaviors.sh`

- [ ] **Step 1: Add position detection tests**

The position detection algorithm is implemented as a bash function within the test file. This serves as a reference implementation that resume/SKILL.md instructions should produce equivalent results to.

```bash
# --- 3. Position detection ---
echo "3. Position detection"

# Reference implementation of resume position detection.
# resume/SKILL.md instructs Claude to follow this same logic.
detect_position() {
    local notes="$1"
    if echo "$notes" | grep -q 'docs-updated:'; then
        echo "post-update-docs"
    elif echo "$notes" | grep -q 'verification:'; then
        echo "post-verification"
    elif echo "$notes" | grep -q 'completed:'; then
        echo "mid-implementation"
    elif echo "$notes" | grep -q 'plan:'; then
        echo "post-planning"
    elif echo "$notes" | grep -q 'spec:'; then
        echo "post-brainstorming"
    elif echo "$notes" | grep -q 'debug:'; then
        echo "mid-debugging"
    elif echo "$notes" | grep -q 'tier:'; then
        echo "start"
    else
        echo "unknown"
    fi
}

# 3a. tier only → start
POS=$(detect_position "tier: small")
[ "$POS" = "start" ] && pass "position: tier only → start" || fail "position: tier only — expected start, got $POS"

# 3b. tier + spec → post-brainstorming
POS=$(detect_position "tier: medium+
spec: docs/specs/foo.md")
[ "$POS" = "post-brainstorming" ] && pass "position: tier+spec → post-brainstorming" || fail "position: tier+spec — expected post-brainstorming, got $POS"

# 3c. tier + spec + plan → post-planning
POS=$(detect_position "tier: medium+
spec: docs/specs/foo.md
plan: docs/plans/foo.md")
[ "$POS" = "post-planning" ] && pass "position: tier+spec+plan → post-planning" || fail "position: tier+spec+plan — expected post-planning, got $POS"

# 3d. with completed → mid-implementation
POS=$(detect_position "tier: medium+
spec: docs/specs/foo.md
plan: docs/plans/foo.md
completed: 1,2,3")
[ "$POS" = "mid-implementation" ] && pass "position: completed → mid-implementation" || fail "position: completed — expected mid-implementation, got $POS"

# 3e. with verification → post-verification
POS=$(detect_position "tier: medium+
verification: tests 47/47, build clean")
[ "$POS" = "post-verification" ] && pass "position: verification → post-verification" || fail "position: verification — expected post-verification, got $POS"

# 3f. with docs-updated → post-update-docs
POS=$(detect_position "tier: medium+
verification: tests 47/47
docs-updated: README refreshed")
[ "$POS" = "post-update-docs" ] && pass "position: docs-updated → post-update-docs" || fail "position: docs-updated — expected post-update-docs, got $POS"

# 3g. with debug → mid-debugging
POS=$(detect_position "tier: small
debug: root cause -- stale cache")
[ "$POS" = "mid-debugging" ] && pass "position: debug → mid-debugging" || fail "position: debug — expected mid-debugging, got $POS"

# 3h. empty notes → unknown
POS=$(detect_position "")
[ "$POS" = "unknown" ] && pass "position: empty → unknown" || fail "position: empty — expected unknown, got $POS"

echo ""
```

- [ ] **Step 2: Run and verify**

Run: `bash tests/test-behaviors.sh`
Expected: 14/14 passing (3 + 3 + 8)

- [ ] **Step 3: Commit**

```bash
git add tests/test-behaviors.sh
git commit -m "test: add behavioral tests — position detection"
```

---

### Task 7: Behavioral tests — stop hook + summary

**Files:**
- Modify: `tests/test-behaviors.sh`

- [ ] **Step 1: Add stop hook tests and summary footer**

```bash
# --- 4. Stop hook ---
echo "4. Stop hook"

# 4a. No commits, no tasks — should be silent (no warning)
setup_mock_bd "" "No issues found."
# Mock git log to return 0 commits
cat > "$MOCK_DIR/git" <<'GITEOF'
#!/usr/bin/env bash
case "$1 $2" in
    "log --oneline") echo "" ;;
    "rev-parse --show-toplevel") echo "/tmp/test-repo" ;;
    *) command git "$@" ;;
esac
GITEOF
chmod +x "$MOCK_DIR/git"
STOP_OUT=$(PATH="$MOCK_DIR:$PATH" bash "$PLUGIN_ROOT/hooks/stop" 2>/dev/null || echo "")
if echo "$STOP_OUT" | grep -q "WARNING"; then
    fail "stop hook: warns on clean session (no commits, no tasks)"
else
    pass "stop hook: silent on clean session"
fi

# 4b. Commits + closed tasks — should NOT warn (tracked work)
setup_mock_bd "" "No issues found."
# Override list to return closed tasks for the closed check
cat > "$MOCK_DIR/bd" <<'BDEOF'
#!/usr/bin/env bash
case "$*" in
    *--status=in_progress*) echo "No issues found." ;;
    *--status=closed*) echo "  test-closed  CLOSED  Done task" ;;
    *--status=open*) echo "No issues found." ;;
    *) echo "No issues found." ;;
esac
BDEOF
chmod +x "$MOCK_DIR/bd"
cat > "$MOCK_DIR/git" <<'GITEOF'
#!/usr/bin/env bash
case "$1 $2" in
    "log --oneline") echo "abc1234 feat: something" ;;
    "rev-parse --show-toplevel") echo "/tmp/test-repo" ;;
    *) command git "$@" ;;
esac
GITEOF
chmod +x "$MOCK_DIR/git"
STOP_OUT=$(PATH="$MOCK_DIR:$PATH" bash "$PLUGIN_ROOT/hooks/stop" 2>/dev/null || echo "")
if echo "$STOP_OUT" | grep -q "WARNING.*NO beads issues"; then
    fail "stop hook: false-positive warning when closed tasks exist"
else
    pass "stop hook: no warning when closed tasks exist"
fi

echo ""

# --- Summary ---
echo "=== Behavioral Test Summary ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "✅ All behavioral tests passed"
    exit 0
else
    echo "❌ $FAIL behavioral test(s) failed"
    exit 1
fi
```

- [ ] **Step 2: Run full suite**

Run: `bash tests/test-behaviors.sh`
Expected: 16/16 passing

- [ ] **Step 3: Commit**

```bash
git add tests/test-behaviors.sh
git commit -m "test: add behavioral tests — stop hook + summary"
```

---

### Task 8: Medium+ ceremony simplification — help.md

**Files:**
- Modify: `commands/help.md`

- [ ] **Step 1: Restructure the Medium+ Path section**

Replace the current numbered 1-11 list (lines 97-128) with:

```markdown
## Medium+ Path

Core flow:
```
1. EPIC       bd create --title="..." --type=epic
2. BRAINSTORM superpowers:brainstorming
               Output: design doc in docs/superpowers/specs/
               bd update <epic-id> --notes "spec: <path>"
3. PLAN       superpowers:writing-plans
               Output: plan in docs/superpowers/plans/
               bd update <epic-id> --notes "plan: <path>"
4. SUB-TASKS  For each plan step:
               bd create --title="Step N: ..." --type=task
               bd dep add <sub-id> <epic-id>
               bd dep add <sub-id> <prev-sub-id>  (only if genuinely sequential)
               bd update <epic-id> --notes "planned-tasks: N"
5. IMPLEMENT  bd ready → claim ALL ready tasks (not just one)
               For independent ready tasks: dispatch parallel agents
               (superpowers:dispatching-parallel-agents)
               For each sub-task:
               ├─ Assess micro-tier (see Sub-task Micro-tiers rule)
               ├─ bd update <sub-id> --notes "micro-tier: <tier>"
               ├─ TDD per micro-tier (micro/full)
               ├─ Commit after each green
               ├─ Code review per micro-tier (individual/batch)
               └─ bd close <sub-id>
               Scope health check every 3 closed sub-tasks.
               Repeat until bd ready shows no more sub-tasks.
6. VERIFY     superpowers:verification-before-completion
7. CLOSE      bd close <epic-id>
```

Use when needed:
```
- SPIKE        Before IMPLEMENT, when architecture assumptions are unverified
               (see spike-phase skill)
- WORKTREE     Before IMPLEMENT, when isolating risk on a feature branch
               superpowers:using-git-worktrees
- UPDATE-DOCS  After VERIFY, when public API or project docs changed
               /ecc:update-docs
- FINISH       After VERIFY, when on a feature branch that needs merging
               superpowers:finishing-a-development-branch
```
```

- [ ] **Step 2: Verify help.md still passes config validation**

Run: `bash tests/validate-config.sh`
Expected: All checks pass (keyword checks for "Pre-Change Gate", "Scope Confirmation", "Task Boundary", "Spec Amendments", "Micro-tier", "Sub-task Dependencies" must still be present)

- [ ] **Step 3: Commit**

```bash
git add commands/help.md
git commit -m "docs: restructure Medium+ path — core flow + optional steps"
```

---

### Task 9: Medium+ ceremony simplification — workflow.md

**Files:**
- Modify: `contexts/workflow.md`

- [ ] **Step 1: Update the tier table Medium+ flow string**

Find the Medium+ row in the Task Sizing table (line 15):
```
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | `bd create -t epic` → brainstorm → plan → sub-tasks → spike → worktree → TDD → review → verify → /ecc:update-docs → finish → `bd close` |
```

Replace with:
```
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | `bd create -t epic` → brainstorm → plan → sub-tasks → TDD → verify → `bd close` (+ spike, worktree, update-docs, finish when applicable) |
```

- [ ] **Step 2: Run config validation**

Run: `bash tests/validate-config.sh`
Expected: All checks pass

- [ ] **Step 3: Commit**

```bash
git add contexts/workflow.md
git commit -m "docs: simplify Medium+ flow in workflow context — mark optional steps"
```

---

### Task 10: /status skill

**Files:**
- Create: `skills/status/SKILL.md`

- [ ] **Step 1: Write the skill**

```markdown
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
| start (task, trivial) | Go fix it, then `bd close <id>` |
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
```

- [ ] **Step 2: Commit**

```bash
git add skills/status/SKILL.md
git commit -m "feat: add /status skill — read-only work orientation"
```

---

### Task 11: Update validate-config.sh for status skill

**Files:**
- Modify: `tests/validate-config.sh`

- [ ] **Step 1: Add status to skill directory checks**

In section 8 (line 162), add `status` to the skill list:

```bash
for skill_dir in start resume setup test debugging-protocol beads-milestones spike-phase scope-health verification-template status; do
```

- [ ] **Step 2: Add status to frontmatter checks**

In section 9 (line 175), add `status` to the skill list:

```bash
for skill_dir in start resume setup test debugging-protocol beads-milestones spike-phase scope-health verification-template status; do
```

- [ ] **Step 3: Run validation**

Run: `bash tests/validate-config.sh`
Expected: All checks pass (should now be 157+ checks)

- [ ] **Step 4: Commit**

```bash
git add tests/validate-config.sh
git commit -m "test: add status skill to config validation checks"
```

---

### Task 12: Update test skill, README, and integration

**Files:**
- Modify: `skills/test/SKILL.md`
- Modify: `README.md`

- [ ] **Step 1: Update test/SKILL.md**

Add behavioral tests section after "## Full Dry-Run Scenarios":

```markdown
## Behavioral Tests

Run hook and position detection behavioral tests:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(dirname "$0")")")}"
bash "$PLUGIN_ROOT/tests/test-behaviors.sh"
```
```

Update "### Config Validation" description:
- Change "155+ checks" to match new count after adding status skill
- Change "all 9 skills present" to "all 10 skills present"

Also add to "### What Gets Tested":
```markdown
### Behavioral Tests
1. bd-notes-append correctness (empty notes, append, error handling)
2. Pre-change-gate warning conditions (no task, no tier, has tier)
3. Position detection algorithm (all 7 milestone patterns + empty)
4. Stop hook warning conditions (clean, tracked, untracked)
```

- [ ] **Step 2: Update README.md**

Add `/claude-workstation:status` to the commands table:

```markdown
| `/claude-workstation:status` | Show current work state — position, next task, suggested skill |
```

Update the Project Structure to add `status/` under skills:

```markdown
│   ├── status/SKILL.md        # /status — read-only work orientation
```

Update the Hooks table if needed (no changes — status doesn't use hooks).

- [ ] **Step 3: Run full validation**

Run: `bash tests/validate-config.sh && bash tests/test-behaviors.sh`
Expected: All config + behavioral tests pass

- [ ] **Step 4: Commit**

```bash
git add skills/test/SKILL.md README.md
git commit -m "docs: add /status to README and test skill, update counts"
```

---

## Self-Review

**Spec coverage:**
- [x] bd-notes-append wrapper — Tasks 1-3
- [x] Behavioral tests — Tasks 4-7
- [x] Medium+ simplification — Tasks 8-9
- [x] /status skill — Tasks 10-12
- [x] validate-config.sh updates — Task 11
- [x] README/test skill updates — Task 12

**Placeholder scan:** No TBD/TODO. All code blocks are complete.

**Type consistency:** `detect_position` function in Task 6 uses same priority order as resume/SKILL.md Step 4 and status/SKILL.md Step 3. Milestone keys match beads-milestones/SKILL.md table. Verified.
