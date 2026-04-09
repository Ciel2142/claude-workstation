# Workflow v2: Unified Lean Workflow

## Problem

The current workflow spans 506 lines across two files:
- `contexts/workflow.md` (206 lines, auto-injected every session)
- `commands/help.md` (300 lines, on-demand)

Additional bloat:
- `skills/setup/SKILL.md` (164 lines) duplicates what each plugin's own README covers
- `skills/continue/SKILL.md` (327 lines) for session recovery that a one-liner handles

Issues:
1. **Context budget waste** — 206 lines auto-injected when ~30 would suffice
2. **Redundancy** — 14 concepts duplicated across both files
3. **Verbosity** — 2-6x more words than needed for shared concepts (compared to template-bridge reference)
4. **19 standalone protocols** — most either redundant with skills that own them, or compressible to one-liners
5. **Setup skill** — each plugin (Beads, Superpowers, ECC) has its own install docs; no need for a wrapper

## Solution

Adopt the template-bridge architecture: lean always-on cheatsheet (auto-injected via SessionStart hook) + full workflow as on-demand skill. Drop setup and continue skills.

### Architecture

| Layer | File | Size | Delivery |
|---|---|---|---|
| Always-on | SessionStart hook injects cheatsheet | ~30 lines | Auto-injected every session (guaranteed) |
| Backup | Plugin `CLAUDE.md` | ~30 lines (same content) | Auto-loaded by Claude Code (if supported) |
| On-demand | `skills/workflow/SKILL.md` | ~120 lines | Loaded when invoked or when `/start` routes |

