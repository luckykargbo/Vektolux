// src/lib/apiAuth.ts — server-only helpers for the admin API routes.
//
// Authentication: the admin's Convex session token travels ONLY in the `x-vektolux-session`
// header set by `adminFetch` (never in a URL, never in a request body). Because the token is not
// an ambient cookie, a cross-site page cannot make an authenticated request (CSRF-safe by design).
// Convex re-authorises every call from that token; no admin id is trusted on its own.
//
// Errors: internal error text is never sent to the browser (it can expose backend details); it is
// mapped to a short generic message, and only a route tag is logged.
import { NextResponse } from "next/server";
import { sessionFromRequest } from "./adminSession";

export { sessionFromRequest };

const AUTH_PATTERN = /unauthori|forbidden|authentication required|session|admin/i;

export function isAuthError(err: unknown): boolean {
  return AUTH_PATTERN.test(String((err as any)?.message ?? ""));
}

/** JSON error response with a generic, safe message. */
export function errorResponse(err: unknown, fallback: string, tag: string): NextResponse {
  const auth = isAuthError(err);
  console.error(`[${tag}] request failed${auth ? " (not authorised)" : ""}`);
  return NextResponse.json(
    {
      success: false,
      error: auth ? "Administrator access required. Please sign in again." : fallback,
      code: auth ? "UNAUTHORIZED" : "SERVER_ERROR",
    },
    { status: auth ? 401 : 500 }
  );
}

/** 401 response when the request carries no admin session header. */
export function missingSession(): NextResponse {
  return NextResponse.json(
    { success: false, error: "Not signed in.", code: "UNAUTHORIZED" },
    { status: 401 }
  );
}
