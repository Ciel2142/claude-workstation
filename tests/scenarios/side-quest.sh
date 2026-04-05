#!/usr/bin/env bash
set -euo pipefail
echo "=== Side Quest: Discover issue mid-work ==="
cd /tmp/workflow-test

MAIN_ID=$(bd create --title="Add subtract function" --type=task --priority=3 2>&1 | grep -oP 'workflow-test-\w+')
bd update "$MAIN_ID" --claim

# Discover unrelated issue
SIDE_ID=$(bd create --title="Found: greet function missing docstring" --type=bug --priority=4 2>&1 | grep -oP 'workflow-test-\w+')
bd dep add "$SIDE_ID" "$MAIN_ID" --type=discovered-from

# Finish main task first
sed -i '/^\[/i \
assert_eq "subtract returns difference" "2" "$(subtract 5 3)"' tests/run.sh

cat >> src/utils.sh << 'FUNC'

subtract() {
    local a="$1"
    local b="$2"
    if ! [[ "$a" =~ ^-?[0-9]+$ ]] || ! [[ "$b" =~ ^-?[0-9]+$ ]]; then
        echo "error: arguments must be integers" >&2
        return 1
    fi
    echo $(( a - b ))
}
FUNC

bash tests/run.sh
git add src/utils.sh tests/run.sh
git commit -m "feat: add subtract function"
bd close "$MAIN_ID"

# Verify side quest in ready front
READY=$(bd ready 2>&1)
if echo "$READY" | grep -q "$SIDE_ID"; then
    echo "  Side quest in ready front: PASS"
else
    echo "  Side quest NOT in ready front: FAIL"; exit 1
fi

echo "=== Side Quest: PASS ==="
