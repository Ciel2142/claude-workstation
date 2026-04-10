# Claude Workstation

A Claude Code plugin that restores your full development environment from a single install.

## What's Included

- **Unified Workflow** -- On-demand skill connecting Beads, Superpowers, and ECC (`/claude-workstation:workflow`)
- **Lean Auto-Injection** -- SessionStart hook delivers ~30-line cheatsheet (down from ~200 lines)
- **Task Kickoff** -- `/start` creates a beads task and routes to brainstorming or planning
- **Session Hooks** -- SessionStart, PreToolUse, and Stop hooks for beads enforcement
- **Test Suite** -- Config validation + dry-run scenarios

## Install

### 1. Install Required Plugins

Install each plugin from the Claude Code marketplace (`/install-plugin`):

| Plugin | Marketplace name |
|---|---|
| [Beads](https://github.com/steveyegge/beads) | `beads-marketplace` |
| [Superpowers](https://github.com/obra/superpowers-marketplace) | `superpowers-marketplace` |
| [ECC](https://github.com/affaan-m/everything-claude-code) | `everything-claude-code` |

### 2. Run Bootstrap Script

```bash
bash install.sh
```

This runs the ECC installer (from the locally cached plugin) and the Beads installer.

## Dependencies

Required plugins:

| Plugin | Marketplace | Purpose |
|---|---|---|
| [Beads](https://github.com/steveyegge/beads) | beads-marketplace | Dolt-powered issue tracker with dependencies, milestones, and persistent task state across sessions |
| [Superpowers](https://github.com/obra/superpowers-marketplace) | superpowers-marketplace | Development process skills — brainstorming, planning, TDD, code review, verification, debugging |
| [ECC](https://github.com/affaan-m/everything-claude-code) | everything-claude-code | Language-specific and domain-specific skills, agents, patterns, and coding standards |

## Commands & Skills

| Command | What it does |
|---|---|
| `/claude-workstation:start` | Create beads task and choose workflow entry (brainstorm or plan) |
| `/claude-workstation:workflow` | Full workflow reference (on-demand) |

### `/start` — Begin New Work

```bash
/claude-workstation:start "Fix the login validation bug"
# → Creates task → "Brainstorm or plan?"

/claude-workstation:start "Design a new notification system"
# → Creates task → "Brainstorm or plan?"

/claude-workstation:start --side-quest "Found: tokens aren't rotated"
# → Detects side-quest → creates bug → links to current task → parks it
```

## Workflow

See `/claude-workstation:workflow` for the full reference, or the cheatsheet in CLAUDE.md for the quick version.

## Hooks

| Hook | When | What |
|---|---|---|
| **SessionStart** | Session begins | Injects lean cheatsheet (~30 lines) via `additionalContext` + auto-inits beads |
| **PreToolUse** | Before Edit/Write | Warns if no active beads task exists (pre-change-gate) |
| **Stop** | Session ends | Warns about untracked commits, lists in-progress tasks |

## Project Structure

```
claude-workstation/
├── install.sh                # Bootstrap ECC + Beads with one command
├── skills/
│   ├── start/SKILL.md         # /start -- task creation & workflow entry
│   └── workflow/SKILL.md      # /workflow -- full workflow reference (on-demand)
├── hooks/
│   ├── hooks.json             # SessionStart + PreToolUse + Stop hooks
│   ├── bd-notes-append        # Safe notes append wrapper
│   ├── session-start          # Cheatsheet injection script
│   ├── pre-change-gate        # Beads task enforcement before file edits
│   └── stop                   # Session-end reminder script
├── tests/
│   ├── validate-config.sh     # Config validation
│   ├── test-behaviors.sh      # Behavioral tests for hooks
│   ├── lib.sh                 # Cross-platform test helpers
│   └── scenarios/             # Workflow dry-run scenario scripts
├── CLAUDE.md
└── README.md
```

## License

MIT
