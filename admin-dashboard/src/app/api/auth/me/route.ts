// src/app/api/auth/me/route.ts
// Validates active admin cookie session against Convex and returns profile details
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { CONVEX_URL } from "@/lib/convex";
import { ADMIN_COOKIE_NAME, sessionFromRequest } from "@/lib/adminSession";

export const dynamic = "force-dynamic";

function unauthorizedResponse(errorMsg: string) {
  const res = NextResponse.json(
    { success: false, error: errorMsg, code: "UNAUTHORIZED" },
    { status: 401 }
  );
  // Actively wipe the invalid or expired cookie to prevent client redirect loops
  res.cookies.set({
    name: ADMIN_COOKIE_NAME,
    value: "",
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "strict",
    path: "/",
    maxAge: 0,
    expires: new Date(0),
  });
  return res;
}

export async function GET(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) {
    return unauthorizedResponse("Not signed in.");
  }

  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const admin: any = await client.query("auth:getAdminSession" as any, { sessionToken });

    if (!admin || admin.role !== "admin") {
      return unauthorizedResponse("Administrator session required.");
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
    return unauthorizedResponse("Session validation failed.");
  }
}
