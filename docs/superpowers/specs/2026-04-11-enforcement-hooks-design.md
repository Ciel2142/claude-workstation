# Enforcement Hooks Design Spec

**Date:** 2026-04-11
**Task:** claude-workstation-1fzl
**Status:** Draft

## Problem

All workflow enforcement in claude-workstation is advisory. Pre-change-gate warns but never blocks (`exit 0`). CLAUDE.md has rules. Superpowers defines rigid skills. But nothing prevents Claude from rationalizing past any of it.

**Evidence:** In the `postman` project, a session executed 14 plan tasks with:
- Only 1 top-level bead created (no sub-task beads for 14 tasks)
- Zero code reviews (except partial task 1)
- No verification-before-completion
- No finishing-a-development-branch
- Caveman mode ignored entirely

The agent had complete knowledge — 4 beads memories with all workflow rules, plugin CLAUDE.md injected via session-start, global rules from `~/.claude/rules/`. It "prioritized throughput over process."

## Solution: Dual-Layer Enforcement

Two enforcement mechanisms covering each other's gaps:

1. **Hard-blocking hooks** — `exit 2` prevents tool execution when workflow steps are missing
2. **Subagent protocol** — mandatory bead tracking rules injected into every subagent prompt, validated by controller on return

## Milestone Format

Append-log lines in beads notes. No timestamps (beads tracks `Updated:` already).

### Format

```
[M] <phase> <freetext detail>
```

### Valid Phases (ordered — each requires all predecessors)

| Phase | Meaning | Prerequisite |
|-------|---------|-------------|
| `task:created` | Sub-task bead exists | — |
| `task:claimed` | Work started | `task:created` |
| `tdd:red` | Failing test written | `task:claimed` |
| `tdd:red-verified` | Confirmed test fails correctly | `tdd:red` |
| `tdd:green` | Implementation passes test | `tdd:red-verified` |
| `tdd:green-verified` | All tests pass | `tdd:green` |
| `tdd:refactor` | Cleanup complete | `tdd:green-verified` |
| `review:spec` | Spec compliance passed | `tdd:refactor` |
| `review:quality` | Code quality review passed | `review:spec` |
| `verified` | Verification-before-completion done | `review:quality` |

