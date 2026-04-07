#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
echo "=== Trivial Tier: Fix README typo ==="
# F18: No stale fallback — require scaffold.sh to have run
TEST_DIR=$(cat "${TMPDIR:-/tmp}/.workflow-test-dir-$(id -un)" 2>/dev/null || echo "")
if [ -z "$TEST_DIR" ] || [ ! -d "$TEST_DIR" ]; then echo "SKIP: No test directory (run scaffold.sh first)"; exit 0; fi
cd "$TEST_DIR"

ID=$(extract_id "$(bd create --title="Fix typo in README" --type=task --priority=4 2>&1)")
sedi 's/Proejct/Project/' README.md
grep "Project" README.md | head -1
git add README.md
git commit -m "fix: correct typo in README title"
bd close "$ID" --reason="Typo fixed"

echo "=== Trivial Tier: PASS ==="
