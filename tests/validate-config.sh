#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "=== Claude Workstation Config Validation ==="
echo ""

# --- 1. File existence ---
echo "1. File existence"

[[ -f "$HOME/.claude/rules/common/unified-workflow.md" ]] \
    && pass "unified-workflow.md exists" \
    || fail "unified-workflow.md MISSING (run /claude-workstation:setup)"

[[ -f "$HOME/.claude/rules/common/plugin-routing.md" ]] \
    && pass "plugin-routing.md exists" \
    || fail "plugin-routing.md MISSING"

[[ -f "$HOME/.claude/rules/common/development-workflow.md" ]] \
    && pass "development-workflow.md exists" \
    || fail "development-workflow.md MISSING"

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

# --- 3. Plugin presence ---
echo "3. Plugin presence"

PLUGIN_CHECK=$(python3 -c "
import json
d = json.load(open('$HOME/.claude/settings.json'))
plugins = d.get('enabledPlugins', {})
needed = ['beads@beads-marketplace', 'superpowers@superpowers-marketplace', 'everything-claude-code@everything-claude-code']
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

# --- 4. Hook safety ---
echo "4. Hook command safety"

if bash -c 'bd prime 2>/dev/null || true' >/dev/null 2>&1; then
    pass "bd prime safe (Beads hook)"
else
    fail "bd prime errors even with || true"
fi

if bash -c 'bd list --status=in_progress 2>/dev/null | head -5' >/dev/null 2>&1; then
    pass "Stop hook safe (bd list)"
else
    fail "Stop hook errors"
fi

echo ""

# --- 5. Cross-references ---
echo "5. Cross-references"

if grep -q "unified-workflow.md" "$HOME/.claude/rules/common/plugin-routing.md" 2>/dev/null; then
    pass "plugin-routing.md references unified-workflow.md"
else
    fail "plugin-routing.md does NOT reference unified-workflow.md"
fi

if grep -q "/workflow" "$HOME/.claude/rules/common/plugin-routing.md" 2>/dev/null; then
    pass "plugin-routing.md references /workflow command"
else
    fail "plugin-routing.md does NOT reference /workflow command"
fi

if grep -q "unified-workflow.md" "$HOME/.claude/rules/common/development-workflow.md" 2>/dev/null; then
    pass "development-workflow.md redirects to unified-workflow.md"
else
    fail "development-workflow.md does NOT redirect to unified-workflow.md"
fi

echo ""

# --- 6. No duplicate workflow definitions ---
echo "6. No duplicate workflow definitions"

if grep -qE "(RED.*GREEN.*REFACTOR|Write tests first|Use \*\*planner\*\* agent|superpowers:test-driven)" "$HOME/.claude/rules/common/development-workflow.md" 2>/dev/null; then
    fail "development-workflow.md still contains workflow definitions (should redirect)"
else
    pass "development-workflow.md has no duplicate workflow definitions"
fi

echo ""

# --- 7. Content completeness ---
echo "7. Content completeness (unified-workflow rule)"

for keyword in "Beads-First" "Trivial" "Small" "Medium+" "Escalation"; do
    if grep -q "$keyword" "$HOME/.claude/rules/common/unified-workflow.md" 2>/dev/null; then
        pass "unified-workflow.md contains '$keyword'"
    else
        fail "unified-workflow.md MISSING '$keyword'"
    fi
done

echo ""

# --- 8. Shell aliases ---
echo "8. Shell aliases"

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
