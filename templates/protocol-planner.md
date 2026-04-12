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


## must_haves Block (Mandatory Per Task)

For every task in the plan you produce, you MUST write a `must_haves` YAML fence under the task heading:

````markdown
### Task N: <title>

```yaml
must_haves:
  truths:
    - <observable behavior, provable by command or grep>
  artifacts:
    - <repo-relative file path with real impl>
  key_links:
    - <src>:<anchor> -> <dst>:<anchor>
```
````

Field rules:

- `truths` has ≥1 entry. No subjective predicates like "code is clean". Every truth must be provable by a command (test run, grep, file read).
- `artifacts` has ≥1 entry. Repo-relative paths only. Must resolve to real files after the task is done, with more than 10 lines of actual implementation.
- `key_links` is optional but recommended when multiple artifacts must reference each other. Format `<src>:<anchor> -> <dst>:<anchor>` where anchor is line range, symbol, or grep pattern.

You MAY also write one epic-level `## must_haves` block at the top of the plan file covering the whole epic.

## Completion Sentinel

After the plan is written, emit as the LAST H2 of your response body:

- `## PLAN READY` on success
- `## PLAN BLOCKED <reason>` if you could not complete (e.g., spec contradictions, missing inputs)

<!-- BEAD-PROTOCOL-v1:planner -->
