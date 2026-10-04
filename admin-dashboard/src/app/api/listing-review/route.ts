// src/app/api/listing-review/route.ts
// Admin → Listing Review: the moderation queue (GET ?moderation=…), one listing in full (GET ?id=…)
// and decisions (POST approve / reject / remove / archive). Convex authorises the admin session,
// validates the transition and requires the reason; this route only forwards.
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";
import { errorResponse, isAuthError, missingSession, sessionFromRequest } from "@/lib/apiAuth";

const FILTERS = ["pending_review", "approved", "rejected", "removed", "all"];
const DECISIONS = ["approve", "reject", "remove", "archive"];

/** The backend's own user-facing validation message, without stack details. */
function validationMessage(err: unknown): string | null {
  const m = String((err as any)?.message ?? "").match(/Uncaught Error: ([^\n]{1,200})/);
  return m ? m[1].trim() : null;
}

export async function GET(request: Request) {
  const sessionToken = sessionFromRequest(request);
  if (!sessionToken) return missingSession();
  const params = new URL(request.url).searchParams;
  const id = params.get("id");
  const moderation = params.get("moderation") ?? "pending_review";
  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const data = id
      ? await client.query("listingModeration:adminGetListing" as any, { sessionToken, listingId: id })
      : await client.query("listingModeration:adminListListings" as any, {
          sessionToken,
          moderation: FILTERS.includes(moderation) ? moderation : "pending_review",
        });
    return NextResponse.json({ success: true, data }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err, "Could not load listings for review.", "api/listing-review GET");
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
  const decision = String(body?.decision ?? "");
  if (!DECISIONS.includes(decision)) return NextResponse.json({ success: false, error: "Unknown decision." }, { status: 400 });
  try {
    const client = new ConvexHttpClient(CONVEX_URL);
    const reason = typeof body.reason === "string" && body.reason.trim() ? body.reason.trim() : undefined;
    const data = await client.mutation("listingModeration:adminModerateListing" as any, {
      sessionToken,
      listingId: String(body.listingId ?? ""),
      decision,
      ...(reason ? { reason } : {}),
    });
    return NextResponse.json({ success: true, data });
  } catch (err) {
    const message = !isAuthError(err) ? validationMessage(err) : null;
    if (message) return NextResponse.json({ success: false, error: message, code: "VALIDATION" }, { status: 400 });
    return errorResponse(err, "Could not save the decision.", "api/listing-review POST");
  }
}
