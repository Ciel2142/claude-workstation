#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
echo "=== Escalation: Trivial -> Small ==="
TEST_DIR=$(cat "${TMPDIR:-/tmp}/.workflow-test-dir" 2>/dev/null || echo "/tmp/workflow-test")
cd "$TEST_DIR"

ID=$(extract_id "$(bd create --title="Fix greet function output format" --type=task --priority=3 2>&1)")

# Discover it needs behavior change + test = escalate to small
sedi '/^\[/i \
assert_eq "greet handles empty name" "Hello, stranger!" "$(greet "")"' tests/run.sh

# RED (capture output first to avoid pipefail masking grep result)
red_output=$(bash tests/run.sh 2>&1 || true)
if echo "$red_output" | grep -q "FAIL"; then
    echo "  RED confirmed (escalated to small, applying TDD)"
fi

# GREEN
sedi 's/local name="$1"/local name="${1:-stranger}"/' src/utils.sh

bash tests/run.sh
echo "  GREEN confirmed"

git add src/utils.sh tests/run.sh
git commit -m "fix: handle empty name in greet function"
bd close "$ID" --reason="Escalated from trivial to small, TDD applied"

echo "=== Escalation: PASS ==="
