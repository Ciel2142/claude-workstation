# Rules-to-Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace always-on rule copying with hook-injected context + on-demand reference skills, saving ~14KB of context per session.

**Architecture:** A SessionStart hook injects a lean workflow context (~3KB) via structured JSON. Five reference rules become on-demand skills. An opt-in `/install-rules` skill preserves the old copy-to-rules behavior. All rule source files stay in `rules/common/` untouched.

**Tech Stack:** Bash (hook script), Markdown (skills, contexts), JSON (hooks.json)

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `contexts/workflow.md` | Create | Condensed unified-workflow + plugin-routing + research-first |
| `hooks/session-start` | Create | Bash script: configure-server + inject workflow.md via additionalContext |
| `hooks/hooks.json` | Modify | Point SessionStart to new script |
| `skills/debugging-protocol/SKILL.md` | Create | On-demand: debugging-first protocol for bugs |
| `skills/beads-milestones/SKILL.md` | Create | On-demand: structured milestone checkpoint format |
| `skills/spike-phase/SKILL.md` | Create | On-demand: spike phase for Medium+ epics |
| `skills/scope-health/SKILL.md` | Create | On-demand: scope health check with escalation ladder |
| `skills/verification-template/SKILL.md` | Create | On-demand: verification output template |
| `skills/install-rules/SKILL.md` | Create | Opt-in: copy rules to ~/.claude/rules/ |
| `skills/setup/SKILL.md` | Modify | Remove rule-copy step, remove ECC check, add notes |
| `skills/test/SKILL.md` | Modify | Validate plugin source files instead of installed copies |
| `tests/validate-config.sh` | Modify | New checks for hook + contexts, remove rule-existence checks |
| `rules/context7.md` | Delete | Redundant with context7 MCP server |
| `profiles/aliases.sh` | Modify | Add claude-workflow alias |
| `CLAUDE.md` | Modify | Mention three-tier model |
| `README.md` | Modify | Updated architecture, hooks, project structure |

---

## Batch A — Core (independent)

### Task 1: Create `contexts/workflow.md`

**Files:**
- Create: `contexts/workflow.md`

- [ ] **Step 1: Write the condensed workflow context**

Create `contexts/workflow.md` with this content:

```markdown
# Workflow Context

All work follows a size-based flow: Beads (tracking) + Superpowers (process) + ECC (expertise).

## Beads-First Rule

Before invoking ANY Superpowers skill, create a beads task first. Sequence: `bd create` → then invoke skill. This applies to ALL work — design, planning, research, and code.

## Task Sizing

| Tier | Signal | Flow |
|---|---|---|
| **Trivial** | ≤1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | `bd create -t epic` → brainstorm → plan → sub-tasks → spike → worktree → TDD → review → verify → update-docs → finish → `bd close` |
| **Bug** | Any tier, type=bug | `bd create -t bug` → debug → TDD (regression test) → review → verify → `bd close` |

Escalation only upward — never downgrade.

## Hard Rules

- No work without a beads task
- No Superpowers skill invocation without an active beads task
- No production code without a failing test (Small/Medium+)
- No completion claims without verification output
- No trusting subagent reports without own verification

## Plugin Routing

- **Beads** → all persistent task/issue tracking (`bd` commands). No TodoWrite for persistent work.
- **Superpowers** → all development process (brainstorming, planning, TDD, code review, verification, debugging, parallel agents, finishing branches).
- **ECC** → all language-specific and domain-specific skills, agents, and patterns. Use within the Superpowers-driven process.

When both apply: Superpowers drives the process, ECC provides expertise within it.

## Research & Reuse

Before any new implementation:
1. GitHub code search first (`gh search repos`, `gh search code`)
2. Library docs second (Context7 or vendor docs)
3. Check package registries before writing utility code
4. Search for adaptable open-source implementations
5. Prefer proven approaches over net-new code

## Side Quests

Discover something unrelated mid-work:
```
bd create --title="Found: <issue>" --type=bug
bd dep add <new-id> <current-id> --type=discovered-from
```
Finish current task first, then `bd ready`.

Run `/help` for detailed step-by-step flows with full ceremony for each tier.
```

- [ ] **Step 2: Verify the file**

