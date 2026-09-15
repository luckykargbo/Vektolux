// src/app/api/verifications/route.ts
// GET: fetch verification queue  |  POST: approve or reject an agent
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

const CONVEX_URL = process.env.NEXT_PUBLIC_CONVEX_URL ?? "https://incredible-possum-462.convex.cloud";

function getClient() { return new ConvexHttpClient(CONVEX_URL); }

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const adminId = searchParams.get("adminId");
    const sessionToken = searchParams.get("sessionToken") ?? undefined;
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
    console.error("[verifications GET] error:", err);
    return NextResponse.json({ success: false, error: err?.message ?? "Failed to fetch queue." }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json() as {
      action: "approve" | "reject";
      adminId: string;
      sessionToken?: string;
      agentId: string;
      reason?: string;
    };

    const { action, adminId, sessionToken, agentId, reason } = body;

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
    console.error("[verifications POST] error:", err);
    return NextResponse.json({ success: false, error: err?.message ?? "Operation failed." }, { status: 500 });
  }
}
