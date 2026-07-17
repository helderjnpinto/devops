#!/usr/bin/env bash
# =============================================================================
# clickhouse-rd — Force TTL materialization
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${PROJECT_ROOT}/.env" 2>/dev/null || true

CLIENT="${SCRIPT_DIR}/clickhouse-client.sh"

echo "=== Materializing TTL on events_raw ==="
CLICKHOUSE_DATABASE="${CLICKHOUSE_DATABASE:-clickhouse_rd}" \
"${CLIENT}" --query "$(envsubst < "${PROJECT_ROOT}/sql/materialize-ttl.sql")"

echo "=== TTL materialization complete ==="
echo "Note: Parts may still be in the process of moving to cold storage."
echo "Run 'make storage-status' to check disk distribution."
