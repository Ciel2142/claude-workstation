#!/usr/bin/env bash
# Shared helpers for cross-platform test scenarios.
# Source this at the top of each scenario script:
#   source "$(dirname "$0")/lib.sh"   (from scenarios/)
#   source "$(dirname "$0")/tests/lib.sh"  (from project root)

# Cross-platform sed in-place editing.
# BSD sed (macOS) requires 'sed -i ""' while GNU sed (Linux) uses 'sed -i'.
sedi() {
    if [[ "$OSTYPE" == darwin* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Cross-platform grep -o with Perl-style \K / lookahead replaced by POSIX.
# Extracts beads task IDs from bd create output.
# Usage: extract_id "bd create output string"
extract_id() {
    grep -o 'workflow-test-[[:alnum:]]*' <<< "$1" | head -1
}
