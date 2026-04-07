# Flow Integrity Audit — Design Spec

**Date:** 2026-04-07
**Epic:** claude-workstation-d1m
**Tier:** Medium+

## Goal

Produce a findings document covering all internal workflow rules, hooks, skills,
and tests for: consistency drift, enforcement blind spots, rationalization
surface, and fragility. Findings only — no code changes in the audit phase.

## Motivation

In a previous session, an agent fixed `_gate_cache()` in `test-behaviors.sh`
without creating a beads task first. The file was outside confirmed scope. The
agent rationalized "my change caused it" — which is exactly the violation class
the Side Quests rule was designed to prevent. Root cause: the word "unrelated"
in the Side Quests trigger was subjective; more capable models rationalize
better, creating an inverse scaling problem. The wording was tightened to
"outside confirmed scope" and the Verification Failure Protocol (Type A/B/C)
and Collateral Breakage Rule were added. This audit checks whether similar
loopholes exist elsewhere.

## Scope

### In scope

All files in the claude-workstation plugin:

- `contexts/workflow.md` — primary rule source
- `commands/help.md` — mirror of workflow rules
- `skills/*/SKILL.md` — 10 skills (start, resume, setup, test, status,
  debugging-protocol, beads-milestones, spike-phase, scope-health,
  verification-template)
- `hooks/*` — session-start, pre-change-gate, stop, bd-notes-append, hooks.json
- `tests/validate-config.sh`, `tests/test-behaviors.sh`, `tests/lib.sh`
- `CLAUDE.md`, `AGENTS.md`, `README.md`
- `profiles/aliases.sh`

### Out of scope

External plugin behavior (Superpowers, ECC, Beads internals). We verify our
wiring references are consistent, but do not validate what those plugins do.

## Severity Levels

| Severity | Definition | Example |
|---|---|---|
| **Break** | Agent follows rules and gets wrong outcome — incorrect routing, lost data, skipped ceremony | `resume` routes to wrong skill for a position |
| **Drift** | Two sources of truth say different things | `workflow.md` says X, `help.md` says Y |
| **Blind spot** | Workflow rule exists only as text with no mechanical enforcement | "No code without failing test" has no hook |
| **Fragile** | Works today but breaks under realistic conditions | sed pattern truncates on unexpected input |
| **Info** | Cosmetic, stale reference, documentation gap — no behavioral impact | README count stale |

## Audit Lenses

| Lens | Question |
|---|---|
| Consistency | Do all sources agree? |
| Enforcement | Is there a mechanical check? |
| Gaps | Can an agent follow rules and still fail? |
| Rationalization surface | Are there subjective terms an agent could interpret away? |

## Audit Passes

### Pass 1: Consistency

For every rule that appears in more than one file, verify wording matches.
Primary source of truth: `workflow.md`. Everything else must agree or explicitly
defer.

Key cross-reference pairs:

- `workflow.md` <-> `help.md` (full mirror — identical in substance)
- `workflow.md` <-> `start/SKILL.md` (tier thresholds, scoring, routing)
- `workflow.md` <-> `resume/SKILL.md` (position detection, skill routing)
- `workflow.md` <-> `status/SKILL.md` (position detection, suggestion table)
- `resume/SKILL.md` <-> `status/SKILL.md` (identical position detection)
- `workflow.md` <-> `debugging-protocol/SKILL.md` (bug path)
- `beads-milestones/SKILL.md` <-> `resume/SKILL.md` (milestone key names)
- `workflow.md` <-> `CLAUDE.md` (top-level claims)
- `workflow.md` <-> `README.md` (tier table, hook descriptions)
- Tier definitions across all files that mention them

### Pass 2: Enforcement

For each workflow gate/rule, determine what enforces it:

| Rule | Expected enforcement |
|---|---|
| No code without beads task | `pre-change-gate` hook |
| Tier assessment before work | `pre-change-gate` checks for `tier:` in notes |
| No skipping tiers downward | ? |
| Scope confirmation before changes | ? |
| Side-quest for out-of-scope discoveries | ? |
| No production code without failing test | ? |
| Milestone updates at phase transitions | ? |
| Spec amendments logged | ? |
| Scope health every 3rd sub-task | ? |
| Session close protocol (commit + push) | `stop` hook |
| Beads-first rule | `pre-change-gate` hook |
| Pre-change gate (3-step check) | `pre-change-gate` hook (partial) |

Classify as blind spot if no enforcement exists.

### Pass 3: Rationalization Surface

Read every rule looking for:

- Subjective terms ("unrelated", "seems", "appropriate", "reasonable")
- Conditional escapes ("unless", "when warranted", "if needed")
- Implied judgment without criteria ("assess whether", "determine if")
- The "unrelated" pattern: a word that feels precise but lets agents rationalize

Focus areas:

- Pre-Change Gate conditions
- Side Quest triggers
- Scope Confirmation rules
- Escalation triggers
- Claude Override in `/start` scoring
- Micro-tier assessment criteria
- Spec amendment minor/material threshold

### Pass 4: Fragility

For each hook and script, check:

- Error paths that silently succeed (exit 0 on failure)
- Assumptions about `bd` output format
- Cache/state that could go stale
- Missing edge cases in tests
- Shell portability gaps not covered by test section 18

## Output Format

Single findings document: `docs/superpowers/specs/2026-04-07-flow-integrity-findings.md`

```
# Flow Integrity Audit — Findings

## Summary
- Break: N | Drift: N | Blind spot: N | Fragile: N | Info: N

## Pass 1: Consistency
### D1: [title]
**Severity:** Drift
**Files:** workflow.md:LNN, help.md:LNN
**Finding:** [what differs]
**Evidence:** [exact text from each file]

## Pass 2: Enforcement
### BS1: [title]
...

## Pass 3: Rationalization Surface
### R1: [title]
...

## Pass 4: Fragility
### F1: [title]
...
```

Finding IDs: D=drift, BS=blind spot, R=rationalization, F=fragile, B=break,
I=info.

## Execution Plan

Four parallel agents, one per pass. Each agent reads the relevant files and
produces findings in the format above. Results merged into the final document.

## Approach

Audit-then-fix: produce the findings document first, user reviews it, then
create sub-tasks to fix findings as part of this epic.
