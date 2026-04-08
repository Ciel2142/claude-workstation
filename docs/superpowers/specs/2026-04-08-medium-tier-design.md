# Medium Tier Design

Adds a "Medium" tier between Small and Medium+ for tasks that touch multiple files
or domains but don't need epic-level ceremony (brainstorming, spike evaluation).

## Tier Table

| Tier | Signal | Type | Priority | Flow |
|---|---|---|---|---|
| **Trivial** | ≤1 file, no behavior change | task | P3 | fix → verify → close |
| **Small** | 1-3 files, single concern | task | P2 | TDD → review → verify → close |
| **Medium** | 4-7 files OR 2 domains, no architecture/system signals | epic | P2 | plan → sub-tasks → TDD (subagent-driven) → review → verify → close |
| **Medium+** | New system/component, OR cross-cutting, OR 8+ files | epic | P1 | brainstorm → plan → sub-tasks → spike → TDD → verify → close |
| **Bug** | Any tier, type=bug | bug | varies | debug → TDD (regression) → review → verify → close |

## Gate Logic

Walk five gates in order. First gate that fires determines the tier.

**Domains** (for counting): API, database, auth, frontend, backend, CI/CD,
infrastructure, testing, security, config.

| Gate | Condition | Result |
|---|---|---|
| **1 — ESCALATION** | "new system", "new component", architecture intent (design, architect, migrate) | Medium+ |
| | security/migration mention (not primary intent) | floor = Medium |
| **2 — SCOPE** | breadth words (all, every, across, entire, global), 3+ domains, rewrite/overhaul | Medium+ |
| **3 — MULTI** | 2+ domains OR estimated 4+ files | Medium |
| **4 — FEATURE** | feature intent (add, create, implement, new), single domain | Small |
| **5 — DEFAULT** | everything else | Trivial (or floor from Gate 1) |

Claude override: upward only (never downward without human approval).
Log: `tier-override: <computed> → <new> — <reason>`

## Medium Flow

```
1. EPIC       bd create --title="..." --type=epic -p 2
2. PLAN       /superpowers:writing-plans
               Output: plan in docs/superpowers/plans/
               Log: "plan: <path>"
3. SUB-TASKS  For each plan step:
               bd create --title="Step N: ..." --type=task
               bd dep add <sub-id> <epic-id>
               bd dep add <sub-id> <prev-sub-id>  (only if genuinely sequential)
               Log: "planned-tasks: N"
4. IMPLEMENT  /superpowers:subagent-driven-development
               For each sub-task:
               ├─ Assess micro-tier
               ├─ TDD per micro-tier
               ├─ Commit after each green
               ├─ Code review per micro-tier
               └─ bd close <sub-id>
               Scope health check every 3 closed sub-tasks.
5. VERIFY     /superpowers:verification-before-completion
6. CLOSE      bd close <epic-id>
```

**What Medium skips vs Medium+:** No brainstorming (requirements are clear).
No spike evaluation (no risky integrations expected).

## Start Routing

| Tier | Routes to |
|---|---|
| Trivial | No skill — "Go fix it. Then verify and `bd close <id>`." |
| Small | `/superpowers:test-driven-development` |
| Medium | `/superpowers:writing-plans` |
| Medium+ | `/superpowers:brainstorming` |

## Resume Position Detection

New position: **post-decomposition** — detected by `planned-tasks:` milestone.

| Priority | Pattern in notes | Position |
|---|---|---|
| 1 (highest) | `docs-updated:` | post-update-docs |
| 2 | `verification:` | post-verification |
| 3 | `completed:` | mid-implementation |
| 4 | `planned-tasks:` | post-decomposition |
| 5 | `plan:` | post-planning |
| 6 | `spec:` | post-brainstorming |
| 7 | `debug:` | mid-debugging |
| 8 (lowest) | `tier:` only | start |

## Resume Routing

| Position | Medium | Medium+ |
|---|---|---|
| start | `/superpowers:writing-plans` | `/superpowers:brainstorming` |
| post-brainstorming | `/superpowers:writing-plans` | `/superpowers:writing-plans` |
| post-planning | Create sub-tasks from plan | Create sub-tasks from plan |
| post-decomposition | `/superpowers:subagent-driven-development` | `/superpowers:test-driven-development` (next ready) |
| mid-implementation | `/superpowers:subagent-driven-development` | `/superpowers:test-driven-development` (next ready) |
| post-verification | `/ecc:update-docs` | `/ecc:update-docs` |
| post-update-docs | `/superpowers:finishing-a-development-branch` | `/superpowers:finishing-a-development-branch` |

## Resume Tier Inference

When `tier:` is not in beads notes:

1. Task is under an epic → medium+ (can't distinguish without tag)
2. Task type is epic → medium+
3. Has `plan:` but no `spec:` → medium (plan without spec = no brainstorming)
4. Has `spec:` → small
5. Otherwise → default to small

## Resume Context Loading

Medium gets **deep** loading (same as Medium+): bd show + git commits + changed
files + spec/plan contents + sub-task statuses + worktree + session files.

## Escalation Paths

| From → To | Trigger | Action |
|---|---|---|
| Trivial → Small | Behavior change discovered | Add TDD and review |
| Small → Medium | Scope grows to 4+ files or 2+ domains | Stop. Create epic, plan, decompose. Continue from IMPLEMENT. |
| Medium → Medium+ | Architecture/system signals emerge | Stop. Add brainstorming + spike. Continue from BRAINSTORM. |

## Scope Health & Micro-tiers

Both apply to Medium identically to Medium+ (both have sub-tasks).

## Hard Rules

"No production code without a failing test" applies to Small, Medium, and Medium+.

## Files to Change

| # | File | Changes |
|---|---|---|
| 1 | `contexts/workflow.md` | Tier table, hard rules, escalation |
| 2 | `skills/start/SKILL.md` | Gate logic, task creation, routing |
| 3 | `skills/resume/SKILL.md` | Tier inference, position detection, context loading, routing |
| 4 | `commands/help.md` | New "Medium Path" section, escalation paths, post-decomposition |
| 5 | `README.md` | Tier table |
| 6 | `tests/validate-config.sh` | Tier signal consistency checks |
| 7 | `tests/test-behaviors.sh` | Position detection for post-decomposition + medium inference |
| 8 | `tests/scenarios/medium.sh` | NEW: medium tier scenario |
| 9 | `skills/test/SKILL.md` | Reference to medium.sh scenario |
