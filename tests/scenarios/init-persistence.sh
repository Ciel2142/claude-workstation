#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
echo "=== Init Persistence: Milestone notes ==="
# F18: No stale fallback — require scaffold.sh to have run
TEST_DIR=$(cat "${TMPDIR:-/tmp}/.workflow-test-dir-$(id -un)" 2>/dev/null || echo "")
if [ -z "$TEST_DIR" ] || [ ! -d "$TEST_DIR" ]; then echo "SKIP: No test directory (run scaffold.sh first)"; exit 0; fi
cd "$TEST_DIR"

# Create a task and add milestone notes (no tier)
TASK_ID=$(extract_id "$(bd create --title="Test milestone persistence" --type=task --priority=2 2>&1)")
bd update "$TASK_ID" --notes "spec: docs/superpowers/specs/test-spec.md"

# Verify spec was persisted
NOTES=$(bd show "$TASK_ID" 2>&1)
if echo "$NOTES" | grep -q "spec:"; then
    echo "  Spec milestone persisted: PASS"
else
    echo "  Spec milestone NOT in notes: FAIL"; exit 1
fi

# Add plan milestone (cumulative)
bd update "$TASK_ID" --notes "spec: docs/superpowers/specs/test-spec.md
plan: docs/superpowers/plans/test-plan.md, 3 tasks"

# Verify both milestones visible
NOTES=$(bd show "$TASK_ID" 2>&1)
if echo "$NOTES" | grep -q "plan:"; then
    echo "  Plan milestone persisted: PASS"
else
    echo "  Plan milestone NOT in notes: FAIL"; exit 1
fi
if echo "$NOTES" | grep -q "spec:"; then
    echo "  Spec preserved in cumulative update: PASS"
else
    echo "  Spec lost in cumulative update: FAIL"; exit 1
fi

bd close "$TASK_ID" --reason="Milestone persistence test"

echo "=== Init Persistence: PASS ==="
