# `/analyze` Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `/claude-workstation:analyze` skill that auto-assesses task tier, creates beads tasks, and routes to the correct workflow skill — plus supporting hooks, rules, and setup updates.

**Architecture:** Pure Markdown skill (no scripts). Six weighted scoring dimensions described in prose that Claude evaluates at invocation time. Two new hooks (SessionStart, PreCompact) in hooks.json. Two new rule files (verification-template, beads-milestones) copied during setup. Workflow command updated with milestone annotations.

**Tech Stack:** Markdown (SKILL.md), JSON (hooks.json), Bash (setup/test scripts)

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `skills/analyze/SKILL.md` | Create | Core skill: parse args, score, assess tier, create beads task, route to first skill |
| `hooks/hooks.json` | Modify | Add SessionStart and PreCompact hooks alongside existing Stop hook |
| `rules/common/verification-template.md` | Create | Verification output format standard |
| `rules/common/beads-milestones.md` | Create | Milestone tracking rule for beads updates |
| `commands/workflow.md` | Modify | Add beads milestone annotations to Medium+ path |
| `skills/setup/SKILL.md` | Modify | Add copy steps for new rule files |
| `tests/validate-config.sh` | Modify | Add checks for new rule files |

---

### Task 1: Create the `/analyze` Skill

**Files:**
- Create: `skills/analyze/SKILL.md`

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p skills/analyze
```

- [ ] **Step 2: Write the SKILL.md file**

Create `skills/analyze/SKILL.md` with the full skill content:

```markdown
---
name: analyze
description: >
  Auto-assess task tier and start the right workflow. Takes a description,
  scores it, creates the beads task, and invokes the first skill.
  TRIGGER: When starting any new work, or when the user describes a task.
---

# Analyze: Auto-Tier Assessment & Workflow Routing

Takes a task description, assesses its complexity tier, creates the appropriate
beads task, and auto-invokes the first workflow skill for that tier.

## Invocation

The user provides a description and optional flags:

- `/claude-workstation:analyze "Add rate limiting to all API endpoints"`
- `/claude-workstation:analyze -p 0 "Critical production outage"`
- `/claude-workstation:analyze --side-quest "Found: tokens aren't rotated"`

## Flow

Execute these steps in order:

### Step 1: PARSE

Extract from arguments:
- **description**: The quoted task description
- **priority override**: `-p <0-4>` if provided (optional)
- **side-quest flag**: `--side-quest` if provided (optional)

### Step 2: CHECK FOR SIDE-QUEST

Before scoring, check if this is a side-quest. A side-quest is detected when ANY of:
- Description starts with "Found:" or "Discovered:"
- The `--side-quest` flag was passed
- There is an active in-progress beads task (check `bd list --status=in_progress`) AND the new description is unrelated to it

**If side-quest detected**, skip to the SIDE-QUEST FLOW below.

### Step 3: SCORE

Evaluate the description against six weighted dimensions. Score each 0.0-1.0, then compute the weighted sum.

#### Scoring Matrix

| Dimension | Weight | How to Score |
|---|---|---|
| **task_type** | 0.20 | Match signal words to type. `fix/bug/broken/error/crash` = bug (0.3). `add/create/implement/new` = feature (0.5). `refactor/rename/move/clean` = refactor (0.4). `design/system/migrate/architecture` = architecture (0.9). `docs/readme/config/typo/comment/format` = docs (0.1). If multiple match, use the highest. |
| **scope_keywords** | 0.25 | Check for breadth signals. `all/every/across/entire/global` = 1.0. `most/many/several` = 0.7. No breadth words = 0.2. |
| **domain_count** | 0.25 | Count distinct domains mentioned in the description: API, database, auth, frontend, backend, CI/CD, infrastructure, testing, security, config. 1 domain = 0.2. 2 domains = 0.5. 3+ domains = 1.0. |
| **change_signal** | 0.15 | Check magnitude words. `typo/tweak/bump/rename` = 0.1. `update/improve/enhance` = 0.4. `new system/new component/rewrite/overhaul` = 1.0. No magnitude words = 0.3. |
| **complexity_markers** | 0.05 | `step by step/multiple phases/depends on/coordination/integration` = 1.0. None = 0.0. |
| **forced_escalation** | 0.10 | Binary. Any of: security, architecture, migration, "new system", "new component" mentioned = 1.0. Otherwise = 0.0. |