```bash
test -f contexts/workflow.md && echo "OK" || echo "FAIL"
wc -c contexts/workflow.md
# Expected: ~1500-2000 bytes (well under 3KB target)
grep -c "Beads-First" contexts/workflow.md
# Expected: 1
grep -c "Plugin Routing" contexts/workflow.md
# Expected: 1
grep -c "Research" contexts/workflow.md
# Expected: 2
```

- [ ] **Step 3: Commit**

```bash
git add contexts/workflow.md
git commit -m "feat: create condensed workflow context for hook injection"
```

---

### Task 2: Create `hooks/session-start` script

**Files:**
- Create: `hooks/session-start`

- [ ] **Step 1: Write the session-start hook script**

Create `hooks/session-start` (no file extension — cross-platform convention from superpowers):

```bash
#!/usr/bin/env bash
# SessionStart hook for claude-workstation plugin
#
# 1. Configures beads server mode (if env vars set)
# 2. Injects condensed workflow context via additionalContext
#
# Output format follows Claude Code's hookSpecificOutput convention.
# Uses printf instead of heredoc to work around bash 5.3+ heredoc hang.
# See: https://github.com/obra/superpowers/issues/571

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Step 1: Configure beads server mode (if applicable)
bash .beads/hooks/configure-server.sh 2>/dev/null || true

# Step 2: Read workflow context
WORKFLOW_CONTEXT_FILE="${PLUGIN_ROOT}/contexts/workflow.md"
if [ ! -f "$WORKFLOW_CONTEXT_FILE" ]; then
    exit 0
fi

WORKFLOW_CONTENT=$(cat "$WORKFLOW_CONTEXT_FILE")

# Step 3: Escape for JSON embedding
escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

escaped_content=$(escape_for_json "$WORKFLOW_CONTENT")

# Step 4: Output structured JSON for Claude Code
# Claude Code sets CLAUDE_PLUGIN_ROOT without COPILOT_CLI
# Cursor sets CURSOR_PLUGIN_ROOT (may also set CLAUDE_PLUGIN_ROOT)
if [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then
    printf '{\n  "additional_context": "%s"\n}\n' "$escaped_content"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -z "${COPILOT_CLI:-}" ]; then
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$escaped_content"
else
    printf '{\n  "additionalContext": "%s"\n}\n' "$escaped_content"
fi

exit 0
```

- [ ] **Step 2: Make executable**

```bash
chmod +x hooks/session-start
```

- [ ] **Step 3: Test the script locally**

```bash
CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
ctx = d.get('hookSpecificOutput', {}).get('additionalContext', '')
print(f'JSON valid: yes')
print(f'Context length: {len(ctx)} chars')
print(f'Contains Beads-First: {\"Beads-First\" in ctx}')
print(f'Contains Plugin Routing: {\"Plugin Routing\" in ctx}')
"
# Expected:
#   JSON valid: yes
#   Context length: ~1500+
#   Contains Beads-First: True
#   Contains Plugin Routing: True
```

- [ ] **Step 4: Commit**

```bash
git add hooks/session-start
git commit -m "feat: add session-start hook for workflow context injection"
```

---

### Task 3: Create 5 reference skills

**Files:**
- Create: `skills/debugging-protocol/SKILL.md`
- Create: `skills/beads-milestones/SKILL.md`
- Create: `skills/spike-phase/SKILL.md`
- Create: `skills/scope-health/SKILL.md`
- Create: `skills/verification-template/SKILL.md`

These 5 skills can be created in parallel. Each wraps an existing rule file with YAML frontmatter.

- [ ] **Step 1: Create `skills/debugging-protocol/SKILL.md`**

```markdown
---
name: debugging-protocol
version: 1.0.0
description: >
  Debugging-first protocol for bugs. Root cause analysis before fixes,
  3-strike rule, systematic debugging workflow.
  TRIGGER: When starting bug work, encountering errors, or debugging.
---

# Debugging

## Debugging-First Protocol

When working on a bug (task type `bug`), ALWAYS invoke `superpowers:systematic-debugging` before attempting a fix.

## Process

1. **Root cause** — read error messages, reproduce the issue, check recent changes
2. **Pattern analysis** — find working examples of similar code, compare with broken code
3. **Hypothesis** — form a single-variable hypothesis, test it
4. **Fix with test** — write a failing regression test that reproduces the bug, then fix (feeds into TDD)
5. **Stop after 3 failed attempts** — if three hypotheses fail, question the architecture. The bug may be a symptom of a deeper design issue.

## Workflow

Bugs follow this path regardless of tier (trivial/small/medium+):

```
bd create --title="..." --type=bug
→ superpowers:systematic-debugging (root cause)
→ superpowers:test-driven-development (regression test + fix)
→ superpowers:requesting-code-review
→ superpowers:verification-before-completion
→ bd close <id>
```

## Anti-Patterns

- Do NOT skip straight to a fix without understanding root cause
- Do NOT write the regression test before identifying the root cause
- Do NOT keep trying random fixes — 3 strikes and reassess
```

