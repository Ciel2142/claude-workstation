# Enforcement Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace advisory-only workflow enforcement with hard-blocking hooks (`exit 2`) that prevent Claude from skipping bead tracking, TDD milestones, code reviews, and subagent protocol injection.

**Architecture:** Dual-layer enforcement — (1) bash hooks on PreToolUse/PostToolUse/Stop that read stdin JSON and check beads state, (2) subagent protocol templates with sentinel markers validated by an Agent-gate hook. Shared cache layer (`cache-utils.sh`) provides sub-second hot path via XDG_RUNTIME_DIR files with 60s TTL.

**Tech Stack:** Bash (hooks), Markdown (protocol templates), JSON (hooks.json config). Dependencies: `bd` CLI, `git`, POSIX tools, optional `python3` for JSON parsing.

**Spec:** `docs/superpowers/specs/2026-04-11-enforcement-hooks-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `hooks/cache-utils.sh` | Shared cache functions: active-task lookup, milestone fetch, edit counter, JSON field extraction |
| `hooks/milestone-gate` | PreToolUse (Edit\|Write) — `exit 2` without active claimed sub-task. Checks file exemptions. |
| `hooks/agent-gate` | PreToolUse (Agent) — `exit 2` without `BEAD-PROTOCOL-v1` sentinel in prompt |
| `hooks/commit-gate` | PreToolUse (Bash) — `exit 2` on `git commit` without `review:quality` milestone |
| `hooks/stop-gate` | Stop — `exit 2` unless all in-progress tasks have `verified` or `paused` |
| `hooks/mid-session-reminder` | PostToolUse (Edit\|Write) — advisory edit counter + status echo |
| `hooks/precompact-state` | PreCompact — dumps current workflow state before compaction |
| `templates/gate-exemptions.txt` | Glob patterns for files exempt from milestone-gate |
| `templates/protocol-base.md` | Shared bead tracking rules for all subagent types |
| `templates/protocol-implementer.md` | Full TDD milestone chain for code implementers |
| `templates/protocol-reviewer.md` | Review findings + side-quest creation protocol |
| `templates/protocol-planner.md` | Plan milestone tracking protocol |
| `templates/protocol-build-fixer.md` | Build fix milestone tracking protocol |

### Modified Files

| File | Change |
|------|--------|
| `hooks/hooks.json` | Replace pre-change-gate → milestone-gate; add agent-gate, commit-gate, stop-gate, mid-session-reminder, precompact-state entries |
| `hooks/bd-notes-append` | Add cache write-through after successful `bd update` |
| `CLAUDE.md` | Add enforcement hooks reference + milestone format + subagent protocol mandate |
| `skills/workflow/SKILL.md` | Add milestone tracking section + subagent protocol section |
| `tests/test-behaviors.sh` | Add Sections 12-17 for all new hooks |
| `tests/validate-config.sh` | Add validation for new hooks + templates |
| `hooks/session-start` | Add echo workflow reminder (enforcement hooks active) |
| `hooks/stop` | Update cache cleanup `rm -f` → `rm -rf` for directory cache |
| `skills/start/SKILL.md` | Add note about sub-task creation + milestone tracking after planning |

### Retired

| File | Reason |
|------|--------|
| `hooks/pre-change-gate` | Replaced by `hooks/milestone-gate` (hard-blocking, milestone-aware, exemption-aware) |

---

### Task 1: Cache Utilities Foundation

**Files:**
- Create: `hooks/cache-utils.sh`

This is the shared infrastructure used by all gate hooks. No separate test — tested transitively through hooks.

- [ ] **Step 1: Create hooks/cache-utils.sh**

```bash
#!/usr/bin/env bash
# Shared cache utilities for enforcement hooks.
# Source this file: . "$(dirname "$0")/cache-utils.sh"
#
# Cache structure (per-project directory):
#   $GATE_CACHE_DIR/active-task          — current sub-task ID
#   $GATE_CACHE_DIR/milestones-<task-id> — cached [M] milestone lines
#   $GATE_CACHE_DIR/edit-counter         — edits since last milestone update

# --- Cache Directory ---

_compute_cache_dir() {
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    local beads_path="${git_root:+$git_root/.beads}"
    beads_path="${beads_path:-$HOME/.beads}"
    local project_hash
    project_hash=$(printf '%s' "$beads_path" | md5sum 2>/dev/null | cut -c1-8 \
        || printf '%s' "$beads_path" | md5 2>/dev/null | cut -c1-8 \
        || echo "default")
    local base_dir="${XDG_RUNTIME_DIR:-/tmp}"
    echo "${base_dir}/.beads-gate-${USER:-$(id -un)}-${project_hash}"
}

GATE_CACHE_DIR=$(_compute_cache_dir)

ensure_cache_dir() {
    if [ -L "$GATE_CACHE_DIR" ]; then
        rm -f "$GATE_CACHE_DIR"
    fi
    # Remove old-format single-file cache if present (migration from pre-change-gate)
    if [ -f "$GATE_CACHE_DIR" ]; then
        rm -f "$GATE_CACHE_DIR"
    fi
    mkdir -p "$GATE_CACHE_DIR"
}

# --- Timeout Wrapper ---

if command -v timeout >/dev/null 2>&1; then
    BD_TIMEOUT="timeout 5"
else
    BD_TIMEOUT=""
fi

# --- Beads Guards ---

