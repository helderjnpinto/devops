# clickhouse-rd — Recalculate Data

A complete, runnable local R&D project demonstrating **ClickHouse hot/cold storage with MinIO**, **incremental materialized views**, **native BACKUP/RESTORE**, and **deterministic aggregate recalculation** from raw data that has moved to cold S3 storage.

**RD = Recalculate Data.**

## Purpose

This repository demonstrates:

1. Retention of tenant event history in a hot/cold ClickHouse `MergeTree` table (`events_raw`).
2. Automatic movement of old table parts from local hot storage to MinIO S3 cold storage using a ClickHouse **TTL move** rule.
3. **Incremental materialized views** that maintain 5-minute and 30-minute TTL aggregate tables (`tenant_metrics_5m`, `tenant_metrics_30m`) as new events arrive.
4. **Deterministic rebuilding of derived aggregates** from `events_raw` — including data that has moved to cold S3 — without duplicating raw rows or double-counting aggregates.
5. **Native ClickHouse `BACKUP` and `RESTORE`** to a dedicated MinIO backup bucket.
6. A **single-node local demonstration** — no replicas, no Keeper, no cluster.

## Architecture

```
                      ┌──────────────────────┐
                      │      events_raw      │
                      │ MergeTree + hot/cold │
                      └──────────┬───────────┘
                                 │ inserts
                    ┌────────────┴────────────┐
                    │                         │
       tenant_metrics_5m MV    tenant_metrics_30m MV
                   │                         │
                   ▼                         ▼
        tenant_metrics_5m        tenant_metrics_30m

events_raw hot parts  ───────────────► local ClickHouse volume
events_raw cold parts ───────────────► MinIO clickhouse-data bucket
native backups        ───────────────► MinIO clickhouse-backups bucket
```

### Storage tiers

| Tier | Location | Purpose |
|------|----------|---------|
| **Hot** | ClickHouse local volume (`default` disk) | Recent data, fast queries |
| **Cold** | MinIO bucket `clickhouse-data` (`s3_cold` disk) | Old data, still queryable via `events_raw` |
| **Backup** | MinIO bucket `clickhouse-backups` (`s3_backup` disk) | Native `BACKUP` / `RESTORE` only |

### Key concepts

- **TTL move** (`toDateTime(event_time) + INTERVAL 5 MINUTE TO VOLUME 'cold'`) makes old parts eligible for migration to S3. This does **not** delete data.
- **Cold data remains queryable** through `events_raw`. ClickHouse reads transparently from both local and S3 disks.
- **S3 cold storage is still live table storage** and is **not** a backup.
- **A delete TTL** (10 minutes) is also configured on `events_raw`. If it fires before recalculation, those rows cannot be recovered.
- **TTL movement is background processing** and may not happen at the exact TTL timestamp. Use `make force-ttl` to accelerate.
- **Materialized views process new inserts only.** Moving existing raw parts from hot to cold does **not** trigger the views again.
- **Recalculation** reads `events_raw` directly and writes to temporary aggregate tables, then uses `ALTER TABLE ... REPLACE PARTITION` to update the real targets without double-counting.

## Prerequisites

- Docker Engine 24+ with Compose v2 plugin
- Bash 4+
- `envsubst` (provided by `gettext` package)
- `curl`, `wget` (available in the ClickHouse image)

## Quick start

```bash
# 1. Clone and configure
cd clickhouse-rd
cp .env.example .env

# 2. Start services
make up

# 3. Seed test data (old + recent events)
make seed

# 4. View aggregates populated by materialized views
make aggregates

# 5. Check storage — all data should be on the 'default' disk
make storage-status

# 6. Force TTL materialization to move old parts to cold S3
make force-ttl
make storage-status

# 7. Verify aggregate consistency
make verify

# 8. Recalculate aggregates for a day (pick one that exists in your data)
make sql QUERY="SELECT DISTINCT toDate(event_time) AS day FROM clickhouse_rd.events_raw ORDER BY day;"
make recalculate-day DATE="$(date -u -d '2 hours ago' +%F)"
make verify

# 9. Create a native backup
make backup

# 10. List backups
make list-backups

# 11. Restore the backup into a separate database
make restore-last
```

