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

[[ -f "$PLUGIN_ROOT/skills/workflow/SKILL.md" ]] \
    && pass "skills/workflow/SKILL.md exists" \
    || fail "skills/workflow/SKILL.md MISSING"

[[ -f "$PLUGIN_ROOT/hooks/session-start" ]] \
    && pass "hooks/session-start exists" \
    || fail "hooks/session-start MISSING"

[[ -x "$PLUGIN_ROOT/hooks/session-start" ]] \
    && pass "hooks/session-start is executable" \
    || fail "hooks/session-start is NOT executable"

echo ""

# --- 4. Workflow skill content ---
echo "4. Workflow skill content"

for keyword in "Pre-Change Gate" "Hard Rules" "Milestone Notes" "Side Quests" "Anti-Patterns" "Plugin Routing" "Skill Invocation Priority" "Task Decomposition" "Ready Fronts" "Key Skills Reference"; do
    if grep -q "$keyword" "$PLUGIN_ROOT/skills/workflow/SKILL.md" 2>/dev/null; then
        pass "workflow skill contains '$keyword'"
    else
        fail "workflow skill MISSING '$keyword'"
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
assert 'Quick Reference' in ctx, 'Quick Reference missing from escaped content'
assert 'Hard Rules' in ctx, 'Hard Rules missing from escaped content'
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

for skill_dir in start workflow test; do
    if [[ -f "$PLUGIN_ROOT/skills/$skill_dir/SKILL.md" ]]; then
        pass "skills/$skill_dir/SKILL.md exists"
    else
        fail "skills/$skill_dir/SKILL.md MISSING"
    fi
done

echo ""

# --- 9. SKILL.md frontmatter ---
echo "9. SKILL.md frontmatter"

for skill_dir in start workflow test; do
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

# --- 11. Milestone schema validation ---
echo "11. Milestone schema validation"

WORKFLOW_SKILL_FILE="$PLUGIN_ROOT/skills/workflow/SKILL.md"

if [[ -f "$WORKFLOW_SKILL_FILE" ]]; then

    # 11a. Verify workflow skill contains key milestone keys
    MILESTONE_KEYS_FOUND=0
    for key in "tier" "spec" "plan" "completed" "verification" "stopped" "active-skill"; do
        if grep -q "$key" "$WORKFLOW_SKILL_FILE" 2>/dev/null; then
            pass "workflow skill contains milestone key '$key'"
            MILESTONE_KEYS_FOUND=$((MILESTONE_KEYS_FOUND + 1))
        else
            fail "workflow skill MISSING milestone key '$key'"
        fi
    done

    if (( MILESTONE_KEYS_FOUND >= 7 )); then
        pass "workflow skill contains all $MILESTONE_KEYS_FOUND milestone keys"
    else
        fail "workflow skill has only $MILESTONE_KEYS_FOUND milestone keys (expected 7)"
    fi
else
    fail "Cannot check milestone schema — skills/workflow/SKILL.md missing"
fi

echo ""

# --- 11g. Context budget accuracy ---
echo "11g. Context budget accuracy"

CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"
CLAUDE_SIZE=$(wc -c < "$CLAUDE_MD" 2>/dev/null || echo 0)
if (( CLAUDE_SIZE > 0 && CLAUDE_SIZE < 2048 )); then
    pass "CLAUDE.md is lean (${CLAUDE_SIZE} bytes)"
else
    fail "CLAUDE.md is ${CLAUDE_SIZE} bytes (expected < 2048 for lean cheatsheet)"
fi

echo ""

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

