#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
echo "=== Small Tier: Add input validation ==="
# F18: No stale fallback — require scaffold.sh to have run
TEST_DIR=$(cat "${TMPDIR:-/tmp}/.workflow-test-dir-$(id -un)" 2>/dev/null || echo "")
if [ -z "$TEST_DIR" ] || [ ! -d "$TEST_DIR" ]; then echo "SKIP: No test directory (run scaffold.sh first)"; exit 0; fi
cd "$TEST_DIR"

ID=$(extract_id "$(bd create --title="Add input validation to add function" --type=bug --priority=2 2>&1)")
bd update "$ID" --claim

# RED — add failing tests
# Note: set +u before add calls prevents fatal nounset errors from bash arithmetic
# indirection ($(( a + b )) where a="abc" → looks up unset $abc → nounset kills subshell)
sedi '/^\[/i \
assert_eq "add rejects non-numeric first arg" "error" "$(set +u; add "abc" 3 2>/dev/null || echo "error")"\
assert_eq "add rejects non-numeric second arg" "error" "$(set +u; add 3 "xyz" 2>/dev/null || echo "error")"\
assert_eq "add still works with valid input" "7" "$(add 3 4)"' tests/run.sh

# Verify RED (capture output first to avoid pipefail masking grep result)
red_output=$(bash tests/run.sh 2>&1 || true)
if echo "$red_output" | grep -q "FAIL"; then
    echo "  RED confirmed"
else
    echo "  ERROR: Tests should have failed"; exit 1
fi

# GREEN — add validation
sedi '/^add() {/,/^}/ c\
add() {\
    local a="$1"\
    local b="$2"\
    if ! [[ "$a" =~ ^-?[0-9]+$ ]] || ! [[ "$b" =~ ^-?[0-9]+$ ]]; then\
        echo "error: arguments must be integers" >\&2\
        return 1\
    fi\
    echo $(( a + b ))\
}' src/utils.sh

# Verify GREEN
bash tests/run.sh
echo "  GREEN confirmed"

git add src/utils.sh tests/run.sh
git commit -m "fix: add input validation to add function"
bd close "$ID" --reason="Input validation added with tests"

echo "=== Small Tier: PASS ==="
