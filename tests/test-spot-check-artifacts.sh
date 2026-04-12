#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/hooks/spot-check-artifacts.sh"
PLAN="$REPO/tests/fixtures/plan-with-must-haves.md"
PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# Case 1: epic block — both artifacts exist (previous tasks created them).
if out=$(cd "$REPO" && bash "$SCRIPT" "$PLAN" epic 2>&1); then
    pass "epic artifacts pass spot-check"
else
    fail "epic artifacts rejected: $out"
fi

# Case 2: task-1 — only stall-check.sh exists, still passes (it's the only required)
if out=$(cd "$REPO" && bash "$SCRIPT" "$PLAN" task-1 2>&1); then
    pass "task-1 artifact passes"
else
    fail "task-1 rejected: $out"
fi

# Case 3: anchor missing -> exit 1
set +e
bash "$SCRIPT" "$PLAN" task-99 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 1 ] && pass "missing anchor exits 1" || fail "missing anchor rc=$rc"

# Case 4: fake plan file with artifact pointing to nonexistent file
FAKE=$(mktemp)
cat > "$FAKE" <<EOF
## must_haves

\`\`\`yaml
truths:
  - fake
artifacts:
  - nonexistent/path/to/file.txt
\`\`\`
EOF
set +e
out=$(cd "$REPO" && bash "$SCRIPT" "$FAKE" epic 2>&1)
rc=$?
set -e
rm -f "$FAKE"
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "missing"; then
    pass "missing artifact fails"
else
    fail "missing artifact: rc=$rc out=$out"
fi

# Case 5: usage error on missing args
set +e
bash "$SCRIPT" 2>/dev/null
rc=$?
set -e
[ "$rc" -eq 2 ] && pass "missing args exits 2" || fail "missing args rc=$rc"

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
