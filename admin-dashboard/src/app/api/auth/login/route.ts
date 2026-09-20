// src/app/api/auth/login/route.ts
// Authenticates admin against live Convex backend via loginWithPhoneOrEmail
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import dns from "node:dns";
import { CONVEX_URL } from "@/lib/convex";

try {
  dns.setDefaultResultOrder("ipv4first");
} catch (_) {}

export async function POST(request: Request) {
  try {
    const { email, password } = await request.json() as { email: string; password: string };

    if (!email || !password) {
      return NextResponse.json({ success: false, error: "Email and password are required." }, { status: 400 });
    }

    let result: any;
    try {
      const client = new ConvexHttpClient(CONVEX_URL);
      result = await client.mutation("auth:loginWithPhoneOrEmail" as any, {
        identifier: email,
        password,
      });
    } catch (primaryErr: any) {
      console.warn("[login] primary URL failed:", primaryErr?.message, "- attempting failover");
      const fallbackUrl = CONVEX_URL.includes("ideal-poodle-813")
        ? "https://incredible-possum-462.convex.cloud"
        : "https://ideal-poodle-813.convex.cloud";
      const fallbackClient = new ConvexHttpClient(fallbackUrl);
      result = await fallbackClient.mutation("auth:loginWithPhoneOrEmail" as any, {
        identifier: email,
        password,
      });
    }

    if (!result || !result.success) {
      return NextResponse.json(
        { success: false, error: result?.errorMessage ?? "Invalid credentials." },
        { status: 401 }
      );
    }

    // Verify the logged-in user is an admin
    if (result.role !== "admin") {
      return NextResponse.json(
        { success: false, error: "Access denied. This dashboard is restricted to administrators." },
        { status: 403 }
      );
    }

    const session = {
      user: {
        id: result.userId,
        name: result.name,
        email: result.email ?? email,
        sessionToken: result.sessionToken,
      },
      loggedInAt: Date.now(),
    };

    return NextResponse.json({ success: true, session });
  } catch (err: any) {
    console.error("[login] error:", err);
    return NextResponse.json(
      { success: false, error: err?.message ?? "Server error during login." },
      { status: 500 }
    );
  }
}
