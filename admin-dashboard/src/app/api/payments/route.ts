// src/app/api/payments/route.ts
// Admin → Payment Methods & Claims Management API Proxy
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { CONVEX_URL } from "@/lib/convex";
import { errorResponse, isAuthError, missingSession, sessionFromRequest } from "@/lib/apiAuth";

export const dynamic = "force-dynamic";

function getClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

function validationMessage(err: unknown): string | null {
  const m = String((err as any)?.message ?? "").match(/Uncaught Error: ([^\n]{1,200})/);
  return m ? m[1].trim() : null;
}

export async function GET(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) return missingSession();

  const { searchParams } = new URL(request.url);
  const type = searchParams.get("type");

  try {
    const client = getClient();
    if (type === "claims") {
      const data = await client.query("payments:getPendingApprovalClaims" as any, { sessionToken });
      return NextResponse.json({ success: true, data }, { headers: { "Cache-Control": "no-store" } });
    }

    // Default: return payment methods
    const data = await client.query("payments:getAllPaymentMethods" as any, { sessionToken });
    return NextResponse.json({ success: true, data }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err, "Failed to load payment settings.", "api/payments GET");
  }
}

export async function POST(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) return missingSession();

  let body: any;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ success: false, error: "Invalid JSON body." }, { status: 400 });
  }

  const { action } = body;
  const client = getClient();

  try {
    switch (action) {
      case "seedDefaultPaymentMethods": {
        const data = await client.mutation("payments:seedDefaultPaymentMethods" as any, { sessionToken });
        return NextResponse.json({ success: true, data });
      }

      case "updatePaymentMethod": {
        const { settingsId, isEnabled, displayName, instructions, accountNumber, accountName } = body;
        if (!settingsId) {
          return NextResponse.json({ success: false, error: "settingsId is required." }, { status: 400 });
        }
        const data = await client.mutation("payments:updatePaymentMethod" as any, {
          sessionToken,
          settingsId,
          ...(isEnabled !== undefined ? { isEnabled: Boolean(isEnabled) } : {}),
          ...(displayName !== undefined ? { displayName: String(displayName) } : {}),
          ...(instructions !== undefined ? { instructions: String(instructions) } : {}),
          ...(accountNumber !== undefined ? { accountNumber: String(accountNumber) } : {}),
          ...(accountName !== undefined ? { accountName: String(accountName) } : {}),
        });
        return NextResponse.json({ success: true, data });
      }

      case "approvePaymentClaim": {
        const { claimId, notes } = body;
        if (!claimId) {
          return NextResponse.json({ success: false, error: "claimId is required." }, { status: 400 });
        }
        const data = await client.mutation("payments:approvePaymentClaim" as any, {
          sessionToken,
          claimId,
          notes: notes ? String(notes) : undefined,
        });
        return NextResponse.json({ success: true, data });
      }

      case "rejectPaymentClaim": {
        const { claimId, rejectionReason } = body;
        if (!claimId || !rejectionReason?.trim()) {
          return NextResponse.json(
            { success: false, error: "claimId and rejectionReason are required." },
            { status: 400 }
          );
        }
        const data = await client.mutation("payments:rejectPaymentClaim" as any, {
          sessionToken,
          claimId,
          rejectionReason: String(rejectionReason).trim(),
        });
        return NextResponse.json({ success: true, data });
      }

      default:
        return NextResponse.json({ success: false, error: "Invalid payment action." }, { status: 400 });
    }
  } catch (err) {
    const vMsg = !isAuthError(err) ? validationMessage(err) : null;
    if (vMsg) {
      return NextResponse.json({ success: false, error: vMsg, code: "VALIDATION" }, { status: 400 });
    }
    return errorResponse(err, "Failed to process payment operation.", "api/payments POST");
  }
}
