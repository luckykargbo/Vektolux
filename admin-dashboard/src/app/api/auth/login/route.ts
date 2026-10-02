// src/app/api/auth/login/route.ts
// Authenticates admin against live Convex backend via loginWithPhoneOrEmail
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";
import { CONVEX_URL } from "@/lib/convex";



export async function POST(request: Request) {
  try {
    const { email, password } = await request.json() as { email: string; password: string };

    if (!email || !password) {
      return NextResponse.json({ success: false, error: "Email and password are required." }, { status: 400 });
    }

    // Only the configured deployment is ever used. (A previous "failover" silently sent admin
    // credentials to a different Convex deployment.)
    const client = new ConvexHttpClient(CONVEX_URL);
    const result: any = await client.mutation("auth:loginWithPhoneOrEmail" as any, {
      identifier: email,
      password,
    });

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
    console.error("[login] request failed");
    return NextResponse.json(
      { success: false, error: "Sign-in is temporarily unavailable. Please try again." },
      { status: 500 }
    );
  }
}
