// src/app/api/verifications/route.ts
// GET: fetch verification queue  |  POST: approve or reject an agent
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { isAuthError, sessionFromRequest } from "@/lib/apiAuth";
import { CONVEX_URL } from "@/lib/convex";

function getClient() { return new ConvexHttpClient(CONVEX_URL); }

/** Never send internal error text to the browser. */
function publicMessage(err: unknown, fallback: string): string {
  return isAuthError(err) ? "Administrator access required. Please sign in again." : fallback;
}

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const adminId = searchParams.get("adminId");
    const sessionToken = sessionFromRequest(request);
    const statusFilter = (searchParams.get("status") ?? "pending") as any;

    if (!adminId) {
      return NextResponse.json({ success: false, error: "adminId is required" }, { status: 400 });
    }

    const client = getClient();
    const result = await client.query("businessVerification:getVerificationQueue" as any, {
      adminId,
      sessionToken,
      statusFilter,
    });

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    console.error("[verifications GET] request failed");
    return NextResponse.json({ success: false, error: publicMessage(err, "Failed to fetch queue.") }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json() as {
      action: "approve" | "reject";
      adminId: string;
      agentId: string;
      reason?: string;
    };

    const { action, adminId, agentId, reason } = body;

    const sessionToken = sessionFromRequest(request);

    if (!adminId || !agentId) {
      return NextResponse.json({ success: false, error: "adminId and agentId are required." }, { status: 400 });
    }

    const client = getClient();
    let result: any;

    if (action === "approve") {
      result = await client.mutation("businessVerification:approveAgent" as any, {
        adminId,
        sessionToken,
        agentId,
      });
    } else if (action === "reject") {
      if (!reason) {
        return NextResponse.json({ success: false, error: "Rejection reason is required." }, { status: 400 });
      }
      result = await client.mutation("businessVerification:rejectAgent" as any, {
        adminId,
        sessionToken,
        agentId,
        reason,
      });
    } else {
      return NextResponse.json({ success: false, error: "Invalid action. Use approve or reject." }, { status: 400 });
    }

    if (!result?.success) {
      return NextResponse.json(
        { success: false, error: result?.errorMessage ?? `${action} failed.` },
        { status: 400 }
      );
    }

    return NextResponse.json({ success: true });
  } catch (err: any) {
    console.error("[verifications POST] request failed");
    return NextResponse.json({ success: false, error: publicMessage(err, "Operation failed.") }, { status: 500 });
  }
}
