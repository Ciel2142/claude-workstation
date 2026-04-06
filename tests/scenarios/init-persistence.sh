#!/usr/bin/env bash
set -euo pipefail
echo "=== Init Persistence: Tier stored in notes ==="
cd /tmp/workflow-test

# Simulate /init for a trivial task — init writes tier to notes
TRIV_ID=$(bd create --title="Fix whitespace in utils" --type=task --priority=4 2>&1 | grep -oP 'workflow-test-\w+')
bd update "$TRIV_ID" --notes "tier: trivial"

# Verify tier was persisted
TRIV_NOTES=$(bd show "$TRIV_ID" 2>&1)
if echo "$TRIV_NOTES" | grep -q "tier: trivial"; then
    echo "  Trivial tier persisted: PASS"
else
    echo "  Trivial tier NOT in notes: FAIL"; exit 1
fi

bd close "$TRIV_ID" --reason="Tier persistence test"

# Simulate /init for a small task
SMALL_ID=$(bd create --title="Add modulo function" --type=task --priority=3 2>&1 | grep -oP 'workflow-test-\w+')
bd update "$SMALL_ID" --notes "tier: small"

SMALL_NOTES=$(bd show "$SMALL_ID" 2>&1)
if echo "$SMALL_NOTES" | grep -q "tier: small"; then
    echo "  Small tier persisted: PASS"
else
    echo "  Small tier NOT in notes: FAIL"; exit 1
fi

bd close "$SMALL_ID" --reason="Tier persistence test"

# Simulate /init for a medium+ epic with milestone progression
# Note: bd update --notes replaces (not appends), so each milestone overwrites
# the previous. Resume handles this by checking latest milestone first, and
# falling back to task type inference for tier when tier: note is overwritten.
EPIC_ID=$(bd create --title="Add string operations" --type=epic --priority=2 2>&1 | grep -oP 'workflow-test-\w+')
bd update "$EPIC_ID" --notes "tier: medium+"

# Verify tier is set initially
EPIC_NOTES=$(bd show "$EPIC_ID" 2>&1)
if echo "$EPIC_NOTES" | grep -q "tier: medium+"; then
    echo "  Medium+ tier persisted initially: PASS"
else
    echo "  Medium+ tier NOT in notes: FAIL"; exit 1
fi

# Simulate milestone progression — each overwrites previous notes
bd update "$EPIC_ID" --notes "spec: docs/superpowers/specs/test-spec.md"
bd update "$EPIC_ID" --notes "plan: docs/superpowers/plans/test-plan.md, 3 tasks"

# Verify latest milestone is visible (plan: overwrote spec: which overwrote tier:)
EPIC_NOTES=$(bd show "$EPIC_ID" 2>&1)
if echo "$EPIC_NOTES" | grep -q "plan:"; then
    echo "  Latest milestone (Plan) detected: PASS"
else
    echo "  Latest milestone NOT in notes: FAIL"; exit 1
fi

# Verify tier inference fallback: epic type → medium+ (since tier: was overwritten)
EPIC_TYPE=$(bd show "$EPIC_ID" 2>&1)
if echo "$EPIC_TYPE" | grep -qi "epic"; then
    echo "  Tier fallback via task type (epic → medium+): PASS"
else
    echo "  Task type not detectable: FAIL"; exit 1
fi

bd close "$EPIC_ID" --reason="Milestone progression test"

echo "=== Init Persistence: PASS ==="
