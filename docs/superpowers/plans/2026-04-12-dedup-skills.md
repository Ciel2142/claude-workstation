# Deduplicate Workflow/Orchestrator/Agent-Roles/Start/CLAUDE.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate content duplication across five plugin files by establishing distributed ownership with rigid reference pointers, and delete the `start` skill (absorbed into workflow).

**Architecture:** Each skill owns its domain concepts. Cross-references use a rigid format that forces agents to read the source file. The `start` skill is deleted — its side-quest detection heuristic moves to workflow, and task creation is trivial (`bd create`).

**Tech Stack:** Bash (shell scripts), Markdown (skills/docs), Python (validate-config.sh assertions)

---

### Task 1: Shrink CLAUDE.md to pointers-only

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write the failing test**

Add assertion to `tests/validate-config.sh` in section 11g. The existing size check (`< 3500` bytes) stays. Add a new check that CLAUDE.md contains `RIGID REF`:

```bash
# After the existing 11g size check, add:
if grep -q "RIGID REF" "$CLAUDE_MD" 2>/dev/null; then
    pass "CLAUDE.md contains RIGID REF pointers"
else
    fail "CLAUDE.md MISSING RIGID REF pointers"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/validate-config.sh 2>&1 | grep -E "RIGID REF"`
Expected: FAIL — current CLAUDE.md has no RIGID REF pointers.

- [ ] **Step 3: Replace CLAUDE.md content**

Replace the entire CLAUDE.md with:

```markdown
## Workflow: Beads + Superpowers + ECC

New task: `bd create --title="..." --type=task` then brainstorm or plan.
Reference: `/claude-workstation:workflow`
Orchestrator: `/claude-workstation:orchestrator`

> **RIGID REF:** Read `skills/workflow/SKILL.md` for hard rules, milestones,
> enforcement hooks, side-quest detection, and session recovery.
> Do not act on these from memory.

> **RIGID REF:** Read `skills/agent-roles/SKILL.md` § "How to use" before
> dispatching any subagent. Do not act on role mapping from memory.

### Prerequisites

Install per plugin docs:
- [Beads](https://github.com/steveyegge/beads) -- task tracking
- [Superpowers](https://github.com/obra/superpowers) -- dev methodology
- [ECC](https://github.com/affaan-m/everything-claude-code) -- domain expertise

### Caveman Mode Rules

Default: **lite**. Code/commits/security: always normal.
Escalate to **full** for: beads ops (responses + note content), pre-compaction context.
Beads titles/descriptions: stay **normal** (human-scannable).

**Pre-compaction** (when `/ecc:strategic-compact` suggests, and safe):
1. Identify essential context not yet in beads
2. Compress via caveman full → `bd update <id> --notes "..."`
3. Then compact
```

- [ ] **Step 4: Update validate-config.sh section 5 (session-start content checks)**

Lines 107-108 check for `Quick Reference` and `Hard Rules` in session-start output. After CLAUDE.md shrinks, `Quick Reference` is gone. `Hard Rules` is gone. Update to check for content that WILL be in the new CLAUDE.md:

Replace:
```python
assert 'Quick Reference' in ctx, 'Quick Reference missing from escaped content'
assert 'Hard Rules' in ctx, 'Hard Rules missing from escaped content'
```

With:
```python
assert 'RIGID REF' in ctx, 'RIGID REF missing from escaped content'
assert 'workflow/SKILL.md' in ctx, 'workflow reference missing from escaped content'
```

- [ ] **Step 5: Update validate-config.sh section 15e (session-start content functional check)**

Line 352 checks for `Quick Reference` in session-start output. After CLAUDE.md shrink, this text is gone. Update:

Replace:
```bash
if echo "$SESSION_OUT" | grep -q "Quick Reference"; then
    pass "session-start injects CLAUDE.md content (functional)"
else
    fail "session-start does NOT inject CLAUDE.md content (functional)"
fi
```

