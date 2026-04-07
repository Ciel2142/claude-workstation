# Flow Integrity Audit — Findings

**Date:** 2026-04-07
**Epic:** claude-workstation-d1m
**Audited by:** 4 parallel Opus agents + merge review

## Summary

| Severity | Count |
|---|---|
| Break | 2 |
| Drift | 13 |
| Blind spot | 7 |
| Partially enforced | 5 |
| Rationalization surface | 17 |
| Fragile | 10 |
| Info | 13 |
| **Total** | **67** |

**Top 5 priority fixes:**
1. **R9** (Break) — Spike "required" vs "optional" contradiction across 3 files
2. **F10** (Break) — Stop hook warning permanently disabled in any project with history
3. **R1** — Claude Override allows downward tier overrides with no audit trail
4. **R17** — Resume defaults to trivial (least ceremony) when tier is missing
5. **BS1** — Pre-change-gate doesn't fire on Bash tool (complete bypass)

---

## Pass 1: Consistency

### D1: Spec Amendments — Minor criteria list differs
**Severity:** Drift
**Files:** workflow.md:64, help.md:165
**Finding:** workflow.md includes "parameter type corrections to match existing code" as a minor amendment criterion. help.md omits this.
**Evidence:**
- workflow.md: `Minor (agent self-approves): Naming mismatches, missing edge case detail, clarifying ambiguous wording, parameter type corrections to match existing code.`
- help.md: `Minor (agent self-approves): Naming mismatches, missing edge case detail, clarifying ambiguous wording.`

### D2: Spec Amendments — Material criteria list differs
**Severity:** Drift
**Files:** workflow.md:68, help.md:166
**Finding:** workflow.md includes "architectural changes" in the material criteria. help.md omits it.
**Evidence:**
- workflow.md: `Material (requires human approval): Different algorithm, adding/dropping features, new dependencies, changed API shape, architectural changes.`
- help.md: `Material (requires human approval): Different algorithm, adding/dropping features, new dependencies, changed API shape.`

### D3: Spec Amendments — Material logging instruction absent from help.md
**Severity:** Drift
**Files:** workflow.md:70, help.md:166
**Finding:** workflow.md includes logging instruction for material amendments. help.md has none.
**Evidence:**
- workflow.md: `Log: spec-amendment: material -- <what changed>, approved by human`
- help.md: `Stop and present the change, wait for approval.` (no log instruction)

### D4: Pre-Change Gate step 3 — Name differs
**Severity:** Drift
**Files:** workflow.md:31, help.md:13
**Finding:** workflow.md calls step 3 "Scope confirmed this turn?" while help.md calls it "Scope Confirmation".

### D5: Pre-Change Gate step 3 — Prior intent examples differ
**Severity:** Drift
**Files:** workflow.md:33, help.md:13
**Finding:** workflow.md lists three examples ("yeah", "go ahead", "just do it"). help.md lists two ("yeah", "go ahead") — omitting "just do it".

### D6: Scope Confirmation exceptions absent from help.md
**Severity:** Drift
**Files:** workflow.md:43-45, help.md (absent)
**Finding:** workflow.md defines two exceptions to scope confirmation: (1) confirmed Medium+ plan sub-tasks, (2) /start invocations. help.md has no equivalent section.

### D7: Bug tier flow — README uses "close" instead of "bd close"
**Severity:** Drift
**Files:** workflow.md:16, README.md:96
**Finding:** workflow.md writes `bd close` in the Bug flow. README writes just `close`.

### D8: Verification Failure Protocol — Type B wording differs
**Severity:** Drift
**Files:** workflow.md:123, help.md:186
**Finding:** workflow.md: "even if your change caused the failure" with full action. help.md: "even if your change caused it" with abbreviated action.

### D9: Verification Failure Protocol — Type A wording differs
**Severity:** Drift
**Files:** workflow.md:122, help.md:185
**Finding:** workflow.md: "The file to fix is one already in your confirmed scope" / "Fix within current task". help.md: "File to fix is in your confirmed scope" / "fix in current task".

### D10: Verification Failure Protocol — Type C action differs
**Severity:** Drift
**Files:** workflow.md:124, help.md:187
**Finding:** workflow.md: "Side-quest: create bug, park it, do NOT fix now". help.md: "side-quest, park it" (abbreviated).

