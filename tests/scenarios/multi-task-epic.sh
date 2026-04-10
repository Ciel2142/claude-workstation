#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
echo "=== Multi-Task Epic: Multi-file feature ==="
# F18: No stale fallback — require scaffold.sh to have run
TEST_DIR=$(cat "${TMPDIR:-/tmp}/.workflow-test-dir-$(id -un)" 2>/dev/null || echo "")
if [ -z "$TEST_DIR" ] || [ ! -d "$TEST_DIR" ]; then echo "SKIP: No test directory (run scaffold.sh first)"; exit 0; fi
cd "$TEST_DIR"

# Epic with sub-tasks
EPIC=$(extract_id "$(bd create --title="Add subtract and modulo operations" --type=epic --priority=2 2>&1)")

# Sub-tasks (simulates plan decomposition step)
S1=$(extract_id "$(bd create --title="Step 1: Add subtract" --type=task 2>&1)")
S2=$(extract_id "$(bd create --title="Step 2: Add modulo" --type=task 2>&1)")

bd dep add "$S1" "$EPIC" --type=parent-child
bd dep add "$S2" "$EPIC" --type=parent-child

# Step 1: Subtract (TDD — RED then GREEN)
bd update "$S1" --claim

# RED
sedi '/^\[/i \
assert_eq "subtract returns difference" "1" "$(subtract 4 3)"\
assert_eq "subtract handles negatives" "-5" "$(subtract -2 3)"' tests/run.sh

red_output=$(bash tests/run.sh 2>&1 || true)
if echo "$red_output" | grep -q "FAIL"; then
    echo "  RED confirmed (subtract)"
else
    echo "  ERROR: Tests should have failed"; exit 1
fi

# GREEN
cat >> src/utils.sh << 'FUNC'

subtract() {
    local a="$1"
    local b="$2"
    if ! [[ "$a" =~ ^-?[0-9]+$ ]] || ! [[ "$b" =~ ^-?[0-9]+$ ]]; then
        echo "error: arguments must be integers" >&2
        return 1
    fi
    echo $(( a - b ))
}
FUNC

bash tests/run.sh
echo "  GREEN confirmed (subtract)"

git add src/utils.sh tests/run.sh
git commit -m "feat: add subtract function"
bd close "$S1"

# Step 2: Modulo (TDD — RED then GREEN)
bd update "$S2" --claim

# RED
sedi '/^\[/i \
assert_eq "modulo returns remainder" "1" "$(modulo 7 3)"\
assert_eq "modulo rejects zero" "error" "$(modulo 5 0 2>/dev/null || echo "error")"' tests/run.sh

red_output=$(bash tests/run.sh 2>&1 || true)
if echo "$red_output" | grep -q "FAIL"; then
    echo "  RED confirmed (modulo)"
else
    echo "  ERROR: Tests should have failed"; exit 1
fi

# GREEN
cat >> src/utils.sh << 'FUNC'

modulo() {
    local a="$1"
    local b="$2"
    if ! [[ "$a" =~ ^-?[0-9]+$ ]] || ! [[ "$b" =~ ^-?[0-9]+$ ]]; then
        echo "error: arguments must be integers" >&2
        return 1
    fi
    if [[ "$b" -eq 0 ]]; then
        echo "error: division by zero" >&2
        return 1
    fi
    echo $(( a % b ))
}
FUNC

bash tests/run.sh
echo "  GREEN confirmed (modulo)"

git add src/utils.sh tests/run.sh
git commit -m "feat: add modulo function"
bd close "$S2"

bd close "$EPIC" --reason="All operations implemented"

echo "=== Multi-Task Epic: PASS ==="
