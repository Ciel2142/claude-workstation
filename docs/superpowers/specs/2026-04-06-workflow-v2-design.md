# Workflow v2: Adaptive Execution Improvements

**Epic:** claude-workstation-geh
**Date:** 2026-04-06
**Status:** Approved

**Goal:** Improve the Medium+ workflow with six enhancements that make execution adaptive, catch scope creep early, preserve context reliably, and enable parallel agent work.

**Scope:** Rules and workflow documentation only. No application code. Changes apply to the claude-workstation project configuration (rules, skills, workflow commands).

---

## 1. Spike Phase

### Summary

A mandatory Task #0 for Medium+ epics that validates architecture assumptions before real implementation begins. Runs after the plan is written and sub-tasks are created, but before the first implementation task.

### Conditional Depth

- **Lightweight (default):** Research artifact only. Confirmed assumptions, file paths for integration points, risk areas. No throwaway code required. ~10-15 minutes.
- **Deep (auto-escalate):** When the plan references unfamiliar APIs, new external libraries, or cross-system data flows. Detected by keywords in plan task descriptions: "API", "integration", "library", "SDK", "migrate", "external". Produces the research artifact plus a minimal proof-of-concept for the riskiest integration. Code is discarded after findings are documented. ~30-60 minutes.

### Output

Stored in the epic's beads notes:

```
spike: <lightweight|deep>
spike-confirmed: <assumption1>, <assumption2>
spike-revised: <assumption that was wrong> -> <correction>
spike-risks: <risk1>, <risk2>
```

### Gate

If the spike reveals the spec is materially wrong (a `spike-revised` entry exists that changes architecture, drops/adds features, or changes API shape), trigger the spec amendment protocol (Section 2) before proceeding to implementation.

### File

New rule: `rules/common/spike-phase.md`

---

## 2. Spec Amendment Protocol

### Summary

A tiered authority system for updating specs when implementation reveals they're wrong. Prevents silent drift between spec and code.

### Minor Amendments (agent self-approves)

Conditions:
- Naming mismatches (spec says `userId`, codebase uses `user_id`)
- Missing edge case detail that doesn't change behavior
- Clarifying ambiguous wording without changing intent
- Parameter type corrections to match existing code

Process:
1. Agent updates the spec file
2. Commits the change
3. Logs in beads notes: `spec-amendment: minor -- <what changed and why>`
4. Continues without interruption

### Material Amendments (requires human approval)

Conditions:
- Different algorithm or data structure than spec proposed
- Adding or dropping a feature/requirement
- New dependency or library not in the original design
- Changed API shape (different endpoints, different request/response format)
- Architectural change (different component boundaries, different data flow)

Process:
1. Agent stops implementing
2. Presents amendment request:
   ```
   Warning: Spec amendment needed (material):
     Section: <which part of the spec>
     Current: <what the spec says>
     Proposed: <what it should say>
     Reason: <what implementation revealed>
     
     Approve? [Y/n/discuss]
   ```
3. Waits for human response
4. On approval: updates spec file, commits, logs: `spec-amendment: material -- <what changed>, approved by human`
5. Resumes implementation

### Applies To

Small and Medium+ tiers. Trivial tasks have no spec.

### File

Extension to `rules/common/unified-workflow.md` — new "Spec Amendments" subsection under Rules.

---

## 3. Sub-task Re-scoring

### Summary

Within a Medium+ epic, each sub-task gets its own micro-tier that determines ceremony level. Reduces overhead for mechanical tasks while maintaining rigor for complex ones.

### Micro-tiers

| Micro-tier | Signal | Ceremony |
|---|---|---|
| **Micro-trivial** | Config, wiring, exports, type files, boilerplate. No logic. | Micro-TDD (one assertion: "does it resolve/parse/load?") -> commit. Batch review every 3 tasks. |
| **Micro-small** | Single-concern logic, one function/method, straightforward behavior. | Full TDD (red-green-refactor) -> commit. Batch review every 3 tasks. |
| **Micro-complex** | New algorithm, security-sensitive, public API surface, cross-cutting logic. | Full TDD -> individual code review -> commit. |

