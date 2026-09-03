/**
 * Core GSC sync: pull `daysBack` days of Search Console keyword + page rows
 * for one site and upsert them. Shared by the session route
 * (app/api/gsc/sync) and the machine surface (app/api/svc gsc_sync tool) so
 * both paths cannot drift. Caller is responsible for authorization; this
 * function trusts the (userId, siteId, gscProperty) it is given.
 *
 * Throws ReauthRequiredError (from lib/google) when the stored Google
 * credential cannot be refreshed — callers map that to their own 401 shape.
 */
import { db } from "@/lib/db";
import { fetchSearchAnalytics, fetchPageAnalytics } from "@/lib/google";
import { getDateRange, getDataLagDate } from "@/lib/date-utils";

export interface GscSyncResult {
  keywordsInserted: number;
  pagesInserted: number;
  start: string;
  end: string;
}

export async function syncSiteGsc(
  userId: string,
  siteId: string,
  gscProperty: string,
  daysBack: number
): Promise<GscSyncResult> {
  // End at the data lag boundary (3 days ago) because Google's most recent
  // 2-3 days are always incomplete.
  const { start } = getDateRange(daysBack);
  const end = getDataLagDate();

  const [keywords, pages] = await Promise.all([
    fetchSearchAnalytics(userId, gscProperty, start, end, [
      "query",
      "page",
      "date",
      "device",
      "country",
    ]),
    fetchPageAnalytics(userId, gscProperty, start, end),
  ]);

  for (const keyword of keywords) {
    await db.keyword.upsert({
      where: {
        siteId_query_date: {
          siteId,
          query: keyword.query,
          date: new Date(keyword.date),
        },
      },
      create: {
        siteId,
        query: keyword.query,
        date: new Date(keyword.date),
        clicks: keyword.clicks,
        impressions: keyword.impressions,
        ctr: keyword.ctr,
        position: keyword.position,
        page: keyword.page,
        device: keyword.device,
        country: keyword.country,
      },
      update: {
        clicks: keyword.clicks,
        impressions: keyword.impressions,
        ctr: keyword.ctr,
        position: keyword.position,
      },
    });
  }

  for (const page of pages) {
    if (!page.page) continue;

    await db.page.upsert({
      where: {
        siteId_url_date: {
          siteId,
          url: page.page,
          date: new Date(page.date),
        },
      },
      create: {
        siteId,
        url: page.page,
        date: new Date(page.date),
        clicks: page.clicks,
        impressions: page.impressions,
        ctr: page.ctr,
        position: page.position,
      },
      update: {
        clicks: page.clicks,
        impressions: page.impressions,
        ctr: page.ctr,
        position: page.position,
      },
    });
  }

  return {
    keywordsInserted: keywords.length,
    pagesInserted: pages.length,
    start,
    end,
  };
}