## Project structure

```
clickhouse-rd/
├── .env.example              # Environment variable template
├── .gitignore                # Ignore .env, .last-backup, temp files
├── docker-compose.yml        # Services: clickhouse, minio, minio-init
├── Makefile                  # Top-level command interface
├── README.md                 # This file
├── clickhouse/
│   ├── config.d/
│   │   ├── logging.xml       # ClickHouse server logging config
│   │   └── storage.xml       # Disk and storage policy definitions
│   ├── users.d/
│   │   └── local-user.xml    # User credentials (from .env)
│   └── initdb.d/             # First-run scripts (executed alphabetically)
│       └── 000-init.sh       # Shell script: database + tables + MVs (env var substitution)
├── sql/
│   ├── seed-old.sql          # Insert old events (>= 2h ago)
│   ├── seed-hot.sql          # Insert recent events (last 30s)
│   ├── storage-status.sql    # Query system.disks and system.parts
│   ├── aggregate-results.sql # Display MV results
│   ├── verify-aggregates.sql # Compare raw vs MV results
│   └── materialize-ttl.sql   # ALTER TABLE ... MATERIALIZE TTL
└── scripts/
    ├── clickhouse-client.sh  # Client wrapper (reads .env)
    ├── wait-for-services.sh  # Health check loop
    ├── seed.sh               # Execute both seed scripts
    ├── storage-status.sh     # Run storage-status.sql
    ├── force-ttl.sh          # Run materialize-ttl.sql
    ├── recalculate-day.sh    # Rebuild aggregates for one UTC day
    ├── backup.sh             # Native BACKUP to s3_backup
    ├── list-backups.sh       # List backups in MinIO + system.backups
    ├── restore.sh            # RESTORE into separate database
    └── verify.sh             # End-to-end aggregate verification
```

## Makefile reference

| Target | Description |
|--------|-------------|
| `help` | Show this help message |
| `env` | Copy `.env.example` to `.env` |
| `up` | Start services (`docker compose up -d`) |
| `down` | Stop services (preserves volumes) |
| `restart` | Restart services |
| `wait` | Wait for healthy services |
| `shell` | Open interactive `clickhouse-client` |
| `sql QUERY="..."` | Run a one-line SQL query |
| `logs` | Follow service logs |
| `ps` | Show container status |
| `seed` | Insert old + recent test data |
| `seed-old` | Insert old data (>= 2h ago) |
| `seed-hot` | Insert recent data (last 30s) |
| `reset-data` | Truncate `events_raw` and aggregate tables |
| `force-ttl` | Materialize TTL on `events_raw` |
| `storage-status` | Show disk/part distribution |
| `aggregates` | Display aggregate results |
| `verify` | Verify aggregate consistency |
| `recalculate-day DATE=YYYY-MM-DD` | Rebuild aggregates for a day |
| `backup` | Create native database backup |
| `list-backups` | List available backups |
| `restore BACKUP=name` | Restore backup into separate DB |
| `restore-last` | Restore the most recent backup |
| `reset-database` | Drop and recreate the database |
| `clean` | Remove temp files (preserves volumes) |
| `destroy` | ⚠ Stop services and delete all volumes |

## What to observe

### 1. Hot → cold movement

After `make force-ttl` (or waiting for background TTL processing):

- **Old parts** appear under `s3_cold` in `make storage-status`.
- **Recent parts** remain on `default`.
- `SELECT` queries over `events_raw` return **both** hot and cold rows transparently.

### 2. Materialized views cover new inserts

After seeding:

- `make aggregates` shows `tenant_metrics_5m` and `tenant_metrics_30m` summaries.
- The materialized views processed only the inserted rows.
- Moving existing parts to cold S3 does **not** re-trigger the views.

### 3. Recalculation reads cold S3 data

`make recalculate-day DATE=...`:

1. Reads directly from `events_raw` (including cold S3 parts).
2. Aggregates into temporary tables.
3. Replaces corresponding partitions in the real aggregate tables.
4. After completion, `make verify` shows no mismatches.

### 4. Partition replacement prevents double-counting

