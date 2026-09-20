import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";

function getClient() { return new ConvexHttpClient(CONVEX_URL); }

export async function POST(req: Request) {
  try {
    const { adminId, sessionToken, listingId, listingType, reason } = await req.json();
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
    return NextResponse.json({ success: false, error: err?.message ?? "Failed to take down listing." }, { status: 500 });
  }
}
