-- =============================================================================
-- clickhouse-rd — Storage status report
-- =============================================================================
-- Shows configured disks, part distribution across disks, and row counts.
-- CLICKHOUSE_DATABASE is substituted by envsubst at runtime.
-- =============================================================================

-- 1. Configured disks
SELECT '--- DISKS ---' AS section;
SELECT name, path, type
FROM system.disks
ORDER BY name;

-- 2. events_raw parts grouped by disk_name
SELECT '--- PARTS PER DISK ---' AS section;
SELECT
    disk_name,
    count()                                 AS part_count,
    sum(rows)                               AS total_rows,
    formatReadableSize(sum(bytes_on_disk))  AS compressed_size,
    min(partition_id)                       AS min_partition,
    max(partition_id)                       AS max_partition
FROM system.parts
WHERE database = '${CLICKHOUSE_DATABASE}'
  AND table = 'events_raw'
  AND active = 1
GROUP BY disk_name
ORDER BY disk_name;

-- 3. All active events_raw parts with details
SELECT '--- PART DETAILS ---' AS section;
SELECT
    name              AS part_name,
    partition_id,
    disk_name,
    rows,
    formatReadableSize(bytes_on_disk) AS size,
    min_time,
    max_time
FROM system.parts
WHERE database = '${CLICKHOUSE_DATABASE}'
  AND table = 'events_raw'
  AND active = 1
ORDER BY partition_id, part_name;

-- 4. Total raw row count
SELECT '--- TOTAL RAW ROWS ---' AS section;
SELECT count() AS total_rows FROM ${CLICKHOUSE_DATABASE}.events_raw;

-- 5. Min/Max event_time
SELECT '--- EVENT TIME RANGE ---' AS section;
SELECT
    min(event_time) AS oldest_event,
    max(event_time) AS newest_event
FROM ${CLICKHOUSE_DATABASE}.events_raw;
