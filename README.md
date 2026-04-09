# Claude Workstation

A Claude Code plugin that restores your full development environment from a single install.

## What's Included

- **Unified Workflow** -- On-demand skill connecting Beads, Superpowers, and ECC (`/claude-workstation:workflow`)
- **Lean Auto-Injection** -- SessionStart hook delivers ~30-line cheatsheet (down from ~200 lines)
- **Auto-Tier Assessment** -- `/start` evaluates task descriptions and routes to the right workflow
- **Context Profiles** -- `claude-dev`, `claude-research`, `claude-review` shell aliases
- **Session Hooks** -- SessionStart, PreToolUse, and Stop hooks for beads enforcement
- **Test Suite** -- Config validation + dry-run scenarios

## Install

Install prerequisites following their own documentation:
- [Beads](https://github.com/steveyegge/beads) -- `/plugin install beads@beads-marketplace`
- [Superpowers](https://github.com/obra/superpowers-marketplace) -- `/plugin install superpowers@superpowers-marketplace`
- [ECC](https://github.com/affaan-m/everything-claude-code) -- `/plugin install ecc@everything-claude-code`

Then install Claude Workstation:

```bash
/plugin marketplace add https://github.com/Ciel2142/claude-workstation
/plugin install claude-workstation@claude-workstation

# Validate:
/claude-workstation:test
```

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
| `/claude-workstation:start` | Auto-assess task tier, create beads task, start the right workflow |
| `/claude-workstation:workflow` | Full workflow reference (on-demand) |
| `/claude-workstation:test` | Validate configuration and run scenarios |

### `/start` — Begin New Work

```bash
/claude-workstation:start "Fix the login validation bug"
# → Assesses tier → Small → creates task → starts TDD

/claude-workstation:start "Design a new notification system"
# → Assesses tier → Medium+ → creates epic → starts brainstorming

/claude-workstation:start "Fix typo in README"
# → Assesses tier → Trivial → creates task → "Go fix it"

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

## Context Profiles

After setup, use these shell aliases:

```bash
claude-dev       # Code-first development mode
claude-research  # Exploration and investigation mode
claude-review    # Code review and quality analysis mode
```

Note: Workflow context is auto-injected via the SessionStart hook — no alias needed.

## Project Structure

```
claude-workstation/
├── skills/
│   ├── start/SKILL.md         # /start -- auto-tier assessment & workflow start
│   ├── workflow/SKILL.md      # /workflow -- full workflow reference (on-demand)
│   └── test/SKILL.md          # /test -- config validation
├── contexts/
│   ├── dev.md
│   ├── research.md
│   └── review.md
├── hooks/
│   ├── hooks.json             # SessionStart + PreToolUse + Stop hooks
│   ├── bd-notes-append        # Safe notes append wrapper
│   ├── session-start          # Cheatsheet injection script
│   ├── pre-change-gate        # Beads task enforcement before file edits
│   └── stop                   # Session-end reminder script
├── profiles/
│   └── aliases.sh             # Shell aliases for context profiles
├── tests/
│   ├── validate-config.sh     # Config validation
│   ├── test-behaviors.sh      # Behavioral tests for hooks
│   ├── lib.sh                 # Cross-platform test helpers
│   └── scenarios/             # Workflow dry-run scenario scripts
├── CLAUDE.md
├── AGENTS.md
└── README.md
```

## License

MIT