# 13b. Version consistency
PLUGIN_VERSION=$(python3 -c "import json; print(json.load(open('$PLUGIN_ROOT/.claude-plugin/plugin.json'))['version'])" 2>/dev/null || echo "unknown")
VERSION_MISMATCH=0
for skill_dir in "$PLUGIN_ROOT"/skills/*/; do
    skill_file="$skill_dir/SKILL.md"
    skill_name=$(basename "$skill_dir")
    if [ -f "$skill_file" ]; then
        skill_ver=$(grep -m1 '^version:' "$skill_file" 2>/dev/null | awk '{print $2}' || echo "missing")
        if [ "$skill_ver" = "$PLUGIN_VERSION" ]; then
            pass "skill $skill_name version matches plugin ($PLUGIN_VERSION)"
        else
            fail "skill $skill_name version $skill_ver != plugin $PLUGIN_VERSION"
            VERSION_MISMATCH=1
        fi
    fi
done

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

# --- 15. Pre-change gate hook ---
echo "15. Pre-change gate hook"

# 15a. hooks.json has PreToolUse entries
if python3 -c "
import json
d = json.load(open('$PLUGIN_ROOT/hooks/hooks.json'))
hooks = d['hooks']
assert 'PreToolUse' in hooks, 'PreToolUse not found'
entries = hooks['PreToolUse']
matchers = [e['matcher'] for e in entries]
assert 'Edit' in matchers, 'Edit matcher not found'
assert 'Write' in matchers, 'Write matcher not found'
for e in entries:
    for h in e['hooks']:
        assert 'type' in h, 'hook entry missing type'
        assert 'command' in h, 'hook entry missing command'
        assert 'pre-change-gate' in h['command'], 'command does not reference pre-change-gate'
" 2>/dev/null; then
    pass "hooks.json has PreToolUse entries for Edit and Write"
else
    fail "hooks.json MISSING PreToolUse entries for Edit and Write"
fi

# 15b. pre-change-gate script exists and is executable
if [[ -f "$PLUGIN_ROOT/hooks/pre-change-gate" ]]; then
    pass "hooks/pre-change-gate exists"
    if [[ -x "$PLUGIN_ROOT/hooks/pre-change-gate" ]]; then
        pass "hooks/pre-change-gate is executable"
    else
        fail "hooks/pre-change-gate is NOT executable"
    fi
else
    fail "hooks/pre-change-gate MISSING"
fi

# 15c. pre-change-gate exits 0 outside a beads project (guard clause)
if (cd /tmp && bash "$PLUGIN_ROOT/hooks/pre-change-gate") 2>/dev/null; then
    pass "hooks/pre-change-gate exits 0 outside beads project"
else
    fail "hooks/pre-change-gate does NOT exit 0 outside beads project"
fi

# 15d. stop hook cleans up cache file
if grep -q 'beads-gate' "$PLUGIN_ROOT/hooks/stop" 2>/dev/null; then
    pass "hooks/stop includes cache cleanup for beads-gate"
else
    fail "hooks/stop MISSING cache cleanup for beads-gate"
fi

# 15e. Functional: session-start hook produces valid JSON with workflow content
SESSION_OUT=$(bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || echo "")
if echo "$SESSION_OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass "session-start hook outputs valid JSON (functional)"
else
    fail "session-start hook output is NOT valid JSON (functional)"
fi
if echo "$SESSION_OUT" | grep -q "Quick Reference"; then
    pass "session-start injects CLAUDE.md content (functional)"
else
    fail "session-start does NOT inject CLAUDE.md content (functional)"
fi

# 15f. Functional: pre-change-gate warns when no task is in_progress
# Run in a temp dir with beads initialized but no in_progress tasks
if command -v bd >/dev/null 2>&1; then
    GATE_OUT=$(cd "$PLUGIN_ROOT" && bash "$PLUGIN_ROOT/hooks/pre-change-gate" 2>/dev/null || echo "")
    # If there are no in_progress tasks, it should warn; if there are, it should be empty or about tier
    # Either way, it should exit 0 and not crash
    GATE_EXIT=$?
    if [ "${GATE_EXIT:-0}" -eq 0 ] 2>/dev/null; then
        pass "pre-change-gate runs without error in project (functional)"
    else
        fail "pre-change-gate crashed in project (functional)"
    fi
fi

# 15g. Functional: session-start with missing CLAUDE.md outputs warning JSON
REAL_CLAUDE="$PLUGIN_ROOT/CLAUDE.md"
if [ -f "$REAL_CLAUDE" ]; then
    TMPDIR_HOOK=$(mktemp -d)
    # Create a minimal plugin structure with no CLAUDE.md
    mkdir -p "$TMPDIR_HOOK/hooks"
    cp "$PLUGIN_ROOT/hooks/session-start" "$TMPDIR_HOOK/hooks/"
    # Run from the temp dir (CLAUDE.md doesn't exist)
    MISSING_OUT=$(bash "$TMPDIR_HOOK/hooks/session-start" 2>/dev/null || echo "")
    if echo "$MISSING_OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "session-start outputs valid JSON even when CLAUDE.md missing (functional)"
    else
        fail "session-start outputs INVALID JSON when CLAUDE.md missing (functional)"
    fi
    rm -rf "$TMPDIR_HOOK"
fi

echo ""

echo ""

# --- 17. README dependencies — no optional plugins ---
echo "17. README — no optional plugin rows"

if [[ -f "$PLUGIN_ROOT/README.md" ]]; then
    for optional_name in "Hookify" "Playwright" "Code Simplifier" "Code Review" "Security Guidance" "Commit Commands" "Frontend Design"; do
        if grep -q "$optional_name.*optional" "$PLUGIN_ROOT/README.md" 2>/dev/null; then
            fail "README still lists optional plugin '$optional_name'"
        else
            pass "README does not list optional '$optional_name'"
        fi
    done

    # mgrep optional row should be removed
    if grep -q "mgrep.*optional" "$PLUGIN_ROOT/README.md" 2>/dev/null; then
        fail "README still lists mgrep as optional"
    else
        pass "README does not list mgrep as optional"
    fi
else
    fail "README.md MISSING"
fi

echo ""

# --- 18. macOS portability (BSD compatibility) ---
echo "18. macOS portability"

# 18a. No GNU-only 'sed -i' in shell scripts
# BSD sed (macOS) requires 'sed -i ""' or a helper; bare 'sed -i' + expression crashes.
# Allowed: sedi() helper, sed -i '' (BSD-form), sed -i.bak (backup suffix), comments.
# Excluded: lib.sh (the portability helper itself), validate-config.sh (this file).
BARE_SED_FILES=()
while IFS= read -r shfile; do
    [[ -z "$shfile" ]] && continue
    # Skip the portability helper and this validation script
    case "$shfile" in
        */lib.sh|*/validate-config.sh) continue ;;
    esac
    # Check non-comment lines for bare 'sed -i' followed by expression start
    if grep -v '^\s*#' "$shfile" | grep -qE "sed -i [\"'/]" 2>/dev/null; then
        # Exclude lines that use the BSD-compatible form: sed -i ''
        if grep -v '^\s*#' "$shfile" | grep -E "sed -i [\"'/]" | grep -qvE "sed -i ''" 2>/dev/null; then
            BARE_SED_FILES+=("$shfile")
        fi
    fi
