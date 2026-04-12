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

## Completion Sentinel (Mandatory)

Every subagent dispatched via a protocol template MUST emit exactly one H2 sentinel as the **last H2 heading** of its response. The orchestrator parses this sentinel to classify the outcome. Without it, the work is rejected and the subagent is re-dispatched.

Registered sentinels:

| Role | On success | On failure |
|------|-----------|-----------|
| implementer | `## PLAN COMPLETE` | `## BLOCKED <reason>` |
| reviewer (spec or quality) | `## REVIEW PASS` | `## REVIEW BLOCKED` |
| verifier | `## VERIFICATION PASSED` | `## VERIFICATION FAILED <reason>` |
| planner | `## PLAN READY` | `## PLAN BLOCKED <reason>` |
| build-fixer | `## BUILD FIXED` | `## BUILD STUCK <reason>` |

Rules:

1. The sentinel MUST be the last H2 heading in the response.
2. Exactly one sentinel per response.
3. The sentinel is required in addition to any beads milestone your role writes — they reinforce each other.
4. The orchestrator runs a filesystem spot-check after a success sentinel. If no artifact in the task's `must_haves` was actually modified, the orchestrator treats the sentinel as a lie and escalates via `bd human`.

## must_haves (Read Before Work)

If your task has a beads note of the form `must_haves: <plan-path>#<anchor>`, you MUST read the YAML block at that anchor before starting work. It contains:

- `truths`: observable behaviors that must hold after the task
- `artifacts`: files that must exist with real implementation
- `key_links`: wiring between artifacts (`<src>:<anchor> -> <dst>:<anchor>`)

Use `bash hooks/parse-must-haves.sh <plan-path> <anchor> <field>` to extract entries, or read the plan file directly.

<!-- BEAD-PROTOCOL-v1:base -->
