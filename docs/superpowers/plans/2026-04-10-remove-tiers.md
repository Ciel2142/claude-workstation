# Remove Tier Mechanism Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the tier classification system from `/start`, replacing it with a simple brainstorm-or-plan choice. Every task gets the full pipeline.

**Architecture:** The tier mechanism (5 gates, keyword matching, tier-based routing) is removed from the start skill. The pre-change gate hook drops its tier check. Tests and docs are updated to reflect the new flow. The brainstorming and writing-plans skills are untouched.

**Tech Stack:** Bash, YAML, Markdown

---

### Task 1: Rewrite `/start` Skill

**Files:**
- Modify: `skills/start/SKILL.md`

- [ ] **Step 1: Read current file and verify starting state**

Run: `head -5 skills/start/SKILL.md`
Expected: frontmatter with `version: 2.2.2`

- [ ] **Step 2: Replace the entire SKILL.md with the simplified version**

Write `skills/start/SKILL.md` with this content:

```markdown
---
name: start
version: 2.3.0
description: >
  Create a beads task and choose your workflow entry point.
  TRIGGER: When starting any new work, or when the user describes a task.
---

# Start: Task Creation & Workflow Entry

Creates a beads task and lets the user choose between brainstorming
(clarify what to build) or planning (decompose into sub-tasks).

## Invocation

- `/claude-workstation:start "Add rate limiting to all API endpoints"`
- `/claude-workstation:start -p 0 "Critical production outage"`
- `/claude-workstation:start --side-quest "Found: tokens aren't rotated"`

## Flow

Execute these steps in order:

### Step 1: PARSE

Extract from arguments:
- **description**: The quoted task description
- **priority override**: `-p <0-4>` if provided (optional)
- **side-quest flag**: `--side-quest` if provided (optional)

### Step 2: CHECK FOR SIDE-QUEST

Before creating, check if this is a side-quest. A side-quest is detected when ANY of:
- Description starts with "Found:" or "Discovered:"
- The `--side-quest` flag was passed
- There is an active in-progress beads task (check `bd list --status=in_progress`) AND the new work would touch files not listed in the current task's beads description or plan (different files or different directory — even if causally related to the current task's changes)

**If side-quest detected**, skip to the SIDE-QUEST FLOW below.

### Step 3: CREATE

Create the beads task:

```bash
bd create --title="<description>" --type=task -p <priority-override-or-2>
```

If `bd create` fails (beads not initialized, offline, or command error), stop and tell
the user: "Failed to create beads task. Run `bd doctor` to diagnose, or `bd init` if
beads is not set up for this project."

Then set it to in-progress:
```bash
bd update <task-id> -s in_progress
```

### Step 4: ROUTE

Print confirmation and ask one question:

```
✓ Created: <task-id> (P<priority>)
→ Brainstorm first, or straight to planning?
```

Wait for user response.

- If the user chooses brainstorm: invoke `/superpowers:brainstorming`
- If the user chooses planning: invoke `/superpowers:writing-plans`

---

## SIDE-QUEST FLOW

When a side-quest is detected:

1. **Identify the current in-progress task:**
   ```bash
   bd list --status=in_progress
   ```

2. **Create the side-quest task:**
   ```bash
   bd create --title="<description>" --type=bug -p <priority-override-or-2>
   ```
   Type defaults to `bug` for all side-quests involving broken behavior. Only use `--type=feature` or `--type=task` if the discovery describes new functionality with no broken behavior.

3. **Link it:**
   ```bash
   bd dep add <new-task-id> <current-task-id> --type=discovered-from
   ```

4. **Print output:**
   ```
   ✓ Created: <new-task-id> (bug, P<priority>)
     Linked: <new-task-id> discovered-from <current-task-id>
   → Parked. Finish current task first, then bd ready.
   ```

5. **Do NOT invoke any skill.** Return control to the user to continue current work.
```

