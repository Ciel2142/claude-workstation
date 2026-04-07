# Review Level Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 2-level review gate (Standard/Consensus) that auto-escalates review intensity based on objective complexity signals, with reviewer-initiated escalation as a safety valve.

**Architecture:** A new skill (`review-level-gate`) provides the gate logic. It runs at claim-time alongside micro-tier assessment. Objective signals (security, API surface, cross-domain, supply-chain, infra) determine whether a sub-task gets Standard review (single reviewer) or Consensus review (santa-method dual independent reviewers with convergence). Any Standard reviewer can escalate to Consensus (max 1 per task). A configurable per-epic budget caps total reviewer invocations.

**Tech Stack:** Bash (skill files, tests), Markdown (SKILL.md, workflow context), existing claude-workstation test harness.

---

### Task 1: Create the review-level-gate skill with signal detection logic

This is the core skill. It defines the two review levels, the objective signals that trigger escalation, and the reviewer escalation protocol.

**Files:**
- Create: `skills/review-level-gate/SKILL.md`

- [ ] **Step 1: Write the failing test — skill file exists and has required sections**

Add to `tests/test-behaviors.sh` at the end (before the summary section):

```bash
# ---------------------------------------------------------------------------
# Section N: review-level-gate skill structure
# ---------------------------------------------------------------------------
echo ""
echo "N. review-level-gate skill"

SKILL_FILE="$PLUGIN_ROOT/skills/review-level-gate/SKILL.md"

# Na. Skill file exists
if [[ -f "$SKILL_FILE" ]]; then
    pass "Na. review-level-gate SKILL.md exists"
else
    fail "Na. review-level-gate SKILL.md does not exist"
fi

# Nb. Has frontmatter with name
if grep -q '^name: review-level-gate' "$SKILL_FILE" 2>/dev/null; then
    pass "Nb. frontmatter has name: review-level-gate"
else
    fail "Nb. frontmatter missing name: review-level-gate"
fi

# Nc. Defines both review levels
if grep -q 'Standard' "$SKILL_FILE" 2>/dev/null && grep -q 'Consensus' "$SKILL_FILE" 2>/dev/null; then
    pass "Nc. defines both Standard and Consensus levels"
else
    fail "Nc. missing Standard and/or Consensus level definitions"
fi

# Nd. Lists objective signals
SIGNAL_COUNT=0
for signal in "security" "API surface" "cross-domain" "supply-chain" "infrastructure"; do
    if grep -qi "$signal" "$SKILL_FILE" 2>/dev/null; then
        SIGNAL_COUNT=$((SIGNAL_COUNT + 1))
    fi
done
if [[ $SIGNAL_COUNT -ge 5 ]]; then
    pass "Nd. all 5 objective signal categories present"
else
    fail "Nd. only $SIGNAL_COUNT/5 objective signal categories found"
fi

# Ne. Defines ESCALATE protocol
if grep -q 'ESCALATE' "$SKILL_FILE" 2>/dev/null; then
    pass "Ne. ESCALATE protocol defined"
else
    fail "Ne. ESCALATE protocol not defined"
fi

# Nf. Defines budget cap
if grep -qi 'budget' "$SKILL_FILE" 2>/dev/null; then
    pass "Nf. budget cap defined"
else
    fail "Nf. budget cap not defined"
fi

# Ng. Does NOT include self-confidence signal
if grep -qi 'self-confidence\|confidence score\|self-report.*confidence' "$SKILL_FILE" 2>/dev/null; then
    fail "Ng. contains self-confidence signal (removed per security review)"
else
    pass "Ng. no self-confidence signal (correct per security review)"
fi

# Nh. Defines claim-time assessment
if grep -qi 'claim.time\|claim time\|at claim' "$SKILL_FILE" 2>/dev/null; then
    pass "Nh. claim-time assessment documented"
else
    fail "Nh. claim-time assessment not documented"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-behaviors.sh 2>&1 | tail -20`
Expected: FAIL on Na through Nh (skill file does not exist yet)

- [ ] **Step 3: Write the review-level-gate skill**

Create `skills/review-level-gate/SKILL.md`:

```markdown
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
4. **No self-confidence input.** The implementing agent's opinion of task difficulty is NOT a signal. Agents are uncalibrated self-assessors. Only objective task properties matter.

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-behaviors.sh 2>&1 | tail -20`
Expected: PASS on Na through Nh

