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
    local cache_dir="${XDG_RUNTIME_DIR:-/tmp}"
    echo "${cache_dir}/.beads-gate-${USER:-$(id -un)}-${project_hash}"
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
    bash "$PLUGIN_ROOT/hooks/bd-notes-append" "task-123" "spec: docs/spec.md" 2>/dev/null
if [[ -f "$CAPTURE_FILE" ]]; then
    CAPTURED=$(cat "$CAPTURE_FILE")
    if [[ "$CAPTURED" == "spec: docs/spec.md" ]]; then
        pass "1a. empty notes — captures exactly 'spec: docs/spec.md'"
    else
        fail "1a. empty notes — expected 'spec: docs/spec.md', got: $(printf '%q' "$CAPTURED")"
    fi
else
    fail "1a. empty notes — capture file not written"
fi

# 1b. Existing notes: bd show returns task with existing 'spec: docs/spec.md' in NOTES
rm -f "$CAPTURE_FILE"
export BD_SHOW_OUTPUT="TITLE
Test task
NOTES
spec: docs/spec.md
STATUS
open"
PATH="$TMPDIR_BD:$PATH" \
    bash "$PLUGIN_ROOT/hooks/bd-notes-append" "task-123" "plan: docs/plan.md" 2>/dev/null
if [[ -f "$CAPTURE_FILE" ]]; then
    CAPTURED=$(cat "$CAPTURE_FILE")
    EXPECTED="spec: docs/spec.md
plan: docs/plan.md"
    if [[ "$CAPTURED" == "$EXPECTED" ]]; then
        pass "1b. existing notes — appends new line preserving existing content"
    else
        fail "1b. existing notes — expected 'spec: docs/spec.md\\nplan: docs/plan.md', got: $(printf '%q' "$CAPTURED")"
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

# 1d. All-caps freetext in notes should NOT be truncated
rm -f "$CAPTURE_FILE"
export BD_SHOW_OUTPUT="TITLE
Test task
NOTES
spec: docs/spec.md
IMPORTANT NOTE
plan: docs/plan.md
STATUS
open"
PATH="$TMPDIR_BD:$PATH" \
    bash "$PLUGIN_ROOT/hooks/bd-notes-append" "task-123" "completed: 1" 2>/dev/null
if [[ -f "$CAPTURE_FILE" ]]; then
    CAPTURED=$(cat "$CAPTURE_FILE")
    if echo "$CAPTURED" | grep -q "IMPORTANT NOTE" && echo "$CAPTURED" | grep -q "plan: docs/plan.md" && echo "$CAPTURED" | grep -q "completed: 1"; then
        pass "1d. all-caps freetext — preserves content without truncation"
    else
        fail "1d. all-caps freetext — truncated at all-caps line, got: $(printf '%q' "$CAPTURED")"
    fi
else
    fail "1d. all-caps freetext — capture file not written"
fi

# 1e. DEPENDS ON section header should stop note extraction
rm -f "$CAPTURE_FILE"
export BD_SHOW_OUTPUT="TITLE
Test task
NOTES
spec: docs/spec.md
plan: docs/plan.md
DEPENDS ON
  other-task-123
STATUS
open"
PATH="$TMPDIR_BD:$PATH" \
    bash "$PLUGIN_ROOT/hooks/bd-notes-append" "task-123" "completed: 1" 2>/dev/null
if [[ -f "$CAPTURE_FILE" ]]; then
    CAPTURED=$(cat "$CAPTURE_FILE")
    if echo "$CAPTURED" | grep -q "plan: docs/plan.md" \
       && echo "$CAPTURED" | grep -q "completed: 1" \
       && ! echo "$CAPTURED" | grep -q "other-task-123"; then
        pass "1e. DEPENDS ON header — stops extraction, does not leak into notes"
    else
        fail "1e. DEPENDS ON header — leaked dependency data into notes, got: $(printf '%q' "$CAPTURED")"
    fi
else
    fail "1e. DEPENDS ON header — capture file not written"
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

# 2b. Task exists — no output expected (tier check removed)
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
if [[ -z "$GATE_OUT" ]]; then
    pass "2b. task exists — outputs nothing (no warning)"
