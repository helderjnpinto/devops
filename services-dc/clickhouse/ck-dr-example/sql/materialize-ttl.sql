-- =============================================================================
-- clickhouse-rd — Force TTL materialization
-- =============================================================================
-- Triggers TTL evaluation on events_raw to move eligible parts from
-- the hot volume to the cold (s3_cold) volume.
-- CLICKHOUSE_DATABASE is substituted by envsubst at runtime.
-- =============================================================================

ALTER TABLE ${CLICKHOUSE_DATABASE}.events_raw MATERIALIZE TTL;

-- OPTIMIZE FINAL also triggers TTL, but may rewrite more parts than needed.
-- Uncomment below for a more aggressive approach:
-- OPTIMIZE TABLE ${CLICKHOUSE_DATABASE}.events_raw FINAL;
