// src/app/api/analytics/route.ts
// Real-time analytics aggregation query endpoint for Overview dashboard
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { isAuthError, sessionFromRequest } from "@/lib/apiAuth";
import { CONVEX_URL } from "@/lib/convex";

export const dynamic = "force-dynamic";

function getClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

/** Never send internal error text to the browser. */
function publicMessage(err: unknown, fallback: string): string {
  return isAuthError(err) ? "Administrator access required. Please sign in again." : fallback;
}

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const adminId = searchParams.get("adminId") ?? undefined;
    const sessionToken = sessionFromRequest(request);

    const client = getClient();
    const result = await client.query("adminPortal:getAdminAnalytics" as any, {
      adminId: adminId || undefined,
      sessionToken: sessionToken || undefined,
    });

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    console.error("[analytics GET] request failed");
    const msg = "Failed to fetch analytics.";
    const isUnauthorized =
      isAuthError(err);
    return NextResponse.json(
      {
        success: false,
        error: publicMessage(err, msg),
        code: isUnauthorized ? "UNAUTHORIZED" : "SERVER_ERROR",
      },
      { status: isUnauthorized ? 401 : 500 }
    );
  }
}
