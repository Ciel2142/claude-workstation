# Reviewer Bead Protocol

You are reviewing code. Track your review in the PARENT task's notes.

## Start Review

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <parent-task-id> "[M] review:<type>:started reviewing <scope>"
```

Where `<type>` is: `spec` | `quality` | `security`

## For EACH Finding

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <parent-task-id> "[M] review:<type>:finding:<severity> <description>"
```

Severity: CRITICAL | HIGH | MEDIUM | LOW | INFO

## For CRITICAL or HIGH Findings — Create Side-Quest (MANDATORY)

```bash
bd create --title="Found: <issue>" --type=bug -p <severity-maps-to-priority>
bd dep add <new-id> <parent-task-id> --type discovered-from
```

You MUST create side-quest beads for CRITICAL and HIGH findings. Do not skip this.

## Verdict

Pass:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <parent-task-id> "[M] review:<type> passed — no blocking issues"
```

Block:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/bd-notes-append" <parent-task-id> "[M] review:<type>:blocked <N> issues must fix"
```

<!-- BEAD-PROTOCOL-v1:reviewer -->
