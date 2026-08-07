#!/usr/bin/env bash
#
# backup-vault.sh — Multi-variant backup of Vaultwarden with Kopia
#
# Goal: because Vaultwarden uses SQLite in WAL mode, a single hot snapshot can
# (rarely) catch an inconsistent state. This script takes SEVERAL variants; the
# probability that at least one is consistent is high, and the sqlite3 variant
# is guaranteed consistent.
#
# Variants:
#   1. sqlite3 .backup  -> consistent backup via SQLite Online Backup API
#   2. direct-N         -> N snapshots of the live directory, time-spaced
#   3. verify           -> SQLite integrity of each variant (if sqlite3 exists)
#
# Usage:
#   ./backup-vault.sh [NUM_VARIANTS]
#
set -euo pipefail

NUM_VARIANTS="${1:-5}"          # how many "direct" snapshots to take
TARGET="/backup/vaultwarden"    # path inside the Kopia container
DB_FILE="db.sqlite3"
STAGE_DIR="/tmp/vw-consolidated"
TSTAMP="$(date +%Y%m%d-%H%M%S)"

echo "==> Multi-variant Vaultwarden backup ($TSTAMP)"

# ---------------------------------------------------------------------------
# 0. Basic checks
# ---------------------------------------------------------------------------
if ! docker exec kopia kopia repository status >/dev/null 2>&1; then
    echo "ERROR: Kopia repository is not connected." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. CONSISTENT VARIANT: sqlite3 .backup (Online Backup API)
#    Copies the DB to a temporary file INSIDE the volume, atomically and
#    consistently, then snapshots that file.
# ---------------------------------------------------------------------------
echo "==> [1/N] sqlite3 variant (guaranteed consistent)"
docker exec kopia sh -c "
    set -e
    if command -v sqlite3 >/dev/null 2>&1; then
        mkdir -p '$STAGE_DIR'
        sqlite3 '$TARGET/$DB_FILE' \".backup '$STAGE_DIR/$DB_FILE.$TSTAMP'\" 2>/dev/null || exit 9
        echo '   sqlite3 available: consistent file created in $STAGE_DIR'
    else
        echo '   sqlite3 NOT available in the container — skipping consistent variant'
        exit 8
    fi
"
SQLITE_RC=$?

if [ "$SQLITE_RC" -eq 0 ]; then
    docker exec kopia kopia snapshot create "$STAGE_DIR" \
        --tags="variant=sqlite3,backup=$TSTAMP" \
        --description "Vaultwarden SQLite consistent backup $TSTAMP" 2>&1 | tail -3
fi

# ---------------------------------------------------------------------------
# 2. DIRECT VARIANTS: N snapshots of the live directory, time-spaced
# ---------------------------------------------------------------------------
for i in $(seq 1 "$NUM_VARIANTS"); do
    echo "==> [2/N] direct variant $i/$NUM_VARIANTS"
    docker exec kopia kopia snapshot create "$TARGET" \
        --tags="variant=direct$i,backup=$TSTAMP" \
        --description "Vaultwarden live snapshot attempt $i/$NUM_VARIANTS" 2>&1 | tail -2
    if [ "$i" -lt "$NUM_VARIANTS" ]; then
        sleep 15   # spacing between attempts to capture distinct states
    fi
done

# ---------------------------------------------------------------------------
# 3. VERIFICATION: SQLite integrity of each snapshot (if sqlite3 exists)
# ---------------------------------------------------------------------------
if docker exec kopia sh -c 'command -v sqlite3 >/dev/null 2>&1'; then
    echo "==> [3] Verifying SQLite integrity of direct variants..."
    # Restore the latest snapshot of each tag to tmp and check
    for i in $(seq 1 "$NUM_VARIANTS"); do
        SNAP_ID=$(docker exec kopia kopia snapshot list "$TARGET" --tags="variant=direct$i" --json 2>/dev/null \
                  | grep -oE '"id":"[a-f0-9]+"' | head -1 | sed 's/.*:"//;s/"//')
        if [ -n "$SNAP_ID" ]; then
            docker exec kopia sh -c "rm -rf /tmp/vw-check && mkdir -p /tmp/vw-check"
            docker exec kopia kopia restore "$SNAP_ID" /tmp/vw-check >/dev/null 2>&1
            RESULT=$(docker exec kopia sh -c "sqlite3 /tmp/vw-check/$DB_FILE 'PRAGMA integrity_check;' 2>/dev/null | head -1")
            echo "   direct-$i: integrity = ${RESULT:-FAILED}"
        fi
    done
fi

echo "==> Backup finished: $((NUM_VARIANTS + SQLITE_RC == 0 ? 1 : 0)) variants created."
echo "    View the snapshots in the UI:  http://<server-ip>:51515/ (Snapshots)"
