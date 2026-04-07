# Workflow Context

All work follows a size-based flow: Beads (tracking) + Superpowers (process) + ECC (expertise).

## Beads-First Rule

Before making ANY change to the codebase — editing files, deleting files, running destructive commands, or invoking Superpowers skills — create a beads task first. Sequence: `bd create` → then work. No work without a beads task. No exceptions.

## Task Sizing

| Tier | Signal | Flow |
|---|---|---|
| **Trivial** | ≤1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files, OR new system/component, OR cross-cutting | `bd create -t epic` → brainstorm → plan → sub-tasks → spike eval → TDD → verify → `bd close` (+ worktree, update-docs, finish when applicable) |
| **Bug** | Any tier, type=bug | `bd create -t bug` → debug → TDD (regression test) → review → verify → `bd close` |

Escalation only upward — never downgrade.

## Hard Rules

- No Superpowers skill invocation without an active beads task
- No production code without a failing test (Small/Medium+)
- No completion claims without verification output
- No trusting subagent reports without own verification

## Pre-Change Gate

Before ANY file change (edit, delete, write, shell command), verify in order:
1. **Task Boundary** — Is this a shift from discussion to action? If yes → `bd create` + tier assessment first.
2. **Beads task exists?** — No task = no change. No exceptions.
3. **Scope confirmed this turn?** — Restate specific files/changes, get explicit "yes." Prior intent ("yeah", "go ahead", "just do it") does NOT count as confirmation.

If any box is unchecked, stop. Tell the user: "This is a new task — let me create a beads task and assess the tier before proceeding."

## Scope Confirmation

Before implementing changes, restate what you will change and confirm with the user. This applies when:
- The user requests a change in conversational flow (not via `/start`)
- The change involves deleting, renaming, or restructuring files
- The request could refer to more than one file, directory, or component — if so, it is ambiguous by definition

Does NOT apply when the specific files being changed are listed in the plan document or in the sub-task's beads description.

Does NOT apply when invoked via `/claude-workstation:start` — the start skill handles its own scope assessment.

Format: "I'll [verb] [specific file paths or named artifacts]. Confirm?" — then wait. Do not use category names ("the profiles") — list actual files.

## Task Boundary

When conversation shifts from research/discussion to implementation ("let's do it", "go ahead", "remove that", or similar intent to begin changes), treat it as a new task. Stop and run the workflow entry point:
1. Create a beads task (`bd create`)
2. Assess the tier
3. Follow the tier's flow

Words like "just", "quickly", "simply" do NOT reduce scope or create exceptions. When you feel the urge to act immediately, that urge is the signal to stop and follow the gate.

Conversational momentum is not a reason to skip the workflow.

## Spec Amendments

When implementation reveals the spec is wrong, amend it — don't silently deviate.

**Minor (agent self-approves):** Changes that do NOT alter the set of deliverables, API surface, or acceptance criteria. Examples: naming mismatches, missing edge case detail, clarifying ambiguous wording, parameter type corrections to match existing code. If any deliverable, endpoint, field, or acceptance criterion is added, removed, or functionally changed, it is Material.
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
- **Spike eval** (Medium+, mandatory) → `/claude-workstation:spike-phase` (evaluate triggers → execute if any fire)
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

## Verification Failure Protocol

When tests or checks fail during VERIFY, classify before acting:

| Type | Signal | Action |
|---|---|---|
| **A — Implementation bug** | The file to fix is one already in your confirmed scope | Fix within current task |
| **B — Collateral breakage** | The file to fix is NOT in your confirmed scope, even if your change caused the failure | Side-quest: create bug, link, fix under its own task |
| **C — Unrelated failure** | A test unrelated to your changes failed | Side-quest: create bug, park it, do NOT fix now |

The test: **"Is the file I need to edit in my confirmed scope?"** If no → it is a side-quest regardless of whether your change caused the breakage.

"My change caused it" is the most common rationalization for skipping the gate. Treat it as a red flag, not a justification.

## Side Quests

Discover a problem in a file outside your confirmed scope mid-work — regardless of whether your changes caused it:
```bash
bd create --title="Found: <issue>" --type=bug
bd dep add <new-id> <current-id> --type=discovered-from
```
Finish current task first, then `bd ready`.

### Collateral Breakage Rule

When your changes cause failures in files OUTSIDE your confirmed scope (tests that hardcoded assumptions, downstream consumers, config files you didn't plan to touch): this is a side-quest, not part of the current task. The fact that your change caused the breakage does NOT make the fix in-scope.

The fix may be trivial (2 lines), but the tracking is mandatory. Create a discovered-from bug, fix it under its own task, close it. Size of the fix does not reduce ceremony.

Run `/help` for detailed step-by-step flows with full ceremony for each tier.
