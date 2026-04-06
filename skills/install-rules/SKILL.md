---
name: install-rules
version: 1.0.0
description: >
  Opt-in: copy all rule files from the plugin to ~/.claude/rules/common/.
  Makes rules always-on in every session. Not required — workflow context
  is auto-injected via hook by default.
  TRIGGER: When user wants traditional always-on rules instead of hook injection.
---

# Install Rules (Opt-In)

Copy all claude-workstation rule files to `~/.claude/rules/common/` so they load
as always-on global rules in every session.

**This is optional.** By default, essential workflow rules are auto-injected via a
SessionStart hook (~3KB). Installing rules adds ~15KB of always-on context on top
of the hook injection. Use this if you want the full reference material (debugging
protocol, milestone format, spike phase, scope health, verification template) always
available without invoking skills.

## Process

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$(dirname "$(dirname "$0")")")" && pwd)}"
RULES_SRC="$PLUGIN_ROOT/rules/common"
RULES_DST="$HOME/.claude/rules/common"

mkdir -p "$RULES_DST"

for file in unified-workflow.md plugin-routing.md development-workflow.md verification-template.md beads-milestones.md debugging.md spike-phase.md scope-health.md; do
    src="$RULES_SRC/$file"
    dst="$RULES_DST/$file"
    if [ ! -f "$dst" ] || [ "$src" -nt "$dst" ]; then
        cp "$src" "$dst"
        echo "Copied: $file"
    else
        echo "Skipped (destination newer): $file"
    fi
done
```

After running, the rules will be active in all future sessions across all projects.

To undo: delete the files from `~/.claude/rules/common/` manually.
