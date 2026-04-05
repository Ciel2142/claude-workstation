# Verification Output Template

When running `/superpowers:verification-before-completion`, produce output in this
standardized format and append it to the beads task notes.

## Template

````
## Verification: <beads-task-id>
- Tests:  <status> <count> passed, <count> failed (exit <code>)
- Build:  <status> <message> (exit <code>)
- Lint:   <status> <message> (exit <code>)
- Type:   <status> <message> (exit <code>)
- Manual: <status> <description of what was checked>
````

## Status Symbols

- `✓` — check passed
- `✗` — check failed (BLOCKING — must fix before closing task)
- `⊘` — skipped with reason

## Rules

1. Each line must include the actual exit code from the command run.
2. Skipped checks must state the reason: `- Lint: ⊘ skipped (no linter configured)`
3. Failed checks block completion: `- Tests: ✗ 2 failed (exit 1) — BLOCKING`
4. At least one check must pass. All-skipped is not valid verification.
5. Append the verification block to beads task notes: `bd update <id> --notes "<block>"`