- [ ] **Step 2: Create `skills/beads-milestones/SKILL.md`**

```markdown
---
name: beads-milestones
version: 1.0.0
description: >
  Structured checkpoint format for beads milestone notes. Standardized
  key-value pairs for workflow progress tracking.
  TRIGGER: When updating beads task notes at workflow milestones.
---

# Beads Milestone Updates

After completing each workflow milestone, update the beads task so progress
survives session crashes and context compaction.

## When to Update

- After brainstorming: note the spec path
- After writing a plan: note the plan path and sub-task count
- After creating sub-tasks: note the planned count
- After spike: note findings
- After each sub-task: note progress
- After verification: note results
- After updating docs: note what was updated
- At session end: note where you stopped

## Standardized Format

Use one key-value pair per `bd update --notes` call. Keys are lowercase with colon separator.

| Key | Written when | Example |
|---|---|---|
| `tier:` | After `/start` scores the task | `tier: medium+` |
| `spec:` | After brainstorming writes the spec | `spec: docs/superpowers/specs/2026-04-06-auth-design.md` |
| `plan:` | After writing-plans saves the plan | `plan: docs/superpowers/plans/2026-04-06-auth.md` |
| `planned-tasks:` | After sub-tasks created from plan | `planned-tasks: 8` |
| `spike:` | After spike completes | `spike: lightweight` |
| `spike-confirmed:` | Spike findings | `spike-confirmed: file paths valid, interfaces match` |
| `spike-revised:` | Spike found wrong assumption | `spike-revised: config key renamed foo -> bar` |
| `spike-risks:` | Spike identified risks | `spike-risks: large file, consider splitting` |
| `completed:` | After each sub-task closes | `completed: 1,2,3` |
| `current:` | When claiming a sub-task | `current: 4` |
| `micro-tier:` | When claiming a sub-task | `micro-tier: micro-small` |
| `spec-amendment:` | When spec is updated | `spec-amendment: minor -- renamed userId to user_id` |
| `scope-check:` | After scope health triggers | `scope-check: warning -- 8/5 tasks (1.6x)` |
| `verification:` | After verification runs | `verification: tests 47/47, build clean, lint clean` |
| `docs-updated:` | After /update-docs completes | `docs-updated: README, API docs refreshed` |
| `stopped:` | At session end | `stopped: Task 5 of 8, resuming with Task 6` |

## How to Update

```
bd update <id> --notes "<key>: <value>"
```

## Rules

- One key-value per `bd update --notes` call (beads appends, doesn't replace)
- Keys are lowercase, colon-separated, no quotes needed
- `/resume` matches by prefix — consistent format makes detection reliable
- Backward compatible with older free-text notes

## What NOT to Do

- Don't update after every micro-step (each brainstorming question, each test run)
- Don't duplicate full spec/plan content — just reference the file path
- Don't update if nothing meaningful changed since last update
- Don't invent new keys — use the table above
```

- [ ] **Step 3: Create `skills/spike-phase/SKILL.md`**

