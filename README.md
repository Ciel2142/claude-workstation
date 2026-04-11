# Claude Workstation

A Claude Code plugin that restores your full development environment from a single install.

## What's Included

- **Unified Workflow** -- On-demand skill connecting Beads, Superpowers, and ECC (`/claude-workstation:workflow`)
- **Lean Auto-Injection** -- SessionStart hook delivers ~30-line cheatsheet (down from ~200 lines)
- **Task Kickoff** -- `bd create` + brainstorm or plan (no separate skill needed)
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

Optional plugins:

| Plugin | Marketplace | Purpose |
|---|---|---|
| [Caveman](https://github.com/JuliusBrussee/caveman) | caveman | Token-saving compression modes (lite, full, ultra). See Caveman Mode Rules in CLAUDE.md |

## Commands & Skills

| Command | What it does |
|---|---|
| `/claude-workstation:workflow` | Full workflow reference (on-demand) |
| `/claude-workstation:agent-roles` | Subagent role registry -- maps agent purpose to protocol template |
| `/claude-workstation:task-scaffolder` | Read plan, create beads tasks with dependency graph |
| `/claude-workstation:orchestrator` | Automated impl→review→fix cycle (rigid protocol) |

## Workflow

See `/claude-workstation:workflow` for the full reference, or the cheatsheet in CLAUDE.md for the quick version.

## Hooks

| Hook | When | What |
|---|---|---|
| **SessionStart** | Session begins | Injects lean cheatsheet via `additionalContext` + auto-inits beads |
| **PreCompact** | Before compaction | Injects in-progress task state into context |
| **PreToolUse: Edit/Write** | Before file changes | Blocks unless active sub-task with `[M] task:claimed` (milestone-gate) |
| **PreToolUse: Agent** | Before subagent dispatch | Blocks unless prompt contains protocol template or `BEAD-ROLE:default` (agent-gate) |
| **PreToolUse: Bash** | Before bash commands | Blocks `git commit` unless `[M] review:quality` present (commit-gate) |
| **PostToolUse: Edit/Write** | After file changes | Echoes current task/phase status (mid-session-reminder) |
| **Stop** | Session ends | Blocks unless all tasks have `[M] verified` or `[M] paused` (stop-gate) + warns about untracked commits (stop) |

## Project Structure

```
claude-workstation/
├── install.sh                # Bootstrap ECC + Beads with one command
├── skills/
│   ├── agent-roles/SKILL.md   # /agent-roles -- subagent role registry
│   ├── orchestrator/SKILL.md  # /orchestrator -- automated impl→review→fix cycle
│   ├── task-scaffolder/SKILL.md # /task-scaffolder -- plan-to-tasks transformer
│   └── workflow/SKILL.md      # /workflow -- full workflow reference (on-demand)
├── hooks/
│   ├── hooks.json             # Hook event → script wiring
│   ├── cache-utils.sh         # Shared utility functions for hooks
│   ├── bd-notes-append        # Safe notes append wrapper
│   ├── session-start          # Cheatsheet injection + beads auto-init
│   ├── milestone-gate         # Blocks Edit/Write without active claimed sub-task
│   ├── agent-gate             # Blocks Agent dispatch without role sentinel
│   ├── commit-gate            # Blocks git commit without review:quality milestone
│   ├── stop-gate              # Blocks session end without verified/paused milestones
│   ├── mid-session-reminder   # Echoes task/phase status after edits
│   ├── precompact-state       # Injects workflow state before compaction
│   └── stop                   # Session-end advisory warnings
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
