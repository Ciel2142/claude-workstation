#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
echo "=== Bug Path: Fix divide rounding ==="
# F18: No stale fallback — require scaffold.sh to have run
TEST_DIR=$(cat "${TMPDIR:-/tmp}/.workflow-test-dir-$(id -un)" 2>/dev/null || echo "")
if [ -z "$TEST_DIR" ] || [ ! -d "$TEST_DIR" ]; then echo "SKIP: No test directory (run scaffold.sh first)"; exit 0; fi
cd "$TEST_DIR"

# Create bug
ID=$(extract_id "$(bd create --title="Bug: divide truncates instead of rounding" --type=bug --priority=2 2>&1)")
bd update "$ID" --claim

# DEBUG phase: identify root cause
# Root cause: bash arithmetic does integer division (truncation), not rounding
bd update "$ID" --notes "Debug: root cause is bash integer division truncates toward zero"

# TDD RED: write regression test that exposes the bug
# Better test: divide 7 2 should be 4 (rounded) but bash gives 3 (truncated)
sedi '/^\[/i \
assert_eq "divide rounds 7\/2 to nearest" "4" "$(divide 7 2)"' tests/run.sh

red_output=$(bash tests/run.sh 2>&1 || true)
if echo "$red_output" | grep -q "FAIL"; then
    echo "  RED confirmed (divide 7/2 returns 3, expected 4)"
else
    echo "  ERROR: Regression test should have failed"; exit 1
fi

# TDD GREEN: fix the divide function to round to nearest integer
sedi '/^divide() {/,/^}/ c\
divide() {\
    local a="$1"\
    local b="$2"\
    if ! [[ "$a" =~ ^-?[0-9]+$ ]] || ! [[ "$b" =~ ^-?[0-9]+$ ]]; then\
        echo "error: arguments must be integers" >&2\
        return 1\
    fi\
    if [[ "$b" -eq 0 ]]; then\
        echo "error: division by zero" >&2\
        return 1\
    fi\
    # Round to nearest integer instead of truncating\
    echo $(( (a + b/2) / b ))\
    # Note: this rounding formula works for positive divisors only.\
    # Negative divisors and banker'\''s rounding are out of scope for this demo.\
}' src/utils.sh

# Verify GREEN
bash tests/run.sh
echo "  GREEN confirmed"

git add src/utils.sh tests/run.sh
git commit -m "fix: round divide results to nearest integer"
bd close "$ID" --reason="Root cause identified, regression test added, fix applied"

echo "=== Bug Path: PASS ==="
