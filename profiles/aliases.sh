# Claude Code profile aliases
# Appended to ~/.bashrc or ~/.zshrc by /claude-workstation:setup
#
# --allow-dangerously-skip-permissions removed: it bypasses all tool-use
# confirmation prompts, which is unsafe for general use. Configure
# allowedTools in ~/.claude.json instead for selective auto-accept.

alias claude-dev='claude --system-prompt "$(cat ~/.claude/contexts/dev.md)" --effort high'
alias claude-research='claude --system-prompt "$(cat ~/.claude/contexts/research.md)" --effort high'
alias claude-review='claude --system-prompt "$(cat ~/.claude/contexts/review.md)" --effort high'
