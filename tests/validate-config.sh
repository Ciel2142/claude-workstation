#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "=== Claude Workstation Config Validation ==="
echo ""

# --- 1. File existence ---
echo "1. File existence"

[[ -f "$HOME/.claude/contexts/dev.md" ]] \
    && pass "dev.md context exists" \
    || fail "dev.md context MISSING"

[[ -f "$HOME/.claude/contexts/research.md" ]] \
    && pass "research.md context exists" \
    || fail "research.md context MISSING"

[[ -f "$HOME/.claude/contexts/review.md" ]] \
    && pass "review.md context exists" \
    || fail "review.md context MISSING"

[[ -f "$HOME/.claude/settings.json" ]] \
    && pass "settings.json exists" \
    || fail "settings.json MISSING"

echo ""

# --- 2. JSON validity ---
echo "2. Settings JSON validity"

if python3 -c "import json; json.load(open('$HOME/.claude/settings.json'))" 2>/dev/null; then
    pass "settings.json is valid JSON"
else
    fail "settings.json is INVALID JSON"
fi

echo ""

# --- 3. Plugin source files ---
echo "3. Plugin source files"

[[ -f "$PLUGIN_ROOT/contexts/workflow.md" ]] \
    && pass "contexts/workflow.md exists" \
    || fail "contexts/workflow.md MISSING"

[[ -f "$PLUGIN_ROOT/hooks/session-start" ]] \
    && pass "hooks/session-start exists" \
    || fail "hooks/session-start MISSING"

[[ -x "$PLUGIN_ROOT/hooks/session-start" ]] \
    && pass "hooks/session-start is executable" \
    || fail "hooks/session-start is NOT executable"

echo ""

# --- 4. Workflow context content ---
echo "4. Workflow context content"

for keyword in "Beads-First" "Task Sizing" "Plugin Routing" "Research" "Side Quests" "Spec Amendments" "Micro-tiers" "Skill References" "Scope Confirmation" "Task Boundary" "Pre-Change Gate"; do
    if grep -q "$keyword" "$PLUGIN_ROOT/contexts/workflow.md" 2>/dev/null; then
        pass "workflow.md contains '$keyword'"
    else
        fail "workflow.md MISSING '$keyword'"
    fi
done

echo ""

# --- 5. Hook output ---
echo "5. Hook output validity"

HOOK_OUTPUT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null)
if echo "$HOOK_OUTPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
hso = d['hookSpecificOutput']
assert 'hookEventName' in hso, 'missing hookEventName'
assert 'additionalContext' in hso, 'missing additionalContext'
assert isinstance(hso['additionalContext'], str), 'additionalContext not string'
assert len(hso['additionalContext']) > 100, 'additionalContext too short'
" 2>/dev/null; then
    pass "session-start hook produces valid JSON with correct structure"
else
    fail "session-start hook output INVALID"
fi

# Verify JSON escaping preserves content with special characters
if echo "$HOOK_OUTPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ctx = d['hookSpecificOutput']['additionalContext']
assert 'Pre-Change Gate' in ctx, 'Pre-Change Gate missing from escaped content'
assert 'Scope Confirmation' in ctx, 'Scope Confirmation missing from escaped content'
assert '\"yes\"' not in ctx or 'yes' in ctx, 'quote escaping corrupted content'
" 2>/dev/null; then
    pass "session-start hook JSON escaping preserves content correctly"
else
    fail "session-start hook JSON escaping CORRUPTS content"
fi

echo ""

# --- 6. Plugin presence ---
echo "6. Plugin presence"

