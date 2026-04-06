---
name: debugging-protocol
version: 1.0.0
description: >
  Debugging-first protocol for bugs. Root cause analysis before fixes,
  3-strike rule, systematic debugging workflow.
  TRIGGER: When starting bug work, encountering errors, or debugging.
---

# Debugging

## Debugging-First Protocol

When working on a bug (task type `bug`), ALWAYS invoke `superpowers:systematic-debugging` before attempting a fix.

## Process

1. **Root cause** — read error messages, reproduce the issue, check recent changes
2. **Pattern analysis** — find working examples of similar code, compare with broken code
3. **Hypothesis** — form a single-variable hypothesis, test it
4. **Fix with test** — write a failing regression test that reproduces the bug, then fix (feeds into TDD)
5. **Stop after 3 failed attempts** — if three hypotheses fail, question the architecture. The bug may be a symptom of a deeper design issue.

## Workflow

Bugs follow this path regardless of tier (trivial/small/medium+):

```
bd create --title="..." --type=bug
→ superpowers:systematic-debugging (root cause)
→ superpowers:test-driven-development (regression test + fix)
→ superpowers:requesting-code-review
→ superpowers:verification-before-completion
→ bd close <id>
```

## Anti-Patterns

- Do NOT skip straight to a fix without understanding root cause
- Do NOT write the regression test before identifying the root cause
- Do NOT keep trying random fixes — 3 strikes and reassess
