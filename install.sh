#!/usr/bin/env bash
# install.sh — Bootstrap the Claude Workstation by installing its dependencies:
#   1. Everything Claude Code (ECC) — from the latest locally cached plugin
#   2. Beads — from the remote install script
set -euo pipefail

ECC_CACHE_DIR="$HOME/.claude/plugins/cache/everything-claude-code/ecc"

# --- Step 1: Run the ECC installer from the latest cached version ---

if [ ! -d "$ECC_CACHE_DIR" ]; then
  echo "ERROR: ECC plugin cache not found at $ECC_CACHE_DIR"
  echo "Install the ECC plugin first: https://github.com/affaan-m/everything-claude-code"
  exit 1
fi

# Pick the highest semver directory
ECC_LATEST="$(ls -d "$ECC_CACHE_DIR"/*/ 2>/dev/null | sort -V | tail -1)"

if [ -z "$ECC_LATEST" ]; then
  echo "ERROR: No ECC versions found in $ECC_CACHE_DIR"
  exit 1
fi

ECC_INSTALL="$ECC_LATEST/install.sh"

if [ ! -f "$ECC_INSTALL" ]; then
  echo "ERROR: install.sh not found at $ECC_INSTALL"
  exit 1
fi

echo "==> Installing ECC from $ECC_INSTALL"
bash "$ECC_INSTALL"

# --- Step 2: Run the Beads remote installer ---

echo "==> Installing Beads"
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
