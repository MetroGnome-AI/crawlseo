import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import { ReauthRequiredError } from "@/lib/google";
import { runGSCSync } from "@/lib/workers/gsc-sync";

export async function POST(req: Request) {
  try {
    const session = await auth();

    if (!session?.user?.id) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { siteId, daysBack: requestedDaysBack } = (await req.json()) as {
      siteId: string;
      daysBack?: number;
    };

    // local: allow callers (e.g. history backfill) to widen the sync window
    // beyond the default 28 days. Clamped to keep a single request from
    // trying to pull an unbounded amount of GSC history in one shot.
    const daysBack = Math.min(
      Math.max(Number(requestedDaysBack) || 28, 1),
      500
    );

    // Verify site belongs to user
    const site = await db.site.findUnique({
      where: { id: siteId },
      select: { userId: true, gscProperty: true },
    });

    if (!site || site.userId !== session.user.id) {
      return Response.json(
        { error: "Site not found or unauthorized" },
        { status: 404 }
      );
    }

    if (!site.gscProperty) {
      return Response.json(
        { error: "Site does not have GSC property connected" },
        { status: 400 }
      );
    }

    // Same fetch + upsert as the background worker, so both paths write
    // identical Keyword/Page rows (see gscDate for the date convention).
    const result = await runGSCSync(
      session.user.id,
      siteId,
      site.gscProperty,
      daysBack
    );

    return Response.json({
      success: true,
      keywordsInserted: result.keywordsInserted,
      pagesInserted: result.pagesInserted,
    });
  } catch (error) {
    if (error instanceof ReauthRequiredError) {
      return Response.json(
        { error: error.message, code: "REAUTH_REQUIRED" },
        { status: 401 }
      );
    }

    console.error("Error syncing GSC data:", error);

    return Response.json(
      {
        error: error instanceof Error ? error.message : "Failed to sync GSC data",
      },
      { status: 500 }
    );
  }
}
