#!/bin/bash
#
# discord-alert.sh — Send Kopia snapshot notifications to Discord via webhook
#
# CRITICAL NOTE: Kopia passes variable contents through TEMPORARY FILES, not
# as direct strings. Therefore:
#   - KOPIA_SNAPSHOT_DESCRIPTION -> path to a file with the description
#   - KOPIA_SNAPSHOT_SIZE        -> path to a file with the size
#   - KOPIA_SNAPSHOT_ERROR       -> path to a file with the error (if any)
#   - KOPIA_SNAPSHOT_START_TIME  -> path to a file with the start time
#   - KOPIA_SNAPSHOT_END_TIME    -> path to a file with the end time
#   - KOPIA_ACTION               -> string: "after-snapshot-root", etc.
#
# Put your Discord webhook URL below.
DISCORD_URL="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL_HERE"

# ---------------------------------------------------------------- helpers ---
read_file() {
    # Returns the content of a file, or an empty string if it does not exist.
    local f="$1"
    if [ -n "$f" ] && [ -f "$f" ]; then
        cat "$f"
    fi
}

json_escape() {
    # Escapes text to be safe inside a JSON string.
    printf '%s' "$1" \
        | sed -e 's/\\/\\\\/g' \
              -e 's/"/\\"/g' \
              -e 's/\r//g'
}

# ------------------------------------------------------------ build msg ---
MESSAGE=""

if [ "$KOPIA_ACTION" = "after-snapshot-root" ]; then
    ERROR="$(read_file "$KOPIA_SNAPSHOT_ERROR")"

    if [ -n "$ERROR" ]; then
        # Snapshot failure
        MESSAGE="❌ **ALERT: Kopia backup failed**\nError: $(json_escape "$ERROR")"
    else
        # Success — include details if available
        DESC="$(read_file "$KOPIA_SNAPSHOT_DESCRIPTION")"
        SIZE="$(read_file "$KOPIA_SNAPSHOT_SIZE")"
        END="$(read_file "$KOPIA_SNAPSHOT_END_TIME")"

        DETAILS="✅ **Kopia backup completed**"
        [ -n "$DESC" ] && DETAILS="$DETAILS\n**Source:** $DESC"
        [ -n "$SIZE" ] && DETAILS="$DETAILS\n**Size:** $SIZE bytes"
        [ -n "$END" ]  && DETAILS="$DETAILS\n**Completed:** $END"

        MESSAGE="$DETAILS"
    fi
else
    MESSAGE="🔄 **Kopia**: action '$KOPIA_ACTION' executed."
fi

# --------------------------------------------------------- send (JSON) ---
if [ -z "$MESSAGE" ]; then
    exit 0
fi

# Discord requires structured JSON {"content": "..."}; plain text = error 400.
PAYLOAD=$(printf '{"content":"%s"}' "$(json_escape "$MESSAGE")")

curl -sS -H "Content-Type: application/json" \
     -X POST \
     -d "$PAYLOAD" \
     "$DISCORD_URL"
