---
name: review-level-gate
version: 1.1.0
description: >
  Auto-escalate review intensity based on objective complexity signals.
  Two levels: Standard (single reviewer) and Consensus (santa-method dual
  independent review). Runs at claim-time alongside micro-tier assessment.
  TRIGGER: When claiming any sub-task within a Medium+ epic.
---

# Review Level Gate

Determine review intensity at claim-time based on objective signals. Sets the review level as a task property alongside micro-tier.

## Two Levels

| Level | Reviewers | Protocol | When |
|---|---|---|---|
| **Standard** | 1 code quality reviewer | Current `requesting-code-review` flow | No escalation signals fire |
| **Consensus** | 2 independent reviewers + convergence | `santa-method` (both must PASS, max 3 rounds) | Any signal fires |

No middle ground. Either one reviewer suffices, or you need adversarial dual review with convergence.

## When to Run

At claim-time, immediately after micro-tier assessment:

```
bd update <task-id> --claim
→ Assess micro-tier → Run review level gate
→ Log: "micro-tier: <tier>, review-level: <standard|consensus>"
```

## Objective Signals

Evaluated against **sub-task description and plan text**, NOT against code (which doesn't exist at claim-time). Each is binary.

| Signal | Fires When | Examples |
|---|---|---|
| **Security-sensitive** | Auth, crypto, input validation, deserialization, eval-adjacent, secrets, permissions | "Add JWT validation", "Sanitize user input" |
| **API surface change** | Public API, CLI interface, exported signature, protocol contract created/modified | "Add /users endpoint", "New exported type" |
| **Cross-domain** | 2+ distinct domains touched (frontend+backend, API+database, auth+billing) | "Update form validation and API endpoint" |
| **Supply-chain** | External dependencies added/removed/updated, lock files modified | "Add zod dependency", "Upgrade React to v19" |
| **Infrastructure** | Docker, CI/CD, env vars, deployment configs, database migrations, IaC | "Update Dockerfile", "Add GitHub Action" |

### Evaluation Rules

1. **One signal is enough.** Any single signal → Consensus.
2. **Evaluate against task text.** Not code — the code doesn't exist yet.
3. **When in doubt, escalate.** False positive costs one extra reviewer. False negative costs a shipped vulnerability.
4. **No agent self-assessment input.** The implementing agent's opinion of difficulty is NOT a signal. Only objective task properties matter.

## ESCALATE Protocol

A Standard reviewer can return `ESCALATE(reason)` to promote to Consensus mid-review.

**On ESCALATE:** Discard the Standard reviewer's partial assessment (context isolation). Dispatch two fresh independent reviewers per `santa-method`. Follow convergence loop (both must PASS, max 3 rounds — escalate to human if exhausted).

**Constraints:**
- Max 1 escalation per task. Consensus cannot escalate further.
- Escalation is up only. No reviewer or signal can demote Consensus to Standard. Never.
- Consensus tasks always get individual review and reset the batch counter.

## Budget Awareness

If review cost becomes a concern, reduce Consensus frequency by narrowing signal definitions — never skip review entirely. Budget pressure falls back to Standard, never eliminates review.

## Red Flags

These thoughts mean the gate is being bypassed — STOP:

| Thought | Reality |
|---|---|
| "This security change is trivial" | Security = Consensus. No exceptions. |
| "It's just a small API tweak" | API surface change = Consensus. Size is irrelevant. |
| "The budget is running low, skip Consensus" | Budget pressure reduces to Standard, never skips review. |
| "The implementer said it's fine" | Implementer opinion is not a signal. |
| "Two reviewers for this is overkill" | Consensus is triggered by objective signals, not feelings. |
| "I already reviewed it mentally" | Mental review is not a gate pass. Dispatch the agents. |