```markdown
---
name: spike-phase
version: 1.0.0
description: >
  Architecture validation before Medium+ implementation. Lightweight or
  deep spike to confirm assumptions and identify risks.
  TRIGGER: During Medium+ epic, after planning, before first implementation task.
---

# Spike Phase

## When

After the plan is written and sub-tasks are created, before the first implementation
task. Required for all Medium+ epics.

## Conditional Depth

**Lightweight (default):** Research artifact only. Validate integration points, confirm
assumptions, identify risks. No throwaway code. ~10-15 minutes.

**Deep (auto-escalate when ANY plan task description contains):** API, integration,
library, SDK, migrate, external. Produces the research artifact plus a minimal
proof-of-concept for the riskiest integration. Code is discarded after findings are
documented. ~30-60 minutes.

## Process

1. Create the spike sub-task:
   ```
   bd create --title="Task 0: Spike" --type=task
   bd dep add <spike-id> <epic-id> --type=parent-child
   ```
   All other sub-tasks should depend on the spike (add `bd dep add <sub-id> <spike-id>`
   for Layer 1 tasks, or let dependency chains handle it).

2. Determine depth: scan plan task descriptions for escalation keywords. If any match,
   use deep. Otherwise use lightweight.

3. Execute the spike:
   - Read the spec and plan
   - For each integration point: verify the file paths exist, the interfaces match
     what the plan assumes, and the data flows as described
   - For deep spikes: build a minimal proof-of-concept for the riskiest integration,
     then discard the code

4. Record findings in the epic's beads notes:
   ```
   spike: <lightweight|deep>
   spike-confirmed: <assumption1>, <assumption2>
   spike-revised: <assumption that was wrong> -> <correction>
   spike-risks: <risk1>, <risk2>
   ```

5. Gate check: if any `spike-revised` entry is material (changes architecture,
   drops/adds features, changes API shape), trigger the spec amendment protocol
   before proceeding. Minor revisions (naming, paths) can be self-corrected.

6. Close the spike task:
   ```
   bd close <spike-id>
   ```

## What Lightweight Validates

- File paths referenced in the plan actually exist
- Interfaces (function signatures, types, config keys) match what the plan assumes
- Integration points (imports, API calls, database access) work as described
- No blocking unknowns in the dependency chain

## What Deep Adds

- Working proof-of-concept for the riskiest integration
- Verified that external APIs/libraries behave as documented
- Performance or compatibility concerns surfaced before full implementation
```

- [ ] **Step 4: Create `skills/scope-health/SKILL.md`**

```markdown
---
name: scope-health
version: 1.0.0
description: >
  Scope creep detection for Medium+ epics. Warning at 1.5x, gate at 2.0x
  planned tasks. Escalation ladder with re-plan/split/continue options.
  TRIGGER: After every 3rd sub-task completion within a Medium+ epic.
---

# Scope Health Check

## When

After every 3rd sub-task completion within a Medium+ epic. Count closed sub-tasks
and trigger at 3, 6, 9, etc.

## Baseline

After all sub-tasks are created from the plan, record the original count:
```
bd update <epic-id> --notes "planned-tasks: N"
```
This is the denominator for all future ratio calculations.

## Measurements

- **Task ratio:** `(total created sub-tasks) / (planned-tasks from notes)`
- **Discovery count:** Sub-tasks created after the initial plan

## Escalation Ladder

| Trigger | Ratio | Response |
|---|---|---|
| **Warning** | >= 1.5x | Print stats, continue. Log: `scope-check: warning -- N/M tasks (ratio)` |
| **Gate** | >= 2.0x | Print stats, stop, ask human. Log: `scope-check: gate -- N/M tasks (ratio), decision: <choice>` |

## Warning Format

```
Scope check (after task N):
   Planned: M tasks | Actual: X tasks (ratio)
   Discovered: Y new tasks since plan
   Warning: scope growing. Consider whether remaining tasks need re-planning.
```

## Gate Format

```
Scope check (after task N):
   Planned: M tasks | Actual: X tasks (ratio)
   Discovered: Y new tasks since plan
   Scope exceeded 2x. Options:
      1. Re-plan remaining work (update plan, re-estimate)
      2. Split epic (carve off discovered work into a new epic)
      3. Continue as-is (acknowledge scope growth, keep going)

   Pick [1-3]:
```

## After Gate Decision

- **Re-plan:** Update the plan document, create/close sub-tasks as needed, update `planned-tasks:` baseline
- **Split epic:** Create new epic for discovered work, move relevant sub-tasks, reset baseline for both
- **Continue:** Acknowledge and log, no further gates until next 3-task interval
```

- [ ] **Step 5: Create `skills/verification-template/SKILL.md`**

