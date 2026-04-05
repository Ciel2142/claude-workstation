# Claude Code profile aliases
# Appended to ~/.bashrc or ~/.zshrc by /claude-workstation:setup

alias claude-dev='claude --system-prompt "$(cat ~/.claude/contexts/dev.md)" --allow-dangerously-skip-permissions --effort high'
alias claude-research='claude --system-prompt "$(cat ~/.claude/contexts/research.md)" --allow-dangerously-skip-permissions --effort high'
alias claude-review='claude --system-prompt "$(cat ~/.claude/contexts/review.md)" --allow-dangerously-skip-permissions --effort high'
