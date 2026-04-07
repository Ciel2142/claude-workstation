# Slim claude-workstation to Core — Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Reduce plugin from 11 skills to 4 by inlining 6 reference skills into workflow.md and removing status skill. Add hook timeouts. Preserve 100% of behavioral enforcement.

**Architecture:** Inline reference-only skills into the always-loaded workflow.md context. Keep only skills that are interactive entry points (start, resume) or one-time setup (setup, test). Add timeout guards to bd calls in hooks.

---

### Task 1: Rewrite workflow.md — inline 6 skills

**Files:**
- Modify: `contexts/workflow.md` (currently 149 lines → target ~100 lines)

**What to inline (extract essential content only):**

1. **beads-milestones** (82 lines → ~20 lines): Keep the key-value table and the `bd-notes-append` usage note. Drop the "When to Update" prose, "What NOT to Do" section, and the fallback instructions.

2. **review-level-gate** (79 lines → ~15 lines): Keep the 5-signal table and the Standard/Consensus definitions. Inline into the Sub-task Micro-tiers section. Drop the standalone ESCALATE protocol detail, Red Flags table, and Budget Awareness section. Keep the one-signal-enough rule and the no-self-assessment rule.

3. **scope-health** (65 lines → ~8 lines): Keep the ratio thresholds (1.5x warning, 2.0x gate) and the 3-option response. Drop the format templates and the "After Gate Decision" prose.

4. **spike-phase** (78 lines → ~5 lines): Reduce to a rule: "After planning, before first implementation: validate file paths exist, interfaces match plan assumptions. If plan mentions API/integration/library/SDK/migrate/external, also build a minimal proof-of-concept for the riskiest integration. Log: spike: <lightweight|deep>."

5. **debugging-protocol** (42 lines → ~3 lines): Reduce to: "Bugs: invoke superpowers:systematic-debugging. 3 failed hypotheses → STOP, present to user. Always write regression test before fix."

6. **verification-template** (38 lines → ~5 lines): Keep the output template format and status symbols. Drop the rules prose.

**Also in this task:**
- Remove the duplicate Collateral Breakage Rule subsection (lines 143-147 repeat lines 127-132)
- Remove the "Review level gate" skill reference bullet (line 101) — content is now inline
- Update all 7 skill reference bullets to reflect inlined content
- Simplify the Sub-task Micro-tiers section: merge micro-tier assessment and review-level signals into a single claim-time evaluation

- [ ] Step 1: Write the new workflow.md
- [ ] Step 2: Verify it's under 110 lines
- [ ] Step 3: Commit

### Task 2: Remove 7 skill directories

**Files:**
- Delete: `skills/debugging-protocol/SKILL.md`
- Delete: `skills/beads-milestones/SKILL.md`
- Delete: `skills/verification-template/SKILL.md`
- Delete: `skills/scope-health/SKILL.md`
- Delete: `skills/spike-phase/SKILL.md`
- Delete: `skills/review-level-gate/SKILL.md`
- Delete: `skills/status/SKILL.md`

- [ ] Step 1: Remove the 7 skill directories
- [ ] Step 2: Commit

### Task 3: Add timeout to bd calls in hooks

**Files:**
- Modify: `hooks/pre-change-gate` (lines 51, 58, 67)
- Modify: `hooks/stop` (lines 31, 38, 40, 42, 49)

Wrap all `bd` invocations with `timeout 5`:
```bash
# Before:
LISTING_JSON=$(bd list --status=in_progress --json 2>/dev/null || echo "")
# After:
LISTING_JSON=$(timeout 5 bd list --status=in_progress --json 2>/dev/null || echo "")
```

Add a macOS compatibility guard at the top of each hook (after the guards section):
```bash
# Timeout wrapper: GNU coreutils timeout preferred, noop fallback
if command -v timeout >/dev/null 2>&1; then
    TO="timeout 5"
else
    TO=""
fi
```
Then use `$TO bd ...` instead of `timeout 5 bd ...`.

- [ ] Step 1: Add timeout wrapper to pre-change-gate
- [ ] Step 2: Add timeout wrapper to stop hook
- [ ] Step 3: Run behavioral tests for hooks (sections 1-6)
- [ ] Step 4: Commit

### Task 4: Update references — start skill

**Files:**
- Modify: `skills/start/SKILL.md` (line ~133)

Remove the "Medium+ sub-task flow note" that references `/claude-workstation:review-level-gate` — this is now handled inline in workflow.md.

- [ ] Step 1: Remove the review-level-gate reference paragraph
- [ ] Step 2: Commit

### Task 5: Update references — README, help, validate-config

**Files:**
- Modify: `README.md` (lines 50-55 commands table, lines 129-134 tree)
- Modify: `commands/help.md` (line 111 spike reference)
- Modify: `tests/validate-config.sh` (lines 162, 175 skill dir loops; lines 237-298 milestone schema checks)

README changes:
- Remove the 6 skill rows from Commands & Skills table (lines 50-55)
- Remove the 6 directory entries from the tree (lines 129-134)
- Remove the status skill row and directory entry

validate-config.sh changes:
- Remove removed skill names from the directory existence loops (lines 162, 175)
- Remove or update the beads-milestones schema validation (section 11, lines 237-298) — the canonical keys now live in workflow.md
- Update test counts in comments if needed

- [ ] Step 1: Update README.md
- [ ] Step 2: Update commands/help.md
- [ ] Step 3: Update validate-config.sh
- [ ] Step 4: Commit

### Task 6: Update tests — remove sections 7-11, add workflow.md guards

**Files:**
- Modify: `tests/test-behaviors.sh` (remove sections 7-11, ~210 lines)

Sections 7-11 all grep for content in the now-deleted review-level-gate SKILL.md. Remove them entirely. The behavioral content (5 signals, Standard/Consensus, claim-time evaluation) is now inline in workflow.md and will be covered by validate-config.sh structural checks.

Add 3-4 replacement tests that verify the inlined content exists in workflow.md:
- workflow.md contains "Standard" and "Consensus"
- workflow.md contains all 5 signal names
- workflow.md contains milestone key table
- workflow.md contains scope-health ratio thresholds

- [ ] Step 1: Remove sections 7-11
- [ ] Step 2: Add replacement workflow.md guards
- [ ] Step 3: Run full test suite
- [ ] Step 4: Commit
