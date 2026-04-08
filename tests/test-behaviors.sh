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

# 1d. All-caps freetext in notes should NOT be truncated
rm -f "$CAPTURE_FILE"
export BD_SHOW_OUTPUT="TITLE
Test task
NOTES
tier: small
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
tier: medium+
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
    elif echo "$notes" | grep -q 'planned-tasks:'; then
        echo "post-decomposition"
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
_assert_position "3i. with planned-tasks"  "$(printf 'tier: medium\nplan: docs/plans/foo.md\nplanned-tasks: 5')"  "post-decomposition"
_assert_position "3j. planned-tasks before completed" "$(printf 'tier: medium\nplanned-tasks: 3\ncompleted: 1')" "mid-implementation"

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
NOAPPEND_OUT=$(bash "$PLUGIN_ROOT/hooks/bd-notes-append" "nonexistent-task-xyz" "tier: small" 2>&1 || true)
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
# Section 7: workflow.md inlined content guards
# ---------------------------------------------------------------------------
echo ""
echo "7. workflow.md inlined content"

WORKFLOW_FILE="$PLUGIN_ROOT/contexts/workflow.md"

# 7a. Review levels defined (Standard and Consensus)
if grep -q 'Standard' "$WORKFLOW_FILE" 2>/dev/null && grep -q 'Consensus' "$WORKFLOW_FILE" 2>/dev/null; then
    pass "7a. workflow.md defines Standard and Consensus review levels"
else
    fail "7a. workflow.md missing Standard and/or Consensus"
fi

# 7b. All 5 review-level signals present
SIGNAL_COUNT=0
for signal in "security" "API surface" "cross-domain" "supply-chain" "infrastructure"; do
    if grep -qi "$signal" "$WORKFLOW_FILE" 2>/dev/null; then
        SIGNAL_COUNT=$((SIGNAL_COUNT + 1))
    fi
done
if [[ $SIGNAL_COUNT -ge 5 ]]; then
    pass "7b. all 5 review-level signals present in workflow.md"
else
    fail "7b. only $SIGNAL_COUNT/5 review-level signals in workflow.md"
fi

# 7c. Milestone key table present
if grep -q 'tier:' "$WORKFLOW_FILE" 2>/dev/null && grep -q 'completed:' "$WORKFLOW_FILE" 2>/dev/null && grep -q 'verification:' "$WORKFLOW_FILE" 2>/dev/null && grep -q 'stopped:' "$WORKFLOW_FILE" 2>/dev/null; then
    pass "7c. milestone key table present in workflow.md"
else
    fail "7c. milestone key table missing or incomplete in workflow.md"
fi

# 7d. Scope health thresholds present
if grep -q '1.5x' "$WORKFLOW_FILE" 2>/dev/null && grep -q '2.0x' "$WORKFLOW_FILE" 2>/dev/null; then
    pass "7d. scope health thresholds (1.5x, 2.0x) in workflow.md"
else
    fail "7d. scope health thresholds missing from workflow.md"
fi

# 7e. Verification format present
if grep -q '✓' "$WORKFLOW_FILE" 2>/dev/null && grep -q '✗' "$WORKFLOW_FILE" 2>/dev/null; then
    pass "7e. verification format symbols present in workflow.md"
else
    fail "7e. verification format symbols missing from workflow.md"
fi

# 7f. Spike phase referenced
if grep -qi 'spike' "$WORKFLOW_FILE" 2>/dev/null; then
    pass "7f. spike phase documented in workflow.md"
else
    fail "7f. spike phase missing from workflow.md"
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
