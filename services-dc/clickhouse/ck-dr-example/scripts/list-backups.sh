#!/usr/bin/env bash
# =============================================================================
# clickhouse-rd — List available backups
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/.env" 2>/dev/null || {
    echo "ERROR: .env file not found at ${PROJECT_ROOT}/.env"
    exit 1
}

echo "=== Backups in system.backups ==="
docker compose -f "${PROJECT_ROOT}/docker-compose.yml" exec -T clickhouse \
    clickhouse-client \
    --host localhost \
    --port 9000 \
    --user "${CLICKHOUSE_USER:-rd_user}" \
    --password "${CLICKHOUSE_PASSWORD:-rd_local_password}" \
    --query "
        SELECT
            name,
            status,
            start_time,
            end_time,
            formatReadableSize(total_size) AS size,
            error
        FROM system.backups
        ORDER BY start_time DESC;
    "

echo ""
echo "=== Backups in MinIO (clickhouse-backups bucket) ==="
docker compose -f "${PROJECT_ROOT}/docker-compose.yml" run --rm \
    --entrypoint /bin/sh \
    -e MC_HOST_clickhouse-rd="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@minio:9000" \
    minio-init \
    -c "mc ls clickhouse-rd/${MINIO_BACKUP_BUCKET}/" 2>/dev/null || echo "  (No backups found or bucket not accessible)"