- [ ] **Step 3: Verify the new file is valid**

Run: `head -5 skills/start/SKILL.md && wc -l skills/start/SKILL.md`
Expected: frontmatter shows `version: 2.3.0`, file is ~85 lines (down from ~193)

- [ ] **Step 4: Commit**

```bash
git add skills/start/SKILL.md
git commit -m "refactor: remove tier mechanism from start skill

Replace 5-gate tier classification with simple brainstorm-or-plan choice.
Every task gets the full pipeline — no more 'go fix it' shortcuts."
```

---

### Task 2: Remove Tier Check from Pre-Change Gate Hook

**Files:**
- Modify: `hooks/pre-change-gate` (lines 73-77)

- [ ] **Step 1: Read the section to remove**

Run: `sed -n '68,80p' hooks/pre-change-gate`
Expected: lines 73-77 contain the `tier:` grep check

- [ ] **Step 2: Remove the tier check block**

Remove lines 73-77 (the `else` branch that checks for `tier:` in notes):

```bash
# BEFORE (lines 69-78):
if [ -z "$TASK_ID" ]; then
    OUTPUT=$(printf '%s\n%s' \
        "WARNING: No active beads task. Create one before modifying files:" \
        "   bd create --title=\"...\" --type=task")
else
    NOTES=$($TO bd show "$TASK_ID" 2>/dev/null || echo "")
    if ! echo "$NOTES" | grep -q 'tier:'; then
        OUTPUT="WARNING: Active task ($TASK_ID) has no tier assessment. Run /claude-workstation:start to assess."
    fi
fi

# AFTER:
if [ -z "$TASK_ID" ]; then
    OUTPUT=$(printf '%s\n%s' \
        "WARNING: No active beads task. Create one before modifying files:" \
        "   bd create --title=\"...\" --type=task")
fi
```

- [ ] **Step 3: Verify hook still runs cleanly**

