-- =============================================================================
-- clickhouse-rd — Seed recent data (within last 30 seconds)
-- =============================================================================
-- Inserts events with event_time very close to now() so they remain
-- on the hot (default) disk during the initial demo.
-- CLICKHOUSE_DATABASE is substituted by envsubst at runtime.
-- =============================================================================

INSERT INTO ${CLICKHOUSE_DATABASE}.events_raw
SELECT
    generateUUIDv4()                                                                         AS event_id,
    number % 5 + 1                                                                           AS tenant_id,
    date_add(second, -floor(rand() % 25), now64(3, 'UTC'))                                   AS event_time,
    now64(3, 'UTC')                                                                          AS ingested_at,
    ['page_view', 'purchase', 'login', 'subscription_started', 'subscription_cancelled']
        [number % 5 + 1]                                                                     AS event_type,
    round(CAST(rand() % 500 + 1 AS Float64) * 1.0 / 10.0, 2)                                AS value,
    format('{{"row":{}, "tenant":{}, "batch":"hot"}}', number, number % 5 + 1)                AS payload
FROM system.numbers
LIMIT 100;
