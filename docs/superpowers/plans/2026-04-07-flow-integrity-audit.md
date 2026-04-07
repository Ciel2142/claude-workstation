# Flow Integrity Audit — Implementation Plan

> **For agentic workers:** This is a research/audit plan. Each task is a parallel agent that reads files and produces findings. Use `superpowers:dispatching-parallel-agents` to run Tasks 1-4 concurrently, then Task 5 merges results.

**Goal:** Produce a comprehensive findings document covering consistency, enforcement, rationalization surface, and fragility across all claude-workstation plugin files.

**Architecture:** Four parallel read-only audit agents (one per pass), followed by a merge step that produces the final findings document. No code changes during audit.

**Tech Stack:** Bash (Read, Grep, Glob tools only — no Edit/Write during audit passes)

---

### Task 1: Consistency Pass

**Purpose:** Find drift between files that express the same rules.

**Files to read:**
- `contexts/workflow.md` (primary source of truth)
- `commands/help.md`
- `skills/start/SKILL.md`
- `skills/resume/SKILL.md`
- `skills/status/SKILL.md`
- `skills/debugging-protocol/SKILL.md`
- `skills/beads-milestones/SKILL.md`
- `skills/scope-health/SKILL.md`
- `skills/spike-phase/SKILL.md`
- `skills/verification-template/SKILL.md`
- `skills/setup/SKILL.md`
- `skills/test/SKILL.md`
- `CLAUDE.md`
- `README.md`
- `AGENTS.md`

**Cross-references to check (produce a finding for each mismatch):**

- [ ] **1.1: Tier definitions** — Compare the tier table (Trivial/Small/Medium+) across: `workflow.md`, `help.md`, `README.md`, `start/SKILL.md`. Check: signal descriptions match, score thresholds match, flow descriptions match.

- [ ] **1.2: Tier flows** — For each tier, trace the step sequence in `workflow.md` vs `help.md`. Every numbered step must match (name, order, skill invoked). Check Bug path separately.

- [ ] **1.3: Position detection** — Compare the milestone-to-position mapping table in `resume/SKILL.md` vs `status/SKILL.md`. Must be identical (same priorities, same patterns, same positions).

- [ ] **1.4: Skill routing** — Compare the position-to-skill routing table in `resume/SKILL.md` vs `status/SKILL.md`. Must match. Then verify `workflow.md` and `help.md` agree on which skill each phase invokes.

- [ ] **1.5: Milestone keys** — Compare the canonical key list in `beads-milestones/SKILL.md` against the patterns matched in `resume/SKILL.md` (Step 4) and `status/SKILL.md` (Step 3). Every key used for routing must appear in the canonical list.

- [ ] **1.6: Side-quest trigger** — Compare the side-quest detection criteria in `workflow.md`, `help.md`, and `start/SKILL.md`. Wording must use "outside confirmed scope" (not "unrelated").

- [ ] **1.7: Pre-Change Gate** — Compare the 3-step gate in `workflow.md` vs `help.md`. Verify `pre-change-gate` hook implements the checks described.

- [ ] **1.8: Scope Confirmation** — Compare scope confirmation rules in `workflow.md` vs `help.md`. Check for matching exceptions (plan sub-tasks, /start invocations).

- [ ] **1.9: Micro-tier table** — Compare micro-tier definitions in `workflow.md` vs `help.md`. Signal, ceremony, and batch review cadence must match.

- [ ] **1.10: Bug path** — Compare bug workflow in `workflow.md`, `help.md`, and `debugging-protocol/SKILL.md`. Step order and skill sequence must match.

- [ ] **1.11: Spec amendments** — Compare minor vs material criteria in `workflow.md` vs `help.md`. Must match.

- [ ] **1.12: CLAUDE.md claims** — Verify every claim in `CLAUDE.md` is accurate (context budget ~7KB, skill names, quick start commands).

- [ ] **1.13: README accuracy** — Verify README tier table, hook table, project structure tree, and test count description match actual state.

