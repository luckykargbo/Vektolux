// src/app/api/users/route.ts
// GET: fetch all platform users  |  POST: toggle user active/suspended state
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
    const { searchParams } = new URL(request.url);
    const adminId = searchParams.get("adminId");
    const sessionToken = sessionFromRequest(request);
    const roleFilter = searchParams.get("role") ?? undefined;
    const searchQuery = searchParams.get("q") ?? undefined;

    if (!adminId) {
      return NextResponse.json({ success: false, error: "adminId is required" }, { status: 400 });
    }

    const client = getClient();
    const result = await client.query("admin:getAllUsers" as any, {
      adminId,
      sessionToken,
      roleFilter: roleFilter === "all" ? undefined : roleFilter,
      searchQuery: searchQuery || undefined,
    });

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    console.error("[users GET] request failed");
    const msg = "Failed to fetch users.";
    const isUnauthorized = isAuthError(err);
    return NextResponse.json(
      { success: false, error: publicMessage(err, msg), code: isUnauthorized ? "UNAUTHORIZED" : "SERVER_ERROR" },
      { status: isUnauthorized ? 401 : 500 }
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as {
      adminId: string;
      userId: string;
      isActive: boolean;
    };

    const { adminId, userId, isActive } = body;

    const sessionToken = sessionFromRequest(request);

    if (!adminId || !userId) {
      return NextResponse.json(
        { success: false, error: "adminId and userId are required." },
        { status: 400 }
      );
    }

    const client = getClient();
    const result = await client.mutation("admin:toggleUserActiveStatus" as any, {
      adminId,
      sessionToken,
      userId,
      isActive,
    });

    return NextResponse.json({ success: true, data: result });
  } catch (err: any) {
    console.error("[users POST] request failed");
    const msg = "Failed to update user status.";
    const isUnauthorized = isAuthError(err);
    return NextResponse.json(
      { success: false, error: publicMessage(err, msg), code: isUnauthorized ? "UNAUTHORIZED" : "SERVER_ERROR" },
      { status: isUnauthorized ? 401 : 500 }
    );
  }
}
