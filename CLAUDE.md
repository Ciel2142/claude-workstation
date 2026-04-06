## Beads-First Rule

Before making ANY change to the codebase — editing files, deleting files, running destructive commands, or invoking Superpowers skills — create a beads task first.

Sequence: `bd create` → then work. No work without a beads task. No exceptions.

## Quick Start

- **New work:** `/claude-workstation:start "description"` — assess tier, create task, start workflow
- **Resume work:** `/claude-workstation:resume` — pick up open tasks, load context, continue workflow

## Workflow

Run `/help` for the full development playbook with size-based routing (trivial/small/medium+).

## Context Delivery

Workflow context is auto-injected via SessionStart hook (~4KB). Phase-specific protocols (debugging, milestones, spike, scope health, verification) are delivered as on-demand skills.

## Setup

Run `/claude-workstation:setup` to install dependencies and configure environment.

## Validation

Run `/claude-workstation:test` to validate the configuration.
