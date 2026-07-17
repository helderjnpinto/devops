#!/usr/bin/env bash
# =============================================================================
# clickhouse-rd — Display storage status
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${PROJECT_ROOT}/.env" 2>/dev/null || true

CLIENT="${SCRIPT_DIR}/clickhouse-client.sh"

CLICKHOUSE_DATABASE="${CLICKHOUSE_DATABASE:-clickhouse_rd}" \
"${CLIENT}" --query "$(envsubst < "${PROJECT_ROOT}/sql/storage-status.sql")"