With:
```bash
if echo "$SESSION_OUT" | grep -q "RIGID REF"; then
    pass "session-start injects CLAUDE.md content (functional)"
else
    fail "session-start does NOT inject CLAUDE.md content (functional)"
fi
```

- [ ] **Step 6: Update validate-config.sh section 23 (enforcement documentation)**

Lines 572-578 check CLAUDE.md for hard rules text. After dedup, hard rules live in workflow only. Update the check targets:

Replace the section 23 CLAUDE.md hard-rule checks:
```bash
# Hard rules now live in workflow, CLAUDE.md has RIGID REF pointers
for rule in "RIGID REF" "workflow/SKILL.md" "agent-roles/SKILL.md" "strategic-compact"; do
    if grep -q "$rule" "$CLAUDE_MD" 2>/dev/null; then
        pass "CLAUDE.md contains: '$rule'"
    else
        fail "CLAUDE.md MISSING: '$rule'"
    fi
done
```

- [ ] **Step 7: Update validate-config.sh section 12.7 (enforcement hooks reference)**

Line 716 checks for `milestone-gate` and `agent-roles` in CLAUDE.md. After dedup, CLAUDE.md won't mention `milestone-gate` directly — it points to workflow. Update:

Replace:
```bash
if grep -q "milestone-gate" "$PLUGIN_ROOT/CLAUDE.md" && grep -q "agent-roles" "$PLUGIN_ROOT/CLAUDE.md"; then
    pass "12.7 CLAUDE.md contains enforcement hooks + agent-roles reference"
else
    fail "12.7 CLAUDE.md missing enforcement hooks reference"
fi
```

With:
```bash
if grep -q "RIGID REF" "$PLUGIN_ROOT/CLAUDE.md" && grep -q "agent-roles" "$PLUGIN_ROOT/CLAUDE.md"; then
    pass "12.7 CLAUDE.md contains RIGID REF pointers + agent-roles reference"
else
    fail "12.7 CLAUDE.md missing RIGID REF pointers"
fi
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bash tests/validate-config.sh`
Expected: All checks pass.

- [ ] **Step 9: Commit**

```bash
git add CLAUDE.md tests/validate-config.sh
git commit -m "refactor: shrink CLAUDE.md to pointers-only with RIGID REF format"
```

---

### Task 2: Strip duplicated sections from workflow, absorb side-quest detection

**Files:**
- Modify: `skills/workflow/SKILL.md`

- [ ] **Step 1: Write the failing test**

Update `tests/validate-config.sh` section 12.8. Currently checks for `Subagent Protocol` in workflow. After dedup, workflow will have `RIGID REF` instead of the full section. Update the check:

Replace:
```bash
if grep -q "tdd:red-verified" "$PLUGIN_ROOT/skills/workflow/SKILL.md" && grep -q "Subagent Protocol" "$PLUGIN_ROOT/skills/workflow/SKILL.md"; then
    pass "12.8 Workflow SKILL.md contains milestone chain + subagent protocol"
else
    fail "12.8 Workflow SKILL.md missing enforcement sections"
fi
```

With:
```bash
if grep -q "tdd:red-verified" "$PLUGIN_ROOT/skills/workflow/SKILL.md" && grep -q "RIGID REF" "$PLUGIN_ROOT/skills/workflow/SKILL.md"; then
    pass "12.8 Workflow SKILL.md contains milestone chain + RIGID REF pointers"
else
    fail "12.8 Workflow SKILL.md missing enforcement sections"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/validate-config.sh 2>&1 | grep "12.8"`
Expected: FAIL — current workflow has `Subagent Protocol` but no `RIGID REF`.

- [ ] **Step 3: Replace § Subagent Protocol (lines 167-180)**

Replace the full "Subagent Protocol" section (from `## Subagent Protocol` through the `BEAD-ROLE:default` paragraph) with:

```markdown
## Subagent Protocol

> **RIGID REF:** Read `skills/agent-roles/SKILL.md` for role-to-template
> mapping before dispatching any subagent. Do not act from memory.
```

- [ ] **Step 4: Replace § Orchestrator Protocol (lines 184-196)**

Replace the full "Orchestrator Protocol" section (from `## Orchestrator Protocol` through `follows the same rules.`) with:

```markdown
## Orchestrator Protocol

> **RIGID REF:** Read `skills/orchestrator/SKILL.md` for the full rigid
> dispatch loop. Do not act on orchestrator rules from memory.
```

- [ ] **Step 5: Expand § Side Quests (lines 199-205)**

Replace the "Side Quests" section with the expanded version that absorbs start's detection heuristic:

```markdown
## Side Quests

Problem outside confirmed scope — even if your change caused it.

**Detection** — new work is a side-quest when ANY of:
- Description starts with "Found:" or "Discovered:"
- User explicitly flags it
- Active in-progress task exists AND new work touches files not in current task's description/plan

**Creation:**
```bash
bd create --title="Found: <issue>" --type=bug
bd dep add <new-id> <current-id> --type=discovered-from
```

Finish current task first, then `bd ready` for parked issue. Fix size doesn't reduce ceremony.

For automated side-quests during orchestration (review findings), see
`skills/orchestrator/SKILL.md` § "ANALYZE SPEC REVIEW REPORT".
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/validate-config.sh`
Expected: All checks pass. Section 4 still finds "Side Quests". Section 12.8 finds `RIGID REF`.

- [ ] **Step 7: Commit**

```bash
git add skills/workflow/SKILL.md tests/validate-config.sh
git commit -m "refactor: strip duplicated sections from workflow, absorb side-quest detection"
```

---

### Task 3: Delete start skill

**Files:**
- Delete: `skills/start/SKILL.md`, `skills/start/` directory
- Delete: `tests/specs/start.yaml`
- Modify: `tests/validate-config.sh` (remove start from skill checks)
- Modify: `README.md` (remove start references)

- [ ] **Step 1: Update validate-config.sh — remove start from skill directory checks**

Section 8 (line 150): Remove `start` from the skill_dir loop:

Replace:
```bash
for skill_dir in start workflow task-scaffolder orchestrator agent-roles; do
```

With:
```bash
for skill_dir in workflow task-scaffolder orchestrator agent-roles; do
```

Section 9 (line 163): Same change:

Replace:
```bash
for skill_dir in start workflow task-scaffolder orchestrator agent-roles; do
```

With:
```bash
for skill_dir in workflow task-scaffolder orchestrator agent-roles; do
```

- [ ] **Step 2: Update validate-config.sh — remove start from behavioral spec checks**

Section 24 (line 602): Remove `start` from spec_name loop:

Replace:
```bash
for spec_name in bd-notes-append scope-health start task-scaffolder orchestrator; do
```

With:
```bash
for spec_name in bd-notes-append scope-health task-scaffolder orchestrator; do
```

- [ ] **Step 3: Update validate-config.sh section 15e — session-start content check**

Line 352 checks for `Quick Reference` in session-start output. After CLAUDE.md shrink (Task 1), this is already fixed by Step 4 of Task 1. Verify no additional changes needed here.

Run: `bash tests/validate-config.sh 2>&1 | grep "15e\|session-start"`
Expected: Pass (already fixed in Task 1).

- [ ] **Step 4: Delete start skill directory**

```bash
rm -rf skills/start/
```

- [ ] **Step 5: Delete start behavioral spec**

```bash
rm tests/specs/start.yaml
```

- [ ] **Step 6: Update README.md — remove start references**

Remove from "What's Included" list (line 9):
```markdown
- **Task Kickoff** -- `/start` creates a beads task and routes to brainstorming or planning
```

