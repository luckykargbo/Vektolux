// src/app/api/seed/route.ts
// POST: run quick seed for a specific vertical / city
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

const CONVEX_URL = process.env.NEXT_PUBLIC_CONVEX_URL ?? "https://incredible-possum-462.convex.cloud";

export async function POST(request: Request) {
  try {
    const { vertical, city, isPublished } = await request.json() as {
      vertical: string; city: string; isPublished: boolean;
    };

    const client = new ConvexHttpClient(CONVEX_URL);
    const result = await client.mutation("admin:quickSeedListings" as any, {
      vertical,
      city,
      isPublished,
    });

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    return NextResponse.json({ success: false, error: err?.message ?? "Seed failed." }, { status: 500 });
  }
}