- [ ] **1.14: Escalation rules** — Compare escalation rules (Trivial->Small, Small->Medium+) in `workflow.md` vs `help.md`. Step references must be correct.

- [ ] **1.15: Verification Failure Protocol** — Compare Type A/B/C table in `workflow.md` vs `help.md`. Wording must match.

**Output format:** For each mismatch, produce:
```
### D[N]: [title]
**Severity:** Drift
**Files:** [file1:line], [file2:line]
**Finding:** [what differs]
**Evidence:** [exact text from each file]
```

---

### Task 2: Enforcement Pass

**Purpose:** For each workflow rule, determine what enforces it mechanically.

**Files to read:**
- `contexts/workflow.md` (extract all rules)
- `hooks/pre-change-gate` (lines 1-84)
- `hooks/stop` (lines 1-51)
- `hooks/session-start` (lines 1-65)
- `hooks/hooks.json` (lines 1-47)
- `hooks/bd-notes-append` (lines 1-47)
- `tests/validate-config.sh` (all — check which rules have test coverage)
- `tests/test-behaviors.sh` (all — check which rules have behavioral tests)

**Rules to audit (produce a finding for each unprotected rule):**

- [ ] **2.1: "No code without beads task"** — Check: `pre-change-gate` hook fires on Edit/Write (hooks.json). Does it also fire on Bash? (Bash can create/modify files too.) Does it fire on NotebookEdit?

- [ ] **2.2: "Tier assessment before work"** — Check: `pre-change-gate` warns if no `tier:` in notes. Is there a test for this? (Yes: test 2b.) Is there a test for the positive case? (Yes: test 2c.)

- [ ] **2.3: "No skipping tiers downward"** — Check: is there ANY enforcement? A hook? A test? Or is this purely text-based?

- [ ] **2.4: "Scope confirmation before changes"** — Check: is there any enforcement beyond the agent reading the rule? Could a hook check for confirmation in the conversation?

- [ ] **2.5: "Side-quest for out-of-scope discoveries"** — Check: is there any enforcement? The pre-change-gate doesn't check scope. This relies entirely on the agent reading workflow.md.

- [ ] **2.6: "No production code without failing test"** — Check: is there any hook or test that verifies TDD order? Or is this purely text-based?

- [ ] **2.7: "Milestone updates at phase transitions"** — Check: what happens if an agent skips a milestone update? Does resume/status break? Are there tests for missing milestones?

- [ ] **2.8: "Spec amendments must be logged"** — Check: any enforcement? Or purely text-based?

- [ ] **2.9: "Scope health every 3rd sub-task"** — Check: any automatic trigger? Or does the agent need to count and self-trigger?

- [ ] **2.10: "Session close protocol"** — Check: `stop` hook warns about untracked commits. Does it warn about unpushed commits? Does it check for unclosed tasks?

- [ ] **2.11: "Beads-first rule"** — Check: same as 2.1 but specifically — does the hook catch `bd create` happening AFTER file edits in the same session?

- [ ] **2.12: "Pre-Change Gate 3-step check"** — Check: the hook checks steps 1-2 (task exists, tier exists). Does it check step 3 (scope confirmed this turn)?

**Output format:** For each rule, produce:
```
### BS[N]: [title]
**Severity:** Blind spot (or "Enforced" if covered)
**Rule:** [exact rule text from workflow.md]
**Enforcement:** [what enforces it, or "None — text only"]
**Test coverage:** [which tests cover it, or "None"]
**Risk:** [what happens when violated]
```

---

### Task 3: Rationalization Surface Pass

**Purpose:** Find subjective terms and escape hatches that agents can interpret away.

**Files to read:**
- `contexts/workflow.md` (every rule)
- `commands/help.md` (every rule)
- `skills/start/SKILL.md` (Claude Override, side-quest detection)
- `skills/resume/SKILL.md` (tier inference, artifact fallback)
- `skills/scope-health/SKILL.md` (ratio thresholds)
- `skills/spike-phase/SKILL.md` (conditional depth)
- `skills/debugging-protocol/SKILL.md` (3-strike rule)
- `skills/beads-milestones/SKILL.md` (when to update)