The recalculation script **replaces** (not appends to) the target partitions. If you recalculate the same day twice, the result is the same — no additive double-counting.

### 5. TTL cascade on events_raw

`events_raw` has two TTL rules that create a visible lifecycle:

| TTL Rule | Effect | Visible after |
|----------|--------|---------------|
| `+ 5 MINUTE TO VOLUME 'cold'` | Parts move from hot (local) → cold (MinIO S3) | ~5 min or `make force-ttl` |
| `+ 10 MINUTE DELETE` | Rows permanently deleted | ~10 min or `make force-ttl` |

**Demonstration sequence** (after fresh seed with the current TTLs):

1. `make storage-status` — all parts on `default` (hot) disk
2. Wait 5 min or `make force-ttl` → `make storage-status` — old parts moved to `s3_cold`
3. `make aggregates` — data still visible from `events_raw` (transparent S3 reads)
4. Wait 10 min or `make force-ttl` → `SELECT count() FROM events_raw` — old rows **permanently deleted**
5. `make recalculate-day DATE=...` — **fails** for the deleted rows (expected behavior)

This demonstrates that S3 cold storage is live table storage (not a backup), and that once the delete TTL fires, the data is gone forever.

### 6. Backups are separate from cold storage

- **Cold storage**: live table parts on `s3_cold` → MinIO `clickhouse-data` bucket.
- **Backups**: native `BACKUP DATABASE` → MinIO `clickhouse-backups` bucket.
- These are **separate concepts** even though both use MinIO.
- Cold storage is **not** a substitute for backups.

## Implementation notes

### Init via shell script (000-init.sh)

The ClickHouse docker entrypoint runs `.sh` files natively but does **not** expand `${VAR}` bash variables inside `.sql` files. This project uses a single [`000-init.sh`](clickhouse/initdb.d/000-init.sh) script that:

1. Receives `CLICKHOUSE_DATABASE` and other env vars from Docker Compose.
2. Uses bash `${DB}` substitution inline to produce valid SQL for the configured database name.
3. Creates all tables and materialized views in a single, ordered script.

This avoids the problem of `.sql` files with unresolvable `${VAR}` references.

### envsubst for runtime SQL

SQL files under `sql/` use `${CLICKHOUSE_DATABASE}` as a **bash env-substitution placeholder**. Shell scripts like [`seed.sh`](scripts/seed.sh), [`storage-status.sh`](scripts/storage-status.sh), and [`verify.sh`](scripts/verify.sh) source `.env` then pipe each SQL file through `envsubst` before passing it to `clickhouse-client`.

The `clickhouse-client.sh` wrapper also passes `--database "${CLICKHOUSE_DATABASE}"` so that bare table references (without a database prefix) resolve to the correct database automatically.

### mc client access

The MinIO `mc` client is used for bucket inspection in `list-backups.sh` and `backup.sh`. Since the `minio-init` container is a one-shot service, these scripts run `mc` through `docker compose run --rm` with the `MC_HOST_*` environment variable for pre-configured credentials — avoiding the need for `mc config add` in short-lived containers.

## MinIO access

| Interface | URL | Default port |
|-----------|-----|-------------|
| **S3 API** | `http://localhost:${MINIO_API_PORT}` | 9002 |
| **Console** | `http://localhost:${MINIO_CONSOLE_PORT}` | 9003 |

Credentials: from `.env` (`MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`).

## Seeding notes

- **Repeated seeding** intentionally adds more events each time. This is by design to let you observe how data accumulates.
- Use `make reset-data` before re-seeding if you want a clean slate. This runs `TRUNCATE TABLE` on all three tables, which **deletes all rows** but keeps the schemas, materialized views, and configuration intact — no restart needed.
- Old seed data uses `event_time` values ~8 minutes in the past — old enough to satisfy the 5-minute cold-storage TTL but NOT old enough to trigger the 10-minute delete TTL. This gives you a ~2-minute window to observe data on the cold tier before it is permanently deleted.
- Recent seed data uses `event_time` values within the last 30 seconds — remains on the `default` (hot) disk.
- **TTL timeline**: After `make seed`, data is distributed across disks. After ~5 minutes, old parts move to `s3_cold` (still queryable). After ~10 minutes, old rows are permanently deleted. Run `make storage-status` immediately after seeding to see both disks populated.

