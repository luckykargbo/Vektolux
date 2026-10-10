// src/app/api/auth/logout/route.ts
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { CONVEX_URL } from "@/lib/convex";
import { ADMIN_COOKIE_NAME, sessionFromRequest } from "@/lib/adminSession";

export async function POST(request: Request) {
  try {
    const sessionToken = sessionFromRequest(request);

    if (sessionToken) {
      try {
        const client = new ConvexHttpClient(CONVEX_URL);
        await client.mutation("auth:logout" as any, { sessionToken });
      } catch (err) {
        console.error("[logout] Convex session invalidation failed:", err);
      }
    }

    const response = NextResponse.json({ success: true });

    // Clear the HttpOnly admin session cookie
    response.cookies.set({
      name: ADMIN_COOKIE_NAME,
      value: "",
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "strict",
      path: "/",
      maxAge: 0,
      expires: new Date(0),
    });

    return response;
  } catch (err) {
    console.error("[logout] request failed:", err);
    return NextResponse.json({ success: false, error: "Logout failed." }, { status: 500 });
  }
}
