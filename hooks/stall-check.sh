#!/usr/bin/env bash
# Detect stall in revision loop by comparing current issue count to previous.
# Usage: stall-check.sh <task-id> <phase> <current-count>
# Phase: spec | quality
# State persisted per (task-id, phase) under $CLAUDE_WORKSTATION_STATE_DIR.
# Exit 0 = not stalled (state updated, continue)
# Exit 1 = stalled (current >= previous)
# Exit 2 = usage error

set -euo pipefail

TASK_ID="${1:-}"
PHASE="${2:-}"
CURRENT="${3:-}"

if [ -z "$TASK_ID" ] || [ -z "$PHASE" ] || [ -z "$CURRENT" ]; then
    echo "Usage: stall-check.sh <task-id> <phase> <current-count>" >&2
    exit 2
fi

case "$CURRENT" in
    ''|*[!0-9]*)
        echo "error: current-count must be a non-negative integer, got: $CURRENT" >&2
        exit 2
        ;;
esac

STATE_DIR="${CLAUDE_WORKSTATION_STATE_DIR:-/tmp/claude-workstation}"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/stall-${TASK_ID}-${PHASE}.count"

PREV=""
if [ -f "$STATE_FILE" ]; then
    PREV=$(cat "$STATE_FILE")
fi

if [ -n "$PREV" ] && [ "$CURRENT" -ge "$PREV" ]; then
    echo "STALLED: phase=$PHASE task=$TASK_ID count=$CURRENT prev=$PREV"
    exit 1
fi

echo "$CURRENT" > "$STATE_FILE"
echo "OK: phase=$PHASE task=$TASK_ID count=$CURRENT prev=${PREV:-infinity}"
exit 0
