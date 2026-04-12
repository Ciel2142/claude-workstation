# Verification Backbone Design

**Beads epic:** `claude-workstation-fg0j`
**Date:** 2026-04-12
**Status:** Approved, pending implementation plan

## Problem

The current claude-workstation orchestrator has four ad-hoc hooks (`milestone-gate`, `agent-gate`, `commit-gate`, `stop-gate`) and a two-phase review loop (spec → quality). It has no formal gate semantics, no goal-backward verification, and no final truth-check that reads code instead of trusting subagent SUMMARY reports.

This leaves a hallucination hole: an implementer subagent can mark `tdd:ready-for-review`, a reviewer can return `VERDICT: PASS` on stub code, and the orchestrator can close the task with no file ever being correctly wired. We have already seen subagents claim "done" while code was a placeholder.

GSD (`gsd-build/get-shit-done`) has solved this exact class of problem with a formal gate taxonomy, a `must_haves` schema for goal-backward verification, a dedicated verifier agent with a "do not trust SUMMARY" mandate, and H2 sentinel completion markers. This spec steals that spine and grafts it onto the existing orchestrator.

## Goals

1. Every orchestrator checkpoint maps to one of four canonical gate types (pre-flight, revision, escalation, abort).
2. Plans carry a machine-readable `must_haves` block (truths, artifacts, key_links) that planners write, implementers read, and verifiers check.
3. A dedicated verifier subagent runs after quality review, reads source files directly, and never trusts the subagent-generated summary.
4. Revision loops escalate early on stall (issue count not decreasing) rather than burning the full 3-cycle budget.
5. Subagents emit H2 sentinels in their response body as the primary completion signal; beads milestones remain as the durable cross-session trail.
6. Orchestrator performs a filesystem spot-check after any "complete" sentinel to catch subagents that log completion without touching files.

## Non-Goals

- Multi-plan / wave execution (belongs to epic `b2cj`).
- Progress hoisting / spatial `AGENTS.md` context layers (belongs to epic `wk69`).
- Fingerprint-based stall detection (count-only is enough for v1; revisit if evidence warrants).
- Stall re-planning re-entry. GSD has it because GSD is user-interactive; this orchestrator is autonomous.
- Verifier writing code, creating side-quests, or performing any action beyond report-and-stop.

## Architecture

### Change Surface

| File | Change |
|------|--------|
| `skills/workflow/SKILL.md` | New "Gate Taxonomy" section, extended milestone table |
| `skills/orchestrator/SKILL.md` | Add Step 9.5 (verify phase), stall detection in Steps 6 and 8, H2 sentinel parsing rules |
| `skills/agent-roles/SKILL.md` | Register `verifier` role with template pointer |
| `templates/protocol-verifier.md` | NEW: zero-tolerance verifier contract |
| `templates/protocol-base.md` | Add H2 sentinel requirement and `must_haves` read rule |
| `templates/protocol-implementer.md` | Add `must_haves` read rule, emit `## PLAN COMPLETE` |
| `templates/protocol-reviewer.md` | Emit `## REVIEW PASS` or `## REVIEW BLOCKED` |
| `templates/protocol-planner.md` | Must write `## must_haves` block per task in plan file |
| `templates/protocol-build-fixer.md` | Emit `## BUILD FIXED` or `## BUILD STUCK` |
| `skills/task-scaffolder/SKILL.md` | Append `must_haves: <plan-path>#<anchor>` note per child task |
| `tests/validate-config.sh` | Extend version-bump check; assert each protocol template declares its sentinel |
| `tests/` | New shell tests (see Testing section) |

### Flow Change

Before:

```
claim -> impl -> spec-review loop -> quality-review loop -> close
```

After:

```
claim -> impl -> spec-review loop -> quality-review loop -> VERIFY -> close
```

### Phase Semantics

| Phase | Gate type | On findings |
|-------|-----------|-------------|
| spec-review | Revision | Loop up to 3, count-stall escalates early |
| quality-review | Revision | Loop up to 3, count-stall escalates early |
| verify | Escalation (zero-tolerance) | ANY finding triggers `bd human`, no loop |

### Rationale for Zero-Tolerance Verify

By the time the orchestrator reaches verify, spec review and quality review have both returned PASS. The verifier's job is to catch lies — code that does not exist, `must_haves` not wired, placeholders masquerading as implementation. If the verifier flags anything post-quality-pass, something is deeply wrong and a human must look. Running another revision loop at this point would just give the lying subagent more chances to cover its tracks.

## Gate Taxonomy

Added as a new section in `skills/workflow/SKILL.md` between "Hard Rules" and "Skill Invocation Priority":

