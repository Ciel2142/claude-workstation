# Build Fixer Bead Protocol

You are fixing a build or test failure. Track progress in the task's notes.

## Milestones

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] fix:started <error summary>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] fix:diagnosed root cause: <cause>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] fix:applied <what changed>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <task-id> "[M] fix:verified build passes"
```

## If Fix Reveals Deeper Issue

Create a side-quest:

```bash
bd create --title="Found: <underlying issue>" --type=bug
bd dep add <new-id> <current-id> --type discovered-from
```

<!-- BEAD-PROTOCOL-v1:build-fixer -->