### D11: Context budget claim — ~7KB understates actual size
**Severity:** Drift
**Files:** CLAUDE.md:18, README.md:8
**Finding:** Both claim "~7KB". Actual workflow.md is 8015 bytes (7.8KB), closer to ~8KB.

### D12: README project structure tree — missing README.md
**Severity:** Drift
**Files:** README.md:120-155
**Finding:** The project tree lists CLAUDE.md and AGENTS.md as root files but omits README.md itself.

### D13: Tier table format — help.md differs from workflow.md
**Severity:** Drift
**Files:** workflow.md:11, help.md:35
**Finding:** workflow.md tier table has "Tier | Signal | Flow" (4 rows including Bug). help.md has "Tier | Signal | Examples" (3 rows, Bug is a separate section).

---

## Pass 2: Enforcement

### BS1: Beads-First Rule — Bash tool bypass
**Severity:** Partially enforced
**Rule:** "Before making ANY change to the codebase — editing files, deleting files, running destructive commands..."
**Enforcement:** pre-change-gate fires on Edit and Write only (hooks.json). Does NOT fire on Bash, NotebookEdit, or Agent tool.
**Test coverage:** Tests 2a-2c, 15a-15f
**Risk:** Agent can create/modify files via Bash (`echo > file`, `sed -i`, `cp`, `mv`, `cat <<EOF > file`) completely bypassing the gate. Also: subagents dispatched via Agent tool get fresh context with no knowledge of the parent's beads task state.

### BS2: Tier assessment — warn-only enforcement
**Severity:** Partially enforced
**Rule:** Tier assessment before work (implied by Pre-Change Gate step 1)
**Enforcement:** pre-change-gate warns if no `tier:` in notes. Always exits 0 — never blocks.
**Test coverage:** Tests 2b (warns), 2c (silent when tier exists)
**Risk:** Agent can proceed despite the warning. Combined with BS1 Bash bypass, files can be modified without this check ever running.

### BS3: No skipping tiers downward
**Severity:** Blind spot
**Rule:** "Escalation only upward — never downgrade." (workflow.md:18)
**Enforcement:** None. No hook checks current tier value or prevents overwriting a higher tier with a lower one. bd-notes-append blindly appends.
**Test coverage:** None
**Risk:** Agent silently downgrades medium+ to trivial, skipping all ceremony.

### BS4: Scope confirmation before changes
**Severity:** Blind spot
**Rule:** "Restate specific files/changes, get explicit 'yes.' Prior intent does NOT count." (workflow.md:31-33)
**Enforcement:** None. pre-change-gate has no access to conversation state. Cannot verify the agent asked for or received confirmation.
**Test coverage:** None
**Risk:** Agent proceeds directly from user intent to file edits without restating scope.

### BS5: Side-quest for out-of-scope discoveries
**Severity:** Blind spot
**Rule:** "Discover a problem in a file outside your confirmed scope mid-work..." + Collateral Breakage Rule (workflow.md:131-144)
**Enforcement:** None. No hook checks whether file being edited is in the task's scope. No scope registry mapping task IDs to permitted file paths.
**Test coverage:** None
**Risk:** Agent fixes collateral breakage inline. This is the exact violation class that triggered this audit.

### BS6: No production code without failing test
**Severity:** Blind spot
**Rule:** "No production code without a failing test (Small/Medium+)" (workflow.md:23)
**Enforcement:** None. No hook distinguishes test files from production files or checks ordering.
**Test coverage:** None
**Risk:** Agent writes implementation first, then tests (or skips tests entirely).

### BS7: Milestone updates at phase transitions
**Severity:** Partially enforced
**Rule:** Milestone system used by /resume and /status for position detection
**Enforcement:** /resume has artifact fallback (checks for files, sub-tasks, git commits when milestones are missing). Falls back gracefully but may misroute.
**Test coverage:** Tests 3a-3h (position detection), 11a-11f (milestone schema)
**Risk:** Partial milestone logging causes resume to route to wrong phase.

### BS8: Spec amendments must be logged
**Severity:** Blind spot
**Rule:** "When implementation reveals the spec is wrong, amend it — don't silently deviate." (workflow.md:62)
**Enforcement:** None. No hook checks whether spec files were modified without a corresponding log entry.
**Test coverage:** None
**Risk:** Agent silently changes spec, material changes proceed without human approval.

