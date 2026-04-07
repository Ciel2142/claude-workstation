# Workflow Context

All work follows a size-based flow: Beads (tracking) + Superpowers (process) + ECC (expertise).

## Beads-First Rule

Before ANY change -- editing, deleting, destructive commands, or Superpowers skills -- `bd create` first. No exceptions.

## Task Sizing

| Tier | Signal | Flow |
|---|---|---|
| **Trivial** | <=1 file, no behavior change | `bd create` -> fix -> verify -> `bd close` |
| **Small** | 1-3 files, single concern | `bd create` -> TDD -> review -> verify -> `bd close` |
| **Medium+** | 4+ files, new system/component, or cross-cutting | `bd create -t epic` -> brainstorm -> plan -> sub-tasks -> spike -> TDD -> verify -> `bd close` |
| **Bug** | Any tier, type=bug | `bd create -t bug` -> debug -> TDD (regression) -> review -> verify -> `bd close` |

Escalation only upward -- never downgrade.

## Hard Rules

- No Superpowers invocation without an active beads task
- No production code without a failing test (Small/Medium+)
- No completion claims without verification output
- No trusting subagent reports without own verification

## Pre-Change Gate

Before ANY file change, verify: (1) **Task Boundary** -- shift from discussion to action? `bd create` + tier first. (2) **Task exists?** -- no task = no change. (3) **Scope confirmed this turn?** -- restate files/changes, get "yes." Prior intent does NOT count. Any unchecked -> stop: "This is a new task -- let me create a beads task and assess the tier."

## Scope Confirmation

Restate what you will change and confirm. Applies: conversational flow (not `/start`), delete/rename/restructure, ambiguous scope. Does NOT apply: files listed in plan/sub-task, or via `/start`. Format: "I'll [verb] [specific paths]. Confirm?" -- wait. When conversation shifts to implementation ("let's do it", "go ahead") -> new task: `bd create` -> tier -> flow. "Just"/"quickly"/"simply" do NOT reduce scope. Momentum is not a reason to skip.

## Spec Amendments

Spec wrong? Amend, don't silently deviate. **Minor (self-approve):** no change to deliverables/API/acceptance criteria. Update, commit, log `spec-amendment: minor -- <what>`. **Material (human):** algorithm, features, deps, API shape, architecture. Stop, present, wait. Log `spec-amendment: material -- <what>, approved`. Applies Small/Medium+ only.

## Sub-task Micro-tiers and Review Level

Each Medium+ sub-task gets micro-tier AND review level at claim-time.

| Micro-tier | Signal | Ceremony |
|---|---|---|
| **Micro-trivial** | Config, wiring, exports, types. No branches/loops/try-catch. | Micro-TDD (1 assertion). Batch review every 3. |
| **Micro-small** | Single-concern logic, one function. Not: algorithm/security/API/cross-cutting. | Full TDD. Batch review every 3. |
| **Micro-complex** | Algorithm, security, public API, cross-cutting. | Full TDD + individual review. |

**Review signals** (against sub-task description, not code): security-sensitive (auth, crypto, validation, secrets), API surface change (public API, CLI, exports), cross-domain (2+ domains), supply-chain (deps added/removed/updated), infrastructure (Docker, CI/CD, env vars, migrations). Any signal -> Consensus (dual independent, santa-method). None -> Standard (single reviewer). No agent self-assessment. Standard can ESCALATE(reason) to Consensus (max 1, up only). Consensus resets batch counter. Log: `micro-tier: <tier>, review-level: <standard|consensus>`

## Spike Phase

After planning, before first implementation: validate file paths and interfaces match plan. If any task mentions API/integration/library/SDK/migrate/external, build minimal proof-of-concept for riskiest integration (discard after documenting). Log `spike:`, `spike-confirmed:`, `spike-revised:`, `spike-risks:`. Revised assumptions changing APIs/libraries/deliverables -> spec amendment.

## Debugging

Invoke `superpowers:systematic-debugging` before any fix. 3 failed hypotheses -> STOP, present to user. Regression test before fix.

## Scope Health (Medium+)

Every 3rd closed sub-task, check ratio = total created / planned-tasks. >=1.5x -> warning. >=2.0x -> gate (stop; re-plan, split, or continue; human decides).

## Verification Format

After `superpowers:verification-before-completion`, log to beads notes:
```
- Tests: <s> N passed, N failed (exit <code>)  - Build: <s> (exit <code>)
- Lint:  <s> (exit <code>)  - Type: <s> (exit <code>)  - Manual: <s> <desc>
```
`s`: `✓` passed, `✗` failed (blocking), `⊘` skipped (reason). Exit code required. At least one must pass.

## Milestone Notes

Update beads notes via `bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "key: value"`.

| Key | When | Key | When |
|---|---|---|---|
| `tier:` | After `/start` | `completed:` | Sub-task closes |
| `spec:` | After brainstorming | `current:` | Claiming sub-task |
| `plan:` | After writing plan | `micro-tier:` | Claiming sub-task |
| `planned-tasks:` | Sub-tasks created | `spec-amendment:` | Spec updated |
| `spike:` | After spike | `scope-check:` | After scope health |
| `spike-confirmed:` | Spike findings | `debug:` | Root cause found |
| `spike-revised:` | Wrong assumption | `verification:` | After verification |
| `spike-risks:` | Risks identified | `docs-updated:` | Docs updated |
| `stopped:` | Session end / pre-compact | | |

## Plugin Routing

**Beads** -> task tracking (`bd`), no TodoWrite. **Superpowers** -> process (brainstorming, planning, TDD, review, verification, debugging, agents, finishing). **ECC** -> language/domain skills within Superpowers process. Before new implementation: GitHub search first, library docs second (Context7), check registries. Proven > net-new.

## Verification Failure Protocol

| Type | Signal | Action |
|---|---|---|
| **A -- Impl bug** | File in confirmed scope | Fix in current task |
| **B -- Collateral** | File NOT in scope, even if your change caused it | Side-quest: bug, link, fix under own task |
| **C -- Unrelated** | Test unrelated to your changes | Side-quest: bug, park, do NOT fix |

"Is the file I need to edit in my confirmed scope?" No -> side-quest. "My change caused it" is rationalization, not justification.

## Side Quests

Problem outside scope: `bd create --title="Found: <issue>" --type=bug` + `bd dep add <new-id> <current-id> --type=discovered-from`. Finish current task first, then `bd ready`. Fix size does not reduce ceremony.

Inlined from former skills: beads-milestones, review-level-gate, scope-health, spike-phase, debugging-protocol, verification-template. Run `/help` for full tier flows.
