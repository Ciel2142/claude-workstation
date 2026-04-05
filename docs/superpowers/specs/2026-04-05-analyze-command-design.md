# `/claude-workstation:analyze` — Auto-Tier Assessment & Workflow Routing

*Design spec — 2026-04-05*
*Epic: claude-workstation-l4i*

## Overview

A skill that takes a task description, automatically assesses its tier (Trivial/Small/Medium+), creates the appropriate beads task, and invokes the first workflow skill for that tier. One command replaces the manual sequence of: read the workflow reference, decide the tier, create the right beads task type, then remember which skill to invoke first.

## Scope

| Component | Description |
|---|---|
| `/analyze` skill | Core skill at `skills/analyze/SKILL.md` |
| SessionStart hook | `bd prime` at session start |
| PreCompact hook | `bd prime` before context compaction |
| Verification template | Standardized verification output format |
| Setup updates | Copy new rule file during `/claude-workstation:setup` |

### Out of Scope

- Codebase pre-scan (brainstorming handles this for Medium+)
- Interactive borderline questions (borderline bumps up automatically)
- Changes to existing Stop hook or `/workflow` command

---

## 1. `/analyze` Skill — Core Flow

### Invocation

```
/claude-workstation:analyze "Add rate limiting to all API endpoints"
/claude-workstation:analyze -p 0 "Critical production outage"
/claude-workstation:analyze --side-quest "Found: tokens aren't rotated"
```

### Flow

```
1. PARSE        Extract description and flags from arguments
2. SCORE        Run weighted scoring matrix against description
3. ASSESS       Map score to tier (borderline bumps up)
4. CREATE       bd create with inferred type and priority
5. ROUTE        Auto-invoke first skill for that tier
```

### Routing Table

| Tier | Task Type | First Skill | What Happens |
|---|---|---|---|
| Trivial | `task` | None | Prints "Go fix it" + verification reminder |
| Small | `task` | `superpowers:test-driven-development` | TDD cycle begins immediately |
| Medium+ | `epic` | `superpowers:brainstorming` | Brainstorming begins immediately |

### Output Format

```
:bar_chart: Analysis: "Add rate limiting to all API endpoints"
   Type: feature | Scope: API, auth, infrastructure (3 domains)
   Score: 0.72 -> Medium+

   Created: claude-workstation-x7k (epic, P1)
   -> Starting: /superpowers:brainstorming
```

For Trivial tasks:

```
:bar_chart: Analysis: "Fix typo in README"
   Type: docs | Scope: config (1 domain)
   Score: 0.10 -> Trivial

   Created: claude-workstation-m2p (task, P3)
   -> Go fix it. Then verify and bd close claude-workstation-m2p.
```

---

## 2. Scoring Matrix

Six dimensions, each scored 0.0-1.0, then weighted and summed.

### Dimensions

| Dimension | Weight | Scoring |
|---|---|---|
| **task_type** | 0.20 | Signal words map to type and base score. `fix/bug/broken/error/crash` = bug (0.3). `add/create/implement/new` = feature (0.5). `refactor/rename/move/clean` = refactor (0.4). `design/system/migrate/architecture` = architecture (0.9). `docs/readme/config/typo/comment/format` = docs (0.1). |
| **scope_keywords** | 0.25 | Breadth signals. `all/every/across/entire/global` = 1.0. `most/many/several` = 0.7. No breadth words = 0.2. |
| **domain_count** | 0.25 | Count distinct domains mentioned: API, database, auth, frontend, backend, CI/CD, infrastructure, testing, security, config. 1 domain = 0.2, 2 = 0.5, 3+ = 1.0. |
| **change_signal** | 0.15 | Magnitude words. `typo/tweak/bump/rename` = 0.1. `update/improve/enhance` = 0.4. `new system/new component/rewrite/overhaul` = 1.0. |
| **complexity_markers** | 0.05 | `step by step/multiple phases/depends on/coordination` = 1.0. None = 0.0. |
| **forced_escalation** | 0.10 | Binary. Security, architecture, migration, or "new system" present = 1.0. Otherwise 0.0. |

### Tier Mapping

| Score | Tier |
|---|---|
| < 0.25 | Trivial |
| 0.25 - 0.39 | Small |
| 0.40 - 0.50 | Borderline -> bump to Medium+ |
| > 0.50 | Medium+ |

### Forced Escalation Override

- If `forced_escalation` fires: minimum tier is Small (regardless of total score).
- If `forced_escalation` fires AND `domain_count` >= 3: minimum tier is Medium+.

### Claude Override

Claude has freedom to override the numerical score when context clearly warrants a different tier. The scoring matrix is a guide, not a cage. If the description says "fix the auth bug" but Claude knows auth spans 12 files in this project, bumping to Medium+ is correct.

---

## 3. Side-Quest Detection

### Triggers

A side-quest is detected when any of these are true:

- Description starts with "Found:" or "Discovered:"
- Explicit flag: `--side-quest`
- There is an active in-progress beads task AND the new description is unrelated to it (Claude judges relatedness)

