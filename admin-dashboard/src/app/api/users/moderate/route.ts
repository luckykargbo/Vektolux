// src/app/api/users/moderate/route.ts
// POST: Moderate platform users (Verify, Suspend, Ban, Delete, Purge Mock Users)
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

const CONVEX_URL = process.env.NEXT_PUBLIC_CONVEX_URL ?? "https://incredible-possum-462.convex.cloud";

function getClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as {
      action: "verify" | "status" | "delete" | "purge_mock";
      adminId: string;
      sessionToken?: string;
      userId?: string;
      status?: "ACTIVE" | "SUSPENDED" | "BANNED";
    };

    const { action, adminId, sessionToken, userId, status } = body;

    if (!adminId) {
      return NextResponse.json(
        { success: false, error: "adminId is required." },
        { status: 400 }
      );
    }

    const client = getClient();

    switch (action) {
      case "verify": {
        if (!userId) {
          return NextResponse.json(
            { success: false, error: "userId is required for verification." },
            { status: 400 }
          );
        }
        const result = await client.mutation("admin:verifyUser" as any, {
          adminId,
          sessionToken,
          userId,
        });
        return NextResponse.json({ success: true, data: result });
      }

      case "status": {
        if (!userId || !status) {
          return NextResponse.json(
            { success: false, error: "userId and status ('ACTIVE' | 'SUSPENDED' | 'BANNED') are required." },
            { status: 400 }
          );
        }
        const result = await client.mutation("admin:setUserStatus" as any, {
          adminId,
          sessionToken,
          userId,
          status,
        });
        return NextResponse.json({ success: true, data: result });
      }

      case "delete": {
        if (!userId) {
          return NextResponse.json(
            { success: false, error: "userId is required for deletion." },
            { status: 400 }
          );
        }
        const result = await client.mutation("admin:deleteUser" as any, {
          adminId,
          sessionToken,
          userId,
        });
        return NextResponse.json({ success: true, data: result });
      }

      case "purge_mock": {
        const result = await client.mutation("admin:purgeMockUsers" as any, {
          adminId,
          sessionToken,
        });
        return NextResponse.json({ success: true, data: result });
      }

      default:
        return NextResponse.json(
          { success: false, error: `Unknown action: ${action}` },
          { status: 400 }
        );
    }
  } catch (err: any) {
    console.error("[user moderate POST] error:", err);
    return NextResponse.json(
      { success: false, error: err?.message ?? "Failed to perform user moderation action." },
      { status: 500 }
    );
  }
}