```markdown
---
name: verification-template
version: 1.0.0
description: >
  Standardized verification output format with exit codes. Use when running
  verification-before-completion to produce consistent output.
  TRIGGER: During verification phase, before claiming work is complete.
---

# Verification Output Template

When running `/superpowers:verification-before-completion`, produce output in this
standardized format and append it to the beads task notes.

## Template

````
## Verification: <beads-task-id>
- Tests:  <status> <count> passed, <count> failed (exit <code>)
- Build:  <status> <message> (exit <code>)
- Lint:   <status> <message> (exit <code>)
- Type:   <status> <message> (exit <code>)
- Manual: <status> <description of what was checked>
````

## Status Symbols

- `✓` — check passed
- `✗` — check failed (BLOCKING — must fix before closing task)
- `⊘` — skipped with reason

## Rules

1. Each line must include the actual exit code from the command run.
2. Skipped checks must state the reason: `- Lint: ⊘ skipped (no linter configured)`
3. Failed checks block completion: `- Tests: ✗ 2 failed (exit 1) — BLOCKING`
4. At least one check must pass. All-skipped is not valid verification.
5. Append the verification block to beads task notes: `bd update <id> --notes "<block>"`
```

- [ ] **Step 6: Create skill directories**

```bash
mkdir -p skills/debugging-protocol skills/beads-milestones skills/spike-phase skills/scope-health skills/verification-template
```

Then write each SKILL.md file from Steps 1-5 into its directory.

- [ ] **Step 7: Verify all 5 skills**

```bash
for skill in debugging-protocol beads-milestones spike-phase scope-health verification-template; do
    if [ -f "skills/$skill/SKILL.md" ]; then
        name=$(sed -n '/^---$/,/^---$/{ /^name:/s/^name: *//p }' "skills/$skill/SKILL.md")
        if [ "$name" = "$skill" ]; then
            echo "OK: $skill (name matches)"
        else
            echo "FAIL: $skill (name='$name', expected '$skill')"
        fi
    else
        echo "FAIL: $skill (file missing)"
    fi
done
# Expected: 5x OK
```

- [ ] **Step 8: Commit**

```bash
git add skills/debugging-protocol skills/beads-milestones skills/spike-phase skills/scope-health skills/verification-template
git commit -m "feat: convert 5 reference rules to on-demand skills"
```

---

### Task 4: Create `skills/install-rules/SKILL.md`

**Files:**
- Create: `skills/install-rules/SKILL.md`

- [ ] **Step 1: Write the install-rules skill**

Create `skills/install-rules/SKILL.md`:

```markdown
---
name: install-rules
version: 1.0.0
description: >
  Opt-in: copy all rule files from the plugin to ~/.claude/rules/common/.
  Makes rules always-on in every session. Not required — workflow context
  is auto-injected via hook by default.
  TRIGGER: When user wants traditional always-on rules instead of hook injection.
---

# Install Rules (Opt-In)

Copy all claude-workstation rule files to `~/.claude/rules/common/` so they load
as always-on global rules in every session.

**This is optional.** By default, essential workflow rules are auto-injected via a
SessionStart hook (~3KB). Installing rules adds ~15KB of always-on context on top
of the hook injection. Use this if you want the full reference material (debugging
protocol, milestone format, spike phase, scope health, verification template) always
available without invoking skills.

## Process

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$(dirname "$(dirname "$0")")")" && pwd)}"
RULES_SRC="$PLUGIN_ROOT/rules/common"
RULES_DST="$HOME/.claude/rules/common"

mkdir -p "$RULES_DST"

for file in unified-workflow.md plugin-routing.md development-workflow.md verification-template.md beads-milestones.md debugging.md spike-phase.md scope-health.md; do
    src="$RULES_SRC/$file"
    dst="$RULES_DST/$file"
    if [ ! -f "$dst" ] || [ "$src" -nt "$dst" ]; then
        cp "$src" "$dst"
        echo "Copied: $file"
    else
        echo "Skipped (destination newer): $file"
    fi
done
```

After running, the rules will be active in all future sessions across all projects.

