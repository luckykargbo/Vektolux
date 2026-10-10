// src/app/api/auth/login/route.ts
// Authenticates admin against live Convex backend via loginWithPhoneOrEmail
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { CONVEX_URL } from "@/lib/convex";



import { ADMIN_COOKIE_NAME, SESSION_MAX_AGE_SECONDS } from "@/lib/adminSession";

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({}));
    const { email, password } = body as { email?: string; password?: string };

    if (!email || !password) {
      return NextResponse.json(
        { success: false, error: "Invalid email or password." },
        { status: 400 }
      );
    }

    // Extract client IP for rate limiting
    const clientIp =
      request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
      request.headers.get("x-real-ip")?.trim() ||
      "unknown_ip";

    const client = new ConvexHttpClient(CONVEX_URL);
    const result: any = await client.mutation("auth:loginWithPhoneOrEmail" as any, {
      identifier: email.trim(),
      password,
      ip: clientIp,
    });

    // Unified generic message for wrong credentials or non-admin roles
    const GENERIC_ERROR = "Invalid email or password.";

    if (!result || !result.success) {
      const errorMsg = String(result?.errorMessage ?? "");
      const isRateLimited = errorMsg.toLowerCase().includes("too many failed attempts");
      return NextResponse.json(
        {
          success: false,
          error: isRateLimited
            ? "Too many failed login attempts. Please try again in 15 minutes."
            : GENERIC_ERROR,
          code: isRateLimited ? "RATE_LIMITED" : "INVALID_CREDENTIALS",
        },
        { status: isRateLimited ? 429 : 401 }
      );
    }

    // If the account is valid but not an administrator, return the identical 401 error
    if (result.role !== "admin") {
      return NextResponse.json(
        { success: false, error: GENERIC_ERROR, code: "INVALID_CREDENTIALS" },
        { status: 401 }
      );
    }

    // Safe session details without exposing the secret session token to client JS
    const safeSession = {
      user: {
        id: result.userId,
        name: result.name,
        email: result.email ?? email,
        role: result.role,
      },
      loggedInAt: Date.now(),
    };

    const response = NextResponse.json({ success: true, session: safeSession });

    // Set HttpOnly, Secure, SameSite=Strict cookie
    response.cookies.set({
      name: ADMIN_COOKIE_NAME,
      value: result.sessionToken,
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "strict",
      path: "/",
      maxAge: SESSION_MAX_AGE_SECONDS,
    });

    return response;
  } catch (err: any) {
    console.error("[login] request failed");
    return NextResponse.json(
      { success: false, error: "Sign-in is temporarily unavailable. Please try again." },
      { status: 500 }
    );
  }
}

