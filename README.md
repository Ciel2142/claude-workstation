# Claude Workstation

A Claude Code plugin that restores your full development environment from a single install.

## What's Included

- **Unified Workflow** — Size-based routing (trivial/small/medium+) connecting Beads, Superpowers, and ECC
- **Auto-Tier Assessment** — `/start` scores task descriptions and routes to the right workflow automatically
- **Resume Work** — `/resume` lists open tasks, loads context at tier-appropriate depth, and continues the workflow
- **Bug Path** — systematic debugging rule ensures root cause analysis before fixes
- **MCP Servers** — context7, memory, exa, playwright, sequential-thinking, token-optimizer
- **Context Profiles** — `claude-dev`, `claude-research`, `claude-review` shell aliases
- **Custom Rules** — Workflow routing, plugin lanes, verification template, milestone tracking
- **Session Hooks** — SessionStart, PreCompact, and Stop hooks for beads state persistence
- **Test Suite** — Config validation + dry-run scenarios for every workflow tier

## Install

```bash
# In Claude Code:
/plugin marketplace add https://github.com/Ciel2142/claude-workstation
/plugin install claude-workstation@claude-workstation

# Then run setup:
/claude-workstation:setup

# Validate:
/claude-workstation:test
```

## Dependencies

Installed by the setup skill (mgrep is offered as an optional add-on):

| Plugin | Marketplace | Purpose |
|---|---|---|
| [Beads](https://github.com/steveyegge/beads) | beads-marketplace | Dolt-powered issue tracker with dependencies, milestones, and persistent task state across sessions |
| [Superpowers](https://github.com/obra/superpowers-marketplace) | superpowers-marketplace | Development process skills — brainstorming, planning, TDD, code review, verification, debugging |
| [ECC](https://github.com/affaan-m/everything-claude-code) | everything-claude-code | Language-specific and domain-specific skills, agents, patterns, and coding standards |
| [mgrep](https://github.com/mixedbread-ai/mgrep) *(optional)* | Mixedbread-Grep | Semantic code and web search using Mixedbread AI embeddings — replaces built-in Grep, Glob, and WebSearch with natural language search |
| Context7 | claude-plugins-official | Real-time library and framework documentation lookup via MCP |
| Hookify | claude-plugins-official | Create and manage hooks to prevent unwanted agent behaviors |
| Playwright | claude-plugins-official | Browser automation for E2E testing and visual verification |
| Code Simplifier | claude-plugins-official | Simplifies and refines code for clarity, consistency, and maintainability |
| Code Review | claude-plugins-official | Automated code review for quality, security, and best practices |
| Security Guidance | claude-plugins-official | Security vulnerability detection and remediation guidance |
| Commit Commands | claude-plugins-official | Git commit, push, and PR creation workflows |
| Frontend Design | claude-plugins-official | Create distinctive, production-grade frontend interfaces |

## Commands & Skills

| Command | What it does |
|---|---|
| `/claude-workstation:start` | Auto-assess task tier, create beads task, start the right workflow |
| `/claude-workstation:resume` | Resume open work — load context, detect position, continue workflow |
| `/workflow` | Show the full development playbook |
| `/claude-workstation:setup` | Install dependencies and configure environment |
| `/claude-workstation:test` | Validate configuration and run scenarios |

### `/start` — Begin New Work

```bash
/claude-workstation:start "Fix the login validation bug"
# → Scores description → Small → creates task → starts TDD

/claude-workstation:start "Design a new notification system"
# → Scores description → Medium+ → creates epic → starts brainstorming

/claude-workstation:start "Fix typo in README"
# → Scores description → Trivial → creates task → "Go fix it"

/claude-workstation:start --side-quest "Found: tokens aren't rotated"
# → Detects side-quest → creates bug → links to current task → parks it
```

### `/resume` — Continue Open Work

```bash
/claude-workstation:resume
# → Shows grouped task list → pick one → loads context → continues workflow

/claude-workstation:resume --interactive
# → Always shows list, suggests next skill but waits for confirmation

/claude-workstation:resume claude-workstation-pyc
# → Resumes specific task directly, skipping selection

/claude-workstation:resume --dry
# → Shows what would happen without invoking anything
```

## Workflow Tiers

| Tier | Signal | Flow |
|---|---|---|
| **Trivial** | 1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files or new system | Epic → brainstorm → plan → sub-tasks → TDD → verify → close |
| **Bug** | Any tier, type=bug | `bd create -t bug` → debug → TDD (regression test) → review → verify → close |

## Hooks

| Hook | When | What |
|---|---|---|
| **SessionStart** | Session begins | Runs `bd prime` to load active tasks |
| **PreCompact** | Before context compaction | Runs `bd prime` to preserve beads state |
| **Stop** | Session ends | Warns about untracked commits, lists in-progress tasks |

## Rules

Copied to `~/.claude/rules/common/` during setup:

| Rule | Purpose |
|---|---|
| `unified-workflow.md` | Beads-first rule, tier definitions, escalation |
| `plugin-routing.md` | Lane separation: Beads (tracking), Superpowers (process), ECC (expertise) |
| `development-workflow.md` | Research-first culture, GitHub search before coding |
| `verification-template.md` | Standardized verification output format with exit codes |
| `beads-milestones.md` | When to update beads notes (after brainstorming, planning, TDD, verification) |
| `debugging.md` | Debugging-first protocol for bugs: root cause before fix, 3-strike rule |

## Context Profiles

After setup, use these shell aliases:

```bash
claude-dev       # Code-first development mode
claude-research  # Exploration and investigation mode
claude-review    # Code review and quality analysis mode
```

## Project Structure

```
claude-workstation/
├── commands/
│   └── workflow.md           # /workflow command — full playbook
├── skills/
│   ├── start/SKILL.md         # /start — auto-tier assessment & workflow start
│   ├── resume/SKILL.md        # /resume — continue open work
│   ├── setup/SKILL.md        # /setup — environment installer
│   └── test/SKILL.md         # /test — config validation
├── rules/common/             # Copied to ~/.claude/rules/common/
│   ├── unified-workflow.md
│   ├── plugin-routing.md
│   ├── development-workflow.md
│   ├── verification-template.md
│   ├── beads-milestones.md
│   └── debugging.md
├── contexts/                 # Copied to ~/.claude/contexts/
│   ├── dev.md
│   ├── research.md
│   └── review.md
├── hooks/
│   └── hooks.json            # SessionStart, PreCompact, Stop
├── tests/
│   └── validate-config.sh    # 32+ config checks
├── .mcp.json                 # MCP server configuration
├── CLAUDE.md                 # Project instructions
└── AGENTS.md                 # Agent instructions (beads)
```

## License

MIT