- [ ] **Step 5: Commit**

```bash
git add skills/review-level-gate/SKILL.md tests/test-behaviors.sh
git commit -m "feat: add review-level-gate skill with 2-level escalation"
```

---

### Task 2: Update workflow.md to integrate the review level gate

Wire the new gate into the existing workflow context so agents know when and how to use it.

**Files:**
- Modify: `contexts/workflow.md:74-88` (Sub-task Micro-tiers section)
- Modify: `contexts/workflow.md:90-98` (Skill References section)

- [ ] **Step 1: Write the failing test — workflow references review-level-gate**

Add to `tests/test-behaviors.sh` (after the review-level-gate section):

```bash
# ---------------------------------------------------------------------------
# Section N+1: workflow.md review-level-gate integration
# ---------------------------------------------------------------------------
echo ""
echo "N+1. workflow.md review-level-gate integration"

WORKFLOW_FILE="$PLUGIN_ROOT/contexts/workflow.md"

# (N+1)a. Workflow references review-level-gate skill
if grep -q 'review-level-gate' "$WORKFLOW_FILE" 2>/dev/null; then
    pass "(N+1)a. workflow.md references review-level-gate"
else
    fail "(N+1)a. workflow.md does not reference review-level-gate"
fi

# (N+1)b. Workflow mentions claim-time gate
if grep -qi 'review.level.*gate\|review.*level.*claim' "$WORKFLOW_FILE" 2>/dev/null; then
    pass "(N+1)b. workflow.md mentions review level at claim-time"
else
    fail "(N+1)b. workflow.md does not mention review level at claim-time"
fi

# (N+1)c. Workflow mentions Standard and Consensus
if grep -q 'Standard' "$WORKFLOW_FILE" 2>/dev/null && grep -q 'Consensus' "$WORKFLOW_FILE" 2>/dev/null; then
    pass "(N+1)c. workflow.md defines Standard and Consensus levels"
else
    fail "(N+1)c. workflow.md missing Standard and/or Consensus"
fi

# (N+1)d. Skill references section includes review-level-gate
if grep -q 'review-level-gate' "$WORKFLOW_FILE" 2>/dev/null; then
    pass "(N+1)d. skill references include review-level-gate"
else
    fail "(N+1)d. skill references missing review-level-gate"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-behaviors.sh 2>&1 | grep 'N+1'`
Expected: FAIL on all (N+1) tests

- [ ] **Step 3: Update workflow.md — Sub-task Micro-tiers section**

In `contexts/workflow.md`, after the micro-tier table (line ~84), add the review level gate instruction:

Replace the line:
```
When claiming a sub-task, assess its micro-tier. If the sub-task creates or modifies any function/method body with conditional logic, loops, or error handling, it is NOT micro-trivial. Log: `micro-tier: <micro-trivial|micro-small|micro-complex>`
```

With:
```
When claiming a sub-task, assess its micro-tier AND review level. If the sub-task creates or modifies any function/method body with conditional logic, loops, or error handling, it is NOT micro-trivial. Then run the review level gate (`/claude-workstation:review-level-gate`) to determine Standard or Consensus review. Log: `micro-tier: <micro-trivial|micro-small|micro-complex>, review-level: <standard|consensus>`
```

After the "Batch review cadence" line, add:

```
**Review level gate:** After micro-tier assessment, evaluate objective signals (security, API surface, cross-domain, supply-chain, infrastructure) against the sub-task description. Any signal → Consensus review (dual independent, santa-method). No signals → Standard review (single reviewer). Consensus tasks always get individual review and reset the batch counter.
```

- [ ] **Step 4: Update workflow.md — Skill References section**

In the Skill References section (~line 92), add a new bullet:

```
- **Review level gate** (Medium+) → `/claude-workstation:review-level-gate` (Standard vs Consensus review intensity at claim-time)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-behaviors.sh 2>&1 | grep 'N+1'`
Expected: PASS on all (N+1) tests

- [ ] **Step 6: Commit**

```bash
git add contexts/workflow.md tests/test-behaviors.sh
git commit -m "feat: integrate review-level-gate into workflow context"
```

---

