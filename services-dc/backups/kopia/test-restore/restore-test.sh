#!/usr/bin/env bash
#
# restore-test.sh — Restores the latest Vaultwarden snapshot and validates the
#                   integrity of the restored SQLite database.
#
# NOTE: Kopia is not installed locally (dev machine); the repository lives on
# the server. This script can be run:
#   - ON THE SERVER (where the kopia container exists), or
#   - ON THE DEV HOST if `kopia` is installed and connected to S3.
#
# Usage (on the server, via ssh):
#   ssh ovh "bash -s" < restore-test.sh
#
# Usage (local, if kopia is installed and the repo is connected):
#   ./restore-test.sh
#
set -euo pipefail

SOURCE="/backup/vaultwarden"
RESTORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/restored"
DB_FILE="db.sqlite3"

# ---------------------------------------------------------------------------
# Detect where we run: host with the kopia container, or local
# ---------------------------------------------------------------------------
run_kopia() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^kopia$'; then
        docker exec kopia kopia "$@"
    elif command -v kopia >/dev/null 2>&1; then
        kopia "$@"
    else
        echo "ERROR: neither the kopia container nor the kopia CLI is available." >&2
        echo "Run this script on the server (ssh ovh) or install kopia locally." >&2
        exit 1
    fi
}

run_sqlite() {
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^kopia$'; then
        docker exec kopia sqlite3 "$@"
    elif command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$@"
    else
        echo "ERROR: sqlite3 is not available." >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# 1. List available snapshots
# ---------------------------------------------------------------------------
echo "==> Available snapshots for '$SOURCE':"
run_kopia snapshot list "$SOURCE"

# ---------------------------------------------------------------------------
# 2. Restore the latest snapshot
# ---------------------------------------------------------------------------
echo
echo "==> Restoring the latest snapshot to $RESTORE_DIR"
mkdir -p "$RESTORE_DIR"
run_kopia restore "$SOURCE" --target "$RESTORE_DIR"

echo
echo "==> Restored content:"
ls -la "$RESTORE_DIR"

# ---------------------------------------------------------------------------
# 3. Validate SQLite integrity
# ---------------------------------------------------------------------------
echo
echo "==> Validating '$DB_FILE'..."
if [ ! -f "$RESTORE_DIR/$DB_FILE" ]; then
    echo "ERROR: $DB_FILE not found in the restore." >&2
    exit 1
fi

echo "--- integrity_check ---"
run_sqlite "$RESTORE_DIR/$DB_FILE" 'PRAGMA integrity_check;'

echo "--- tables (schema) ---"
run_sqlite "$RESTORE_DIR/$DB_FILE" '.tables'

echo "--- ciphers count (vaults) ---"
run_sqlite "$RESTORE_DIR/$DB_FILE" 'SELECT COUNT(*) AS total_ciphers FROM ciphers;' 2>/dev/null \
    || echo "('ciphers' table not found — older schema version?)"

echo "--- users count ---"
run_sqlite "$RESTORE_DIR/$DB_FILE" 'SELECT COUNT(*) AS total_users FROM users;' 2>/dev/null \
    || echo "('users' table not found)"

echo
echo "==> Test finished."
echo "    If 'integrity_check' = 'ok' and the tables exist, the backup is VALID."
echo "    Reminder: values appear encrypted — that is normal (Vaultwarden cipher)."
