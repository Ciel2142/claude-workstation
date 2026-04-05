#!/usr/bin/env bash
# Configure beads server mode from environment variables.
# If BEADS_SERVER_HOST is set, rewrites metadata.json to server mode.
# Otherwise, ensures metadata.json stays in embedded mode.
#
# Required env vars for server mode:
#   BEADS_SERVER_HOST  - Dolt server hostname/IP
#   BEADS_DOLT_PASSWORD - Dolt server password
# Optional:
#   BEADS_SERVER_PORT  - Dolt server port (default: 3307)
#   BEADS_SERVER_USER  - Dolt server user (default: root)

set -euo pipefail

BEADS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
METADATA="$BEADS_DIR/metadata.json"

if [ ! -f "$METADATA" ]; then
    exit 0
fi

# Read project-specific values from current metadata
DATABASE=$(python3 -c "import json; print(json.load(open('$METADATA')).get('dolt_database', ''))" 2>/dev/null || echo "")
PROJECT_ID=$(python3 -c "import json; print(json.load(open('$METADATA')).get('project_id', ''))" 2>/dev/null || echo "")

if [ -n "${BEADS_SERVER_HOST:-}" ]; then
    PORT="${BEADS_SERVER_PORT:-3307}"
    USER="${BEADS_SERVER_USER:-root}"

    cat > "$METADATA" <<EOF
{
  "database": "dolt",
  "backend": "dolt",
  "dolt_mode": "server",
  "dolt_server_host": "$BEADS_SERVER_HOST",
  "dolt_server_port": $PORT,
  "dolt_server_user": "$USER",
  "dolt_database": "$DATABASE",
  "project_id": "$PROJECT_ID"
}
EOF
    echo "$PORT" > "$BEADS_DIR/dolt-server.port"
else
    # Ensure embedded mode
    cat > "$METADATA" <<EOF
{
  "database": "dolt",
  "backend": "dolt",
  "dolt_mode": "embedded",
  "dolt_database": "$DATABASE",
  "project_id": "$PROJECT_ID"
}
EOF
    rm -f "$BEADS_DIR/dolt-server.port"
fi
