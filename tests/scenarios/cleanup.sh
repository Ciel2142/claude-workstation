#!/usr/bin/env bash
echo "=== Cleanup: Removing test project ==="
COORD="${TMPDIR:-/tmp}/.workflow-test-dir"
if [ -f "$COORD" ]; then
    TEST_DIR=$(cat "$COORD")
    rm -rf "$TEST_DIR"
    rm -f "$COORD"
    # Verify cleanup succeeded
    if [ -d "$TEST_DIR" ]; then
        echo "  WARNING: Failed to remove $TEST_DIR"
    fi
else
    # Fallback: clean legacy hardcoded path
    rm -rf /tmp/workflow-test
fi
echo "=== Cleanup: DONE ==="
