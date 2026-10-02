// src/app/api/listing-agents/route.ts
// Admin → Listing Agents: list authorisations (GET) and revoke one (POST, reason required).
// Convex authorises the admin session and validates every value; this route only forwards.
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";
import { errorResponse, isAuthError, missingSession, sessionFromRequest } from "@/lib/apiAuth";

const STATUSES = ["pending", "active", "declined", "revoked"];

/** The backend's own user-facing validation message, without stack details. */
function validationMessage(err: unknown): string | null {
  const m = String((err as any)?.message ?? "").match(/Uncaught Error: ([^\n]{1,200})/);
  return m ? m[1].trim() : null;
}

export async function GET(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) return missingSession();
  const status = new URL(request.url).searchParams.get("status") ?? "";
  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const data = await client.query("listingAgents:adminListListingAgents" as any, {
      sessionToken,
      ...(STATUSES.includes(status) ? { status } : {}),
    });
    return NextResponse.json({ success: true, data }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err, "Could not load listing agents.", "api/listing-agents GET");
  }
}

export async function POST(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) return missingSession();
  let body: any;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ success: false, error: "Invalid request." }, { status: 400 });
  }
  if (body?.action !== "revoke") return NextResponse.json({ success: false, error: "Unknown action." }, { status: 400 });
  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const data = await client.mutation("listingAgents:revokeListingAgent" as any, {
      sessionToken,
      authorizationId: String(body.authorizationId ?? ""),
      reason: String(body.reason ?? ""),
    });
    return NextResponse.json({ success: true, data });
  } catch (err) {
    const message = !isAuthError(err) ? validationMessage(err) : null;
    if (message) return NextResponse.json({ success: false, error: message, code: "VALIDATION" }, { status: 400 });
    return errorResponse(err, "Could not revoke the authorisation.", "api/listing-agents POST");
  }
}
