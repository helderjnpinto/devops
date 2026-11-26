# GrowthBook (local test)

Self-hosted GrowthBook + MongoDB via Docker Compose. Docs: https://docs.growthbook.io/self-host

## Run
```bash
docker compose up -d
docker compose logs -f growthbook
```
- UI: http://localhost:3000 (create the first account on first visit)
- API: http://localhost:3100

## Config
Edit `.env` (ports, Mongo credentials, `JWT_SECRET`, `ENCRYPTION_KEY`). Values are for local testing only.
`APP_ORIGIN` / `API_HOST` must match the URLs you use in the browser.

## Stop / reset
```bash
docker compose down        # keep data
docker compose down -v     # wipe Mongo + uploads
```
