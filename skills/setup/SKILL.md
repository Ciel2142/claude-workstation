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
    'beads@beads-marketplace': 'Beads',
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

## Step 2b: Optional — mgrep (Semantic Search)

**Ask the user before proceeding:**

> **Would you like to install mgrep (semantic search)?**
>
> mgrep replaces the built-in Grep, Glob, and WebSearch tools with semantic search powered by Mixedbread AI embeddings. Instead of exact pattern matching, you describe what you're looking for in natural language and it finds semantically relevant code and files.
>
> **Why install it:**
> - Natural language code search — find code by intent, not exact strings
> - Semantic web search — `mgrep --web --answer "query"` replaces WebSearch
> - Better for exploratory searches when you don't know exact function/variable names
>
> **Caveat:** Once installed, mgrep overrides all built-in search tools (Grep, Glob, WebSearch). If you prefer exact pattern matching for precision work, you may want to skip this.
>
> Install mgrep? (yes/no)

**If the user says yes:**

1. Register the marketplace:
   ```bash
   /plugin marketplace add https://github.com/mixedbread-ai/mgrep
   ```

2. Install the plugin:
   ```bash
   /plugin install mgrep@Mixedbread-Grep
   ```

**If the user says no**, skip to Step 3.

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
for SHELL_RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$SHELL_RC" ] || continue
    if grep -q "alias claude-workflow=" "$SHELL_RC" 2>/dev/null; then
        sed -i '/alias claude-workflow=/d' "$SHELL_RC"
        echo "Removed stale alias: claude-workflow from $SHELL_RC"
    fi
done
```

## Step 5: Append Shell Aliases

Detect shell and append aliases if not already present.

```bash
FOUND_RC=0
for SHELL_RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$SHELL_RC" ] || continue
    FOUND_RC=1
    echo "Checking $SHELL_RC..."
    for alias_name in claude-dev claude-research claude-review; do
        if ! grep -q "alias $alias_name=" "$SHELL_RC" 2>/dev/null; then
            case "$alias_name" in
                claude-dev)
                    echo "alias claude-dev='claude --system-prompt \"\$(cat ~/.claude/contexts/dev.md)\" --effort high'" >> "$SHELL_RC"
                    echo "Added: $alias_name"
                    ;;
                claude-research)
                    echo "alias claude-research='claude --system-prompt \"\$(cat ~/.claude/contexts/research.md)\" --effort high'" >> "$SHELL_RC"
                    echo "Added: $alias_name"
                    ;;
                claude-review)
                    echo "alias claude-review='claude --system-prompt \"\$(cat ~/.claude/contexts/review.md)\" --effort high'" >> "$SHELL_RC"
                    echo "Added: $alias_name"
                    ;;
            esac
        else
            echo "Skipped (already present): $alias_name"
        fi
    done
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