### BS9: Scope health every 3rd sub-task
**Severity:** Blind spot
**Rule:** "Every 3rd sub-task (Medium+) → /claude-workstation:scope-health" (workflow.md:95)
**Enforcement:** None. No automatic trigger. Agent must count sub-tasks and self-trigger. No PostToolUse hook monitors `bd close` calls.
**Test coverage:** None
**Risk:** Agent never invokes scope-health, allowing unbounded scope creep.

### BS10: Session close protocol
**Severity:** Partially enforced
**Rule:** Session end should warn about untracked work
**Enforcement:** Stop hook checks for commits without beads issues. Does NOT check for unpushed commits, uncommitted staged changes, or unclosed in-progress tasks (those are just listed, not warned about).
**Test coverage:** Tests 4a-4c
**Risk:** Work lost if session ends without pushing. See also F10 (the warning itself is broken).

### BS11: Pre-Change Gate 3-step check
**Severity:** Partially enforced
**Rule:** Steps 1-3: Task Boundary, Beads task exists, Scope confirmed this turn
**Enforcement:** Hook implements steps 1-2 (task exists, tier exists). Step 3 (scope confirmed this turn) is structurally unenforceable by shell hook — requires conversation state access.
**Test coverage:** Tests 2a-2c (steps 1-2)
**Risk:** Step 3 is entirely self-enforced. This is the last gate before file modification — most critical and least enforceable.

### BS12: Verification Failure Protocol (Type A/B/C)
**Severity:** Blind spot
**Rule:** "When tests fail during VERIFY, classify before acting" (workflow.md:118-129)
**Enforcement:** None. Classification and action are entirely agent self-assessed.
**Test coverage:** None
**Risk:** Agent classifies Type B as Type A to avoid side-quest ceremony. The workflow explicitly warns about this rationalization.

---

## Pass 3: Rationalization Surface

### R1: Claude Override allows unconstrained tier overrides
**Severity:** Rationalization surface (high)
**File:** skills/start/SKILL.md:68
**Text:** "You have freedom to override the numerical score when context clearly warrants it. The matrix is a guide, not a cage."
**Risk:** Agent overrides Medium+ down to Small to skip brainstorming ceremony. "Clearly warrants" is subjective. No directional constraint, no audit trail requirement.
**Suggested fix:** Restrict to upward-only: "You may override the numerical score UPWARD ONLY (never downward). Log: `tier-override: <computed> -> <new> -- <reason>`. Downward overrides require human approval."

### R2: Micro-tier self-assessment — agent grades itself
**Severity:** Rationalization surface (high)
**File:** contexts/workflow.md:76-84
**Text:** "When claiming a sub-task, assess its micro-tier."
**Risk:** Agent always chooses "micro-trivial" (one assertion) to avoid full TDD. Boundary between "no logic" and "single-concern logic, straightforward" is a judgment call.
**Suggested fix:** Add structural test: "If the sub-task creates or modifies any function/method body with conditional logic, loops, or error handling, it is NOT micro-trivial."

### R3: Spec amendment "clarifying ambiguous wording"
**Severity:** Rationalization surface (high)
**File:** contexts/workflow.md:64
**Text:** "Minor (agent self-approves): Naming mismatches, missing edge case detail, clarifying ambiguous wording"
**Risk:** Agent drops a feature by framing it as "clarifying that the spec's mention of X was describing existing behavior, not a new requirement."
**Suggested fix:** "Minor: Changes that do NOT alter the set of deliverables, API surface, or acceptance criteria. If any deliverable, endpoint, field, or acceptance criterion is added, removed, or functionally changed, it is Material."

### R4: Scope confirmation exception — "confirmed plan sub-tasks"
**Severity:** Rationalization surface (high)
**File:** contexts/workflow.md:44
**Text:** "Does NOT apply when executing confirmed plan sub-tasks within a Medium+ epic"
**Risk:** Agent discovers new file needs changing, stretches "confirmed plan sub-task" to cover it: "The plan said implement auth module, this file is part of auth."
**Suggested fix:** "Does NOT apply when the specific files being changed are listed in the plan document or in the sub-task's beads description."

