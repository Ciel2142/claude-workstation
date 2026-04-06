## Beads-First Rule

Before invoking ANY Superpowers skill (brainstorming, writing-plans, TDD, code-review, debugging, verification, etc.), create a beads task first.

Sequence: `bd create` → then invoke skill.

This applies to ALL work — design, planning, research, and code. No exceptions.

## Quick Start

- **New work:** `/claude-workstation:start "description"` — assess tier, create task, start workflow
- **Resume work:** `/claude-workstation:resume` — pick up open tasks, load context, continue workflow

## Workflow

Run `/help` for the full development playbook with size-based routing (trivial/small/medium+).

## Rules Delivery

Workflow rules are auto-injected via SessionStart hook (~3KB). Reference skills (debugging protocol, milestones, spike phase, scope health, verification template) are loaded on demand.

- **Opt-in always-on rules:** `/claude-workstation:install-rules` — copies all rules to `~/.claude/rules/`
- **Workflow alias:** `claude-workflow` — launches Claude with workflow context

## Setup

Run `/claude-workstation:setup` to install dependencies and configure environment.

## Validation

Run `/claude-workstation:test` to validate the configuration.
