// src/app/api/seed/route.ts
// POST: run quick seed for a specific vertical / city
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { isAuthError } from "@/lib/apiAuth";
import { CONVEX_URL } from "@/lib/convex";

/** Never send internal error text to the browser. */
function publicMessage(err: unknown, fallback: string): string {
  return isAuthError(err) ? "Administrator access required. Please sign in again." : fallback;
}

export async function POST(request: Request) {
  try {
    const { vertical, city, isPublished } = await request.json() as {
      vertical: string; city: string; isPublished: boolean;
    };

    // Seeding sample listings into the live database is disabled (it inserted fake listings and was
    // callable by anyone). admin:quickSeedListings is now internal: run it only against a
    // non-production deployment from the Convex dashboard/CLI.
    void vertical; void city; void isPublished; void ConvexHttpClient; void CONVEX_URL;
    return NextResponse.json(
      { success: false, error: "Seeding sample data is disabled on this deployment." },
      { status: 403 }
    );
  } catch (err: any) {
    return NextResponse.json({ success: false, error: publicMessage(err, "Seed failed.") }, { status: 500 });
  }
}