### Writing Milestones

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] tdd:red wrote failing test for auth middleware"
```

### Validation

```bash
grep -c '^\[M\] tdd:red-verified' <<< "$NOTES"
```

### State Transition Validation

Hook validates ordering — can't claim `tdd:green` without `tdd:red-verified`. If gap found, blocks with specific message:

```
Phase tdd:green present but tdd:red-verified missing. Complete RED verification first.
```

### Repeated TDD Cycles

Multiple red-green cycles allowed (iterative implementation). Append log handles naturally:

```
[M] tdd:red first test: auth header parsing
[M] tdd:red-verified fails with "missing auth header"
[M] tdd:green parsing works
[M] tdd:green-verified all pass
[M] tdd:red second test: token expiry
[M] tdd:red-verified fails with "token not validated"
[M] tdd:green expiry check works
[M] tdd:green-verified all pass
[M] tdd:refactor extracted shared auth helpers
```

Hook checks: at least one complete cycle (red → red-verified → green → green-verified) AND `tdd:refactor` present.

### Special Transitions

| Transition | When |
|-----------|------|
| `review:spec:blocked` → back to `tdd:red` | Spec review finds missing behavior |
| `review:quality:blocked` → back to `tdd:refactor` | Quality review finds issues |
| `paused <reason>` | Session end, context pressure — Stop hook accepts |

## Hook Enforcement Points

### 1. Milestone Gate (PreToolUse — Edit|Write)

**Action:** `exit 2` block unless active sub-task bead exists with `[M] task:claimed`.

**File exemptions** (configured in `templates/gate-exemptions.txt`):

| Pattern | Reason |
|---------|--------|
| `docs/**` | Documentation |
| `*.md` | Markdown files |
| `.beads/**` | Beads internal state |
| `docs/superpowers/**` | Specs and plans |
| `.claude/**` | Claude config |
| `**/testdata/**`, `**/*_test.*`, `**/*_test_*`, `**/test/**` | Test fixtures |

Test files are exempt from the gate (must write tests before production code in TDD) but milestone tracking is still expected — enforced by controller verification, not hook.

Hook extracts `file_path` from tool input JSON, matches against exempt patterns. Exempt → `exit 0` silently. Not exempt → full gate check.

**Always outputs 1-line status** even when passing:

```
✓ task:postman-abc | phase:tdd:green | next: verify all tests pass
```

### 2. Agent Gate (PreToolUse — Agent)

**Action:** `exit 2` block unless subagent prompt contains `BEAD-PROTOCOL-v1` sentinel.

Hook reads stdin JSON, extracts `prompt` field, greps for sentinel. Missing → block with message listing which template to include.

**Exemptions:** Prompts containing `BEAD-EXEMPT:research` or `BEAD-EXEMPT:exploration` are allowed without protocol. But any subagent that touches files will hit the milestone gate independently.

### 3. Commit Gate (PreToolUse — Bash)

**Action:** `exit 2` on commands matching `git commit` unless active sub-task bead has `[M] review:quality`.

Hook reads Bash tool input JSON, extracts `command` field. Only triggers when command contains `git commit` (regex: `\bgit\s+commit\b`). Other Bash usage unaffected. Does NOT trigger on `git add`, `git push`, `git status`, etc.

### 4. Stop Gate (Stop)

**Action:** `exit 2` unless ALL in-progress beads have either `[M] verified` or `[M] paused <reason>`.

### 5. Mid-Session Reminder (PostToolUse — Bash|Edit|Write)

**Action:** Advisory, never blocks. Three behaviors:

- **Edit counter:** Tracks edits since last milestone update. After 5+ edits with no `[M]` progression → warning: `"⚠ N edits since last milestone. Current phase: X. Update milestone or explain."`
- **Subagent dispatch detection:** If Bash output matches subagent patterns → reminder about mandatory bead tracking protocol.
- **Always echoes current state** on Edit/Write (same status line as milestone gate).

### 6. PreCompact State Dump

Before context compaction, inject full workflow state:

```
WORKFLOW STATE:
  Parent: postman-xyz (in_progress)
  Sub-tasks: 3/14 complete
  Current: postman-abc phase:tdd:refactor
  Next unblocked: postman-def
  RULE: each sub-task needs full [M] progression before close
```

### Bypass Mechanisms

- `[M] paused <reason>` — explicit pause, Stop hook accepts
- Env var `BEADS_GATE_BYPASS=1` — user emergency override. Hook warns but allows.
- File exemptions in `templates/gate-exemptions.txt`

## Subagent Protocol

### Problem

Subagents don't inherit hooks. PreToolUse gates don't fire in subagent context. Enforcement comes from prompt injection + controller verification.

### Template Files

Stored in `templates/`:

| File | Agent Type |
|------|-----------|
| `protocol-base.md` | Shared rules all agents get |
| `protocol-implementer.md` | Full TDD milestone chain |
| `protocol-reviewer.md` | Findings + side-quest creation |
| `protocol-planner.md` | Plan milestones |
| `protocol-build-fixer.md` | Fix milestones |

Each template ends with sentinel:

```
<!-- BEAD-PROTOCOL-v1:<type> -->
```

Agent gate hook greps for `BEAD-PROTOCOL-v1` — one regex covers all types.

### Implementer Protocol

```
Before ANY code changes:
  bd create --title="<task-description>" --type=task -p 2
  bd dep add <new-id> <parent-id> --type parent-child
  bd update <new-id> --claim

During TDD — update after EACH phase:
  bash bd-notes-append <id> "[M] tdd:red <detail>"
  bash bd-notes-append <id> "[M] tdd:red-verified <detail>"
  bash bd-notes-append <id> "[M] tdd:green <detail>"
  bash bd-notes-append <id> "[M] tdd:green-verified <detail>"
  bash bd-notes-append <id> "[M] tdd:refactor <detail>"

After completion:
  bd close <id>

SKIP NONE OF THESE. Your work will be rejected if milestones are missing.
```

### Reviewer Protocol

```
Track your review:
  bash bd-notes-append <parent-task-id> "[M] review:<type>:started reviewing <scope>"

For EACH finding:
  bash bd-notes-append <parent-task-id> "[M] review:<type>:finding:<severity> <description>"

For CRITICAL or HIGH findings — create side-quest:
  bd create --title="Found: <issue>" --type=bug -p <severity-priority>
  bd dep add <new-id> <parent-task-id> --type discovered-from

Verdict:
  bash bd-notes-append <parent-task-id> "[M] review:<type>:passed no blocking issues"
  OR
  bash bd-notes-append <parent-task-id> "[M] review:<type>:blocked <N> issues must fix"
```

Where `<type>` = `spec` | `quality` | `security`

### Planner Protocol

```
  bash bd-notes-append <task-id> "[M] plan:started analyzing requirements"
  bash bd-notes-append <task-id> "[M] plan:spec-written path/to/spec.md"
  bash bd-notes-append <task-id> "[M] plan:subtasks-created N sub-tasks linked"
  bash bd-notes-append <task-id> "[M] plan:completed"
```

### Build Fixer Protocol

```
  bash bd-notes-append <task-id> "[M] fix:started <error summary>"
  bash bd-notes-append <task-id> "[M] fix:diagnosed root cause: <cause>"
  bash bd-notes-append <task-id> "[M] fix:applied <what changed>"
  bash bd-notes-append <task-id> "[M] fix:verified build passes"
```

If fix reveals deeper issue → side-quest:

```
  bd create --title="Found: <underlying issue>" --type=bug
  bd dep add <new-id> <current-id> --type discovered-from
```

### Controller Protocol

Main agent tracks its own orchestration:

```
[M] dispatch:impl:<sub-task-id> dispatched implementer
[M] dispatch:review-spec:<sub-task-id> dispatched spec reviewer
[M] dispatch:review-quality:<sub-task-id> dispatched quality reviewer
[M] controller:milestone-check:<sub-task-id> verified milestones present
[M] controller:rejected:<sub-task-id> missing milestones, re-dispatching
```

### Controller Verification

After ANY subagent returns, controller MUST:

1. `bd show <sub-task-id>` — check expected milestones present
2. Verify side-quest beads created for any CRITICAL/HIGH findings
3. If missing → reject work, re-dispatch or fix
4. Only AFTER milestone validation → dispatch next reviewer

### Agent Type Bead Obligations

| Agent Type | Creates Own Bead? | Milestones | Side-Quest Obligation |
|-----------|-------------------|------------|----------------------|
| Implementer | Yes (sub-task) | Full TDD chain | If discovers bugs outside scope |
| Spec Reviewer | No (appends to parent) | review:spec:* | MUST for CRITICAL/HIGH findings |
| Quality Reviewer | No (appends to parent) | review:quality:* | MUST for CRITICAL/HIGH findings |
| Security Reviewer | No (appends to parent) | review:security:* | MUST for CRITICAL/HIGH findings |
| Planner | No (appends to parent) | plan:* | If scope issues found |
| Build Fixer | No (appends to parent) | fix:* | If deeper issue found |
| Controller | No (appends to parent) | dispatch:*, controller:* | — |

## Performance & Caching

### Cache Structure

```
$XDG_RUNTIME_DIR/.beads-gate-<user>-<project-hash>/
├── active-task          ← current sub-task ID
├── milestones-<task-id> ← cached milestone lines
└── edit-counter         ← edits since last milestone
```

### Cache Lifecycle

| Event | Action |
|-------|--------|
| `bd-notes-append` called | Invalidate `milestones-<task-id>`, reset `edit-counter` |
| `bd update --claim` | Update `active-task` |
| `bd close` | Clear `active-task`, clear `milestones-<task-id>` |
| Cache file age > 60s | Stale — re-fetch from `bd show` |
| Session start | Clear entire cache dir |

### Performance

| Path | Latency |
|------|---------|
| Hot (cached) | ~1ms — local file read + grep |
| Cold (cache miss) | ~60-210ms — `bd show` network call, write cache, grep |

### Failure Mode

If `bd show` fails (server down, timeout): warn but do NOT block. Message:

```
⚠ Beads server unreachable — milestone gate bypassed. Re-run bd show <id> when server recovers.
```

### bd-notes-append Cache Integration

After successful `bd update`, also write to local cache:

```bash
echo "$NEW_LINE" >> "${CACHE_DIR}/milestones-${TASK_ID}"
echo 0 > "${CACHE_DIR}/edit-counter"
```

## Files

### New Files

| File | Purpose |
|------|---------|
| `hooks/agent-gate` | PreToolUse — blocks Agent dispatch without protocol sentinel |
| `hooks/milestone-gate` | PreToolUse — blocks Edit/Write without active sub-task + milestone |
| `hooks/commit-gate` | PreToolUse — blocks git commit without review:quality |
| `hooks/stop-gate` | Stop — blocks without verified/paused on all in-progress |
| `hooks/mid-session-reminder` | PostToolUse — edit counter, periodic reminders, state echo |
| `hooks/cache-utils.sh` | Shared cache read/write/invalidate functions |
| `templates/protocol-base.md` | Shared bead rules all subagents get |
| `templates/protocol-implementer.md` | Implementer: full TDD milestone chain |
| `templates/protocol-reviewer.md` | Reviewer: findings + side-quest creation |
| `templates/protocol-planner.md` | Planner: plan milestones |
| `templates/protocol-build-fixer.md` | Build fixer: fix milestones |
| `templates/gate-exemptions.txt` | Glob patterns exempt from Edit/Write gate |

### Modified Files

| File | Change |
|------|--------|
| `hooks/hooks.json` | Add new hook entries for all gates + reminder |
| `hooks/pre-change-gate` | Retire — replaced by milestone-gate |
| `hooks/bd-notes-append` | Add cache invalidation + write-through |
| `hooks/session-start` | Add echo workflow reminder |
| `hooks/stop` | Integrate stop-gate or replace |
| `CLAUDE.md` | Add milestone format reference + subagent protocol mandate |
| `skills/workflow/SKILL.md` | Add milestone tracking + subagent protocol sections |
| `skills/start/SKILL.md` | Ensure sub-task creation in flow |

### hooks.json Additions

```json
{
  "PreToolUse": [
    {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/milestone-gate\""}]},
    {"matcher": "Agent", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agent-gate\""}]},
    {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/commit-gate\""}]}
  ],
  "PostToolUse": [
    {"matcher": "Bash|Edit|Write", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/mid-session-reminder\""}]}
  ],
  "Stop": [
    {"matcher": "", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/stop-gate\""}]}
  ]
}
```

### Not Modified (upstream)

| File | Reason |
|------|--------|
| Superpowers skills | Upstream plugin, not controlled by us |
| Beads core | Upstream plugin, work with `bd` CLI as-is |
