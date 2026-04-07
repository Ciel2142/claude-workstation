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
    SRV_USER="${BEADS_SERVER_USER:-root}"

    # M1: Use python3 json.dumps to avoid injection via env vars with quotes/special chars
    python3 -c "
import json, sys
data = {
    'database': 'dolt',
    'backend': 'dolt',
    'dolt_mode': 'server',
    'dolt_server_host': sys.argv[1],
    'dolt_server_port': int(sys.argv[2]),
    'dolt_server_user': sys.argv[3],
    'dolt_database': sys.argv[4],
    'project_id': sys.argv[5]
}
json.dump(data, open(sys.argv[6], 'w'), indent=2)
print()  # trailing newline
" "$BEADS_SERVER_HOST" "$PORT" "$SRV_USER" "$DATABASE" "$PROJECT_ID" "$METADATA"
    echo "$PORT" > "$BEADS_DIR/dolt-server.port"
else
    # Ensure embedded mode — safe JSON via python3
    python3 -c "
import json, sys
data = {
    'database': 'dolt',
    'backend': 'dolt',
    'dolt_mode': 'embedded',
    'dolt_database': sys.argv[1],
    'project_id': sys.argv[2]
}
json.dump(data, open(sys.argv[3], 'w'), indent=2)
print()  # trailing newline
" "$DATABASE" "$PROJECT_ID" "$METADATA"
    rm -f "$BEADS_DIR/dolt-server.port"
fi
