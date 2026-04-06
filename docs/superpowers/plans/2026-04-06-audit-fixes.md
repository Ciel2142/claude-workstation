# Fix 14 Audit Findings — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve all 14 findings from the 2026-04-06 plugin audit — improving hook robustness, test coverage, README accuracy, and file hygiene.

**Architecture:** Four independent batches (hooks, tests, README, .gitignore) executed in parallel. No batch depends on another. Each batch edits 1-2 files and commits independently.

**Tech Stack:** Bash (hooks, tests), Markdown (README, .gitignore)

---

### Task 1: Fix hooks — stop and session-start (H3, M3, L1, M1, M2)

**Files:**
- Modify: `hooks/stop` (lines 17-25)
- Modify: `hooks/session-start` (lines 17-19)

- [ ] **Step 1: Rewrite hooks/stop with all 3 fixes**

Replace the entire content of `hooks/stop` with:

```bash
#!/usr/bin/env bash
# Stop hook for claude-workstation plugin
#
# Warns about untracked commits and lists in-progress tasks.

set -euo pipefail

# Only run if beads is initialized (project-local or global)
BEADS_DIR="${PWD}/.beads"
BEADS_GLOBAL="$HOME/.beads"

if [ ! -d "$BEADS_DIR" ] && [ ! -d "$BEADS_GLOBAL" ]; then
    exit 0
fi

# H3: Check bd availability before using it
if ! command -v bd >/dev/null 2>&1; then
    echo "warning: bd not found in PATH — skipping beads session check"
    exit 0
fi

# M3: Configurable time window (default: 8 hours)
TIME_WINDOW="${BEADS_CHECK_WINDOW:-8 hours ago}"

# L1: Consistent error handling — all numeric fallbacks use || echo "0"
IN_PROGRESS=$(bd list --status=in_progress 2>/dev/null | grep -c 'beads-\|workflow-' || echo "0")
RECENT_COMMITS=$(git log --oneline --since="$TIME_WINDOW" 2>/dev/null | wc -l | tr -d ' ' || echo "0")

if [ "$RECENT_COMMITS" -gt 0 ] && [ "$IN_PROGRESS" -eq 0 ]; then
    echo "WARNING: This session made $RECENT_COMMITS commit(s) but has NO beads issues. Work should be tracked."
fi

# Show in-progress tasks as a reminder
bd list --status=in_progress 2>/dev/null | head -5 || true

echo "---"
echo "Reminder: bd close <id> for completed work"
```

- [ ] **Step 2: Rewrite hooks/session-start lines 16-20 with M1 and M2 fixes**

Replace lines 16-20 in `hooks/session-start`:

```
# Step 1: Configure beads server mode (if applicable)
BEADS_CONFIGURE="${PWD}/.beads/hooks/configure-server.sh"
if [ -x "$BEADS_CONFIGURE" ]; then
    bash "$BEADS_CONFIGURE" 2>/dev/null || true
fi
```

With:

```
# Step 1: Configure beads server mode (if applicable)
# M1: Use git root instead of PWD (robust across subdirectories)
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -n "$GIT_ROOT" ]; then
    BEADS_CONFIGURE="$GIT_ROOT/.beads/hooks/configure-server.sh"
else
    BEADS_CONFIGURE=""
fi
# M2: Warn on failure instead of silent suppression
if [ -n "$BEADS_CONFIGURE" ] && [ -x "$BEADS_CONFIGURE" ]; then
    if ! bash "$BEADS_CONFIGURE" 2>/dev/null; then
        echo "warning: beads configure-server.sh failed" >&2
    fi
fi
```

- [ ] **Step 3: Verify hooks execute without errors**

Run:
```bash
# Stop hook — should exit cleanly (may print warnings if not in a beads project)
bash hooks/stop 2>&1; echo "exit: $?"

# Session-start hook — should produce valid JSON
CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK:', list(d.keys()))"
```

Expected: Both exit 0. Session-start produces valid JSON.

- [ ] **Step 4: Run validate-config.sh**

Run: `bash tests/validate-config.sh`

