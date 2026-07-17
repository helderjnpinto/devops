#!/usr/bin/env bash
# =============================================================================
# clickhouse-rd — Database initialization script
# =============================================================================
# This scripts runs during ClickHouse container startup via
# /docker-entrypoint-initdb.d/.  It uses envsubst to substitute environment
# variables into SQL templates before passing them to clickhouse-client.
#
# The CLICKHOUSE_DATABASE, CLICKHOUSE_USER, etc. are set as environment
# variables by Docker Compose.
# =============================================================================
set -Eeuo pipefail

DB="${CLICKHOUSE_DATABASE:-clickhouse_rd}"

echo "[init] Creating database ${DB} if not exists..."
clickhouse-client --query "CREATE DATABASE IF NOT EXISTS ${DB} ENGINE = Atomic;"

echo "[init] Creating events_raw table..."
clickhouse-client --query "
CREATE TABLE IF NOT EXISTS ${DB}.events_raw
(
    event_id     UUID,
    tenant_id    UInt32,
    event_time   DateTime64(3, 'UTC'),
    ingested_at  DateTime64(3, 'UTC'),
    event_type   LowCardinality(String),
    value        Float64,
    payload      String
)
ENGINE = MergeTree
PARTITION BY toStartOfHour(event_time)
ORDER BY (tenant_id, event_time, event_type, event_id)
TTL toDateTime(event_time) + INTERVAL 5 MINUTE TO VOLUME 'cold',
    toDateTime(event_time) + INTERVAL 10 MINUTE DELETE
SETTINGS storage_policy = 'hot_cold',
         merge_with_ttl_timeout = 60;
"

echo "[init] Creating tenant_metrics_5m table and MV..."
clickhouse-client --query "
CREATE TABLE IF NOT EXISTS ${DB}.tenant_metrics_5m
(
    hour       DateTime('UTC'),
    tenant_id  UInt32,
    event_type LowCardinality(String),
    event_count AggregateFunction(count),
    value_sum   AggregateFunction(sum, Float64),
    value_min   AggregateFunction(min, Float64),
    value_max   AggregateFunction(max, Float64)
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(hour)
ORDER BY (tenant_id, event_type, hour);
"

clickhouse-client --query "
CREATE MATERIALIZED VIEW IF NOT EXISTS ${DB}.tenant_metrics_5m_mv
TO ${DB}.tenant_metrics_5m
AS
SELECT
    toStartOfHour(event_time) AS hour,
    tenant_id,
    event_type,
    countState()                         AS event_count,
    sumState(value)                      AS value_sum,
    minState(value)                      AS value_min,
    maxState(value)                      AS value_max
FROM ${DB}.events_raw
GROUP BY hour, tenant_id, event_type;
"

clickhouse-client --query "
CREATE OR REPLACE VIEW ${DB}.tenant_metrics_5m_flat
AS
SELECT
    hour,
    tenant_id,
    event_type,
    countMerge(event_count) AS event_count,
    sumMerge(value_sum)     AS value_sum,
    minMerge(value_min)     AS value_min,
    maxMerge(value_max)     AS value_max
FROM ${DB}.tenant_metrics_5m
GROUP BY hour, tenant_id, event_type;
"

echo "[init] Creating tenant_metrics_30m table and MV..."
clickhouse-client --query "
CREATE TABLE IF NOT EXISTS ${DB}.tenant_metrics_30m
(
    day            Date,
    tenant_id      UInt32,
    total_events   UInt64,
    purchase_events UInt64,
    total_value    Float64
)
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(day)
ORDER BY (tenant_id, day);
"

clickhouse-client --query "
CREATE MATERIALIZED VIEW IF NOT EXISTS ${DB}.tenant_metrics_30m_mv
TO ${DB}.tenant_metrics_30m
AS
SELECT
    toDate(event_time)    AS day,
    tenant_id,
    count(*)              AS total_events,
    countIf(event_type = 'purchase') AS purchase_events,
    sum(value)            AS total_value
FROM ${DB}.events_raw
GROUP BY day, tenant_id;
"

echo "[init] Initialization complete."
