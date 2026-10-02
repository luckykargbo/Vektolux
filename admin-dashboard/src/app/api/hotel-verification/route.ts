// src/app/api/hotel-verification/route.ts
// Admin → Hotels: list applications (GET) and approve / reject / suspend / reinstate (POST).
// Convex authorises the admin session, validates the state change, records the actor, time and
// note, and writes the audit trail; this route only forwards the admin's decision.
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";
import { errorResponse, isAuthError, missingSession, sessionFromRequest } from "@/lib/apiAuth";

const STATUSES = ["pending", "verified", "rejected", "suspended"];
const DECISIONS = ["approve", "reject", "suspend", "reinstate"];

function validationMessage(err: unknown): string | null {
  const m = String((err as any)?.message ?? "").match(/Uncaught Error: ([^\n]{1,200})/);
  return m ? m[1].trim() : null;
}

export async function GET(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) return missingSession();
  const status = new URL(request.url).searchParams.get("status") ?? "pending";
  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const data = await client.query("hotelVerification:adminListHotelApplications" as any, {
      sessionToken,
      status: STATUSES.includes(status) ? status : "pending",
    });
    return NextResponse.json({ success: true, data }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err, "Could not load hotel applications.", "api/hotel-verification GET");
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
  if (!DECISIONS.includes(body?.decision)) return NextResponse.json({ success: false, error: "Unknown decision." }, { status: 400 });
  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const data = await client.mutation("hotelVerification:adminReviewHotel" as any, {
      sessionToken,
      hotelId: String(body.hotelId ?? ""),
      decision: body.decision,
      note: typeof body.note === "string" ? body.note : undefined,
    });
    return NextResponse.json({ success: true, data });
  } catch (err) {
    const message = !isAuthError(err) ? validationMessage(err) : null;
    if (message) return NextResponse.json({ success: false, error: message, code: "VALIDATION" }, { status: 400 });
    return errorResponse(err, "The decision could not be applied.", "api/hotel-verification POST");
  }
}