### Task 3: Add enforcement tests for gate bypass scenarios

Test that the skill's anti-bypass rules are documented and that critical edge cases are covered.

**Files:**
- Modify: `tests/test-behaviors.sh`

- [ ] **Step 1: Write the tests**

Add to `tests/test-behaviors.sh`:

```bash
# ---------------------------------------------------------------------------
# Section N+2: review-level-gate enforcement guards
# ---------------------------------------------------------------------------
echo ""
echo "N+2. review-level-gate enforcement"

SKILL_FILE="$PLUGIN_ROOT/skills/review-level-gate/SKILL.md"

# (N+2)a. Security always triggers Consensus
if grep -qi 'security.*consensus\|security.*no exception' "$SKILL_FILE" 2>/dev/null; then
    pass "(N+2)a. security signal always triggers Consensus"
else
    fail "(N+2)a. security signal does not explicitly require Consensus"
fi

# (N+2)b. Budget exhaustion falls back to Standard, never skips
if grep -qi 'budget.*standard\|fall.*back.*standard\|never.*skip.*review' "$SKILL_FILE" 2>/dev/null; then
    pass "(N+2)b. budget exhaustion falls back to Standard (never skips)"
else
    fail "(N+2)b. budget exhaustion behavior not documented"
fi

# (N+2)c. Max 1 escalation per task documented
if grep -qi 'max.*1.*escalation\|one.*escalation.*per.*task' "$SKILL_FILE" 2>/dev/null; then
    pass "(N+2)c. max 1 escalation per task documented"
else
    fail "(N+2)c. max 1 escalation per task NOT documented"
fi

# (N+2)d. Escalation is up only
if grep -qi 'up.*only\|never.*demote\|never.*down' "$SKILL_FILE" 2>/dev/null; then
    pass "(N+2)d. escalation up-only rule documented"
else
    fail "(N+2)d. escalation up-only rule NOT documented"
fi

# (N+2)e. Consensus tasks skip batch review
if grep -qi 'consensus.*individual\|consensus.*skip.*batch\|consensus.*reset.*batch' "$SKILL_FILE" 2>/dev/null; then
    pass "(N+2)e. Consensus tasks skip batch / get individual review"
else
    fail "(N+2)e. Consensus/batch interaction not documented"
fi

# (N+2)f. Red flags / rationalization table present
if grep -qi 'red.flag\|rationali' "$SKILL_FILE" 2>/dev/null; then
    pass "(N+2)f. red flags / rationalization guards present"
else
    fail "(N+2)f. red flags / rationalization guards missing"
fi

# (N+2)g. Human escalation after 3 Consensus rounds
if grep -qi 'human\|escalate.*3.*round\|3.*round.*escalat' "$SKILL_FILE" 2>/dev/null; then
    pass "(N+2)g. human escalation after 3 rounds documented"
else
    fail "(N+2)g. human escalation after 3 rounds NOT documented"
fi

# (N+2)h. Signal detection runs against task text, not code
if grep -qi 'task.*text\|description.*plan.*text\|not.*against.*implementation\|not.*code' "$SKILL_FILE" 2>/dev/null; then
    pass "(N+2)h. signal detection runs against task text, not code"
else
    fail "(N+2)h. signal detection scope (task text vs code) not documented"
fi
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `bash tests/test-behaviors.sh 2>&1 | tail -30`
Expected: PASS on all (N+2) tests (the skill from Task 1 already contains all these elements)

- [ ] **Step 3: Commit**

```bash
git add tests/test-behaviors.sh
git commit -m "test: add enforcement guards for review-level-gate"
```

---

### Task 4: Update the start skill to mention review-level-gate in Medium+ routing

The `/start` skill routes Medium+ tasks through brainstorm → plan → sub-tasks. The sub-task flow should reference the review level gate.

**Files:**
- Modify: `skills/start/SKILL.md` (Step 6: ROUTE section, Medium+ entry)

- [ ] **Step 1: Write the failing test**

Add to `tests/test-behaviors.sh`:

```bash
# ---------------------------------------------------------------------------
# Section N+3: start skill references review-level-gate
# ---------------------------------------------------------------------------
echo ""
echo "N+3. start skill review-level-gate reference"

START_FILE="$PLUGIN_ROOT/skills/start/SKILL.md"

