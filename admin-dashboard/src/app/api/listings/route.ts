// src/app/api/listings/route.ts
// GET: fetch all admin listings  |  DELETE: clear all listings
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";

function getClient() { return new ConvexHttpClient(CONVEX_URL); }

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const vertical = (searchParams.get("vertical") ?? "all") as any;
    const client = getClient();
    const result = await client.query("admin:getAdminListings" as any, { vertical });
    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    return NextResponse.json({ success: false, error: err?.message ?? "Failed." }, { status: 500 });
  }
}

export async function DELETE() {
  try {
    const client = getClient();
    const result = await client.mutation("admin:clearAllListings" as any, {});
    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    return NextResponse.json({ success: false, error: err?.message ?? "Failed." }, { status: 500 });
  }
}
