#!/usr/bin/env bash
# =============================================================================
# clickhouse-rd — Restore from a native backup
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${PROJECT_ROOT}/.env" 2>/dev/null || {
    echo "ERROR: .env file not found at ${PROJECT_ROOT}/.env"
    exit 1
}

CLIENT="${SCRIPT_DIR}/clickhouse-client.sh"
DB="${CLICKHOUSE_DATABASE:-clickhouse_rd}"
BACKUP_NAME="${1:-}"
TARGET_DB="${2:-${DB}_restored}"

# ---- Validate arguments -------------------------------------------------
if [ -z "${BACKUP_NAME}" ]; then
    echo "ERROR: Usage: $0 <backup-name> [target-database]" >&2
    echo "  Use 'make list-backups' to see available backups." >&2
    exit 1
fi

echo "=== Restoring backup: ${BACKUP_NAME} ==="
echo "   Target database: ${TARGET_DB}"

# Verify the backup exists in system.backups
EXISTS=$("${CLIENT}" --query "
    SELECT count()
    FROM system.backups
    WHERE name LIKE '%${BACKUP_NAME}%'
    AND status = 'BACKUP_CREATED'
")

if [ "${EXISTS}" -eq 0 ] 2>/dev/null; then
    echo "WARNING: Backup '${BACKUP_NAME}' not found in system.backups." >&2
    echo "Attempting restore anyway — the backup may still exist in MinIO." >&2
fi

# Drop and recreate target database for clean restore
"${CLIENT}" --query "
    DROP DATABASE IF EXISTS ${TARGET_DB};
    CREATE DATABASE ${TARGET_DB}
    ENGINE = Atomic;
"

# Execute restore
echo "--- Running RESTORE ---"
"${CLIENT}" --query "
    RESTORE DATABASE ${DB} AS ${TARGET_DB}
    FROM Disk('s3_backup', '${BACKUP_NAME}')
    SETTINGS id = 'restore_${BACKUP_NAME}';
"

# Show restored row counts
echo "--- Restored table row counts ---"
"${CLIENT}" --query "
    SELECT 'events_raw:', count() FROM ${TARGET_DB}.events_raw
    UNION ALL
    SELECT 'tenant_metrics_5m:', count() FROM ${TARGET_DB}.tenant_metrics_5m
    UNION ALL
    SELECT 'tenant_metrics_30m:', count() FROM ${TARGET_DB}.tenant_metrics_30m;
"

echo "=== Restore complete ==="
echo "Restored database: ${TARGET_DB}"
echo "Active database:   ${DB} (unchanged)"
echo ""
echo "To query the restored database:"
echo "  make sql QUERY=\"SELECT count() FROM ${TARGET_DB}.events_raw\""
