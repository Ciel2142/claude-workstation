# Medium Tier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Medium" tier between Small and Medium+ for multi-file tasks that don't need brainstorming or spike evaluation.

**Architecture:** Extends the existing tier system across 9 files. Tests written first (RED), then source files updated (GREEN). No new dependencies — pure markdown/shell changes.

**Tech Stack:** Bash (tests, hooks), Markdown (skills, contexts, docs)

**Spec:** `docs/superpowers/specs/2026-04-08-medium-tier-design.md`

---

### Task 1: RED — Position detection tests (test-behaviors.sh)

**Files:**
- Modify: `tests/test-behaviors.sh:296-337`

- [ ] **Step 1: Update detect_position() to add planned-tasks check**

In `tests/test-behaviors.sh`, the `detect_position()` function (line 296-314) mirrors resume/SKILL.md position detection. Add `planned-tasks:` check between `completed:` and `plan:`:

```bash
detect_position() {
    local notes="$1"
    if echo "$notes" | grep -q 'docs-updated:'; then
        echo "post-update-docs"
    elif echo "$notes" | grep -q 'verification:'; then
        echo "post-verification"
    elif echo "$notes" | grep -q 'completed:'; then
        echo "mid-implementation"
    elif echo "$notes" | grep -q 'planned-tasks:'; then
        echo "post-decomposition"
    elif echo "$notes" | grep -q 'plan:'; then
        echo "post-planning"
    elif echo "$notes" | grep -q 'spec:'; then
        echo "post-brainstorming"
    elif echo "$notes" | grep -q 'debug:'; then
        echo "mid-debugging"
    elif echo "$notes" | grep -q 'tier:'; then
        echo "start"
    else
        echo "unknown"
    fi
}
```

- [ ] **Step 2: Add post-decomposition test case**

After line 337 (`_assert_position "3h. empty string"`), add:

```bash
_assert_position "3i. with planned-tasks"  "$(printf 'tier: medium\nplan: docs/plans/foo.md\nplanned-tasks: 5')"  "post-decomposition"
_assert_position "3j. planned-tasks before completed" "$(printf 'tier: medium\nplanned-tasks: 3\ncompleted: 1')" "mid-implementation"
```

Test 3i verifies `planned-tasks:` triggers post-decomposition. Test 3j verifies `completed:` still takes priority over `planned-tasks:` (higher in the detection chain).

- [ ] **Step 3: Run tests to verify**

Run: `bash tests/test-behaviors.sh`
Expected: All tests pass (detect_position and test cases are both test code, so they pass together). The "RED" for this task is that resume/SKILL.md doesn't yet match — validated later in Task 6.

- [ ] **Step 4: Commit**

```bash
git add tests/test-behaviors.sh
git commit -m "test: add post-decomposition position detection tests"
```

---

### Task 2: RED — Tier signal validation tests (validate-config.sh)

**Files:**
- Modify: `tests/validate-config.sh:338`

- [ ] **Step 1: Update tier signal consistency check**

Replace line 338:

```bash
for tier_signal in "≤1 file" "1-3 files" "4+ files"; do
```

With:

```bash
for tier_signal in "≤1 file" "1-3 files" "4-7 files" "8+ files"; do
```

This checks that both workflow.md and help.md contain the Medium tier signal ("4-7 files") and the updated Medium+ signal ("8+ files").

- [ ] **Step 2: Run validation to verify failure**

Run: `bash tests/validate-config.sh`
Expected: FAIL — "4-7 files" and "8+ files" not found in workflow.md or help.md (they currently say "4+ files" for Medium+).

- [ ] **Step 3: Commit**

```bash
git add tests/validate-config.sh
git commit -m "test: update tier signal checks for medium tier"
```

---

### Task 3: RED — Medium tier scenario (scenarios/medium.sh)

**Files:**
- Create: `tests/scenarios/medium.sh`
- Modify: `skills/test/SKILL.md:33`

- [ ] **Step 1: Create the medium scenario script**