**Patterns to scan for:**

- [ ] **3.1: Subjective adjectives** — Search all files for: "appropriate", "reasonable", "significant", "meaningful", "relevant", "related", "unrelated", "obvious", "clearly", "simple", "complex". For each hit, assess: could an agent use this word to rationalize skipping a rule?

- [ ] **3.2: Conditional escapes** — Search for: "unless", "except when", "when warranted", "if needed", "when applicable", "as needed", "if appropriate". For each, assess: is the condition objective (measurable) or subjective (judgment call)?

- [ ] **3.3: Claude Override in /start** — The scoring matrix says "You have freedom to override the numerical score when context clearly warrants it." This is an explicit escape hatch. Assess: what stops an agent from always overriding downward to skip ceremony?

- [ ] **3.4: Micro-tier self-assessment** — Agents assess their own sub-task micro-tiers. What stops an agent from always choosing "micro-trivial" to minimize ceremony?

- [ ] **3.5: Spec amendment threshold** — "Minor" vs "material" is a judgment call. Could an agent classify a material change as minor to avoid stopping for human approval?

- [ ] **3.6: Scope Confirmation exceptions** — "Does NOT apply when executing confirmed plan sub-tasks within a Medium+ epic." Could an agent claim something is a "confirmed plan sub-task" when it isn't?

- [ ] **3.7: Side-quest trigger phrasing** — Check `start/SKILL.md` Step 2 for the side-quest detection wording. Is "would touch files outside the confirmed scope" objective enough? What about the "different files, different directory, or different concern" clause?

- [ ] **3.8: "when applicable" / "as needed" in help.md** — The Medium+ path lists optional steps with "Use when needed." Could agents always skip these?

- [ ] **3.9: Beads-milestones "meaningful" threshold** — "Don't update if nothing meaningful changed." What counts as meaningful?

- [ ] **3.10: Debugging 3-strike interpretation** — "If three hypotheses fail, question the architecture." This is vague. What does "question" mean? Stop? Escalate? Just think harder?

**Output format:** For each finding, produce:
```
### R[N]: [title]
**Severity:** Rationalization surface (or Break if it causes wrong outcomes)
**File:** [file:line]
**Text:** [exact quote]
**Risk:** [how an agent could exploit this]
**Suggested fix:** [objective replacement, if one exists]
```

---

### Task 4: Fragility Pass

**Purpose:** Find edge cases, silent failures, and assumptions in hooks and scripts.

**Files to read:**
- `hooks/pre-change-gate` (lines 1-84)
- `hooks/stop` (lines 1-51)
- `hooks/session-start` (lines 1-65)
- `hooks/bd-notes-append` (lines 1-47)
- `hooks/hooks.json` (lines 1-47)
- `tests/validate-config.sh` (all)
- `tests/test-behaviors.sh` (all)
- `tests/lib.sh` (all)
- `tests/scenarios/*.sh` (all 9 files)
- `profiles/aliases.sh` (lines 1-11)

**Checks to perform:**

- [ ] **4.1: pre-change-gate silent exit paths** — The hook exits 0 on every path (line 4: "Always exits 0 — warns but never blocks"). Catalog every early-exit path and assess whether any should produce a warning instead of silently passing.

- [ ] **4.2: pre-change-gate cache race** — Two concurrent sessions editing different files could race on the same cache file. The symlink guard (lines 35-36, 76) addresses CWE-59 but not concurrent write races. Assess: is this a realistic scenario?

- [ ] **4.3: pre-change-gate bd output parsing** — Lines 51-59 parse `bd list --json` output then fall back to text parsing. Check: what happens if `bd list` returns valid JSON but with unexpected schema (missing "id" field, nested structure, etc.)?

