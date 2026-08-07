# Kopia Command Reference

A practical, topic-organized reference for managing the Kopia backup server
running in Docker at `services-dc/backups/kopia`.

> **Environment note:** The Kopia server runs inside the `kopia` container.
> Most commands are executed with `docker exec kopia kopia ...`. Example:
> `ssh ovh "docker exec kopia kopia repository status"`

---

## Table of Contents

1. [Repository (S3)](#1-repository-s3)
2. [Server & UI](#2-server--ui)
3. [Users & Access Control](#3-users--access-control)
4. [Snapshots (Backups)](#4-snapshots-backups)
5. [Policies (Retention & Scheduling)](#5-policies-retention--scheduling)
6. [Actions (Hooks / Discord Notifications)](#6-actions-hooks--discord-notifications)
7. [Restore (Recovery)](#7-restore-recovery)
8. [Maintenance & Health](#8-maintenance--health)
9. [Inspection & Diagnostics](#9-inspection--diagnostics)

---

## 1. Repository (S3)

| Topic | Command |
|---|---|
| Show repository status | `docker exec kopia kopia repository status` |
| Show repository details (incl. `enableActions`) | `docker exec kopia kopia repository status --json` |
| Connect to existing S3 repository | `docker exec kopia kopia repository connect s3 --bucket=BUCKET --endpoint=s3.amazonaws.com --region=eu-west-2 --access-key=AKIA... --secret-access-key=... --enable-actions` |
| Connect **without** actions | `docker exec kopia kopia repository connect s3 --bucket=BUCKET ... --no-enable-actions` |
| Show the repo config file | `docker exec kopia cat /app/config/repository.config` |
| Set repository parameters | `docker exec kopia kopia repository set-parameters --max-pack-size-mb=...` |

> **Notes:**
> - `--enable-actions` is **critical**: if omitted, `enableActions` is stored
>   as `false` in the config and **no snapshot action will ever run**
>   (the log shows *"disabled for this client"*).
> - The config file lives at `/app/config/repository.config` inside the
>   container (bind-mounted to `./config/repository.config` on the host).
> - Current repo: `s3://<your-bucket>`, region `<region>`, endpoint `s3.amazonaws.com`.

---

## 2. Server & UI

| Topic | Command |
|---|---|
| Start server (UI) | `docker exec kopia kopia server start --insecure --address=0.0.0.0:51515 --server-username=admin --server-password=PASSWORD` |
| List sources known to the server | `docker exec kopia kopia source list` |
| Refresh server credentials/cache (after user changes) | `docker exec kopia kopia server refresh` |
| Show server status | `docker exec kopia kopia server status` |
| Container lifecycle | `docker compose up -d` / `docker compose down` / `docker compose restart kopia` |
| View server logs | `docker logs kopia --tail 100` / `docker compose logs -f kopia` |

> **Notes:**
> - In recent Kopia versions (0.12+), `--server-username`/`--server-password`
>   only authenticate the UI setup flow. User accounts are stored **in the
>   repository** and managed with `kopia server user` (see section 3).
> - After adding/changing users, run `kopia server refresh` or restart the
>   container — changes take effect in 5–10 minutes otherwise.
> - If the UI shows *"Repository not configured"*, the repository was never
>   created or the config volume was wiped — complete the setup wizard or
>   connect the repository with section 1 commands.

---

## 3. Users & Access Control

| Topic | Command |
|---|---|
| Add a user | `docker exec kopia kopia server user add admin@myserver` |
| List users | `docker exec kopia kopia server users list` |
| List users (JSON) | `docker exec kopia kopia server users list --json` |
| Change user password | `docker exec kopia kopia server user set admin@myserver` |
| Delete a user | `docker exec kopia kopia server user delete admin@myserver` |
| Enable ACLs (fine-grained access) | `docker exec kopia kopia server acl enable` |
| Add ACL rule | `docker exec kopia kopia server acl add --user=... --target=... --access=...` |

> **Notes:**
> - Users are identified as `username@hostname`.
> - Without ACLs, authenticated users have broad access (manage their own
>   snapshots and policies, read global policy, write content).
> - The Vaultwarden snapshots are created as `root@<container-hostname>`
>   because the server runs as `root` — this is expected and does not block
>   the `admin` UI user from viewing them.

---

## 4. Snapshots (Backups)

| Topic | Command |
|---|---|
| Create a snapshot (manual) | `docker exec kopia kopia snapshot create /backup/vaultwarden` |
| Create with description | `docker exec kopia kopia snapshot create /backup/vaultwarden --description "weekly full"` |
| Create with tags | `docker exec kopia kopia snapshot create /backup/vaultwarden --tags="env=prod,variant=direct"` |
| List all snapshots | `docker exec kopia kopia snapshot list --all` |
| List snapshots for a path | `docker exec kopia kopia snapshot list /backup/vaultwarden` |
| List snapshots (JSON) | `docker exec kopia kopia snapshot list --all --json` |
| Show snapshot stats | `docker exec kopia kopia snapshot stats /backup/vaultwarden` |
| Delete a snapshot | `docker exec kopia kopia snapshot delete SNAPSHOT_ID` |
| Trigger scheduled/instant snapshot via UI | UI → *Snapshots* → *Snapshot Now* |

> **Notes:**
> - Scheduled snapshots (e.g. every 6h) are created by the **server**
>   automatically — no cron needed.
> - `kopia snapshot list --all` groups identical snapshots (e.g.
>   `+ 4 identical snapshots`) to save space — deduplication is automatic.
> - Manual CLI snapshots run actions **only if** the repo was connected with
>   `--enable-actions` (see section 1).

---

## 5. Policies (Retention & Scheduling)

| Topic | Command |
|---|---|
| Set retention + schedule for a path | `docker exec kopia kopia policy set /backup/vaultwarden --keep-latest=7 --keep-hourly=24 --keep-daily=7 --keep-weekly=4 --keep-monthly=12 --snapshot-interval=6h` |
| Show policy for a path | `docker exec kopia kopia policy show /backup/vaultwarden` |
| Show global policy | `docker exec kopia kopia policy show --global` |
| List all policies | `docker exec kopia kopia policy list` |
| Set schedule only | `docker exec kopia kopia policy set /backup/vaultwarden --snapshot-interval=12h` |
| Set retention only | `docker exec kopia kopia policy set /backup/vaultwarden --keep-latest=7 --keep-daily=7 --keep-weekly=4 --keep-monthly=6` |
| Set global retention | `docker exec kopia kopia policy set --global --keep-daily=7 --keep-weekly=4` |
| Compression policy | `docker exec kopia kopia policy set /backup/vaultwarden --compression=zstd` |
| Ignore patterns (files) | `docker exec kopia kopia policy set /backup/vaultwarden --add-ignore "*.tmp"` |
| Remove a policy override | `docker exec kopia kopia policy remove /backup/vaultwarden` |

> **Notes:**
> - Retention keeps the **newest N** snapshots of each age bucket; older ones
>   are pruned automatically.
> - A sensible light setup: `--keep-latest=7 --keep-daily=7 --keep-weekly=4
>   --keep-monthly=6 --snapshot-interval=12h` (12h interval, ~6 months).
> - The **Policies page in the UI only shows the global policy by default** —
>   you must type the path (e.g. `/backup/vaultwarden`) in the search box to
>   see a per-directory policy. Server cache may require a container restart
>   to show newly-created policies.

---

## 6. Actions (Hooks / Discord Notifications)

| Topic | Command |
|---|---|
| Register global after-snapshot action | `docker exec kopia kopia policy set --global --after-snapshot-root-action /app/config/scripts/discord-alert.sh` |
| Register action for a path | `docker exec kopia kopia policy set /backup/vaultwarden --after-snapshot-root-action /app/config/scripts/discord-alert.sh` |
| Register before-snapshot action | `docker exec kopia kopia policy set --global --before-snapshot-root-action /app/config/scripts/pre-backup.sh` |
| Show action in policy | `docker exec kopia kopia policy show --global` (see *Actions* section) |
| Remove action | `docker exec kopia kopia policy set --global --no-after-snapshot-root-action` |
| Test the Discord script (simulated) | `docker exec kopia sh -c 'KOPIA_ACTION=after-snapshot-root KOPIA_SNAPSHOT_DESCRIPTION=/tmp/d KOPIA_SNAPSHOT_SIZE=/tmp/s KOPIA_SNAPSHOT_END_TIME=/tmp/e bash /app/config/scripts/discord-alert.sh'` |

> **Notes:**
> - **`enableActions` must be `true`** in the repo config or nothing runs
>   (log: *"disabled for this client"*). Fix: edit
>   `/app/config/repository.config` → `"enableActions": true` and restart, or
>   re-connect with `--enable-actions`.
> - The Discord webhook needs **JSON payloads** (`{"content":"..."}`); raw
>   text returns HTTP 400. The provided
>   [`discord-alert.sh`](config/scripts/discord-alert.sh) handles this.
> - `KOPIA_SNAPSHOT_DESCRIPTION`, `KOPIA_SNAPSHOT_SIZE`,
>   `KOPIA_SNAPSHOT_ERROR`, etc. are **file paths**, not strings — read them
>   with `cat`. See the script for the full list of env vars.

---

## 7. Restore (Recovery)

| Topic | Command |
|---|---|
| Restore latest snapshot of a path | `docker exec kopia kopia restore /backup/vaultwarden --target /tmp/restore` |
| Restore a specific snapshot | `docker exec kopia kopia restore SNAPSHOT_ID --target /tmp/restore` |
| Restore a single file | `docker exec kopia kopia restore SNAPSHOT_ID:/path/to/file --target /tmp/restore` |
| Mount a snapshot (FUSE, read-only) | `docker exec kopia kopia mount SNAPSHOT_ID /tmp/mnt` |
| List files in a snapshot | `docker exec kopia kopia ls SNAPSHOT_ID` |
| Find a file across snapshots | `docker exec kopia kopia find /backup/vaultwarden --file-pattern "db.sqlite3"` |

> **Notes:**
> - `kopia restore` with no snapshot ID restores the **latest** snapshot of
>   the given path.
> - Restoring to the same machine: be careful not to overwrite the live data
>   directory; restore to a temporary target first and validate with
>   `sqlite3 /tmp/restore/db.sqlite3 'PRAGMA integrity_check;'`.

---

## 8. Maintenance & Health

| Topic | Command |
|---|---|
| Check repository health | `docker exec kopia kopia repository verify` |
| Repair/check manifest consistency | `docker exec kopia kopia repository repair` |
| Flush pending writes | `docker exec kopia kopia flush` |
| Run maintenance (auto, usually on) | `docker exec kopia kopia maintenance run --full` |
| Show maintenance info | `docker exec kopia kopia maintenance info` |
| Cleanup old blobs/cache | `docker exec kopia kopia repository cleanup` |
| Set content policy (deletion) | `docker exec kopia kopia content policy set --delete` |
| Check cache stats | `docker exec kopia kopia cache info` |

> **Notes:**
> - `kopia repository verify` is read-only and safe to run anytime; it checks
>   for corrupted or missing data.
> - Automatic maintenance runs by default; `--full` forces a complete pass.

---

## 9. Inspection & Diagnostics

| Topic | Command |
|---|---|
| Show version | `docker exec kopia kopia --version` |
| Global CLI help | `docker exec kopia kopia --help` |
| Command-specific help | `docker exec kopia kopia snapshot create --help` |
| Show repository stats / usage | `docker exec kopia kopia repository status` |
| List blobs in the repository | `docker exec kopia kopia blob list` |
| Show content object stats | `docker exec kopia kopia content list` |
| Show recent server log lines | `docker logs kopia --tail 50` |

> **Notes:**
> - `kopia blob list` reads from the configured storage (S3) — useful to
>   verify what actually lives in the bucket.
> - `docker exec` commands must be run from the host (or via your SSH alias,
>   e.g. `ssh ovh "docker exec kopia ..."`).

---

## Quick reference — current production setup

| Setting | Value |
|---|---|
| Server URL | `http://<server-ip>:51515/` |
| UI user | `admin` |
| Repository | `s3://<your-bucket>` |
| Backup source | `<path>/vw-data` → `/backup/vaultwarden` (`:ro`) |
| Snapshot interval | `6h` |
| Retention | latest=7, hourly=24, daily=7, weekly=4, monthly=12 |
| Discord action | `/app/config/scripts/discord-alert.sh` (after-snapshot-root) |
| `enableActions` | `true` |
