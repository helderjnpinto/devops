# OpenObserve Monitoring

This document provides monitoring commands and procedures for the OpenObserve instance.

## Disk Usage Monitoring

Check the current disk usage of OpenObserve data:

```bash
# Check disk usage
du -sh ~/home/hp/projects/hp/devops~/services-dc/openobserver/data/
```

## Compaction Monitoring

Monitor the compaction process to ensure data retention is working properly:

```bash
# Monitor compaction logs
docker logs openobserve | grep -i compact
```

## Retention Settings Verification

Verify that the data retention settings are correctly configured:

```bash
# Check retention settings
curl -X GET "http://localhost:5080/api/default/settings" \
  -u admin@example.com:StrongPassword123!
```

## Expected Storage with 5-Day Retention

| Cluster Size | Daily Volume | 5-Day SQLite | 5-Day PostgreSQL |
|-------------|--------------|--------------|------------------|
| Small (10-20 pods) | 1-3 GB | 7-15 GB | 10-20 GB |
| Medium (20-50 pods) | 3-8 GB | 15-40 GB | 20-60 GB |

## Configuration Summary

Current retention configuration:

- **Data Retention**: 5 days (`ZO_COMPACT_DATA_RETENTION_DAYS=5`)
- **Compaction Interval**: 600 seconds (`ZO_COMPACT_INTERVAL=600`)
- **Storage**: SQLite (default)

## When to Consider PostgreSQL

Switch to PostgreSQL if:

- Database size exceeds 15GB
- Query performance degrades
- Frequent container restarts due to I/O
- Planning for production use