## Backup and restore notes

- Backups are stored on the `s3_backup` disk (MinIO `clickhouse-backups` bucket).
- Each backup has a UTC-timestamped name: `clickhouse-rd-20260716T153000Z`.
- The most recent backup name is saved to `.last-backup` (gitignored).
- Restore creates a **separate database** (default: `clickhouse_rd_restored`) to avoid overwriting the active database.
- Raw data in the S3 cold tier and ClickHouse backups are **separate concepts** even though both are stored in MinIO.

## Recalculation safety

The recalculation procedure (`make recalculate-day`) uses `ALTER TABLE ... REPLACE PARTITION ... FROM ...` to swap in rebuilt aggregate data. This is safe for a local demonstration where there are no concurrent inserts for the target historical day.

**Production caveats:**

- Production recalculation requires a checkpoint or controlled write strategy to avoid losing late-arriving events during partition replacement.
- Consider using a staging table and atomic swap pattern for production workloads.

## Limitations

- **Single ClickHouse node** — no replicas, no Keeper.
- **Local development credentials** — not suitable for production.
- **Minute-level TTLs** (5-minute move to cold, 10-minute delete) are for demonstration only. Production TTLs are typically days. The short windows let you observe the full hot → cold → deleted lifecycle within minutes.
- **Delete TTL may clean data before you observe it.** If the 10-minute delete TTL on `events_raw` fires before recalculation or verification, those rows are permanently gone. Run `make seed` and then immediately `make aggregates` / `make force-ttl` / `make verify` to complete the full workflow before the delete TTL expires.
- **Hourly raw partitions** (`PARTITION BY toStartOfHour`) are unusually granular and are used only for this small local demonstration. Do not automatically copy this into production.
- **Forced `OPTIMIZE FINAL`** should not be treated as a routine production operation.
- **Production S3** should use TLS (HTTPS) and workload or instance credentials.
- **Production backfills** need checkpointing and late-event handling.
- **Replication is not a substitute for backups.**
- **S3 cold storage is not itself a backup.**

## Environment variables

See [`.env.example`](.env.example) for the full list. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLICKHOUSE_VERSION` | `25.3` | Pinned ClickHouse image tag |
| `MINIO_VERSION` | `RELEASE.2025-01-20T14-49-07Z` | Pinned MinIO image tag |
| `MINIO_MC_VERSION` | `RELEASE.2025-01-17T23-25-50Z` | Pinned MinIO client image tag |
| `CLICKHOUSE_DATABASE` | `clickhouse_rd` | Database name |
| `CLICKHOUSE_USER` | `rd_user` | ClickHouse user |
| `CLICKHOUSE_PASSWORD` | `rd_local_password` | ClickHouse password |
| `CLICKHOUSE_HTTP_PORT` | `8123` | ClickHouse HTTP port (host) |
| `CLICKHOUSE_NATIVE_PORT` | `9004` | ClickHouse native port (host) |
| `MINIO_ROOT_USER` | `minioadmin` | MinIO root access key |
| `MINIO_ROOT_PASSWORD` | `minioadmin123` | MinIO root secret key |
| `MINIO_API_PORT` | `9002` | MinIO S3 API port (host) |
| `MINIO_CONSOLE_PORT` | `9003` | MinIO web console port (host) |
| `MINIO_DATA_BUCKET` | `clickhouse-data` | MinIO bucket for cold table parts |
| `MINIO_BACKUP_BUCKET` | `clickhouse-backups` | MinIO bucket for native backups |

## Version decisions

- **ClickHouse 25.3**: Stable release with full support for S3-backed storage, `BACKUP`/`RESTORE` to `s3_plain` disks, `MATERIALIZE TTL`, and `AggregatingMergeTree` with aggregate-state functions.
- **MinIO RELEASE.2025-01-20**: Compatible S3 implementation with no gateway dependencies.
- **Alpine-based images** chosen for smaller footprint in local development.
- Image versions are **pinned** in `.env.example` — no `latest` tag anywhere.
