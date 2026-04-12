# Implementer Bead Protocol

You are implementing code changes. Follow the full TDD milestone chain.

## Before ANY Code Changes

Read the task's `must_haves` block first:

```bash
# Find the pointer in beads notes
bd show <task-id> | grep '^must_haves:' || echo "WARNING: no must_haves pointer — escalate to orchestrator"
# Extract fields (run for each field needed)
bash "${CLAUDE_PLUGIN_ROOT}/hooks/parse-must-haves.sh" <plan-path> <anchor> truths
bash "${CLAUDE_PLUGIN_ROOT}/hooks/parse-must-haves.sh" <plan-path> <anchor> artifacts
bash "${CLAUDE_PLUGIN_ROOT}/hooks/parse-must-haves.sh" <plan-path> <anchor> key_links
```

The truths are your acceptance criteria. Your TDD test must drive at least one truth. Your implementation must touch every artifact. Your wiring must satisfy every key_link.

## TDD Preamble

```bash
bd create --title="<task-description>" --type=task -p 2
bd dep add <new-id> <parent-id> --type parent-child
bd update <new-id> --claim
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] task:created sub-task for <description>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] task:claimed work started"
```

## During TDD — Update After EACH Phase

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:red <what test you wrote>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:red-verified <how it failed>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:green <what you implemented>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:green-verified <test output summary>"
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:refactor <what you cleaned up>"
```

Multiple TDD cycles allowed — repeat red→green as needed, then one refactor at end.

## After TDD Complete — Hand Off to Orchestrator

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <id> "[M] tdd:ready-for-review implementation complete"
```

**Do NOT close the task.** Return control to the orchestrator. Only the orchestrator closes tasks.

## SKIP NONE OF THESE

Your work will be rejected if milestones are missing. The orchestrator verifies every milestone after you return.


## Completion Sentinel

After writing `[M] tdd:ready-for-review` milestone, emit as the LAST H2 of your response body:

- `## PLAN COMPLETE` on success
- `## BLOCKED <short reason>` if you could not complete (e.g., upstream task returned bad output, test framework broken, ambiguous spec)

The orchestrator will not accept your return without this sentinel.

<!-- BEAD-PROTOCOL-v1:implementer -->
