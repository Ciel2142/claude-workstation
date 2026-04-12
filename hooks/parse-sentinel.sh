#!/usr/bin/env bash
# Parse subagent response for the last H2 sentinel marker.
# Reads stdin. Prints the matching H2 line on stdout.
# Exit 0 if a sentinel was found. Exit 1 if none.
# Usage: cat response.txt | parse-sentinel.sh

set -euo pipefail

SENTINELS=(
    "## PLAN COMPLETE"
    "## PLAN READY"
    "## PLAN BLOCKED"
    "## REVIEW PASS"
    "## REVIEW BLOCKED"
    "## VERIFICATION PASSED"
    "## VERIFICATION FAILED"
    "## BUILD FIXED"
    "## BUILD STUCK"
    "## BLOCKED"
)

INPUT=$(cat)

LAST_MATCH=""
while IFS= read -r line; do
    for s in "${SENTINELS[@]}"; do
        if [[ "$line" == "$s" || "$line" == "$s "* ]]; then
            LAST_MATCH="$line"
            break
        fi
    done
done <<< "$INPUT"

if [ -z "$LAST_MATCH" ]; then
    echo "none"
    exit 1
fi

echo "$LAST_MATCH"
exit 0