else
    fail "2b. task exists — expected empty output, got: $(printf '%q' "$GATE_OUT")"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 3: Position detection tests
# ---------------------------------------------------------------------------
echo "3. Position detection"

# Mirror the workflow skill position detection logic
detect_position() {
    local notes="$1"
    if echo "$notes" | grep -q 'docs-updated:'; then
        echo "post-update-docs"
    elif echo "$notes" | grep -q 'verification:'; then
        echo "post-verification"
    elif echo "$notes" | grep -q 'completed:'; then
        echo "mid-implementation"
    elif echo "$notes" | grep -q 'planned-tasks:'; then
        echo "post-decomposition"
    elif echo "$notes" | grep -q 'plan:'; then
        echo "post-planning"
    elif echo "$notes" | grep -q 'spec:'; then
        echo "post-brainstorming"
    elif echo "$notes" | grep -q 'debug:'; then
        echo "mid-debugging"
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

_assert_position "3a. spec only"          "spec: docs/specs/foo.md"                                           "post-brainstorming"
_assert_position "3b. spec + plan"        "$(printf 'spec: docs/specs/foo.md\nplan: docs/plans/foo.md')"      "post-planning"
_assert_position "3c. with completed"     "$(printf 'plan: docs/plans/foo.md\ncompleted: 1,2,3')"             "mid-implementation"
_assert_position "3d. with verification"  "$(printf 'plan: docs/plans/foo.md\ncompleted: 1,2\nverification: tests 47/47')" "post-verification"
_assert_position "3e. with docs-updated"  "$(printf 'verification: tests 47/47\ndocs-updated: README refreshed')"          "post-update-docs"
_assert_position "3f. with debug"         "$(printf 'debug: root cause -- stale cache')"                      "mid-debugging"
_assert_position "3g. empty string"       ""                                                                   "unknown"
_assert_position "3h. with planned-tasks" "$(printf 'plan: docs/plans/foo.md\nplanned-tasks: 5')"             "post-decomposition"
_assert_position "3i. planned-tasks before completed" "$(printf 'planned-tasks: 3\ncompleted: 1')"            "mid-implementation"

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
        HAS_CLOSED_AFTER=""
        for arg in "$@"; do
            case "$arg" in
                --status=*) HAS_STATUS="${arg#--status=}" ;;
                --closed-after=*) HAS_CLOSED_AFTER="${arg#--closed-after=}" ;;
            esac
        done
        case "$HAS_STATUS" in
            in_progress) echo "$BD_LIST_IN_PROGRESS" ;;
            closed)
                # F10: when --closed-after is passed, use session-scoped result
                if [ -n "$HAS_CLOSED_AFTER" ] && [ -n "${BD_LIST_CLOSED_RECENT+x}" ]; then
                    echo "$BD_LIST_CLOSED_RECENT"
                else
                    echo "$BD_LIST_CLOSED"
                fi
                ;;
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

# 4b. Commits exist + recently closed task — should NOT warn about no beads issues
rm -f "$GATE_CACHE"
export GIT_LOG_OUTPUT="abc1234 feat: do something"
export BD_LIST_IN_PROGRESS="No issues found."
export BD_LIST_CLOSED="  task-789  CLOSED  Implement feature"
export BD_LIST_CLOSED_RECENT="  task-789  CLOSED  Implement feature"
export BD_LIST_OPEN="No issues found."
STOP_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_STOP:$PATH" \
    bash "$PLUGIN_ROOT/hooks/stop" 2>/dev/null || true)
if echo "$STOP_OUT" | grep -qE "WARNING.*NO beads issues"; then
    fail "4b. commits + closed task — should NOT warn about NO beads issues, got: $(printf '%q' "$STOP_OUT")"
else
    pass "4b. commits + closed task — no spurious 'NO beads issues' warning"
fi

