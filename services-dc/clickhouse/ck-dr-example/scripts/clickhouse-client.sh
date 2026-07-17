#!/usr/bin/env bash
# =============================================================================
# clickhouse-rd — ClickHouse client wrapper script
# =============================================================================
# Opens an interactive clickhouse-client session or runs a query passed as
# arguments.  All connection parameters come from the .env file located in the
# project root (one directory above scripts/).
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/.env" 2>/dev/null || {
    echo "ERROR: .env file not found at ${PROJECT_ROOT}/.env"
    echo "Copy .env.example to .env and adjust values."
    exit 1
}

exec docker compose \
    -f "${PROJECT_ROOT}/docker-compose.yml" \
    exec -T clickhouse \
    clickhouse-client \
    --host localhost \
    --port 9000 \
    --user "${CLICKHOUSE_USER:-rd_user}" \
    --password "${CLICKHOUSE_PASSWORD:-rd_local_password}" \
    --database "${CLICKHOUSE_DATABASE:-clickhouse_rd}" \
    "$@"
