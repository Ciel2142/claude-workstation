#!/usr/bin/env bash
# Shared utilities for enforcement hooks.
# Source this file: . "$(dirname "$0")/cache-utils.sh"

# --- Timeout Wrapper ---

if command -v timeout >/dev/null 2>&1; then
    BD_TIMEOUT="timeout 5"
else
    BD_TIMEOUT=""
fi

# --- Beads Guards ---

# Check if beads is usable. Sets GIT_ROOT. Returns 1 if not usable.
check_beads_available() {
    GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    local beads_dir="${GIT_ROOT:+$GIT_ROOT/.beads}"
    if [ -z "$beads_dir" ] || { [ ! -d "$beads_dir" ] && [ ! -d "$HOME/.beads" ]; }; then
        return 1
    fi
    if ! command -v bd >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# --- JSON Field Extraction ---

# Extract a dotted field path from JSON string.
# Usage: json_field "$json_string" "tool_input.file_path"
# Tries python3 for reliability, grep fallback for leaf key.
json_field() {
    local json="$1"
    local path="$2"

    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for k in '${path}'.split('.'):
        d = d.get(k, {}) if isinstance(d, dict) else {}
    print(d if isinstance(d, str) else '')
except:
    print('')" 2>/dev/null || echo ""
    else
        # Grep fallback: extract leaf key value (works for non-nested unique keys)
        local key="${path##*.}"
        printf '%s' "$json" | grep -o "\"${key}\": *\"[^\"]*\"" | head -1 \
            | sed "s/\"${key}\": *\"//;s/\"$//" || echo ""
    fi
}

# --- Active Task ---

# Returns: task ID, empty string (no tasks), or "BD_UNREACHABLE" (server down).
get_active_task() {
    local task_id=""
    local bd_ok=true
    local listing_json=""
    listing_json=$($BD_TIMEOUT bd list --status=in_progress --json 2>/dev/null) || bd_ok=false

    if $bd_ok && [ -n "$listing_json" ] && [ "$listing_json" != "[]" ] && [ "$listing_json" != "null" ]; then
        task_id=$(printf '%s' "$listing_json" | grep -o '"id": *"[^"]*"' | head -1 | cut -d'"' -f4 2>/dev/null || echo "")
    fi

    # Fallback to text parsing
    if $bd_ok && [ -z "$task_id" ]; then
        local listing=""
        listing=$($BD_TIMEOUT bd list --status=in_progress 2>/dev/null) || bd_ok=false
        if $bd_ok; then
            task_id=$(echo "$listing" | grep -v 'No issues' | awk 'NR>1 && NF>0{print $1; exit}' || true)
        fi
    fi

    if ! $bd_ok && [ -z "$task_id" ]; then
        echo "BD_UNREACHABLE"
        return 0
    fi

    echo "${task_id:-}"
}

# --- Milestones ---

# Get [M] milestone lines from beads notes.
# Returns: milestone lines (may be empty), or "BD_UNREACHABLE".
get_milestones() {
    local task_id="$1"
    [ -z "$task_id" ] && return 0

    local bd_ok=true
    local bd_output=""
    bd_output=$($BD_TIMEOUT bd show "$task_id" 2>/dev/null) || bd_ok=false

    if ! $bd_ok; then
        echo "BD_UNREACHABLE"
        return 0
    fi

    # Extract notes section, then grep [M] lines
    local notes
    notes=$(printf '%s\n' "$bd_output" \
        | sed -n '/^NOTES$/,$ p' \
        | sed '1d' \
        | sed '/^\(TITLE\|STATUS\|PRIORITY\|TYPE\|PARENT\|CHILDREN\|BLOCKS\|BLOCKED BY\|DEPENDS ON\|DEPENDENCIES\|LABELS\|ASSIGNEE\|CREATED\|UPDATED\|ACCEPTANCE CRITERIA\|DESIGN\|COMMENTS\|HISTORY\|ATTACHMENTS\|METADATA\|DESCRIPTION\|DUE\|DEFER\)$/,$d')

    local milestones
    milestones=$(printf '%s\n' "$notes" | grep '^\[M\] ' || echo "")

    echo "$milestones"
}

# Determine current phase from milestone lines (most advanced present).
get_current_phase() {
    local milestones="$1"
    local phases="verified review:quality review:spec tdd:refactor tdd:green-verified tdd:green tdd:red-verified tdd:red task:claimed task:created"
    for phase in $phases; do
        if printf '%s' "$milestones" | grep -q "^\[M\] ${phase}"; then
            echo "$phase"
            return 0
        fi
    done
    echo "none"
}

# Recommend next action based on current phase.
get_next_phase() {
    local current="$1"
    case "$current" in
        "none"|"")          echo "create sub-task bead" ;;
        "task:created")     echo "claim the task" ;;
        "task:claimed")     echo "write failing test (TDD red)" ;;
        "tdd:red")          echo "verify test fails" ;;
        "tdd:red-verified") echo "implement to pass test" ;;
        "tdd:green")        echo "verify all tests pass" ;;
        "tdd:green-verified") echo "refactor" ;;
        "tdd:refactor")     echo "run spec review" ;;
        "review:spec")      echo "run quality review" ;;
        "review:quality")   echo "verify before completion" ;;
        "verified")         echo "done — close task" ;;
        *)                  echo "update milestone" ;;
    esac
}