Create `tests/scenarios/medium.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
echo "=== Medium Tier: Multi-file feature ==="
# F18: No stale fallback — require scaffold.sh to have run
TEST_DIR=$(cat "${TMPDIR:-/tmp}/.workflow-test-dir-$(id -un)" 2>/dev/null || echo "")
if [ -z "$TEST_DIR" ] || [ ! -d "$TEST_DIR" ]; then echo "SKIP: No test directory (run scaffold.sh first)"; exit 0; fi
cd "$TEST_DIR"

# Epic (medium tier uses --type=epic)
EPIC=$(extract_id "$(bd create --title="Add subtract and modulo operations" --type=epic --priority=2 2>&1)")

# Sub-tasks (simulates plan decomposition step)
S1=$(extract_id "$(bd create --title="Step 1: Add subtract" --type=task 2>&1)")
S2=$(extract_id "$(bd create --title="Step 2: Add modulo" --type=task 2>&1)")

bd dep add "$S1" "$EPIC" --type=parent-child
bd dep add "$S2" "$EPIC" --type=parent-child

# Step 1: Subtract (TDD — RED then GREEN)
bd update "$S1" --claim

# RED
sedi '/^\[/i \
assert_eq "subtract returns difference" "1" "$(subtract 4 3)"\
assert_eq "subtract handles negatives" "-5" "$(subtract -2 3)"' tests/run.sh

red_output=$(bash tests/run.sh 2>&1 || true)
if echo "$red_output" | grep -q "FAIL"; then
    echo "  RED confirmed (subtract)"
else
    echo "  ERROR: Tests should have failed"; exit 1
fi

# GREEN
cat >> src/utils.sh << 'FUNC'

subtract() {
    local a="$1"
    local b="$2"
    if ! [[ "$a" =~ ^-?[0-9]+$ ]] || ! [[ "$b" =~ ^-?[0-9]+$ ]]; then
        echo "error: arguments must be integers" >&2
        return 1
    fi
    echo $(( a - b ))
}
FUNC

bash tests/run.sh
echo "  GREEN confirmed (subtract)"

git add src/utils.sh tests/run.sh
git commit -m "feat: add subtract function"
bd close "$S1"

# Step 2: Modulo (TDD — RED then GREEN)
bd update "$S2" --claim

# RED
sedi '/^\[/i \
assert_eq "modulo returns remainder" "1" "$(modulo 7 3)"\
assert_eq "modulo rejects zero" "error" "$(modulo 5 0 2>/dev/null || echo "error")"' tests/run.sh

red_output=$(bash tests/run.sh 2>&1 || true)
if echo "$red_output" | grep -q "FAIL"; then
    echo "  RED confirmed (modulo)"
else
    echo "  ERROR: Tests should have failed"; exit 1
fi

# GREEN
cat >> src/utils.sh << 'FUNC'

modulo() {
    local a="$1"
    local b="$2"
    if ! [[ "$a" =~ ^-?[0-9]+$ ]] || ! [[ "$b" =~ ^-?[0-9]+$ ]]; then
        echo "error: arguments must be integers" >&2
        return 1
    fi
    if [[ "$b" -eq 0 ]]; then
        echo "error: division by zero" >&2
        return 1
    fi
    echo $(( a % b ))
}
FUNC

bash tests/run.sh
echo "  GREEN confirmed (modulo)"

git add src/utils.sh tests/run.sh
git commit -m "feat: add modulo function"
bd close "$S2"

bd close "$EPIC" --reason="All operations implemented"

echo "=== Medium Tier: PASS ==="
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x tests/scenarios/medium.sh`

- [ ] **Step 3: Add reference in skills/test/SKILL.md**

After the line `bash "$SCENARIOS/small.sh"` (line 33), add:

```bash
bash "$SCENARIOS/medium.sh"
```

- [ ] **Step 4: Run scenario to verify**

Run: `bash tests/scenarios/scaffold.sh && bash tests/scenarios/medium.sh`
Expected: PASS — this tests the bd workflow (epic + sub-tasks + TDD), not skill file content.

- [ ] **Step 5: Commit**

```bash
git add tests/scenarios/medium.sh skills/test/SKILL.md
git commit -m "test: add medium tier dry-run scenario"
```

---

### Task 4: GREEN — Core tier definition (contexts/workflow.md)

**Files:**
- Modify: `contexts/workflow.md:11-18,23,39,59`

- [ ] **Step 1: Update tier table (lines 11-16)**

Replace:

```markdown
| **Trivial** | <=1 file, no behavior change | `bd create` -> fix -> verify -> `bd close` |
| **Small** | 1-3 files, single concern | `bd create` -> TDD -> review -> verify -> `bd close` |
| **Medium+** | 4+ files, new system/component, or cross-cutting | `bd create -t epic` -> brainstorm -> plan -> sub-tasks -> spike -> TDD -> verify -> `bd close` |
| **Bug** | Any tier, type=bug | `bd create -t bug` -> debug -> TDD (regression) -> review -> verify -> `bd close` |
```

With:

```markdown
| **Trivial** | <=1 file, no behavior change | `bd create` -> fix -> verify -> `bd close` |
| **Small** | 1-3 files, single concern | `bd create` -> TDD -> review -> verify -> `bd close` |
| **Medium** | 4-7 files OR 2 domains, no architecture/system signals | `bd create -t epic` -> plan -> sub-tasks -> TDD (subagent-driven) -> review -> verify -> `bd close` |
| **Medium+** | New system/component, OR cross-cutting, OR 8+ files | `bd create -t epic` -> brainstorm -> plan -> sub-tasks -> spike -> TDD -> verify -> `bd close` |
| **Bug** | Any tier, type=bug | `bd create -t bug` -> debug -> TDD (regression) -> review -> verify -> `bd close` |
```

- [ ] **Step 2: Update hard rules (line 23)**

Replace:

```markdown
- No production code without a failing test (Small/Medium+)
```

With:

```markdown
- No production code without a failing test (Small/Medium/Medium+)
```

- [ ] **Step 3: Update sub-task micro-tiers heading (line 39)**

Replace:

```markdown
## Sub-task Micro-tiers and Review Level

Each Medium+ sub-task gets micro-tier AND review level at claim-time.
```

With:

```markdown
## Sub-task Micro-tiers and Review Level

Each Medium/Medium+ sub-task gets micro-tier AND review level at claim-time.
```

- [ ] **Step 4: Update scope health heading (line 59)**

Replace:

```markdown
## Scope Health (Medium+)
```

With:

```markdown
## Scope Health (Medium/Medium+)
```

- [ ] **Step 5: Commit**

```bash
git add contexts/workflow.md
git commit -m "feat: add medium tier to workflow context"
```

---

### Task 5: GREEN — Help documentation (commands/help.md)

**Files:**
- Modify: `commands/help.md:35-41,56-70,95-128,172-179`

- [ ] **Step 1: Update tier table (lines 35-41)**

Replace:

```markdown
| **Trivial** | ≤1 file, no behavior change | Typo, config tweak, formatting, comment |
| **Small** | 1-3 files, single concern | Bug fix, small feature, focused refactor |
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | New feature, API, architectural change |
| **Bug** | Any tier, type=bug | See Bug Path below |
```

With:

```markdown
| **Trivial** | ≤1 file, no behavior change | Typo, config tweak, formatting, comment |
| **Small** | 1-3 files, single concern | Bug fix, small feature, focused refactor |
| **Medium** | 4-7 files OR 2 domains, no architecture/system signals | Multi-file feature, cross-domain change |
| **Medium+** | New system/component, OR cross-cutting, OR 8+ files | New system, API, architectural change |
| **Bug** | Any tier, type=bug | See Bug Path below |
```

- [ ] **Step 2: Add Medium Path section**

After the Small Path section (after line 70, before Bug Path), add:

```markdown
---

## Medium Path

```
1. EPIC       bd create --title="..." --type=epic
2. PLAN       superpowers:writing-plans
               Output: plan in docs/superpowers/plans/
               bd update <epic-id> --notes "plan: <path>"
3. SUB-TASKS  For each plan step:
               bd create --title="Step N: ..." --type=task
               bd dep add <sub-id> <epic-id>
               bd update <epic-id> --notes "planned-tasks: N"
4. IMPLEMENT  superpowers:subagent-driven-development
               For each sub-task:
               ├─ Assess micro-tier
               ├─ TDD per micro-tier
               ├─ Commit after each green
               ├─ Code review per micro-tier
               └─ bd close <sub-id>
               Scope health check every 3 closed sub-tasks.
5. VERIFY     superpowers:verification-before-completion
6. CLOSE      bd close <epic-id>
```

What Medium skips vs Medium+: No brainstorming (requirements are clear). No spike
evaluation (no risky integrations expected). Goes straight to planning.
```