Compute: `total = sum(dimension_score * weight for each dimension)`

#### Forced Escalation Override

After computing the total:
- If `forced_escalation` fired (1.0): minimum tier is **Small** regardless of total score.
- If `forced_escalation` fired AND `domain_count` score was 1.0 (3+ domains): minimum tier is **Medium+**.

#### Claude Override

You have freedom to override the numerical score when context clearly warrants it. The matrix is a guide, not a cage. If you know from project context that a seemingly small task actually spans many files, bump it up.

### Step 4: ASSESS

Map the final score to a tier:

| Score | Tier |
|---|---|
| < 0.25 | Trivial |
| 0.25 - 0.39 | Small |
| 0.40 - 0.50 | Borderline — bump to **Medium+** |
| > 0.50 | Medium+ |

### Step 5: CREATE

Create the beads task:

**Determine task type:**
- Trivial or Small: `--type=task`
- Medium+: `--type=epic`

**Determine priority** (if no `-p` override):
- Forced escalation fired (security, architecture): P1
- Medium+: P1
- Small: P2
- Trivial: P3

**Run:**
```bash
bd create --title="<description>" --type=<task|epic> -p <priority>
```

Then set it to in-progress:
```bash
bd update <task-id> -s in_progress
```

### Step 6: ROUTE

**Print the analysis output:**
```
📊 Analysis: "<description>"
   Type: <task_type> | Scope: <domains> (<domain_count> domains)
   Score: <total> → <tier>

   ✓ Created: <task-id> (<type>, P<priority>)
   → Starting: <next skill>
```

**Then auto-invoke the first skill for the tier:**

| Tier | Action |
|---|---|
| Trivial | Print: "Go fix it. Then verify and `bd close <task-id>`." Do NOT invoke any skill. |
| Small | Invoke: `/superpowers:test-driven-development` |
| Medium+ | Invoke: `/superpowers:brainstorming` |

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

3. **Link it:**
   ```bash
   bd dep add <new-task-id> <current-task-id> --type=discovered-from
   ```

4. **Print output:**
   ```
   📊 Analysis: "<description>"
      Detected: Side-quest (current task: <current-task-id>)

      ✓ Created: <new-task-id> (bug, P<priority>)
      ✓ Linked: <new-task-id> discovered-from <current-task-id>
      → Parked. Finish current task first, then bd ready.
   ```

