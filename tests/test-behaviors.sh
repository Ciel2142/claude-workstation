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

# ---------------------------------------------------------------------------
# Helper: compute the gate cache path for the plugin's .beads dir
# (mirrors the logic in pre-change-gate and stop)
# ---------------------------------------------------------------------------
_gate_cache() {
    local beads_path="$PLUGIN_ROOT/.beads"
    local project_hash
    project_hash=$(printf '%s' "$beads_path" | md5sum 2>/dev/null | cut -c1-8 \
        || printf '%s' "$beads_path" | md5 2>/dev/null | cut -c1-8 \
        || echo "default")
    echo "/tmp/.beads-gate-${USER:-$(id -un)}-${project_hash}"
}

GATE_CACHE=$(_gate_cache)

# ---------------------------------------------------------------------------
# Section 1: bd-notes-append tests
# ---------------------------------------------------------------------------
echo "1. bd-notes-append"

# Build a temp dir with a mock bd script
TMPDIR_BD=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BD"' EXIT

# The mock bd will store the last --notes value to a file we can inspect.
# We store it in $TMPDIR_BD/captured-notes.
# The mock handles: bd show <id>, bd list [--status=...], bd update <id> --notes ...
cat > "$TMPDIR_BD/bd" << 'MOCK'
#!/usr/bin/env bash
# Mock bd command for bd-notes-append tests
SUBCOMMAND="${1:-}"
shift || true

case "$SUBCOMMAND" in
    show)
        echo "$BD_SHOW_OUTPUT"
        ;;
    list)
        echo "$BD_LIST_OUTPUT"
        ;;
    update)
        # Consume <task-id>
        shift || true
        # Parse --notes value — support both --notes=value and --notes value
        NOTES_VALUE=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --notes=*)
                    NOTES_VALUE="${1#--notes=}"
                    shift
                    ;;
                --notes)
                    shift
                    NOTES_VALUE="$1"
                    shift
                    ;;
                *)
                    shift
                    ;;
            esac
        done
        printf '%s' "$NOTES_VALUE" > "$CAPTURE_FILE"
        ;;
    *)
        echo "mock bd: unknown subcommand $SUBCOMMAND" >&2
        exit 1
        ;;
esac
exit 0
MOCK
chmod +x "$TMPDIR_BD/bd"

CAPTURE_FILE="$TMPDIR_BD/captured-notes"

# 1a. Empty notes: bd show returns task with empty NOTES section
export BD_SHOW_OUTPUT="TITLE
Test task
NOTES

STATUS
open"
export CAPTURE_FILE
PATH="$TMPDIR_BD:$PATH" \
    bash "$PLUGIN_ROOT/hooks/bd-notes-append" "task-123" "tier: small" 2>/dev/null
if [[ -f "$CAPTURE_FILE" ]]; then
    CAPTURED=$(cat "$CAPTURE_FILE")
    if [[ "$CAPTURED" == "tier: small" ]]; then
        pass "1a. empty notes — captures exactly 'tier: small'"
    else
        fail "1a. empty notes — expected 'tier: small', got: $(printf '%q' "$CAPTURED")"
    fi
else
    fail "1a. empty notes — capture file not written"
fi

# 1b. Existing notes: bd show returns task with existing 'tier: small' in NOTES
rm -f "$CAPTURE_FILE"
export BD_SHOW_OUTPUT="TITLE
Test task
NOTES
tier: small
STATUS
open"
PATH="$TMPDIR_BD:$PATH" \
    bash "$PLUGIN_ROOT/hooks/bd-notes-append" "task-123" "plan: docs/plan.md" 2>/dev/null
if [[ -f "$CAPTURE_FILE" ]]; then
    CAPTURED=$(cat "$CAPTURE_FILE")
    EXPECTED="tier: small
plan: docs/plan.md"
    if [[ "$CAPTURED" == "$EXPECTED" ]]; then
        pass "1b. existing notes — appends new line preserving existing content"
    else
        fail "1b. existing notes — expected 'tier: small\\nplan: docs/plan.md', got: $(printf '%q' "$CAPTURED")"
    fi
else
    fail "1b. existing notes — capture file not written"
fi

# 1c. No arguments: should exit 1
unset BD_SHOW_OUTPUT
if PATH="$TMPDIR_BD:$PATH" \
       bash "$PLUGIN_ROOT/hooks/bd-notes-append" 2>/dev/null; then
    fail "1c. no args — expected exit 1 but got exit 0"
