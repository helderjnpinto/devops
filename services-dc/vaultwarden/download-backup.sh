#!/usr/bin/env bash
#
# download-backup.sh — Fetch the latest Vaultwarden snapshot files from the
#                      server (where Kopia runs) into the local ./vw-data
#                      folder (ready for the local Vaultwarden container).
#
# Prerequisites:
#   - SSH access to the server via alias 'ovh' (or change SERVER below)
#   - The 'kopia' container must be running on the server
#
# Usage:
#   bash download-backup.sh
#
set -euo pipefail

SERVER="ovh"                       # ssh alias of the server (change if needed)
KOPIA_SOURCE="/backup/vaultwarden" # source path inside the container
REMOTE_TMP="/tmp/vw-download-$$"   # temp folder on the server
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vw-data"

echo "==> Downloading backup from server ($SERVER) to $LOCAL_DIR"
mkdir -p "$LOCAL_DIR"

echo "==> 1. Restoring latest snapshot on $SERVER:$REMOTE_TMP"
ssh "$SERVER" "docker exec kopia sh -c 'rm -rf $REMOTE_TMP && mkdir -p $REMOTE_TMP' && \
docker exec kopia kopia restore $KOPIA_SOURCE --target $REMOTE_TMP 2>&1 | tail -3"

echo "==> 2. Packing and downloading"
# Stream via tar over ssh to avoid duplicating space on the server
ssh "$SERVER" "cd $REMOTE_TMP && tar czf - ." | tar xzf - -C "$LOCAL_DIR"

echo "==> 3. Cleaning up temp folder on the server"
ssh "$SERVER" "docker exec kopia sh -c 'rm -rf $REMOTE_TMP'"

echo "==> Downloaded content in $LOCAL_DIR:"
ls -la "$LOCAL_DIR" | head -20

echo
echo "==> Done. Start Vaultwarden with:"
echo "    docker compose up -d"
echo "    and open https://localhost:18443 (self-signed certificate)"