- [ ] **Step 3: Update escalation section (lines 172-179)**

Replace:

```markdown
## Escalation

If work grows beyond current tier, stop and escalate:

- **Trivial → Small:** Add TDD and review before continuing.
- **Small → Medium+:** Stop. Create an epic, brainstorm, plan, decompose into sub-tasks. Then continue from step 6 (IMPLEMENT).

Never skip tiers downward.
```

With:

```markdown
## Escalation

If work grows beyond current tier, stop and escalate:

- **Trivial → Small:** Add TDD and review before continuing.
- **Small → Medium:** Stop. Create an epic, plan, decompose into sub-tasks. Then continue from step 4 (IMPLEMENT).
- **Medium → Medium+:** Stop. Add brainstorming and spike evaluation. Continue from step 2 (BRAINSTORM) in the Medium+ Path.

Never skip tiers downward.
```

- [ ] **Step 4: Update plugin roles table (line 215)**

Replace:

```markdown
| **Superpowers** | Process: brainstorm, plan, TDD, review, verify, debug, finish | Small, Medium+, Bug |
```

With:

```markdown
| **Superpowers** | Process: brainstorm, plan, TDD, review, verify, debug, finish | Small, Medium, Medium+, Bug |
```

- [ ] **Step 5: Commit**

```bash
git add commands/help.md
git commit -m "feat: add medium path to help documentation"
```

---

### Task 6: GREEN — Start skill (skills/start/SKILL.md)

**Files:**
- Modify: `skills/start/SKILL.md:46-101,123-144`

- [ ] **Step 1: Update gate logic (lines 46-65)**

Replace the four-gate section:

```markdown
#### Gate 1 — ESCALATION
- Description contains **"new system"** or **"new component"** → **Medium+**
- Primary intent is architecture (**design, architect, migrate**) → **Medium+**
- Description mentions **security** or **migration** (not as primary intent) → set **floor = Small**, continue

#### Gate 2 — SCOPE
- Breadth words present (**all, every, across, entire, global**) → **Medium+**
- **3+ domains** touched → **Medium+**
- **Rewrite** or **overhaul** mentioned → **Medium+**

#### Gate 3 — SIZE
- **2+ domains** touched → **Small**
- Feature intent (**add, create, implement, new**) → **Small**

#### Gate 4 — DEFAULT
- → **Trivial** (or floor from Gate 1 if set)
```

With:

```markdown
#### Gate 1 — ESCALATION
- Description contains **"new system"** or **"new component"** → **Medium+**
- Primary intent is architecture (**design, architect, migrate**) → **Medium+**
- Description mentions **security** or **migration** (not as primary intent) → set **floor = Medium**, continue

#### Gate 2 — SCOPE
- Breadth words present (**all, every, across, entire, global**) → **Medium+**
- **3+ domains** touched → **Medium+**
- **Rewrite** or **overhaul** mentioned → **Medium+**

#### Gate 3 — MULTI
- **2+ domains** touched → **Medium**
- Estimated **4+ files** changed → **Medium**

#### Gate 4 — FEATURE
- Feature intent (**add, create, implement, new**), single domain → **Small**

#### Gate 5 — DEFAULT
- → **Trivial** (or floor from Gate 1 if set)
```

- [ ] **Step 2: Update task type and priority rules (lines 75-82)**

Replace:

```markdown
**Determine task type:**
- Trivial or Small: `--type=task`
- Medium+: `--type=epic`

**Determine priority** (if no `-p` override):
- Medium+: P1
- Small: P2
- Trivial: P3
```

With:

```markdown
**Determine task type:**
- Trivial or Small: `--type=task`
- Medium or Medium+: `--type=epic`

**Determine priority** (if no `-p` override):
- Medium+: P1
- Medium: P2
- Small: P2
- Trivial: P3
```

- [ ] **Step 3: Update tier value in notes (line 100)**

Replace:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "tier: <trivial|small|medium+>"
```

With:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "tier: <trivial|small|medium|medium+>"
```

- [ ] **Step 4: Update routing table (lines 123-144)**

Replace the recommendation table:

