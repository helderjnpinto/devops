# Vaultwarden (self-hosted Bitwarden)

Vaultwarden service in Docker Compose, with a **Caddy** reverse proxy for HTTPS.

> The Vaultwarden web vault uses the **Web Crypto API**, which **requires
> HTTPS**. Traffic always goes through Caddy — never access Vaultwarden
> directly over plain HTTP.

---

## Structure

```
services-dc/vaultwarden/
├── docker-compose.yml     # Vaultwarden + Caddy
├── Caddyfile              # HTTPS reverse proxy (local or production)
├── README.md
├── .env.example           # configuration (copy to .env)
├── vw-data/               # Vaultwarden data (db.sqlite3, attachments, ...)
├── backups/               # Vaultwarden backups (optional)
└── download-backup.sh     # fetch backup files from the Kopia server
```

---

## Start

### Local testing (self-signed HTTPS)

```bash
cp .env.example .env        # adjust if needed
docker compose up -d
```

Open: **https://localhost:18443**

The browser warns that the certificate is self-signed (normal for local
testing) → **Advanced → Proceed to localhost (unsafe)**.

### Production (real domain + Let's Encrypt)

1. In [`docker-compose.yml`](docker-compose.yml): uncomment the `443:443` and
   `80:80` ports (and comment out the test ports `18443`/`18480`).
2. In [`Caddyfile`](Caddyfile): uncomment the `https://vault.yourdomain.com`
   block (and comment out the `https://localhost` block) — adjust the domain.
3. Set `DOMAIN` in `.env`/compose to `https://vault.yourdomain.com`.
4. `docker compose up -d` — Caddy obtains the Let's Encrypt certificate
   automatically.

---

## Configuration (environment variables)

| Variable | Example | Description |
|---|---|---|
| `DOMAIN` | `https://vault.yourdomain.com` | Public URL (used by the web vault) |
| `ADMIN_TOKEN` | `openssl rand -base64 48` | Access to the `/admin` panel |
| `WEBSOCKET_ENABLED` | `true` | Real-time sync (clients) |
| `SIGNUPS_ALLOWED` | `false` | Block public signup |
| `TZ` | `Europe/Lisbon` | Timezone |

> Generate an admin token with: `openssl rand -base64 48`

---

## Test a backup restore

The backup is captured by Kopia on the server (see
[`../backups/kopia/`](../backups/kopia/KOPIA_COMMANDS.md)). To test a restore
locally:

```bash
bash download-backup.sh     # fetch the latest snapshot from the server (ssh)
docker compose up -d
# open https://localhost:18443 and log in with the master password
```

---

## Security notes

- **Never** expose Vaultwarden over plain HTTP (the web vault will not work).
- Generate a strong `ADMIN_TOKEN` and keep `SIGNUPS_ALLOWED=false`.
- Data lives in `vw-data/` — include this folder in your backups (Kopia
  already captures it via `/backup/vaultwarden`).
- For testing, the self-signed certificate is enough; for production use the
  Caddy Let's Encrypt mode.
