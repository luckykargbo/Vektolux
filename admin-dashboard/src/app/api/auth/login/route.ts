// src/app/api/auth/login/route.ts
// Authenticates admin against live Convex backend via loginWithPhoneOrEmail
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { CONVEX_URL } from "@/lib/convex";



import { ADMIN_COOKIE_NAME, SESSION_MAX_AGE_SECONDS } from "@/lib/adminSession";

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({}));
    const { email, password, totpCode } = body as {
      email?: string;
      password?: string;
      totpCode?: string;
    };

    if (!email || !password) {
      return NextResponse.json(
        { success: false, error: "Invalid email or password." },
        { status: 400 }
      );
    }

    // No client IP is sent: Convex derives it from the request itself (ctx.meta). Headers such as
    // CF-Connecting-IP / X-Forwarded-For are caller-controlled unless the proxy topology guarantees them.
    const client = new ConvexHttpClient(CONVEX_URL);
    const result: any = await client.mutation("auth:loginWithPhoneOrEmail" as any, {
      identifier: email.trim(),
      password,
      totpCode: totpCode ? totpCode.trim() : undefined,
    });

    // Unified generic message for wrong credentials or non-admin roles
    const GENERIC_ERROR = "Invalid email or password.";

    if (!result || !result.success) {
      if (result?.mfaRequired) {
        return NextResponse.json(
          {
            success: false,
            mfaRequired: true,
            error: "Two-factor authentication code required.",
            code: "MFA_REQUIRED",
          },
          { status: 200 }
        );
      }

      const errorMsg = String(result?.errorMessage ?? "");
      const isRateLimited = errorMsg.toLowerCase().includes("too many failed attempts");
      const is2faError = errorMsg.toLowerCase().includes("two-factor") || errorMsg.toLowerCase().includes("2fa");

      return NextResponse.json(
        {
          success: false,
          error: isRateLimited
            ? "Too many failed login attempts. Please try again in 15 minutes."
            : is2faError
            ? errorMsg
            : GENERIC_ERROR,
          code: isRateLimited ? "RATE_LIMITED" : is2faError ? "INVALID_MFA" : "INVALID_CREDENTIALS",
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

