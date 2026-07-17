-- =============================================================================
-- clickhouse-rd — Display aggregate results
-- =============================================================================
-- CLICKHOUSE_DATABASE is substituted by envsubst at runtime.
-- =============================================================================

-- 5-minute aggregate table (TTL: 5 minutes)
SELECT '--- TENANT_METRICS_5M (5-minute TTL) ---' AS section;
SELECT
    hour,
    tenant_id,
    event_type,
    countMerge(event_count) AS event_count,
    sumMerge(value_sum)     AS value_sum,
    minMerge(value_min)     AS value_min,
    maxMerge(value_max)     AS value_max
FROM ${CLICKHOUSE_DATABASE}.tenant_metrics_5m
GROUP BY hour, tenant_id, event_type
ORDER BY hour, tenant_id, event_type;

-- 30-minute aggregate table (TTL: 30 minutes)
SELECT '--- TENANT_METRICS_30M (30-minute TTL) ---' AS section;
SELECT
    day,
    tenant_id,
    sum(total_events)    AS total_events,
    sum(purchase_events) AS purchase_events,
    sum(total_value)     AS total_value
FROM ${CLICKHOUSE_DATABASE}.tenant_metrics_30m
GROUP BY day, tenant_id
ORDER BY day, tenant_id;