### Assignment

The agent assigns the micro-tier when it picks up a sub-task (`bd update <id> --claim`). It reads the plan's task description and assigns based on the signals above. Logged in beads notes:

```
micro-tier: <micro-trivial|micro-small|micro-complex>
```

### Batch Review Cadence

After every 3rd non-complex task (micro-trivial or micro-small), the agent dispatches a single batch code review covering all changes since the last review. The counter tracks consecutive non-complex tasks only. Micro-complex tasks always get individual reviews, and completing one resets the batch counter to 0.

### Micro-TDD for Micro-trivial Tasks

One assertion proving the wiring works:
- Import resolves: `expect(() => require('./newModule')).not.toThrow()`
- Config parses: `expect(loadConfig()).toHaveProperty('newKey')`
- Type compiles: `tsc --noEmit` passes (the type-check is the test)

Not a full behavioral test suite — just proof the mechanical change didn't break the build.

### File

Extension to `rules/common/unified-workflow.md` — new "Sub-task Micro-tiers" subsection.

---

## 4. Scope Health Check

### Summary

A periodic check during Medium+ implementation that detects when an epic is growing beyond its plan. Uses an escalation ladder: warning at 1.5x, gate at 2.0x.

### Trigger

Automatically after every 3rd sub-task completion within an epic. The agent counts closed sub-tasks and runs the check at 3, 6, 9, etc.

### Measurements

- **Task ratio:** `(total created sub-tasks) / (original planned sub-tasks)`. The original count is stored in beads notes as `planned-tasks: N` when the plan is created.
- **Discovery count:** Sub-tasks created after the initial plan.

### Escalation Ladder

| Trigger | Ratio | Response |
|---|---|---|
| **Warning** | >= 1.5x | Print stats, continue working. Log: `scope-check: warning -- N/M tasks (1.Nx)` |
| **Gate** | >= 2.0x | Print stats, stop, ask human to choose: re-plan, split epic, or continue. Log: `scope-check: gate -- N/M tasks (2.Nx), decision: <choice>` |

### Warning Message Format

```
Scope check (after task N):
   Planned: M tasks | Actual: X tasks (ratio)
   Discovered: Y new tasks since plan
   Warning: scope growing. Consider whether remaining tasks need re-planning.
```

### Gate Message Format

```
Scope check (after task N):
   Planned: M tasks | Actual: X tasks (ratio)
   Discovered: Y new tasks since plan
   Scope exceeded 2x. Options:
      1. Re-plan remaining work (update plan, re-estimate)
      2. Split epic (carve off discovered work into a new epic)
      3. Continue as-is (acknowledge scope growth, keep going)
   
   Pick [1-3]:
```

### Baseline Capture

After all sub-tasks are created from the plan, the agent records `planned-tasks: N` in the epic's beads notes. This is the denominator for all future ratio calculations.

### File

New rule: `rules/common/scope-health.md`

---

## 5. Structured Checkpoints

### Summary

Formalize existing free-text milestone notes into standardized key-value lines that `/resume` can parse reliably. Changes the write side (consistent format in), not the read side (`/resume` already pattern-matches these prefixes).

### Standardized Keys

