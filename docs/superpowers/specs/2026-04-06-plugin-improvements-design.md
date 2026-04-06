# Plugin Improvements: Design Spec

Epic: claude-workstation-7l4

Four strategic improvements identified in post-audit analysis. All items are
independent and can be implemented in any order.

---

## 1. bd-notes-append wrapper

### Problem

`bd update --notes` replaces all previous notes. Every milestone update must
include all prior milestones cumulatively. If any update is partial, `/resume`
position detection breaks because earlier milestones are lost.

### Design

**File**: `hooks/bd-notes-append`

**Interface**:
```bash
bash "$PLUGIN_ROOT/hooks/bd-notes-append" <task-id> "key: value"
```

**Behavior**:
1. Read current notes from `bd show <id>` — extract everything after the
   `NOTES` header line until end of output (or next section header)
2. Append the new line to existing notes
3. Write the full cumulative string via `bd update <id> --notes "..."`
4. If current notes are empty (no NOTES section or blank), write the new line directly
5. Exit 0 on success, exit 1 on failure (bd not available, invalid task ID)

**Downstream changes**:
- `skills/beads-milestones/SKILL.md`: Replace all `bd update --notes`
  instructions with the wrapper. Remove cumulative pattern warnings.
- `skills/start/SKILL.md`: Update `bd update --notes "tier: ..."` to use wrapper.
- `skills/resume/SKILL.md`: No code changes (reads notes, doesn't write them).

---

## 2. Behavioral test scenarios

### Problem

155 tests validate config (file existence, JSON validity, hook output format).
Zero tests verify actual behavior: position detection, pre-change-gate logic,
bd-notes-append correctness, stop hook warning conditions.

### Design

**File**: `tests/test-behaviors.sh`

**Approach**: Mock `bd` by placing a fake script on PATH that returns canned
output. Call actual hook scripts. Assert on stdout content.

**Test matrix**:

| Category | Test | Input | Expected output |
|---|---|---|---|
| Position detection | start | notes = `tier: small` | position = start |
| Position detection | post-brainstorming | notes with `spec:` | position = post-brainstorming |
| Position detection | post-planning | notes with `plan:` | position = post-planning |
| Position detection | mid-implementation | notes with `completed:` | position = mid-implementation |
| Position detection | post-verification | notes with `verification:` | position = post-verification |
| Position detection | post-update-docs | notes with `docs-updated:` | position = post-update-docs |
| Pre-change-gate | no task | `bd list` empty | WARNING output |
| Pre-change-gate | task, no tier | `bd list` returns task, no `tier:` in show | tier WARNING |
| Pre-change-gate | task, has tier | `bd list` returns task, `tier:` present | empty output |
| bd-notes-append | empty notes | `bd show` has no notes | writes just new line |
| bd-notes-append | existing notes | `bd show` returns `tier: small` | writes both old + new |
| Stop hook | clean session | 0 commits, 0 tasks | no warning |
| Stop hook | tracked session | commits + closed tasks | no warning |
| Stop hook | untracked session | commits + 0 tasks any status | WARNING output |

**Position detection tests require extracting the matching logic.** Currently the
pattern matching lives only in resume/SKILL.md as instructions for Claude — not
as executable code. The behavioral tests will implement the matching algorithm in
bash and test it directly, serving as a reference implementation that the skill's
instructions must produce equivalent results to.

**Integration**: Add to `skills/test/SKILL.md` as a separate section after config
validation. Update skill description counts.

---

## 3. Medium+ ceremony simplification

### Problem

11 numbered steps in the Medium+ path. Spike, worktree, update-docs, and
finish-branch are situational but presented as required, creating compliance
fatigue.

### Design

**Files changed**: `commands/help.md`, `contexts/workflow.md`

**New Medium+ structure in help.md**:

```
Core flow (always):
  1. EPIC       bd create --type=epic
  2. BRAINSTORM superpowers:brainstorming
  3. PLAN       superpowers:writing-plans
  4. SUB-TASKS  Create sub-tasks with dependencies
  5. IMPLEMENT  bd ready -> claim -> TDD per micro-tier -> close
  6. VERIFY     superpowers:verification-before-completion
  7. CLOSE      bd close <epic-id>

Use when needed:
  - SPIKE        Before IMPLEMENT, when architecture assumptions are unverified
  - WORKTREE     Before IMPLEMENT, when isolating risk on a feature branch
  - UPDATE-DOCS  After VERIFY, when public API or project docs changed
  - FINISH       After VERIFY, when on a feature branch that needs merging
```

**Workflow.md tier table update**:
```
Medium+ flow: bd create -t epic -> brainstorm -> plan -> sub-tasks -> TDD ->
verify -> bd close (+ spike, worktree, update-docs, finish when applicable)
```

**Unchanged**: Sub-task micro-tiers, batch review cadence, spec amendments,
scope health checks. These are rules within IMPLEMENT, not separate steps.

---

## 4. /status skill

### Problem

After compaction or a break, users need orientation without action. `/resume`
loads context and auto-invokes skills. `/resume --dry` exists but runs the full
detection machinery and is verbose. No lightweight "where am I" command.

### Design

**File**: `skills/status/SKILL.md`

**Invocation**: `/claude-workstation:status`

**Output format**:
```
Active:     claude-workstation-abc -- "Add rate limiting" (medium+, in_progress)
Position:   mid-implementation (completed: 1,2,3)
Next ready: claude-workstation-def -- "Rate limit middleware"
Worktree:   /tmp/worktree-abc
Last commit: 2h ago -- "feat: add token bucket"

Suggested: /superpowers:test-driven-development
```

**Logic**:
1. `bd list --status=in_progress` — if empty, `bd list --status=open`
2. If nothing: "No active work. Use /claude-workstation:start to begin."
3. `bd show <id>` for notes, type, description
4. Detect position via milestone pattern matching (same as resume Step 4)
5. `bd ready` for next available task
6. `git worktree list` and `git log --oneline -1` for context
7. Map position to suggested skill (same routing table as resume Step 5)
8. Print. Stop. Never take action.

**Conditional fields**: Only show lines with values. No "Worktree: none".

**Downstream changes**:
- `README.md`: Add `/claude-workstation:status` to commands table
- `skills/test/SKILL.md`: Update skill count (9 -> 10)
- `tests/validate-config.sh`: Add status skill directory check

---

## Out of scope

- Changes to beads itself (bd append flag)
- Subagent-based test scenarios (too expensive, flaky)
- Tier scoring tests (judgment-based, not deterministic)
- Ralph loop integration