Note: Plugin CLAUDE.md auto-loading is not guaranteed across all environments. The SessionStart hook is the primary delivery mechanism (following template-bridge's approach of hook-based injection). CLAUDE.md serves as backup for environments that do load it.

### Context budget

| Before | After | Reduction |
|---|---|---|
| ~230 lines always-on (CLAUDE.md + workflow.md) | ~30 lines always-on (hook-injected) | 87% |
| ~1020 lines total (workflow + help + setup + continue) | ~150 lines total (CLAUDE.md + workflow skill) | 85% |

## File Changes

### 1. Plugin `CLAUDE.md` — REWRITE (~30 lines)

Structure mirrors template-bridge CLAUDE.md:

```markdown
## Workflow: Beads + Superpowers + ECC

Before starting ANY task, invoke `/claude-workstation:start "description"` to assess and route.
For the full workflow reference, invoke `/claude-workstation:workflow`.

### Quick Reference (scale ceremony to complexity)

1. **Task** -- `bd create "Goal"` (every change gets tracked)
2. **Brainstorm** -- `superpowers:brainstorming` (design before code)
3. **Plan** -- `superpowers:writing-plans` (decompose into sub-tasks)
4. **Sub-tasks** -- `bd create` for each + `bd dep add` (parent-child, blocks)
5. **Implement** -- `bd ready` -> pick -> `bd update --claim` -> TDD (RED -> GREEN -> REFACTOR)
6. **Review** -- `superpowers:requesting-code-review`
7. **Verify** -- `superpowers:verification-before-completion` (evidence before claims)
8. **Finish** -- `superpowers:finishing-a-development-branch`
9. **Close** -- `bd close <id>`

### Hard Rules

- No code without a beads task
- No production code without a failing test
- No completion claims without verification output
- No trusting subagent reports without own verification
- Query Context7 before implementing with any library/framework
- Escalation upward only -- if work grows, re-assess tier, never downgrade
- Invoke `/ecc:strategic-compact` every 3rd closed sub-task
- Outside scope = side-quest: `bd create -t bug` + `bd dep add new current --type=discovered-from`, finish current first

### Session

- **Resume:** `bd list --status=in_progress` -> `bd show <id>` -> read notes for spec/plan paths
- **Validate:** `/claude-workstation:test`

### Prerequisites

Install each plugin following its own documentation:
- [Beads](https://github.com/steveyegge/beads) -- task tracking
- [Superpowers](https://github.com/obra/superpowers) -- development methodology
- [ECC](https://github.com/affaan-m/everything-claude-code) -- domain expertise
```

### 2. `hooks/session-start` — SIMPLIFY

Keep beads auto-init (Step 0) and server configuration (Step 1). Replace workflow.md injection (Step 2) with injection of the lean cheatsheet content from CLAUDE.md (~30 lines).

The hook reads `CLAUDE.md` instead of `contexts/workflow.md` and injects it as `additionalContext`. Same mechanism, smaller payload.

### 3. `skills/workflow/SKILL.md` — CREATE (~120 lines)

Full workflow reference, loaded on-demand. Contains:

```
Section 1: THE STACK (3 lines)
  Beads = WHAT (task tracking, bd CLI)
  Superpowers = HOW (development methodology, rigid skills)
  ECC = expertise (language/domain skills within Superpowers process)

Section 2: THE FLOW (10 lines)
  Single canonical sequence:
  Task -> Brainstorm -> Plan -> Sub-tasks -> TDD per sub-task -> Verify -> Finish -> Close
  Not every task needs every step. /start assesses complexity and suggests entry point.
  Brainstorm produces spec in docs/superpowers/specs/
  Plan produces plan in docs/superpowers/plans/
  Sub-tasks: bd create for each, bd dep add for dependencies
  Implement: bd ready -> claim -> TDD (RED verify fail, GREEN verify pass, REFACTOR) -> commit
  Verify: run proving command fresh, read output, verify it supports the claim

Section 3: PRE-CHANGE GATE (5 lines)
  Before any file change:
  (1) Task boundary -- shifting from discussion to action? bd create first.
  (2) Task exists? No task = no change.
  (3) Scope confirmed this turn? Restate files/changes, get explicit "yes."
  Exceptions: files listed in plan/sub-task description, /start invocations.

Section 4: HARD RULES (8 lines)
  Same as CLAUDE.md (canonical source is CLAUDE.md; repeated here for skill-load context)

Section 5: SKILL INVOCATION PRIORITY (4 lines)
  1. Context7 -- fresh docs for any library/framework
  2. Process skills -- brainstorming, debugging, verification
  3. Implementation skills -- TDD, code-review, frontend-design
  4. ECC domain skills -- language-specific reviewers, build fixers

Section 6: TASK DECOMPOSITION (10 lines)
  Four dependency types:
  | Type           | Affects bd ready | Use when                              |
  | blocks         | YES              | Sequential work, technical prereqs    |
  | parent-child   | No               | Epic -> sub-task structure             |
  | related        | No               | Connected but independent             |
  | discovered-from| No               | Side-quest found during implementation |
  Direction rule: "X needs Y" -> bd dep add X Y
  Ready Fronts: as tasks close, blocked work auto-unblocks. bd ready shows what's available.

Section 7: KEY SKILLS REFERENCE (16 lines)
  | Skill                          | When                              | Type     |
  | brainstorming                  | Before any creative/feature work  | Rigid    |
  | writing-plans                  | After brainstorm approval         | Rigid    |
  | test-driven-development        | During all implementation         | Rigid    |
  | systematic-debugging           | Any bug or test failure           | Rigid    |
  | verification-before-completion | Before claiming done              | Rigid    |
  | requesting-code-review         | After implementation              | Flexible |
  | receiving-code-review          | When getting feedback              | Rigid    |
  | using-git-worktrees            | Non-trivial feature isolation     | Flexible |
  | subagent-driven-development    | Executing plans, independent tasks| Flexible |
  | executing-plans                | Following pre-written plans       | Flexible |
  | finishing-a-development-branch | Tests pass, ready to merge        | Rigid    |
  | dispatching-parallel-agents    | 2+ independent problems           | Flexible |

Section 8: MILESTONE NOTES (10 lines)
  Update beads notes to preserve context across sessions and compaction.
  | Key              | When                    | Key              | When                    |
  | tier:            | After /start            | completed:       | Sub-task closes         |
  | spec:            | After brainstorming     | current:         | Claiming sub-task       |
  | plan:            | After writing plan      | debug:           | Root cause found        |
  | planned-tasks:   | Sub-tasks created       | verification:    | After verification      |
  | stopped:         | Session end / compact   | active-skill:    | Skill invoked           |
  Write via: bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "key: value"

Section 9: SIDE QUESTS (4 lines)
  Problem outside your confirmed scope -- even if your change caused it:
  bd create --title="Found: <issue>" --type=bug
  bd dep add <new-id> <current-id> --type=discovered-from
  Finish current task first, then bd ready. Size of fix does not reduce ceremony.

Section 10: ANTI-PATTERNS (8 lines)
  - Skip brainstorming -> "just code it"
  - Write code before failing test
  - Claim "fixed" without verification output
  - Work without beads task
  - Multiple fixes simultaneously
  - Trust subagent reports without own verification
  - Qualifier language ("should work", "probably fixed")
  - Implement with library without querying Context7
  
Section 11: PLUGIN ROUTING (3 lines)
  Beads -> task tracking (bd CLI). No TodoWrite.
  Superpowers -> process (brainstorm, plan, TDD, review, verify, debug, finish).
  ECC -> language/domain expertise within Superpowers process.
  Before new implementation: search existing tools first, library docs second (Context7), build last.
```

### 4. `contexts/workflow.md` — DELETE

Content merged into `skills/workflow/SKILL.md`.

### 5. `commands/help.md` — DELETE

Content merged into `skills/workflow/SKILL.md` and `CLAUDE.md`. The detailed per-tier paths (Trivial Path, Small Path, Medium Path, etc.) are dropped -- `/start` handles tier routing at invocation time.

### 6. `skills/continue/SKILL.md` — DELETE

Replaced by one-liner session recovery in CLAUDE.md:
```
Resume: bd list --status=in_progress -> bd show <id> -> read notes for spec/plan paths
```

### 7. `skills/setup/SKILL.md` — DELETE

Each plugin has its own installation docs:
- Beads: https://github.com/steveyegge/beads
- Superpowers: https://github.com/obra/superpowers
- ECC: https://github.com/affaan-m/everything-claude-code

CLAUDE.md lists prerequisites with links. Beads auto-init is handled by SessionStart hook.
The setup skill was wrapping `/plugin install` commands that each plugin's README already documents.

### 8. `/start` skill — NO CHANGE (this task)

`/start` continues to own tier assessment and skill routing. The tier system is an internal implementation detail of `/start`, no longer explained in workflow context. Future optimization of `/start` is a separate task.

## What We Keep vs. Drop

### Kept (in workflow skill)

| Protocol | Lines | Rationale |
|---|---|---|
| Pre-Change Gate | 5 | Real enforcement, catches untracked work |
| Milestone Notes | 10 | Structured context recovery across sessions |
| Side Quests | 4 | Disciplined discovery handling |

### Kept as one-liner hard rules

| Rule | Rationale |
|---|---|
| Escalation upward only | Prevents ceremony downgrade |
| Strategic compact every 3rd sub-task | Context preservation without heavyweight protocol |
| Context7 before implementation | Prevents stale-docs bugs |
| No trusting subagent reports | Verification discipline |

### Dropped (owned by skills or unnecessary)

| Protocol | Lines saved | Why dropped |
|---|---|---|
| Task Sizing table | 17 | `/start` owns tier routing |
| Per-tier paths (Trivial/Small/Medium/Medium+/Project) | 100+ | `/start` routes; skills define their own process |
| Scope Confirmation | 5 | Pre-Change Gate covers this |
| Spec Amendments | 10 | Brainstorming/writing-plans skills own this |
| Spec Coverage Gate | 7 | Writing-plans skill owns this |
| Micro-tiers + Review Level | 18 | Tier table applied to sub-tasks; code-review skill judges |
| Spike Phase | 6 | Writing-plans skill can mention it |
| Scope Health Check | 3 | Compressible to nothing; strategic-compact covers |
| Plan Phases | 17 | Writing-plans skill structures phases |
| Strategic Compaction (full protocol) | 31 | Replaced by one-liner invoking the skill |
| Verification Format | 7 | Verification skill prescribes its own format |
| Project Decomposition | 57 | Brainstorming skill handles scope assessment |
| Greenfield Gate | 10 | Brainstorming skill's clarifying questions |
| Verification Failure A/B/C | 16 | Covered by side quests rule |
| Escalation paths (detailed) | 10 | One-liner sufficient |
| After Closing checklist | 7 | Obvious, agents know this |

### Added (from reference)

| Concept | Lines | Source |
|---|---|---|
| Canonical flow sequence | 10 | template-bridge |
| Dependency type table + direction rule | 10 | template-bridge |
| Skill invocation priority | 4 | template-bridge |
| Skills reference table | 16 | template-bridge |

## Risks

1. **Skills losing their protocols.** Dropped protocols (spec amendments, spec coverage, micro-tiers, etc.) must be owned by their respective Superpowers skills. If those skills don't already contain this logic, it's lost. Mitigation: verify each dropped protocol exists in its target skill before deleting.

2. **`/start` becomes the only tier-aware component.** If an agent doesn't use `/start`, they won't get tier routing. Mitigation: CLAUDE.md says "invoke `/start` before ANY task" -- same pattern as the reference.

3. **Session recovery is weaker.** `/continue` had deep context loading (spec files, plan files, sub-task statuses, worktree detection). The one-liner replacement relies on agent judgment. Mitigation: milestone notes preserve enough breadcrumbs for manual recovery.

4. **Setup discoverability.** New users won't have a guided setup experience. Mitigation: CLAUDE.md lists prerequisites with GitHub links; each plugin's docs are comprehensive.

## Out of Scope

- Optimizing `/start` skill (tier gates, side-quest detection) -- separate task
- Modifying Superpowers skills to absorb dropped protocols -- separate task (Risk 1)
- Changing hook infrastructure (pre-change-gate, stop hooks) -- unchanged
- AGENTS.md changes -- unchanged

## Summary of Deletions

| File | Lines removed | Replacement |
|---|---|---|
| `contexts/workflow.md` | 206 | `skills/workflow/SKILL.md` (~120 lines) |
| `commands/help.md` | ~300 | Merged into workflow skill + CLAUDE.md |
| `skills/continue/SKILL.md` | 327 | One-liner in CLAUDE.md |
| `skills/setup/SKILL.md` | 164 | Prerequisites section in CLAUDE.md + plugin READMEs |
| **Total removed** | **~997 lines** | **~150 lines** |
