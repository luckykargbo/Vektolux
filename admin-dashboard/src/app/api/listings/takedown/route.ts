import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { isAuthError, sessionFromRequest } from "@/lib/apiAuth";
import { CONVEX_URL } from "@/lib/convex";

function getClient() { return new ConvexHttpClient(CONVEX_URL); }

/** Never send internal error text to the browser. */
function publicMessage(err: unknown, fallback: string): string {
  return isAuthError(err) ? "Administrator access required. Please sign in again." : fallback;
}

export async function POST(req: Request) {
  try {
    const { adminId, listingId, listingType, reason } = await req.json();
    const sessionToken = sessionFromRequest(req);
    const client = getClient();
    const result = await client.mutation("admin:takeDownListing" as any, {
      adminId,
      sessionToken,
      listingId,
      listingType,
      reason
    });
    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    return NextResponse.json({ success: false, error: publicMessage(err, "Failed to take down listing.") }, { status: 500 });
  }
}