# Check if beads is usable. Sets GIT_ROOT. Returns 1 if not usable.
check_beads_available() {
    GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    local beads_dir="${GIT_ROOT:+$GIT_ROOT/.beads}"
    if [ -z "$beads_dir" ] || { [ ! -d "$beads_dir" ] && [ ! -d "$HOME/.beads" ]; }; then
        return 1
    fi
    if ! command -v bd >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# --- JSON Field Extraction ---

# Extract a dotted field path from JSON string.
# Usage: json_field "$json_string" "tool_input.file_path"
# Tries python3 for reliability, grep fallback for leaf key.
json_field() {
    local json="$1"
    local path="$2"

    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for k in '${path}'.split('.'):
        d = d.get(k, {}) if isinstance(d, dict) else {}
    print(d if isinstance(d, str) else '')
except:
    print('')" 2>/dev/null || echo ""
    else
        # Grep fallback: extract leaf key value (works for non-nested unique keys)
        local key="${path##*.}"
        printf '%s' "$json" | grep -o "\"${key}\": *\"[^\"]*\"" | head -1 \
            | sed "s/\"${key}\": *\"//;s/\"$//" || echo ""
    fi
}

# --- Active Task ---

# Returns: task ID, empty string (no tasks), or "BD_UNREACHABLE" (server down).
get_active_task() {
    ensure_cache_dir
    local cache_file="$GATE_CACHE_DIR/active-task"

    # Check cache freshness (< 60s)
    if [ -f "$cache_file" ] && [ ! -L "$cache_file" ]; then
        local mod now age
        mod=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        now=$(date +%s)
        age=$(( now - mod ))
        if [ "$age" -ge 0 ] && [ "$age" -lt 60 ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Query bd
    local task_id=""
    local bd_ok=true
    local listing_json=""
    listing_json=$($BD_TIMEOUT bd list --status=in_progress --json 2>/dev/null) || bd_ok=false

    if $bd_ok && [ -n "$listing_json" ] && [ "$listing_json" != "[]" ] && [ "$listing_json" != "null" ]; then
        task_id=$(printf '%s' "$listing_json" | grep -o '"id": *"[^"]*"' | head -1 | cut -d'"' -f4 2>/dev/null || echo "")
    fi

    # Fallback to text parsing
    if $bd_ok && [ -z "$task_id" ]; then
        local listing=""
        listing=$($BD_TIMEOUT bd list --status=in_progress 2>/dev/null) || bd_ok=false
        if $bd_ok; then
            task_id=$(echo "$listing" | grep -v 'No issues' | awk 'NR>1 && NF>0{print $1; exit}' || true)
        fi
    fi

    # If bd failed completely and no cached fallback, signal unreachable
    if ! $bd_ok && [ -z "$task_id" ]; then
        echo "BD_UNREACHABLE"
        return 0
    fi

    # Write cache atomically
    local tmp="${cache_file}.$$"
    printf '%s' "${task_id:-}" > "$tmp"
    mv -f "$tmp" "$cache_file"
    echo "${task_id:-}"
}

# --- Milestones ---

# Get [M] milestone lines from beads notes. Uses cache if fresh.
# Returns: milestone lines (may be empty), or "BD_UNREACHABLE".
get_milestones() {
    local task_id="$1"
    [ -z "$task_id" ] && return 0
    ensure_cache_dir
    local cache_file="$GATE_CACHE_DIR/milestones-${task_id}"

    # Check cache freshness
    if [ -f "$cache_file" ] && [ ! -L "$cache_file" ]; then
        local mod now age
        mod=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        now=$(date +%s)
        age=$(( now - mod ))
        if [ "$age" -ge 0 ] && [ "$age" -lt 60 ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Query bd show and extract [M] lines from notes
    local bd_ok=true
    local bd_output=""
    bd_output=$($BD_TIMEOUT bd show "$task_id" 2>/dev/null) || bd_ok=false

    if ! $bd_ok; then
        echo "BD_UNREACHABLE"
        return 0
    fi

    # Extract notes section, then grep [M] lines
    local notes
    notes=$(printf '%s\n' "$bd_output" \
        | sed -n '/^NOTES$/,$ p' \
        | sed '1d' \
        | sed '/^\(TITLE\|STATUS\|PRIORITY\|TYPE\|PARENT\|CHILDREN\|BLOCKS\|BLOCKED BY\|DEPENDS ON\|DEPENDENCIES\|LABELS\|ASSIGNEE\|CREATED\|UPDATED\|ACCEPTANCE CRITERIA\|DESIGN\|COMMENTS\|HISTORY\|ATTACHMENTS\|METADATA\|DESCRIPTION\|DUE\|DEFER\)$/,$d')

    local milestones
    milestones=$(printf '%s\n' "$notes" | grep '^\[M\] ' || echo "")

    # Write cache
    local tmp="${cache_file}.$$"
    printf '%s' "$milestones" > "$tmp"
    mv -f "$tmp" "$cache_file"
    echo "$milestones"
}

# Determine current phase from milestone lines (most advanced present).
get_current_phase() {
    local milestones="$1"
    local phases="verified review:quality review:spec tdd:refactor tdd:green-verified tdd:green tdd:red-verified tdd:red task:claimed task:created"
    for phase in $phases; do
        if printf '%s' "$milestones" | grep -q "^\[M\] ${phase}"; then
            echo "$phase"
            return 0
        fi
    done
    echo "none"
}

# Recommend next action based on current phase.
get_next_phase() {
    local current="$1"
    case "$current" in
        "none"|"")          echo "create sub-task bead" ;;
        "task:created")     echo "claim the task" ;;
        "task:claimed")     echo "write failing test (TDD red)" ;;
        "tdd:red")          echo "verify test fails" ;;
        "tdd:red-verified") echo "implement to pass test" ;;
        "tdd:green")        echo "verify all tests pass" ;;
        "tdd:green-verified") echo "refactor" ;;
        "tdd:refactor")     echo "run spec review" ;;
        "review:spec")      echo "run quality review" ;;
        "review:quality")   echo "verify before completion" ;;
        "verified")         echo "done — close task" ;;
        *)                  echo "update milestone" ;;
    esac
}

# --- Edit Counter ---

get_edit_count() {
    ensure_cache_dir
    local f="$GATE_CACHE_DIR/edit-counter"
    if [ -f "$f" ]; then cat "$f"; else echo "0"; fi
}

increment_edit_count() {
    ensure_cache_dir
    local f="$GATE_CACHE_DIR/edit-counter"
    local count
    count=$(get_edit_count)
    echo $(( count + 1 )) > "$f"
}

reset_edit_count() {
    ensure_cache_dir
    echo "0" > "$GATE_CACHE_DIR/edit-counter"
}

# --- Cache Management ---

invalidate_task_cache() {
    local task_id="$1"
    [ -n "$task_id" ] && rm -f "$GATE_CACHE_DIR/milestones-${task_id}"
    reset_edit_count
}

clean_cache() {
    rm -rf "$GATE_CACHE_DIR"
}
```

- [ ] **Step 2: Make executable**

Run: `chmod +x hooks/cache-utils.sh`

- [ ] **Step 3: Commit**

```bash
git add hooks/cache-utils.sh
git commit -m "feat: add shared cache utilities for enforcement hooks"
```

---

### Task 2: Gate Exemptions Config

**Files:**
- Create: `templates/gate-exemptions.txt`

- [ ] **Step 1: Create templates directory**

Run: `mkdir -p templates`

- [ ] **Step 2: Write gate-exemptions.txt**

```text
# File patterns exempt from milestone gate (PreToolUse Edit|Write).
# Exempt files can be edited without an active sub-task bead.
# One pattern per line. Comments start with #.
#
# Syntax:
#   *.ext         — match any file with extension
#   prefix/**     — match any file under prefix/
#   **/name/**    — match name/ anywhere in path
#   **/pattern.*  — match pattern.* anywhere in path

