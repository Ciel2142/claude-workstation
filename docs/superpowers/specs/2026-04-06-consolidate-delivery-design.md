# Consolidate Context Delivery: Remove Rules & MCP

**Date:** 2026-04-06
**Epic:** claude-workstation-leh
**Tier:** Medium+

## Problem

The plugin delivers workflow context through three redundant layers:

1. **SessionStart hook** (`contexts/workflow.md`, 2.3 KB) — condensed workflow context
2. **`rules/common/`** (8 files, ~15 KB) — installed to `~/.claude/rules/common/` via `/install-rules`
3. **On-demand skills** (5 skills) — phase-specific protocols

Three rules duplicate the hook context. Five rules duplicate on-demand skills. Two sections (spec amendments, sub-task micro-tiers) exist only in `unified-workflow.md`.

Additionally, `.mcp.json` ships context7 and sequential-thinking servers that are already provided by their own plugins (Context7 via claude-plugins-official, sequential-thinking via ECC). `mcp-configs/optional-servers.json` is an unused template.

## Solution

Consolidate to hook + skills delivery only.

### 1. Add missing content to `contexts/workflow.md`

Add two sections between "Hard Rules" and "Plugin Routing":

- **Spec Amendments** — minor (agent self-approves) vs material (requires human approval), with log format
- **Sub-task Micro-tiers** — micro-trivial/micro-small/micro-complex ceremony levels, micro-TDD definition, batch review cadence

Source: `rules/common/unified-workflow.md` lines 28-73. Condensed to remove the verbose material amendment template block — keep intent, criteria, and log format.

### 2. Delete redundant files

| Path | Reason |
|---|---|
| `rules/common/` (entire directory) | 3 files duplicate hook, 5 duplicate skills |
| `skills/install-rules/` | No rules to install |
| `.mcp.json` | context7 and sequential-thinking provided by own plugins |
| `mcp-configs/` (entire directory) | Unused optional template |

### 3. Update references in active files

| File | Change |
|---|---|
| `CLAUDE.md` | Replace "Rules Delivery" section with "Context Delivery" — remove install-rules and workflow alias references |
| `README.md` | Remove `/install-rules` from commands table, remove "Rules" section, remove deleted paths from project structure, update "What's Included" |
| `skills/setup/SKILL.md` | Remove "Workflow Rules" section referencing `/install-rules` |
| `tests/validate-config.sh` | Remove `install-rules` from skill checks in sections 3, 8, 9 |

Historical docs (`docs/superpowers/specs/`, `docs/superpowers/plans/`) are untouched — they are design records.

### 4. Global cleanup

Remove 8 files from `~/.claude/rules/common/` that were previously installed by `/install-rules`:
unified-workflow.md, plugin-routing.md, development-workflow.md, verification-template.md, beads-milestones.md, debugging.md, spike-phase.md, scope-health.md.

## Result

- Plugin always-on context: ~5.2 KB (hook ~4 KB + CLAUDE.md ~1.2 KB), down from ~18.5 KB
- On-demand skills: unchanged (5 phase-specific protocols)
- No content lost — spec amendments and micro-tiers move to hook context
- No MCP server duplication