Expected: All existing checks still pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/stop hooks/session-start
git commit -m "fix: improve hook robustness — bd check, configurable window, git-root path"
```

---

### Task 2: Expand test coverage (H2, M5, M6, L2)

**Files:**
- Modify: `tests/validate-config.sh` (lines 62, 86-91, and append new sections)

- [ ] **Step 1: Fix H2 — expand section 3 skill list**

In `tests/validate-config.sh`, replace line 62:

```bash
for skill in debugging-protocol beads-milestones spike-phase scope-health verification-template; do
```

With:

```bash
for skill in start resume setup test debugging-protocol beads-milestones spike-phase scope-health verification-template; do
```

- [ ] **Step 2: Fix L2 — improve hook output validation**

In `tests/validate-config.sh`, replace lines 87-88:

```bash
if echo "$HOOK_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); ctx=d['hookSpecificOutput']['additionalContext']; assert len(ctx) > 100" 2>/dev/null; then
    pass "session-start hook produces valid JSON with additionalContext"
```

With:

```bash
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
```

- [ ] **Step 3: Add M5 — section 12: scenario script validation**

Append after the section 11 closing `echo ""` (after line 235), before the Summary section:

```bash
# --- 12. Scenario scripts ---
echo "12. Scenario scripts"

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
```

- [ ] **Step 4: Add M6 — section 13: cross-reference validation**

Append after section 12:

```bash
# --- 13. Cross-reference validation ---
echo "13. Cross-reference validation"

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
```

- [ ] **Step 5: Run the updated test suite**

Run: `bash tests/validate-config.sh`

Expected: All checks pass (old + new sections 12 and 13). Count should increase from 55 to ~80+.

- [ ] **Step 6: Commit**

```bash
git add tests/validate-config.sh
git commit -m "test: expand coverage — full skill list, scenario checks, cross-ref validation"
```

---

### Task 3: Fix README accuracy (H1, M4, L3, L5)

**Files:**
- Modify: `README.md` (lines 14, 41-48, 111, 126-153)
- Modify: `skills/setup/SKILL.md` (line 53 — remove Context7 to stay consistent)

- [ ] **Step 1: Fix H1 — remove phantom PreCompact hook**

In `README.md`, replace line 14:

```
- **Session Hooks** — SessionStart, PreCompact, and Stop hooks for beads state persistence
```

With:

```
- **Session Hooks** — SessionStart and Stop hooks for beads state persistence
```

Then replace the hooks table (lines 108-112):

```
| Hook | When | What |
|---|---|---|
| **SessionStart** | Session begins | Injects condensed workflow context via `additionalContext` + configures beads server |
| **PreCompact** | Before context compaction | Runs `bd prime` to preserve beads state |
| **Stop** | Session ends | Warns about untracked commits, lists in-progress tasks |
```

With:

```
| Hook | When | What |
|---|---|---|
| **SessionStart** | Session begins | Injects condensed workflow context via `additionalContext` + configures beads server |
| **Stop** | Session ends | Warns about untracked commits, lists in-progress tasks |
```

- [ ] **Step 2: Fix M4 — remove Context7 from dependencies**

In `README.md`, delete line 41:

```
| Context7 | claude-plugins-official | Real-time library and framework documentation lookup via MCP |
```

In `skills/setup/SKILL.md`, remove Context7 from the needed dict (line 53):

```python
    'context7@claude-plugins-official': 'Context7',
