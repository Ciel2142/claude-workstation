# Claude Workstation

A Claude Code plugin that restores your full development environment from a single install.

## What's Included

- **Unified Workflow** — Size-based routing (trivial/small/medium+) connecting Beads, Superpowers, and ECC
- **MCP Servers** — context7, memory, exa, playwright, sequential-thinking, token-optimizer
- **Context Profiles** — `claude-dev`, `claude-research`, `claude-review` shell aliases
- **Custom Rules** — Workflow routing, plugin lanes, research guidance
- **Test Suite** — Config validation + dry-run scenarios for every workflow tier

## Install

```bash
# In Claude Code:
/plugin marketplace add github:Ciel2142/claude-workstation
/plugin install claude-workstation@claude-workstation

# Then run setup:
/claude-workstation:setup

# Validate:
/claude-workstation:test
```

## Dependencies

Installed automatically by the setup skill:

| Plugin | Purpose |
|---|---|
| [Beads](https://github.com/steveyegge/beads) | Task tracking |
| [Superpowers](https://github.com/obra/superpowers-marketplace) | Development process |
| [ECC](https://github.com/affaan-m/everything-claude-code) | Language/domain expertise |
| + 9 more from claude-plugins-official | Search, review, security, etc. |

## Commands

| Command | What it does |
|---|---|
| `/workflow` | Show the full development playbook |
| `/claude-workstation:setup` | Install dependencies and configure environment |
| `/claude-workstation:test` | Validate configuration and run scenarios |

## Workflow Tiers

| Tier | Signal | Flow |
|---|---|---|
| **Trivial** | 1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files or new system | Epic → brainstorm → plan → sub-tasks → TDD → verify → close |

## Context Profiles

After setup, use these shell aliases:

```bash
claude-dev       # Code-first development mode
claude-research  # Exploration and investigation mode
claude-review    # Code review and quality analysis mode
```

## License

MIT