Run: `bash hooks/pre-change-gate; echo "exit: $?"`
Expected: exits 0 (may warn about no active task — that's fine)

- [ ] **Step 4: Commit**

```bash
git add hooks/pre-change-gate
git commit -m "refactor: remove tier check from pre-change gate hook

The hook still checks for active beads task existence. The tier-specific
warning is removed since tiers no longer exist."
```

---

### Task 3: Update Workflow Skill

**Files:**
- Modify: `skills/workflow/SKILL.md`

- [ ] **Step 1: Update version in frontmatter**

Change line 3 from `version: 2.2.2` to `version: 2.3.0`.

- [ ] **Step 2: Update "The Flow" description**

Change line 25 from:
```
Not every task needs every step. `/claude-workstation:start` assesses complexity and suggests where to enter.
```
To:
```
Every task follows the full pipeline. The pipeline self-scales to complexity.
```

- [ ] **Step 3: Remove tier escalation from Hard Rules**

Remove line 50:
```
- Escalation upward only -- if work grows, re-assess tier, never downgrade
```

- [ ] **Step 4: Remove `tier:` from Milestone Notes table**

Change the milestone notes table (lines 135-141) from:
```
| Key | When | Key | When |
|-----|------|-----|------|
| `tier:` | After `/start` | `completed:` | Sub-task closes |
| `spec:` | After brainstorming | `current:` | Claiming sub-task |
| `plan:` | After writing plan | `debug:` | Root cause found |
| `planned-tasks:` | Sub-tasks created | `verification:` | After verification |
| `stopped:` | Session end / compact | `active-skill:` | Skill invoked |
```
To:
```
| Key | When | Key | When |
|-----|------|-----|------|
| `spec:` | After brainstorming | `completed:` | Sub-task closes |
| `plan:` | After writing plan | `current:` | Claiming sub-task |
| `planned-tasks:` | Sub-tasks created | `debug:` | Root cause found |
| `stopped:` | Session end / compact | `verification:` | After verification |
| `active-skill:` | Skill invoked | | |
```

- [ ] **Step 5: Verify the file**

Run: `grep -n 'tier' skills/workflow/SKILL.md`
Expected: no matches (tier fully removed)

- [ ] **Step 6: Commit**

```bash
git add skills/workflow/SKILL.md
git commit -m "refactor: remove tier references from workflow skill

Full pipeline always applies. No tier escalation rule needed."
```

---

### Task 4: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Remove tier escalation from Hard Rules**

Remove line 25:
```
- Escalation upward only -- if work grows, re-assess tier, never downgrade
```

- [ ] **Step 2: Update the heading**

Change line 6 from:
```
### Quick Reference (scale ceremony to complexity)
```
To:
```
### Quick Reference
```

- [ ] **Step 3: Verify**

Run: `grep -n 'tier' CLAUDE.md`
Expected: no matches

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "refactor: remove tier references from CLAUDE.md"
```

---

### Task 5: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update plugin description (line 9)**

Change:
```
- **Auto-Tier Assessment** -- `/start` evaluates task descriptions and routes to the right workflow
```
To:
```
- **Task Kickoff** -- `/start` creates a beads task and routes to brainstorming or planning
```

- [ ] **Step 2: Update Commands table (line 47)**

Change:
```
| `/claude-workstation:start` | Auto-assess task tier, create beads task, start the right workflow |
```
To:
```
| `/claude-workstation:start` | Create beads task and choose workflow entry (brainstorm or plan) |
```

- [ ] **Step 3: Update `/start` examples section (lines 50-64)**

Replace the entire `/start` examples block with:

```markdown
### `/start` — Begin New Work

```bash
/claude-workstation:start "Fix the login validation bug"
# → Creates task → "Brainstorm or plan?"

/claude-workstation:start "Design a new notification system"
# → Creates task → "Brainstorm or plan?"

/claude-workstation:start --side-quest "Found: tokens aren't rotated"
# → Detects side-quest → creates bug → links to current task → parks it
```
```

- [ ] **Step 4: Update project structure description (line 84)**

Change:
```
│   ├── start/SKILL.md         # /start -- auto-tier assessment & workflow start
```
To:
```
│   ├── start/SKILL.md         # /start -- task creation & workflow entry
```

- [ ] **Step 5: Verify no tier references remain**

Run: `grep -in 'tier' README.md`
Expected: no matches

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: update README to reflect tier removal"
```

---

### Task 6: Update Version in Plugin Configs

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Update plugin.json version and description**

Change line 3 from `"version": "2.2.2"` to `"version": "2.3.0"`.

Change line 4 description from:
```
"description": "Personal development environment — unified workflow (Beads + Superpowers + ECC) with auto-tier assessment and session hooks. One install restores everything.",
```
To:
```
"description": "Personal development environment — unified workflow (Beads + Superpowers + ECC) with session hooks. One install restores everything.",
```

- [ ] **Step 2: Update marketplace.json version and descriptions**

Change line 5 description from:
```
"description": "Personal dev environment — unified Beads + Superpowers + ECC workflow with auto-tier assessment and session hooks. One install restores everything.",
```
To:
```
"description": "Personal dev environment — unified Beads + Superpowers + ECC workflow with session hooks. One install restores everything.",
```

Change line 12 description from:
```
"description": "Unified development workflow with size-based routing, auto-tier assessment, and session hooks",
```
To:
```
"description": "Unified development workflow with session hooks",
```

Change line 13 from `"version": "2.2.2"` to `"version": "2.3.0"`.

- [ ] **Step 3: Verify JSON validity**

Run: `python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); json.load(open('.claude-plugin/marketplace.json')); print('valid')"`
Expected: `valid`

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore: bump version to 2.3.0 and remove tier from descriptions"
```

---

### Task 7: Rewrite Start Skill Spec

**Files:**
- Modify: `tests/specs/start.yaml`

- [ ] **Step 1: Replace start.yaml with simplified spec**

Write `tests/specs/start.yaml` with:

```yaml
id: start-skill
name: Start Skill Workflow
source_rule: skills/start/SKILL.md
version: "2.0"

steps:
  - id: parse_args
    description: "Parse description, priority override, and side-quest flag from arguments"
    required: true
    detector:
      description: "Extract quoted description, -p flag value, and --side-quest flag"
      before_step: check_side_quest

  - id: check_side_quest
    description: "Check for side-quest indicators before task creation"
    required: true
    detector:
      description: "Check for Found:/Discovered: prefix, --side-quest flag, or scope conflict with in-progress task"
      after_step: parse_args
      before_step: create_task

  - id: create_task
    description: "Create beads task with --type=task and default P2 priority"
    required: true
    detector:
      description: "Run bd create with --type=task and -p 2 (or user override), then bd update to in_progress"
      after_step: check_side_quest

  - id: present_choice
    description: "Ask user: brainstorm first, or straight to planning?"
    required: true
    detector:
      description: "Print task-id confirmation and present brainstorm/plan choice. Wait for user response."
      after_step: create_task

scoring:
  threshold_promote_to_hook: 0.6
```

- [ ] **Step 2: Verify YAML structure**

Run: `python3 -c "import yaml; yaml.safe_load(open('tests/specs/start.yaml')); print('valid')"`
Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add tests/specs/start.yaml
git commit -m "test: rewrite start spec for simplified flow (no tiers)"
```

---

### Task 8: Update Pre-Change Gate Spec

**Files:**
- Modify: `tests/specs/pre-change-gate.yaml`

- [ ] **Step 1: Remove `warn_no_tier` step**

Remove lines 44-49 (the `warn_no_tier` step):

```yaml
  - id: warn_no_tier
    description: "Warn if active task has no tier assessment"
    required: true
    detector:
      description: "Run bd show on task, check notes for tier: pattern, warn if missing"
      after_step: query_in_progress
```

- [ ] **Step 2: Verify YAML structure**

Run: `python3 -c "import yaml; yaml.safe_load(open('tests/specs/pre-change-gate.yaml')); print('valid')"`
Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add tests/specs/pre-change-gate.yaml
git commit -m "test: remove warn_no_tier step from pre-change gate spec"
```

---

### Task 9: Update Position Detection Spec

**Files:**
- Modify: `tests/specs/position-detection.yaml`

- [ ] **Step 1: Remove `detect_tier_only` step**

Remove lines 48-53 (the `detect_tier_only` step):

```yaml
  - id: detect_tier_only
    description: "Detect start position when only tier: is present"
    required: true
    detector:
      description: "If notes contain only tier: with no other milestones, return start (priority 8)"
      after_step: scan_milestones
```

- [ ] **Step 2: Remove `tier` from the `scan_milestones` detector description**

Change the `scan_milestones` detector from:
```yaml
      description: "Check notes string for milestone keys in order: docs-updated, verification, completed, planned-tasks, plan, spec, debug, tier"
```
To:
```yaml
      description: "Check notes string for milestone keys in order: docs-updated, verification, completed, planned-tasks, plan, spec, debug"
```

- [ ] **Step 3: Verify YAML structure**

Run: `python3 -c "import yaml; yaml.safe_load(open('tests/specs/position-detection.yaml')); print('valid')"`
Expected: `valid`

- [ ] **Step 4: Commit**

```bash
git add tests/specs/position-detection.yaml
git commit -m "test: remove tier from position detection spec"
```

---

### Task 10: Rewrite Behavioral Tests (tier-dependent sections)

**Files:**
- Modify: `tests/test-behaviors.sh`

- [ ] **Step 1: Update Section 2 — remove test 2b (tier warning) and update 2c**

Remove test 2b entirely (lines 253-268, "Task exists, no tier in notes").

Update test 2c (lines 270-286, "Task exists with tier") to become the new 2b — "Task exists, no warning expected". Change the test to verify that when a task exists (regardless of notes content), there is no warning:

Change the mock's `BD_SHOW_OUTPUT` to have notes WITHOUT `tier:`:
```bash
# 2b. Task exists — no output expected (tier check removed)
rm -f "$GATE_CACHE"
export BD_LIST_JSON_OUTPUT='[{"id": "test-456", "title": "Test task"}]'
export BD_LIST_OUTPUT="  test-456  IN_PROGRESS  Test task"
export BD_SHOW_OUTPUT="TITLE
Test task
NOTES
plan: docs/plan.md
STATUS
in_progress"
GATE_OUT=$(cd "$PLUGIN_ROOT" && PATH="$TMPDIR_GATE:$PATH" \
    bash "$PLUGIN_ROOT/hooks/pre-change-gate" 2>/dev/null || true)
if [[ -z "$GATE_OUT" ]]; then
    pass "2b. task exists — outputs nothing (no warning)"
else
    fail "2b. task exists — expected empty output, got: $(printf '%q' "$GATE_OUT")"
fi
```

- [ ] **Step 2: Update Section 3 — remove tier from position detection**

In the `detect_position()` function (lines 296-317), remove the tier check:

```bash
# REMOVE these two lines from the function:
    elif echo "$notes" | grep -q 'tier:'; then
        echo "start"
```

Update test assertions. Replace the full assertion block (lines 332-341) with:

```bash
_assert_position "3a. spec only"          "spec: docs/specs/foo.md"                                           "post-brainstorming"
_assert_position "3b. spec + plan"        "$(printf 'spec: docs/specs/foo.md\nplan: docs/plans/foo.md')"      "post-planning"
_assert_position "3c. with completed"     "$(printf 'plan: docs/plans/foo.md\ncompleted: 1,2,3')"             "mid-implementation"
_assert_position "3d. with verification"  "$(printf 'plan: docs/plans/foo.md\ncompleted: 1,2\nverification: tests 47/47')" "post-verification"
_assert_position "3e. with docs-updated"  "$(printf 'verification: tests 47/47\ndocs-updated: README refreshed')"          "post-update-docs"
_assert_position "3f. with debug"         "$(printf 'debug: root cause -- stale cache')"                      "mid-debugging"
_assert_position "3g. empty string"       ""                                                                   "unknown"
_assert_position "3h. with planned-tasks" "$(printf 'plan: docs/plans/foo.md\nplanned-tasks: 5')"             "post-decomposition"
_assert_position "3i. planned-tasks before completed" "$(printf 'planned-tasks: 3\ncompleted: 1')"            "mid-implementation"
```

- [ ] **Step 3: Update Section 6d — cache test depends on 2b setup**

The cache test at 6d (line 573) runs the pre-change-gate twice. It previously used the mock from 2c (with tier in notes). After step 1, the mock from the new 2b (without tier) is active. The test logic is unchanged — it only checks consistent output between first and second call.

No code change needed, but verify the test still works after steps 1-2.

- [ ] **Step 4: Run the full behavioral test suite**

Run: `bash tests/test-behaviors.sh`
Expected: All tests pass, 0 failures

- [ ] **Step 5: Commit**

```bash
git add tests/test-behaviors.sh
git commit -m "test: remove tier-dependent assertions from behavioral tests"
```

---

### Task 11: Rewrite Scenario Tests

**Files:**
- Delete: `tests/scenarios/trivial.sh`
- Delete: `tests/scenarios/escalation.sh`
- Modify: `tests/scenarios/small.sh`
- Modify: `tests/scenarios/medium.sh`
- Modify: `tests/scenarios/medium-plus.sh`
- Modify: `tests/scenarios/init-persistence.sh`

- [ ] **Step 1: Delete tier-named scenarios that don't add value**

`trivial.sh` just commits a typo fix without TDD — that contradicts the new "full pipeline always" philosophy. Delete it.

`escalation.sh` tests tier escalation which no longer exists. Delete it.

```bash
rm tests/scenarios/trivial.sh tests/scenarios/escalation.sh
```

- [ ] **Step 2: Rename remaining scenarios to remove tier language**

The `small.sh`, `medium.sh`, and `medium-plus.sh` files are good TDD workflow tests — they demonstrate RED-GREEN cycles and sub-task decomposition. Rename them to reflect what they actually test:

```bash
git mv tests/scenarios/small.sh tests/scenarios/single-task-tdd.sh
git mv tests/scenarios/medium.sh tests/scenarios/multi-task-epic.sh
git mv tests/scenarios/medium-plus.sh tests/scenarios/blocked-dependencies.sh
```

- [ ] **Step 3: Update header comments in renamed files**

In `tests/scenarios/single-task-tdd.sh`, change:
```bash
echo "=== Small Tier: Add input validation ==="
```
To:
```bash
echo "=== Single Task TDD: Add input validation ==="
```

And change the final line from:
```bash
echo "=== Small Tier: PASS ==="
```
To:
```bash
echo "=== Single Task TDD: PASS ==="
```

In `tests/scenarios/multi-task-epic.sh`, change:
```bash
echo "=== Medium Tier: Multi-file feature ==="
```
To:
```bash
echo "=== Multi-Task Epic: Multi-file feature ==="
```

And the final line from:
```bash
echo "=== Medium Tier: PASS ==="
```
To:
```bash
echo "=== Multi-Task Epic: PASS ==="
```

In `tests/scenarios/blocked-dependencies.sh`, change:
```bash
echo "=== Medium+ Tier: Calculator operations ==="
```
To:
```bash
echo "=== Blocked Dependencies: Calculator operations ==="
```

And the final line from:
```bash
echo "=== Medium+ Tier: PASS ==="
```
To:
```bash
echo "=== Blocked Dependencies: PASS ==="
```

- [ ] **Step 4: Rewrite init-persistence.sh to test milestone notes without tier**

Replace the entire file with:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
echo "=== Init Persistence: Milestone notes ==="
# F18: No stale fallback — require scaffold.sh to have run
TEST_DIR=$(cat "${TMPDIR:-/tmp}/.workflow-test-dir-$(id -un)" 2>/dev/null || echo "")
if [ -z "$TEST_DIR" ] || [ ! -d "$TEST_DIR" ]; then echo "SKIP: No test directory (run scaffold.sh first)"; exit 0; fi
cd "$TEST_DIR"

# Create a task and add milestone notes (no tier)
TASK_ID=$(extract_id "$(bd create --title="Test milestone persistence" --type=task --priority=2 2>&1)")
bd update "$TASK_ID" --notes "spec: docs/superpowers/specs/test-spec.md"

# Verify spec was persisted
NOTES=$(bd show "$TASK_ID" 2>&1)
if echo "$NOTES" | grep -q "spec:"; then
    echo "  Spec milestone persisted: PASS"
else
    echo "  Spec milestone NOT in notes: FAIL"; exit 1
fi

# Add plan milestone (cumulative)
bd update "$TASK_ID" --notes "spec: docs/superpowers/specs/test-spec.md
plan: docs/superpowers/plans/test-plan.md, 3 tasks"

# Verify both milestones visible
NOTES=$(bd show "$TASK_ID" 2>&1)
if echo "$NOTES" | grep -q "plan:"; then
    echo "  Plan milestone persisted: PASS"
else
    echo "  Plan milestone NOT in notes: FAIL"; exit 1
fi
if echo "$NOTES" | grep -q "spec:"; then
    echo "  Spec preserved in cumulative update: PASS"
else
    echo "  Spec lost in cumulative update: FAIL"; exit 1
fi

bd close "$TASK_ID" --reason="Milestone persistence test"

echo "=== Init Persistence: PASS ==="
```

- [ ] **Step 5: Run all scenario tests**

Run: `bash tests/scenarios/scaffold.sh && bash tests/scenarios/single-task-tdd.sh && bash tests/scenarios/multi-task-epic.sh && bash tests/scenarios/blocked-dependencies.sh && bash tests/scenarios/init-persistence.sh && bash tests/scenarios/side-quest.sh && bash tests/scenarios/bug-path.sh`
Expected: all PASS

- [ ] **Step 6: Commit**

```bash
git add -A tests/scenarios/
git commit -m "test: rewrite scenario tests to remove tier language

Delete trivial.sh and escalation.sh (tier-specific).
Rename remaining scenarios to describe what they actually test.
Rewrite init-persistence.sh for milestone notes without tier."
```

---

### Task 12: Update validate-config.sh

**Files:**
- Modify: `tests/validate-config.sh`

- [ ] **Step 1: Remove `tier` from milestone keys check (Section 11)**

In line 216, change the milestone keys loop from:
```bash
    for key in "tier" "spec" "plan" "completed" "verification" "stopped" "active-skill"; do
```
To:
```bash
    for key in "spec" "plan" "completed" "verification" "stopped" "active-skill"; do
```

- [ ] **Step 2: Update expected count**

In lines 225-226, change from:
```bash
    if (( MILESTONE_KEYS_FOUND >= 7 )); then
        pass "workflow skill contains all $MILESTONE_KEYS_FOUND milestone keys"
```
To:
```bash
    if (( MILESTONE_KEYS_FOUND >= 6 )); then
        pass "workflow skill contains all $MILESTONE_KEYS_FOUND milestone keys"
```

And in line 228:
```bash
        fail "workflow skill has only $MILESTONE_KEYS_FOUND milestone keys (expected 7)"
```
To:
```bash
        fail "workflow skill has only $MILESTONE_KEYS_FOUND milestone keys (expected 6)"
```

- [ ] **Step 3: Run validation**

Run: `bash tests/validate-config.sh`
Expected: All checks pass

- [ ] **Step 4: Commit**

```bash
git add tests/validate-config.sh
git commit -m "test: remove tier from milestone validation in config checks"
```

---

### Task 13: Final Verification

**Files:** None (read-only verification)

- [ ] **Step 1: Grep entire project for stale tier references**

Run: `grep -rn 'tier' --include='*.md' --include='*.sh' --include='*.yaml' --include='*.json' . | grep -v 'docs/superpowers/specs/2026-04-10-workflow-v2-design.md' | grep -v 'docs/superpowers/plans/2026-04-10-workflow-v2.md' | grep -v 'docs/superpowers/specs/2026-04-10-remove-tiers-design.md' | grep -v 'docs/superpowers/plans/2026-04-10-remove-tiers.md' | grep -v '.beads/'`
Expected: no matches (historical spec/plan files excluded from search)

- [ ] **Step 2: Run full test suite**

Run: `bash tests/validate-config.sh && bash tests/test-behaviors.sh`
Expected: all pass

- [ ] **Step 3: Run scenario tests**

Run: `bash tests/scenarios/scaffold.sh && for f in tests/scenarios/single-task-tdd.sh tests/scenarios/multi-task-epic.sh tests/scenarios/blocked-dependencies.sh tests/scenarios/init-persistence.sh tests/scenarios/side-quest.sh tests/scenarios/bug-path.sh tests/scenarios/cleanup.sh; do bash "$f"; done`
Expected: all PASS

- [ ] **Step 4: Verify version consistency**

Run: `grep -r '2.3.0' .claude-plugin/ skills/ | head -10`
Expected: 4 matches — plugin.json, marketplace.json, start/SKILL.md, workflow/SKILL.md

Run: `grep -r '2.2.2' .claude-plugin/ skills/`
Expected: no matches (old version fully replaced)
