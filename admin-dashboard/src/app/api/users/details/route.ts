// src/app/api/users/details/route.ts
// GET: fetch full user profile, verification details, and posted listings
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

export const dynamic = "force-dynamic";

const CONVEX_URL = process.env.NEXT_PUBLIC_CONVEX_URL ?? "https://incredible-possum-462.convex.cloud";

function getClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const adminId = searchParams.get("adminId");
    const sessionToken = searchParams.get("sessionToken") ?? undefined;
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
    console.error("[user details GET] error:", err);
    return NextResponse.json(
      { success: false, error: err?.message ?? "Failed to fetch user details." },
      { status: 500 }
    );
  }
}
