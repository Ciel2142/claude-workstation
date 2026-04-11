# Deduplicate Workflow/Orchestrator/Agent-Roles/Start/CLAUDE.md

**Date:** 2026-04-12
**Task:** claude-workstation-3r58

## Problem

Five files carry overlapping content. Same concepts (hard rules, milestone chain, subagent protocol, side-quest flow, compact trigger) appear in 2-3 places each. Drift risk, maintenance burden, wasted context tokens.

## Approach

**Distributed ownership with rigid reference pointers.**

Each skill owns its domain concepts fully. When another skill needs content owned elsewhere, it uses a rigid reference — not a copy.

### Rigid Reference Format

```markdown
> **RIGID REF:** Read `skills/<owner>/SKILL.md` § "<section heading>" before proceeding. Do not act on this concept from memory.
```

The `§` + heading gives agents a precise read target. "Do not act from memory" blocks rationalization.

## Ownership Map

| File | Owns | Removes (moved to owner) |
|------|------|--------------------------|
| **CLAUDE.md** | Entry points, prerequisites, caveman mode rules | Hard rules, milestone chain, enforcement hooks table, subagent protocol, session recovery, quick reference pipeline |
| **workflow** | Pipeline overview, hard rules, milestone chain, dep types, Context7, pre-change gate, anti-patterns, skill ref table, session recovery | Orchestrator dispatch detail (§ Orchestrator Protocol), subagent template table (§ Subagent Protocol), side-quest creation commands (§ Side Quests) |
| **orchestrator** | Dispatch loop, cycle limits, verdict parsing, compact trigger, automated side-quest creation, rigid rules, anti-rationalizations | Nothing removed — already self-contained |
| **agent-roles** | Role-to-template mapping, role examples, orchestrator context | Nothing removed — already self-contained |
| **start** | User-initiated side-quest flow, task creation, routing | Enforcement Integration section (lines 103-110) |

## File Changes

### CLAUDE.md (major shrink)

Before: 75 lines with duplicated rules, milestones, hooks, protocol.
After: ~25 lines — entry points, prerequisites, caveman rules, pointers.

```markdown
## Workflow: Beads + Superpowers + ECC

Entry: `/claude-workstation:start "description"`
Reference: `/claude-workstation:workflow`
Orchestrator: `/claude-workstation:orchestrator`

> **RIGID REF:** Read `skills/workflow/SKILL.md` for hard rules, milestones,
> enforcement hooks, and session recovery. Do not act on these from memory.

> **RIGID REF:** Read `skills/agent-roles/SKILL.md` § "How to use" before
> dispatching any subagent. Do not act on role mapping from memory.

### Prerequisites
[kept as-is — CLAUDE.md owns this]

### Caveman Mode Rules
[kept as-is — CLAUDE.md owns this]
```

Removed sections:
- Quick Reference (10-step pipeline) — lives in workflow § "The Flow"
- Hard Rules — lives in workflow § "Hard Rules"
- Enforcement Hooks table — lives in workflow § "Enforcement Milestones"
- Milestone Format + phases — lives in workflow § "Enforcement Milestones"
- Subagent Protocol — lives in agent-roles
- Session recovery — lives in workflow § "Beads Quick Reference"

### workflow (moderate shrink)

Remove three sections, replace with rigid refs:

**Remove § "Subagent Protocol" (lines 167-180).** Replace with:
```markdown
## Subagent Protocol

> **RIGID REF:** Read `skills/agent-roles/SKILL.md` for role-to-template
> mapping before dispatching any subagent. Do not act from memory.
```

**Remove § "Orchestrator Protocol" (lines 184-196).** Replace with:
```markdown
## Orchestrator Protocol

> **RIGID REF:** Read `skills/orchestrator/SKILL.md` for the full rigid
> dispatch loop. Do not act on orchestrator rules from memory.
```

**Remove § "Side Quests" (lines 199-205).** Replace with:
```markdown
## Side Quests

Problem outside confirmed scope — even if your change caused it.

> **RIGID REF:** For user-initiated side-quests, read `skills/start/SKILL.md`
> § "SIDE-QUEST FLOW". For automated side-quests during orchestration, read
> `skills/orchestrator/SKILL.md` § "ANALYZE SPEC REVIEW REPORT".
```

Net: ~219 lines → ~195 lines.

### start (minor)

**Remove § "Enforcement Integration" (lines 103-110).** Replace with:
```markdown
## Enforcement Integration

> **RIGID REF:** Read `skills/workflow/SKILL.md` § "Enforcement Milestones"
> for the full milestone chain and gate requirements. Do not act from memory.
```

### orchestrator — no changes

Already self-contained. Owns its dispatch loop, side-quest creation, cycle limits, compact trigger.

### agent-roles — no changes

Already self-contained. Owns role-to-template mapping.

## What This Does NOT Change

- No behavioral changes. Same workflow, same gates, same enforcement.
- No hook changes. All hooks remain identical.
- No template changes. Protocol templates untouched.
- No test changes needed. `validate-config.sh` checks structure, not prose.
- Orchestrator and agent-roles are untouched files.

## Risk

**Agent skips the rigid ref and acts from stale session context.** Mitigated by:
1. The ref text says "Do not act from memory" — blocks rationalization
2. Hooks still enforce (milestone-gate, agent-gate, commit-gate) regardless of whether the agent read the source
3. The concepts removed from CLAUDE.md are still enforced by hooks — removing the text doesn't remove the enforcement

## Version

Patch bump: 2.6.0 → 2.6.1 (doc cleanup, no behavioral change).
