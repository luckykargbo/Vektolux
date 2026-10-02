// src/app/api/refund-recovery/route.ts
// Admin → Refund Recovery: list reversals + recent payouts (GET); reverse a payout, retry recovery,
// platform cover, write off, lift/restore protection (POST). Every action requires an admin note;
// Convex authorises the session, validates and audits. This route only forwards.
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";
import { errorResponse, isAuthError, missingSession, sessionFromRequest } from "@/lib/apiAuth";

function validationMessage(err: unknown): string | null {
  const m = String((err as any)?.message ?? "").match(/Uncaught Error: ([^\n]{1,200})/);
  return m ? m[1].trim() : null;
}

export async function GET(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) return missingSession();
  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const [reversals, releases] = await Promise.all([
      client.query("reversals:adminListReversals" as any, { sessionToken }),
      client.query("reversals:adminListRecentReleases" as any, { sessionToken }),
    ]);
    return NextResponse.json({ success: true, data: { reversals, releases } }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err, "Could not load refund recovery data.", "api/refund-recovery GET");
  }
}

export async function POST(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) return missingSession();
  let body: any;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ success: false, error: "Invalid request." }, { status: 400 });
  }
  const note = String(body?.note ?? "");
  const reversalId = String(body?.reversalId ?? "");
  const client = new ConvexHttpClient(CONVEX_URL);
  try {
    let data: unknown;
    switch (body?.action) {
      case "reverse":
        data = await client.mutation("reversals:adminReverseRelease" as any, {
          sessionToken,
          releaseTransactionId: String(body.releaseTransactionId ?? ""),
          reason: note,
        });
        break;
      case "retry":
        data = await client.mutation("reversals:adminRetryRecovery" as any, { sessionToken, reversalId, note });
        break;
      case "platform_covered":
      case "written_off":
        data = await client.mutation("reversals:adminCloseRecovery" as any, { sessionToken, reversalId, resolution: body.action, note });
        break;
      case "lift_protection":
      case "restore_protection":
        data = await client.mutation("reversals:adminSetRecoveryProtection" as any, {
          sessionToken,
          reversalId,
          lifted: body.action === "lift_protection",
          note,
        });
        break;
      default:
        return NextResponse.json({ success: false, error: "Unknown action." }, { status: 400 });
    }
    return NextResponse.json({ success: true, data });
  } catch (err) {
    const message = !isAuthError(err) ? validationMessage(err) : null;
    if (message) return NextResponse.json({ success: false, error: message, code: "VALIDATION" }, { status: 400 });
    return errorResponse(err, "The action could not be completed.", "api/refund-recovery POST");
  }
}
