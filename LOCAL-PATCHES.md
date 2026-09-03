# Local Patches

Deviations from upstream `crawlseo/crawlseo` kept only in this self-hosted
fork (not intended to go back upstream as-is, or not yet upstreamed). Keep
these small and easy to re-apply if we ever rebase onto a newer upstream.

Fork of record: `MetroGnome-AI/crawlseo` (`origin`, push) with
`upstream` = `crawlseo/crawlseo` (pull-only catch-ups) — same remote
convention as the nanoclaw fork.

Upstream catch-up 2026-08-24 (14 commits, through `e75b042`): patches 1 and 2
retired (superseded upstream); 3 re-applied over upstream's reauth rewrite of
the same route; 4 untouched.

Upstream catch-up 2026-09-03 (7 commits, through upstream #25→#32 series):
patch 5 retired (upstream #32 supersedes it — our issue #27 fixed properly);
patch 3 re-applied combined with upstream's data-lag end boundary (#26);
patch 4 untouched (PR #20 still open awaiting review). `docker-compose.override.yml` now pins
`build: .` / `image: crawlseo-local:main` because upstream's compose switched
to pulling a published ghcr image — a patched fork must build itself.

## 1. ~~Pin Prisma CLI in Docker CMD~~ — RETIRED 2026-08-24: upstream #23 copies the built Prisma CLI from the builder stage (no npx at runtime). Was commit `e49dba6`.

`Dockerfile` — the runtime `CMD` ran `npx prisma migrate deploy`, which
resolves to whatever `prisma@latest` is at pull time. That drifted to
Prisma 7.x, which rejects the `url = env(...)` datasource syntax our
`prisma/schema.prisma` uses. Pinned to `npx prisma@6.19.3` to match the
project's installed version.

## 2. ~~Build-stage OAuth/env placeholders~~ — RETIRED 2026-08-24: upstream #24 dropped the placeholder secrets from the build stage. Was commit `ce62166`.

`Dockerfile` — `lib/auth.ts` throws at import time when `GOOGLE_CLIENT_ID` /
`GOOGLE_CLIENT_SECRET` / `NEXTAUTH_SECRET` / `APP_SECRET` / `DATABASE_URL`
are empty, and `next build` imports route modules during page-data
collection. Added placeholder values as build-stage `ENV` vars so the image
builds without real secrets baked in; the standalone server reads the real
values from `.env` at container runtime.

## 3. `daysBack` param on `/api/gsc/sync` (2026-07-28 — upstream draft PR crawlseo/crawlseo#21)

`app/api/gsc/sync/route.ts` — the POST handler hardcoded
`getDateRange(28)`, so the GSC sync could never pull more than a rolling
28-day window. That's fine for day-to-day refreshes but blocks
period-over-period comparisons and content-decay analysis, which need
50+ days of history.

Patched to accept an optional `daysBack` in the POST body (still defaults
to 28, clamped to `[1, 500]`) so a one-off backfill can request a wider
window. Auth/session/ownership checks are untouched. The route still
duplicates the fetch/upsert logic inline rather than calling
`lib/workers/gsc-sync.ts`'s `syncGSCDataForSite` (which already takes a
`daysBack` param) — that duplication predates this patch and wasn't
touched here.

Used once for a manual GSC history backfill on 2026-07-28: `daysBack=120`
then `daysBack=480`, both invoked via `syncGSCDataForSite` (the
worker function this route duplicates, not the route itself) from a
host-side `tsx` script (same pattern as `mcp/server.ts`), not through this
HTTP route, since the route requires an authenticated browser session.
Idempotent via the existing `Keyword`/`Page` `@@unique([siteId, ..., date])`
constraints (upsert), so re-running with overlapping windows does not
duplicate rows. Result: `Keyword`/`Page` history widened from 29 days
(2026-06-26 → 2026-07-24) to 480 days back from today. See git history /
ask Rob for the exact before/after row counts from that run.

**Known pre-existing gotcha (not fixed here):** `Keyword`'s unique key is
`(siteId, query, date)` — it does not include `device`/`country`, even
though `fetchSearchAnalytics` is called with those as dimensions. GSC
returns one row per (query, page, date, device, country) tuple, so when
multiple such rows collapse onto the same `(siteId, query, date)` key,
only the last upserted row survives per keyword/day. Out of scope for the
backfill task; flagging so it doesn't get mistaken for a backfill bug.

Also note: `fetchPageAnalytics` (used by both `route.ts` and
`gsc-sync.ts`) does a single GSC API call with `rowLimit: 25000` and does
not paginate past that, unlike `fetchSearchAnalytics`. Not hit at
120-480 days for this one site's page count, but would silently truncate
for a bigger site/date range.

## 4. Machine service surface `/api/svc/<tool>` (commit `31650db`, 2026-08-20 — upstream draft PR crawlseo/crawlseo#20)

`app/api/svc/[tool]/route.ts` — the MCP tool set over HTTP with a bearer
service token (`Authorization: Bearer $CRAWLSEO_SERVICE_TOKEN`, fail-closed
when the env is unset), JSON responses, same lib queries as `mcp/server.ts`.
Added for external engines/dashboards — the FLOW platform's
`providers/crawlseo` adapter consumes it. Instance-level scope (no per-user
filtering), matching the MCP server's semantics. Upstream-PR candidate —
if accepted, this patch retires.

## 5. ~~Runner-stage Prisma CLI install~~ — RETIRED 2026-09-03: upstream #32 ships the full Prisma CLI dependency closure in the runner (fixes our #27). Was carried since 2026-08-24.

`Dockerfile` — upstream #23 replaced the runner's `npm install` with copies of
`node_modules/prisma`, `@prisma/engines` and `.bin/prisma`. That misses
transitive deps (`@prisma/debug`, then `@prisma/config` → `effect`, …) and
flattens the `.bin` symlink so the bundled CLI cannot find its sibling WASM;
`prisma migrate deploy` crashes at boot (restart loop; seen live 2026-08-24 on
x86, three distinct MODULE_NOT_FOUND/ENOENT faults in a row). Replaced with
`RUN npm install --no-save --omit=dev prisma@6.19.3` in the runner — complete
tree, pinned, no runtime network. Worth reporting upstream: their published
image likely crashes identically.
