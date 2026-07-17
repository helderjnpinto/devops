-- =============================================================================
-- clickhouse-rd — Seed old data (~8 minutes in the past)
-- =============================================================================
-- Inserts events with event_time ~8 minutes ago so they satisfy the
-- 5-minute cold-storage TTL without triggering the 10-minute delete TTL
-- immediately. This gives you a ~2-minute window to observe data on
-- the cold tier before the delete TTL removes it.
-- CLICKHOUSE_DATABASE is substituted by envsubst at runtime.
-- =============================================================================

INSERT INTO ${CLICKHOUSE_DATABASE}.events_raw
SELECT
    generateUUIDv4()                                                                         AS event_id,
    number % 5 + 1                                                                           AS tenant_id,
    date_add(minute, -8 + floor(number / 50) % 2, now64(3, 'UTC'))                           AS event_time,
    now64(3, 'UTC')                                                                          AS ingested_at,
    ['page_view', 'purchase', 'login', 'subscription_started', 'subscription_cancelled']
        [number % 5 + 1]                                                                     AS event_type,
    round(CAST(rand() % 1000 + 1 AS Float64) * 1.0 / 10.0, 2)                               AS value,
    format('{{"row":{}, "tenant":{}, "batch":"old"}}', number, number % 5 + 1)                AS payload
FROM system.numbers
LIMIT 200;