To undo: delete the files from `~/.claude/rules/common/` manually.
```

- [ ] **Step 2: Verify**

```bash
test -f skills/install-rules/SKILL.md && echo "OK" || echo "FAIL"
name=$(sed -n '/^---$/,/^---$/{ /^name:/s/^name: *//p }' skills/install-rules/SKILL.md)
[ "$name" = "install-rules" ] && echo "OK: name matches" || echo "FAIL: name='$name'"
```

- [ ] **Step 3: Commit**

```bash
git add skills/install-rules/SKILL.md
git commit -m "feat: add install-rules skill for opt-in always-on rules"
```

---

## Batch B — Integration (depends on Batch A)

### Task 5: Update `hooks/hooks.json`

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Replace hooks.json content**

Replace the entire content of `hooks/hooks.json` with:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -d .beads ] || [ -d \"$HOME/.beads\" ]; then IN_PROGRESS=$(bd list --status=in_progress 2>/dev/null | grep -c 'workflow-\\|beads-' || true); COMMITS=$(git log --oneline --since='4 hours ago' 2>/dev/null | wc -l | tr -d ' '); if [ \"$COMMITS\" -gt 0 ] && [ \"$IN_PROGRESS\" -eq 0 ]; then echo 'WARNING: This session made commits but has NO beads issues. Work should be tracked.'; fi; bd list --status=in_progress 2>/dev/null | head -5; echo '---'; echo 'Reminder: bd close <id> for completed work'; fi"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Verify**

```bash
python3 -c "import json; d=json.load(open('hooks/hooks.json')); print('JSON valid'); ss=d['hooks']['SessionStart'][0]['hooks'][0]['command']; print(f'SessionStart: {ss[:50]}...')"
# Expected:
#   JSON valid
#   SessionStart: bash "${CLAUDE_PLUGIN_ROOT}/hooks/session-sta...
```

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "refactor: point SessionStart hook to session-start script"
```

---

### Task 6: Update `skills/setup/SKILL.md`

**Files:**
- Modify: `skills/setup/SKILL.md`

- [ ] **Step 1: Remove Step 3 (copy rules)**

In `skills/setup/SKILL.md`, remove the entire "## Step 3: Copy Custom Rules" section (lines 109-141 — from `## Step 3:` through the closing `fi` of the context7.md copy loop).

Replace with:

```markdown
## Step 3: Workflow Rules

Rules are auto-injected via the SessionStart hook — no manual copy needed.

To opt into always-on global rules (adds ~15KB to every session's context):
```bash
/claude-workstation:install-rules
```
```

- [ ] **Step 2: Remove Step 6 (check ECC rules)**

Remove the entire "## Step 6: Check ECC Rules" section (lines 199-210 — from `## Step 6:` through the closing `fi`).

- [ ] **Step 3: Add `claude-workflow` alias to Step 5**

In the shell aliases section, add the `claude-workflow` case after the `claude-review` case:

```bash
                # DEPRECATED: --allow-dangerously-skip-permissions was removed — it bypasses all
                # tool-use confirmation prompts. See profiles/aliases.sh for the safe version.
                claude-workflow)
                    echo "alias claude-workflow='claude --system-prompt \"\$(cat ~/.claude/contexts/workflow.md)\" --effort high'" >> "$SHELL_RC"
                    echo "Added: $alias_name"
                    ;;
```

And update the `for` loop to include `claude-workflow`:

```bash
    for alias_name in claude-dev claude-research claude-review claude-workflow; do
```

- [ ] **Step 4: Renumber remaining steps**

After removing Step 3 (rules) and Step 6 (ECC), renumber:
- Step 4 (contexts) → Step 3
- Step 5 (aliases) → Step 4
- Step 7 (validate) → Step 5

- [ ] **Step 5: Verify**

```bash
grep -c "install-rules" skills/setup/SKILL.md
# Expected: 1
grep -c "claude-workflow" skills/setup/SKILL.md
# Expected: 2+ (in the for loop and case statement)
grep -c "Copy Custom Rules" skills/setup/SKILL.md
# Expected: 0
grep -c "Check ECC" skills/setup/SKILL.md
# Expected: 0
```

- [ ] **Step 6: Commit**

```bash
git add skills/setup/SKILL.md
git commit -m "refactor: remove rule-copy from setup, add install-rules opt-in"
```

---

### Task 7: Update `tests/validate-config.sh` and `skills/test/SKILL.md`

**Files:**
- Modify: `tests/validate-config.sh`
- Modify: `skills/test/SKILL.md`

- [ ] **Step 1: Remove rule file existence checks from validate-config.sh**

Remove section "1. File existence" checks for rule files in `~/.claude/rules/common/` (lines 16-31 — the checks for unified-workflow.md, plugin-routing.md, development-workflow.md, verification-template.md, beads-milestones.md). Keep the checks for contexts and settings.json.

- [ ] **Step 2: Remove checks for rule files at user path**

Remove section "10. Debugging rule" (lines 194-204) and section "10b. Workflow v2 rules" (lines 221-228) and section "11b. Workflow v2 content" (lines 233-261) — these all check `$HOME/.claude/rules/common/` which is no longer required.

- [ ] **Step 3: Add plugin source file checks**