### R5: "when applicable" in Task Sizing table
**Severity:** Rationalization surface (moderate)
**File:** contexts/workflow.md:15
**Text:** "(+ spike, worktree, update-docs, finish when applicable)"
**Risk:** Agent decides all optional steps are "not applicable" — reduces Medium+ to core flow only.
**Suggested fix:** Replace with specific triggers for each optional step.

### R6: "Use when needed" for optional steps
**Severity:** Rationalization surface (high)
**File:** commands/help.md:126-136
**Text:** "Use when needed: SPIKE [...] WORKTREE [...] UPDATE-DOCS [...] FINISH [...]"
**Risk:** Agent short-circuits without evaluating conditions. Directly contradicts spike-phase/SKILL.md (see R9).
**Suggested fix:** Replace with mandatory evaluation: "SPIKE — Evaluate triggers. If any fire → required. Log: `spike-eval: <triggered|skipped> -- <reason>`"

### R7: "meaningful" in beads-milestones threshold
**Severity:** Rationalization surface (high)
**File:** skills/beads-milestones/SKILL.md:80
**Text:** "Don't update if nothing meaningful changed since last update"
**Risk:** Agent skips all milestone updates ("micro-trivial, nothing meaningful"). Breaks /resume position detection.
**Suggested fix:** "Update at EVERY milestone in the table above. Do NOT update between milestones."

### R8: 3-strike rule — "question the architecture"
**Severity:** Rationalization surface (high)
**File:** skills/debugging-protocol/SKILL.md:22
**Text:** "if three hypotheses fail, question the architecture"
**Risk:** "Question" is a mental state, not an action. Agent "questions" for one token and continues.
**Suggested fix:** "If three hypotheses fail: STOP. Log `debug: 3-strike -- <h1>, <h2>, <h3>`. Present findings to user. Do NOT attempt a fourth hypothesis without human direction."

### R9: Spike — "Required" vs "when needed" contradiction
**Severity:** Break
**Files:** spike-phase/SKILL.md:15 ("Required for all Medium+ epics"), help.md:128 ("Use when needed"), workflow.md:15 ("when applicable")
**Finding:** Three files give contradictory guidance. Agent follows whichever suits its preference. workflow.md and help.md have more exposure (injected at session start / on /help) so "optional" wins in practice.
**Suggested fix:** Make spike EVALUATION mandatory, execution conditional: "After PLAN, evaluate spike triggers (see spike-phase skill). If any trigger fires, execute spike. Log: `spike-eval: <triggered|skipped> -- <reason>`"

### R10: Scope health counting — agent self-counts
**Severity:** Rationalization surface (moderate)
**File:** contexts/workflow.md:95, scope-health/SKILL.md:14
**Text:** "After every 3rd sub-task completion"
**Risk:** Agent "loses count" after compaction. No structural enforcement, no audit trail.
**Suggested fix:** "After closing ANY sub-task, query `bd list --status=closed` count for current epic. If `count % 3 == 0`, invoke scope-health."

### R11: "straightforward" in micro-small signal
**Severity:** Rationalization surface (moderate)
**File:** contexts/workflow.md:81
**Text:** "Single-concern logic, one function/method, straightforward."
**Risk:** Agent downgrades micro-complex to micro-small by calling security-sensitive code "straightforward," skipping individual code review.
**Suggested fix:** Remove "straightforward." Define by exclusion: "NOT any of: new algorithm, security-sensitive, public API, cross-cutting (those are micro-complex)."

### R12: Side-quest type override — "clearly"
**Severity:** Rationalization surface (minor)
**File:** skills/start/SKILL.md:148
**Text:** "If the side-quest is clearly a feature or task, use --type=feature or --type=task instead."
**Risk:** Agent types discovered bug as "task" to avoid debugging-first protocol.
**Suggested fix:** "Type defaults to bug for all side-quests involving broken behavior, regardless of beads type."

### R13: "No logic" in micro-trivial signal
**Severity:** Rationalization surface (moderate)
**File:** contexts/workflow.md:80
**Text:** "Config, wiring, exports, type files, boilerplate. No logic."
**Risk:** "Logic" is undefined. Agent labels real code as "boilerplate" to get micro-trivial ceremony.
**Suggested fix:** "No logic means: no conditional branches, no loops, no try/catch, no function calls that could fail, no computed values."