```markdown
| Tier | Default Recommendation | Reasoning to Show |
|---|---|---|
| Trivial | No skill needed — "Go fix it. Then verify and `bd close <task-id>`." | Explain: single-file, no behavior change, ceremony would slow you down. |
| Small | `/superpowers:test-driven-development` | Explain: single-concern change benefits from RED-GREEN-REFACTOR to catch regressions. |
| Medium+ | `/superpowers:brainstorming` | Explain: multi-file/cross-cutting work needs requirements exploration before code. |
```

With:

```markdown
| Tier | Default Recommendation | Reasoning to Show |
|---|---|---|
| Trivial | No skill needed — "Go fix it. Then verify and `bd close <task-id>`." | Explain: single-file, no behavior change, ceremony would slow you down. |
| Small | `/superpowers:test-driven-development` | Explain: single-concern change benefits from RED-GREEN-REFACTOR to catch regressions. |
| Medium | `/superpowers:writing-plans` | Explain: multi-file work benefits from planning the order of changes before TDD. Implementation via subagent-driven-development. |
| Medium+ | `/superpowers:brainstorming` | Explain: new system/cross-cutting work needs requirements exploration before code. |
```

- [ ] **Step 5: Commit**

```bash
git add skills/start/SKILL.md
git commit -m "feat: add medium tier to start skill gate logic and routing"
```

---

### Task 7: GREEN — Resume skill (skills/resume/SKILL.md)

**Files:**
- Modify: `skills/resume/SKILL.md:101-108,149-162,170-181,202-215`

- [ ] **Step 1: Update tier inference (lines 101-108)**

Replace:

```markdown
**Determine tier:**

1. Check beads notes for `"tier: <value>"` (set by `/start`)
2. If not found, infer:
   - Task is under an epic → medium+
   - Task type is epic → medium+
   - Task has notes referencing spec/plan files (contains `"spec:"` or `"plan:"`) → small
   - Otherwise → **default to small** (ensures minimum TDD + review; can escalate if needed)
```

With:

```markdown
**Determine tier:**

1. Check beads notes for `"tier: <value>"` (set by `/start`)
2. If not found, infer:
   - Task is under an epic → medium+
   - Task type is epic → medium+
   - Task has notes with `"plan:"` but no `"spec:"` → medium (plan without spec = no brainstorming)
   - Task has notes referencing spec files (contains `"spec:"`) → small
   - Otherwise → **default to small** (ensures minimum TDD + review; can escalate if needed)
```

- [ ] **Step 2: Update context loading tiers (line 152)**

In the context object assembly, replace:

```markdown
  tier:        trivial | small | medium+
```

With:

```markdown
  tier:        trivial | small | medium | medium+
```

- [ ] **Step 3: Update position detection table (lines 170-181)**

Replace:

```markdown
| Priority | Pattern in notes | Position |
|---|---|---|
| 1 (highest) | `"docs-updated:"` | post-update-docs |
| 2 | `"verification:"` | post-verification |
| 3 | `"completed:"` | mid-implementation |
| 4 | `"plan:"` | post-planning |
| 5 | `"spec:"` | post-brainstorming |
| 6 | `"debug:"` | mid-debugging |
| 7 (lowest) | `"tier:"` only (no other milestones) | start |
```

With:

```markdown
| Priority | Pattern in notes | Position |
|---|---|---|
| 1 (highest) | `"docs-updated:"` | post-update-docs |
| 2 | `"verification:"` | post-verification |
| 3 | `"completed:"` | mid-implementation |
| 4 | `"planned-tasks:"` | post-decomposition |
| 5 | `"plan:"` | post-planning |
| 6 | `"spec:"` | post-brainstorming |
| 7 | `"debug:"` | mid-debugging |
| 8 (lowest) | `"tier:"` only (no other milestones) | start |
```

- [ ] **Step 4: Update routing table (lines 202-215)**

Replace:

```markdown
| Position | Task type | Next skill |
|---|---|---|
| start | epic | `/superpowers:brainstorming` |
| start | task (small) | `/superpowers:test-driven-development` |
| start | task (trivial) | No skill — "Go fix it. Then verify and `bd close <id>`." |
| start | bug (any tier) | `/superpowers:systematic-debugging` |
| mid-debugging | bug | `/superpowers:systematic-debugging` (continue) |
| post-brainstorming | any | `/superpowers:writing-plans` |
| post-planning | any | `/superpowers:test-driven-development` (next ready sub-task) |
| mid-implementation | any | `/superpowers:test-driven-development` (next ready sub-task) |
| post-verification | any | `/ecc:update-docs` |
| post-update-docs | any | `/superpowers:finishing-a-development-branch` |
```

