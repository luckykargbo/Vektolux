// src/app/api/users/route.ts
// GET: fetch all platform users  |  POST: toggle user active/suspended state
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";

function getClient() {
  return new ConvexHttpClient(CONVEX_URL);
}

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const adminId = searchParams.get("adminId");
    const sessionToken = searchParams.get("sessionToken") ?? undefined;
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
    console.error("[users GET] error:", err);
    const msg = err?.message ?? "Failed to fetch users.";
    const isUnauthorized = msg.includes("Unauthorized") || msg.includes("Forbidden") || msg.includes("session token");
    return NextResponse.json(
      { success: false, error: msg, code: isUnauthorized ? "UNAUTHORIZED" : "SERVER_ERROR" },
      { status: isUnauthorized ? 401 : 500 }
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as {
      adminId: string;
      sessionToken?: string;
      userId: string;
      isActive: boolean;
    };

    const { adminId, sessionToken, userId, isActive } = body;

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
    console.error("[users POST] error:", err);
    const msg = err?.message ?? "Failed to update user status.";
    const isUnauthorized = msg.includes("Unauthorized") || msg.includes("Forbidden") || msg.includes("session token");
    return NextResponse.json(
      { success: false, error: msg, code: isUnauthorized ? "UNAUTHORIZED" : "SERVER_ERROR" },
      { status: isUnauthorized ? 401 : 500 }
    );
  }
}
