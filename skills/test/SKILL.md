---
name: test
version: 1.0.0
description: >
  Validate the Claude Workstation configuration and run workflow dry-run scenarios.
  TRIGGER: After setup, or anytime to verify configuration integrity.
---

# Claude Workstation Tests

## Quick Validation

Run the automated config validation (26+ checks):

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(dirname "$0")")")}"
bash "$PLUGIN_ROOT/tests/validate-config.sh"
```

## Full Dry-Run Scenarios

To run all workflow tier scenarios end-to-end:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(dirname "$0")")")}"
SCENARIOS="$PLUGIN_ROOT/tests/scenarios"

bash "$SCENARIOS/scaffold.sh"
bash "$SCENARIOS/trivial.sh"
bash "$SCENARIOS/small.sh"
bash "$SCENARIOS/medium-plus.sh"
bash "$SCENARIOS/escalation.sh"
bash "$SCENARIOS/side-quest.sh"
bash "$SCENARIOS/cleanup.sh"
```

Each scenario script is self-contained and exits 0 on success, 1 on failure.

## What Gets Tested

### Config Validation
1. File existence (contexts, settings, plugin source files)
2. JSON validity (settings.json)
3. Plugin source files (workflow.md, session-start hook, 6 new skills)
4. Workflow context content completeness
5. Hook output validity (produces valid JSON with additionalContext)
6. Plugin presence (Beads, Superpowers, ECC)
7. Shell aliases presence
8. Skill directory completeness (all 10 skills present)
9. SKILL.md frontmatter name matches directory

### Dry-Run Scenarios
- **Trivial:** bd create -> fix -> verify -> bd close
- **Small:** bd create -> TDD (RED->GREEN) -> review -> verify -> bd close
- **Medium+:** Epic -> sub-tasks with deps -> ready front -> TDD per sub-task -> close
- **Escalation:** Start trivial -> discover scope growth -> escalate to small
- **Side quest:** Discover unrelated issue mid-work -> log -> finish current -> check ready