# (N+3)a. Start skill mentions review-level-gate for Medium+
if grep -qi 'review.level' "$START_FILE" 2>/dev/null; then
    pass "(N+3)a. start skill references review level"
else
    fail "(N+3)a. start skill does not reference review level"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-behaviors.sh 2>&1 | grep 'N+3'`
Expected: FAIL

- [ ] **Step 3: Update start skill**

In `skills/start/SKILL.md`, find the Medium+ row in the Step 6 ROUTE table. After the existing text about invoking `/superpowers:brainstorming`, add a note in the description or as a comment:

In the Step 6 section, after the route table, add:

```markdown
**Medium+ sub-task flow note:** When sub-tasks are claimed during execution, the orchestrator assesses both micro-tier AND review level (`/claude-workstation:review-level-gate`). This happens automatically in `superpowers:subagent-driven-development`.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-behaviors.sh 2>&1 | grep 'N+3'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add skills/start/SKILL.md tests/test-behaviors.sh
git commit -m "docs: reference review-level-gate in start skill Medium+ routing"
```

---

### Task 5: Update help skill to include review-level-gate in command reference

The help skill shows available commands and workflow steps. Add the new gate.

**Files:**
- Modify: `skills/help/SKILL.md` (if it exists; otherwise check where help content lives)

- [ ] **Step 1: Locate the help content**

```bash
find skills/ -name 'SKILL.md' | xargs grep -l 'command reference\|available.*command\|workflow.*step' 2>/dev/null
```

If the help skill is at `skills/help/SKILL.md`, modify it. If help is generated from workflow.md, this task is already covered by Task 2.

- [ ] **Step 2: Write the failing test**

Add to `tests/test-behaviors.sh`:

```bash
# ---------------------------------------------------------------------------
# Section N+4: help content includes review-level-gate
# ---------------------------------------------------------------------------
echo ""
echo "N+4. help content review-level-gate reference"

HELP_FILE="$PLUGIN_ROOT/skills/help/SKILL.md"
if [[ -f "$HELP_FILE" ]]; then
    if grep -qi 'review.level' "$HELP_FILE" 2>/dev/null; then
        pass "(N+4)a. help skill references review-level-gate"
    else
        fail "(N+4)a. help skill does not reference review-level-gate"
    fi
else
    # Help may be derived from workflow.md — check there
    if grep -qi 'review.level.*gate' "$PLUGIN_ROOT/contexts/workflow.md" 2>/dev/null; then
        pass "(N+4)a. help derived from workflow.md which includes review-level-gate"
    else
        fail "(N+4)a. neither help skill nor workflow.md references review-level-gate"
    fi
fi
```

- [ ] **Step 3: Update help content (if separate file exists)**

If `skills/help/SKILL.md` exists, add under the Medium+ workflow section:

```markdown
- `/claude-workstation:review-level-gate` — Assess review intensity (Standard/Consensus) at sub-task claim time
```

If help is derived from workflow.md, this is already covered by Task 2 — mark this task as N/A.

- [ ] **Step 4: Run tests and commit**

```bash
bash tests/test-behaviors.sh 2>&1 | grep 'N+4'
git add skills/help/SKILL.md tests/test-behaviors.sh  # or just tests/ if no help file
git commit -m "docs: add review-level-gate to help content"
```

---

## Self-Review Checklist

**1. Spec coverage:**
- [x] Two levels (Standard/Consensus) — Task 1
- [x] Objective signals (5 categories) — Task 1
- [x] Claim-time assessment — Task 1, Task 2
- [x] Reviewer escalation (ESCALATE protocol) — Task 1
- [x] Budget cap with defaults — Task 1
- [x] No self-confidence signal — Task 1 (test Ng explicitly guards this)
- [x] Micro-tier interaction — Task 1, Task 2
- [x] Batch review interaction — Task 1, Task 2
- [x] Workflow integration — Task 2
- [x] Enforcement guards — Task 3
- [x] Start skill routing — Task 4
- [x] Help/discoverability — Task 5

**2. Placeholder scan:** No TBD, TODO, or "implement later" found.

**3. Type consistency:** Review levels consistently named "Standard" and "Consensus" throughout. Signal names match between skill and tests. Budget terms match between skill and workflow.
