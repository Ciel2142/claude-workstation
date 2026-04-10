# Remove Tier Mechanism from `/start` Skill

**Date:** 2026-04-10
**Task:** claude-workstation-g30
**Version:** 2.2.2 -> 2.3.0

## Problem

The tier mechanism in `/start` classifies tasks into Trivial/Small/Medium/Medium+ using
a 5-gate keyword-matching system, then routes each tier to a different workflow entry point:

- Trivial -> "go fix it" (no structure)
- Small -> TDD (a methodology, not a workflow)
- Medium -> writing-plans (actual structure)
- Medium+ -> brainstorming (actual structure)

Two of the four routes provide meaningful structure (brainstorming, planning). The other
two are effectively "good luck" — they skip the thinking-before-coding step that actually
changes outcomes. TDD and verification should happen on every task regardless, not as
routing destinations.

The tier's primary consumer (`/continue` skill) was deleted in workflow v2. What remains
is tier generation, persistence to notes, and a validation check in the pre-change gate
hook — but nothing reads the tier value for routing anymore.

## Design Principle

**Every task gets the full pipeline. The pipeline self-scales to complexity.**

A typo fix produces a one-line plan and a trivial test. A new system produces a multi-page
spec with sub-tasks. But both go through the same flow:

```
Task -> Brainstorm (if unclear) -> Plan -> TDD -> Review -> Verify -> Close
```

No escape hatches. No "this is trivial, skip planning."

## Changes

### 1. `/start` Skill (`skills/start/SKILL.md`)

**Remove:**
- Step 3 (TIER): all 5 gates, domain counting, keyword matching
- Claude Override mechanism (upward-only tier bumps)
- Tier-to-type mapping (trivial/small -> task, medium/medium+ -> epic)
- Tier-to-priority mapping (P1/P2/P3 by tier)
- Tier persistence via `bd-notes-append`
- 4-option recommendation table with per-option reasoning columns

**Keep:**
- Step 1 (PARSE): extract description, `-p` override, `--side-quest` flag
- Step 2 (SIDE-QUEST): detection and parking flow, unchanged
- Task creation and set in-progress

**Replace Step 3 + Step 5 with simplified flow:**

After creating the task, print confirmation and ask one question:

```
Created: <task-id> (P<priority>)
Brainstorm first, or straight to planning?
```

User answers. `/start` invokes the chosen skill.

**Task creation defaults:**
- Type: always `--type=task` (user upgrades to epic manually if needed)
- Priority: always P2 unless `-p` override provided

**Update frontmatter version:** 2.2.2 -> 2.3.0

### 2. Workflow Skill (`skills/workflow/SKILL.md`)

**Update "The Flow" section:**

From:
```
Not every task needs every step. /start assesses complexity and suggests where to enter.
```

To:
```
Every task follows the full pipeline. The pipeline self-scales to complexity.
```

**Update Hard Rules:**

Remove:
```
Escalation upward only -- if work grows, re-assess tier, never downgrade
```

**Update Milestone Notes table:**

Remove the `tier:` row.

**Update frontmatter version:** 2.2.2 -> 2.3.0

### 3. Pre-Change Gate Hook (`hooks/pre-change-gate`)

Remove the `warn_no_tier` check (lines 74-77 that grep for `tier:` in notes).
The hook still checks for active task existence — that is the real gate.

### 4. CLAUDE.md

Remove any tier references. The Quick Reference stays structurally the same
but without the tier escalation rule. Update the "Validate" line if it references
tier-specific tests.

### 5. README.md

Update the `/start` example from:
```
/claude-workstation:start "Fix typo in README"
# -> Assesses tier -> Trivial -> creates task -> "Go fix it"
```

To:
```
/claude-workstation:start "Fix typo in README"
# -> Creates task -> "Brainstorm or plan?"
```

Remove any other tier language from skill descriptions.

### 6. Version Bump

2.2.2 -> 2.3.0 in:
- `skills/start/SKILL.md` (frontmatter)
- `skills/workflow/SKILL.md` (frontmatter)
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`

### 7. Tests

- Delete tier-specific scenarios: `trivial.sh`, `small.sh`, `medium.sh`,
  `medium-plus.sh`, `escalation.sh` (these test tier routing, which no longer exists)
- Add a new scenario `full-pipeline.sh` that verifies any task goes through
  plan -> TDD -> review -> verify regardless of size
- Remove `persist_tier` step from `tests/specs/start.yaml`
- Remove `warn_no_tier` step from `tests/specs/pre-change-gate.yaml`
- Remove `detect_tier_only` step from `tests/specs/position-detection.yaml`
- Update `init-persistence.sh` to not assert tier in notes
- Add new test: `/start` creates task and presents brainstorm/plan choice

### 8. Old Design Specs

`docs/superpowers/specs/2026-04-10-workflow-v2-design.md` and
`docs/superpowers/plans/2026-04-10-workflow-v2.md` are historical documents.
Do not modify them — they record what was decided at that time.

## Not Changing

- Brainstorming skill — untouched
- Writing-plans skill — untouched
- TDD, code-review, verification, finishing skills — untouched
- Side-quest flow in `/start` — untouched
- Beads itself — untouched
- Context7 requirement — untouched

## Risks

1. **Loss of automatic epic creation.** Previously Medium/Medium+ tasks became epics
   automatically. Now users must manually create epics or the planning skill must
   handle decomposition. Mitigation: writing-plans already creates sub-tasks; epic
   creation can happen there when needed.

2. **Loss of automatic priority scaling.** Previously critical-sounding tasks got P1
   automatically. Now everything defaults to P2 unless overridden with `-p`.
   Mitigation: `-p` flag still works; explicit is better than keyword-guessing.

3. **Test scenarios need rewriting, not just deleting.** The tier-specific scenarios
   test real user flows (single-file fix, multi-file feature, etc.). The flows still
   exist — they just all go through plan now. Rewrite as pipeline tests.