| Gate | Purpose | On fail | Where in this repo |
|------|---------|---------|--------------------|
| pre-flight | Check preconditions before work | Block entry, no partial work | `milestone-gate` hook, `commit-gate` hook |
| revision | Evaluate output, loop back to producer | Bounded loop plus stall check | Orchestrator Steps 5–8 (spec and quality review) |
| escalation | Surface unresolvable to human | `bd human <id>`, stop | Orchestrator Step 9.5 verify, stall detection, 3-cycle ceiling |
| abort | Terminate to prevent damage | Hard stop, preserve state | `stop-gate` hook, `agent-gate` hook |

**Selection heuristic** (verbatim from GSD): start pre-flight. If the check happens after work is produced, it is a revision gate. If the revision loop cannot resolve the issue, escalate. If continuing is dangerous, abort.

This section is docs-only. No hook files change. The orchestrator skill cross-references this section rather than redefining the taxonomy.

## Completion Markers (H2 Sentinels)

### Role-to-Sentinel Map

| Role | On success | On failure |
|------|-----------|-----------|
| implementer | `## PLAN COMPLETE` | `## BLOCKED <reason>` |
| reviewer (spec or quality) | `## REVIEW PASS` | `## REVIEW BLOCKED` |
| verifier | `## VERIFICATION PASSED` | `## VERIFICATION FAILED` |
| planner | `## PLAN READY` | `## PLAN BLOCKED <reason>` |
| build-fixer | `## BUILD FIXED` | `## BUILD STUCK` |

### Emission Rules (added to `templates/protocol-base.md`)

1. The sentinel MUST be the last H2 heading in the subagent response.
2. Exactly one sentinel per response.
3. Sentinel AND beads milestone are both required. Missing either causes the orchestrator to reject and re-dispatch.

### Orchestrator Parsing (added to `skills/orchestrator/SKILL.md`)

After a subagent returns, the orchestrator runs this sequence:

1. Grep the response body for registered sentinels (fast path).
2. If no sentinel, run `bd show <task-id>` and check the latest milestone (fallback).
3. If both missing, log `[M] orchestrator:rejected:no-signal` and re-dispatch once. If still missing, escalate to `bd human`.
4. **Filesystem spot-check**: for sentinels that claim completion (`## PLAN COMPLETE`, `## VERIFICATION PASSED`), verify that at least one file in `must_haves.artifacts` was actually modified in this task's workspace (via `git diff --name-only HEAD`). If not, treat as lying and escalate to `bd human` regardless of sentinel.

The filesystem spot-check is the anti-hallucination insurance. Sentinels and milestones can both be written by a hallucinating subagent; files in `git diff` cannot.

## `must_haves` Schema

### Format

Written by the planner into the plan file under each task section:

````markdown
### Task 3: Build verifier subagent template

```yaml
must_haves:
  truths:
    - Verifier refuses to trust SUMMARY-style reports (grep for "do NOT trust" in template)
    - Verifier opens each artifact file and greps for key_link (grep for "Read" or "grep" in verify procedure)
  artifacts:
    - templates/protocol-verifier.md
  key_links:
    - skills/orchestrator/SKILL.md:Step-9.5 -> templates/protocol-verifier.md
    - skills/agent-roles/SKILL.md:role-table -> templates/protocol-verifier.md
```
````

### Field Rules

| Field | Required | Format rule |
|-------|----------|-------------|
| `truths` | at least 1 | Must be provable by a command (grep, test run, file read). No subjective predicates like "code is clean". |
| `artifacts` | at least 1 | Repo-relative path. Must resolve to a real file with non-placeholder content after implementation. |
| `key_links` | 0 or more | Format: `<src>:<anchor> -> <dst>:<anchor>`. Anchors can be line range, symbol, or grep pattern. |

### Scope

- **Epic-level** `## must_haves` at the top of the plan file covers the whole epic.
- **Per-task** `### must_haves` nested under each `### Task N: <title>` covers that task only.

The verifier reads the per-task section first and falls back to epic-level if the task has none.

### Anchor Resolution

The pointer stored in beads notes is `<plan-path>#<anchor>`. Anchor format:

- `task-<N>` — resolves to the YAML fence immediately under `### Task <N>:` heading.
- `epic` — resolves to the YAML fence under the top-level `## must_haves` heading.

Resolution is literal string match on the heading line, not markdown slug computation. If the heading is renamed without updating the anchor, resolution fails and the verifier returns FAIL. This is intentional: renaming a task heading without updating its pointer is drift we want to catch.

### Beads Storage

Plan file is the single source of truth. Beads notes hold a pointer only:

```bash
bash hooks/bd-notes-append <task-id> "must_haves: docs/superpowers/plans/2026-04-12-verification-backbone-plan.md#task-3"
```

- Note key: `must_haves`
- Value: `<plan-path>#<anchor>`

No YAML copy in beads notes. Caching the `must_haves` content in a note defeats the "do not trust SUMMARY" contract — the verifier must re-read the plan file every invocation.