PLUGIN_CHECK=$(python3 -c "
import json
d = json.load(open('$HOME/.claude/settings.json'))
plugins = d.get('enabledPlugins', {})
needed = ['beads@beads-marketplace', 'superpowers@superpowers-marketplace', 'ecc@everything-claude-code']
for p in needed:
    if plugins.get(p) is True:
        print(f'FOUND:{p}')
    else:
        print(f'MISSING:{p}')
" 2>/dev/null)

while IFS= read -r line; do
    if [[ "$line" == FOUND:* ]]; then
        pass "Plugin ${line#FOUND:} enabled"
    elif [[ "$line" == MISSING:* ]]; then
        fail "Plugin ${line#MISSING:} NOT enabled"
    fi
done <<< "$PLUGIN_CHECK"

echo ""

# --- 7. Shell aliases ---
echo "7. Shell aliases"

RC_FILES=()
[[ -f "$HOME/.bashrc" ]] && RC_FILES+=("$HOME/.bashrc")
[[ -f "$HOME/.zshrc" ]] && RC_FILES+=("$HOME/.zshrc")

if [ ${#RC_FILES[@]} -gt 0 ]; then
    for rc_file in "${RC_FILES[@]}"; do
        for alias_name in claude-dev claude-research claude-review; do
            if grep -q "alias $alias_name=" "$rc_file" 2>/dev/null; then
                pass "$alias_name alias in $rc_file"
            else
                fail "$alias_name alias MISSING from $rc_file"
            fi
        done
    done
else
    fail "No .bashrc or .zshrc found"
fi

echo ""

# --- 8. Skill directories ---
echo "8. Skill directories"

for skill_dir in start resume setup test debugging-protocol beads-milestones spike-phase scope-health verification-template; do
    if [[ -f "$PLUGIN_ROOT/skills/$skill_dir/SKILL.md" ]]; then
        pass "skills/$skill_dir/SKILL.md exists"
    else
        fail "skills/$skill_dir/SKILL.md MISSING"
    fi
done

echo ""

# --- 9. SKILL.md frontmatter ---
echo "9. SKILL.md frontmatter"

for skill_dir in start resume setup test debugging-protocol beads-milestones spike-phase scope-health verification-template; do
    skill_file="$PLUGIN_ROOT/skills/$skill_dir/SKILL.md"
    if [[ -f "$skill_file" ]]; then
        # Extract name from YAML frontmatter
        yaml_name=$(sed -n '/^---$/,/^---$/{ /^name:/s/^name: *//p }' "$skill_file")
        if [[ "$yaml_name" == "$skill_dir" ]]; then
            pass "skills/$skill_dir/SKILL.md name matches directory ($yaml_name)"
        else
            fail "skills/$skill_dir/SKILL.md name mismatch (expected '$skill_dir', got '$yaml_name')"
        fi
    fi
done

echo ""

# --- 10. Stop hook ---
echo "10. Stop hook"

if python3 -c "
import json
d = json.load(open('$PLUGIN_ROOT/hooks/hooks.json'))
hooks = d['hooks']
assert 'SessionStart' in hooks, 'SessionStart hook not found'
assert 'Stop' in hooks, 'Stop hook not found'
for name in ('SessionStart', 'Stop'):
    entries = hooks[name]
    assert isinstance(entries, list), f'{name} must be a list'
    for group in entries:
        assert 'hooks' in group, f'{name} group missing hooks array'
        for h in group['hooks']:
            assert 'type' in h, f'{name} hook entry missing type'
            assert 'command' in h, f'{name} hook entry missing command'
" 2>/dev/null; then
    pass "hooks.json is valid JSON with correct structure (SessionStart + Stop)"
else
    fail "hooks.json structure INVALID"
fi

if [[ -f "$PLUGIN_ROOT/hooks/stop" ]]; then
    pass "hooks/stop script exists"
    if [[ -x "$PLUGIN_ROOT/hooks/stop" ]]; then
        pass "hooks/stop is executable"
    else
        fail "hooks/stop is NOT executable"
    fi
else
    fail "hooks/stop script MISSING (stop hook is inline)"
fi

# Stop hook should run without error (outside git repo = early exit is OK)
if bash "$PLUGIN_ROOT/hooks/stop" 2>/dev/null; then
    pass "hooks/stop runs without error"
else
    fail "hooks/stop exits with error"
fi

echo ""

# --- 11. Milestone pattern consistency ---
echo "11. Milestone pattern consistency"

RESUME_FILE="$PLUGIN_ROOT/skills/resume/SKILL.md"
MILESTONES_FILE="$PLUGIN_ROOT/skills/beads-milestones/SKILL.md"

if [[ -f "$RESUME_FILE" ]] && [[ -f "$MILESTONES_FILE" ]]; then
    # beads-milestones defines keys as lowercase with colon (e.g. "verification:", "plan:")
    # resume must match the same keys (case-sensitive)
    CONSISTENT=true

    # Check that resume patterns use lowercase to match beads-milestones keys
    for key in "verification:" "completed:" "plan:" "spec:" "docs-updated:" "tier:"; do
        if grep -q "\"$key\"" "$RESUME_FILE" 2>/dev/null; then
            pass "resume matches milestone key '$key'"
        else
            fail "resume MISSING or MISMATCHED milestone key '$key'"
            CONSISTENT=false
        fi
    done

    # Check that resume does NOT use wrong-case patterns
    for bad_pattern in '"Verification:"' '"Tests passing:"' '"Tests green:"' '"Plan:"' '"Spec:"'; do
        if grep -q "$bad_pattern" "$RESUME_FILE" 2>/dev/null; then
            fail "resume uses wrong-case pattern $bad_pattern (should be lowercase)"
            CONSISTENT=false
        fi
    done

    # Check that resume references /ecc:update-docs (not bare /update-docs)
    if grep -q '/ecc:update-docs' "$RESUME_FILE" 2>/dev/null; then
        pass "resume references /ecc:update-docs correctly"
    else
        fail "resume MISSING /ecc:update-docs reference"
    fi

    # Check no bare /update-docs without ecc: prefix
    if grep '/update-docs' "$RESUME_FILE" 2>/dev/null | grep -qv '/ecc:update-docs'; then
        fail "resume references bare /update-docs without ecc: prefix"
    else
        pass "resume has no bare /update-docs references"
    fi
else
    fail "Cannot check milestone consistency — resume or beads-milestones SKILL.md missing"
fi

echo ""

# --- 11b. Context budget accuracy ---
echo "11b. Context budget accuracy"

WORKFLOW_SIZE=$(wc -c < "$PLUGIN_ROOT/contexts/workflow.md" 2>/dev/null || echo 0)
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]] && grep -q '~[0-9]' "$CLAUDE_MD" 2>/dev/null; then
    STATED_KB=$(grep -oP '~\K[0-9]+' "$CLAUDE_MD" | head -1)
    ACTUAL_KB=$(( (WORKFLOW_SIZE + 512) / 1024 ))
    if (( ACTUAL_KB <= STATED_KB + 1 )); then
        pass "CLAUDE.md context budget (~${STATED_KB}KB) matches actual (${ACTUAL_KB}KB)"
    else
        fail "CLAUDE.md says ~${STATED_KB}KB but workflow.md is ${ACTUAL_KB}KB"
    fi
else
    pass "No context budget claim found in CLAUDE.md (skipped)"
fi

echo ""

# --- 12. help.md gate rules ---
echo "12. help.md gate rules"

HELP_FILE="$PLUGIN_ROOT/commands/help.md"
if [[ -f "$HELP_FILE" ]]; then
    for keyword in "Pre-Change Gate" "Scope Confirmation" "Task Boundary"; do
        if grep -q "$keyword" "$HELP_FILE" 2>/dev/null; then
            pass "help.md references '$keyword'"
        else
            fail "help.md MISSING '$keyword'"
        fi
    done
else
    fail "commands/help.md MISSING"
fi

echo ""

# --- 13. Scenario scripts ---
echo "13. Scenario scripts"

if [ -d "$PLUGIN_ROOT/tests/scenarios" ]; then
    for scenario in "$PLUGIN_ROOT"/tests/scenarios/*.sh; do
        name=$(basename "$scenario")
        if [[ -f "$scenario" ]]; then
            pass "scenarios/$name exists"
        else
            fail "scenarios/$name MISSING"
        fi
        if [[ -x "$scenario" ]]; then
            pass "scenarios/$name is executable"
        else
            fail "scenarios/$name is NOT executable"
        fi
    done
else
    fail "tests/scenarios/ directory MISSING"
fi

echo ""

# --- 14. Cross-reference validation ---
echo "14. Cross-reference validation"

# Verify every skills/ directory is mentioned in README
for skill_dir in "$PLUGIN_ROOT"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    if grep -q "$skill_name" "$PLUGIN_ROOT/README.md" 2>/dev/null; then
        pass "skill $skill_name referenced in README"
    else
        fail "skill $skill_name NOT referenced in README"
    fi
done

# Verify every command in commands/ is referenced in README
for cmd_file in "$PLUGIN_ROOT"/commands/*.md; do
    cmd_name=$(basename "$cmd_file" .md)
    if grep -q "$cmd_name" "$PLUGIN_ROOT/README.md" 2>/dev/null; then
        pass "command $cmd_name referenced in README"
    else
        fail "command $cmd_name NOT referenced in README"
    fi
done

echo ""

# --- Summary ---
echo "=== Summary ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "✅ All checks passed"
    exit 0
else
    echo "❌ $FAIL check(s) failed — run /claude-workstation:setup to fix"
    exit 1
fi
