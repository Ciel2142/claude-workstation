#!/usr/bin/env bash
set -euo pipefail
echo "=== Escalation: Trivial -> Small ==="
cd /tmp/workflow-test

ID=$(bd create --title="Fix greet function output format" --type=task --priority=3 2>&1 | grep -oP 'workflow-test-\w+')

# Discover it needs behavior change + test = escalate to small
sed -i '/^\[/i \
assert_eq "greet handles empty name" "Hello, stranger!" "$(greet "")"' tests/run.sh

# RED
if bash tests/run.sh 2>&1 | grep -q "FAIL"; then
    echo "  RED confirmed (escalated to small, applying TDD)"
fi

# GREEN
sed -i 's/local name="$1"/local name="${1:-stranger}"/' src/utils.sh

bash tests/run.sh
echo "  GREEN confirmed"

git add src/utils.sh tests/run.sh
git commit -m "fix: handle empty name in greet function"
bd close "$ID" --reason="Escalated from trivial to small, TDD applied"

echo "=== Escalation: PASS ==="
