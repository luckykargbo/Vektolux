// src/app/api/fee-rules/route.ts
// Fees & Commissions: list rules (GET), add a rule version or cancel a scheduled one (POST).
// Convex authorises the admin session and validates every value; this route only forwards.
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";
import { errorResponse, isAuthError, missingSession, sessionFromRequest } from "@/lib/apiAuth";

/** The backend's own user-facing validation message (e.g. "cannot be backdated"), without stack details. */
function validationMessage(err: unknown): string | null {
  const msg = String((err as any)?.message ?? "");
  const m = msg.match(/Uncaught Error: ([^\n]{1,200})/);
  return m ? m[1].trim() : null;
}

export async function GET(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) return missingSession();
  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const data = await client.query("feeRules:adminListFeeRules" as any, { sessionToken });
    return NextResponse.json({ success: true, data }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err, "Could not load fee rules.", "api/fee-rules GET");
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
  const client = new ConvexHttpClient(CONVEX_URL);
  try {
    if (body?.action === "set") {
      const data = await client.mutation("feeRules:adminSetFeeRule" as any, {
        sessionToken,
        vertical: String(body.vertical ?? ""),
        ownerFeeBps: Number(body.ownerFeeBps),
        buyerFeeBps: Number(body.buyerFeeBps),
        agentCommissionBps: Number(body.agentCommissionBps),
        agentCommissionPayer: body.agentCommissionPayer === "owner" ? "owner" : "buyer",
        platformShareOfAgentCommissionBps: Number(body.platformShareOfAgentCommissionBps),
        effectiveFrom: typeof body.effectiveFrom === "number" ? body.effectiveFrom : undefined,
        note: String(body.note ?? ""),
      });
      return NextResponse.json({ success: true, data });
    }
    if (body?.action === "cancel") {
      const data = await client.mutation("feeRules:adminCancelScheduledFeeRule" as any, {
        sessionToken,
        ruleId: String(body.ruleId ?? ""),
        reason: String(body.reason ?? ""),
      });
      return NextResponse.json({ success: true, data });
    }
    return NextResponse.json({ success: false, error: "Unknown action." }, { status: 400 });
  } catch (err) {
    const message = !isAuthError(err) ? validationMessage(err) : null;
    if (message) {
      console.error("[api/fee-rules POST] rejected by validation");
      return NextResponse.json({ success: false, error: message, code: "VALIDATION" }, { status: 400 });
    }
    return errorResponse(err, "Could not save the fee rule.", "api/fee-rules POST");
  }
}