### Behavior

Side-quests differ from normal `/analyze` flow:

1. Creates the task with `--type=bug` (default, overridable)
2. Auto-links with `discovered-from` dependency to the current in-progress task
3. Does NOT auto-invoke any skill
4. Reminds user to finish current work first

### Output

```
:bar_chart: Analysis: "Found: login tokens aren't being rotated"
   Detected: Side-quest (current task: claude-workstation-x7k)

   Created: claude-workstation-r3m (bug, P2)
   Linked: claude-workstation-r3m discovered-from claude-workstation-x7k
   -> Parked. Finish current task first, then bd ready.
```

---

## 4. Priority Assignment

### Auto-Inference

| Condition | Priority |
|---|---|
| Forced escalation fired (security, architecture) | P1 |
| Medium+ tier | P1 |
| Small tier | P2 |
| Trivial tier | P3 |
| Side-quest | P2 (default) |

### User Override

The `-p` flag overrides auto-inference:

```
/claude-workstation:analyze -p 0 "Critical production outage"
```

Priority levels: 0=critical, 1=high, 2=medium, 3=low, 4=backlog.

---

## 5. Hooks

### SessionStart

Runs `bd prime` at the start of every session so active tasks, epics, and ready work are immediately visible.

```json
"SessionStart": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "bd prime 2>/dev/null || true"
      }
    ]
  }
]
```

Graceful no-op if beads isn't initialized.

### PreCompact

Runs `bd prime` before context compaction so beads state survives memory compression in long sessions.

```json
"PreCompact": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "bd prime 2>/dev/null || true"
      }
    ]
  }
]
```

### Stop (Existing)

No changes. The existing Stop hook already checks for untracked commits and in-progress tasks.

### File Location

All hooks live in `hooks/hooks.json`. The setup skill copies this to the project or user-level hooks configuration.

---

## 6. Verification Output Template

### Purpose

Standardize what "verification" means so `/superpowers:verification-before-completion` produces consistent, auditable output.

### Template

```
## Verification: <beads-task-id>
- Tests:  <status> <count> passed, <count> failed (exit <code>)
- Build:  <status> <message> (exit <code>)
- Lint:   <status> <message> (exit <code>)
- Type:   <status> <message> (exit <code>)
- Manual: <status> <description of what was checked>
```

Status symbols:
- `pass` — check passed
- `fail` — check failed (BLOCKING)
- `skip` — skipped with reason

### Rules

1. Each line must include the actual exit code from the command run.
2. Skipped checks must state the reason: `- Lint: skip skipped (no linter configured)`
3. Failed checks block completion: `- Tests: fail 2 failed (exit 1) -- BLOCKING`
4. At least one check must pass. All-skipped is not valid verification.
5. The verification block gets appended to beads task notes via `bd update <id> --notes`.

### File Location

`rules/verification-template.md` — copied to `~/.claude/rules/common/` during setup.

---

## 7. Setup Updates

The `/claude-workstation:setup` skill needs these additions:

1. Copy `rules/verification-template.md` to `~/.claude/rules/common/verification-template.md`
2. The hooks.json already gets copied by existing setup — no additional step needed for new hooks

---

## 8. File Map

| File | Action | Purpose |
|---|---|---|
| `skills/analyze/SKILL.md` | Create | The analyze skill |
| `hooks/hooks.json` | Update | Add SessionStart and PreCompact hooks |
| `rules/verification-template.md` | Create | Verification output standard |
| `skills/setup/SKILL.md` | Update | Copy verification template during setup |
| `docs/superpowers/specs/2026-04-05-analyze-command-design.md` | Create | This spec |

---

## Design Decisions

1. **Skill, not command** — Skills support checklists, process flows, and hard gates. Commands are simpler but less structured.
2. **No codebase pre-scan** — Brainstorming already does "explore project context" for Medium+ tasks. Scanning in `/analyze` would duplicate work.
3. **Borderline bumps up, no question asked** — Erring toward more process is safer. Reduces friction by keeping the flow non-interactive.
4. **Claude override allowed** — The scoring matrix guides but doesn't cage. When context clearly warrants a different tier, Claude should override.
5. **Side-quest parks, doesn't start** — Side-quests are logged and linked but don't interrupt current work. This prevents the context-switching that derails agent sessions.
6. **Verification is a rule, not part of `/analyze`** — It applies globally to all tasks, not just those created by `/analyze`.

---

## Research Sources

- [template-bridge](https://github.com/maslennikov-ig/template-bridge) — Three-layer enforcement, PreCompact hook, side-quest protocol
- [LiteLLM complexity_router](https://github.com/BerriAI/litellm/pull/21789) — Weighted keyword scoring for tier classification
- [rjmurillo/ai-agents](https://deepwiki.com/rjmurillo/ai-agents/3.3-task-classification-and-routing) — Domain-count heuristic for task routing
- [tzachbon/claude-model-router-hook](https://github.com/tzachbon/claude-model-router-hook) — Pattern-match classification in Claude Code hooks
