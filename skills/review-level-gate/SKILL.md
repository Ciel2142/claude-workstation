---
name: review-level-gate
version: 1.0.0
description: >
  Auto-escalate review intensity based on objective complexity signals.
  Two levels: Standard (single reviewer) and Consensus (santa-method dual
  independent review). Runs at claim-time alongside micro-tier assessment.
  TRIGGER: When claiming any sub-task within a Medium+ epic.
---

# Review Level Gate

Determine the review intensity for a sub-task based on objective complexity signals. This gate runs at claim-time, alongside micro-tier assessment, and sets the review level as a task property.

## Two Levels

| Level | Reviewers | Protocol | When |
|---|---|---|---|
| **Standard** | 1 code quality reviewer | Current `requesting-code-review` flow | Default — no escalation signals fire |
| **Consensus** | 2 independent reviewers + convergence | `santa-method` (both must PASS, max 3 rounds) | Any escalation signal fires |

There is no middle ground. Either one reviewer is enough, or you need adversarial dual review with convergence. Two reviewers without a consensus mechanism is worse than both extremes.

## When to Run

Run this gate when claiming any sub-task within a Medium+ epic, immediately after micro-tier assessment:

```
bd update <task-id> --claim
→ Assess micro-tier (micro-trivial / micro-small / micro-complex)
→ Run review level gate (Standard / Consensus)
→ Log both: "micro-tier: <tier>, review-level: <standard|consensus>"
```

## Signal Detection

