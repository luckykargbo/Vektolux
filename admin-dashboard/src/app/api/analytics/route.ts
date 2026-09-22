// src/app/api/analytics/route.ts
// Real-time analytics aggregation query endpoint for Overview dashboard
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { CONVEX_URL } from "@/lib/convex";

export const dynamic = "force-dynamic";

function getClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const adminId = searchParams.get("adminId") ?? undefined;
    const sessionToken = searchParams.get("sessionToken") ?? undefined;

    const client = getClient();
    const result = await client.query("adminPortal:getAdminAnalytics" as any, {
      adminId: adminId || undefined,
      sessionToken: sessionToken || undefined,
    });

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    console.error("[analytics GET] error:", err);
    const msg = err?.message ?? "Failed to fetch analytics.";
    const isUnauthorized =
      msg.includes("Unauthorized") ||
      msg.includes("Forbidden") ||
      msg.includes("session token");
    return NextResponse.json(
      {
        success: false,
        error: msg,
        code: isUnauthorized ? "UNAUTHORIZED" : "SERVER_ERROR",
      },
      { status: isUnauthorized ? 401 : 500 }
    );
  }
}
