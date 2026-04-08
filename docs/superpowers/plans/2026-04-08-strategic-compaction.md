# Strategic Compaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Strategic Compaction" section to workflow.md so agents invoke `ecc:strategic-compact` at four phase boundaries and save context to beads before compacting.

**Architecture:** Single rule addition to `contexts/workflow.md` (always-injected workflow context), validated by behavioral test guards and config validation keyword check.

**Tech Stack:** Bash (tests), Markdown (workflow context)

---

### Task 1: Add behavioral test guard for strategic compaction content

**Files:**
- Modify: `tests/test-behaviors.sh:588-642` (Section 7: workflow.md inlined content guards)

- [ ] **Step 1: Add test 7g to Section 7**

Append after the `7f. spike phase` check (line 641), before the closing `echo ""` (line 643):

```bash
# 7g. Strategic compaction section present
if grep -q 'Strategic Compaction' "$WORKFLOW_FILE" 2>/dev/null && \
   grep -q 'ecc:strategic-compact' "$WORKFLOW_FILE" 2>/dev/null && \
   grep -q 'spec:' "$WORKFLOW_FILE" 2>/dev/null && \
   grep -q 'plan:' "$WORKFLOW_FILE" 2>/dev/null && \
   grep -q 'debug:' "$WORKFLOW_FILE" 2>/dev/null && \
   grep -q 'scope-health' "$WORKFLOW_FILE" 2>/dev/null; then
    pass "7g. strategic compaction section with trigger points in workflow.md"
else
    fail "7g. strategic compaction section missing or incomplete in workflow.md"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `CLAUDE_PLUGIN_ROOT=/home/igi21/work/claude-workstation bash /home/igi21/work/claude-workstation/tests/test-behaviors.sh 2>&1 | grep '7g\.'`

Expected: `❌ 7g. strategic compaction section missing or incomplete in workflow.md`

- [ ] **Step 3: Commit failing test**

```bash
git add tests/test-behaviors.sh
git commit -m "test: add behavioral guard for strategic compaction in workflow.md"
```

---

### Task 2: Add config validation keyword for Strategic Compaction

**Files:**
- Modify: `tests/validate-config.sh:67` (Section 4: Workflow context content keyword list)

- [ ] **Step 1: Add "Strategic Compaction" to keyword list**

Change the keyword list on line 67 from:

```bash
for keyword in "Beads-First" "Task Sizing" "Plugin Routing" "Side Quests" "Spec Amendments" "Micro-tiers" "Scope Confirmation" "Pre-Change Gate" "Hard Rules" "Milestone Notes" "Verification Format" "Spike Phase" "Scope Health" "Debugging"; do
```

to:

```bash
for keyword in "Beads-First" "Task Sizing" "Plugin Routing" "Side Quests" "Spec Amendments" "Micro-tiers" "Scope Confirmation" "Pre-Change Gate" "Hard Rules" "Milestone Notes" "Verification Format" "Spike Phase" "Scope Health" "Debugging" "Strategic Compaction"; do
```

- [ ] **Step 2: Run test to verify it fails**

Run: `CLAUDE_PLUGIN_ROOT=/home/igi21/work/claude-workstation bash /home/igi21/work/claude-workstation/tests/validate-config.sh 2>&1 | grep -i 'strategic'`

Expected: `❌ workflow.md MISSING 'Strategic Compaction'`

- [ ] **Step 3: Commit failing test**

```bash
git add tests/validate-config.sh
git commit -m "test: add Strategic Compaction to workflow.md keyword validation"
```

---

### Task 3: Add Strategic Compaction section to workflow.md

**Files:**
- Modify: `contexts/workflow.md:62-63` (insert after Scope Health, before Verification Format)

- [ ] **Step 1: Insert the Strategic Compaction section**

After line 62 (end of Scope Health section), before line 64 (`## Verification Format`), insert:

```markdown

## Strategic Compaction

At these phase boundaries, invoke `ecc:strategic-compact` to assess context consumption:
- After `spec:` milestone (brainstorming complete)
- After `plan:` milestone (planning complete)
- After `debug:` milestone (root cause found)
- During scope-health check (every 3rd closed sub-task)

If strategic-compact recommends compaction: (1) write any unrecorded decisions, context, or insights to beads notes via `bd-notes-append` -- anything that lives only in conversation and wouldn't survive compaction, (2) log `stopped: pre-compact -- <phase>`, (3) proceed with compaction.
```

- [ ] **Step 2: Run behavioral test to verify it passes**

Run: `CLAUDE_PLUGIN_ROOT=/home/igi21/work/claude-workstation bash /home/igi21/work/claude-workstation/tests/test-behaviors.sh 2>&1 | grep '7g\.'`

Expected: `✅ 7g. strategic compaction section with trigger points in workflow.md`

- [ ] **Step 3: Run config validation to verify it passes**

Run: `CLAUDE_PLUGIN_ROOT=/home/igi21/work/claude-workstation bash /home/igi21/work/claude-workstation/tests/validate-config.sh 2>&1 | grep -i 'strategic'`

Expected: `✅ workflow.md contains 'Strategic Compaction'`

- [ ] **Step 4: Run full test suites to verify no regressions**

Run: `CLAUDE_PLUGIN_ROOT=/home/igi21/work/claude-workstation bash /home/igi21/work/claude-workstation/tests/test-behaviors.sh 2>&1 | tail -5`

Expected: `✅ All behavioral tests passed`

Run: `CLAUDE_PLUGIN_ROOT=/home/igi21/work/claude-workstation bash /home/igi21/work/claude-workstation/tests/validate-config.sh 2>&1 | tail -5`

Expected: `✅ All checks passed`

- [ ] **Step 5: Commit implementation**

```bash
git add contexts/workflow.md
git commit -m "feat: add strategic compaction at phase boundaries"
```