# 4c. Commits exist + no issues at all — should warn
rm -f "$GATE_CACHE"
export GIT_LOG_OUTPUT="abc1234 feat: do something"
export BD_LIST_IN_PROGRESS="No issues found."
export BD_LIST_CLOSED="No issues found."
export BD_LIST_CLOSED_RECENT="No issues found."
export BD_LIST_OPEN="No issues found."
STOP_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_STOP:$PATH" \
    bash "$PLUGIN_ROOT/hooks/stop" 2>/dev/null || true)
if echo "$STOP_OUT" | grep -qE "WARNING.*NO beads issues"; then
    pass "4c. commits + no issues — warns about NO beads issues"
else
    fail "4c. commits + no issues — expected WARNING about 'NO beads issues', got: $(printf '%q' "$STOP_OUT")"
fi

# 4d. F10 regression: commits + historical closed task (not recent) + no in-progress — SHOULD warn
rm -f "$GATE_CACHE"
export GIT_LOG_OUTPUT="abc1234 feat: do something"
export BD_LIST_IN_PROGRESS="No issues found."
export BD_LIST_CLOSED="  task-100  CLOSED  Old historical task"
export BD_LIST_CLOSED_RECENT="No issues found."
export BD_LIST_OPEN="No issues found."
STOP_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_STOP:$PATH" \
    bash "$PLUGIN_ROOT/hooks/stop" 2>/dev/null || true)
if echo "$STOP_OUT" | grep -qE "WARNING.*NO beads issues"; then
    pass "4d. F10 regression: historical closed task does NOT suppress warning"
else
    fail "4d. F10 regression: historical closed task should NOT suppress warning, got: $(printf '%q' "$STOP_OUT")"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 5: Session-start output branches (M3)
# ---------------------------------------------------------------------------
echo "5. session-start output branches"

# 5a. Cursor branch: CURSOR_PLUGIN_ROOT set
CURSOR_OUT=$(CURSOR_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || echo "")
if echo "$CURSOR_OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'additional_context' in d, 'missing additional_context key'
assert isinstance(d['additional_context'], str), 'additional_context not string'
assert len(d['additional_context']) > 100, 'additional_context too short'
" 2>/dev/null; then
    pass "5a. Cursor branch — produces {additional_context: ...} format"
else
    fail "5a. Cursor branch — wrong JSON format"
fi

# 5b. Copilot CLI branch: COPILOT_CLI set (no CURSOR_PLUGIN_ROOT)
COPILOT_OUT=$(COPILOT_CLI="1" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || echo "")
if echo "$COPILOT_OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'additionalContext' in d, 'missing additionalContext key'
assert 'hookSpecificOutput' not in d, 'should not have hookSpecificOutput'
assert isinstance(d['additionalContext'], str), 'additionalContext not string'
" 2>/dev/null; then
    pass "5b. Copilot CLI branch — produces {additionalContext: ...} format"
else
    fail "5b. Copilot CLI branch — wrong JSON format"
fi

# 5c. Claude Code branch (default): only CLAUDE_PLUGIN_ROOT set
CC_OUT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || echo "")
if echo "$CC_OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'hookSpecificOutput' in d, 'missing hookSpecificOutput'
hso = d['hookSpecificOutput']
assert 'additionalContext' in hso, 'missing additionalContext in hookSpecificOutput'
" 2>/dev/null; then
    pass "5c. Claude Code branch — produces {hookSpecificOutput: {additionalContext: ...}} format"
else
    fail "5c. Claude Code branch — wrong JSON format"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 6: F15 — Previously untested hook paths
# ---------------------------------------------------------------------------
echo "6. untested hook paths (F15)"

# 6a. pre-change-gate: no-bd guard — exits 0 silently when bd not in PATH
TMPDIR_NOBD=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BD" "$TMPDIR_GATE" "$TMPDIR_STOP" "$TMPDIR_NOBD"' EXIT
# Empty PATH dir with only git (needed for rev-parse)
cat > "$TMPDIR_NOBD/git" << GITNOBD
#!/usr/bin/env bash
echo "$PLUGIN_ROOT"
GITNOBD
chmod +x "$TMPDIR_NOBD/git"
# No bd in PATH — pre-change-gate should exit 0 with no output
NOBD_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_NOBD" \
    bash "$PLUGIN_ROOT/hooks/pre-change-gate" 2>/dev/null || true)
