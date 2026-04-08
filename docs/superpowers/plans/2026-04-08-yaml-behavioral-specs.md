# YAML Behavioral Specs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create YAML behavioral specs for 6 core skills using the skill-comply format, graded by existing bash mock infrastructure.

**Architecture:** One YAML spec file per skill in `tests/specs/`. Each spec defines 3-7 behavioral steps with ordering constraints. Corresponding bash test sections in `tests/test-behaviors.sh` verify the mechanical parts. The YAML serves as both documentation and the RED/GREEN reference for writing-skills-enforcement.

**Tech Stack:** YAML (specs), Bash (tests)

---

## File Structure

```
tests/
  specs/                           # NEW directory
    pre-change-gate.yaml           # NEW: hook behavioral spec
    bd-notes-append.yaml           # NEW: hook behavioral spec
    position-detection.yaml        # NEW: position detection spec (covers beads-milestones)
    scope-health.yaml              # NEW: rule behavioral spec
    start.yaml                     # NEW: skill behavioral spec
    resume.yaml                    # NEW: skill behavioral spec
  test-behaviors.sh                # MODIFY: add spec-validation section
  validate-config.sh               # MODIFY: add spec file existence checks
```

Note: "workflow" and "beads-milestones" and "scope-health" from the task description are sections of `contexts/workflow.md`, not standalone skills. They map to: position-detection (covers milestone handling), scope-health (rule verification), and the existing workflow content guards (test-behaviors.sh section 7). The bd-notes-append spec replaces "beads-milestones" since that's the actual mechanical behavior.

---

### Task 1: Create specs directory and spec-validation infrastructure

**Files:**
- Create: `tests/specs/` (directory)
- Modify: `tests/validate-config.sh`
- Modify: `tests/test-behaviors.sh`

- [ ] **Step 1: Create the specs directory**

```bash
mkdir -p tests/specs
```

- [ ] **Step 2: Add spec file existence checks to validate-config.sh**

After the section 21 block (README test file references, around line 688), add a new section:

```bash
# --- 24. Behavioral spec files ---
echo "24. Behavioral spec files"

SPECS_DIR="$PLUGIN_ROOT/tests/specs"
if [ -d "$SPECS_DIR" ]; then
    pass "tests/specs/ directory exists"
    for spec_name in pre-change-gate bd-notes-append position-detection scope-health start resume; do
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
```

Insert this BEFORE the `# --- Summary ---` line.

- [ ] **Step 3: Add spec-content validation section to test-behaviors.sh**

After the section 7 block (workflow.md inlined content, around line 638), add:

```bash
# ---------------------------------------------------------------------------
# Section 8: YAML spec structure validation
# ---------------------------------------------------------------------------
echo ""
echo "8. YAML spec structure"

SPECS_DIR="$PLUGIN_ROOT/tests/specs"
if [ -d "$SPECS_DIR" ]; then
    for spec_file in "$SPECS_DIR"/*.yaml; do
        spec_name=$(basename "$spec_file" .yaml)
        # Check required top-level keys exist
        HAS_ID=0; HAS_STEPS=0; HAS_SCORING=0
        grep -q '^id:' "$spec_file" 2>/dev/null && HAS_ID=1
        grep -q '^steps:' "$spec_file" 2>/dev/null && HAS_STEPS=1
        grep -q '^scoring:' "$spec_file" 2>/dev/null && HAS_SCORING=1
        if [ "$HAS_ID" -eq 1 ] && [ "$HAS_STEPS" -eq 1 ] && [ "$HAS_SCORING" -eq 1 ]; then
            pass "8. $spec_name.yaml has required keys (id, steps, scoring)"
        else
            fail "8. $spec_name.yaml missing keys: id=$HAS_ID steps=$HAS_STEPS scoring=$HAS_SCORING"
        fi
        # Check version is 2.0
        if grep -q 'version: "2.0"' "$spec_file" 2>/dev/null; then
            pass "8. $spec_name.yaml version is 2.0"
        else
            fail "8. $spec_name.yaml version is not 2.0"
        fi
    done
else
    pass "8. specs directory not yet created (skipped)"
fi

echo ""
```

