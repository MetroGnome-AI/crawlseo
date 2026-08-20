# CrawlSEO on HAL — Setup Notes

Last verified: 2026-07-26. Deployed 2026-07-23/24; healthcheck + MCP DB access fixed 2026-07-26.

## What is running

| Container | Image | Status | Ports (host -> container) |
|---|---|---|---|
| crawlseo-app-1 | built from ./Dockerfile (Next.js 16 standalone) | healthy | 0.0.0.0:3200 -> 3000 |
| crawlseo-db-1 | postgres:16-alpine | healthy | 127.0.0.1:5433 -> 5432 (loopback only) |

- App URL: http://100.125.124.117:3200 (HAL tailnet IP) or http://localhost:3200 on HAL.
  The app listens on 0.0.0.0:3200, but HAL is firewalled and reachable only via
  tailnet/WireGuard, so this is not publicly exposed.
- Port 3000 is flow-dashboard, 5432 (loopback) is onecli-postgres — do not reuse either.
- DB data lives in the `crawlseo_db_data` docker volume.
- Migrations: 5 Prisma migrations, applied automatically by the app container at
  startup (`npx prisma@6.19.3 migrate deploy` in the Dockerfile CMD). Currently
  "No pending migrations to apply."

## Config layout

- `.env` — all secrets (Postgres creds, APP_SECRET, NEXTAUTH_SECRET, Google OAuth
  client, DATABASE_URL for host-side tools). Never print this file.
- `docker-compose.override.yml` — local port remap (3200), healthcheck fix,
  loopback publish of Postgres on 5433 for the MCP server.
- Local commits on top of upstream (github.com/crawlseo/crawlseo @ 2662a5a):
  prisma CLI pin in Dockerfile CMD, build-stage env placeholders.
- Note: inside compose, the app gets DATABASE_URL pointing at `db:5432` from
  docker-compose.yml `environment:` (which overrides `.env`). The DATABASE_URL
  in `.env` (127.0.0.1:5433) is only used by host-side tools (MCP server, prisma CLI).

## Google OAuth — DONE

Credentials are already installed in `.env` and working: one Google account is
linked (provider row in the Account table), one site is registered
(chillxchillers.com) and GSC data synced on 2026-07-24. Nothing pending here.

### If credentials ever need to be recreated/rotated (reference)

1. Go to https://console.cloud.google.com/ and select (or create) the project.
2. APIs & Services -> Library -> enable **Google Search Console API**.
3. APIs & Services -> Credentials -> Create Credentials -> **OAuth client ID**,
   application type **Web application**.
4. Authorized redirect URI (must match exactly):
   - `http://100.125.124.117:3200/api/auth/callback/google`
   - optionally also `http://localhost:3200/api/auth/callback/google` (for use
     via SSH tunnel from HAL itself)
5. Scopes used at sign-in: `openid`, `email`, `profile`,
   `https://www.googleapis.com/auth/webmasters.readonly`.
6. Paste the two values: run `/home/eggers/crawlseo/set-google-creds.sh` (prompts
   for Client ID + Secret, validates, writes `.env`, restarts the app container).
   Manual alternative: edit `GOOGLE_CLIENT_ID=` / `GOOGLE_CLIENT_SECRET=` in
   `.env`, then `cd /home/eggers/crawlseo && docker compose up -d app`.

## MCP server (for Claude Code / Desktop)

Verified working command (handshake + live `list_sites` against the DB):

```bash
cd /home/eggers/crawlseo && node --env-file=/home/eggers/crawlseo/.env --import tsx mcp/server.ts
```

Registration snippet:

```json
{
  "mcpServers": {
    "crawlseo": {
      "command": "node",
      "args": ["--env-file=/home/eggers/crawlseo/.env", "--import", "tsx", "mcp/server.ts"],
      "cwd": "/home/eggers/crawlseo"
    }
  }
}
```

- Env needed: only `DATABASE_URL` (already in `.env`, points at 127.0.0.1:5433).
  `--env-file` loads it without exposing values; tsx does not auto-load `.env`.
- `tsx` is installed in local node_modules with `--no-save` (upstream does not
  ship it as a dependency). If `npm ci` is ever re-run, reinstall with
  `npm install --no-save tsx`.
- 10 tools: list_sites, get_site_overview, get_keywords, get_pages, get_traffic,
  run_crawl, get_crawl_status, get_crawl_issues, get_vitals, get_opportunities.

## Pending / optional

- `DISABLE_REGISTRATION=true` in `.env` (then `docker compose up -d app`) would
  stop new sign-ups; currently open, but the app is tailnet-only.
- Optional integrations not configured: PageSpeed API key, DataForSEO (keywords/
  backlinks BYOK), SMTP / Telegram / Slack alerts, cron schedules
  (CRAWL_SCHEDULE, GSC_SYNC_SCHEDULE, VITALS_SCHEDULE).

## Ops

```bash
cd /home/eggers/crawlseo
docker compose ps                 # status
docker compose logs -f app        # app logs (migrations run at startup)
docker compose up -d              # apply compose/.env changes
docker compose restart app        # plain restart
```

Gotcha fixed 2026-07-26: Next.js standalone binds to $HOSTNAME (container id) by
default -> healthcheck against localhost failed while the mapped port worked.
Fixed with `HOSTNAME: 0.0.0.0` + healthcheck against `127.0.0.1` (busybox wget
tries ::1 first for `localhost`; Node on 0.0.0.0 is IPv4-only).
