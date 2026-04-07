#!/usr/bin/env bash
set -euo pipefail
if ! command -v bd >/dev/null 2>&1; then
    echo "SKIP: bd not found in PATH"
    exit 0
fi
echo "=== Scaffold: Creating test project ==="

# F2: Use mktemp for isolated test directories; share path via coordination file
# L2: Coordination file uses a stable path derived from the mktemp parent,
#     with restrictive permissions to prevent tampering on shared systems
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/workflow-test.XXXXXX")
COORD_FILE="${TMPDIR:-/tmp}/.workflow-test-dir-$(id -un)"
echo "$TEST_DIR" > "$COORD_FILE"
chmod 600 "$COORD_FILE"

# F17: Cleanup on abnormal exit (Ctrl-C, kill) so temp dir isn't leaked
trap 'echo "Interrupted — cleaning up $TEST_DIR"; rm -rf "$TEST_DIR"; rm -f "$COORD_FILE"; exit 130' INT TERM
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