# Documentation
docs/**
*.md

# Beads internal state
.beads/**

# Specs and plans
docs/superpowers/**

# Claude config
.claude/**

# Test files (TDD: must write tests before production code)
**/testdata/**
**/*_test.*
**/*_test_*
**/test/**
**/*.test.*
**/*.spec.*
**/tests/**
**/__tests__/**
**/fixtures/**
```

- [ ] **Step 3: Commit**

```bash
git add templates/gate-exemptions.txt
git commit -m "feat: add gate exemptions config for milestone gate"
```

---

### Task 3: Milestone Gate

**Files:**
- Create: `hooks/milestone-gate`
- Test: `tests/test-behaviors.sh` (Section 12)

- [ ] **Step 1: Write failing tests in test-behaviors.sh**

Append to the end of `tests/test-behaviors.sh`, before the final summary block:

```bash
# ---------------------------------------------------------------------------
# Section 12: milestone-gate tests
# ---------------------------------------------------------------------------
echo ""
echo "12. milestone-gate"

# Reuse TMPDIR_BD mock directory from Section 1 setup

# Helper: compute gate cache dir (same logic as cache-utils.sh)
_gate_cache_dir() {
    local beads_path="$PLUGIN_ROOT/.beads"
    local project_hash
    project_hash=$(printf '%s' "$beads_path" | md5sum 2>/dev/null | cut -c1-8 \
        || printf '%s' "$beads_path" | md5 2>/dev/null | cut -c1-8 \
        || echo "default")
    local cache_dir="${XDG_RUNTIME_DIR:-/tmp}"
    echo "${cache_dir}/.beads-gate-${USER:-$(id -un)}-${project_hash}"
}
GATE_CACHE_NEW=$(_gate_cache_dir)

# 12a. No active task → exit 2
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
echo "No issues found"
MOCK
chmod +x "$TMPDIR_BD/bd"
rm -rf "$GATE_CACHE_NEW"

STDIN='{"tool_name":"Edit","tool_input":{"file_path":"'"${PLUGIN_ROOT}"'/hooks/cache-utils.sh"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/milestone-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 2 ] && echo "$OUTPUT" | grep -q "BLOCKED"; then
    pass "12a. milestone-gate: no active task → exit 2 BLOCKED"
else
    fail "12a. milestone-gate: expected exit 2 BLOCKED, got exit $EXIT_CODE: $OUTPUT"
fi

# 12b. Active task with [M] task:claimed → exit 0 with status
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo "ID        STATUS        TITLE"
        echo "abc-123   in_progress   Test task" ;;
    show)
        cat << 'BD_SHOW'
TITLE
Test task
STATUS
in_progress
NOTES
[M] task:created sub-task
[M] task:claimed work started
[M] tdd:red wrote failing test
PARENT
BD_SHOW
        ;;
esac
MOCK
chmod +x "$TMPDIR_BD/bd"
rm -rf "$GATE_CACHE_NEW"

STDIN='{"tool_name":"Edit","tool_input":{"file_path":"'"${PLUGIN_ROOT}"'/hooks/cache-utils.sh"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/milestone-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ] && echo "$OUTPUT" | grep -q "task:abc-123"; then
    pass "12b. milestone-gate: claimed task → exit 0 with status"
else
    fail "12b. milestone-gate: expected exit 0 + status, got exit $EXIT_CODE: $OUTPUT"
fi

# 12c. Active task WITHOUT [M] task:claimed → exit 2
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo "ID        STATUS        TITLE"
        echo "abc-123   in_progress   Test task" ;;
    show)
        cat << 'BD_SHOW'
TITLE
Test task
STATUS
in_progress
NOTES
[M] task:created sub-task
PARENT
BD_SHOW
        ;;
esac
MOCK
chmod +x "$TMPDIR_BD/bd"
rm -rf "$GATE_CACHE_NEW"

STDIN='{"tool_name":"Edit","tool_input":{"file_path":"'"${PLUGIN_ROOT}"'/hooks/cache-utils.sh"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/milestone-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 2 ] && echo "$OUTPUT" | grep -q "not claimed"; then
    pass "12c. milestone-gate: unclaimed task → exit 2"
else
    fail "12c. milestone-gate: expected exit 2 (unclaimed), got exit $EXIT_CODE: $OUTPUT"
fi

# 12d. Exempt file (*.md) → exit 0 silently even without task
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
echo "No issues found"
MOCK
chmod +x "$TMPDIR_BD/bd"
rm -rf "$GATE_CACHE_NEW"

STDIN='{"tool_name":"Write","tool_input":{"file_path":"'"${PLUGIN_ROOT}"'/README.md"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/milestone-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "12d. milestone-gate: exempt file (*.md) → exit 0"
else
    fail "12d. milestone-gate: expected exit 0 for *.md, got exit $EXIT_CODE"
fi

# 12e. Exempt file (docs/**) → exit 0
STDIN='{"tool_name":"Edit","tool_input":{"file_path":"'"${PLUGIN_ROOT}"'/docs/superpowers/specs/test.md"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/milestone-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "12e. milestone-gate: exempt file (docs/**) → exit 0"
else
    fail "12e. milestone-gate: expected exit 0 for docs/**, got exit $EXIT_CODE"
fi

# 12f. Exempt file (test file) → exit 0
STDIN='{"tool_name":"Write","tool_input":{"file_path":"'"${PLUGIN_ROOT}"'/tests/test-new.sh"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/milestone-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "12f. milestone-gate: exempt file (tests/**) → exit 0"
else
    fail "12f. milestone-gate: expected exit 0 for tests/**, got exit $EXIT_CODE"
fi

# 12g. BEADS_GATE_BYPASS=1 → exit 0 with warning
STDIN='{"tool_name":"Edit","tool_input":{"file_path":"'"${PLUGIN_ROOT}"'/hooks/cache-utils.sh"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" BEADS_GATE_BYPASS=1 bash "$PLUGIN_ROOT/hooks/milestone-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ] && echo "$OUTPUT" | grep -q "BEADS_GATE_BYPASS"; then
    pass "12g. milestone-gate: BEADS_GATE_BYPASS=1 → exit 0 with warning"
else
    fail "12g. milestone-gate: expected bypass warning, got exit $EXIT_CODE: $OUTPUT"
fi
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-behaviors.sh 2>&1 | tail -20`

Expected: Tests 12a-12g FAIL (milestone-gate script does not exist yet).

- [ ] **Step 3: Write hooks/milestone-gate**

```bash
#!/usr/bin/env bash
# Milestone gate: blocks Edit/Write without active sub-task bead + [M] task:claimed.
# Registered as PreToolUse hook for Edit and Write in hooks.json.
# Exit 2 = block. Exit 0 = allow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cache-utils.sh
. "$SCRIPT_DIR/cache-utils.sh"

PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXEMPTIONS_FILE="${PLUGIN_ROOT}/templates/gate-exemptions.txt"

# --- Bypass ---
if [ "${BEADS_GATE_BYPASS:-}" = "1" ]; then
    echo "⚠ BEADS_GATE_BYPASS=1 — milestone gate bypassed"
    exit 0
fi

# --- Guards ---
if ! check_beads_available; then
    exit 0
fi

# --- Read stdin JSON ---
STDIN=$(cat)
FILE_PATH=$(json_field "$STDIN" "tool_input.file_path")

# --- Check file exemptions ---
if [ -n "$FILE_PATH" ] && [ -f "$EXEMPTIONS_FILE" ]; then
    # Convert to path relative to git root
    REL_PATH="$FILE_PATH"
    if [ -n "$GIT_ROOT" ]; then
        REL_PATH="${FILE_PATH#$GIT_ROOT/}"
    fi

    while IFS= read -r pattern || [ -n "$pattern" ]; do
        # Skip comments and blank lines
        [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${pattern// /}" ]] && continue
        # Trim whitespace
        pattern="${pattern#"${pattern%%[![:space:]]*}"}"
        pattern="${pattern%"${pattern##*[![:space:]]}"}"

        matched=false
        case "$pattern" in
            "**/"*)
                # **/ prefix: match suffix anywhere in path
                suffix="${pattern#\*\*/}"
                # shellcheck disable=SC2254
                case "$REL_PATH" in
                    $suffix|*/$suffix) matched=true ;;
                esac
                ;;
            *"/**")
                # /** suffix: match any file under prefix
                prefix="${pattern%/\*\*}"
                [[ "$REL_PATH" == "$prefix/"* ]] && matched=true
                ;;
            *)
                # Simple glob (e.g., *.md)
                # shellcheck disable=SC2254
                case "$REL_PATH" in
                    $pattern) matched=true ;;
                esac
                ;;
        esac

        if $matched; then
            exit 0
        fi
    done < "$EXEMPTIONS_FILE"
fi

# --- Check active task ---
TASK_ID=$(get_active_task)

if [ "$TASK_ID" = "BD_UNREACHABLE" ]; then
    echo "⚠ Beads server unreachable — milestone gate bypassed. Re-run bd show when server recovers."
    exit 0
fi

if [ -z "$TASK_ID" ]; then
    echo "🚫 BLOCKED: No active sub-task bead. Create one before editing files:"
    echo "   bd create --title=\"...\" --type=task -p 2"
    echo "   bd dep add <new-id> <parent-id> --type parent-child"
    echo "   bd update <new-id> --claim"
    exit 2
fi

# --- Check milestones ---
MILESTONES=$(get_milestones "$TASK_ID")

if [ "$MILESTONES" = "BD_UNREACHABLE" ]; then
    echo "⚠ Beads server unreachable — milestone gate bypassed."
    exit 0
fi

if ! printf '%s' "$MILESTONES" | grep -q '^\[M\] task:claimed'; then
    echo "🚫 BLOCKED: Task $TASK_ID exists but not claimed. Claim it first:"
    echo "   bd update $TASK_ID --claim"
    echo "   bash \"\${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append\" $TASK_ID \"[M] task:claimed work started\""
    exit 2
fi

# --- Status line (always output on success) ---
PHASE=$(get_current_phase "$MILESTONES")
NEXT=$(get_next_phase "$PHASE")
echo "✓ task:${TASK_ID} | phase:${PHASE} | next: ${NEXT}"

exit 0
```

- [ ] **Step 4: Make executable**

Run: `chmod +x hooks/milestone-gate`

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/test-behaviors.sh 2>&1 | grep -E '12[a-g]\.'`

Expected: All 12a-12g PASS.

- [ ] **Step 6: Commit**

```bash
git add hooks/milestone-gate tests/test-behaviors.sh
git commit -m "feat: add milestone-gate hook — blocks Edit/Write without claimed sub-task"
```

---

### Task 4: Agent Gate

**Files:**
- Create: `hooks/agent-gate`
- Test: `tests/test-behaviors.sh` (Section 13)

- [ ] **Step 1: Write failing tests**

Append to `tests/test-behaviors.sh`:

```bash
# ---------------------------------------------------------------------------
# Section 13: agent-gate tests
# ---------------------------------------------------------------------------
echo ""
echo "13. agent-gate"

# 13a. Prompt without BEAD-PROTOCOL-v1 → exit 2
STDIN='{"tool_name":"Agent","tool_input":{"prompt":"Do the task without any protocol","description":"test"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | bash "$PLUGIN_ROOT/hooks/agent-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 2 ] && echo "$OUTPUT" | grep -q "BLOCKED"; then
    pass "13a. agent-gate: no sentinel → exit 2 BLOCKED"
else
    fail "13a. agent-gate: expected exit 2, got exit $EXIT_CODE: $OUTPUT"
fi

# 13b. Prompt with BEAD-PROTOCOL-v1 → exit 0
STDIN='{"tool_name":"Agent","tool_input":{"prompt":"Implement the feature.\n<!-- BEAD-PROTOCOL-v1:implementer -->","description":"test"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | bash "$PLUGIN_ROOT/hooks/agent-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "13b. agent-gate: sentinel present → exit 0"
else
    fail "13b. agent-gate: expected exit 0, got exit $EXIT_CODE: $OUTPUT"
fi

# 13c. Prompt with BEAD-EXEMPT:research → exit 0
STDIN='{"tool_name":"Agent","tool_input":{"prompt":"Research how auth works. BEAD-EXEMPT:research","description":"test"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | bash "$PLUGIN_ROOT/hooks/agent-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "13c. agent-gate: BEAD-EXEMPT:research → exit 0"
else
    fail "13c. agent-gate: expected exit 0 for exempt, got exit $EXIT_CODE: $OUTPUT"
fi

# 13d. BEADS_GATE_BYPASS=1 → exit 0
STDIN='{"tool_name":"Agent","tool_input":{"prompt":"No protocol","description":"test"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | BEADS_GATE_BYPASS=1 bash "$PLUGIN_ROOT/hooks/agent-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ] && echo "$OUTPUT" | grep -q "BEADS_GATE_BYPASS"; then
    pass "13d. agent-gate: BEADS_GATE_BYPASS=1 → exit 0 with warning"
else
    fail "13d. agent-gate: expected bypass, got exit $EXIT_CODE: $OUTPUT"
fi
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-behaviors.sh 2>&1 | grep -E '13[a-d]\.'`

Expected: Tests 13a-13d FAIL.

- [ ] **Step 3: Write hooks/agent-gate**

```bash
#!/usr/bin/env bash
# Agent gate: blocks Agent dispatch without BEAD-PROTOCOL-v1 sentinel in prompt.
# Registered as PreToolUse hook for Agent in hooks.json.
# Exit 2 = block. Exit 0 = allow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cache-utils.sh
. "$SCRIPT_DIR/cache-utils.sh"

# --- Bypass ---
if [ "${BEADS_GATE_BYPASS:-}" = "1" ]; then
    echo "⚠ BEADS_GATE_BYPASS=1 — agent gate bypassed"
    exit 0
fi

# --- Guards ---
if ! check_beads_available; then
    exit 0
fi

# --- Read stdin JSON ---
STDIN=$(cat)

# --- Check for exemptions ---
if printf '%s' "$STDIN" | grep -q 'BEAD-EXEMPT:research\|BEAD-EXEMPT:exploration'; then
    exit 0
fi

# --- Check for protocol sentinel ---
if printf '%s' "$STDIN" | grep -q 'BEAD-PROTOCOL-v1'; then
    exit 0
fi

# --- Block ---
echo "🚫 BLOCKED: Subagent prompt missing BEAD-PROTOCOL-v1 sentinel."
echo "   Include the appropriate protocol template in the prompt:"
echo "   - templates/protocol-implementer.md (code changes)"
echo "   - templates/protocol-reviewer.md (reviews)"
echo "   - templates/protocol-planner.md (planning)"
echo "   - templates/protocol-build-fixer.md (build fixes)"
echo "   Or add BEAD-EXEMPT:research for research-only agents."
exit 2
```

- [ ] **Step 4: Make executable and run tests**

Run: `chmod +x hooks/agent-gate && bash tests/test-behaviors.sh 2>&1 | grep -E '13[a-d]\.'`

Expected: All 13a-13d PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/agent-gate tests/test-behaviors.sh
git commit -m "feat: add agent-gate hook — blocks Agent dispatch without protocol sentinel"
```

---

### Task 5: Commit Gate

**Files:**
- Create: `hooks/commit-gate`
- Test: `tests/test-behaviors.sh` (Section 14)

- [ ] **Step 1: Write failing tests**

Append to `tests/test-behaviors.sh`:

```bash
# ---------------------------------------------------------------------------
# Section 14: commit-gate tests
# ---------------------------------------------------------------------------
echo ""
echo "14. commit-gate"

# 14a. Non-git-commit command → exit 0 (no interference)
STDIN='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | bash "$PLUGIN_ROOT/hooks/commit-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "14a. commit-gate: git status → exit 0 (not gated)"
else
    fail "14a. commit-gate: expected exit 0 for non-commit, got exit $EXIT_CODE"
fi

# 14b. git commit without review:quality → exit 2
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo "ID        STATUS        TITLE"
        echo "abc-123   in_progress   Test task" ;;
    show)
        cat << 'BD_SHOW'
TITLE
Test task
NOTES
[M] task:claimed work started
[M] tdd:green all tests pass
[M] tdd:green-verified confirmed
[M] tdd:refactor cleanup done
PARENT
BD_SHOW
        ;;
esac
MOCK
chmod +x "$TMPDIR_BD/bd"
rm -rf "$GATE_CACHE_NEW"

STDIN='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: add feature\""}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/commit-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 2 ] && echo "$OUTPUT" | grep -q "BLOCKED"; then
    pass "14b. commit-gate: git commit without review:quality → exit 2"
else
    fail "14b. commit-gate: expected exit 2, got exit $EXIT_CODE: $OUTPUT"
fi

# 14c. git commit WITH review:quality → exit 0
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo "ID        STATUS        TITLE"
        echo "abc-123   in_progress   Test task" ;;
    show)
        cat << 'BD_SHOW'
TITLE
Test task
NOTES
[M] task:claimed work started
[M] tdd:refactor cleanup done
[M] review:spec passed
[M] review:quality passed — no blocking issues
PARENT
BD_SHOW
        ;;
esac
MOCK
chmod +x "$TMPDIR_BD/bd"
rm -rf "$GATE_CACHE_NEW"

STDIN='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: add feature\""}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/commit-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "14c. commit-gate: git commit with review:quality → exit 0"
else
    fail "14c. commit-gate: expected exit 0, got exit $EXIT_CODE: $OUTPUT"
fi

# 14d. ls command → exit 0 (Bash commands unrelated to git commit)
STDIN='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | bash "$PLUGIN_ROOT/hooks/commit-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "14d. commit-gate: ls → exit 0 (not gated)"
else
    fail "14d. commit-gate: expected exit 0 for ls, got exit $EXIT_CODE"
fi
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-behaviors.sh 2>&1 | grep -E '14[a-d]\.'`

Expected: Tests 14a-14d FAIL.

- [ ] **Step 3: Write hooks/commit-gate**

```bash
#!/usr/bin/env bash
# Commit gate: blocks git commit without review:quality milestone.
# Registered as PreToolUse hook for Bash in hooks.json.
# Only triggers on commands containing "git commit". Other Bash usage unaffected.
# Exit 2 = block. Exit 0 = allow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cache-utils.sh
. "$SCRIPT_DIR/cache-utils.sh"

# --- Read stdin JSON ---
STDIN=$(cat)
COMMAND=$(json_field "$STDIN" "tool_input.command")

# --- Only trigger on git commit ---
if [ -z "$COMMAND" ] || ! printf '%s' "$COMMAND" | grep -qE '\bgit[[:space:]]+commit\b'; then
    exit 0
fi

# --- Bypass ---
if [ "${BEADS_GATE_BYPASS:-}" = "1" ]; then
    echo "⚠ BEADS_GATE_BYPASS=1 — commit gate bypassed"
    exit 0
fi

# --- Guards ---
if ! check_beads_available; then
    exit 0
fi

# --- Check active task ---
TASK_ID=$(get_active_task)

if [ "$TASK_ID" = "BD_UNREACHABLE" ]; then
    echo "⚠ Beads server unreachable — commit gate bypassed."
    exit 0
fi

if [ -z "$TASK_ID" ]; then
    echo "🚫 BLOCKED: Cannot commit without an active beads task."
    exit 2
fi

# --- Check for review:quality milestone ---
MILESTONES=$(get_milestones "$TASK_ID")