### R14: Side-quest — "different concern" subjectivity
**Severity:** Rationalization surface (moderate)
**File:** skills/start/SKILL.md:39
**Text:** "different files, different directory, or different concern"
**Risk:** "Different concern" is subjective. Agent argues "same concern (auth), different file, so not a side-quest."
**Suggested fix:** Drop "different concern": "files not listed in the current task's beads description or plan."

### R15: Spike gate check reuses Minor/Material ambiguity
**Severity:** Rationalization surface (moderate)
**File:** skills/spike-phase/SKILL.md:57-58
**Text:** "if any spike-revised entry is material [...] Minor revisions (naming, paths) can be self-corrected."
**Risk:** Agent frames architectural change as "just updated the file path."
**Suggested fix:** "If a spike-revised entry changes any assumption about external APIs, libraries, or system boundaries, it is always Material."

### R16: "relevant" in scope-health split decision
**Severity:** Rationalization surface (minor)
**File:** skills/scope-health/SKILL.md:63
**Text:** "move relevant sub-tasks"
**Risk:** Agent cherry-picks which tasks to move based on preference.
**Suggested fix:** "Move all sub-tasks created after the original plan that are not dependencies of originally-planned sub-tasks."

### R17: Resume defaults to trivial when tier missing
**Severity:** Rationalization surface (high)
**File:** skills/resume/SKILL.md:108
**Text:** "Otherwise → default to trivial (safest: minimal ceremony, can always escalate)"
**Risk:** Agent creates tasks via raw `bd create` (bypassing /start) to ensure no tier exists, guaranteeing trivial default = no TDD, no review. The comment "safest" is misleading — trivial is least ceremony.
**Suggested fix:** Default to small: "Otherwise → default to small (ensures minimum TDD + review)." Or require the agent to assess and set tier if none found.

### R18: "Run relevant check" in Trivial verify
**Severity:** Rationalization surface (minor)
**File:** commands/help.md:48
**Text:** "VERIFY   Run relevant check (build, lint, etc.)"
**Risk:** Agent decides no check is "relevant" and skips verification entirely.
**Suggested fix:** "VERIFY   Run at minimum: build + linter. If tests exist, run them. No check = no close."

---

## Pass 4: Fragility

### F1: pre-change-gate silent exit — no .beads dir
**Severity:** Info
**File:** hooks/pre-change-gate:14-16
**Finding:** Silently exits 0 when no .beads directory exists. Correct behavior for non-beads projects, but no trace that the hook ran.
**Conditions:** Non-beads project or misconfigured beads init.
**Current test coverage:** validate-config.sh 15c (exit 0 from /tmp)

### F2: pre-change-gate silent exit — bd not installed
**Severity:** Info
**File:** hooks/pre-change-gate:19-21
**Finding:** Silently exits 0 with no warning. Compare: stop hook (line 19) DOES warn.
**Conditions:** bd not in PATH.
**Current test coverage:** None

### F3: pre-change-gate — 60-second cache blind spot
**Severity:** Info
**File:** hooks/pre-change-gate:41-44
**Finding:** Cache hit returns previous result for 60 seconds. If task is deleted within that window, gate doesn't notice.
**Conditions:** Task state changes within 60 seconds of last check. By design (performance).
**Current test coverage:** None (tests clear cache before each run)

### F4: pre-change-gate cache race in parallel sessions
**Severity:** Fragile
**File:** hooks/pre-change-gate:30-32, 76-77
**Finding:** Two concurrent sessions in the same project share the cache file. Session A writes empty (task OK), session B reads stale empty and passes. Write is not atomic (truncate then write).
**Conditions:** Parallel Claude sessions editing same project within 60 seconds. Realistic with tmux/multi-agent workflows.
**Current test coverage:** None

### F5: pre-change-gate bd JSON schema assumption
**Severity:** Fragile
**File:** hooks/pre-change-gate:51-55
**Finding:** Parses JSON with `grep -o '"id": *"[^"]*"'`. Breaks if bd changes JSON key name or structure. Falls through to text fallback, which is a safety net. If bd consistently returns errors as JSON objects, both branches fail → false "no task" warning.
**Conditions:** bd changes JSON schema or returns error JSON.
**Current test coverage:** Tests 2a-2c (normal path only)

