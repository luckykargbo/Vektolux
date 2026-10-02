// src/app/api/users/moderate/route.ts
// POST: Moderate platform users (Verify, Suspend, Ban, Delete, Purge Mock Users)
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

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as {
      action: "verify" | "status" | "delete" | "purge_mock";
      adminId: string;
      userId?: string;
      status?: "ACTIVE" | "SUSPENDED" | "BANNED";
    };

    const { action, adminId, userId, status } = body;

    const sessionToken = sessionFromRequest(request);

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
    console.error("[user moderate POST] request failed");
    return NextResponse.json(
      { success: false, error: publicMessage(err, "Failed to perform user moderation action.") },
      { status: 500 }
    );
  }
}