- [ ] **Step 4: Run tests to verify RED**

Run: `bash tests/validate-config.sh 2>&1 | grep -E "specs|24\."` — should fail (specs don't exist yet).
Run: `bash tests/test-behaviors.sh 2>&1 | grep "8\."` — should skip (no specs dir yet).

- [ ] **Step 5: Commit**

```bash
git add tests/validate-config.sh tests/test-behaviors.sh
git commit -m "test: add YAML spec validation infrastructure"
```

---

### Task 2: pre-change-gate behavioral spec

**Files:**
- Create: `tests/specs/pre-change-gate.yaml`

- [ ] **Step 1: Create the YAML spec**

Create `tests/specs/pre-change-gate.yaml`:

```yaml
id: pre-change-gate
name: Pre-Change Gate Hook
source_rule: hooks/pre-change-gate
version: "2.0"

steps:
  - id: check_beads_dir
    description: "Check for .beads directory; exit silently if not found"
    required: true
    detector:
      description: "Script checks for .beads directory existence and exits 0 if missing"
      before_step: check_bd_available

  - id: check_bd_available
    description: "Check if bd command is available; exit silently if not"
    required: true
    detector:
      description: "command -v bd check, exits 0 if bd not in PATH"
      after_step: check_beads_dir
      before_step: check_cache

  - id: check_cache
    description: "Check per-project cache; return cached result if fresh (<60s)"
    required: true
    detector:
      description: "Read cache file, compare mtime, return cached output if age < 60s"
      after_step: check_bd_available
      before_step: query_in_progress

  - id: query_in_progress
    description: "Query bd for in-progress tasks"
    required: true
    detector:
      description: "Run bd list --status=in_progress (JSON first, text fallback)"
      after_step: check_cache

  - id: warn_no_task
    description: "Warn if no active beads task found"
    required: true
    detector:
      description: "Output WARNING about no active beads task when bd list returns empty"
      after_step: query_in_progress

  - id: warn_no_tier
    description: "Warn if active task has no tier assessment"
    required: true
    detector:
      description: "Run bd show on task, check notes for tier: pattern, warn if missing"
      after_step: query_in_progress

scoring:
  threshold_promote_to_hook: 0.8
```

- [ ] **Step 2: Run tests to verify GREEN**

Run: `bash tests/test-behaviors.sh 2>&1 | grep "8\."` — spec structure validation should pass.
Run: `bash tests/validate-config.sh 2>&1 | grep "pre-change-gate"` — spec existence should pass.

Existing tests in test-behaviors.sh section 2 already verify the behavioral steps:
- 2a: no task in progress → warns (step: warn_no_task ✓)
- 2b: task exists, no tier → warns (step: warn_no_tier ✓)
- 2c: task with tier → no output (steps: check_cache → query → silent ✓)
- 6a: no bd in PATH → exits silently (step: check_bd_available ✓)
- 6d: cache hit → consistent output (step: check_cache ✓)

- [ ] **Step 3: Commit**

```bash
git add tests/specs/pre-change-gate.yaml
git commit -m "feat: add pre-change-gate behavioral spec"
```

---

### Task 3: bd-notes-append behavioral spec

**Files:**
- Create: `tests/specs/bd-notes-append.yaml`

- [ ] **Step 1: Create the YAML spec**

Create `tests/specs/bd-notes-append.yaml`:

```yaml
id: bd-notes-append
name: Beads Notes Append Hook
source_rule: hooks/bd-notes-append
version: "2.0"

steps:
  - id: validate_args
    description: "Validate task-id and new-line arguments are provided"
    required: true
    detector:
      description: "Check that both positional args are non-empty, exit 1 with usage if missing"
      before_step: check_bd

  - id: check_bd
    description: "Verify bd command is available"
    required: true
    detector:
      description: "command -v bd check, exit 1 with error if bd not in PATH"
      after_step: validate_args
      before_step: fetch_existing

  - id: fetch_existing
    description: "Fetch current notes from bd show"
    required: true
    detector:
      description: "Run bd show <task-id>, extract NOTES section between headers"
      after_step: check_bd
      before_step: append_note

  - id: append_note
    description: "Append new line to existing notes and update"
    required: true
    detector:
      description: "Run bd update --notes with existing content plus new line appended"
      after_step: fetch_existing

scoring:
  threshold_promote_to_hook: 0.8
```

- [ ] **Step 2: Verify coverage against existing tests**

Existing tests in test-behaviors.sh section 1 already verify the behavioral steps:
- 1a: empty notes → captures new line (steps: fetch_existing → append_note ✓)
- 1b: existing notes → appends preserving content (step: append_note ✓)
- 1c: no arguments → exits 1 (step: validate_args ✓)
- 1d: all-caps freetext → preserves content (step: fetch_existing ✓)
- 1e: DEPENDS ON header → stops extraction (step: fetch_existing ✓)
- 6c: bd show failure → reports error (step: check_bd ✓)

- [ ] **Step 3: Commit**

```bash
git add tests/specs/bd-notes-append.yaml
git commit -m "feat: add bd-notes-append behavioral spec"
```

---

### Task 4: position-detection behavioral spec

**Files:**
- Create: `tests/specs/position-detection.yaml`

- [ ] **Step 1: Create the YAML spec**

This spec covers the beads-milestones position detection algorithm from resume/SKILL.md, mechanically tested via the detect_position() function in test-behaviors.sh.

Create `tests/specs/position-detection.yaml`:

```yaml
id: position-detection
name: Position Detection Algorithm
source_rule: skills/resume/SKILL.md
version: "2.0"

steps:
  - id: scan_milestones
    description: "Scan beads notes for milestone patterns in priority order"
    required: true
    detector:
      description: "Check notes string for milestone keys in order: docs-updated, verification, completed, planned-tasks, plan, spec, debug, tier"

  - id: detect_docs_updated
    description: "Detect post-update-docs position from docs-updated: pattern"
    required: true
    detector:
      description: "If notes contain docs-updated: return post-update-docs (priority 1)"
      after_step: scan_milestones

  - id: detect_verification
    description: "Detect post-verification position from verification: pattern"
    required: true
    detector:
      description: "If notes contain verification: return post-verification (priority 2)"
      after_step: scan_milestones

  - id: detect_completed
    description: "Detect mid-implementation position from completed: pattern"
    required: true
    detector:
      description: "If notes contain completed: return mid-implementation (priority 3)"
      after_step: scan_milestones

  - id: detect_planned_tasks
    description: "Detect post-decomposition position from planned-tasks: pattern"
    required: true
    detector:
      description: "If notes contain planned-tasks: return post-decomposition (priority 4)"
      after_step: scan_milestones

  - id: detect_plan
    description: "Detect post-planning position from plan: pattern"
    required: true
    detector:
      description: "If notes contain plan: return post-planning (priority 5)"
      after_step: scan_milestones

  - id: detect_tier_only
    description: "Detect start position when only tier: is present"
    required: true
    detector:
      description: "If notes contain only tier: with no other milestones, return start (priority 8)"
      after_step: scan_milestones

scoring:
  threshold_promote_to_hook: 0.6
```

- [ ] **Step 2: Verify coverage against existing tests**

Existing tests in test-behaviors.sh section 3 already verify every step:
- 3a: tier only → start (step: detect_tier_only ✓)
- 3b: tier + spec → post-brainstorming ✓
- 3c: tier + spec + plan → post-planning (step: detect_plan ✓)
- 3d: with completed → mid-implementation (step: detect_completed ✓)
- 3e: with verification → post-verification (step: detect_verification ✓)
- 3f: with docs-updated → post-update-docs (step: detect_docs_updated ✓)
- 3g: with debug → mid-debugging ✓
- 3h: empty string → unknown ✓
- 3i: with planned-tasks → post-decomposition (step: detect_planned_tasks ✓)
- 3j: planned-tasks before completed → mid-implementation (priority ordering ✓)

- [ ] **Step 3: Commit**

```bash
git add tests/specs/position-detection.yaml
git commit -m "feat: add position-detection behavioral spec"
```

---

### Task 5: scope-health behavioral spec

**Files:**
- Create: `tests/specs/scope-health.yaml`

- [ ] **Step 1: Create the YAML spec**

Scope health is a rule in `contexts/workflow.md`, not a script. Its behavioral steps are enforced by the LLM agent when following the workflow. The spec formalizes the expected sequence; grading is via the content guard tests in test-behaviors.sh section 7d.

Create `tests/specs/scope-health.yaml`:

```yaml
id: scope-health
name: Scope Health Check
source_rule: contexts/workflow.md
version: "2.0"

steps:
  - id: trigger_check
    description: "Trigger scope health check every 3rd closed sub-task"
    required: true
    detector:
      description: "After closing a sub-task, count total closed. If divisible by 3, run scope health."

  - id: compute_ratio
    description: "Compute ratio of total created tasks to planned tasks"
    required: true
    detector:
      description: "Calculate ratio = total_created / planned_tasks from beads notes"
      after_step: trigger_check

  - id: warn_at_threshold
    description: "Warn when ratio reaches 1.5x"
    required: true
    detector:
      description: "If ratio >= 1.5, output warning about scope growth"
      after_step: compute_ratio

  - id: gate_at_threshold
    description: "Gate (stop and ask human) when ratio reaches 2.0x"
    required: true
    detector:
      description: "If ratio >= 2.0, stop execution and present re-plan/split/continue options to human"
      after_step: compute_ratio

scoring:
  threshold_promote_to_hook: 0.6
```

- [ ] **Step 2: Verify coverage against existing tests**

Existing test in test-behaviors.sh section 7d verifies the thresholds are documented:
- 7d: scope health thresholds (1.5x, 2.0x) present in workflow.md ✓

The behavioral sequence itself (trigger → compute → warn/gate) is LLM-enforced. The YAML spec formalizes what the agent should do.

- [ ] **Step 3: Commit**

```bash
git add tests/specs/scope-health.yaml
git commit -m "feat: add scope-health behavioral spec"
```

---

### Task 6: start skill behavioral spec

**Files:**
- Create: `tests/specs/start.yaml`

- [ ] **Step 1: Create the YAML spec**

Create `tests/specs/start.yaml`:

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
    description: "Check for side-quest indicators before tier assessment"
    required: true
    detector:
      description: "Check for Found:/Discovered: prefix, --side-quest flag, or scope conflict with in-progress task"
      after_step: parse_args
      before_step: walk_gates

  - id: walk_gates
    description: "Walk gates 1-5 to determine tier"
    required: true
    detector:
      description: "Evaluate Gate 1 (ESCALATION), Gate 2 (SCOPE), Gate 3 (MULTI), Gate 4 (FEATURE), Gate 5 (DEFAULT) in order"
      after_step: check_side_quest
      before_step: create_task

  - id: create_task
    description: "Create beads task with correct type and priority"
    required: true
    detector:
      description: "Run bd create with --type=task|epic and -p based on tier (Trivial/Small=task, Medium/Medium+=epic)"
      after_step: walk_gates

  - id: persist_tier
    description: "Log tier to beads notes via bd-notes-append"
    required: true
    detector:
      description: "Run bd-notes-append with tier: trivial|small|medium|medium+"
      after_step: create_task

  - id: present_recommendation
    description: "Present workflow options table and wait for user choice"
    required: true
    detector:
      description: "Print analysis with gate, tier, task-id, and recommendation table. Do NOT auto-invoke any skill."
      after_step: persist_tier

scoring:
  threshold_promote_to_hook: 0.6
```

- [ ] **Step 2: Verify coverage**

The start skill is LLM-interpreted. Mechanical parts tested by existing scenarios:
- scenarios/small.sh: creates task with bd create ✓
- scenarios/medium.sh: creates epic with bd create ✓
- scenarios/medium-plus.sh: creates epic with bd create ✓

The YAML spec formalizes the full behavioral sequence for writing-skills-enforcement RED/GREEN phases.

- [ ] **Step 3: Commit**

```bash
git add tests/specs/start.yaml
git commit -m "feat: add start skill behavioral spec"
```

---

### Task 7: resume skill behavioral spec

**Files:**
- Create: `tests/specs/resume.yaml`

- [ ] **Step 1: Create the YAML spec**

Create `tests/specs/resume.yaml`:

```yaml
id: resume-skill
name: Resume Skill Workflow
source_rule: skills/resume/SKILL.md
version: "2.0"

steps:
  - id: gather_open_work
    description: "Query beads for in-progress and open tasks"
    required: true
    detector:
      description: "Run bd list --status=in_progress and bd list --status=open"
      before_step: select_task

  - id: select_task
    description: "Auto-select if 1 in-progress, show list if multiple or none"
    required: true
    detector:
      description: "Apply auto-selection logic: 1 in_progress=auto, multiple=show list, 0=show list"
      after_step: gather_open_work
      before_step: load_context

  - id: load_context
    description: "Load context at tier-appropriate depth"
    required: true
    detector:
      description: "Determine tier from notes or inference. Load shallow (trivial), medium (small), or deep (medium/medium+)."
      after_step: select_task
      before_step: detect_position

  - id: detect_position
    description: "Detect workflow position from milestone notes"
    required: true
    detector:
      description: "Scan notes for milestone patterns in priority order (docs-updated > verification > completed > planned-tasks > plan > spec > debug > tier)"
      after_step: load_context
      before_step: route_to_skill

  - id: route_to_skill
    description: "Map position and tier to next skill"
    required: true
    detector:
      description: "Use routing table to determine next skill based on position + task type/tier. Medium at post-decomposition routes to subagent-driven-development."
      after_step: detect_position

  - id: print_summary
    description: "Print resume summary with status, tier, and next skill"
    required: true
    detector:
      description: "Output formatted summary showing task title, position, tier, and next skill name"
      after_step: route_to_skill

scoring:
  threshold_promote_to_hook: 0.6
```

- [ ] **Step 2: Verify coverage**

Mechanical parts tested by existing infrastructure:
- test-behaviors.sh section 3: position detection algorithm (step: detect_position ✓)
- The routing table and tier inference are LLM-interpreted. The YAML spec formalizes the expected sequence.

- [ ] **Step 3: Commit**

```bash
git add tests/specs/resume.yaml
git commit -m "feat: add resume skill behavioral spec"
```

---

### Task 8: Verify all specs and tests pass

**Files:** None (read-only verification)

- [ ] **Step 1: Run behavioral tests**

Run: `bash tests/test-behaviors.sh`
Expected: All tests pass, including new section 8 (YAML spec structure validation).

- [ ] **Step 2: Run config validation**

Run: `bash tests/validate-config.sh`
Expected: All checks pass, including new section 24 (spec file existence).

- [ ] **Step 3: Verify all 6 spec files exist and have correct structure**

Run:
```bash
for f in tests/specs/*.yaml; do
    echo "--- $(basename $f) ---"
    grep -E '^(id|name|version|steps|scoring):' "$f"
    echo "Steps: $(grep -c '  - id:' "$f")"
    echo ""
done
```

Expected: 6 files, each with id, name, version 2.0, steps, scoring, and 3-7 steps.

- [ ] **Step 4: Final commit if any fixups needed**

```bash
git add -A
git commit -m "fix: address test failures from YAML spec integration"
```
Only if Steps 1-3 revealed issues.