Signals are evaluated against the **sub-task description and plan text**, NOT against the implementation (which doesn't exist yet at claim-time). Each signal is binary: fires or doesn't.

### Objective Signals

| Signal | Fires When | Examples |
|---|---|---|
| **Security-sensitive** | Task involves authentication, authorization, cryptography, input validation, deserialization, eval-adjacent patterns, secrets handling, or permission checks | "Add JWT validation", "Sanitize user input", "Encrypt at rest" |
| **API surface change** | Task creates or modifies a public API, CLI interface, exported function signature, or protocol contract | "Add /users endpoint", "Change CLI --format flag", "New exported type" |
| **Cross-domain** | Task touches 2+ distinct domains (frontend + backend, API + database, auth + billing, etc.) | "Update form validation and API endpoint", "Add DB migration and UI" |
| **Supply-chain** | Task adds, removes, or updates external dependencies, or modifies lock files | "Upgrade React to v19", "Add zod dependency", "Replace lodash with native" |
| **Infrastructure** | Task modifies Docker, CI/CD, environment variables, deployment configs, database migrations, or IaC | "Update Dockerfile", "Add GitHub Action", "New DB migration" |

### Signal Evaluation Rules

1. **One signal is enough.** Any single signal firing promotes to Consensus.
2. **Evaluate against task text.** Read the sub-task description and the corresponding plan section. Do NOT run code analysis — the code doesn't exist yet.
3. **When in doubt, escalate.** If a signal might fire but you're not sure, treat it as fired. False positive (unnecessary Consensus review) costs one extra reviewer invocation. False negative (missed Standard review) costs a shipped vulnerability.
4. **No agent self-assessment input.** The implementing agent's opinion of task difficulty is NOT a signal. Agents are uncalibrated self-assessors. Only objective task properties matter.

## Reviewer Escalation Protocol

A Standard reviewer who encounters unexpected complexity can promote the task to Consensus mid-review. This is the safety valve for signals that fire at implementation time but weren't visible at claim-time.

### How It Works

The code quality reviewer (dispatched for Standard review) may return one of:

| Response | Meaning | Action |
|---|---|---|
| **PASS** / **FAIL** (normal) | Standard review complete | Proceed normally (fix if FAIL, continue if PASS) |
| **ESCALATE(reason)** | Reviewer found complexity the signals missed | Promote to Consensus review |

### On ESCALATE

1. Log: `review-escalated: standard→consensus, reason: <reason>`
2. Discard the Standard reviewer's partial assessment (do not carry it forward — context isolation)
3. Dispatch two fresh independent reviewers per `santa-method` protocol
4. Follow Consensus convergence loop (both must PASS, max 3 rounds)

### Constraints

- **Max 1 escalation per task.** A Standard task can escalate to Consensus. A Consensus task cannot escalate further. If Consensus reviewers exhaust 3 rounds without convergence, escalate to human — not to a higher level.
- **Escalation is up only.** No reviewer, agent, or signal can demote Consensus to Standard. Ever.
- **Consensus tasks skip batch review.** They always get individual review, like micro-complex tasks. They reset the batch counter.

## Budget Cap

To prevent runaway cost, each epic has a maximum reviewer invocation budget.

### Defaults

| Setting | Default | Meaning |
|---|---|---|
| `review-budget-multiplier` | 2.5 | Max total reviewer invocations = planned_tasks * multiplier |
| `review-budget-floor` | 10 | Minimum budget regardless of epic size |

For a 10-task epic: budget = max(10, 10 * 2.5) = 25 reviewer invocations.

### Tracking

After each reviewer invocation, log to the epic's notes:
```
review-invocations: <current>/<budget>
```

### At Budget

When the budget is reached:
1. **Warning** at 80% — log: `review-budget-warning: 80% consumed (N/M)`
2. **Gate** at 100% — stop dispatching Consensus reviews. Fall back to Standard for remaining tasks. Log: `review-budget-exhausted: falling back to Standard`
3. **Never skip review entirely.** Budget exhaustion reduces intensity, never eliminates it.

## Integration with Existing Workflow

### Micro-tier Interaction

| Micro-tier | Default Review Level | Can Escalate? |
|---|---|---|
| **Micro-trivial** | Standard (batch every 3) | Yes → Consensus (exits batch, individual review) |
| **Micro-small** | Standard (batch every 3) | Yes → Consensus (exits batch, individual review) |
| **Micro-complex** | Standard (individual) | Yes → Consensus |

Note: Micro-complex tasks already get individual review. The gate adds the possibility of Consensus (dual independent) review when signals fire. Most micro-complex tasks will trigger at least one signal (security-sensitive, public API), so Consensus will be common for micro-complex.

### Subagent-Driven Development Integration

The gate inserts into the existing flow:

```
Current:  claim → micro-tier → implement → spec review → code quality review → done
Proposed: claim → micro-tier → REVIEW LEVEL GATE → implement → spec review → code quality review(s) → done
                                    ↓
                              Standard: 1 reviewer (current flow)
                              Consensus: 2 reviewers, santa-method convergence
```

The gate runs BEFORE implementation. The review level is set as a task property and does not change during implementation (unless a reviewer escalates).

### Batch Review Interaction

- Standard tasks follow existing batch cadence (review every 3rd task)
- Consensus tasks always get individual review and reset the batch counter
- Escalated tasks (Standard→Consensus mid-review) count as Consensus for batch purposes

## Output Format

When the gate runs, log to the sub-task notes:

```
review-level: standard
signals: none
```

or:

```
review-level: consensus
signals: security-sensitive, cross-domain
```

And announce:
```
🔍 Review Level: Standard (no escalation signals)
```
or:
```
🔍 Review Level: Consensus (signals: security-sensitive, cross-domain)
   → Dual independent review with convergence after implementation
```

## Red Flags

These thoughts mean the gate is being bypassed — STOP:

| Thought | Reality |
|---|---|
| "This security change is trivial" | Security = Consensus. No exceptions. |
| "It's just a small API tweak" | API surface change = Consensus. Size is irrelevant. |
| "The budget is running low, skip Consensus" | Budget exhaustion reduces to Standard, never skips review. |
| "The implementer said it's fine" | Implementer opinion is not a signal. |
| "Two reviewers for this is overkill" | Consensus is triggered by objective signals, not feelings. |
| "I already reviewed it mentally" | Mental review is not a gate pass. Dispatch the agents. |