### F6: pre-change-gate handles "null" JSON correctly
**Severity:** Info
**File:** hooks/pre-change-gate:52
**Finding:** Explicitly checks `!= "null"`. Correctly falls through to text parsing.
**Conditions:** N/A — handled correctly.
**Current test coverage:** None explicit, but logic is sound.

### F7: bd-notes-append hardcoded section header list
**Severity:** Fragile
**File:** hooks/bd-notes-append:38
**Finding:** 16 hardcoded section headers. If beads adds new headers (COMMENTS, HISTORY, ATTACHMENTS, etc.), content from those sections leaks into extracted notes. Silent data corruption.
**Conditions:** Future beads version adds new section header after NOTES.
**Current test coverage:** Tests 1d (all-caps freetext preserved), 1e (DEPENDS ON stops extraction). No test for unknown new headers.

### F8: bd-notes-append strips blank lines from notes
**Severity:** Fragile
**File:** hooks/bd-notes-append:39
**Finding:** `sed '/^$/d'` removes ALL blank lines. Intentional formatting (blank lines separating groups) is lost.
**Conditions:** Notes contain intentional blank line separators.
**Current test coverage:** None

### F9: stop hook timezone handling
**Severity:** Info
**File:** hooks/stop:24,28
**Finding:** `git log --since="8 hours ago"` could be off by 1 hour during DST transition. Negligible impact.
**Conditions:** DST transition within the 8-hour window.
**Current test coverage:** None (impractical to test)

### F10: Stop hook warning permanently disabled by historical issues
**Severity:** Break
**File:** hooks/stop:31-36
**Finding:** The warning fires only when `RECENT_COMMITS > 0 AND IN_PROGRESS == 0 AND CLOSED_RECENT == 0 AND OPEN_COUNT == 0`. But `bd list --status=closed` returns ALL historical closed issues, not session-scoped. So if ANY old issue was ever closed, `CLOSED_RECENT > 0` and the warning NEVER fires. The variable `CLOSED_RECENT` is misleadingly named — it's all-time, not recent. In practice, this means the untracked-work warning is permanently disabled in any project with beads history.
**Conditions:** Any project that has ever had a closed issue (i.e., every active project).
**Current test coverage:** Tests 4b and 4c validate current behavior but don't flag the semantic bug.

### F11: session-start JSON escaping — missing control characters
**Severity:** Fragile
**File:** hooks/session-start:42-50
**Finding:** `escape_for_json` handles `\`, `"`, `\n`, `\r`, `\t`. Does NOT handle form-feed (0x0C), backspace (0x08), or null bytes (0x00), which are illegal in JSON per RFC 8259.
**Conditions:** workflow.md contains control characters (unlikely for markdown, possible from copy-paste).
**Current test coverage:** Tests 5, 5a-5c test with current workflow.md content.

### F12: session-start printf % expansion
**Severity:** Fragile
**File:** hooks/session-start:58-62
**Finding:** `$escaped_content` is passed as a printf argument for `%s`, which is safe. BUT if the content itself contains `%` characters, those are NOT in the format string — they're in the data argument position, so they're safe. Wait — re-reading: `printf '... "%s" ...' "$escaped_content"` — the `%s` is the format specifier and `$escaped_content` replaces it. Any `%` in the workflow content appears in the output literally because it's in the data argument, not the format string. **Actually safe.** However, the Pass 4 agent flagged a concern — let me verify by checking if workflow.md contains `%`.
**Conditions:** Only a concern if the format/data argument analysis is wrong. Likely Info, not Fragile.
**Current test coverage:** None with `%` characters.

### F13: hooks.json CLAUDE_PLUGIN_ROOT expansion
**Severity:** Info
**File:** hooks/hooks.json:9,20,32,40
**Finding:** `${CLAUDE_PLUGIN_ROOT}` is expanded by Claude Code's hook runner, not bash. If the runner changes expansion behavior, hooks would fail visibly (not silently).
**Conditions:** Claude Code hook runner changes.
**Current test coverage:** Tests 5, 15e set the var explicitly.

### F14: session-start branch detection — multiple env vars
**Severity:** Info
**File:** hooks/session-start:57-63
**Finding:** If both CURSOR_PLUGIN_ROOT and COPILOT_CLI are set, Cursor branch wins. Correct: Cursor format should take precedence.
**Conditions:** Both env vars set. Unlikely.
**Current test coverage:** 5a tests Cursor, 5b tests Copilot, 5c tests Claude Code. No combined test.

