# Kopia Backup — Restore Test & Verification

Work area for **testing and validating Vaultwarden backups** captured by Kopia
on the server.

> **The Vaultwarden test service was moved** to its own folder:
> [`services-dc/vaultwarden/`](../../vaultwarden/README.md)

---

## Ways to test

| Method | When to use | Where |
|---|---|---|
| **Local restore** (recommended) | Validate in an isolated Vaultwarden on your machine | [`../../vaultwarden/`](../../vaultwarden/README.md) |
| **Server-side validation** | Quick integrity check without downloading | `restore-test.sh` |

---

## ⚠️ About the "encrypted" SQLite data

**This is normal behavior, not a backup problem.**

Vaultwarden **encrypts data at the application level** before storing it in
SQLite. The `db.sqlite3` file is a valid SQLite database, but sensitive fields
(passwords, vaults, etc.) are stored as **ciphertext** (encrypted binary)
using the key derived from the *master password*.

So opening the file in an editor or running `SELECT` shows "garbage" — **it
does not mean the backup is corrupted**.

### Correct validation of a Vaultwarden backup

1. The **file** is valid SQLite → `PRAGMA integrity_check;` = `ok`
2. The **schema** is present → tables `users`, `ciphers`, `folders`, ...
3. **Readable content** = only after starting a Vaultwarden with those files
   and using the real *master password* (the cipher is only undone by the app).

---

## Local restore test (recommended) — 3 steps

1. **Download the files** from the latest snapshot:
   ```bash
   cd ../../vaultwarden
   bash download-backup.sh        # uses ssh + tar stream
   ```
   (or download manually via the Kopia UI → *Snapshots* → *Download*)

2. **Start Vaultwarden** (HTTPS via Caddy on port 18443):
   ```bash
   cd ../../vaultwarden
   docker compose up -d
   ```

3. **Open https://localhost:18443** (accept the self-signed certificate) and
   log in with the real master password.

Full instructions: [`../../vaultwarden/README.md`](../../vaultwarden/README.md)

---

## 🔍 Quick server-side validation (alternative)

```bash
# On the server (via ssh), restores and validates without downloading locally:
ssh ovh "bash -s" < restore-test.sh
```

This:
- restores the latest snapshot to `/tmp` on the server
- runs `PRAGMA integrity_check;` (expected: `ok`)
- lists the tables and counts `users`/`ciphers`

> `restore-test.sh` automatically detects whether to use the `kopia` container
> or a locally installed `kopia` CLI.

---

## Files in this folder

| File | Description |
|---|---|
| [`restore-test.sh`](restore-test.sh) | Quick integrity validation on the server |
| [`../KOPIA_COMMANDS.md`](../KOPIA_COMMANDS.md) | Full Kopia command reference |
| [`../../vaultwarden/`](../../vaultwarden/README.md) | Vaultwarden service (with Caddy/HTTPS) |
