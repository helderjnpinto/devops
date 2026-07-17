#!/usr/bin/env bash
# =============================================================================
# clickhouse-rd — Seed data
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source .env so envsubst can substitute variables
source "${PROJECT_ROOT}/.env" 2>/dev/null || true

CLIENT="${SCRIPT_DIR}/clickhouse-client.sh"

echo "=== Seeding old data (events >= 2 hours ago) ==="
CLICKHOUSE_DATABASE="${CLICKHOUSE_DATABASE:-clickhouse_rd}" \
"${CLIENT}" --query "$(envsubst < "${PROJECT_ROOT}/sql/seed-old.sql")"

echo "=== Seeding recent data (within last 30 seconds) ==="
CLICKHOUSE_DATABASE="${CLICKHOUSE_DATABASE:-clickhouse_rd}" \
"${CLIENT}" --query "$(envsubst < "${PROJECT_ROOT}/sql/seed-hot.sql")"

echo "=== Seed complete ==="
