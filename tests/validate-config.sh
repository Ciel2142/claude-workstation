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

[[ -f "$HOME/.claude/rules/context7.md" ]] \
    && pass "context7.md exists" \
    || fail "context7.md MISSING"

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

for skill in debugging-protocol beads-milestones spike-phase scope-health verification-template; do
    [[ -f "$PLUGIN_ROOT/skills/$skill/SKILL.md" ]] \
        && pass "skills/$skill/SKILL.md exists" \
        || fail "skills/$skill/SKILL.md MISSING"
done

echo ""

# --- 4. Workflow context content ---
echo "4. Workflow context content"

for keyword in "Beads-First" "Task Sizing" "Plugin Routing" "Research" "Side Quests" "Spec Amendments" "Micro-tiers" "Skill References"; do
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
if echo "$HOOK_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); ctx=d['hookSpecificOutput']['additionalContext']; assert len(ctx) > 100" 2>/dev/null; then
    pass "session-start hook produces valid JSON with additionalContext"
else
    fail "session-start hook output INVALID"
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

SHELL_RC=""
[[ -f "$HOME/.bashrc" ]] && SHELL_RC="$HOME/.bashrc"
[[ -f "$HOME/.zshrc" ]] && SHELL_RC="${SHELL_RC:-$HOME/.zshrc}"

if [ -n "$SHELL_RC" ]; then
    for alias_name in claude-dev claude-research claude-review; do
        if grep -q "alias $alias_name=" "$SHELL_RC" 2>/dev/null; then
            pass "$alias_name alias in $SHELL_RC"
        else
            fail "$alias_name alias MISSING from $SHELL_RC"
        fi
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
