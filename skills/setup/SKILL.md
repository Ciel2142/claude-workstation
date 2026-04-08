---
name: setup
version: 1.6.0
description: >
  Install and configure the full Claude Code development environment.
  TRIGGER: First run on a new machine, or anytime to repair configuration.
---

# Claude Workstation Setup

Install dependencies, copy rules, contexts, and aliases. All steps are idempotent.

## Step 1: Register Marketplaces

Check and register any missing marketplaces:

```bash
cat ~/.claude/settings.json | python3 -c "
import sys, json
d = json.load(sys.stdin)
markets = d.get('extraKnownMarketplaces', {})
needed = {
    'everything-claude-code': 'affaan-m/everything-claude-code',
    'superpowers-marketplace': 'obra/superpowers-marketplace',
    'beads-marketplace': 'steveyegge/beads'
}
for key, repo in needed.items():
    if key in markets:
        print(f'OK: {key}')
    else:
        print(f'MISSING: {key} ({repo})')
"
```

For any MISSING marketplaces, add them:
- `/plugin marketplace add https://github.com/affaan-m/everything-claude-code`
- `/plugin marketplace add https://github.com/obra/superpowers-marketplace`
- `/plugin marketplace add https://github.com/steveyegge/beads`

## Step 2: Install and Update Plugins

Check, install missing, and update already-installed plugins:

```bash
cat ~/.claude/settings.json | python3 -c "
import sys, json
d = json.load(sys.stdin)
plugins = d.get('enabledPlugins', {})
needed = {
    'ecc@everything-claude-code': 'ECC',
    'superpowers@superpowers-marketplace': 'Superpowers',
    'beads@beads-marketplace': 'Beads'
}
for key, name in needed.items():
    status = plugins.get(key)
    if status is True:
        print(f'UPDATE: {name} ({key})')
    elif status is False:
        print(f'DISABLED: {name} (enable with /plugin enable)')
    else:
        print(f'MISSING: {name} (install: /plugin install {key})')
"
```

For any MISSING plugins, install using `/plugin install <key>`.

For any UPDATE plugins, update using `/plugin update <key>`.
A restart is required after updates take effect.

## Step 3: Copy Context Profiles

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(dirname "$0")")")}"
CONTEXTS_SRC="$PLUGIN_ROOT/contexts"
CONTEXTS_DST="$HOME/.claude/contexts"

mkdir -p "$CONTEXTS_DST"

for file in dev.md research.md review.md; do
    cp "$CONTEXTS_SRC/$file" "$CONTEXTS_DST/$file"
    echo "Copied: $file"
done
```

Note: `workflow.md` is NOT copied — it is delivered automatically via the SessionStart hook.

## Step 4: Clean Up Stale Aliases

Remove the deprecated `claude-workflow` alias (now delivered via SessionStart hook).

```bash
# Cross-platform sed in-place (BSD macOS requires -i '' for no backup)
sedi() {
    if [[ "$OSTYPE" == darwin* ]]; then sed -i '' "$@"; else sed -i "$@"; fi
}

for SHELL_RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$SHELL_RC" ] || continue
    if grep -q "alias claude-workflow=" "$SHELL_RC" 2>/dev/null; then
        sedi '/alias claude-workflow=/d' "$SHELL_RC"
        echo "Removed stale alias: claude-workflow from $SHELL_RC"
    fi
done
```

## Step 5: Append Shell Aliases

Detect shell and append aliases if not already present.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(dirname "$0")")")}"
ALIASES_FILE="$PLUGIN_ROOT/profiles/aliases.sh"

FOUND_RC=0
for SHELL_RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$SHELL_RC" ] || continue
    FOUND_RC=1
    echo "Checking $SHELL_RC..."
    # Read alias definitions from profiles/aliases.sh (single source of truth)
    while IFS= read -r line; do
        [[ "$line" =~ ^alias\ ([a-z-]+)= ]] || continue
        alias_name="${BASH_REMATCH[1]}"
        if ! grep -q "alias $alias_name=" "$SHELL_RC" 2>/dev/null; then
            echo "$line" >> "$SHELL_RC"
            echo "Added: $alias_name"
        else
            echo "Skipped (already present): $alias_name"
        fi
    done < "$ALIASES_FILE"
    echo ""
    echo "Run 'source $SHELL_RC' or start a new terminal to use the aliases."
done

if [ "$FOUND_RC" -eq 0 ]; then
    echo "WARNING: No .bashrc or .zshrc found. Create one first."
fi
```

## Step 6: Validate

Run the validation script:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(dirname "$0")")")}"
bash "$PLUGIN_ROOT/tests/validate-config.sh"
```

If all checks pass, setup is complete.
