#!/usr/bin/env bash
# =============================================================================
# clickhouse-rd — Native ClickHouse backup
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
BACKUP_NAME="clickhouse-rd-$(date -u +%Y%m%dT%H%M%SZ)"
LAST_BACKUP_FILE="${PROJECT_ROOT}/.last-backup"

echo "=== Creating backup: ${BACKUP_NAME} ==="

# Check if backup already exists in system.backups
EXISTS=$("${CLIENT}" --query "
    SELECT count()
    FROM system.backups
    WHERE name LIKE '%${BACKUP_NAME}%'
    AND status = 'BACKUP_CREATED'
")

if [ "${EXISTS}" -gt 0 ] 2>/dev/null; then
    echo "ERROR: Backup '${BACKUP_NAME}' already exists in system.backups." >&2
    exit 1
fi

# Check MinIO bucket via mc (run a new mc container instance)
MC_ALIAS="clickhouse-rd"
if docker compose -f "${PROJECT_ROOT}/docker-compose.yml" run --rm \
    --entrypoint /bin/sh \
    -e MC_HOST_clickhouse-rd="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@minio:9000" \
    minio-init \
    -c "mc stat ${MC_ALIAS}/${MINIO_BACKUP_BUCKET}/${BACKUP_NAME}/ 2>/dev/null" 2>/dev/null; then
    echo "ERROR: Backup path already exists in MinIO bucket." >&2
    exit 1
fi

# Execute backup
"${CLIENT}" --query "
    BACKUP DATABASE ${DB}
    TO Disk('s3_backup', '${BACKUP_NAME}')
    SETTINGS id = '${BACKUP_NAME}';
"

echo "--- Backup status ---"
"${CLIENT}" --query "
    SELECT *
    FROM system.backups
    WHERE name LIKE '%${BACKUP_NAME}%'
    ORDER BY start_time DESC
    LIMIT 1;
"

# Save last backup name
echo "${BACKUP_NAME}" > "${LAST_BACKUP_FILE}"
echo "Last backup saved to ${LAST_BACKUP_FILE}"

echo "=== Backup complete: ${BACKUP_NAME} ==="
