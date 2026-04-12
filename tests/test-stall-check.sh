#!/usr/bin/env bash
# Unit test for hooks/stall-check.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/hooks/stall-check.sh"
STATE_DIR=$(mktemp -d)
trap 'rm -rf "$STATE_DIR"' EXIT
export CLAUDE_WORKSTATION_STATE_DIR="$STATE_DIR"
TASK="test-task-001"
PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# Case 1: first call has no prior state, always OK
if out=$(bash "$SCRIPT" "$TASK" spec 5 2>&1) && echo "$out" | grep -q "OK"; then
    pass "first call prints OK and exits 0"
else
    fail "first call rejected or no OK output: $out"
fi

# Case 2: decreasing count continues
if out=$(bash "$SCRIPT" "$TASK" spec 3 2>&1) && echo "$out" | grep -q "OK"; then
    pass "decreasing count continues"
else
    fail "decreasing count rejected: $out"
fi

# Case 3: equal count stalls (exit 1)
set +e
out=$(bash "$SCRIPT" "$TASK" spec 3 2>&1)
rc=$?
set -e
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "STALLED"; then
    pass "equal count stalls with exit 1"
else
    fail "equal count did not stall (rc=$rc): $out"
fi

# Case 4: growing count stalls
bash "$SCRIPT" "$TASK" quality 2 >/dev/null
set +e
out=$(bash "$SCRIPT" "$TASK" quality 5 2>&1)
rc=$?
set -e
if [ "$rc" -eq 1 ]; then
    pass "growing count stalls"
else
    fail "growing count did not stall (rc=$rc)"
fi

# Case 5: different phases use independent state
bash "$SCRIPT" new-task-002 spec 10 >/dev/null
if bash "$SCRIPT" new-task-002 quality 10 >/dev/null 2>&1; then
    pass "phases are independent"
else
    fail "phases leaked state"
fi

# Case 6: usage error on missing args
set +e
bash "$SCRIPT" 2>/dev/null
rc=$?
set -e
if [ "$rc" -eq 2 ]; then
    pass "missing args returns exit 2"
else
    fail "missing args returned rc=$rc"
fi

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