if [ "$MILESTONES" = "BD_UNREACHABLE" ]; then
    echo "⚠ Beads server unreachable — commit gate bypassed."
    exit 0
fi

if ! printf '%s' "$MILESTONES" | grep -q '^\[M\] review:quality'; then
    PHASE=$(get_current_phase "$MILESTONES")
    echo "🚫 BLOCKED: Cannot commit without code quality review."
    echo "   Task: $TASK_ID | Current phase: $PHASE"
    echo "   Complete quality review first, then:"
    echo "   bash \"\${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append\" $TASK_ID \"[M] review:quality passed\""
    exit 2
fi

exit 0
```

- [ ] **Step 4: Make executable and run tests**

Run: `chmod +x hooks/commit-gate && bash tests/test-behaviors.sh 2>&1 | grep -E '14[a-d]\.'`

Expected: All 14a-14d PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/commit-gate tests/test-behaviors.sh
git commit -m "feat: add commit-gate hook — blocks git commit without review:quality"
```

---

### Task 6: Stop Gate

**Files:**
- Create: `hooks/stop-gate`
- Test: `tests/test-behaviors.sh` (Section 15)

- [ ] **Step 1: Write failing tests**

Append to `tests/test-behaviors.sh`:

```bash
# ---------------------------------------------------------------------------
# Section 15: stop-gate tests
# ---------------------------------------------------------------------------
echo ""
echo "15. stop-gate"

# 15a. In-progress task without verified/paused → exit 2
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo "ID        STATUS        TITLE"
        echo "abc-123   in_progress   Test task" ;;
    show)
        cat << 'BD_SHOW'
TITLE
Test task
NOTES
[M] task:claimed work started
[M] tdd:green-verified all pass
PARENT
BD_SHOW
        ;;
esac
MOCK
chmod +x "$TMPDIR_BD/bd"
rm -rf "$GATE_CACHE_NEW"

EXIT_CODE=0
OUTPUT=$(PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/stop-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 2 ] && echo "$OUTPUT" | grep -q "BLOCKED"; then
    pass "15a. stop-gate: in-progress without verified → exit 2"
else
    fail "15a. stop-gate: expected exit 2, got exit $EXIT_CODE: $OUTPUT"
fi

# 15b. In-progress task with [M] verified → exit 0
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo "ID        STATUS        TITLE"
        echo "abc-123   in_progress   Test task" ;;
    show)
        cat << 'BD_SHOW'
TITLE
Test task
NOTES
[M] task:claimed work started
[M] review:quality passed
[M] verified all tests pass, feature works
PARENT
BD_SHOW
        ;;
esac
MOCK
chmod +x "$TMPDIR_BD/bd"
rm -rf "$GATE_CACHE_NEW"

EXIT_CODE=0
OUTPUT=$(PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/stop-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "15b. stop-gate: verified task → exit 0"
else
    fail "15b. stop-gate: expected exit 0, got exit $EXIT_CODE: $OUTPUT"
fi

# 15c. In-progress task with [M] paused → exit 0
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo "ID        STATUS        TITLE"
        echo "abc-123   in_progress   Test task" ;;
    show)
        cat << 'BD_SHOW'
TITLE
Test task
NOTES
[M] task:claimed work started
[M] paused context pressure, saving state
PARENT
BD_SHOW
        ;;
esac
MOCK
chmod +x "$TMPDIR_BD/bd"
rm -rf "$GATE_CACHE_NEW"

EXIT_CODE=0
OUTPUT=$(PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/stop-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "15c. stop-gate: paused task → exit 0"
else
    fail "15c. stop-gate: expected exit 0, got exit $EXIT_CODE: $OUTPUT"
fi

# 15d. No in-progress tasks → exit 0
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
echo "No issues found"
MOCK
chmod +x "$TMPDIR_BD/bd"
rm -rf "$GATE_CACHE_NEW"

EXIT_CODE=0
OUTPUT=$(PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/stop-gate" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "15d. stop-gate: no in-progress tasks → exit 0"
else
    fail "15d. stop-gate: expected exit 0, got exit $EXIT_CODE: $OUTPUT"
fi
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-behaviors.sh 2>&1 | grep -E '15[a-d]\.'`

Expected: Tests 15a-15d FAIL.

- [ ] **Step 3: Write hooks/stop-gate**

```bash
#!/usr/bin/env bash
# Stop gate: blocks session end unless all in-progress beads have verified/paused.
# Registered as Stop hook in hooks.json (runs after advisory stop hook).
# Exit 2 = block. Exit 0 = allow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cache-utils.sh
. "$SCRIPT_DIR/cache-utils.sh"

# --- Bypass ---
if [ "${BEADS_GATE_BYPASS:-}" = "1" ]; then
    echo "⚠ BEADS_GATE_BYPASS=1 — stop gate bypassed"
    exit 0
fi

# --- Guards ---
if ! check_beads_available; then
    exit 0
fi

# --- Get all in-progress tasks ---
LISTING=$($BD_TIMEOUT bd list --status=in_progress 2>/dev/null || echo "")
TASK_IDS=$(echo "$LISTING" | grep -v 'No issues\|^$\|Total:\|Status:' | awk 'NR>1 && NF>0{print $1}' || true)

if [ -z "$TASK_IDS" ]; then
    exit 0
fi

# --- Check each task for verified or paused ---
MISSING=""
for task_id in $TASK_IDS; do
    MILESTONES=$(get_milestones "$task_id")

    # If server unreachable, don't block
    if [ "$MILESTONES" = "BD_UNREACHABLE" ]; then
        echo "⚠ Beads server unreachable — stop gate bypassed for $task_id."
        continue
    fi

    HAS_VERIFIED=$(printf '%s' "$MILESTONES" | grep -c '^\[M\] verified' || echo "0")
    HAS_PAUSED=$(printf '%s' "$MILESTONES" | grep -c '^\[M\] paused' || echo "0")

    if [ "$HAS_VERIFIED" -eq 0 ] && [ "$HAS_PAUSED" -eq 0 ]; then
        PHASE=$(get_current_phase "$MILESTONES")
        MISSING="${MISSING}   ${task_id} (phase: ${PHASE})\n"
    fi
done

if [ -n "$MISSING" ]; then
    echo "🚫 BLOCKED: In-progress tasks missing verified/paused milestone:"
    printf '%b' "$MISSING"
    echo ""
    echo "   Either verify completion or pause with reason:"
    echo "   bash \"\${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append\" <id> \"[M] verified done\""
    echo "   bash \"\${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append\" <id> \"[M] paused <reason>\""
    exit 2
fi

exit 0
```

- [ ] **Step 4: Make executable and run tests**

Run: `chmod +x hooks/stop-gate && bash tests/test-behaviors.sh 2>&1 | grep -E '15[a-d]\.'`

Expected: All 15a-15d PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/stop-gate tests/test-behaviors.sh
git commit -m "feat: add stop-gate hook — blocks session end without verified/paused"
```

---

### Task 7: Mid-Session Reminder

**Files:**
- Create: `hooks/mid-session-reminder`
- Test: `tests/test-behaviors.sh` (Section 16)

- [ ] **Step 1: Write failing tests**

Append to `tests/test-behaviors.sh`:

```bash
# ---------------------------------------------------------------------------
# Section 16: mid-session-reminder tests
# ---------------------------------------------------------------------------
echo ""
echo "16. mid-session-reminder"

# 16a. After 5+ edits without milestone → warning
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo "ID        STATUS        TITLE"
        echo "abc-123   in_progress   Test task" ;;
    show)
        cat << 'BD_SHOW'
TITLE
Test task
NOTES
[M] task:claimed work started
PARENT
BD_SHOW
        ;;
esac
MOCK
chmod +x "$TMPDIR_BD/bd"
rm -rf "$GATE_CACHE_NEW"

# Simulate 5 prior edits by pre-seeding edit counter
mkdir -p "$GATE_CACHE_NEW"
echo "5" > "$GATE_CACHE_NEW/edit-counter"
# Pre-seed active-task cache
echo "abc-123" > "$GATE_CACHE_NEW/active-task"

STDIN='{"tool_name":"Edit","tool_input":{"file_path":"test.ts"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/mid-session-reminder" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ] && echo "$OUTPUT" | grep -q "edits since last milestone"; then
    pass "16a. mid-session-reminder: 5+ edits → warning"