- [ ] **4.4: bd-notes-append section header list** — Line 38 lists known section headers (TITLE, STATUS, etc.) for note extraction. Check: is this list complete? What happens if beads adds a new section header? Could notes be truncated?

- [ ] **4.5: bd-notes-append multiline notes** — What happens if a note value contains a newline? Does the sed pipeline handle it correctly?

- [ ] **4.6: stop hook commit counting** — Line 28 counts recent commits with `wc -l`. Check: does `--since` work correctly across timezone changes? DST transitions?

- [ ] **4.7: stop hook false negatives** — The hook only warns if `RECENT_COMMITS > 0 && IN_PROGRESS == 0 && CLOSED_RECENT == 0 && OPEN_COUNT == 0`. What if commits exist and tasks were closed but the close happened in a previous session (status shows 0 closed in current window)?

- [ ] **4.8: session-start JSON escaping** — The `escape_for_json` function (lines 42-50) handles backslash, quotes, newlines, carriage returns, and tabs. Check: does it handle control characters (0x00-0x1F)? Unicode? Does it handle dollar signs or backticks that could cause shell expansion?

- [ ] **4.9: hooks.json CLAUDE_PLUGIN_ROOT assumption** — All commands use `${CLAUDE_PLUGIN_ROOT}`. What happens if this env var is unset? Does the hook runner expand it before passing to bash?

- [ ] **4.10: test coverage gaps** — Compare the list of hook behaviors against test-behaviors.sh test cases. Are there untested paths? Specifically check: pre-change-gate JSON fallback path, bd-notes-append with bd show failure, stop hook with git not available.

- [ ] **4.11: validate-config.sh test count accuracy** — The test SKILL.md says "170+ checks". Count actual checks in validate-config.sh. Is this number current?

- [ ] **4.12: scenario scripts coordination file** — Scenarios use `COORD_FILE` for cross-script state. Check: what happens if cleanup.sh doesn't run (test killed mid-flight)? Is state left behind?

- [ ] **4.13: aliases.sh --effort flag** — Aliases use `--effort high`. Check: is this a valid claude CLI flag? What happens if the CLI version doesn't support it?

- [ ] **4.14: session-start branch detection** — Lines 57-63 detect Cursor, Copilot CLI, and Claude Code. Check: are the detection env vars correct? What happens if multiple are set (both CURSOR_PLUGIN_ROOT and COPILOT_CLI)?

**Output format:** For each finding, produce:
```
### F[N]: [title]
**Severity:** Fragile (or Break if it causes wrong outcomes now)
**File:** [file:line]
**Finding:** [what could go wrong]
**Conditions:** [when it would trigger]
**Current test coverage:** [which tests cover this, or "None"]
```

---

### Task 5: Merge and Produce Findings Document

**Depends on:** Tasks 1-4 complete.

**Files:**
- Create: `docs/superpowers/specs/2026-04-07-flow-integrity-findings.md`

- [ ] **5.1: Collect outputs** — Gather findings from all four parallel agents.

- [ ] **5.2: Deduplicate** — If two passes found the same issue (e.g., a drift finding that's also a rationalization surface), keep the higher-severity version and cross-reference.

- [ ] **5.3: Assign final IDs** — Renumber findings sequentially within each category.

- [ ] **5.4: Write summary** — Count findings by severity. Produce the summary line: `Break: N | Drift: N | Blind spot: N | Fragile: N | Info: N`.

- [ ] **5.5: Write findings document** — Merge all findings into `docs/superpowers/specs/2026-04-07-flow-integrity-findings.md` following the format from the design spec.

- [ ] **5.6: Commit** — `git add docs/superpowers/specs/2026-04-07-flow-integrity-findings.md && git commit -m "docs: flow integrity audit findings"`

- [ ] **5.7: Update beads milestone** — `bash bd-notes-append claude-workstation-d1m "plan: docs/superpowers/plans/2026-04-07-flow-integrity-audit.md"`

- [ ] **5.8: Present to user** — Print the summary and ask user to review findings before creating fix tasks.
