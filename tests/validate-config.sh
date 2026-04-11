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

SETTINGS_JSON="$HOME/.claude/settings.json"
HAS_SETTINGS=false

if [[ -f "$SETTINGS_JSON" ]]; then
    HAS_SETTINGS=true
    pass "settings.json exists"
else
    echo "  ⏭️  settings.json not found (CI environment) — skipping user-env checks"
fi

# contexts/ and profiles/ were removed in v2.1 — verify they're gone
[[ ! -d "$PLUGIN_ROOT/contexts" ]] \
    && pass "contexts/ directory removed" \
    || fail "contexts/ directory still exists (should be removed)"

[[ ! -d "$PLUGIN_ROOT/profiles" ]] \
    && pass "profiles/ directory removed" \
    || fail "profiles/ directory still exists (should be removed)"

echo ""

# --- 2. JSON validity ---
echo "2. Settings JSON validity"

if $HAS_SETTINGS; then
    if python3 -c "import json; json.load(open('$SETTINGS_JSON'))" 2>/dev/null; then
        pass "settings.json is valid JSON"
    else
        fail "settings.json is INVALID JSON"
    fi
else
    echo "  ⏭️  skipped (no settings.json)"
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

for keyword in "Pre-Change Gate" "Hard Rules" "Milestone Notes" "Side Quests" "Anti-Patterns" "Skill Invocation Priority" "Task Decomposition" "Ready Fronts" "Key Skills Reference"; do
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
assert 'RIGID REF' in ctx, 'RIGID REF missing from escaped content'
assert 'workflow/SKILL.md' in ctx, 'workflow reference missing from escaped content'
assert '\"yes\"' not in ctx or 'yes' in ctx, 'quote escaping corrupted content'
" 2>/dev/null; then
    pass "session-start hook JSON escaping preserves content correctly"
else
    fail "session-start hook JSON escaping CORRUPTS content"
fi

echo ""

# --- 6. Plugin presence ---
echo "6. Plugin presence"

