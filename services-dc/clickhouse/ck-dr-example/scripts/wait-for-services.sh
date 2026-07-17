#!/usr/bin/env bash
# =============================================================================
# clickhouse-rd — Wait for all services to be healthy
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Waiting for services to become healthy..."

# Wait for ClickHouse to respond to /ping
for i in $(seq 1 30); do
    if docker compose -f "${PROJECT_ROOT}/docker-compose.yml" exec -T clickhouse \
        wget --no-verbose --tries=1 --spider http://localhost:8123/ping 2>/dev/null
    then
        echo "ClickHouse is healthy."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "ERROR: ClickHouse did not become healthy within 30 attempts."
        exit 1
    fi
    echo "Waiting for ClickHouse... attempt $i/30"
    sleep 2
done

echo "All services are ready."
