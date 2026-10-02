// src/app/api/real-estate-escrow/route.ts
// Proxy for Convex Real Estate Escrow & Settlement operations in Next.js Admin Dashboard
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
    const summary = await client.query("realEstateEscrow:getAdminRealEstateEscrowSummary" as any, { sessionToken });
    const escrows = summary?.recentContracts ?? [];
    return NextResponse.json({ success: true, data: { summary, escrows } });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: publicMessage(err, "Failed to fetch real estate escrow summary.") },
      { status: 500 }
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { action, contractId, passId, milestoneIndex, proofUrls, damageDeductionAmount, notes } = body;
    const sessionToken = sessionFromRequest(request);
    const client = getClient();

    let result;
    if (action === "releaseStay24h") {
      result = await client.mutation("realEstateEscrow:releaseShortStayPayout24h" as any, {
        contractId,
        adminForceOverride: true,
        sessionToken,
      });
    } else if (action === "refundCaution") {
      result = await client.mutation("realEstateEscrow:refundCautionDeposit" as any, {
        contractId,
        inspectionPassedClean: !damageDeductionAmount || damageDeductionAmount === 0,
        damageDeductionAmount: damageDeductionAmount ? Number(damageDeductionAmount) : undefined,
        notes,
        sessionToken,
      });
    } else if (action === "releaseLandMilestone") {
      result = await client.mutation("realEstateEscrow:verifyAndReleaseLandMilestone" as any, {
        contractId,
        milestoneIndex: Number(milestoneIndex),
        proofDocumentUrls: proofUrls ?? [],
        legalNotes: notes,
        sessionToken,
      });
    } else if (action === "verifyPass") {
      result = await client.mutation("realEstateEscrow:verifyInspectionPass" as any, {
        passId,
        scannedQrHash: body.qrHash,
        enteredOtp: body.otpCode,
        sessionToken,
      });
    } else {
      return NextResponse.json({ success: false, error: "Invalid real estate action" }, { status: 400 });
    }

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    return NextResponse.json(
      { success: false, error: publicMessage(err, "Failed to process real estate action") },
      { status: 500 }
    );
  }
}