else
    fail "16a. mid-session-reminder: expected warning, got exit $EXIT_CODE: $OUTPUT"
fi

# 16b. Status echo on every Edit/Write
rm -rf "$GATE_CACHE_NEW"
mkdir -p "$GATE_CACHE_NEW"
echo "0" > "$GATE_CACHE_NEW/edit-counter"
echo "abc-123" > "$GATE_CACHE_NEW/active-task"

STDIN='{"tool_name":"Edit","tool_input":{"file_path":"test.ts"}}'
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/mid-session-reminder" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ] && echo "$OUTPUT" | grep -q "task:abc-123"; then
    pass "16b. mid-session-reminder: status echo on edit"
else
    fail "16b. mid-session-reminder: expected status, got exit $EXIT_CODE: $OUTPUT"
fi

# 16c. Always exits 0 (never blocks)
EXIT_CODE=0
OUTPUT=$(echo "$STDIN" | PATH="$TMPDIR_BD:$PATH" bash "$PLUGIN_ROOT/hooks/mid-session-reminder" 2>&1) || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    pass "16c. mid-session-reminder: always exits 0"
else
    fail "16c. mid-session-reminder: expected exit 0, got exit $EXIT_CODE"
fi
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-behaviors.sh 2>&1 | grep -E '16[a-c]\.'`

Expected: Tests 16a-16c FAIL.

- [ ] **Step 3: Write hooks/mid-session-reminder**

```bash
#!/usr/bin/env bash
# Mid-session reminder: advisory, never blocks.
# - Tracks edit count, warns after 5+ edits without milestone progression
# - Echoes current task/phase status on every Edit/Write
# Registered as PostToolUse hook for Edit and Write in hooks.json.
# Always exits 0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cache-utils.sh
. "$SCRIPT_DIR/cache-utils.sh"

# --- Guards ---
if ! check_beads_available; then
    exit 0
fi

# --- Read stdin ---
STDIN=$(cat)
TOOL_NAME=$(json_field "$STDIN" "tool_name")

# --- Only track edits for Edit/Write ---
if [ "$TOOL_NAME" != "Edit" ] && [ "$TOOL_NAME" != "Write" ]; then
    exit 0
fi

# --- Get active task ---
TASK_ID=$(get_active_task)
if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "BD_UNREACHABLE" ]; then
    exit 0
fi

# --- Increment edit counter ---
increment_edit_count
EDIT_COUNT=$(get_edit_count)

# --- Get milestones ---
MILESTONES=$(get_milestones "$TASK_ID")
if [ "$MILESTONES" = "BD_UNREACHABLE" ]; then
    exit 0
fi

PHASE=$(get_current_phase "$MILESTONES")
NEXT=$(get_next_phase "$PHASE")

# --- Warn on edit staleness ---
if [ "$EDIT_COUNT" -ge 5 ]; then
    echo "⚠ ${EDIT_COUNT} edits since last milestone. Current phase: ${PHASE}. Update milestone or explain."
fi

# --- Always echo status ---
echo "✓ task:${TASK_ID} | phase:${PHASE} | next: ${NEXT}"

exit 0
```

- [ ] **Step 4: Make executable and run tests**

Run: `chmod +x hooks/mid-session-reminder && bash tests/test-behaviors.sh 2>&1 | grep -E '16[a-c]\.'`

Expected: All 16a-16c PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/mid-session-reminder tests/test-behaviors.sh
git commit -m "feat: add mid-session-reminder hook — edit counter + status echo"
```

---

### Task 8: PreCompact State Dump + bd-notes-append Cache Write-Through

**Files:**
- Create: `hooks/precompact-state`
- Modify: `hooks/bd-notes-append`

- [ ] **Step 1: Write hooks/precompact-state**

```bash
#!/usr/bin/env bash
# PreCompact state dump: injects current workflow state before context compaction.
# Runs alongside bd prime. Always exits 0 (advisory).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cache-utils.sh
. "$SCRIPT_DIR/cache-utils.sh"

if ! check_beads_available; then
    exit 0
fi

# Get all in-progress tasks
LISTING=$($BD_TIMEOUT bd list --status=in_progress 2>/dev/null || echo "")
TASK_IDS=$(echo "$LISTING" | grep -v 'No issues\|^$\|Total:\|Status:' | awk 'NR>1 && NF>0{print $1}' || true)

if [ -z "$TASK_IDS" ]; then
    echo "WORKFLOW STATE: No in-progress tasks"
    exit 0
fi

echo "WORKFLOW STATE:"
for task_id in $TASK_IDS; do
    MILESTONES=$(get_milestones "$task_id")
    if [ "$MILESTONES" = "BD_UNREACHABLE" ]; then
        echo "  Task: $task_id (server unreachable)"
        continue
    fi
    PHASE=$(get_current_phase "$MILESTONES")
    NEXT=$(get_next_phase "$PHASE")
    echo "  Task: $task_id | phase:$PHASE | next: $NEXT"
done
echo "  RULE: each sub-task needs full [M] progression before close"

exit 0
```

- [ ] **Step 2: Make executable**

Run: `chmod +x hooks/precompact-state`

- [ ] **Step 3: Add cache write-through to bd-notes-append**

In `hooks/bd-notes-append`, append after the final `bd update` block (after line 45, before end of file):

```bash
# --- Cache write-through ---
# After successful bd update, write to local milestone cache + reset edit counter
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/cache-utils.sh" ]; then
    # shellcheck source=cache-utils.sh
    . "$SCRIPT_DIR/cache-utils.sh"
    ensure_cache_dir
    echo "$NEW_LINE" >> "${GATE_CACHE_DIR}/milestones-${TASK_ID}"
    echo 0 > "${GATE_CACHE_DIR}/edit-counter"
fi
```

The modified `bd-notes-append` now has the original 45 lines plus 9 lines of cache integration.

- [ ] **Step 4: Commit**

```bash
git add hooks/precompact-state hooks/bd-notes-append
git commit -m "feat: add precompact-state dump + bd-notes-append cache write-through"
```

---

### Task 9: Protocol Templates

**Files:**
- Create: `templates/protocol-base.md`
- Create: `templates/protocol-implementer.md`
- Create: `templates/protocol-reviewer.md`
- Create: `templates/protocol-planner.md`
- Create: `templates/protocol-build-fixer.md`

- [ ] **Step 1: Write templates/protocol-base.md**

```markdown
# Bead Protocol (All Agents)

You MUST track your work in the beads system. This is not optional.

## Rules

1. **Every action is tracked** — update beads notes as you progress through milestones
2. **No silent work** — if you make changes, log them with `[M]` milestone markers
3. **Side-quests get their own beads** — CRITICAL/HIGH findings during review → create new bead

## Milestone Format

Append milestone lines to task notes:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] <phase> <freetext detail>"
```

## Side-Quest Protocol

When you discover an issue OUTSIDE your current task scope:

```bash
bd create --title="Found: <issue>" --type=bug -p <priority>
bd dep add <new-id> <current-id> --type discovered-from
```

Do NOT fix it inline. Log it and continue your current task.

<!-- BEAD-PROTOCOL-v1:base -->
```

- [ ] **Step 2: Write templates/protocol-implementer.md**

```markdown
# Implementer Bead Protocol

You are implementing code changes. Follow the full TDD milestone chain.

## Before ANY Code Changes

```bash
bd create --title="<task-description>" --type=task -p 2
bd dep add <new-id> <parent-id> --type parent-child
bd update <new-id> --claim
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] task:created sub-task for <description>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] task:claimed work started"
```

## During TDD — Update After EACH Phase

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:red <what test you wrote>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:red-verified <how it failed>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:green <what you implemented>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:green-verified <test output summary>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:refactor <what you cleaned up>"
```

Multiple TDD cycles allowed — repeat red→green as needed, then one refactor at end.

## After Completion

```bash
bd close <id>
```

## SKIP NONE OF THESE

Your work will be rejected if milestones are missing. The controller agent verifies every milestone after you return.

<!-- BEAD-PROTOCOL-v1:implementer -->
```

- [ ] **Step 3: Write templates/protocol-reviewer.md**

