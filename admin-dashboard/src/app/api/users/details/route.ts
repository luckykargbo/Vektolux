// src/app/api/users/details/route.ts
// GET: fetch full user profile, verification details, and posted listings
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

export const dynamic = "force-dynamic";

import { isAuthError, sessionFromRequest } from "@/lib/apiAuth";
import { CONVEX_URL } from "@/lib/convex";

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
    const adminId = searchParams.get("adminId");
    const sessionToken = sessionFromRequest(request);
    const userId = searchParams.get("userId");

    if (!adminId || !userId) {
      return NextResponse.json(
        { success: false, error: "adminId and userId are required" },
        { status: 400 }
      );
    }

    const client = getClient();
    const result = await client.query("admin:getUserFullDetails" as any, {
      adminId,
      sessionToken,
      userId,
    });

    if (!result) {
      return NextResponse.json({ success: false, error: "User not found" }, { status: 404 });
    }

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    console.error("[user details GET] request failed");
    return NextResponse.json(
      { success: false, error: publicMessage(err, "Failed to fetch user details.") },
      { status: 500 }
    );
  }
}
