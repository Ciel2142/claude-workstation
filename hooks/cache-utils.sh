#!/usr/bin/env bash
# Shared cache utilities for enforcement hooks.
# Source this file: . "$(dirname "$0")/cache-utils.sh"
#
# Cache structure (per-project directory):
#   $GATE_CACHE_DIR/active-task          — current sub-task ID
#   $GATE_CACHE_DIR/milestones-<task-id> — cached [M] milestone lines
#   $GATE_CACHE_DIR/edit-counter         — edits since last milestone update

# --- Cache Directory ---

_compute_cache_dir() {
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    local beads_path="${git_root:+$git_root/.beads}"
    beads_path="${beads_path:-$HOME/.beads}"
    local project_hash
    project_hash=$(printf '%s' "$beads_path" | md5sum 2>/dev/null | cut -c1-8 \
        || printf '%s' "$beads_path" | md5 2>/dev/null | cut -c1-8 \
        || echo "default")
    local base_dir="${XDG_RUNTIME_DIR:-/tmp}"
    echo "${base_dir}/.beads-gate-${USER:-$(id -un)}-${project_hash}"
}

GATE_CACHE_DIR=$(_compute_cache_dir)

ensure_cache_dir() {
    if [ -L "$GATE_CACHE_DIR" ]; then
        rm -f "$GATE_CACHE_DIR"
    fi
    # Remove old-format single-file cache if present (migration from pre-change-gate)
    if [ -f "$GATE_CACHE_DIR" ]; then
        rm -f "$GATE_CACHE_DIR"
    fi
    mkdir -p "$GATE_CACHE_DIR"
}

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
    ensure_cache_dir
    local cache_file="$GATE_CACHE_DIR/active-task"

    # Check cache freshness (< 60s)
    if [ -f "$cache_file" ] && [ ! -L "$cache_file" ]; then
        local mod now age
        mod=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        now=$(date +%s)
        age=$(( now - mod ))
        if [ "$age" -ge 0 ] && [ "$age" -lt 60 ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Query bd
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

    # If bd failed completely and no cached fallback, signal unreachable
    if ! $bd_ok && [ -z "$task_id" ]; then
        echo "BD_UNREACHABLE"
        return 0
    fi

    # Write cache atomically
    local tmp="${cache_file}.$$"
    printf '%s' "${task_id:-}" > "$tmp"
    mv -f "$tmp" "$cache_file"
    echo "${task_id:-}"
}

# --- Milestones ---

# Get [M] milestone lines from beads notes. Uses cache if fresh.
# Returns: milestone lines (may be empty), or "BD_UNREACHABLE".
get_milestones() {
    local task_id="$1"
    [ -z "$task_id" ] && return 0
    ensure_cache_dir
    local cache_file="$GATE_CACHE_DIR/milestones-${task_id}"

    # Check cache freshness
    if [ -f "$cache_file" ] && [ ! -L "$cache_file" ]; then
        local mod now age
        mod=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        now=$(date +%s)
        age=$(( now - mod ))
        if [ "$age" -ge 0 ] && [ "$age" -lt 60 ]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Query bd show and extract [M] lines from notes
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

    # Write cache
    local tmp="${cache_file}.$$"
    printf '%s' "$milestones" > "$tmp"
    mv -f "$tmp" "$cache_file"
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

# --- Edit Counter ---

get_edit_count() {
    ensure_cache_dir
    local f="$GATE_CACHE_DIR/edit-counter"
    if [ -f "$f" ]; then cat "$f"; else echo "0"; fi
}

increment_edit_count() {
    ensure_cache_dir
    local f="$GATE_CACHE_DIR/edit-counter"
    local count
    count=$(get_edit_count)
    echo $(( count + 1 )) > "$f"
}

reset_edit_count() {
    ensure_cache_dir
    echo "0" > "$GATE_CACHE_DIR/edit-counter"
}

# --- Cache Management ---

invalidate_task_cache() {
    local task_id="$1"
    [ -n "$task_id" ] && rm -f "$GATE_CACHE_DIR/milestones-${task_id}"
    reset_edit_count
}

clean_cache() {
    rm -rf "$GATE_CACHE_DIR"
}
