# Unified Workflow

All work follows a size-based flow connecting Beads (tracking) + Superpowers (process) + ECC (expertise).

## Beads-First Rule

Before invoking ANY Superpowers skill (brainstorming, writing-plans, TDD, code-review, debugging, verification, etc.), create a beads task first. The beads task is the anchor — skills are the process. Sequence: `bd create` → then invoke skill. This applies to ALL work, including design and planning — not just code.

## Task Sizing

| Tier | Signal | Flow |
|---|---|---|
| **Trivial** | ≤1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | `bd create -t epic` → brainstorm → plan → sub-tasks → worktree → TDD → review → verify → finish → `bd close` |
| **Bug** | Any tier, type=bug | `bd create -t bug` → debug → TDD (regression test) → review → verify → `bd close` |

**Escalation only upward.** If work grows beyond current tier, stop and escalate — never downgrade.

## Rules

- No work without a beads task — not just code, ALL work (design, planning, research)
- No Superpowers skill invocation without an active beads task
- No production code without a failing test (Small/Medium+)
- No completion claims without verification output
- No trusting subagent reports without own verification

## Spec Amendments

When implementation reveals the spec is wrong, amend it — don't silently deviate.

**Minor (agent self-approves):** Naming mismatches, missing edge case detail,
clarifying ambiguous wording, parameter type corrections to match existing code.
- Update the spec file, commit, log: `spec-amendment: minor -- <what changed>`
- Continue without interruption.

**Material (requires human approval):** Different algorithm, adding/dropping features,
new dependencies, changed API shape, architectural changes.
- Stop implementing and present:
  ```
  Spec amendment needed (material):
    Section: <which part>
    Current: <what spec says>
    Proposed: <what it should say>
    Reason: <what implementation revealed>
    Approve? [Y/n/discuss]
  ```
- Wait for approval. On yes: update spec, commit, log: `spec-amendment: material -- <what changed>, approved by human`
- Resume implementation.

Applies to Small and Medium+ tiers. Trivial tasks have no spec.

## Sub-task Micro-tiers

Within a Medium+ epic, each sub-task gets a micro-tier that determines ceremony level.

| Micro-tier | Signal | Ceremony |
|---|---|---|
| **Micro-trivial** | Config, wiring, exports, type files, boilerplate. No logic. | Micro-TDD (one assertion) -> commit. Batch review every 3 tasks. |
| **Micro-small** | Single-concern logic, one function/method, straightforward. | Full TDD (red-green-refactor) -> commit. Batch review every 3 tasks. |
| **Micro-complex** | New algorithm, security-sensitive, public API, cross-cutting. | Full TDD -> individual code review -> commit. |

**Assignment:** When claiming a sub-task, assess its micro-tier from the plan description.
Log: `micro-tier: <micro-trivial|micro-small|micro-complex>`

**Micro-TDD:** One assertion proving the wiring works:
- Import resolves: `expect(() => require('./newModule')).not.toThrow()`
- Config parses: `expect(loadConfig()).toHaveProperty('newKey')`
- Type compiles: `tsc --noEmit` passes

**Batch review cadence:** After every 3rd non-complex task, dispatch one batch code
review covering all changes since the last review. Micro-complex tasks get individual
reviews and reset the batch counter to 0.

## Side Quests

Discover something unrelated mid-work:
```
bd create --title="Found: <issue>" --type=bug
bd dep add <new-id> <current-id> --type=discovered-from
```
Finish current task first, then `bd ready`.

Run `/workflow` for detailed step-by-step flows.
