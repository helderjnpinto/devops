#!/usr/bin/env bash
# =============================================================================
# clickhouse-rd — Recalculate aggregate tables for a specific UTC day
# =============================================================================
# Reads from events_raw (including cold S3 data) and rebuilds both hourly
# and daily aggregate tables for the given date.
#
# Usage:  ./recalculate-day.sh YYYY-MM-DD
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLIENT="${SCRIPT_DIR}/clickhouse-client.sh"

# ---- Validate argument --------------------------------------------------
DATE="${1:-}"
if [ -z "${DATE}" ]; then
    echo "ERROR: Usage: $0 YYYY-MM-DD" >&2
    exit 1
fi

if ! echo "${DATE}" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo "ERROR: Date must be in YYYY-MM-DD format, got: ${DATE}" >&2
    exit 1
fi

# Validate that the date is a real calendar date
if ! date -u -d "${DATE}" >/dev/null 2>&1; then
    echo "ERROR: Invalid date: ${DATE}" >&2
    exit 1
fi

DB="${CLICKHOUSE_DATABASE:-clickhouse_rd}"

echo "=== Recalculating aggregates for UTC day: ${DATE} ==="

# ---- Step 1: Create temporary hourly target table -----------------------
echo "--- Creating temporary hourly table ---"
"${CLIENT}" --query "
    DROP TABLE IF EXISTS ${DB}._tmp_hourly;
    CREATE TABLE ${DB}._tmp_hourly
    ENGINE = AggregatingMergeTree
    PARTITION BY toYYYYMM(hour)
    ORDER BY (tenant_id, event_type, hour)
    AS
    SELECT
        toStartOfHour(event_time) AS hour,
        tenant_id,
        event_type,
        countState()              AS event_count,
        sumState(value)           AS value_sum,
        minState(value)           AS value_min,
        maxState(value)           AS value_max
    FROM ${DB}.events_raw
    WHERE toDate(event_time) = toDate('${DATE}')
    GROUP BY hour, tenant_id, event_type;
"

# ---- Step 2: Create temporary daily target table ------------------------
echo "--- Creating temporary daily table ---"
"${CLIENT}" --query "
    DROP TABLE IF EXISTS ${DB}._tmp_daily;
    CREATE TABLE ${DB}._tmp_daily
    ENGINE = SummingMergeTree
    PARTITION BY toYYYYMM(day)
    ORDER BY (tenant_id, day)
    AS
    SELECT
        toDate(event_time) AS day,
        tenant_id,
        count(*)                      AS total_events,
        countIf(event_type = 'purchase') AS purchase_events,
        sum(value)                    AS total_value
    FROM ${DB}.events_raw
    WHERE toDate(event_time) = toDate('${DATE}')
    GROUP BY day, tenant_id;
"

# ---- Step 3: Show validation counts ------------------------------------
echo "--- Validation counts (temporary tables) ---"
"${CLIENT}" --query "
    SELECT 'Hourly groups in tmp:', count() FROM ${DB}._tmp_hourly;
"
"${CLIENT}" --query "
    SELECT 'Daily groups in tmp:', count() FROM ${DB}._tmp_daily;
"

# ---- Step 4: Replace partitions in real target tables --------------------
echo "--- Replacing 5m table partitions ---"
HOUR_PARTS=$("${CLIENT}" --query "
    SELECT DISTINCT partition_id
    FROM system.parts
    WHERE database = '${DB}' AND table = '_tmp_hourly' AND active = 1
    ORDER BY partition_id;
")

for part_id in ${HOUR_PARTS}; do
    echo "  Replacing partition ${part_id} in tenant_metrics_5m"
    "${CLIENT}" --query "
        ALTER TABLE ${DB}.tenant_metrics_5m
        REPLACE PARTITION ID '${part_id}'
        FROM ${DB}._tmp_hourly;
    "
done

echo "--- Replacing 30m table partitions ---"
DAY_PARTS=$("${CLIENT}" --query "
    SELECT DISTINCT partition_id
    FROM system.parts
    WHERE database = '${DB}' AND table = '_tmp_daily' AND active = 1
    ORDER BY partition_id;
")

for part_id in ${DAY_PARTS}; do
    echo "  Replacing partition ${part_id} in tenant_metrics_30m"
    "${CLIENT}" --query "
        ALTER TABLE ${DB}.tenant_metrics_30m
        REPLACE PARTITION ID '${part_id}'
        FROM ${DB}._tmp_daily;
    "
done

# ---- Step 5: Drop temporary tables --------------------------------------
echo "--- Cleaning up temporary tables ---"
"${CLIENT}" --query "
    DROP TABLE IF EXISTS ${DB}._tmp_hourly;
    DROP TABLE IF EXISTS ${DB}._tmp_daily;
"

echo "=== Recalculation complete for ${DATE} ==="
