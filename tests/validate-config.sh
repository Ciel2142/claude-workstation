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

[[ -f "$HOME/.claude/rules/common/verification-template.md" ]] \
    && pass "verification-template.md exists" \
    || fail "verification-template.md MISSING (run /claude-workstation:setup)"

[[ -f "$HOME/.claude/rules/common/beads-milestones.md" ]] \
    && pass "beads-milestones.md exists" \
    || fail "beads-milestones.md MISSING (run /claude-workstation:setup)"

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

echo "8. Content completeness (verification template)"

for keyword in "Verification" "BLOCKING" "exit" "bd update"; do
    if grep -q "$keyword" "$HOME/.claude/rules/common/verification-template.md" 2>/dev/null; then
        pass "verification-template.md contains '$keyword'"
    else
        fail "verification-template.md MISSING '$keyword'"
    fi
done

echo ""

# --- 9. Shell aliases ---
echo "9. Shell aliases"

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

# --- 10. Debugging rule ---
echo "10. Debugging rule"

[[ -f "$HOME/.claude/rules/common/debugging.md" ]] \
    && pass "debugging.md exists" \
    || fail "debugging.md MISSING (run /claude-workstation:setup)"

if grep -q "systematic-debugging" "$HOME/.claude/rules/common/debugging.md" 2>/dev/null; then
    pass "debugging.md references systematic-debugging"
else
    fail "debugging.md MISSING systematic-debugging reference"
fi

echo ""

# --- 11. Bug tier in unified workflow ---
echo "11. Bug tier in unified workflow"

if grep -q '^\| \*\*Bug\*\*' "$HOME/.claude/rules/common/unified-workflow.md" 2>/dev/null; then
    pass "unified-workflow.md contains Bug tier"
else
    fail "unified-workflow.md MISSING Bug tier row"
fi

echo ""

# --- 10b. Workflow v2 rules ---
echo "10b. Workflow v2 rules"

[[ -f "$HOME/.claude/rules/common/spike-phase.md" ]] \
    && pass "spike-phase.md exists" \
    || fail "spike-phase.md MISSING (run /claude-workstation:setup)"

[[ -f "$HOME/.claude/rules/common/scope-health.md" ]] \
    && pass "scope-health.md exists" \
    || fail "scope-health.md MISSING (run /claude-workstation:setup)"

echo ""

# --- 11b. Workflow v2 content ---
echo "11b. Workflow v2 content"

if grep -q "Spec Amendments" "$HOME/.claude/rules/common/unified-workflow.md" 2>/dev/null; then
    pass "unified-workflow.md contains Spec Amendments"
else
    fail "unified-workflow.md MISSING Spec Amendments section"
fi

if grep -q "Micro-tiers" "$HOME/.claude/rules/common/unified-workflow.md" 2>/dev/null; then
    pass "unified-workflow.md contains Micro-tiers"
else
    fail "unified-workflow.md MISSING Micro-tiers section"
fi

if grep -q "spike" "$HOME/.claude/rules/common/spike-phase.md" 2>/dev/null; then
    pass "spike-phase.md contains spike content"
else
    fail "spike-phase.md MISSING spike content"
fi

if grep -q "planned-tasks" "$HOME/.claude/rules/common/scope-health.md" 2>/dev/null; then
    pass "scope-health.md contains planned-tasks baseline"
else
    fail "scope-health.md MISSING planned-tasks baseline"
fi

if grep -q "Standardized Format" "$HOME/.claude/rules/common/beads-milestones.md" 2>/dev/null; then
    pass "beads-milestones.md has structured checkpoint format"
else
    fail "beads-milestones.md MISSING structured checkpoint format"
fi

echo ""

# --- 12. Skill directories ---
echo "12. Skill directories"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

for skill_dir in start resume setup test; do
    if [[ -f "$PLUGIN_ROOT/skills/$skill_dir/SKILL.md" ]]; then
        pass "skills/$skill_dir/SKILL.md exists"
    else
        fail "skills/$skill_dir/SKILL.md MISSING"
    fi
done

echo ""

# --- 13. SKILL.md frontmatter ---
echo "13. SKILL.md frontmatter"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

for skill_dir in start resume setup test; do
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
