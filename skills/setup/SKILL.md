---
name: setup
version: 1.0.0
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
    'beads-marketplace': 'steveyegge/beads',
    'Mixedbread-Grep': 'mixedbread-ai/mgrep'
}
for key, repo in needed.items():
    if key in markets:
        print(f'OK: {key}')
    else:
        print(f'MISSING: {key} ({repo})')
"
```

For any MISSING marketplaces, add them:
- `/plugin marketplace add github:affaan-m/everything-claude-code`
- `/plugin marketplace add github:obra/superpowers-marketplace`
- `/plugin marketplace add github:steveyegge/beads`
- `/plugin marketplace add github:mixedbread-ai/mgrep`

## Step 2: Install Plugins

Check and install any missing plugins:

```bash
cat ~/.claude/settings.json | python3 -c "
import sys, json
d = json.load(sys.stdin)
plugins = d.get('enabledPlugins', {})
needed = {
    'everything-claude-code@everything-claude-code': 'ECC',
    'superpowers@superpowers-marketplace': 'Superpowers',
    'beads@beads-marketplace': 'Beads',
    'mgrep@Mixedbread-Grep': 'mgrep',
    'context7@claude-plugins-official': 'Context7',
    'hookify@claude-plugins-official': 'Hookify',
    'playwright@claude-plugins-official': 'Playwright',
    'code-simplifier@claude-plugins-official': 'Code Simplifier',
    'code-review@claude-plugins-official': 'Code Review',
    'security-guidance@claude-plugins-official': 'Security Guidance',
    'commit-commands@claude-plugins-official': 'Commit Commands',
    'frontend-design@claude-plugins-official': 'Frontend Design'
}
for key, name in needed.items():
    status = plugins.get(key)
    if status is True:
        print(f'OK: {name}')
    elif status is False:
        print(f'DISABLED: {name} (enable with /plugin enable)')
    else:
        print(f'MISSING: {name} (install: /plugin install {key})')
"
```

Install any MISSING plugins using `/plugin install <key>`.

## Step 3: Copy Custom Rules

Copy rules from the plugin to the user's rules directory. Skip if destination is newer.

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(dirname "$0")")")}"
RULES_COMMON_SRC="$PLUGIN_ROOT/rules/common"
RULES_COMMON_DST="$HOME/.claude/rules/common"
RULES_SRC="$PLUGIN_ROOT/rules"
RULES_DST="$HOME/.claude/rules"

mkdir -p "$RULES_COMMON_DST"

for file in unified-workflow.md plugin-routing.md development-workflow.md; do
    src="$RULES_COMMON_SRC/$file"
    dst="$RULES_COMMON_DST/$file"
    if [ ! -f "$dst" ] || [ "$src" -nt "$dst" ]; then
        cp "$src" "$dst"
        echo "Copied: common/$file"
    else
        echo "Skipped (destination newer): common/$file"
    fi
done

# context7.md lives at rules root, not in common/
src="$RULES_SRC/context7.md"
dst="$RULES_DST/context7.md"
if [ ! -f "$dst" ] || [ "$src" -nt "$dst" ]; then
    cp "$src" "$dst"
    echo "Copied: context7.md"
else
    echo "Skipped (destination newer): context7.md"
fi
```

## Step 4: Copy Context Profiles

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

## Step 5: Append Shell Aliases

Detect shell and append aliases if not already present.

```bash
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    echo "WARNING: No .bashrc or .zshrc found. Create one first."
    SHELL_RC=""
fi

if [ -n "$SHELL_RC" ]; then
    for alias_name in claude-dev claude-research claude-review; do
        if ! grep -q "alias $alias_name=" "$SHELL_RC" 2>/dev/null; then
            case "$alias_name" in
                claude-dev)
                    echo "alias claude-dev='claude --system-prompt \"\$(cat ~/.claude/contexts/dev.md)\" --allow-dangerously-skip-permissions --effort high'" >> "$SHELL_RC"
                    echo "Added: $alias_name"
                    ;;
                claude-research)
                    echo "alias claude-research='claude --system-prompt \"\$(cat ~/.claude/contexts/research.md)\" --allow-dangerously-skip-permissions --effort high'" >> "$SHELL_RC"
                    echo "Added: $alias_name"
                    ;;
                claude-review)
                    echo "alias claude-review='claude --system-prompt \"\$(cat ~/.claude/contexts/review.md)\" --allow-dangerously-skip-permissions --effort high'" >> "$SHELL_RC"
                    echo "Added: $alias_name"
                    ;;
            esac
        else
            echo "Skipped (already present): $alias_name"
        fi
    done
    echo ""
    echo "Run 'source $SHELL_RC' or start a new terminal to use the aliases."
fi
```

## Step 6: Check ECC Rules

```bash
ECC_RULES="$HOME/.claude/rules/common/coding-style.md"
if [ -f "$ECC_RULES" ]; then
    echo "OK: ECC rules are installed"
else
    echo ""
    echo "NOTE: ECC language-specific rules are not installed."
    echo "Run ECC's installer to add them:"
    echo "  bash ~/.claude/plugins/cache/everything-claude-code/everything-claude-code/*/install.sh"
    echo ""
fi
```

## Step 7: Validate

Run the validation script:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(dirname "$0")")")}"
bash "$PLUGIN_ROOT/tests/validate-config.sh"
```

If all checks pass, setup is complete.