### Who Reads What

| Role | Action |
|------|--------|
| Planner | Writes `## must_haves` block per task in plan file |
| Task-scaffolder | Appends `must_haves: <plan-path>#<anchor>` note on each child task |
| Implementer | Reads plan file section before TDD to know acceptance truths |
| Verifier | Opens plan file fresh (never cached), parses YAML fence, validates every entry |

### Failure Modes

| Failure | Verifier response |
|---------|-------------------|
| Plan file moved or deleted | `## VERIFICATION FAILED`, report missing plan, orchestrator escalates |
| Anchor not found in plan file | Same |
| YAML fence invalid (strict parse) | Same |
| Artifact file missing | `## VERIFICATION FAILED` with `artifact: <path> -> missing` |
| Artifact file is a stub (TODO only, `pass`, `throw new Error("not implemented")`) | `## VERIFICATION FAILED` with `artifact: <path> -> stub` |
| Truth command fails | `## VERIFICATION FAILED` with `truth: <desc> -> failed` |
| Key-link one-sided (src mentions dst but dst has no incoming hook) | `## VERIFICATION FAILED` with `key_link: <src> -> <dst> -> missing-dst` |

## Verifier Protocol (`templates/protocol-verifier.md`)

```markdown
# Verifier Bead Protocol

Zero-tolerance final check. Revision already ran. Spec and quality already passed.
Your job: catch lies.

## Core Mindset

Do NOT trust the subagent's SUMMARY or `## PLAN COMPLETE` marker.
Do NOT re-run the tests the implementer claimed to pass.
Open each file. Read actual code. Verify `must_haves` are wired.

## Self-Gather Context

1. `bd show <task-id>` — read the `must_haves` note pointer.
2. Open the plan file at that path. Parse YAML under the matching anchor.
3. For each entry in `must_haves`, verify independently.

## Verification Procedure

For each artifact:
- Read tool: open the file. Does it exist? Does it contain more than 10 lines of real code (not placeholder)?
- Grep for stub patterns: `TODO`, `pass  # implement`, `throw new Error("not implemented")`, `raise NotImplementedError`.

For each truth:
- If the truth specifies a prove command, run it. Read exit code and output.
- If the truth is "file X contains Y", grep directly.

For each key_link:
- Parse as `<src>:<anchor> -> <dst>:<anchor>`.
- Grep the src file for a reference to dst. Grep the dst file for the incoming hook from src.
- Both sides must match. One-sided = BLOCKED.

## Structured Report Format

VERIFY: <task-id>
PLAN: <plan-path>
VERDICT: PASS | FAIL

CHECKED:
- artifact: <path> -> <exists|missing|stub>
- truth: <description> -> <verified|failed> (evidence: <output snippet>)
- key_link: <src> -> <dst> -> <wired|missing-src|missing-dst>

ISSUES: (empty if PASS)
- [BLOCKER] <category>: <file>:<line> <specific description>

## Rules

1. Zero findings = PASS. Any finding = FAIL.
2. FAIL always escalates. There is no revision loop at this phase.
3. Report only. Do NOT fix code. Do NOT create tasks. Do NOT write milestones other than the one your role requires.
4. Read files directly. Never trust upstream reports.
5. Emit `## VERIFICATION PASSED` or `## VERIFICATION FAILED` as the last H2.

<!-- BEAD-PROTOCOL-v1:verifier -->
```

## Orchestrator Changes

### New Step 9.5: Dispatch Verifier

Inserted between the current Step 9 (close task) and Step 10 (compact trigger):

```
### Step 9.5: DISPATCH VERIFIER

After quality-review PASS, before close.

1. Read templates/protocol-verifier.md.
2. Build prompt: include protocol + task-id + plan-path from bd notes.
3. Dispatch verifier subagent. Wait.
4. Parse response:
   - `## VERIFICATION PASSED` -> log `[M] orchestrator:verified:<task-id>`, proceed to Step 9 (close).
   - `## VERIFICATION FAILED` -> `bd human <task-id> --reason="verifier found lies"`,
     log `[M] orchestrator:escalated-verify:<task-id>`, STOP this task, move to next.
5. Missing sentinel -> re-dispatch once. Still missing -> `bd human`.
```

Note: the existing Step 9 (close) and Step 10 (compact) keep their current numbers. 9.5 slots in front of close.

### Stall Detection

Added to Step 6 (spec review analysis) and mirrored in Step 8 (quality review analysis):

```
# At top of main loop init, per task:
spec_prev_count = Infinity
quality_prev_count = Infinity
spec_cycles = 0
quality_cycles = 0

# In Step 6, when VERDICT == BLOCKED:
issue_count = count(CRITICAL + HIGH + MEDIUM in FINDINGS)