Remove from "Commands & Skills" table (line 53):
```markdown
| `/claude-workstation:start` | Create beads task and choose workflow entry (brainstorm or plan) |
```

Remove the entire "### `/start` — Begin New Work" section (lines 59-70).

Update project structure (line 96): Remove the start line:
```markdown
│   ├── start/SKILL.md         # /start -- task creation & workflow entry
```

Update "What's Included" to reflect new entry point:
```markdown
- **Task Kickoff** -- `bd create` + brainstorm or plan (no separate skill needed)
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bash tests/validate-config.sh`
Expected: All checks pass. No references to start skill remain in test assertions.

- [ ] **Step 8: Commit**

```bash
git add -A tests/validate-config.sh README.md
git commit -m "refactor: delete start skill, update tests and README"
```

---

### Task 4: Version bump 2.6.0 → 2.7.0

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `skills/workflow/SKILL.md` (frontmatter)
- Modify: `skills/orchestrator/SKILL.md` (frontmatter)
- Modify: `skills/agent-roles/SKILL.md` (frontmatter)
- Modify: `skills/task-scaffolder/SKILL.md` (frontmatter)

- [ ] **Step 1: Bump plugin.json**

In `.claude-plugin/plugin.json`, replace:
```json
"version": "2.6.0"
```
With:
```json
"version": "2.7.0"
```

- [ ] **Step 2: Bump marketplace.json**

In `.claude-plugin/marketplace.json`, replace:
```json
"version": "2.6.0"
```
With:
```json
"version": "2.7.0"
```

- [ ] **Step 3: Bump all SKILL.md frontmatter**

For each skill file (`skills/*/SKILL.md`), replace:
```yaml
version: 2.6.0
```
With:
```yaml
version: 2.7.0
```

Files: `skills/workflow/SKILL.md`, `skills/orchestrator/SKILL.md`, `skills/agent-roles/SKILL.md`, `skills/task-scaffolder/SKILL.md`.

Note: `skills/start/SKILL.md` is already deleted in Task 3.

- [ ] **Step 4: Run version consistency check**

Run: `bash tests/validate-config.sh 2>&1 | grep -E "version|13b"`
Expected: All skill versions match plugin version 2.7.0.

- [ ] **Step 5: Run full test suite**

Run: `bash tests/validate-config.sh`
Expected: All checks pass.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json skills/*/SKILL.md
git commit -m "chore: bump version to 2.7.0"
```

---

### Task 5: Final validation

**Files:**
- None modified — validation only

- [ ] **Step 1: Run full validate-config.sh**

Run: `bash tests/validate-config.sh`
Expected: All checks pass, 0 failures.

- [ ] **Step 2: Run behavioral tests**

Run: `bash tests/test-behaviors.sh`
Expected: All behavioral tests pass.

- [ ] **Step 3: Verify start skill is fully removed**

```bash
# No references to /claude-workstation:start in any skill or config
grep -r "claude-workstation:start" skills/ hooks/ CLAUDE.md README.md tests/ || echo "CLEAN"

# No start directory exists
ls skills/start/ 2>&1 || echo "DELETED"

# No start.yaml spec exists
ls tests/specs/start.yaml 2>&1 || echo "DELETED"
```

Expected: "CLEAN", "DELETED", "DELETED"

- [ ] **Step 4: Verify CLAUDE.md is lean**

```bash
wc -c CLAUDE.md
# Expected: < 1500 bytes (was ~3000)
```

- [ ] **Step 5: Verify no orphaned cross-references**

```bash
# Check no skill references start skill
grep -r "skills/start" skills/ CLAUDE.md hooks/ || echo "CLEAN"

# Check workflow has RIGID REF pointers
grep -c "RIGID REF" skills/workflow/SKILL.md
# Expected: 2 (agent-roles + orchestrator)

# Check CLAUDE.md has RIGID REF pointers
grep -c "RIGID REF" CLAUDE.md
# Expected: 2 (workflow + agent-roles)
```
