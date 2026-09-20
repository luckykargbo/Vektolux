// src/app/api/real-estate-escrow/route.ts
// Proxy for Convex Real Estate Escrow & Settlement operations in Next.js Admin Dashboard
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";

function getClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

export async function GET() {
  try {
    const client = getClient();
    const summary = await client.query("realEstateEscrow:getAdminRealEstateEscrowSummary" as any, {});
    const escrows = await client.query("realEstateEscrow:getMyRealEstateEscrows" as any, {});
    return NextResponse.json({ success: true, data: { summary, escrows } });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err?.message ?? "Failed to fetch real estate escrow summary." },
      { status: 500 }
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { action, contractId, passId, milestoneIndex, proofUrls, damageDeductionAmount, notes } = body;
    const client = getClient();

    let result;
    if (action === "releaseStay24h") {
      result = await client.mutation("realEstateEscrow:releaseShortStayPayout24h" as any, {
        contractId,
        adminForceOverride: true,
      });
    } else if (action === "refundCaution") {
      result = await client.mutation("realEstateEscrow:refundCautionDeposit" as any, {
        contractId,
        inspectionPassedClean: !damageDeductionAmount || damageDeductionAmount === 0,
        damageDeductionAmount: damageDeductionAmount ? Number(damageDeductionAmount) : undefined,
        notes,
      });
    } else if (action === "releaseLandMilestone") {
      result = await client.mutation("realEstateEscrow:verifyAndReleaseLandMilestone" as any, {
        contractId,
        milestoneIndex: Number(milestoneIndex),
        proofDocumentUrls: proofUrls ?? [],
        legalNotes: notes,
      });
    } else if (action === "verifyPass") {
      result = await client.mutation("realEstateEscrow:verifyInspectionPass" as any, {
        passId,
        scannedQrHash: body.qrHash,
        enteredOtp: body.otpCode,
      });
    } else {
      return NextResponse.json({ success: false, error: "Invalid real estate action" }, { status: 400 });
    }

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: err?.message ?? "Failed to process real estate action" },
      { status: 500 }
    );
  }
}