# Stall check runs BEFORE incrementing cycle counter.
if issue_count >= spec_prev_count:
    log [M] orchestrator:stalled:<task-id> spec <issue_count> >= <spec_prev_count>
    bd human <task-id> --reason="spec review stalled, no progress"
    STOP this task. Move to Step 1.

spec_prev_count = issue_count
spec_cycles += 1

if spec_cycles > 3:
    bd human, stop (existing logic)

# ... existing side-quest dispatch
```

**Zero-issue case:** if FINDINGS is empty or contains only LOW / INFO, the verdict is PASS and the stall check is skipped entirely. Matches GSD.

**No re-planning re-entry.** A single stall escalates to `bd human`. GSD has a `stall_reentry_count` for user-interactive re-planning; this orchestrator is autonomous, so a human decision is the right off-ramp.

## Milestones

New rows appended to the TDD milestone chain in `skills/workflow/SKILL.md`:

| Phase | Prerequisite | Detail |
|-------|-------------|--------|
| `verify:dispatched` | `review:quality` | Orchestrator dispatched verifier |
| `verify:passed` | `verify:dispatched` | Verifier returned `## VERIFICATION PASSED` |
| `verify:failed` | `verify:dispatched` | Verifier returned `## VERIFICATION FAILED` — escalated to `bd human` |

The existing `verified` milestone is rewired: its prerequisite changes from `review:quality` to `verify:passed`.

Full chain after this change:

```
task:created -> task:claimed -> tdd:red -> tdd:red-verified -> tdd:green
-> tdd:green-verified -> tdd:refactor -> tdd:ready-for-review
-> review:spec -> review:quality -> verify:dispatched -> verify:passed
-> verified (close)
```

## Testing Plan

1. **Stall detection unit test** (shell, in `tests/`):
   - Simulate 2 cycles with `findings_count = 3, 3` — assert `bd human` called and milestone logged.
   - Simulate 2 cycles with `findings_count = 3, 2` — assert loop continues, no escalation.

2. **Sentinel parsing unit test** (shell):
   - Feed a fake subagent response containing `## VERIFICATION PASSED` — assert orchestrator parses PASS.
   - Feed response with sentinel missing — assert `bd show` fallback, then re-dispatch.
   - Feed response claiming PASS but no files in `must_haves.artifacts` modified — assert filesystem spot-check catches the lie and escalates.

3. **`must_haves` parsing unit test** (shell):
   - Valid YAML block — artifacts, truths, key_links extracted correctly.
   - Missing anchor in plan file — verifier returns FAIL with `## VERIFICATION FAILED`.
   - Stub file (contains only TODO) listed as artifact — verifier flags stub.

4. **End-to-end integration test**:
   - Write a dummy plan with `must_haves`.
   - Run orchestrator against a single task.
   - Assert all new milestones written in order.
   - Assert verifier dispatched and returned PASS.

5. **`validate-config.sh` extension** (check 13b or new check):
   - Every `protocol-*.md` must declare which sentinel it emits.
   - Version-bump rule must catch the new template file.

## Version Bump

Per `.claude/rules/version-bump.md`:

- `.claude-plugin/plugin.json` — minor bump (new skill content, new template, new orchestrator step)
- `.claude-plugin/marketplace.json` — match
- `skills/*/SKILL.md` frontmatter — match across all skill files

Current `2.7.1` → new `2.8.0`.

## Out of Scope

Explicit deferrals (YAGNI):

- Fingerprint-based stall detection. Count-only is v1. Revisit with real orchestrator telemetry if count-only proves insufficient.
- Stall re-planning re-entry (`stall_reentry_count`). Belongs to a user-interactive workflow, not an autonomous one.
- Verifier writing code, creating side-quests, or any action beyond report-and-stop.
- Multi-plan / wave execution (epic `b2cj`).
- Progress hoisting and spatial `AGENTS.md` context layers (epic `wk69`).

## Success Criteria

1. `skills/workflow/SKILL.md` contains a Gate Taxonomy section mapping existing hooks to the four GSD gate types.
2. Every protocol template declares the H2 sentinel it emits, checked by `validate-config.sh`.
3. A subagent that fabricates completion (emits sentinel + milestone but touches no files) is caught by the orchestrator filesystem spot-check and escalated via `bd human`.
4. A revision loop that produces the same issue count twice in a row is escalated to `bd human` before exhausting the 3-cycle budget.
5. Every task in an implementation plan has a `must_haves` block with at least one truth and one artifact, validated by the verifier subagent.
6. The verifier refuses to trust any upstream SUMMARY, reads source files directly, and returns FAIL on any stub or missing wiring.
7. All existing orchestrator behavior (spec review loop, quality review loop, side-quest creation, cycle limits, compact trigger) remains unchanged except for the additions documented above.