5. **Do NOT invoke any skill.** Return control to the user to continue current work.
```

- [ ] **Step 3: Verify the skill file is well-formed**

Read the created file and confirm:
- The YAML frontmatter has `name: analyze` and a `description` field
- All six scoring dimensions are present with correct weights summing to 1.00
- The tier mapping table has all four rows (< 0.25, 0.25-0.39, 0.40-0.50, > 0.50)
- The routing table has all three tiers
- The side-quest flow section is present

- [ ] **Step 4: Commit**

```bash
git add skills/analyze/SKILL.md
git commit -m "feat: add /analyze skill for auto-tier assessment and workflow routing"
```

---

### Task 2: Add SessionStart and PreCompact Hooks

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Read the current hooks.json**

Current content has only a `Stop` hook:

```json
{
  "hooks": {
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

- [ ] **Step 2: Add SessionStart and PreCompact hooks**

Replace the entire file with the updated version that adds both new hooks before the existing Stop hook:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bd prime 2>/dev/null || true"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bd prime 2>/dev/null || true"
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

- [ ] **Step 3: Validate JSON**

```bash
python3 -c "import json; json.load(open('hooks/hooks.json')); print('Valid JSON')"
```

Expected: `Valid JSON`

- [ ] **Step 4: Verify hooks are safe in non-beads projects**

```bash
bash -c 'bd prime 2>/dev/null || true'
echo "Exit code: $?"
```

Expected: Exit code 0 (graceful no-op or beads output)

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: add SessionStart and PreCompact hooks for beads state persistence"
```

---

### Task 3: Create Verification Template Rule

**Files:**
- Create: `rules/common/verification-template.md`

- [ ] **Step 1: Create the rule file**

Create `rules/common/verification-template.md`:

```markdown
# Verification Output Template

When running `/superpowers:verification-before-completion`, produce output in this
standardized format and append it to the beads task notes.

## Template

```
## Verification: <beads-task-id>
- Tests:  <status> <count> passed, <count> failed (exit <code>)
- Build:  <status> <message> (exit <code>)
- Lint:   <status> <message> (exit <code>)
- Type:   <status> <message> (exit <code>)
- Manual: <status> <description of what was checked>
```

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

- [ ] **Step 2: Verify the file exists and has key content**

```bash
grep -c "Verification" rules/common/verification-template.md
grep -c "BLOCKING" rules/common/verification-template.md
grep -c "exit" rules/common/verification-template.md
```

Expected: Each returns at least 1.

- [ ] **Step 3: Commit**

```bash
git add rules/common/verification-template.md
git commit -m "feat: add verification output template rule"
```

---

### Task 4: Create Beads Milestones Rule

**Files:**
- Create: `rules/common/beads-milestones.md`

- [ ] **Step 1: Create the rule file**

Create `rules/common/beads-milestones.md`:

```markdown
# Beads Milestone Updates

After completing each workflow milestone, update the beads task so progress
survives session crashes and context compaction.

## When to Update

- After brainstorming: note the spec path and key design decisions
- After writing a plan: note the plan path and number of sub-tasks
- After each sub-task TDD cycle: note what was implemented and that tests pass
- After verification: append the verification output block
- At session end: note where you stopped and what's next

## How to Update

```
bd update <id> --notes "<milestone>: <path-or-summary>"
```

## Examples

```
bd update claude-workstation-x7k --notes "Spec: docs/superpowers/specs/2026-04-05-analyze-design.md"
bd update claude-workstation-x7k --notes "Plan: docs/superpowers/plans/2026-04-05-analyze.md, 7 tasks"
bd update claude-workstation-r3m --notes "Tests passing: auth validation, 4 tests green"
bd update claude-workstation-x7k --notes "Stopped at: Task 5 of 7 complete, resuming with Task 6 (setup updates)"
```

## What NOT to Do

- Don't update after every micro-step (each brainstorming question, each test run)
- Don't duplicate the full spec/plan content — just reference the file path
- Don't update if nothing meaningful changed since last update
```

- [ ] **Step 2: Verify the file exists and has key content**

```bash
grep -c "Milestone" rules/common/beads-milestones.md
grep -c "bd update" rules/common/beads-milestones.md
grep -c "NOT to Do" rules/common/beads-milestones.md
```

Expected: Each returns at least 1.

- [ ] **Step 3: Commit**

```bash
git add rules/common/beads-milestones.md
git commit -m "feat: add beads milestone tracking rule"
```

---

### Task 5: Update Workflow Command with Milestone Annotations

**Files:**
- Modify: `commands/workflow.md`

- [ ] **Step 1: Read the current workflow.md**

The current Medium+ path (lines 59-82) looks like:

```
## Medium+ Path

```
1. EPIC       bd create --title="..." --type=epic
2. BRAINSTORM superpowers:brainstorming
               Output: design doc in docs/superpowers/specs/
3. PLAN       superpowers:writing-plans
               Output: plan in docs/superpowers/plans/
4. SUB-TASKS  For each plan step:
               bd create --title="Step N: ..." --type=task
               bd dep add <sub-id> <epic-id>
               bd dep add <sub-id> <prev-sub-id>  (if sequential)
5. ISOLATE    superpowers:using-git-worktrees
6. IMPLEMENT  bd ready → pick next → bd update <id> --claim
               For each sub-task:
               ├─ superpowers:test-driven-development
               ├─ Commit after each green
               ├─ superpowers:requesting-code-review
               └─ bd close <sub-id>
               Repeat until bd ready shows no more sub-tasks.
7. VERIFY     superpowers:verification-before-completion
8. FINISH     superpowers:finishing-a-development-branch
9. CLOSE      bd close <epic-id>
```
```

- [ ] **Step 2: Replace the Medium+ path with milestone-annotated version**

Replace the Medium+ path code block (the block between the triple backticks under `## Medium+ Path`) with:

```
1. EPIC       bd create --title="..." --type=epic
2. BRAINSTORM superpowers:brainstorming
               Output: design doc in docs/superpowers/specs/
               bd update <epic-id> --notes "Spec: <path>"
3. PLAN       superpowers:writing-plans
               Output: plan in docs/superpowers/plans/
               bd update <epic-id> --notes "Plan: <path>, N sub-tasks"
4. SUB-TASKS  For each plan step:
               bd create --title="Step N: ..." --type=task
               bd dep add <sub-id> <epic-id>
               bd dep add <sub-id> <prev-sub-id>  (if sequential)
5. ISOLATE    superpowers:using-git-worktrees
6. IMPLEMENT  bd ready → pick next → bd update <sub-id> -s in_progress
               For each sub-task:
               ├─ superpowers:test-driven-development
               ├─ Commit after each green
               ├─ bd update <sub-id> --notes "Tests passing: <summary>"
               ├─ superpowers:requesting-code-review
               └─ bd close <sub-id>
               Repeat until bd ready shows no more sub-tasks.
7. VERIFY     superpowers:verification-before-completion
8. FINISH     superpowers:finishing-a-development-branch
9. CLOSE      bd close <epic-id>
```

Key changes from the original:
- Step 2: Added `bd update <epic-id> --notes "Spec: <path>"` after brainstorming output
- Step 3: Added `bd update <epic-id> --notes "Plan: <path>, N sub-tasks"` after plan output
- Step 6: Changed `bd update <id> --claim` to `bd update <sub-id> -s in_progress`
- Step 6: Added `bd update <sub-id> --notes "Tests passing: <summary>"` after green commits

- [ ] **Step 3: Add a note about /analyze as an alternative entry point**

After the `## Step Zero: Create a Beads Task` section (after line 16), add:

```markdown
**Or use `/claude-workstation:analyze`** to auto-assess the tier, create the task, and start the right flow in one step.
```

- [ ] **Step 4: Verify the changes**

```bash
grep -c "bd update" commands/workflow.md
grep -c "analyze" commands/workflow.md
```

Expected: `bd update` appears at least 4 times. `analyze` appears at least 1 time.

- [ ] **Step 5: Commit**

```bash
git add commands/workflow.md
git commit -m "feat: add beads milestone annotations and /analyze reference to workflow"
```

---

### Task 6: Update Setup Skill to Copy New Rule Files

**Files:**
- Modify: `skills/setup/SKILL.md`

- [ ] **Step 1: Read the current Step 3 in setup**

The current Step 3 copies three files:

```bash
for file in unified-workflow.md plugin-routing.md development-workflow.md; do
```

- [ ] **Step 2: Add the two new rule files to the copy loop**

Replace the loop line in Step 3:

```bash
for file in unified-workflow.md plugin-routing.md development-workflow.md; do
```

with:

```bash
for file in unified-workflow.md plugin-routing.md development-workflow.md verification-template.md beads-milestones.md; do
```

This adds `verification-template.md` and `beads-milestones.md` to the existing copy loop. The rest of the loop logic (skip-if-newer, source/destination paths) remains the same.

- [ ] **Step 3: Verify the change**

```bash
grep "verification-template.md" skills/setup/SKILL.md
grep "beads-milestones.md" skills/setup/SKILL.md
```

Expected: Both return a match.

- [ ] **Step 4: Commit**

```bash
git add skills/setup/SKILL.md
git commit -m "feat: add verification-template and beads-milestones to setup copy list"
```

---

### Task 7: Update Validation Script for New Rule Files

**Files:**
- Modify: `tests/validate-config.sh`

- [ ] **Step 1: Read the current file existence checks**

The current section 1 (lines 14-42) checks for these files:
- `unified-workflow.md`
- `plugin-routing.md`
- `development-workflow.md`
- `context7.md`
- `dev.md`, `research.md`, `review.md` contexts
- `settings.json`

- [ ] **Step 2: Add checks for the two new rule files**

After the `development-workflow.md` check (after line 26), add:

```bash
[[ -f "$HOME/.claude/rules/common/verification-template.md" ]] \
    && pass "verification-template.md exists" \
    || fail "verification-template.md MISSING (run /claude-workstation:setup)"

[[ -f "$HOME/.claude/rules/common/beads-milestones.md" ]] \
    && pass "beads-milestones.md exists" \
    || fail "beads-milestones.md MISSING (run /claude-workstation:setup)"
```

- [ ] **Step 3: Add a content check for verification-template**

In section 7 (content completeness), after the unified-workflow keyword checks (after line 146), add a new section:

```bash
echo "8. Content completeness (verification template)"

for keyword in "Verification" "BLOCKING" "exit" "bd update"; do
    if grep -q "$keyword" "$HOME/.claude/rules/common/verification-template.md" 2>/dev/null; then
        pass "verification-template.md contains '$keyword'"
    else
        fail "verification-template.md MISSING '$keyword'"
    fi
done

echo ""
```

Note: This shifts the existing "8. Shell aliases" section to "9. Shell aliases". Update the echo label:

```bash
echo "9. Shell aliases"
```

- [ ] **Step 4: Verify the script still runs without errors**

```bash
bash tests/validate-config.sh 2>&1 | tail -5
```

Expected: Script runs, shows summary. Some checks may fail (new rule files not yet copied to `~/.claude/rules/common/`) — that's expected until setup is re-run.

- [ ] **Step 5: Commit**

```bash
git add tests/validate-config.sh
git commit -m "feat: add validation checks for verification-template and beads-milestones rules"
```

---

### Task 8: Integration Test — Run Setup and Validate

**Files:**
- No file changes — this is a verification task

- [ ] **Step 1: Run the setup skill to copy new files**

The setup skill will now copy `verification-template.md` and `beads-milestones.md` to `~/.claude/rules/common/`. Run the copy commands manually:

```bash
cp rules/common/verification-template.md "$HOME/.claude/rules/common/verification-template.md"
cp rules/common/beads-milestones.md "$HOME/.claude/rules/common/beads-milestones.md"
echo "Copied both rule files"
```

- [ ] **Step 2: Run the validation script**

```bash
bash tests/validate-config.sh
```

Expected: All checks pass, including the new file existence and content checks.

- [ ] **Step 3: Verify hooks.json is valid and contains all three hook types**

```bash
python3 -c "
import json
d = json.load(open('hooks/hooks.json'))
hooks = d.get('hooks', {})
for h in ['SessionStart', 'PreCompact', 'Stop']:
    if h in hooks:
        print(f'OK: {h} hook present')
    else:
        print(f'MISSING: {h} hook')
"
```

Expected: All three hooks present.

- [ ] **Step 4: Verify the analyze skill is discoverable**

```bash
test -f skills/analyze/SKILL.md && echo "OK: analyze skill exists" || echo "MISSING: analyze skill"
head -5 skills/analyze/SKILL.md
```

Expected: File exists, shows YAML frontmatter with `name: analyze`.

- [ ] **Step 5: Update beads with plan completion**

```bash
bd update claude-workstation-l4i --notes "Plan: docs/superpowers/plans/2026-04-05-analyze-command.md, 8 tasks. Implementation ready."
```
