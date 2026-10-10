// src/app/api/auth/me/route.ts
// Validates active admin cookie session against Convex and returns profile details
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { CONVEX_URL } from "@/lib/convex";
import { sessionFromRequest } from "@/lib/adminSession";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) {
    return NextResponse.json(
      { success: false, error: "Not signed in.", code: "UNAUTHORIZED" },
      { status: 401 }
    );
  }

  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const admin: any = await client.query("auth:getAdminSession" as any, { sessionToken });

    if (!admin || admin.role !== "admin") {
      return NextResponse.json(
        { success: false, error: "Administrator session required.", code: "UNAUTHORIZED" },
        { status: 401 }
      );
    }

    return NextResponse.json({
      success: true,
      user: {
        id: admin.userId,
        name: admin.name,
        email: admin.email,
        role: admin.role,
      },
    });
  } catch (err) {
    return NextResponse.json(
      { success: false, error: "Session validation failed.", code: "UNAUTHORIZED" },
      { status: 401 }
    );
  }
}