Add a new section after the JSON validity check:

```bash
# --- 2b. Plugin source files ---
echo "2b. Plugin source files"

[[ -f "$PLUGIN_ROOT/contexts/workflow.md" ]] \
    && pass "contexts/workflow.md exists" \
    || fail "contexts/workflow.md MISSING"

[[ -f "$PLUGIN_ROOT/hooks/session-start" ]] \
    && pass "hooks/session-start exists" \
    || fail "hooks/session-start MISSING"

[[ -x "$PLUGIN_ROOT/hooks/session-start" ]] \
    && pass "hooks/session-start is executable" \
    || fail "hooks/session-start is NOT executable"

for skill in debugging-protocol beads-milestones spike-phase scope-health verification-template install-rules; do
    [[ -f "$PLUGIN_ROOT/skills/$skill/SKILL.md" ]] \
        && pass "skills/$skill/SKILL.md exists" \
        || fail "skills/$skill/SKILL.md MISSING"
done

echo ""
```

- [ ] **Step 4: Add content completeness checks against plugin source**

Add a new section:

```bash
# --- 3b. Workflow context content ---
echo "3b. Workflow context content"

for keyword in "Beads-First" "Task Sizing" "Plugin Routing" "Research" "Side Quests"; do
    if grep -q "$keyword" "$PLUGIN_ROOT/contexts/workflow.md" 2>/dev/null; then
        pass "workflow.md contains '$keyword'"
    else
        fail "workflow.md MISSING '$keyword'"
    fi
done

echo ""
```

- [ ] **Step 5: Add hook output test**

```bash
# --- 3c. Hook output ---
echo "3c. Hook output validity"

HOOK_OUTPUT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/hooks/session-start" 2>/dev/null)
if echo "$HOOK_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); ctx=d['hookSpecificOutput']['additionalContext']; assert len(ctx) > 100" 2>/dev/null; then
    pass "session-start hook produces valid JSON with additionalContext"
else
    fail "session-start hook output INVALID"
fi

echo ""
```

- [ ] **Step 6: Update skills/test/SKILL.md**

The test skill just invokes validate-config.sh — update the description to reflect the new checks:

In the "What Gets Tested" section, replace the config validation items:

```markdown
### Config Validation
1. File existence (contexts, settings, plugin source files)
2. JSON validity (settings.json)
3. Plugin presence (Beads, Superpowers, ECC)
4. Hook safety and output validity (session-start produces valid JSON)
5. Workflow context content completeness
6. Skill directory completeness (all 10 skills present)
7. SKILL.md frontmatter name matches directory
8. Shell aliases presence
```

- [ ] **Step 7: Verify**

```bash
grep -c "contexts/workflow.md" tests/validate-config.sh
# Expected: 2+ (existence check + content check)
grep -c "hooks/session-start" tests/validate-config.sh
# Expected: 3+ (existence + executable + output)
grep -c 'HOME/.claude/rules/common/unified-workflow' tests/validate-config.sh
# Expected: 0
```

- [ ] **Step 8: Commit**

```bash
git add tests/validate-config.sh skills/test/SKILL.md
git commit -m "refactor: validate plugin source files instead of installed rule copies"
```

---

## Batch C — Documentation (depends on Batch B)

### Task 8: Delete `rules/context7.md` and update profiles/CLAUDE.md/README

**Files:**
- Delete: `rules/context7.md`
- Modify: `profiles/aliases.sh`
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Delete context7.md**

```bash
git rm rules/context7.md
```

- [ ] **Step 2: Update `profiles/aliases.sh`**

Add the `claude-workflow` alias after the existing three:

```bash
# DEPRECATED: --allow-dangerously-skip-permissions was removed — it bypasses all
# tool-use confirmation prompts. See profiles/aliases.sh for the safe version.
alias claude-workflow='claude --system-prompt "$(cat ~/.claude/contexts/workflow.md)" --effort high'
```

- [ ] **Step 3: Update `CLAUDE.md`**

Replace the entire content with:

