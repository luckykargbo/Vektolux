// src/app/api/escrow/route.ts
// Proxy for Convex Escrow & Settlement operations in the Admin Dashboard
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { isAuthError, sessionFromRequest } from "@/lib/apiAuth";
import { CONVEX_URL } from "@/lib/convex";

function getClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

/** Never send internal error text to the browser. */
function publicMessage(err: unknown, fallback: string): string {
  return isAuthError(err) ? "Administrator access required. Please sign in again." : fallback;
}

export async function GET(request: Request) {
  try {
    const sessionToken = sessionFromRequest(request);
    const client = getClient();
    const summary = await client.query("escrow:getAdminEscrowSummary" as any, { sessionToken });
    const orders = summary?.recentOrders ?? [];
    return NextResponse.json({ success: true, data: { summary, orders } });
  } catch (err: any) {
    return NextResponse.json({ success: false, error: publicMessage(err, "Failed to fetch escrow.") }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { action, escrowOrderId, damageDeductionCost, verificationNotes } = body;
    const sessionToken = sessionFromRequest(request);
    const client = getClient();

    let result;
    if (action === "release60") {
      result = await client.mutation("escrow:releaseMilestoneHandoff60" as any, { escrowOrderId, sessionToken });
    } else if (action === "settleReturn") {
      result = await client.mutation("escrow:settleVehicleReturn" as any, {
        escrowOrderId,
        damageDeductionCost: damageDeductionCost ? Number(damageDeductionCost) : undefined,
        sessionToken,
      });
    } else if (action === "confirmSlrsa") {
      result = await client.mutation("escrow:confirmSlrsaTransfer" as any, {
        escrowOrderId,
        verificationNotes,
        sessionToken,
      });
    } else {
      return NextResponse.json({ success: false, error: "Invalid action" }, { status: 400 });
    }

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    return NextResponse.json({ success: false, error: publicMessage(err, "Failed to process action") }, { status: 500 });
  }
}
