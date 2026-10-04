// src/app/api/roles/route.ts
// Admin → Business Roles: role applications (GET ?status=…) and decisions (POST approve / reject /
// suspend with notes). A Car Dealer approval for a Real Estate Agent is ADDED to the agent role by
// the backend (roles:adminDecideRoleApplication); this route only forwards.
import { NextResponse } from "next/server";
import { ConvexHttpClient } from "convex/browser";

import { CONVEX_URL } from "@/lib/convex";
import { errorResponse, isAuthError, missingSession, sessionFromRequest } from "@/lib/apiAuth";

const STATUSES = ["pending", "approved", "rejected", "suspended"];
const DECISIONS = ["approve", "reject", "suspend"];

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
    const data = await client.query("roles:adminListRoleApplications" as any, {
      sessionToken,
      ...(STATUSES.includes(status) ? { status } : {}),
    });
    return NextResponse.json({ success: true, data }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    return errorResponse(err, "Could not load role applications.", "api/roles GET");
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
    const notes = typeof body.notes === "string" && body.notes.trim() ? body.notes.trim() : undefined;
    const data = await client.mutation("roles:adminDecideRoleApplication" as any, {
      sessionToken,
      applicationId: String(body.applicationId ?? ""),
      decision,
      ...(notes ? { notes } : {}),
    });
    return NextResponse.json({ success: true, data });
  } catch (err) {
    const message = !isAuthError(err) ? validationMessage(err) : null;
    if (message) return NextResponse.json({ success: false, error: message, code: "VALIDATION" }, { status: 400 });
    return errorResponse(err, "Could not save the decision.", "api/roles POST");
  }
}