```markdown
# Reviewer Bead Protocol

You are reviewing code. Track your review in the PARENT task's notes.

## Start Review

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <parent-task-id> "[M] review:<type>:started reviewing <scope>"
```

Where `<type>` is: `spec` | `quality` | `security`

## For EACH Finding

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <parent-task-id> "[M] review:<type>:finding:<severity> <description>"
```

Severity: CRITICAL | HIGH | MEDIUM | LOW | INFO

## For CRITICAL or HIGH Findings — Create Side-Quest (MANDATORY)

```bash
bd create --title="Found: <issue>" --type=bug -p <severity-maps-to-priority>
bd dep add <new-id> <parent-task-id> --type discovered-from
```

You MUST create side-quest beads for CRITICAL and HIGH findings. Do not skip this.

## Verdict

Pass:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <parent-task-id> "[M] review:<type> passed — no blocking issues"
```

Block:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <parent-task-id> "[M] review:<type>:blocked <N> issues must fix"
```

<!-- BEAD-PROTOCOL-v1:reviewer -->
```

- [ ] **Step 4: Write templates/protocol-planner.md**

```markdown
# Planner Bead Protocol

You are creating an implementation plan. Track progress in the task's notes.

## Milestones

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] plan:started analyzing requirements"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] plan:spec-written path/to/spec.md"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] plan:subtasks-created N sub-tasks linked"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] plan:completed"
```

## If Scope Issues Found

Create a side-quest:

```bash
bd create --title="Found: <scope issue>" --type=task
bd dep add <new-id> <current-id> --type discovered-from
```

<!-- BEAD-PROTOCOL-v1:planner -->
```

- [ ] **Step 5: Write templates/protocol-build-fixer.md**

```markdown
# Build Fixer Bead Protocol

You are fixing a build or test failure. Track progress in the task's notes.

## Milestones

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] fix:started <error summary>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] fix:diagnosed root cause: <cause>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] fix:applied <what changed>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] fix:verified build passes"
```

## If Fix Reveals Deeper Issue

Create a side-quest:

```bash
bd create --title="Found: <underlying issue>" --type=bug
bd dep add <new-id> <current-id> --type discovered-from
```

<!-- BEAD-PROTOCOL-v1:build-fixer -->
```

- [ ] **Step 6: Commit**

```bash
git add templates/protocol-base.md templates/protocol-implementer.md \
    templates/protocol-reviewer.md templates/protocol-planner.md \
    templates/protocol-build-fixer.md
git commit -m "feat: add subagent protocol templates with BEAD-PROTOCOL-v1 sentinels"
```

---

### Task 10: Wire Hooks in hooks.json

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Replace hooks.json with new configuration**

Replace the entire content of `hooks/hooks.json`:

```json
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bd prime"
          },
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/precompact-state\""
          }
        ]
      }
    ],
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
          },
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/stop-gate\""
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
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/milestone-gate\""
          }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/milestone-gate\""
          }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agent-gate\""
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/commit-gate\""
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/mid-session-reminder\""
          }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/mid-session-reminder\""
          }
        ]
      }
    ]
  }
}
```

Key changes from previous:
- Pre-change-gate → milestone-gate for Edit/Write
- Added: agent-gate (Agent), commit-gate (Bash)
- Added: stop-gate (Stop, after existing stop)
- Added: mid-session-reminder (PostToolUse, Edit/Write)
- Added: precompact-state (PreCompact, after bd prime)

- [ ] **Step 2: Keep pre-change-gate file (test compatibility)**

Do NOT delete `hooks/pre-change-gate` — existing behavioral tests (Section 2) reference it. It's no longer wired in hooks.json, which is sufficient. It can be removed in a follow-up cleanup task.

- [ ] **Step 3: Validate hooks.json is valid JSON**

Run: `python3 -c "import json; json.load(open('hooks/hooks.json'))"`

Expected: No output (valid JSON).

- [ ] **Step 4: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: wire enforcement hooks in hooks.json, retire pre-change-gate"
```

---

### Task 11: Context Updates

**Files:**
- Modify: `CLAUDE.md`
- Modify: `skills/workflow/SKILL.md`
- Modify: `hooks/session-start`
- Modify: `skills/start/SKILL.md`

- [ ] **Step 1: Add enforcement hooks section to CLAUDE.md**

Add before `### Session` section in `CLAUDE.md`:

```markdown
### Enforcement Hooks

Hooks block (`exit 2`) when workflow steps are skipped:

| Gate | Trigger | Blocks unless |
|------|---------|---------------|
| milestone-gate | Edit/Write | Active sub-task with `[M] task:claimed` |
| agent-gate | Agent dispatch | Prompt contains `BEAD-PROTOCOL-v1` sentinel |
| commit-gate | git commit | `[M] review:quality` present |
| stop-gate | Session end | All tasks have `[M] verified` or `[M] paused` |

### Milestone Format

`[M] <phase> <freetext>` — append via `bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] phase detail"`

Phases: task:created → task:claimed → tdd:red → tdd:red-verified → tdd:green → tdd:green-verified → tdd:refactor → review:spec → review:quality → verified

### Subagent Protocol

ALL subagent prompts MUST include protocol template from `templates/protocol-*.md`.
Sentinel: `<!-- BEAD-PROTOCOL-v1:<type> -->`. Research-only: use `BEAD-EXEMPT:research`.
```

- [ ] **Step 2: Add milestone tracking and subagent protocol sections to workflow SKILL.md**

Add after the `## Milestone Notes` section (around line 142) in `skills/workflow/SKILL.md`:

```markdown
## Enforcement Milestones

TDD milestone chain — each requires predecessors:

| Phase | Prerequisite | Detail |
|-------|-------------|--------|
| `task:created` | — | Sub-task bead exists |
| `task:claimed` | task:created | Work started (`bd update --claim`) |
| `tdd:red` | task:claimed | Failing test written |
| `tdd:red-verified` | tdd:red | Test fails correctly |
| `tdd:green` | tdd:red-verified | Implementation passes |
| `tdd:green-verified` | tdd:green | All tests pass |
| `tdd:refactor` | tdd:green-verified | Cleanup complete |
| `review:spec` | tdd:refactor | Spec compliance passed |
| `review:quality` | review:spec | Code quality review passed |
| `verified` | review:quality | Verification-before-completion done |

Multiple TDD cycles allowed. Special: `paused <reason>` accepted by stop-gate.

Write milestones:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:red wrote failing test for X"
```

## Subagent Protocol

ALL subagents MUST include a protocol template from `templates/`:

| Template | Agent Type |
|----------|-----------|
| `protocol-implementer.md` | Code changes (full TDD chain) |
| `protocol-reviewer.md` | Code review (findings + side-quests) |
| `protocol-planner.md` | Planning (plan milestones) |
| `protocol-build-fixer.md` | Build fixes (fix milestones) |

Each ends with `<!-- BEAD-PROTOCOL-v1:<type> -->` sentinel. The agent-gate hook blocks dispatch without it.

Research-only agents: add `BEAD-EXEMPT:research` or `BEAD-EXEMPT:exploration` to prompt.

## Controller Protocol

The main/controller agent tracks its own orchestration milestones:

```
[M] dispatch:impl:<sub-task-id> dispatched implementer
[M] dispatch:review-spec:<sub-task-id> dispatched spec reviewer
[M] dispatch:review-quality:<sub-task-id> dispatched quality reviewer
[M] controller:milestone-check:<sub-task-id> verified milestones present
[M] controller:rejected:<sub-task-id> missing milestones, re-dispatching
```

## Controller Verification (MANDATORY)

After ANY subagent returns, the controller MUST:

1. `bd show <sub-task-id>` — check expected milestones are present
2. Verify side-quest beads created for any CRITICAL/HIGH review findings
3. If milestones missing → reject work, re-dispatch or fix directly
4. Only AFTER milestone validation → dispatch next reviewer/task

Never trust subagent reports at face value. Always verify with `bd show`.
```

- [ ] **Step 3: Add echo reminder to session-start**

In `hooks/session-start`, add a line to the `WORKFLOW_CONTENT` that echoes enforcement is active. After line 56 (`WORKFLOW_CONTENT=$(cat "$CHEATSHEET_FILE")`), add:

```bash
WORKFLOW_CONTENT="${WORKFLOW_CONTENT}

