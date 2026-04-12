#!/usr/bin/env bash
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/hooks/parse-sentinel.sh"
PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# Case 1: ## PLAN COMPLETE
out=$(printf '## Work summary\ndid stuff\n\n## PLAN COMPLETE\n' | bash "$SCRIPT")
[ "$out" = "## PLAN COMPLETE" ] && pass "PLAN COMPLETE matched" || fail "PLAN COMPLETE: got '$out'"

# Case 2: ## VERIFICATION FAILED with trailing reason
out=$(printf 'findings below\n\n## VERIFICATION FAILED missing artifact\n' | bash "$SCRIPT")
case "$out" in
    "## VERIFICATION FAILED"*) pass "VERIFICATION FAILED prefix matched" ;;
    *) fail "VERIFICATION FAILED: got '$out'" ;;
esac

# Case 3: no sentinel → exit 1, print 'none'
set +e
out=$(printf '## Random heading\nnothing special\n' | bash "$SCRIPT")
rc=$?
set -e
if [ "$rc" -eq 1 ] && [ "$out" = "none" ]; then
    pass "missing sentinel exits 1 and prints none"
else
    fail "missing sentinel: rc=$rc out='$out'"
fi

# Case 4: last sentinel wins when multiple present
out=$(printf '## PLAN READY\ndraft done\n\n## PLAN COMPLETE\nfinalized\n' | bash "$SCRIPT")
[ "$out" = "## PLAN COMPLETE" ] && pass "last sentinel chosen" || fail "last sentinel: got '$out'"

# Case 5: ## REVIEW BLOCKED
out=$(printf '## REVIEW BLOCKED\n' | bash "$SCRIPT")
[ "$out" = "## REVIEW BLOCKED" ] && pass "REVIEW BLOCKED matched" || fail "REVIEW BLOCKED: got '$out'"

# Case 6: ## BUILD FIXED
out=$(printf '## BUILD FIXED\n' | bash "$SCRIPT")
[ "$out" = "## BUILD FIXED" ] && pass "BUILD FIXED matched" || fail "BUILD FIXED: got '$out'"

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