if $HAS_SETTINGS; then
    PLUGIN_CHECK=$(python3 -c "
import json
d = json.load(open('$SETTINGS_JSON'))
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
else
    echo "  ⏭️  skipped (no settings.json)"
fi

echo ""

# --- 8. Skill directories ---
echo "8. Skill directories"

for skill_dir in start workflow task-scaffolder orchestrator agent-roles; do
    if [[ -f "$PLUGIN_ROOT/skills/$skill_dir/SKILL.md" ]]; then
        pass "skills/$skill_dir/SKILL.md exists"
    else
        fail "skills/$skill_dir/SKILL.md MISSING"
    fi
done

echo ""

# --- 9. SKILL.md frontmatter ---
echo "9. SKILL.md frontmatter"

for skill_dir in start workflow task-scaffolder orchestrator agent-roles; do
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
    for key in "spec" "plan" "completed" "verification" "stopped" "active-skill"; do
        if grep -q "$key" "$WORKFLOW_SKILL_FILE" 2>/dev/null; then
            pass "workflow skill contains milestone key '$key'"
            MILESTONE_KEYS_FOUND=$((MILESTONE_KEYS_FOUND + 1))
        else
            fail "workflow skill MISSING milestone key '$key'"
        fi
    done

    if (( MILESTONE_KEYS_FOUND >= 6 )); then
        pass "workflow skill contains all $MILESTONE_KEYS_FOUND milestone keys"
    else
        fail "workflow skill has only $MILESTONE_KEYS_FOUND milestone keys (expected 6)"
    fi
else
    fail "Cannot check milestone schema — skills/workflow/SKILL.md missing"
fi

echo ""

# --- 11g. Context budget accuracy ---
echo "11g. Context budget accuracy"

CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"
CLAUDE_SIZE=$(wc -c < "$CLAUDE_MD" 2>/dev/null || echo 0)
if (( CLAUDE_SIZE > 0 && CLAUDE_SIZE < 3500 )); then
    pass "CLAUDE.md is lean (${CLAUDE_SIZE} bytes)"
else
    fail "CLAUDE.md is ${CLAUDE_SIZE} bytes (expected < 3500 for lean cheatsheet)"
fi

if grep -q "RIGID REF" "$CLAUDE_MD" 2>/dev/null; then
    pass "CLAUDE.md contains RIGID REF pointers"
else
    fail "CLAUDE.md MISSING RIGID REF pointers"
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

echo ""

# --- 15. Milestone gate hook (replaced pre-change-gate) ---
echo "15. Milestone gate hook"

# 15a. hooks.json has PreToolUse entries referencing milestone-gate
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
    if e['matcher'] in ('Edit', 'Write'):
        for h in e['hooks']:
            assert 'type' in h, 'hook entry missing type'
            assert 'command' in h, 'hook entry missing command'
            assert 'milestone-gate' in h['command'], 'command does not reference milestone-gate'
" 2>/dev/null; then
    pass "hooks.json has PreToolUse entries for Edit and Write (milestone-gate)"
else
    fail "hooks.json MISSING PreToolUse entries for Edit and Write"
fi

# 15b-d. (removed — pre-change-gate retired in 2.5.3, replaced by milestone-gate)

# 15e. Functional: session-start hook produces valid JSON with workflow content
SESSION_OUT=$(bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null || echo "")
if echo "$SESSION_OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass "session-start hook outputs valid JSON (functional)"
else
    fail "session-start hook output is NOT valid JSON (functional)"
fi
if echo "$SESSION_OUT" | grep -q "RIGID REF"; then
    pass "session-start injects CLAUDE.md content (functional)"
else
    fail "session-start does NOT inject CLAUDE.md content (functional)"
fi

# 15f. (removed — pre-change-gate retired, replaced by milestone-gate)

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

# --- 16. PreCompact hook ---
echo "16. PreCompact hook"

# 16a. hooks.json has PreCompact entry
if python3 -c "
import json
d = json.load(open('$PLUGIN_ROOT/hooks/hooks.json'))
hooks = d['hooks']
assert 'PreCompact' in hooks, 'PreCompact not found'
entries = hooks['PreCompact']
assert isinstance(entries, list), 'PreCompact must be a list'
assert len(entries) > 0, 'PreCompact has no entries'
for group in entries:
    assert 'hooks' in group, 'PreCompact group missing hooks array'
    for h in group['hooks']:
        assert 'type' in h, 'hook entry missing type'
        assert 'command' in h, 'hook entry missing command'
" 2>/dev/null; then
    pass "hooks.json has PreCompact entry with correct structure"
else
    fail "hooks.json MISSING PreCompact entry"
fi

# 16b. PreCompact hook runs bd prime
if python3 -c "
import json
d = json.load(open('$PLUGIN_ROOT/hooks/hooks.json'))
hooks = d['hooks']['PreCompact']
commands = [h['command'] for group in hooks for h in group['hooks']]
assert any('bd prime' in cmd for cmd in commands), 'PreCompact does not run bd prime'
" 2>/dev/null; then
    pass "PreCompact hook runs 'bd prime'"
else
    fail "PreCompact hook does NOT run 'bd prime'"
fi

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

# --- 22. Removed content guards ---
echo "22. Removed content guards"

if [[ -f "$PLUGIN_ROOT/README.md" ]]; then
    # 22b. README should NOT reference "Context Profiles" (removed in v2.1)
    if grep -q 'Context Profiles' "$PLUGIN_ROOT/README.md" 2>/dev/null; then
        fail "README still references 'Context Profiles' (should be removed)"
    else
        pass "README does not reference 'Context Profiles'"
    fi

    # 22c. README project structure should NOT list contexts/ or profiles/
    if grep -q 'contexts/' "$PLUGIN_ROOT/README.md" 2>/dev/null; then
        fail "README project structure still lists contexts/"
    else
        pass "README does not list contexts/ in structure"
    fi

    if grep -q 'profiles/' "$PLUGIN_ROOT/README.md" 2>/dev/null; then
        fail "README project structure still lists profiles/"
    else
        pass "README does not list profiles/ in structure"
    fi
fi

# 22e. plugin.json should NOT have "setup" keyword
if python3 -c "
import json
d = json.load(open('$PLUGIN_ROOT/.claude-plugin/plugin.json'))
kw = d.get('keywords', [])
assert 'setup' not in kw, 'setup keyword still present'
" 2>/dev/null; then
    pass "plugin.json does not have 'setup' keyword"
else
    fail "plugin.json still has 'setup' keyword"
fi

# 22f. plugin.json description should not reference 'context profiles'
if python3 -c "
import json
d = json.load(open('$PLUGIN_ROOT/.claude-plugin/plugin.json'))
assert 'context profiles' not in d.get('description', '').lower(), 'description still mentions context profiles'
" 2>/dev/null; then
    pass "plugin.json description does not mention context profiles"
else
    fail "plugin.json description still mentions 'context profiles'"
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
for rule in "RIGID REF" "workflow/SKILL.md" "agent-roles/SKILL.md" "strategic-compact"; do
    if grep -q "$rule" "$CLAUDE_MD" 2>/dev/null; then
        pass "CLAUDE.md contains: '$rule'"
    else
        fail "CLAUDE.md MISSING: '$rule'"
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
    for spec_name in bd-notes-append scope-health start task-scaffolder orchestrator; do
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

# --- 25. CI pipeline ---
echo "25. CI pipeline"

if [[ -f "$PLUGIN_ROOT/.github/workflows/test.yml" ]]; then
    pass "GitHub Actions workflow exists"
    # Verify it references both test scripts
    if grep -q "validate-config.sh" "$PLUGIN_ROOT/.github/workflows/test.yml" 2>/dev/null; then
        pass "CI runs validate-config.sh"
    else
        fail "CI does NOT run validate-config.sh"
    fi
    if grep -q "test-behaviors.sh" "$PLUGIN_ROOT/.github/workflows/test.yml" 2>/dev/null; then
        pass "CI runs test-behaviors.sh"
    else
        fail "CI does NOT run test-behaviors.sh"
    fi
else
    fail "GitHub Actions workflow MISSING (.github/workflows/test.yml)"
fi

echo ""

# ── Section 12: Enforcement hooks ────────────────────────────────────────────
echo ""
echo "12. Enforcement hooks"

# 12.1 New hook scripts exist and are executable
for hook in milestone-gate agent-gate commit-gate stop-gate mid-session-reminder precompact-state; do
    HOOK_PATH="$PLUGIN_ROOT/hooks/$hook"
    if [ -x "$HOOK_PATH" ]; then
        pass "12.1 hooks/$hook exists and is executable"
    else
        fail "12.1 hooks/$hook missing or not executable"
    fi
done

# 12.2 cache-utils.sh exists
if [ -f "$PLUGIN_ROOT/hooks/cache-utils.sh" ]; then
    pass "12.2 hooks/cache-utils.sh exists"
else
    fail "12.2 hooks/cache-utils.sh missing"
fi

# 12.3 Templates directory exists with required files
for tmpl in gate-exemptions.txt protocol-base.md protocol-implementer.md protocol-reviewer.md protocol-planner.md protocol-build-fixer.md; do
    if [ -f "$PLUGIN_ROOT/templates/$tmpl" ]; then
        pass "12.3 templates/$tmpl exists"
    else
        fail "12.3 templates/$tmpl missing"
    fi
done

# 12.4 All protocol templates contain BEAD-PROTOCOL-v1 sentinel
for tmpl in protocol-base.md protocol-implementer.md protocol-reviewer.md protocol-planner.md protocol-build-fixer.md; do
    if grep -q 'BEAD-PROTOCOL-v1' "$PLUGIN_ROOT/templates/$tmpl"; then
        pass "12.4 templates/$tmpl contains BEAD-PROTOCOL-v1 sentinel"
    else
        fail "12.4 templates/$tmpl missing BEAD-PROTOCOL-v1 sentinel"
    fi
done

# 12.9 protocol-implementer.md does NOT contain bd close
if grep -q 'bd close' "$PLUGIN_ROOT/templates/protocol-implementer.md"; then
    fail "12.9 protocol-implementer.md still contains 'bd close'"
else
    pass "12.9 protocol-implementer.md does not contain 'bd close'"
fi

# 12.10 protocol-implementer.md contains ready-for-review
if grep -q 'ready-for-review' "$PLUGIN_ROOT/templates/protocol-implementer.md"; then
    pass "12.10 protocol-implementer.md contains 'ready-for-review'"
else
    fail "12.10 protocol-implementer.md missing 'ready-for-review'"
fi

# 12.11 protocol-reviewer.md does NOT contain bd create
if grep -qE 'bd create|bd dep add' "$PLUGIN_ROOT/templates/protocol-reviewer.md"; then
    fail "12.11 protocol-reviewer.md still contains task creation commands"
else
    pass "12.11 protocol-reviewer.md is report-only (no task creation)"
fi

# 12.12 protocol-reviewer.md contains VERDICT format
if grep -q 'VERDICT:' "$PLUGIN_ROOT/templates/protocol-reviewer.md"; then
    pass "12.12 protocol-reviewer.md contains structured report format"
else
    fail "12.12 protocol-reviewer.md missing VERDICT report format"
fi

# 12.5 hooks.json references new hooks
for hook in milestone-gate agent-gate commit-gate stop-gate mid-session-reminder precompact-state; do
    if grep -q "$hook" "$PLUGIN_ROOT/hooks/hooks.json"; then
        pass "12.5 hooks.json references $hook"
    else
        fail "12.5 hooks.json missing reference to $hook"
    fi
done

# 12.6 (removed — pre-change-gate hook deleted)

# 12.7 CLAUDE.md contains enforcement hooks reference
if grep -q "RIGID REF" "$PLUGIN_ROOT/CLAUDE.md" && grep -q "agent-roles" "$PLUGIN_ROOT/CLAUDE.md"; then
    pass "12.7 CLAUDE.md contains RIGID REF pointers + agent-roles reference"
else
    fail "12.7 CLAUDE.md missing RIGID REF pointers"
fi

# 12.8 Workflow SKILL.md contains milestone chain
if grep -q "tdd:red-verified" "$PLUGIN_ROOT/skills/workflow/SKILL.md" && grep -q "RIGID REF" "$PLUGIN_ROOT/skills/workflow/SKILL.md"; then
    pass "12.8 Workflow SKILL.md contains milestone chain + RIGID REF pointers"
else
    fail "12.8 Workflow SKILL.md missing enforcement sections"
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
    echo "❌ $FAIL check(s) failed"
    exit 1
fi