else
    pass "1c. no args — exits 1 as expected"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 2: pre-change-gate tests
# ---------------------------------------------------------------------------
echo "2. pre-change-gate"

# Build a separate temp dir for gate mock (includes git passthrough)
TMPDIR_GATE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BD" "$TMPDIR_GATE"' EXIT

cat > "$TMPDIR_GATE/bd" << 'MOCK'
#!/usr/bin/env bash
SUBCOMMAND="${1:-}"
shift || true

case "$SUBCOMMAND" in
    list)
        # Check for --json flag
        HAS_JSON=0
        HAS_STATUS=""
        for arg in "$@"; do
            case "$arg" in
                --json) HAS_JSON=1 ;;
                --status=*) HAS_STATUS="${arg#--status=}" ;;
            esac
        done
        if [[ "$HAS_JSON" -eq 1 ]]; then
            echo "$BD_LIST_JSON_OUTPUT"
        else
            echo "$BD_LIST_OUTPUT"
        fi
        ;;
    show)
        echo "$BD_SHOW_OUTPUT"
        ;;
    *)
        echo "mock bd: unknown subcommand $SUBCOMMAND" >&2
        exit 1
        ;;
esac
exit 0
MOCK
chmod +x "$TMPDIR_GATE/bd"

# 2a. No task in progress
rm -f "$GATE_CACHE"
export BD_LIST_JSON_OUTPUT="[]"
export BD_LIST_OUTPUT="No issues found."
export BD_SHOW_OUTPUT=""
GATE_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_GATE:$PATH" \
    bash "$PLUGIN_ROOT/hooks/pre-change-gate" 2>/dev/null || true)
if echo "$GATE_OUT" | grep -q "WARNING" && echo "$GATE_OUT" | grep -q "No active beads task"; then
    pass "2a. no task in progress — warns about missing beads task"
else
    fail "2a. no task in progress — expected WARNING about 'No active beads task', got: $(printf '%q' "$GATE_OUT")"
fi

# 2b. Task exists, no tier in notes
rm -f "$GATE_CACHE"
export BD_LIST_JSON_OUTPUT='[{"id": "test-456", "title": "Test task"}]'
export BD_LIST_OUTPUT="  test-456  IN_PROGRESS  Test task"
export BD_SHOW_OUTPUT="TITLE
Test task
NOTES
plan: docs/plan.md
STATUS
in_progress"
GATE_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_GATE:$PATH" \
    bash "$PLUGIN_ROOT/hooks/pre-change-gate" 2>/dev/null || true)
if echo "$GATE_OUT" | grep -q "WARNING" && echo "$GATE_OUT" | grep -qi "no tier"; then
    pass "2b. task exists, no tier — warns about missing tier assessment"
else
    fail "2b. task exists, no tier — expected WARNING about 'no tier', got: $(printf '%q' "$GATE_OUT")"
fi

# 2c. Task exists with tier — no output expected
rm -f "$GATE_CACHE"
export BD_LIST_JSON_OUTPUT='[{"id": "test-456", "title": "Test task"}]'
export BD_LIST_OUTPUT="  test-456  IN_PROGRESS  Test task"
export BD_SHOW_OUTPUT="TITLE
Test task
NOTES
tier: small
STATUS
in_progress"
GATE_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_GATE:$PATH" \
    bash "$PLUGIN_ROOT/hooks/pre-change-gate" 2>/dev/null || true)
if [[ -z "$GATE_OUT" ]]; then
    pass "2c. task with tier — outputs nothing (no warning)"
else
    fail "2c. task with tier — expected empty output, got: $(printf '%q' "$GATE_OUT")"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 3: Position detection tests
# ---------------------------------------------------------------------------
echo "3. Position detection"

# Mirror the resume/SKILL.md position detection logic
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

_assert_position() {
    local label="$1"
    local notes="$2"
    local expected="$3"
    local actual
    actual=$(detect_position "$notes")
    if [[ "$actual" == "$expected" ]]; then
        pass "$label — detected '$actual'"
    else
        fail "$label — expected '$expected', got '$actual'"
    fi
}

