#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
echo "=== Trivial Tier: Fix README typo ==="
TEST_DIR=$(cat "${TMPDIR:-/tmp}/.workflow-test-dir-$(id -un)" 2>/dev/null || echo "/tmp/workflow-test")
cd "$TEST_DIR"

ID=$(extract_id "$(bd create --title="Fix typo in README" --type=task --priority=4 2>&1)")
sedi 's/Proejct/Project/' README.md
grep "Project" README.md | head -1
git add README.md
git commit -m "fix: correct typo in README title"
bd close "$ID" --reason="Typo fixed"

echo "=== Trivial Tier: PASS ==="
