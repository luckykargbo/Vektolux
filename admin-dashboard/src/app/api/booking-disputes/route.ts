// src/app/api/booking-disputes/route.ts
// Admin → Booking Disputes: list (GET) and settle (POST: release to vendor / refund buyer).
// Convex authorises the admin session, decides every amount, enforces the dispute rules and audits;
// this route only forwards the admin's decision, note and the server amount they confirmed.
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";
import { errorResponse, isAuthError, missingSession, sessionFromRequest } from "@/lib/apiAuth";

const VIEWS = ["open", "held", "resolved"];

function validationMessage(err: unknown): string | null {
  const m = String((err as any)?.message ?? "").match(/Uncaught Error: ([^\n]{1,200})/);
  return m ? m[1].trim() : null;
}

export async function GET(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) return missingSession();
  const view = new URL(request.url).searchParams.get("view") ?? "open";
  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const data = await client.query("bookings:adminListBookingDisputes" as any, {
      sessionToken,
      view: VIEWS.includes(view) ? view : "open",
    });
    return NextResponse.json({ success: true, data }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err, "Could not load booking disputes.", "api/booking-disputes GET");
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
  const resolution = body?.resolution;
  if (resolution !== "release_to_vendor" && resolution !== "refund_buyer") {
    return NextResponse.json({ success: false, error: "Unknown action." }, { status: 400 });
  }
  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const data = await client.mutation("bookings:adminResolveBookingDispute" as any, {
      sessionToken,
      bookingId: String(body.bookingId ?? ""),
      resolution,
      note: String(body.note ?? ""),
      // only a staleness check: the server recomputes the amount and rejects a mismatch
      ...(typeof body.expectedAmount === "number" ? { expectedAmount: body.expectedAmount } : {}),
    });
    return NextResponse.json({ success: true, data });
  } catch (err) {
    const message = !isAuthError(err) ? validationMessage(err) : null;
    if (message) return NextResponse.json({ success: false, error: message, code: "VALIDATION" }, { status: 400 });
    return errorResponse(err, "The decision could not be applied.", "api/booking-disputes POST");
  }
}
