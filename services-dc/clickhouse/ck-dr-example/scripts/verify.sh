#!/usr/bin/env bash
# =============================================================================
# clickhouse-rd — Verify aggregate consistency end-to-end
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${PROJECT_ROOT}/.env" 2>/dev/null || true

CLIENT="${SCRIPT_DIR}/clickhouse-client.sh"
DB="${CLICKHOUSE_DATABASE:-clickhouse_rd}"

ERRORS=0

echo "=== Aggregate Consistency Verification ==="
echo ""

# ---- Step 1: Run verification SQL and capture output -------------------
echo "--- Running verification queries ---"
RESULTS=$(CLICKHOUSE_DATABASE="${DB}" "${CLIENT}" --query "$(envsubst < "${PROJECT_ROOT}/sql/verify-aggregates.sql")" 2>&1)
VERIFY_EXIT=$?

if [ "${VERIFY_EXIT}" -ne 0 ]; then
    echo "ERROR: Verification SQL failed with exit code ${VERIFY_EXIT}" >&2
    echo "${RESULTS}"
    exit 1
fi

echo "${RESULTS}"
echo ""

# ---- Step 2: Check for mismatches --------------------------------------
if echo "${RESULTS}" | grep -qE '5M MISMATCHES|---'; then
    _5M_MISMATCHES=$(echo "${RESULTS}" | awk '/5M MISMATCHES/{flag=1; next} /30M MISMATCHES/{flag=0} flag' | grep -cvE '^-|^$|section')
    if [ "${_5M_MISMATCHES:-0}" -gt 0 ] 2>/dev/null; then
        echo "WARNING: tenant_metrics_5m mismatches detected!" >&2
        ERRORS=$((ERRORS + 1))
    fi
fi

if echo "${RESULTS}" | grep -qE '30M MISMATCHES|---'; then
    _30M_MISMATCHES=$(echo "${RESULTS}" | awk '/30M MISMATCHES/{flag=1; next} /SUMMARY/{flag=0} flag' | grep -cvE '^-|^$|section')
    if [ "${_30M_MISMATCHES:-0}" -gt 0 ] 2>/dev/null; then
        echo "WARNING: tenant_metrics_30m mismatches detected!" >&2
        ERRORS=$((ERRORS + 1))
    fi
fi

# ---- Step 3: Direct comparison counts ----------------------------------
echo "--- Direct count comparison ---"

RAW_COUNTS=$(CLICKHOUSE_DATABASE="${DB}" "${CLIENT}" --query "
    SELECT
        tenant_id,
        toDate(event_time) AS day,
        count(*) AS raw_count,
        countIf(event_type = 'purchase') AS raw_purchases,
        round(sum(value), 6) AS raw_value_sum
    FROM ${DB}.events_raw
    GROUP BY tenant_id, day
    ORDER BY tenant_id, day;
")

_5M_COUNTS=$(CLICKHOUSE_DATABASE="${DB}" "${CLIENT}" --query "
    SELECT
        tenant_id,
        toDate(hour) AS day,
        sum(countMerge(event_count)) AS mv_count,
        round(sum(sumMerge(value_sum)), 6) AS mv_value_sum
    FROM ${DB}.tenant_metrics_5m
    GROUP BY tenant_id, day
    ORDER BY tenant_id, day;
")

_30M_COUNTS=$(CLICKHOUSE_DATABASE="${DB}" "${CLIENT}" --query "
    SELECT
        tenant_id,
        day,
        sum(total_events) AS mv_total_events,
        sum(purchase_events) AS mv_purchases,
        round(sum(total_value), 6) AS mv_total_value
    FROM ${DB}.tenant_metrics_30m
    GROUP BY tenant_id, day
    ORDER BY tenant_id, day;
")

echo ""
echo "--- Raw data summary ---"
echo "${RAW_COUNTS}"
echo ""
echo "--- tenant_metrics_5m summary ---"
echo "${_5M_COUNTS}"
echo ""
echo "--- tenant_metrics_30m summary ---"
echo "${_30M_COUNTS}"

echo ""
echo "=== Verification complete ==="

if [ "${ERRORS}" -gt 0 ]; then
    echo "FAILED: ${ERRORS} mismatch(es) detected." >&2
    exit 1
else
    echo "PASSED: All aggregates match."
    exit 0
fi