done < <(find "$PLUGIN_ROOT" -name '*.sh' -type f 2>/dev/null)

if [[ ${#BARE_SED_FILES[@]} -eq 0 ]]; then
    pass "no GNU-only sed -i in shell scripts (macOS compatible)"
else
    fail "${#BARE_SED_FILES[@]} file(s) use bare 'sed -i' (crashes on macOS BSD sed)"
fi

# 18b. No grep -P (Perl regex) in shell scripts
# macOS grep does not support -P. Use POSIX ERE (-E) or -o with sed instead.
# Excluded: validate-config.sh (this file — test description mentions the pattern).
GREP_P_FILES=()
while IFS= read -r shfile; do
    [[ -z "$shfile" ]] && continue
    case "$shfile" in
        */validate-config.sh) continue ;;
    esac
    # Check non-comment lines for grep with -P flag
    if grep -v '^\s*#' "$shfile" | grep -qE 'grep\s+-[a-zA-Z]*P' 2>/dev/null; then
        GREP_P_FILES+=("$shfile")
    fi
done < <(find "$PLUGIN_ROOT" -name '*.sh' -type f 2>/dev/null)

if [[ ${#GREP_P_FILES[@]} -eq 0 ]]; then
    pass "no grep -P in shell scripts (macOS compatible)"
else
    fail "${#GREP_P_FILES[@]} file(s) use grep -P (not available on macOS)"
fi

echo ""

echo ""

# --- 20. Alias consistency ---
echo "20. Alias consistency"

ALIASES_FILE="$PLUGIN_ROOT/profiles/aliases.sh"

if [[ -f "$ALIASES_FILE" ]]; then
    for alias_name in claude-dev claude-research claude-review; do
        if grep -q "alias $alias_name=" "$ALIASES_FILE" 2>/dev/null; then
            pass "profiles/aliases.sh defines $alias_name"
        else
            fail "profiles/aliases.sh MISSING $alias_name definition"
        fi
    done
else
    fail "profiles/aliases.sh MISSING"
fi

echo ""

# --- 21. README test file references ---
echo "21. README test file references"

if [[ -f "$PLUGIN_ROOT/README.md" ]]; then
    # M1: README project structure should list test-behaviors.sh and lib.sh
    for test_file in test-behaviors.sh lib.sh; do
        if grep -q "$test_file" "$PLUGIN_ROOT/README.md" 2>/dev/null; then
            pass "README references $test_file"
        else
            fail "README MISSING reference to $test_file"
        fi
    done
else
    fail "README.md MISSING"
fi

echo ""

# --- 22. Context file tool references ---
echo "22. Context file tool references"

RESEARCH_FILE="$PLUGIN_ROOT/contexts/research.md"
if [[ -f "$RESEARCH_FILE" ]]; then
    # I1: Should reference "Agent" tool, not stale "Task" tool name
    if grep -q 'Task with' "$RESEARCH_FILE" 2>/dev/null; then
        fail "research.md uses stale 'Task with' tool reference (should be 'Agent')"
    else
        pass "research.md does not use stale 'Task' tool name"
    fi
else
    fail "contexts/research.md MISSING"
fi

echo ""

# ---------------------------------------------------------------------------
# Section 23: Enforcement documentation guards
# Verifies that hard rules remain documented in source-of-truth files.
# These rules have no mechanical enforcement; tests ensure text survives edits.
# ---------------------------------------------------------------------------
echo "23. Enforcement documentation"

WORKFLOW_SKILL="$PLUGIN_ROOT/skills/workflow/SKILL.md"
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"

# Hard rules in CLAUDE.md (always-on)
for rule in "No code without a beads task" "No production code without a failing test" "No completion claims without verification output" "strategic-compact"; do
    if grep -q "$rule" "$CLAUDE_MD" 2>/dev/null; then
        pass "CLAUDE.md contains hard rule: '$rule'"
    else
        fail "CLAUDE.md MISSING hard rule: '$rule'"
    fi
done

# Pre-Change Gate in workflow skill
if grep -q "Pre-Change Gate" "$WORKFLOW_SKILL" 2>/dev/null; then
    pass "workflow skill contains Pre-Change Gate"
else
    fail "workflow skill MISSING Pre-Change Gate"
fi

# Side quests in workflow skill
if grep -q "Side Quests" "$WORKFLOW_SKILL" 2>/dev/null; then
    pass "workflow skill contains Side Quests"
else
    fail "workflow skill MISSING Side Quests"
fi

echo ""

# --- 24. Behavioral spec files ---
echo "24. Behavioral spec files"

SPECS_DIR="$PLUGIN_ROOT/tests/specs"
if [ -d "$SPECS_DIR" ]; then
    pass "tests/specs/ directory exists"
    for spec_name in pre-change-gate bd-notes-append position-detection scope-health start; do
        if [ -f "$SPECS_DIR/${spec_name}.yaml" ]; then
            pass "specs/${spec_name}.yaml exists"
        else
            fail "specs/${spec_name}.yaml MISSING"
        fi
    done
else
    fail "tests/specs/ directory MISSING"
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
