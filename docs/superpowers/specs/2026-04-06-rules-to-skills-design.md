# Rules-to-Skills: Hook-Injected Context + On-Demand Reference Skills

**Epic:** claude-workstation-0av
**Date:** 2026-04-06
**Status:** Approved

**Goal:** Eliminate the setup rule-copying step by injecting essential rules via a SessionStart hook and converting reference rules to on-demand skills. Save ~14KB of always-on context per session.

**Scope:** Plugin architecture change. Affects hooks, skills, contexts, setup, tests, and documentation. No changes to the rule content itself — only how it's delivered.

---

## Problem

Claude Code plugins cannot declare rules natively (issue #14200). The current workaround copies 8 rule files (~15KB) to `~/.claude/rules/common/` during setup, making them always-on in every session. This has three problems:

1. **Context waste** — Reference material (verification template, milestone format, spike protocol) is loaded every session but only used during specific workflow phases.
2. **Stale copies** — Plugin updates don't sync rules. Users must re-run `/setup`.
3. **No lifecycle** — Disabling the plugin leaves orphaned rules. Uninstalling doesn't clean up.

---

## Solution: Three-Tier Context Model

### Tier 1: Auto (default, zero setup)

A SessionStart hook injects `contexts/workflow.md` (~3KB) via the `hookSpecificOutput.additionalContext` JSON field (same pattern as the superpowers plugin). This document contains the condensed unified-workflow decision tables and plugin-routing lanes — the behavioral contract that must always be active.

The hook script resolves its own directory to find the plugin root — no hardcoded cache paths, no version numbers.

### Tier 2: Alias (manual launch)

A `claude-workflow` shell alias launches Claude with the workflow context as `--system-prompt`. Same content as the hook, different delivery. Added alongside existing `claude-dev`, `claude-research`, `claude-review` aliases.

### Tier 3: Install (explicit opt-in)

A new `/install-rules` skill copies all `rules/common/*.md` files to `~/.claude/rules/common/`. Same behavior as the old setup Step 3, but opt-in. For users who want traditional always-on rules despite the context cost.

---

## Changes

### New Files

#### `contexts/workflow.md` (~3KB)

Condensed version of unified-workflow + plugin-routing + research-first checklist. Contains:

- Task sizing table (trivial/small/medium+/bug)
- Tier flow summaries (one line each, not full step-by-step)
- Plugin routing lanes (Beads/Superpowers/ECC)
- Hard rules (beads-first, no code without test, no completion without verification)
- Escalation rules
- Research & Reuse checklist (from development-workflow.md)

Does NOT contain: full step-by-step flows (that's `/help`), reference formats (that's skills), examples, extended explanations.

#### `hooks/session-start`

Bash script (extensionless, following superpowers convention for cross-platform compatibility).

1. Resolves plugin root from script location
2. Runs `bash .beads/hooks/configure-server.sh 2>/dev/null || true` (moved from hooks.json)
3. Reads `contexts/workflow.md`
4. Outputs JSON: `{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "<escaped content>"}}`

#### 5 Reference Skills

Each wraps an existing rule file as a plugin-native skill with YAML frontmatter:

| Skill directory | Source rule | Trigger description |
|---|---|---|
| `skills/debugging-protocol/` | `rules/common/debugging.md` | When starting bug work or debugging |
| `skills/beads-milestones/` | `rules/common/beads-milestones.md` | When updating beads milestone notes |
| `skills/spike-phase/` | `rules/common/spike-phase.md` | During Medium+ spike phase |
| `skills/scope-health/` | `rules/common/scope-health.md` | At scope health check intervals |
| `skills/verification-template/` | `rules/common/verification-template.md` | During verification phase |

Content is the full rule text (not condensed). These are reference material that should be available on demand but not loaded every session.

#### `skills/install-rules/SKILL.md`

Opt-in skill that copies `rules/common/*.md` to `~/.claude/rules/common/`. Idempotent (skip if destination newer). Warns about context cost (~15KB always-on on top of the ~3KB hook).

### Modified Files

#### `hooks/hooks.json`

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start\""
      }]
    }],
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "... (unchanged Stop hook)"
      }]
    }]
  }
}
```

Changes:
- SessionStart: replace inline `configure-server.sh + bd prime` with the new `session-start` script
- PreCompact: already removed (beads plugin handles this)
- Stop: unchanged

#### `skills/setup/SKILL.md`

- Remove Step 3 (copy rules to ~/.claude/rules/) — no longer default
- Remove Step 6 (check ECC rules) — not our concern
- Add note: "Rules are auto-injected via hook. Run `/install-rules` to opt into always-on global rules."
- Add `claude-workflow` alias to Step 5 (shell aliases)

#### `skills/test/SKILL.md` and `tests/validate-config.sh`

- Remove checks for rule files in `~/.claude/rules/common/` — no longer required
- Add: `contexts/workflow.md` exists in plugin
- Add: `hooks/session-start` exists and is executable in plugin
- Keep content completeness checks, run against plugin source files

#### `profiles/aliases.sh`

Add `claude-workflow` alias alongside existing three.

#### `CLAUDE.md`

Update to mention three-tier model and `/install-rules` opt-in.

#### `README.md`

- Update architecture description (three-tier model)
- Update hooks table (new session-start script)
- Update project structure diagram
- Update setup instructions

### Deleted Files

- `rules/context7.md` (root-level, not in `common/`) — redundant with context7 MCP server's own injected instructions

### Unchanged Files

- `rules/common/*.md` — all source files remain as-is (source of truth)
- `commands/help.md` — still the detailed playbook (on-demand command)
- `skills/start/SKILL.md` — routing logic unchanged
- `skills/resume/SKILL.md` — position detection unchanged
- `.claude-plugin/plugin.json` — skills auto-discovered, no manifest change needed

---

## Context Budget Impact

| Component | Before | After |
|---|---|---|
| Unified-workflow rule | 3.9KB always-on | ~1.5KB in workflow.md (condensed) |
| Plugin-routing rule | 0.9KB always-on | ~0.5KB in workflow.md (condensed) |
| Development-workflow rule | 1.1KB always-on | ~0.5KB in workflow.md (research checklist) |
| Debugging rule | 1.2KB always-on | 0 (on-demand skill) |
| Beads-milestones rule | 2.7KB always-on | 0 (on-demand skill) |
| Spike-phase rule | 2.4KB always-on | 0 (on-demand skill) |
| Scope-health rule | 1.7KB always-on | 0 (on-demand skill) |
| Verification-template rule | 1.0KB always-on | 0 (on-demand skill) |
| Context7 rule | 1.8KB always-on | 0 (deleted, redundant) |
| **Total** | **~16.7KB** | **~3KB** |

**Savings: ~13.7KB per session** from claude-workstation rules alone.

(ECC's ~10KB of rules remain unchanged — that's upstream.)

---

## Implementation Batches

### Batch A — Core (independent tasks)

1. Create `contexts/workflow.md`
2. Create `hooks/session-start` script
3. Create 5 reference skills (can be parallel)
4. Create `skills/install-rules/SKILL.md`

### Batch B — Integration (depends on Batch A)

5. Modify `hooks/hooks.json` to use new session-start script
6. Modify `skills/setup/SKILL.md` (remove rule copy, add notes)
7. Modify `skills/test/SKILL.md` and `tests/validate-config.sh`

### Batch C — Documentation (depends on Batch B)

8. Delete `rules/context7.md`
9. Update `profiles/aliases.sh`, `CLAUDE.md`, `README.md`

---

## Decisions

1. **Hook pattern:** Superpowers-style JSON (`hookSpecificOutput.additionalContext`) over raw stdout
2. **Context scope:** Lean (~3KB) — decision tables and routing only, no reference material
3. **Rule files:** Kept as source of truth in `rules/common/`, not deleted
4. **Context7 rule:** Deleted — MCP server injects own instructions
5. **ECC rules:** Out of scope — upstream concern
6. **Install-rules:** Opt-in skill, not default behavior
7. **configure-server.sh:** Moved into session-start script, not removed

## What This Does NOT Change

- Rule content — no rewrites, same text
- Workflow routing logic in /start and /resume
- The /help command (detailed playbook)
- Beads plugin's own SessionStart hook
- ECC's rules or installation approach
