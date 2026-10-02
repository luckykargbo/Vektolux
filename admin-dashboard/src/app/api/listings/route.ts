// src/app/api/listings/route.ts
// GET: fetch all admin listings  |  DELETE: clear all listings
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { isAuthError, sessionFromRequest } from "@/lib/apiAuth";
import { CONVEX_URL } from "@/lib/convex";

function getClient() { return new ConvexHttpClient(CONVEX_URL); }

/** Never send internal error text to the browser. */
function publicMessage(err: unknown, fallback: string): string {
  return isAuthError(err) ? "Administrator access required. Please sign in again." : fallback;
}

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const vertical = (searchParams.get("vertical") ?? "all") as any;
    const client = getClient();
    const result = await client.query("admin:getAdminListings" as any, {
      vertical,
      sessionToken: sessionFromRequest(request),
    });
    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    return NextResponse.json({ success: false, error: publicMessage(err, "Failed.") }, { status: 500 });
  }
}

// Deleting every listing is a destructive maintenance operation. It is now an internal Convex
// function (it used to be callable by anyone) and can only be run from the Convex dashboard/CLI.
export async function DELETE() {
  return NextResponse.json(
    { success: false, error: "Clearing all listings is disabled here. Use the Convex dashboard (internal function admin:clearAllListings)." },
    { status: 403 }
  );
}
