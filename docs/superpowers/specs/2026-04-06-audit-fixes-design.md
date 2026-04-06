# Design: Fix 14 Plugin Audit Findings

**Date:** 2026-04-06
**Epic:** claude-workstation-n71
**Tier:** Medium+
**Approach:** Batch by file (4 batches, parallel execution)

## Context

A comprehensive plugin audit on 2026-04-06 (commit `ae8d21c`) found 14 issues across hooks, tests, README, and .gitignore. Three HIGH, six MEDIUM, five LOW. No cross-reference bugs — all skill references are valid.

## Batch 1: Hooks (5 findings)

### hooks/stop — H3, M3, L1

**H3: Silent failure when `bd` unavailable**

Add explicit `command -v bd` check before calling `bd list`. If `bd` is not in PATH, print a diagnostic warning instead of silently skipping the reminder.

```bash
if command -v bd >/dev/null 2>&1; then
    IN_PROGRESS=$(bd list --status=in_progress 2>/dev/null | head -5)
else
    echo "warning: bd not found — skipping in-progress task check"
    IN_PROGRESS=""
fi
```

**M3: Hardcoded 8-hour time window**

Replace `'8 hours ago'` with configurable env var:

```bash
TIME_WINDOW="${BEADS_CHECK_WINDOW:-8 hours ago}"
RECENT_COMMITS=$(git log --oneline --since="$TIME_WINDOW" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
```

**L1: Inconsistent error handling**

Normalize all numeric fallbacks to `|| echo "0"` pattern. Remove mixed `|| true` usage on numeric-producing pipelines.

### hooks/session-start — M1, M2

**M1: PWD-relative path for beads configure-server.sh**

Replace `${PWD}/.beads/hooks/configure-server.sh` with a git-root-based lookup:

```bash
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -n "$GIT_ROOT" ]; then
    BEADS_CONFIGURE="$GIT_ROOT/.beads/hooks/configure-server.sh"
fi
```

This is robust across subdirectories and doesn't depend on PWD.

**M2: Silent error suppression on configure-server.sh**

Replace `2>/dev/null || true` with stderr-aware fallback:

```bash
if [ -f "$BEADS_CONFIGURE" ]; then
    BEADS_ERR=$(mktemp 2>/dev/null || echo "/tmp/beads-config-err.$$")
    if ! bash "$BEADS_CONFIGURE" 2>"$BEADS_ERR"; then
        echo "warning: beads configure-server.sh failed" >&2
    fi
    rm -f "$BEADS_ERR"
fi
```

## Batch 2: Tests (4 findings)

All changes in `tests/validate-config.sh`.

### H2: Incomplete skill list in section 3

Expand line 62 from 5 skills to all 9:

```bash
for skill in start resume setup test debugging-protocol beads-milestones spike-phase scope-health verification-template; do
```

### M5: Scenario test structural validation

Add new section (after current section 11) that checks scenario scripts exist and are executable. Does NOT run them — avoids beads database pollution.

```bash
echo "12. Scenario scripts"
for scenario in tests/scenarios/*.sh; do
    name=$(basename "$scenario")
    [[ -f "$scenario" ]] && pass "scenarios/$name exists" || fail "scenarios/$name MISSING"
    [[ -x "$scenario" ]] && pass "scenarios/$name is executable" || fail "scenarios/$name is NOT executable"
done
```

### M6: Cross-reference validation

Add new section that verifies README skill references match actual `skills/*/` directories.

```bash
echo "13. Cross-reference validation"
for skill_dir in skills/*/; do
    skill_name=$(basename "$skill_dir")
    if grep -q "$skill_name" "$PLUGIN_ROOT/README.md" 2>/dev/null; then
        pass "skill $skill_name referenced in README"
    else
        fail "skill $skill_name NOT referenced in README"
    fi
done
```

### L2: Expand hook output validation

Enhance section 5 to check JSON structure beyond just `additionalContext` length. Verify `hookSpecificOutput` key exists:

```python
d=json.load(sys.stdin)
hso=d['hookSpecificOutput']
ctx=hso['additionalContext']
assert isinstance(ctx, str) and len(ctx) > 100
```

## Batch 3: README (4 findings)

All changes in `README.md`.

### H1: Remove phantom PreCompact hook

- Line 14: Change "SessionStart, PreCompact, and Stop hooks" to "SessionStart and Stop hooks"
- Lines 111-112: Remove the PreCompact row from the hooks table

The design spec confirms: "PreCompact: already removed (beads plugin handles this)".

### M4: Remove Context7 from dependencies

Remove the Context7 row from the dependencies table (line 41). Context7 ships with ECC and is not required by any claude-workstation skill.

### L3: Add profiles/ to Project Structure

Add `profiles/` directory entry to the Project Structure diagram, with description "Shell aliases for context-specific Claude invocations".

### L5: Mark optional dependencies

Add "(optional)" annotation to non-essential plugins in the dependencies table: Hookify, Playwright, Code Simplifier, Code Review, Security Guidance, Commit Commands, Frontend Design. Mirrors how mgrep is already annotated.

## Batch 4: .gitignore (1 finding)

### L4: Add common editor/OS temps

Append entries for `.DS_Store`, `*~`, `*.swp`, `*.swo`.

## Execution Strategy

- 4 batches, no inter-dependencies
- Execute via parallel subagents (one per batch)
- Each batch: edit files, run `validate-config.sh` to verify, commit
- Final verification: run full test suite after all batches merge

## Out of Scope

- Functional testing of hooks (running them end-to-end) — would require mock beads environment
- Integrating scenario test execution into validate-config.sh — deferred to avoid side effects
- Refactoring hooks into smaller scripts — current structure is adequate