```markdown
## Beads-First Rule

Before invoking ANY Superpowers skill (brainstorming, writing-plans, TDD, code-review, debugging, verification, etc.), create a beads task first.

Sequence: `bd create` → then invoke skill.

This applies to ALL work — design, planning, research, and code. No exceptions.

## Quick Start

- **New work:** `/claude-workstation:start "description"` — assess tier, create task, start workflow
- **Resume work:** `/claude-workstation:resume` — pick up open tasks, load context, continue workflow

## Workflow

Run `/help` for the full development playbook with size-based routing (trivial/small/medium+).

## Rules Delivery

Workflow rules are auto-injected via SessionStart hook (~3KB). Reference skills (debugging protocol, milestones, spike phase, scope health, verification template) are loaded on demand.

- **Opt-in always-on rules:** `/claude-workstation:install-rules` — copies all rules to `~/.claude/rules/`
- **Workflow alias:** `claude-workflow` — launches Claude with workflow context

## Setup

Run `/claude-workstation:setup` to install dependencies and configure environment.

## Validation

Run `/claude-workstation:test` to validate the configuration.
```

- [ ] **Step 4: Update `README.md`**

Update these sections:

**In "What's Included"**, replace the MCP Servers line:
```
- **Auto-Injected Context** — SessionStart hook delivers workflow rules (~3KB) without setup
```

**In "Hooks" table**, replace the SessionStart row:
```
| **SessionStart** | Session begins | Injects condensed workflow context via `additionalContext` + configures beads server |
```

**In "Rules" section**, add note:
```
Rules are auto-injected via hook by default. Run `/install-rules` to opt into always-on global rules.
```

**In "Commands & Skills" table**, add:
```
| `/claude-workstation:install-rules` | Opt-in: copy rules to ~/.claude/rules/ for always-on |
| `/claude-workstation:debugging-protocol` | Reference: debugging-first protocol for bugs |
| `/claude-workstation:beads-milestones` | Reference: structured milestone checkpoint format |
| `/claude-workstation:spike-phase` | Reference: architecture validation for Medium+ |
| `/claude-workstation:scope-health` | Reference: scope creep detection with escalation |
| `/claude-workstation:verification-template` | Reference: standardized verification output format |
```

**In "Context Profiles"**, add:
```bash
claude-workflow   # Workflow rules context (same as auto-injected hook)
```

**In "Project Structure"**, update to:
```
claude-workstation/
├── commands/
│   └── help.md               # /help command — full playbook
├── skills/
│   ├── start/SKILL.md         # /start — auto-tier assessment & workflow start
│   ├── resume/SKILL.md        # /resume — continue open work
│   ├── setup/SKILL.md         # /setup — environment installer
│   ├── test/SKILL.md          # /test — config validation
│   ├── install-rules/SKILL.md # /install-rules — opt-in always-on rules
│   ├── debugging-protocol/    # On-demand: debugging-first protocol
│   ├── beads-milestones/      # On-demand: milestone checkpoint format
│   ├── spike-phase/           # On-demand: architecture validation
│   ├── scope-health/          # On-demand: scope creep detection
│   └── verification-template/ # On-demand: verification output format
├── rules/common/              # Source of truth (used by /install-rules)
├── contexts/
│   ├── workflow.md            # Condensed rules (auto-injected via hook)
│   ├── dev.md
│   ├── research.md
│   └── review.md
├── hooks/
│   ├── hooks.json             # SessionStart + Stop hooks
│   └── session-start          # Context injection script
├── tests/
│   └── validate-config.sh
├── .mcp.json
├── CLAUDE.md
└── AGENTS.md
```

- [ ] **Step 5: Verify**

```bash
test ! -f rules/context7.md && echo "OK: context7.md deleted" || echo "FAIL: still exists"
grep -c "claude-workflow" profiles/aliases.sh
# Expected: 1
grep -c "install-rules" CLAUDE.md
# Expected: 1
grep -c "auto-injected\|SessionStart hook" README.md
# Expected: 2+
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "docs: update plugin for three-tier rules delivery model"
```

---

## Task Dependencies

```
Batch A (all independent):
  Task 1: contexts/workflow.md     (no deps)
  Task 2: hooks/session-start      (depends on Task 1 — reads workflow.md)
  Task 3: 5 reference skills       (no deps)
  Task 4: install-rules skill      (no deps)

Batch B (depends on Batch A):
  Task 5: hooks.json               (depends on Task 2 — references session-start)
  Task 6: setup skill              (depends on Tasks 3, 4 — references new skills)
  Task 7: test suite               (depends on Tasks 1, 2, 3, 4 — validates all)

Batch C (depends on Batch B):
  Task 8: docs + cleanup           (depends on everything — documents final state)
```
