// src/app/api/finance/route.ts
// Read-only proxy for the admin financial overview. Convex authorises the admin session.
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";
import { sessionFromRequest } from "@/lib/adminSession";

export async function GET(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) {
    return NextResponse.json({ success: false, error: "Not signed in." }, { status: 401 });
  }
  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const data = await client.query("adminFinance:getFinancialOverview" as any, { sessionToken });
    return NextResponse.json({ success: true, data }, { headers: { "Cache-Control": "no-store" } });
  } catch (err: any) {
    // No internal details to the browser; authorisation failures are reported generically.
    const msg = String(err?.message ?? "");
    const denied = /unauthori|admin|authentication/i.test(msg);
    console.error("[api/finance] overview failed");
    return NextResponse.json(
      { success: false, error: denied ? "Administrator access required." : "Could not load the financial overview." },
      { status: denied ? 403 : 500 }
    );
  }
}