### F15: Significant untested hook behaviors
**Severity:** Fragile
**File:** tests/test-behaviors.sh
**Finding:** Untested paths include:
- pre-change-gate: no-beads guard, no-bd guard, cache hit, cache symlink detection, text fallback when JSON fails, md5sum vs md5 fallback
- stop: no-beads guard, no-bd warning, cache cleanup, BEADS_CHECK_WINDOW override
- session-start: configure-server.sh error handling, missing workflow.md (covered by validate-config 15g but not behavioral tests)
- bd-notes-append: bd show failure path, NOTES as last section
**Conditions:** Any untested path is exercised.
**Current test coverage:** As detailed — significant gaps.

### F16: Test count claim accuracy
**Severity:** Info
**File:** skills/test/SKILL.md:13
**Finding:** Claims "170+ checks". Actual count is 170 with typical dual-shell setup. Accurate but marginal.
**Conditions:** Always. The claim is approximately correct.
**Current test coverage:** N/A

### F17: Scenario temp dir not cleaned on abnormal exit
**Severity:** Fragile
**File:** tests/scenarios/scaffold.sh
**Finding:** scaffold.sh creates mktemp directory. If test run is killed (Ctrl-C, `set -e` exit), cleanup.sh never runs. Temp dir is leaked. No trap-based cleanup in scaffold.sh. Compare: test-behaviors.sh DOES have `trap 'rm -rf ...' EXIT`.
**Conditions:** Test run interrupted before cleanup.sh.
**Current test coverage:** None

### F18: Scenario fallback to /tmp/workflow-test
**Severity:** Fragile
**File:** tests/scenarios/*.sh:5
**Finding:** Each scenario falls back to `/tmp/workflow-test` if coordination file doesn't exist. If that directory exists from a previous manual run, scenario operates on stale data.
**Conditions:** Running scenario without scaffold.sh AND /tmp/workflow-test exists.
**Current test coverage:** None

### F19: aliases.sh --effort flag
**Severity:** Info
**File:** profiles/aliases.sh:8-10
**Finding:** `--effort high` is a valid, documented Claude CLI flag. No current risk. Would fail visibly if removed in future CLI version.
**Conditions:** Future CLI removes --effort flag.
**Current test coverage:** Section 7 checks alias presence, not validity.

### F20: pre-change-gate stat portability
**Severity:** Info
**File:** hooks/pre-change-gate:38
**Finding:** `stat -c %Y` (GNU) with `stat -f %m` (BSD) fallback. If neither works, CACHE_MOD=0, cache treated as stale. Safe but cache is never effective on such systems.
**Conditions:** System with neither GNU nor BSD stat. Extremely unlikely.
**Current test coverage:** None

### F21: bd-notes-append NOTES as last section
**Severity:** Info
**File:** hooks/bd-notes-append:35-39
**Finding:** If NOTES is the last section, extraction works correctly to end of output.
**Conditions:** Handled correctly.
**Current test coverage:** Not explicitly tested (test 1a has STATUS after NOTES).

### F22: session-start dollar signs and backticks
**Severity:** Info
**File:** hooks/session-start:42-50
**Finding:** `escape_for_json` uses bash parameter expansion, not command substitution. Dollar signs and backticks in content are safe.
**Conditions:** N/A — correctly handled.
**Current test coverage:** None explicit, but code is safe.

### F23: stop hook BEADS_PATH fallback consistency
**Severity:** Info
**File:** hooks/stop:44 vs pre-change-gate:29
**Finding:** Both resolve to the same path ($HOME/.beads when BEADS_DIR is empty). Functionally equivalent.
**Conditions:** N/A — consistent.
**Current test coverage:** None direct, but tests exercise full paths.

### F24: pre-change-gate text fallback awk parsing
**Severity:** Fragile
**File:** hooks/pre-change-gate:58-59
**Finding:** `awk 'NR>1 && NF>0{print $1; exit}'` assumes task ID is first field after a header line. Breaks if bd changes text output format. Mitigated by JSON-first approach.
**Conditions:** bd changes text format AND doesn't support --json.
**Current test coverage:** Tests mock the output format.
