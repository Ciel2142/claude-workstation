# Workflow Context

All work follows a size-based flow: Beads (tracking) + Superpowers (process) + ECC (expertise).

## Beads-First Rule

Before invoking ANY Superpowers skill, create a beads task first. Sequence: `bd create` → then invoke skill. This applies to ALL work — design, planning, research, and code.

## Task Sizing

| Tier | Signal | Flow |
|---|---|---|
| **Trivial** | ≤1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | `bd create -t epic` → brainstorm → plan → sub-tasks → spike → worktree → TDD → review → verify → update-docs → finish → `bd close` |
| **Bug** | Any tier, type=bug | `bd create -t bug` → debug → TDD (regression test) → review → verify → `bd close` |

Escalation only upward — never downgrade.

## Hard Rules

- No work without a beads task
- No Superpowers skill invocation without an active beads task
- No production code without a failing test (Small/Medium+)
- No completion claims without verification output
- No trusting subagent reports without own verification

## Spec Amendments

When implementation reveals the spec is wrong, amend it — don't silently deviate.

**Minor (agent self-approves):** Naming mismatches, missing edge case detail, clarifying ambiguous wording, parameter type corrections to match existing code.
- Update the spec file, commit, log: `spec-amendment: minor -- <what changed>`
- Continue without interruption.

**Material (requires human approval):** Different algorithm, adding/dropping features, new dependencies, changed API shape, architectural changes.
- Stop implementing and present the change, wait for approval.
- Log: `spec-amendment: material -- <what changed>, approved by human`

Applies to Small and Medium+ tiers. Trivial tasks have no spec.

## Sub-task Micro-tiers

Within a Medium+ epic, each sub-task gets a micro-tier that determines ceremony level.

| Micro-tier | Signal | Ceremony |
|---|---|---|
| **Micro-trivial** | Config, wiring, exports, type files, boilerplate. No logic. | Micro-TDD (one assertion) → commit. Batch review every 3 tasks. |
| **Micro-small** | Single-concern logic, one function/method, straightforward. | Full TDD (red-green-refactor) → commit. Batch review every 3 tasks. |
| **Micro-complex** | New algorithm, security-sensitive, public API, cross-cutting. | Full TDD → individual code review → commit. |

When claiming a sub-task, assess its micro-tier. Log: `micro-tier: <micro-trivial|micro-small|micro-complex>`

**Micro-TDD:** One assertion proving the wiring works (import resolves, config parses, type compiles).

**Batch review cadence:** After every 3rd non-complex task, dispatch one batch code review. Micro-complex tasks get individual reviews and reset the batch counter.

## Skill References

On-demand skills for specific workflow phases — invoke when reaching that step:
- **Bug work** → `/claude-workstation:debugging-protocol` (root cause before fix, 3-strike rule)
- **Spike phase** (Medium+) → `/claude-workstation:spike-phase` (lightweight or deep validation)
- **Every 3rd sub-task** (Medium+) → `/claude-workstation:scope-health` (scope creep detection)
- **Milestone notes** → `/claude-workstation:beads-milestones` (standardized checkpoint format)
- **Verification** → `/claude-workstation:verification-template` (output format with exit codes)

## Plugin Routing

- **Beads** → all persistent task/issue tracking (`bd` commands). No TodoWrite for persistent work.
- **Superpowers** → all development process (brainstorming, planning, TDD, code review, verification, debugging, parallel agents, finishing branches).
- **ECC** → all language-specific and domain-specific skills, agents, and patterns. Use within the Superpowers-driven process.

When both apply: Superpowers drives the process, ECC provides expertise within it.

## Research & Reuse

Before any new implementation:
1. GitHub code search first (`gh search repos`, `gh search code`)
2. Library docs second (Context7 or vendor docs)
3. Check package registries before writing utility code
4. Search for adaptable open-source implementations
5. Prefer proven approaches over net-new code

## Side Quests

Discover something unrelated mid-work:
```
bd create --title="Found: <issue>" --type=bug
bd dep add <new-id> <current-id> --type=discovered-from
```
Finish current task first, then `bd ready`.

Run `/help` for detailed step-by-step flows with full ceremony for each tier.
