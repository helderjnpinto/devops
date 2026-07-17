-- =============================================================================
-- clickhouse-rd — Verify aggregate consistency
-- =============================================================================
-- Compares aggregates computed directly from events_raw against the
-- materialized view results for both 5m and 30m aggregate tables.
-- CLICKHOUSE_DATABASE is substituted by envsubst at runtime.
-- =============================================================================

-- ── 5m table: compute from raw ─────────────────────────────────────────
DROP TABLE IF EXISTS ${CLICKHOUSE_DATABASE}._verify_5m_raw;

CREATE TABLE ${CLICKHOUSE_DATABASE}._verify_5m_raw
ENGINE = Memory
AS
SELECT
    toStartOfHour(event_time) AS hour,
    tenant_id,
    event_type,
    count(*)                  AS raw_event_count,
    sum(value)                AS raw_value_sum,
    min(value)                AS raw_value_min,
    max(value)                AS raw_value_max
FROM ${CLICKHOUSE_DATABASE}.events_raw
GROUP BY hour, tenant_id, event_type;

-- ── 5m table: read from MV target ──────────────────────────────────────
DROP TABLE IF EXISTS ${CLICKHOUSE_DATABASE}._verify_5m_mv;

CREATE TABLE ${CLICKHOUSE_DATABASE}._verify_5m_mv
ENGINE = Memory
AS
SELECT
    hour,
    tenant_id,
    event_type,
    countMerge(event_count) AS mv_event_count,
    sumMerge(value_sum)     AS mv_value_sum,
    minMerge(value_min)     AS mv_value_min,
    maxMerge(value_max)     AS mv_value_max
FROM ${CLICKHOUSE_DATABASE}.tenant_metrics_5m
GROUP BY hour, tenant_id, event_type;

-- ── Compare 5m ─────────────────────────────────────────────────────────
SELECT '--- 5M MISMATCHES ---' AS section;

SELECT
    coalesce(r.hour, m.hour)           AS hour,
    coalesce(r.tenant_id, m.tenant_id) AS tenant_id,
    coalesce(r.event_type, m.event_type) AS event_type,
    r.raw_event_count,
    m.mv_event_count,
    abs(CAST(coalesce(r.raw_event_count, 0) AS Int64) - CAST(coalesce(m.mv_event_count, 0) AS Int64)) AS event_count_diff,
    round(coalesce(r.raw_value_sum, 0.0) - coalesce(m.mv_value_sum, 0.0), 6) AS value_sum_diff
FROM ${CLICKHOUSE_DATABASE}._verify_5m_raw AS r
FULL OUTER JOIN ${CLICKHOUSE_DATABASE}._verify_5m_mv AS m
    ON r.hour = m.hour AND r.tenant_id = m.tenant_id AND r.event_type = m.event_type
WHERE abs(CAST(coalesce(r.raw_event_count, 0) AS Int64) - CAST(coalesce(m.mv_event_count, 0) AS Int64)) > 0
   OR abs(coalesce(r.raw_value_sum, 0.0) - coalesce(m.mv_value_sum, 0.0)) > 0.001
ORDER BY hour, tenant_id, event_type;

-- ── 30m table: compute from raw ────────────────────────────────────────
DROP TABLE IF EXISTS ${CLICKHOUSE_DATABASE}._verify_30m_raw;

CREATE TABLE ${CLICKHOUSE_DATABASE}._verify_30m_raw
ENGINE = Memory
AS
SELECT
    toDate(event_time) AS day,
    tenant_id,
    count(*)                      AS raw_total_events,
    countIf(event_type = 'purchase') AS raw_purchase_events,
    sum(value)                    AS raw_total_value
FROM ${CLICKHOUSE_DATABASE}.events_raw
GROUP BY day, tenant_id;

-- ── 30m table: read from MV target ─────────────────────────────────────
DROP TABLE IF EXISTS ${CLICKHOUSE_DATABASE}._verify_30m_mv;

CREATE TABLE ${CLICKHOUSE_DATABASE}._verify_30m_mv
ENGINE = Memory
AS
SELECT
    day,
    tenant_id,
    sum(total_events)    AS mv_total_events,
    sum(purchase_events) AS mv_purchase_events,
    sum(total_value)     AS mv_total_value
FROM ${CLICKHOUSE_DATABASE}.tenant_metrics_30m
GROUP BY day, tenant_id;

-- ── Compare 30m ────────────────────────────────────────────────────────
SELECT '--- 30M MISMATCHES ---' AS section;

SELECT
    coalesce(r.day, m.day)             AS day,
    coalesce(r.tenant_id, m.tenant_id) AS tenant_id,
    r.raw_total_events,
    m.mv_total_events,
    r.raw_purchase_events,
    m.mv_purchase_events,
    round(coalesce(r.raw_total_value, 0.0) - coalesce(m.mv_total_value, 0.0), 6) AS value_diff
FROM ${CLICKHOUSE_DATABASE}._verify_30m_raw AS r
FULL OUTER JOIN ${CLICKHOUSE_DATABASE}._verify_30m_mv AS m
    ON r.day = m.day AND r.tenant_id = m.tenant_id
WHERE abs(CAST(coalesce(r.raw_total_events, 0) AS Int64) - CAST(coalesce(m.mv_total_events, 0) AS Int64)) > 0
   OR abs(CAST(coalesce(r.raw_purchase_events, 0) AS Int64) - CAST(coalesce(m.mv_purchase_events, 0) AS Int64)) > 0
   OR abs(coalesce(r.raw_total_value, 0.0) - coalesce(m.mv_total_value, 0.0)) > 0.001
ORDER BY day, tenant_id;

-- ── Summary ─────────────────────────────────────────────────────────────
SELECT '--- SUMMARY ---' AS section;

SELECT
    (SELECT count() FROM ${CLICKHOUSE_DATABASE}._verify_5m_raw)   AS raw_5m_groups,
    (SELECT count() FROM ${CLICKHOUSE_DATABASE}._verify_5m_mv)    AS mv_5m_groups,
    (SELECT count() FROM ${CLICKHOUSE_DATABASE}._verify_30m_raw)  AS raw_30m_groups,
    (SELECT count() FROM ${CLICKHOUSE_DATABASE}._verify_30m_mv)   AS mv_30m_groups;

-- ── Cleanup ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS ${CLICKHOUSE_DATABASE}._verify_5m_raw;
DROP TABLE IF EXISTS ${CLICKHOUSE_DATABASE}._verify_5m_mv;
DROP TABLE IF EXISTS ${CLICKHOUSE_DATABASE}._verify_30m_raw;
DROP TABLE IF EXISTS ${CLICKHOUSE_DATABASE}._verify_30m_mv;
