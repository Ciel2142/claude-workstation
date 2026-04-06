#!/usr/bin/env bash
set -euo pipefail
if ! command -v bd >/dev/null 2>&1; then
    echo "SKIP: bd not found in PATH"
    exit 0
fi
echo "=== Scaffold: Creating test project ==="

TEST_DIR="/tmp/workflow-test"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/src" "$TEST_DIR/tests"
cd "$TEST_DIR"
git init

cat > src/utils.sh << 'UTILS'
#!/usr/bin/env bash

greet() {
    local name="$1"
    echo "Hello, $name!"
}

add() {
    local a="$1"
    local b="$2"
    echo $(( a + b ))
}
UTILS

cat > tests/run.sh << 'TESTS'
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../src/utils.sh"
PASS=0; FAIL=0
assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"; FAIL=$((FAIL + 1))
    fi
}
echo "Running tests..."
echo ""
assert_eq "greet returns greeting" "Hello, World!" "$(greet "World")"
assert_eq "add returns sum" "5" "$(add 2 3)"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
TESTS

cat > README.md << 'README'
# Workflow Test Proejct

A disposable project for testing the unified development workflow.
README

chmod +x tests/run.sh
bd init 2>/dev/null || true
git add -A
git commit -m "chore: initial scaffold"

bash tests/run.sh
echo "=== Scaffold: DONE ==="