_assert_position "3a. tier only"           "tier: small"                                                "start"
_assert_position "3b. tier + spec"         "$(printf 'tier: medium+\nspec: docs/specs/foo.md')"        "post-brainstorming"
_assert_position "3c. tier + spec + plan"  "$(printf 'tier: medium+\nspec: docs/specs/foo.md\nplan: docs/plans/foo.md')" "post-planning"
_assert_position "3d. with completed"      "$(printf 'tier: small\nplan: docs/plans/foo.md\ncompleted: 1,2,3')"          "mid-implementation"
_assert_position "3e. with verification"   "$(printf 'tier: small\nplan: docs/plans/foo.md\ncompleted: 1,2\nverification: tests 47/47')" "post-verification"
_assert_position "3f. with docs-updated"   "$(printf 'tier: small\nverification: tests 47/47\ndocs-updated: README refreshed')"          "post-update-docs"
_assert_position "3g. with debug"          "$(printf 'tier: small\ndebug: root cause -- stale cache')"                  "mid-debugging"
_assert_position "3h. empty string"        ""                                                           "unknown"

echo ""

# ---------------------------------------------------------------------------
# Section 4: Stop hook tests
# ---------------------------------------------------------------------------
echo "4. stop hook"

# Build temp dir with mocked git and bd for stop hook tests
TMPDIR_STOP=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BD" "$TMPDIR_GATE" "$TMPDIR_STOP"' EXIT

cat > "$TMPDIR_STOP/bd" << 'MOCK'
#!/usr/bin/env bash
SUBCOMMAND="${1:-}"
shift || true

case "$SUBCOMMAND" in
    list)
        HAS_STATUS=""
        for arg in "$@"; do
            case "$arg" in
                --status=*) HAS_STATUS="${arg#--status=}" ;;
            esac
        done
        case "$HAS_STATUS" in
            in_progress) echo "$BD_LIST_IN_PROGRESS" ;;
            closed)      echo "$BD_LIST_CLOSED" ;;
            open)        echo "$BD_LIST_OPEN" ;;
            *)           echo "No issues found." ;;
        esac
        ;;
    *)
        echo "mock bd: unknown subcommand $SUBCOMMAND" >&2
        exit 1
        ;;
esac
exit 0
MOCK
chmod +x "$TMPDIR_STOP/bd"

cat > "$TMPDIR_STOP/git" << GITM
#!/usr/bin/env bash
# Pass through all git calls except the ones we need to mock
case "\$1" in
    rev-parse)
        # Return the plugin root as the git toplevel so .beads is found
        echo "$PLUGIN_ROOT"
        ;;
    log)
        # Return the mocked git log output — use printf to avoid spurious newline on empty
        [[ -n "\$GIT_LOG_OUTPUT" ]] && printf '%s\n' "\$GIT_LOG_OUTPUT" || true
        ;;
    *)
        # Pass through to real git
        exec /usr/bin/git "\$@"
        ;;
esac
GITM
chmod +x "$TMPDIR_STOP/git"

# 4a. Clean session: no commits, no tasks of any status
rm -f "$GATE_CACHE"
export GIT_LOG_OUTPUT=""
export BD_LIST_IN_PROGRESS="No issues found."
export BD_LIST_CLOSED="No issues found."
export BD_LIST_OPEN="No issues found."
STOP_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_STOP:$PATH" \
    bash "$PLUGIN_ROOT/hooks/stop" 2>/dev/null || true)
if echo "$STOP_OUT" | grep -q "WARNING"; then
    fail "4a. clean session — should NOT warn but got: $(printf '%q' "$STOP_OUT")"
else
    pass "4a. clean session — no WARNING output"
fi

# 4b. Commits exist + closed task exists — should NOT warn about no beads issues
rm -f "$GATE_CACHE"
export GIT_LOG_OUTPUT="abc1234 feat: do something"
export BD_LIST_IN_PROGRESS="No issues found."
export BD_LIST_CLOSED="  task-789  CLOSED  Implement feature"
export BD_LIST_OPEN="No issues found."
STOP_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_STOP:$PATH" \
    bash "$PLUGIN_ROOT/hooks/stop" 2>/dev/null || true)
if echo "$STOP_OUT" | grep -qE "WARNING.*NO beads issues"; then
    fail "4b. commits + closed task — should NOT warn about NO beads issues, got: $(printf '%q' "$STOP_OUT")"
else
    pass "4b. commits + closed task — no spurious 'NO beads issues' warning"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
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
