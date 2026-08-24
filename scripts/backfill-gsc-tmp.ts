#!/usr/bin/env node

/**
 * One-off GSC history backfill.
 *
 * Reuses lib/workers/gsc-sync.ts's syncGSCDataForSite (already parameterized
 * by daysBack) instead of re-implementing the GSC fetch/upsert logic.
 *
 * Run (same host-side pattern as mcp/server.ts):
 *   node --env-file=/home/eggers/crawlseo/.env --import tsx backfill-gsc-tmp.ts <userId> <siteId> <daysBack>
 */

import { syncGSCDataForSite } from "../lib/workers/gsc-sync";
import { db } from "../lib/db";

async function main() {
  const [userId, siteId, daysBackRaw] = process.argv.slice(2);

  if (!userId || !siteId || !daysBackRaw) {
    console.error(
      "Usage: backfill-gsc-tmp.ts <userId> <siteId> <daysBack>"
    );
    process.exit(1);
  }

  const daysBack = Number(daysBackRaw);

  console.log(
    `[backfill] userId=${userId} siteId=${siteId} daysBack=${daysBack}`
  );

  const result = await syncGSCDataForSite(userId, siteId, daysBack);

  console.log("[backfill] result:", JSON.stringify(result, null, 2));

  await db.$disconnect();

  if (!result.success) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("[backfill] fatal:", err);
  process.exit(1);
});
