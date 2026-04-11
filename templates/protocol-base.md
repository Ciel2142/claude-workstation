# Bead Protocol (All Agents)

You MUST track your work in the beads system. This is not optional.

## Rules

1. **Every action is tracked** — update beads notes as you progress through milestones
2. **No silent work** — if you make changes, log them with `[M]` milestone markers
3. **Side-quests get their own beads** — CRITICAL/HIGH findings during review → create new bead

## Milestone Format

Append milestone lines to task notes:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] <phase> <freetext detail>"
```

## Side-Quest Protocol

When you discover an issue OUTSIDE your current task scope:

```bash
bd create --title="Found: <issue>" --type=bug -p <priority>
bd dep add <new-id> <current-id> --type discovered-from
```

Do NOT fix it inline. Log it and continue your current task.

<!-- BEAD-PROTOCOL-v1:base -->
