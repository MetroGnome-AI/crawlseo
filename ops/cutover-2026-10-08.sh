#!/usr/bin/env bash
# cutover-2026-10-08.sh — swap the running SEO service onto the merged image
# (branch catchup-2026-10-08, image crawlseo-local:main built 2026-10-08 14:06),
# with a database dump first and an automatic rollback if the new container
# does not come healthy. Run after hours; takes ~2 minutes. Logs to ops/logs/.
#
#   bash ops/cutover-2026-10-08.sh            # do it
#   bash ops/cutover-2026-10-08.sh --rollback # put the previous image back by hand
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p ops/logs ops/backups
LOG="ops/logs/cutover-$(date +%Y%m%d-%H%M%S).log"; exec > >(tee -a "$LOG") 2>&1
PREV_IMAGE_ID="sha256:1e544c0887eb8961ccea66be1c569197a7302ff12dd596fb91126468ef6b4920"   # running before the cutover
NEW_IMAGE_ID="sha256:8e2ab1860954ae3930924cc7d40af93637d631364cbc190ac956367bc504e3bb"    # built from c635dda
health() { curl -s -m 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:3200/api/health || true; }

if [ "${1:-}" = "--rollback" ]; then
  echo "== ROLLBACK $(date -Is): retag previous image and recreate"
  docker tag "$PREV_IMAGE_ID" crawlseo-local:main
  docker compose up -d --no-build app
  for i in $(seq 1 24); do [ "$(health)" = 200 ] && { echo "rollback healthy"; exit 0; }; sleep 5; done
  echo "rollback did NOT come healthy — check: docker compose logs app"; exit 1
fi

echo "== CUTOVER $(date -Is)"
echo "-- git: $(git rev-parse --abbrev-ref HEAD) $(git log --oneline -1 | cut -c1-70)"
[ "$(docker image inspect crawlseo-local:main --format '{{.Id}}')" = "$NEW_IMAGE_ID" ] || { echo "tag crawlseo-local:main is not the merged image — rebuild first (docker compose build app)"; exit 1; }
echo "-- health before: $(health)"
echo "-- database dump"
docker compose exec -T db pg_dump -U crawlseo -Fc crawlseo > "ops/backups/crawlseo-pre-catchup-$(date +%Y%m%d-%H%M%S).dump"
ls -la ops/backups | tail -1
echo "-- recreate app on the merged image (migrations run in the container CMD)"
docker compose up -d --no-build app
for i in $(seq 1 36); do
  code="$(health)"; echo "   health $i: $code"
  [ "$code" = 200 ] && break
  sleep 5
done
if [ "$(health)" != 200 ]; then
  echo "!! new container not healthy — last log lines, then automatic rollback"
  docker compose logs --tail 40 app
  docker tag "$PREV_IMAGE_ID" crawlseo-local:main
  docker compose up -d --no-build app
  exit 1
fi
echo "-- migrations applied:"
docker compose exec -T db psql -U crawlseo -d crawlseo -Atc "select migration_name from _prisma_migrations order by finished_at desc limit 6"
echo "-- version served: $(curl -s -m 10 http://127.0.0.1:3200/api/health)"
echo "-- machine surface (what the dashboard's provider calls) and the table it reads:"
set -a; . ./.env; set +a
curl -s -m 25 -o /dev/null -w '   svc list_sites: HTTP %{http_code} %{size_download}B\n' -X POST -H "Authorization: Bearer ${CRAWLSEO_SERVICE_TOKEN:-}" -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:3200/api/svc/list_sites
echo "   Keyword rows: $(docker compose exec -T db psql -U crawlseo -d crawlseo -Atc 'select count(*) from "Keyword"')  (baseline before cutover: see ops/logs)"
echo "-- dashboard: open the SEO page in a browser and confirm pulse/movers render (its API is session-authenticated; curl shows 401 by design)"
echo "== DONE $(date -Is) — merge main when satisfied: git checkout main && git merge --ff-only catchup-2026-10-08 && git push origin main"