| Key | Written when | Example |
|---|---|---|
| `tier:` | After `/init` scores the task | `tier: medium+` |
| `spec:` | After brainstorming writes the spec | `spec: docs/superpowers/specs/2026-04-06-workflow-v2-design.md` |
| `plan:` | After writing-plans saves the plan | `plan: docs/superpowers/plans/2026-04-06-workflow-v2.md` |
| `planned-tasks:` | After sub-tasks are created from plan | `planned-tasks: 8` |
| `spike:` | After spike completes | `spike: lightweight` |
| `spike-confirmed:` | Spike findings | `spike-confirmed: existing rules load correctly` |
| `spike-revised:` | Spike found wrong assumption | `spike-revised: resume parses free-text -> needs key-value` |
| `spike-risks:` | Spike identified risks | `spike-risks: unified-workflow.md getting long` |
| `completed:` | After each sub-task closes | `completed: 1,2,3` |
| `current:` | When claiming a sub-task | `current: 4` |
| `micro-tier:` | When claiming a sub-task | `micro-tier: micro-small` |
| `spec-amendment:` | When spec is updated | `spec-amendment: minor -- renamed userId to user_id` |
| `scope-check:` | After scope health triggers | `scope-check: warning -- 8/5 tasks (1.6x)` |
| `verification:` | After verification runs | `verification: tests 47/47, build clean, lint clean` |
| `stopped:` | At session end | `stopped: Task 5 of 8, resuming with Task 6` |

### Rules

- One key-value per `bd update --notes` call (beads appends, doesn't replace)
- Keys are lowercase, colon-separated, no quotes needed
- `/resume` matches by prefix — existing pattern detection still works but now has consistent format
- Backward compatible: old free-text notes like `"Spec: path"` still match the `spec:` prefix

### File

Extension to `rules/common/beads-milestones.md` — replace the current Examples section with the standardized format table.

---

## 6. Dependency-Aware Parallelism

### Summary

Instead of a separate layer system, enhance workflow documentation to make the `writing-plans` skill think about parallelism when creating sub-tasks. Use existing `bd dep` + `bd ready` as the execution engine.

### Guidance for Plan Creation

Add to the Medium+ path in `commands/workflow.md`:

```
When creating sub-tasks from the plan:
- Default to independent (no deps between sub-tasks) unless one task genuinely
  needs another's output
- Only add bd dep when Task B literally cannot start without Task A's artifacts
  (schema it reads, interface it imports, config it loads)
- "Conceptually related" is NOT a dependency. Two endpoints that share a database
  table can be built in parallel — the table creation is the dependency, not the
  endpoints on each other.
```

### Execution Change

Update the IMPLEMENT step in `rules/common/unified-workflow.md`:

```
6. IMPLEMENT  bd ready -> claim ALL ready tasks (not just one)
              For independent ready tasks, dispatch parallel agents
              (superpowers:dispatching-parallel-agents)
              For sequential tasks, work one at a time
```

### No New Tooling

Uses existing `bd dep`, `bd ready`, and `superpowers:dispatching-parallel-agents`. No new files — two small additions to existing workflow docs.

### Files

Extensions to `commands/workflow.md` and `rules/common/unified-workflow.md`.

---

## Implementation Batches

### Batch A (independent, can be parallel)

| # | Improvement | File action |
|---|---|---|
| 1 | Spike phase | Create `rules/common/spike-phase.md` |
| 2 | Spec amendment protocol | Extend `rules/common/unified-workflow.md` |
| 3 | Structured checkpoints | Extend `rules/common/beads-milestones.md` |

### Batch B (depends on Batch A decisions)

| # | Improvement | File action |
|---|---|---|
| 4 | Sub-task re-scoring | Extend `rules/common/unified-workflow.md` |
| 5 | Scope health check | Create `rules/common/scope-health.md` |
| 6 | Dependency-aware parallelism | Extend `commands/workflow.md` + `rules/common/unified-workflow.md` |

### Cross-cutting

- Update `commands/workflow.md` Medium+ path to reference spike phase, micro-tiers, scope health, and parallel execution
- Update `skills/setup/SKILL.md` to copy new rule files (`spike-phase.md`, `scope-health.md`)

---

## What This Does NOT Change

- No changes to Superpowers plugin skills (brainstorming, writing-plans, TDD, etc.) — these are upstream
- No changes to `/init` or `/resume` skill logic — checkpoint format is backward compatible
- No new beads features required — uses existing `bd dep`, `bd ready`, `bd update --notes`
- No application code — this is all workflow documentation and rules
