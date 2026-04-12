#!/usr/bin/env bash
# Parse a must_haves YAML fence from a plan markdown file at a given anchor.
# Usage: parse-must-haves.sh <plan-path> <anchor> <field>
#   <anchor>: "epic" -> top-level "## must_haves"
#             "task-N" -> "### Task N:" heading
#   <field>:  truths | artifacts | key_links
# Prints extracted list entries one per line on stdout.
# Exit 0 = success, 1 = parse error or not found, 2 = usage.

set -euo pipefail

PLAN="${1:-}"
ANCHOR="${2:-}"
FIELD="${3:-}"

if [ -z "$PLAN" ] || [ -z "$ANCHOR" ] || [ -z "$FIELD" ]; then
    echo "Usage: parse-must-haves.sh <plan-path> <anchor> <field>" >&2
    exit 2
fi

case "$FIELD" in
    truths|artifacts|key_links) ;;
    *) echo "error: field must be truths|artifacts|key_links" >&2; exit 2 ;;
esac

if [ ! -f "$PLAN" ]; then
    echo "error: plan file not found: $PLAN" >&2
    exit 1
fi

# Resolve anchor -> heading regex
if [ "$ANCHOR" = "epic" ]; then
    HEADING='^## must_haves[[:space:]]*$'
elif [[ "$ANCHOR" == task-* ]]; then
    N="${ANCHOR#task-}"
    case "$N" in
        ''|*[!0-9]*) echo "error: task anchor must be task-<integer>" >&2; exit 2 ;;
    esac
    HEADING="^### Task ${N}:"
else
    echo "error: anchor must be 'epic' or 'task-<N>'" >&2
    exit 2
fi

# Extract the section: from heading line until next heading of same-or-higher level.
SECTION=$(awk -v re="$HEADING" -v is_epic="$([ "$ANCHOR" = epic ] && echo 1 || echo 0)" '
    BEGIN { in_section = 0 }
    $0 ~ re && !in_section { in_section = 1; next }
    in_section && is_epic == 1 && /^## / { exit }
    in_section && is_epic == 0 && /^### / { exit }
    in_section && is_epic == 0 && /^## / { exit }
    in_section { print }
' "$PLAN")

if [ -z "$SECTION" ]; then
    echo "error: anchor not found: $ANCHOR" >&2
    exit 1
fi

# Extract the first yaml fence inside the section.
YAML=$(echo "$SECTION" | awk '
    /^```yaml[[:space:]]*$/ { in_yaml = 1; next }
    /^```[[:space:]]*$/ && in_yaml { exit }
    in_yaml { print }
')

if [ -z "$YAML" ]; then
    echo "error: no yaml fence found under anchor: $ANCHOR" >&2
    exit 1
fi

# Pull the field's list entries. Handles both top-level and nested fields.
echo "$YAML" | awk -v field="$FIELD" '
    BEGIN { in_field = 0; field_indent = -1 }
    {
        if (match($0, "^([[:space:]]*)" field ":[[:space:]]*$", arr)) {
            in_field = 1
            field_indent = length(arr[1])
            next
        }
        if (in_field) {
            # A new key at same or lesser indent ends the field
            if (match($0, "^([[:space:]]*)[a-z_]+:", arr2)) {
                cur_indent = length(arr2[1])
                if (cur_indent <= field_indent) {
                    in_field = 0
                    next
                }
            }
            if (match($0, "^[[:space:]]*-[[:space:]]*")) {
                item = substr($0, RSTART + RLENGTH)
                print item
            }
        }
    }
'