if [ -z "$NOBD_OUT" ]; then
    pass "6a. pre-change-gate no-bd guard — exits silently"
else
    fail "6a. pre-change-gate no-bd guard — expected no output, got: $(printf '%q' "$NOBD_OUT")"
fi

# 6b. stop hook: no-bd warning — should warn when bd not found
# Use restricted PATH with only essential system commands (no bd)
STOP_NOBD_OUT=$(cd "$PLUGIN_ROOT" && PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$PLUGIN_ROOT/hooks/stop" 2>&1 || true)
if echo "$STOP_NOBD_OUT" | grep -q "bd not found"; then
    pass "6b. stop hook no-bd — warns about missing bd"
else
    fail "6b. stop hook no-bd — expected 'bd not found' warning, got: $(printf '%q' "$STOP_NOBD_OUT")"
fi

# 6c. bd-notes-append: bd show failure — exits 1 with error
NOAPPEND_OUT=$(bash "$PLUGIN_ROOT/hooks/bd-notes-append" "nonexistent-task-xyz" "spec: docs/spec.md" 2>&1 || true)
NOAPPEND_EXIT=$?
if echo "$NOAPPEND_OUT" | grep -qi "error\|failed"; then
    pass "6c. bd-notes-append bd-show failure — reports error"
else
    # May also exit non-zero without message if bd itself errors
    if [ "$NOAPPEND_EXIT" -ne 0 ] 2>/dev/null; then
        pass "6c. bd-notes-append bd-show failure — exits non-zero"
    else
        fail "6c. bd-notes-append bd-show failure — expected error, got: $(printf '%q' "$NOAPPEND_OUT")"
    fi
fi

# 6d. pre-change-gate: cache hit — second call within 60s uses cache
rm -f "$GATE_CACHE"
FIRST_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_GATE:$PATH" \
    bash "$PLUGIN_ROOT/hooks/pre-change-gate" 2>/dev/null || true)
# Second call should hit cache and return same result
SECOND_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_GATE:$PATH" \
    bash "$PLUGIN_ROOT/hooks/pre-change-gate" 2>/dev/null || true)
if [ "$FIRST_OUT" = "$SECOND_OUT" ]; then
    pass "6d. pre-change-gate cache hit — consistent output on second call"
else
    fail "6d. pre-change-gate cache hit — first and second call differ"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 7: YAML spec structure validation
# ---------------------------------------------------------------------------
echo ""
echo "7. YAML spec structure"

SPECS_DIR="$PLUGIN_ROOT/tests/specs"
if [ -d "$SPECS_DIR" ]; then
    for spec_file in "$SPECS_DIR"/*.yaml; do
        [ -f "$spec_file" ] || continue
        spec_name=$(basename "$spec_file" .yaml)
        # Check required top-level keys exist
        HAS_ID=0; HAS_STEPS=0; HAS_SCORING=0
        grep -q '^id:' "$spec_file" 2>/dev/null && HAS_ID=1
        grep -q '^steps:' "$spec_file" 2>/dev/null && HAS_STEPS=1
        grep -q '^scoring:' "$spec_file" 2>/dev/null && HAS_SCORING=1
        if [ "$HAS_ID" -eq 1 ] && [ "$HAS_STEPS" -eq 1 ] && [ "$HAS_SCORING" -eq 1 ]; then
            pass "7. $spec_name.yaml has required keys (id, steps, scoring)"
        else
            fail "7. $spec_name.yaml missing keys: id=$HAS_ID steps=$HAS_STEPS scoring=$HAS_SCORING"
        fi
        # Check version is 2.0
        if grep -q 'version: "2.0"' "$spec_file" 2>/dev/null; then
            pass "7. $spec_name.yaml version is 2.0"
        else
            fail "7. $spec_name.yaml version is not 2.0"
        fi
    done
else
    pass "7. specs directory not yet created (skipped)"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 8: Command injection prevention in session-start (SECURITY)
# ---------------------------------------------------------------------------
echo "8. session-start command injection prevention"

TMPDIR_INJECT=$(mktemp -d)
CANARY_FILE=$(mktemp -u "${TMPDIR_INJECT}/canary.XXXXXX")
trap 'rm -rf "$TMPDIR_BD" "$TMPDIR_GATE" "$TMPDIR_STOP" "$TMPDIR_NOBD" "$TMPDIR_INJECT"' EXIT

# Mock bd: record arguments, do nothing dangerous
cat > "$TMPDIR_INJECT/bd" << 'MOCK_BD'
#!/usr/bin/env bash
exit 0
MOCK_BD
chmod +x "$TMPDIR_INJECT/bd"

# Mock git: return the temp dir as git root (no .beads, so auto-init triggers)
FAKE_GIT_ROOT=$(mktemp -d "${TMPDIR_INJECT}/gitroot.XXXXXX")
cat > "$TMPDIR_INJECT/git" << MOCK_GIT
#!/usr/bin/env bash
case "\$1" in
    rev-parse) echo "$FAKE_GIT_ROOT" ;;
    *) exec /usr/bin/git "\$@" ;;
esac
MOCK_GIT
chmod +x "$TMPDIR_INJECT/git"

# 8a. Hostile BEADS_SERVER_HOST must NOT execute injected command
INJECT_OUT=$(
    BEADS_SERVER_HOST='evil$(touch '"$CANARY_FILE"')' \
    BEADS_SERVER_PORT='3307' \
    BEADS_SERVER_USER='root' \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    PATH="$TMPDIR_INJECT:$PATH" \
    bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || true
)
if [ -f "$CANARY_FILE" ]; then
    fail "8a. command injection — canary file was created (injection succeeded!)"
    rm -f "$CANARY_FILE"
else
    pass "8a. command injection — canary file NOT created (injection blocked)"
fi

# 8b. Hook should still produce valid JSON despite hostile input
if echo "$INJECT_OUT" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
    pass "8b. hostile env — hook still produces valid JSON"
else
    fail "8b. hostile env — hook did not produce valid JSON, got: $(printf '%q' "$INJECT_OUT")"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 9: F11 regression — JSON control character stripping
# ---------------------------------------------------------------------------
echo "9. F11 — JSON control character stripping"

# Create a temp plugin dir with a CLAUDE.md containing control chars
TMPDIR_F11=$(mktemp -d)

mkdir -p "$TMPDIR_F11/hooks"
cp "$PLUGIN_ROOT/hooks/session-start" "$TMPDIR_F11/hooks/"

# Write a CLAUDE.md with form-feed (0x0c) and backspace (0x08) chars
printf '## Workflow\n\x0cThis has a form-feed\x08and backspace\n' > "$TMPDIR_F11/CLAUDE.md"

F11_OUT=$(CLAUDE_PLUGIN_ROOT="$TMPDIR_F11" \
    bash "$TMPDIR_F11/hooks/session-start" 2>/dev/null || echo "")

if echo "$F11_OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass "9a. CLAUDE.md with control chars produces valid JSON"
else
    fail "9a. CLAUDE.md with control chars produces INVALID JSON"
fi

# Verify the content is present (stripped of control chars, not empty)
if echo "$F11_OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ctx = d.get('hookSpecificOutput', d).get('additionalContext', d.get('additional_context', ''))
assert 'Workflow' in ctx, 'content lost after stripping'
assert 'form-feed' in ctx, 'content truncated at control char'
" 2>/dev/null; then
    pass "9b. content preserved after control char stripping"
else
    fail "9b. content lost or truncated after control char stripping"
fi

rm -rf "$TMPDIR_F11"

echo ""

# ---------------------------------------------------------------------------
# Section 10: F12 regression — printf format string safety
# ---------------------------------------------------------------------------
echo "10. F12 — printf format string safety"

TMPDIR_F12=$(mktemp -d)

mkdir -p "$TMPDIR_F12/hooks"
cp "$PLUGIN_ROOT/hooks/session-start" "$TMPDIR_F12/hooks/"

# Write CLAUDE.md with % characters that would break printf if used in format string
# Using heredoc with single-quoted delimiter to prevent any interpretation
cat > "$TMPDIR_F12/CLAUDE.md" << 'CLAUDE_EOF'
## Workflow
Coverage: 100%% achieved
Progress: %%d items %%s done
CLAUDE_EOF

# Verify the file actually contains % characters
if grep -q '%' "$TMPDIR_F12/CLAUDE.md"; then
    :  # File contains % as expected, continue
else
    fail "10-setup. test CLAUDE.md does not contain %% characters"
    rm -rf "$TMPDIR_F12"
fi

F12_OUT=$(CLAUDE_PLUGIN_ROOT="$TMPDIR_F12" \
    bash "$TMPDIR_F12/hooks/session-start" 2>/dev/null || echo "")

if echo "$F12_OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass "10a. CLAUDE.md with %% format chars produces valid JSON"
else
    fail "10a. CLAUDE.md with %% format chars produces INVALID JSON"
fi

# Verify the % chars survive in the output
if echo "$F12_OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ctx = d.get('hookSpecificOutput', d).get('additionalContext', d.get('additional_context', ''))
assert '100%' in ctx, 'percent sign lost'
" 2>/dev/null; then
    pass "10b. percent characters preserved in output"
else
    fail "10b. percent characters lost or corrupted"
fi

rm -rf "$TMPDIR_F12"

echo ""

# ---------------------------------------------------------------------------
# Section 11: Timeout resilience — hooks handle hanging bd
# ---------------------------------------------------------------------------
echo "11. Timeout resilience"

# Skip if 'timeout' command not available (macOS without coreutils)
if ! command -v timeout >/dev/null 2>&1; then
    pass "11a. (skipped — timeout command not available)"
    pass "11b. (skipped — timeout command not available)"
else
    TMPDIR_HANG=$(mktemp -d)

    cat > "$TMPDIR_HANG/bd" << 'MOCK'
#!/usr/bin/env bash
# Simulate a hanging bd command
sleep 60
MOCK
    chmod +x "$TMPDIR_HANG/bd"

    cat > "$TMPDIR_HANG/git" << GITMOCK
#!/usr/bin/env bash
case "\$1" in
    rev-parse) echo "$PLUGIN_ROOT" ;;
    log) true ;;
    *) /usr/bin/git "\$@" ;;
esac
GITMOCK
    chmod +x "$TMPDIR_HANG/git"

    # 11a. pre-change-gate with hanging bd — should exit within 12s (2 x 5s timeouts + margin)
    rm -f "$GATE_CACHE"
    if timeout 12 bash -c "cd '$PLUGIN_ROOT' && PATH='$TMPDIR_HANG:$PATH' bash '$PLUGIN_ROOT/hooks/pre-change-gate'" 2>/dev/null; then
        pass "11a. pre-change-gate completes when bd hangs (timeout works)"
    else
        EXIT_CODE=$?
        if [ "$EXIT_CODE" -eq 124 ]; then
            fail "11a. pre-change-gate timed out at 12s (internal timeout 5s did not fire)"
        else
            pass "11a. pre-change-gate exited with code $EXIT_CODE when bd hangs"
        fi
    fi

    # 11b. stop hook with hanging bd — should exit within 15s (multiple bd calls x 5s timeouts + margin)
    rm -f "$GATE_CACHE"
    if timeout 15 bash -c "cd '$PLUGIN_ROOT' && PATH='$TMPDIR_HANG:$PATH' bash '$PLUGIN_ROOT/hooks/stop'" 2>/dev/null; then
        pass "11b. stop hook completes when bd hangs (timeout works)"
    else
        EXIT_CODE=$?
        if [ "$EXIT_CODE" -eq 124 ]; then
            fail "11b. stop hook timed out at 15s (internal timeout 5s did not fire)"
        else
            pass "11b. stop hook exited with code $EXIT_CODE when bd hangs"
        fi
    fi

    rm -rf "$TMPDIR_HANG"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 12: milestone-gate tests
# ---------------------------------------------------------------------------
echo ""
echo "12. milestone-gate"

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

echo ""

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

echo ""

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