With:

```markdown
| Position | Task type | Next skill |
|---|---|---|
| start | epic (medium+) | `/superpowers:brainstorming` |
| start | epic (medium) | `/superpowers:writing-plans` |
| start | task (small) | `/superpowers:test-driven-development` |
| start | task (trivial) | No skill — "Go fix it. Then verify and `bd close <id>`." |
| start | bug (any tier) | `/superpowers:systematic-debugging` |
| mid-debugging | bug | `/superpowers:systematic-debugging` (continue) |
| post-brainstorming | any | `/superpowers:writing-plans` |
| post-planning | any | Create sub-tasks from plan, then continue |
| post-decomposition | medium | `/superpowers:subagent-driven-development` |
| post-decomposition | medium+ | `/superpowers:test-driven-development` (next ready sub-task) |
| mid-implementation | medium | `/superpowers:subagent-driven-development` (continue) |
| mid-implementation | medium+ | `/superpowers:test-driven-development` (next ready sub-task) |
| post-verification | any | `/ecc:update-docs` |
| post-update-docs | any | `/superpowers:finishing-a-development-branch` |
```

- [ ] **Step 5: Commit**

```bash
git add skills/resume/SKILL.md
git commit -m "feat: add medium tier to resume skill routing and detection"
```

---

### Task 8: GREEN — README (README.md)

**Files:**
- Modify: `README.md:85-91`

- [ ] **Step 1: Update tier table**

Replace:

```markdown
| **Trivial** | ≤1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | `bd create -t epic` → brainstorm → plan → sub-tasks → spike eval → TDD → verify → `bd close` (+ worktree when isolating risk; update-docs when public API changed; finish when on feature branch) |
| **Bug** | Any tier, type=bug | `bd create -t bug` → debug → TDD (regression test) → review → verify → `bd close` |
```

With:

```markdown
| **Trivial** | ≤1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium** | 4-7 files OR 2 domains, no architecture/system signals | `bd create -t epic` → plan → sub-tasks → TDD (subagent-driven) → review → verify → `bd close` |
| **Medium+** | New system/component, OR cross-cutting, OR 8+ files | `bd create -t epic` → brainstorm → plan → sub-tasks → spike eval → TDD → verify → `bd close` (+ worktree when isolating risk; update-docs when public API changed; finish when on feature branch) |
| **Bug** | Any tier, type=bug | `bd create -t bug` → debug → TDD (regression test) → review → verify → `bd close` |
```

- [ ] **Step 2: Update "What's Included" line (line 7)**

Replace:

```markdown
- **Unified Workflow** — Size-based routing (trivial/small/medium+) connecting Beads, Superpowers, and ECC
```

With:

```markdown
- **Unified Workflow** — Size-based routing (trivial/small/medium/medium+) connecting Beads, Superpowers, and ECC
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "feat: add medium tier to README"
```

---

### Task 9: Verify GREEN — Run all tests

**Files:** None (read-only verification)

- [ ] **Step 1: Run behavioral tests**

Run: `bash tests/test-behaviors.sh`
Expected: All tests pass, including new 3i and 3j.

- [ ] **Step 2: Run config validation**

Run: `bash tests/validate-config.sh`
Expected: All checks pass, including updated tier signal checks ("4-7 files", "8+ files").

- [ ] **Step 3: Run medium scenario**

Run: `bash tests/scenarios/scaffold.sh && bash tests/scenarios/medium.sh`
Expected: `=== Medium Tier: PASS ===`

- [ ] **Step 4: Run full scenario suite**

Run:
```bash
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash tests/scenarios/scaffold.sh
bash tests/scenarios/init-persistence.sh
bash tests/scenarios/trivial.sh
bash tests/scenarios/small.sh
bash tests/scenarios/medium.sh
bash tests/scenarios/medium-plus.sh
bash tests/scenarios/escalation.sh
bash tests/scenarios/side-quest.sh
bash tests/scenarios/bug-path.sh
bash tests/scenarios/cleanup.sh
```
Expected: All scenarios pass.

- [ ] **Step 5: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "fix: address test failures from medium tier integration"
```
Only if Step 1-4 revealed issues that needed fixing.
