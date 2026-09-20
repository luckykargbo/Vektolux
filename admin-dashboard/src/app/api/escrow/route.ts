// src/app/api/escrow/route.ts
// Proxy for Convex Escrow & Settlement operations in the Admin Dashboard
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";

function getClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

export async function GET() {
  try {
    const client = getClient();
    const summary = await client.query("escrow:getAdminEscrowSummary" as any, {});
    // We can also fetch the recent orders
    const orders = await client.query("escrow:getMyEscrowOrders" as any, {});
    return NextResponse.json({ success: true, data: { summary, orders } });
  } catch (err: any) {
    return NextResponse.json({ success: false, error: err?.message ?? "Failed to fetch escrow." }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { action, escrowOrderId, damageDeductionCost, verificationNotes } = body;
    const client = getClient();

    let result;
    if (action === "release60") {
      result = await client.mutation("escrow:releaseMilestoneHandoff60" as any, { escrowOrderId });
    } else if (action === "settleReturn") {
      result = await client.mutation("escrow:settleVehicleReturn" as any, {
        escrowOrderId,
        damageDeductionCost: damageDeductionCost ? Number(damageDeductionCost) : undefined,
      });
    } else if (action === "confirmSlrsa") {
      result = await client.mutation("escrow:confirmSlrsaTransfer" as any, {
        escrowOrderId,
        verificationNotes,
      });
    } else {
      return NextResponse.json({ success: false, error: "Invalid action" }, { status: 400 });
    }

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    return NextResponse.json({ success: false, error: err?.message ?? "Failed to process action" }, { status: 500 });
  }
}
