#!/usr/bin/env bash
# Orchestrator-side spot-check: confirm each must_haves artifact exists
# and has at least 10 lines of content. This is the anti-hallucination
# insurance that runs before trusting a subagent's ## PLAN COMPLETE.
#
# Usage: spot-check-artifacts.sh <plan-path> <anchor>
# Exit 0 = every artifact present and non-trivial
# Exit 1 = at least one artifact missing or too short, or parse error
# Exit 2 = usage error

set -euo pipefail

PLAN="${1:-}"
ANCHOR="${2:-}"

if [ -z "$PLAN" ] || [ -z "$ANCHOR" ]; then
    echo "Usage: spot-check-artifacts.sh <plan-path> <anchor>" >&2
    exit 2
fi

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSE="$HOOKS_DIR/parse-must-haves.sh"

if [ ! -x "$PARSE" ] && [ ! -f "$PARSE" ]; then
    echo "error: parse-must-haves.sh not found at $PARSE" >&2
    exit 1
fi

ARTIFACTS=$(bash "$PARSE" "$PLAN" "$ANCHOR" artifacts) || {
    echo "FAIL: cannot parse artifacts from $PLAN#$ANCHOR" >&2
    exit 1
}

if [ -z "$ARTIFACTS" ]; then
    echo "FAIL: no artifacts declared under $ANCHOR" >&2
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MIN_LINES=10
FAILED=0

while IFS= read -r artifact; do
    [ -z "$artifact" ] && continue
    FULL="$REPO_ROOT/$artifact"
    if [ ! -f "$FULL" ]; then
        echo "FAIL: artifact missing: $artifact" >&2
        FAILED=1
        continue
    fi
    LINES=$(wc -l < "$FULL")
    if [ "$LINES" -lt "$MIN_LINES" ]; then
        echo "FAIL: artifact too short ($LINES < $MIN_LINES lines): $artifact" >&2
        FAILED=1
        continue
    fi
    echo "OK: $artifact ($LINES lines)"
done <<< "$ARTIFACTS"

exit "$FAILED"