```

- [ ] **Step 3: Fix L5 — mark optional dependencies**

In `README.md`, update the dependencies table. Change lines 42-48 from:

```
| Hookify | claude-plugins-official | Create and manage hooks to prevent unwanted agent behaviors |
| Playwright | claude-plugins-official | Browser automation for E2E testing and visual verification |
| Code Simplifier | claude-plugins-official | Simplifies and refines code for clarity, consistency, and maintainability |
| Code Review | claude-plugins-official | Automated code review for quality, security, and best practices |
| Security Guidance | claude-plugins-official | Security vulnerability detection and remediation guidance |
| Commit Commands | claude-plugins-official | Git commit, push, and PR creation workflows |
| Frontend Design | claude-plugins-official | Create distinctive, production-grade frontend interfaces |
```

To:

```
| Hookify *(optional)* | claude-plugins-official | Create and manage hooks to prevent unwanted agent behaviors |
| Playwright *(optional)* | claude-plugins-official | Browser automation for E2E testing and visual verification |
| Code Simplifier *(optional)* | claude-plugins-official | Simplifies and refines code for clarity, consistency, and maintainability |
| Code Review *(optional)* | claude-plugins-official | Automated code review for quality, security, and best practices |
| Security Guidance *(optional)* | claude-plugins-official | Security vulnerability detection and remediation guidance |
| Commit Commands *(optional)* | claude-plugins-official | Git commit, push, and PR creation workflows |
| Frontend Design *(optional)* | claude-plugins-official | Create distinctive, production-grade frontend interfaces |
```

- [ ] **Step 4: Fix L3 — add profiles/ and stop hook to Project Structure**

In `README.md`, replace the Project Structure block (lines 127-153):

```
claude-workstation/
├── commands/
│   └── help.md               # /help command — full playbook
├── skills/
│   ├── start/SKILL.md         # /start — auto-tier assessment & workflow start
│   ├── resume/SKILL.md        # /resume — continue open work
│   ├── setup/SKILL.md         # /setup — environment installer
│   ├── test/SKILL.md          # /test — config validation
│   ├── debugging-protocol/    # On-demand: debugging-first protocol
│   ├── beads-milestones/      # On-demand: milestone checkpoint format
│   ├── spike-phase/           # On-demand: architecture validation
│   ├── scope-health/          # On-demand: scope creep detection
│   └── verification-template/ # On-demand: verification output format
├── contexts/
│   ├── workflow.md            # Workflow context (auto-injected via hook)
│   ├── dev.md
│   ├── research.md
│   └── review.md
├── hooks/
│   ├── hooks.json             # SessionStart + Stop hooks
│   └── session-start          # Context injection script
├── tests/
│   └── validate-config.sh
├── CLAUDE.md
└── AGENTS.md
```

With:

```
claude-workstation/
├── commands/
│   └── help.md               # /help command — full playbook
├── skills/
│   ├── start/SKILL.md         # /start — auto-tier assessment & workflow start
│   ├── resume/SKILL.md        # /resume — continue open work
│   ├── setup/SKILL.md         # /setup — environment installer
│   ├── test/SKILL.md          # /test — config validation
│   ├── debugging-protocol/    # On-demand: debugging-first protocol
│   ├── beads-milestones/      # On-demand: milestone checkpoint format
│   ├── spike-phase/           # On-demand: architecture validation
│   ├── scope-health/          # On-demand: scope creep detection
│   └── verification-template/ # On-demand: verification output format
├── contexts/
│   ├── workflow.md            # Workflow context (auto-injected via hook)
│   ├── dev.md
│   ├── research.md
│   └── review.md
├── hooks/
│   ├── hooks.json             # SessionStart + Stop hooks
│   ├── session-start          # Context injection script
│   └── stop                   # Session-end reminder script
├── profiles/
│   └── aliases.sh             # Shell aliases for context profiles
├── tests/
│   ├── validate-config.sh     # Config validation
│   └── scenarios/             # Workflow dry-run scenario scripts
├── CLAUDE.md
└── AGENTS.md
```

- [ ] **Step 5: Verify README renders correctly**

Run:
```bash
# Check no broken markdown table syntax
python3 -c "
lines = open('README.md').readlines()
for i, line in enumerate(lines, 1):
    if '|' in line and line.strip().startswith('|'):
        cols = line.strip().split('|')
        if len(cols) < 3:
            print(f'WARNING line {i}: possible broken table row')
print('README table check done')
"
```

Expected: No warnings.

- [ ] **Step 6: Commit**

```bash
git add README.md skills/setup/SKILL.md
git commit -m "docs: fix README — remove PreCompact, drop Context7, mark optional deps, update structure"
```

---

### Task 4: Update .gitignore (L4)

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Append editor/OS temp patterns**

Append to `.gitignore`:

```
# Editor and OS temps
.DS_Store
*~
*.swp
*.swo
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add editor/OS temp patterns to .gitignore"
```

---

### Task 5: Final verification

**Files:** None (read-only verification)

- [ ] **Step 1: Run full test suite**

Run: `bash tests/validate-config.sh`

Expected: All checks pass. Total should be ~80+ (up from 55).

- [ ] **Step 2: Run hooks manually**

```bash
# Stop hook
bash hooks/stop 2>&1; echo "exit: $?"

# Session-start hook
CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start | python3 -c "import sys,json; d=json.load(sys.stdin); print('Keys:', list(d.get('hookSpecificOutput', d).keys()))"
```

Expected: Both exit 0, valid output.

- [ ] **Step 3: Push all commits**

```bash
git push
```
