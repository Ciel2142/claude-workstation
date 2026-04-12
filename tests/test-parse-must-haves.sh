#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/hooks/parse-must-haves.sh"
PLAN="$REPO/tests/fixtures/plan-with-must-haves.md"
PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# Case 1: epic artifacts
out=$(bash "$SCRIPT" "$PLAN" epic artifacts)
expected=$'hooks/stall-check.sh\nhooks/parse-sentinel.sh'
if [ "$out" = "$expected" ]; then
    pass "epic artifacts extracted"
else
    fail "epic artifacts: got '$out'"
fi

# Case 2: epic truths (2 items)
out=$(bash "$SCRIPT" "$PLAN" epic truths)
count=$(echo "$out" | wc -l)
[ "$count" -eq 2 ] && pass "epic truths count=2" || fail "epic truths count=$count"

# Case 3: task-1 artifacts
out=$(bash "$SCRIPT" "$PLAN" task-1 artifacts)
[ "$out" = "hooks/stall-check.sh" ] && pass "task-1 artifacts" || fail "task-1 artifacts: got '$out'"

# Case 4: task-2 truths
out=$(bash "$SCRIPT" "$PLAN" task-2 truths)
[ "$out" = "parse-sentinel.sh matches last H2 sentinel" ] && pass "task-2 truths" || fail "task-2 truths: got '$out'"

# Case 5: task-2 key_links (empty, missing field)
out=$(bash "$SCRIPT" "$PLAN" task-2 key_links)
[ -z "$out" ] && pass "task-2 key_links empty" || fail "task-2 key_links non-empty: '$out'"

# Case 6: missing anchor returns exit 1
set +e
bash "$SCRIPT" "$PLAN" task-99 artifacts 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 1 ] && pass "missing anchor exits 1" || fail "missing anchor rc=$rc"

# Case 7: missing plan file returns exit 1
set +e
bash "$SCRIPT" /nonexistent.md epic artifacts 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 1 ] && pass "missing plan file exits 1" || fail "missing plan rc=$rc"

# Case 8: invalid field returns exit 2
set +e
bash "$SCRIPT" "$PLAN" epic bogus 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 2 ] && pass "invalid field exits 2" || fail "invalid field rc=$rc"

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
