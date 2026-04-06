# Claude Workstation

A Claude Code plugin that restores your full development environment from a single install.

## What's Included

- **Unified Workflow** — Size-based routing (trivial/small/medium+) connecting Beads, Superpowers, and ECC
- **Auto-Injected Context** — SessionStart hook delivers workflow context (~7KB) without setup
- **Auto-Tier Assessment** — `/start` scores task descriptions and routes to the right workflow automatically
- **Resume Work** — `/resume` lists open tasks, loads context at tier-appropriate depth, and continues the workflow
- **Bug Path** — systematic debugging rule ensures root cause analysis before fixes
- **Context Profiles** — `claude-dev`, `claude-research`, `claude-review` shell aliases
- **On-Demand Skills** — Phase-specific protocols for debugging, spike, scope health, milestones, verification
- **Session Hooks** — SessionStart and Stop hooks for beads state persistence
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

Installed by the setup skill:

| Plugin | Marketplace | Purpose |
|---|---|---|
| [Beads](https://github.com/steveyegge/beads) | beads-marketplace | Dolt-powered issue tracker with dependencies, milestones, and persistent task state across sessions |
| [Superpowers](https://github.com/obra/superpowers-marketplace) | superpowers-marketplace | Development process skills — brainstorming, planning, TDD, code review, verification, debugging |
| [ECC](https://github.com/affaan-m/everything-claude-code) | everything-claude-code | Language-specific and domain-specific skills, agents, patterns, and coding standards |

## Commands & Skills

| Command | What it does |
|---|---|
| `/claude-workstation:start` | Auto-assess task tier, create beads task, start the right workflow |
| `/claude-workstation:resume` | Resume open work — load context, detect position, continue workflow |
| `/help` | Show the full development playbook |
| `/claude-workstation:setup` | Install dependencies and configure environment |
| `/claude-workstation:test` | Validate configuration and run scenarios |
| `/claude-workstation:status` | Show current work state — position, next task, suggested skill |
| `/claude-workstation:debugging-protocol` | Reference: debugging-first protocol for bugs |
| `/claude-workstation:beads-milestones` | Reference: structured milestone checkpoint format |
| `/claude-workstation:spike-phase` | Reference: architecture validation for Medium+ |
| `/claude-workstation:scope-health` | Reference: scope creep detection with escalation |
| `/claude-workstation:verification-template` | Reference: standardized verification output format |

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
| **Trivial** | ≤1 file, no behavior change | `bd create` → fix → verify → `bd close` |
| **Small** | 1-3 files, single concern | `bd create` → TDD → review → verify → `bd close` |
| **Medium+** | 4+ files or new system | Epic → brainstorm → plan → sub-tasks → spike → TDD → verify → update-docs → finish → close |
| **Bug** | Any tier, type=bug | `bd create -t bug` → debug → TDD (regression test) → review → verify → close |

## Hooks

| Hook | When | What |
|---|---|---|
| **SessionStart** | Session begins | Injects condensed workflow context via `additionalContext` + configures beads server |
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
├── commands/
│   └── help.md               # /help command — full playbook
├── skills/
│   ├── start/SKILL.md         # /start — auto-tier assessment & workflow start
│   ├── resume/SKILL.md        # /resume — continue open work
│   ├── setup/SKILL.md         # /setup — environment installer
│   ├── test/SKILL.md          # /test — config validation
│   ├── debugging-protocol/    # On-demand: debugging-first protocol
│   ├── beads-milestones/      # On-demand: milestone checkpoint format
│   ├── spike-phase/           # On-demand: architecture validation
│   ├── scope-health/          # On-demand: scope creep detection
│   ├── verification-template/ # On-demand: verification output format
│   └── status/SKILL.md        # /status — read-only work orientation
├── contexts/
│   ├── workflow.md            # Workflow context (auto-injected via hook)
│   ├── dev.md
│   ├── research.md
│   └── review.md
├── hooks/
│   ├── hooks.json             # SessionStart + PreToolUse + Stop hooks
│   ├── session-start          # Context injection script
│   ├── pre-change-gate        # Beads task enforcement before file edits
│   └── stop                   # Session-end reminder script
├── profiles/
│   └── aliases.sh             # Shell aliases for context profiles
├── tests/
│   ├── validate-config.sh     # Config validation
│   └── scenarios/             # Workflow dry-run scenario scripts
├── CLAUDE.md
└── AGENTS.md
```

## License

MIT
