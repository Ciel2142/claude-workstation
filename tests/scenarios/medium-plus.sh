#!/usr/bin/env bash
set -euo pipefail
echo "=== Medium+ Tier: Calculator operations ==="
cd /tmp/workflow-test

# Epic
EPIC=$(bd create --title="Add calculator operations" --type=epic --priority=2 2>&1 | grep -oP 'workflow-test-\w+')

# Sub-tasks
S1=$(bd create --title="Step 1: Add multiply" --type=task 2>&1 | grep -oP 'workflow-test-\w+')
S2=$(bd create --title="Step 2: Add divide" --type=task 2>&1 | grep -oP 'workflow-test-\w+')
S3=$(bd create --title="Step 3: Add calculator dispatcher" --type=task 2>&1 | grep -oP 'workflow-test-\w+')

bd dep add "$S1" "$EPIC" --type=parent-child
bd dep add "$S2" "$EPIC" --type=parent-child
bd dep add "$S3" "$EPIC" --type=parent-child
bd dep add "$S3" "$S1"
bd dep add "$S3" "$S2"

# Step 1: Multiply
bd update "$S1" --claim

sed -i '/^\[/i \
assert_eq "multiply returns product" "12" "$(multiply 3 4)"\
assert_eq "multiply handles negatives" "-6" "$(multiply -2 3)"' tests/run.sh

cat >> src/utils.sh << 'FUNC'

multiply() {
    local a="$1"
    local b="$2"
    if ! [[ "$a" =~ ^-?[0-9]+$ ]] || ! [[ "$b" =~ ^-?[0-9]+$ ]]; then
        echo "error: arguments must be integers" >&2
        return 1
    fi
    echo $(( a * b ))
}
FUNC

bash tests/run.sh
git add src/utils.sh tests/run.sh
git commit -m "feat: add multiply function"
bd close "$S1"

# Step 2: Divide
bd update "$S2" --claim

sed -i '/^\[/i \
assert_eq "divide returns quotient" "3" "$(divide 9 3)"\
assert_eq "divide rejects zero" "error" "$(divide 5 0 2>/dev/null || echo "error")"' tests/run.sh

cat >> src/utils.sh << 'FUNC'

divide() {
    local a="$1"
    local b="$2"
    if ! [[ "$a" =~ ^-?[0-9]+$ ]] || ! [[ "$b" =~ ^-?[0-9]+$ ]]; then
        echo "error: arguments must be integers" >&2
        return 1
    fi
    if [[ "$b" -eq 0 ]]; then
        echo "error: division by zero" >&2
        return 1
    fi
    echo $(( a / b ))
}
FUNC

bash tests/run.sh
git add src/utils.sh tests/run.sh
git commit -m "feat: add divide function"
bd close "$S2"

# Verify S3 unblocked
READY=$(bd ready 2>&1)
if echo "$READY" | grep -q "$S3"; then
    echo "  Step 3 unblocked: PASS"
else
    echo "  Step 3 NOT unblocked: FAIL"; exit 1
fi

# Step 3: Calculator dispatcher
bd update "$S3" --claim

sed -i '/^\[/i \
assert_eq "calc add" "5" "$(calculator add 2 3)"\
assert_eq "calc multiply" "12" "$(calculator multiply 3 4)"\
assert_eq "calc divide" "3" "$(calculator divide 9 3)"\
assert_eq "calc unknown op" "error" "$(calculator modulo 5 3 2>/dev/null || echo "error")"' tests/run.sh

cat >> src/utils.sh << 'FUNC'

calculator() {
    local op="$1"
    local a="$2"
    local b="$3"
    case "$op" in
        add)      add "$a" "$b" ;;
        multiply) multiply "$a" "$b" ;;
        divide)   divide "$a" "$b" ;;
        *)
            echo "error: unknown operation '$op'" >&2
            return 1
            ;;
    esac
}
FUNC

bash tests/run.sh
git add src/utils.sh tests/run.sh
git commit -m "feat: add calculator dispatcher"
bd close "$S3"
bd close "$EPIC" --reason="All calculator operations implemented"

echo "=== Medium+ Tier: PASS ==="