---
ENFORCEMENT: milestone-gate (Edit/Write), agent-gate (Agent), commit-gate (Bash), stop-gate (Stop) are ACTIVE. exit 2 = blocked."
```

This appends an enforcement reminder to the injected CLAUDE.md content, visible at session start.

- [ ] **Step 4: Add sub-task creation note to start/SKILL.md**

Add after the `### Step 4: ROUTE` section in `skills/start/SKILL.md`:

```markdown
---

## Enforcement Integration

After planning produces sub-tasks, each sub-task MUST be:
1. Created as a beads task: `bd create --title="..." --type=task`
2. Linked to parent: `bd dep add <sub> <parent> --type parent-child`
3. Claimed before work: `bd update <sub> --claim`
4. Milestone-tracked: `[M] task:created`, `[M] task:claimed`, then full TDD chain

The milestone-gate hook blocks file edits without a claimed sub-task bead.
Subagent prompts MUST include `templates/protocol-*.md` (agent-gate enforces this).
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md skills/workflow/SKILL.md hooks/session-start skills/start/SKILL.md
git commit -m "docs: add enforcement hooks + milestone format + controller protocol to all context files"
```

---

### Task 12: Update validate-config.sh

**Files:**
- Modify: `tests/validate-config.sh`

- [ ] **Step 1: Add validation for new hooks and templates**

Add a new section to `tests/validate-config.sh` (after existing Section 11):

```bash
# ── Section 12: Enforcement hooks ────────────────────────────────────────────
echo ""
echo "12. Enforcement hooks"

# 12.1 New hook scripts exist and are executable
for hook in milestone-gate agent-gate commit-gate stop-gate mid-session-reminder precompact-state; do
    HOOK_PATH="$PLUGIN_ROOT/hooks/$hook"
    if [ -x "$HOOK_PATH" ]; then
        pass "12.1 hooks/$hook exists and is executable"
    else
        fail "12.1 hooks/$hook missing or not executable"
    fi
done

# 12.2 cache-utils.sh exists
if [ -f "$PLUGIN_ROOT/hooks/cache-utils.sh" ]; then
    pass "12.2 hooks/cache-utils.sh exists"
else
    fail "12.2 hooks/cache-utils.sh missing"
fi

# 12.3 Templates directory exists with required files
for tmpl in gate-exemptions.txt protocol-base.md protocol-implementer.md protocol-reviewer.md protocol-planner.md protocol-build-fixer.md; do
    if [ -f "$PLUGIN_ROOT/templates/$tmpl" ]; then
        pass "12.3 templates/$tmpl exists"
    else
        fail "12.3 templates/$tmpl missing"
    fi
done

# 12.4 All protocol templates contain BEAD-PROTOCOL-v1 sentinel
for tmpl in protocol-base.md protocol-implementer.md protocol-reviewer.md protocol-planner.md protocol-build-fixer.md; do
    if grep -q 'BEAD-PROTOCOL-v1' "$PLUGIN_ROOT/templates/$tmpl"; then
        pass "12.4 templates/$tmpl contains BEAD-PROTOCOL-v1 sentinel"
    else
        fail "12.4 templates/$tmpl missing BEAD-PROTOCOL-v1 sentinel"
    fi
done

# 12.5 hooks.json references new hooks
for hook in milestone-gate agent-gate commit-gate stop-gate mid-session-reminder precompact-state; do
    if grep -q "$hook" "$PLUGIN_ROOT/hooks/hooks.json"; then
        pass "12.5 hooks.json references $hook"
    else
        fail "12.5 hooks.json missing reference to $hook"
    fi
done

# 12.6 pre-change-gate is NOT referenced in hooks.json (retired)
if grep -q "pre-change-gate" "$PLUGIN_ROOT/hooks/hooks.json"; then
    fail "12.6 hooks.json still references retired pre-change-gate"
else
    pass "12.6 pre-change-gate retired from hooks.json"
fi

# 12.7 CLAUDE.md contains enforcement hooks reference
if grep -q "milestone-gate" "$PLUGIN_ROOT/CLAUDE.md" && grep -q "BEAD-PROTOCOL-v1" "$PLUGIN_ROOT/CLAUDE.md"; then
    pass "12.7 CLAUDE.md contains enforcement hooks + protocol reference"
else
    fail "12.7 CLAUDE.md missing enforcement hooks reference"
fi

# 12.8 Workflow SKILL.md contains milestone chain
if grep -q "tdd:red-verified" "$PLUGIN_ROOT/skills/workflow/SKILL.md" && grep -q "Subagent Protocol" "$PLUGIN_ROOT/skills/workflow/SKILL.md"; then
    pass "12.8 Workflow SKILL.md contains milestone chain + subagent protocol"
else
    fail "12.8 Workflow SKILL.md missing enforcement sections"
fi
```

- [ ] **Step 2: Run validate-config.sh**

Run: `bash tests/validate-config.sh 2>&1 | tail -30`

Expected: All Section 12 checks PASS.

- [ ] **Step 3: Run full test suite**

Run: `bash tests/test-behaviors.sh && bash tests/validate-config.sh`

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add tests/validate-config.sh
git commit -m "test: add validation for enforcement hooks + templates"
```

---

### Task 13: Update stop Hook Cache Cleanup

**Files:**
- Modify: `hooks/stop`

The existing `stop` hook cleans up the old single-file cache. Update it to clean up the new directory cache.

- [ ] **Step 1: Update cache cleanup in hooks/stop**

Replace line 63 in `hooks/stop`:

Old:
```bash
rm -f "${CACHE_DIR}/.beads-gate-${USER:-$(id -un)}-${PROJECT_HASH}"
```

New:
```bash
rm -rf "${CACHE_DIR}/.beads-gate-${USER:-$(id -un)}-${PROJECT_HASH}"
```

Change: `rm -f` → `rm -rf` (directory instead of file).

- [ ] **Step 2: Verify existing stop tests still pass**

Run: `bash tests/test-behaviors.sh 2>&1 | grep -E '4[a-d]\.'`

Expected: All Section 4 (stop hook) tests still PASS.

- [ ] **Step 3: Commit**

```bash
git add hooks/stop
git commit -m "fix: update stop hook cache cleanup for directory-based cache"
```

---

### Task 14: Final Integration Validation

- [ ] **Step 1: Run full test suite**

Run: `bash tests/test-behaviors.sh && bash tests/validate-config.sh`

Expected: ALL tests pass — zero failures.

- [ ] **Step 2: Verify hooks.json is valid**

Run: `python3 -c "import json; json.load(open('hooks/hooks.json')); print('OK')"`

Expected: `OK`

- [ ] **Step 3: Verify all hooks are executable**

Run: `ls -la hooks/milestone-gate hooks/agent-gate hooks/commit-gate hooks/stop-gate hooks/mid-session-reminder hooks/precompact-state hooks/cache-utils.sh`

Expected: All show `-rwxr-xr-x` permissions.

- [ ] **Step 4: Verify templates have sentinels**

Run: `grep -l 'BEAD-PROTOCOL-v1' templates/protocol-*.md | wc -l`

Expected: `4` (implementer, reviewer, planner, build-fixer — base has it too, so 5 total with base).

- [ ] **Step 5: Smoke test — milestone-gate blocks without task**

Run: `echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test.ts"}}' | bash hooks/milestone-gate; echo "exit: $?"`

Expected: `🚫 BLOCKED: No active sub-task bead...` and `exit: 2` (if you have no in-progress beads task).

- [ ] **Step 6: Smoke test — agent-gate blocks without sentinel**

Run: `echo '{"tool_name":"Agent","tool_input":{"prompt":"test"}}' | bash hooks/agent-gate; echo "exit: $?"`

Expected: `🚫 BLOCKED: Subagent prompt missing BEAD-PROTOCOL-v1...` and `exit: 2`.

- [ ] **Step 7: Bump version**

Update version in `skills/workflow/SKILL.md` frontmatter if following semver.

- [ ] **Step 8: Final commit**

```bash
git add -A
git commit -m "chore: enforcement hooks implementation complete — all tests pass"
```
