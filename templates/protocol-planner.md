# Planner Bead Protocol

You are creating an implementation plan. Track progress in the task's notes.

## Milestones

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] plan:started analyzing requirements"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] plan:spec-written path/to/spec.md"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] plan:subtasks-created N sub-tasks linked"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] plan:completed"
```

## If Scope Issues Found

Create a side-quest:

```bash
bd create --title="Found: <scope issue>" --type=task
bd dep add <new-id> <current-id> --type discovered-from
```

<!-- BEAD-PROTOCOL-v1:planner -->
