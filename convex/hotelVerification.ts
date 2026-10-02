// convex/hotelVerification.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Hotel / guest-house verification (admin review).
//
//   pending ──approve──▶ verified ──suspend──▶ suspended ──reinstate──▶ verified
//      └──reject──▶ rejected ──(owner resubmits)──▶ pending
//
//  • The decision, the status and every timestamp are written by the SERVER from the admin's own
//    session; nothing is taken from the browser or the app.
//  • Every step is appended to hotel_verification_events (append-only: actor, time, from → to, note)
//    and to the admin audit log.
//  • Verification is independent of the operator's role approval and of their paid subscription:
//    approving a hotel never activates a subscription (lib/hotelAccess.ts).
//  • Existing hotels are never auto-verified; a row is verified only after an admin approves it here.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query, MutationCtx } from "./_generated/server";
import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { requireAdminSession, requireSelf } from "./lib/auth";
import { hotelIsVerified } from "./lib/hotelAccess";
import { activeSubscription, businessRole, isRoleApproved } from "./lib/permissions";

type Status = Doc<"hotel_profiles">["verificationStatus"];

/** A row marked verified without the matching isVerified flag (legacy data) is treated as PENDING review. */
const effectiveStatus = (h: Doc<"hotel_profiles">): Status =>
  h.verificationStatus === "verified" && !hotelIsVerified(h) ? "pending" : h.verificationStatus;
type EventAction = "SUBMITTED" | "RESUBMITTED" | "APPROVED" | "REJECTED" | "SUSPENDED" | "REINSTATED";

const statusValidator = v.union(v.literal("pending"), v.literal("verified"), v.literal("rejected"), v.literal("suspended"));
const MIN_NOTE = 5;

/** Appends to a hotel's verification history (never edited). Also used by hotels.ts on submission. */
export async function logHotelEvent(
  ctx: { db: any },
  hotelId: Id<"hotel_profiles">,
  action: EventAction,
  from: Status | undefined,
  to: Status,
  actor: { id: Id<"users">; role: "owner" | "admin" },
  note?: string
) {
  await ctx.db.insert("hotel_verification_events", {
    hotelId,
    action,
    fromStatus: from,
    toStatus: to,
    actorId: actor.id,
    actorRole: actor.role,
    note: note ? note.trim().slice(0, 1000) : undefined,
    at: Date.now(),
  });
}

const maskTin = (tin: string | undefined) => (tin ? `${"•".repeat(Math.max(0, tin.length - 3))}${tin.slice(-3)}` : null);

/** Admin: hotel applications (default: pending) with what a reviewer needs and nothing more. */
export const adminListHotelApplications = query({
  args: { sessionToken: v.optional(v.string()), status: v.optional(statusValidator) },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const wanted = args.status ?? "pending";
    const all = await ctx.db.query("hotel_profiles").order("desc").take(500);
    const rows = all.filter((h) => effectiveStatus(h) === wanted);
    const now = Date.now();
    const out = [];
    for (const h of rows.slice(0, 100)) {
      const operator = await ctx.db.get(h.userId);
      const events = await ctx.db.query("hotel_verification_events").withIndex("by_hotel", (q) => q.eq("hotelId", h._id)).collect();
      const eventsOut = [];
      for (const e of events) {
        const actor = await ctx.db.get(e.actorId);
        eventsOut.push({ action: e.action, from: e.fromStatus ?? null, to: e.toStatus, actorRole: e.actorRole, actorName: actor?.name ?? null, note: e.note ?? null, at: e.at });
      }
      const rooms = await ctx.db.query("hotel_rooms").withIndex("by_hotelId", (q) => q.eq("hotelId", h._id)).take(100);
      out.push({
        id: h._id as string,
        businessName: h.businessName,
        operationalType: h.operationalType,
        status: effectiveStatus(h),
        city: h.city,
        address: h.address, // business premises, shown to the reviewer only
        businessPhone: h.phone,
        businessEmail: h.email ?? null,
        tinMasked: maskTin(h.tinNumber),
        hasCommercialLicense: !!h.commercialLicenseUrl,
        roomsCount: rooms.length,
        submittedAt: h.submittedAt ?? null,
        reviewedAt: h.reviewedAt ?? null,
        verifiedAt: h.verifiedAt ?? null,
        reviewNote: h.reviewNote ?? null,
        operator: operator
          ? {
              name: operator.name ?? null,
              email: operator.email ?? null,
              role: businessRole(operator),
              roleApproved: isRoleApproved(operator),
              kycStatus: operator.verificationStatus ?? null,
              hasActiveSubscription: !!(await activeSubscription(ctx, operator._id, "hotel_operator", now)),
            }
          : null,
        events: eventsOut,
      });
    }
    return out;
  },
});

/**
 * Admin decision on a hotel. approve (pending→verified) · reject (pending→rejected, note) ·
 * suspend (verified→suspended, note) · reinstate (suspended→verified, note).
 * A repeat of a decision that already holds is refused (and records nothing).
 */
export const adminReviewHotel = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    hotelId: v.id("hotel_profiles"),
    decision: v.union(v.literal("approve"), v.literal("reject"), v.literal("suspend"), v.literal("reinstate")),
    note: v.optional(v.string()),
  },
  handler: async (ctx: MutationCtx, args) => {
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    const hotel = await ctx.db.get(args.hotelId);
    if (!hotel) throw new Error("Hotel not found.");
    const note = (args.note ?? "").trim();
    const from: Status = effectiveStatus(hotel);
    const needsNote = args.decision !== "approve";
    if (needsNote && note.length < MIN_NOTE) throw new Error("A note explaining the decision is required.");

    const transitions: Record<typeof args.decision, { from: Status; to: Status; event: EventAction }> = {
      approve: { from: "pending", to: "verified", event: "APPROVED" },
      reject: { from: "pending", to: "rejected", event: "REJECTED" },
      suspend: { from: "verified", to: "suspended", event: "SUSPENDED" },
      reinstate: { from: "suspended", to: "verified", event: "REINSTATED" },
    };
    const tr = transitions[args.decision];
    if (tr.to === "verified" && hotelIsVerified(hotel)) throw new Error("This property is already verified.");
    if (from !== tr.from) throw new Error(`Cannot ${args.decision} a property that is ${from}.`);
    if (tr.to === "verified") {
      const operator = await ctx.db.get(hotel.userId);
      if (!operator || operator.isActive === false) throw new Error("The operator's account is not active.");
    }

    const now = Date.now();
    await ctx.db.patch(hotel._id, {
      verificationStatus: tr.to,
      isVerified: tr.to === "verified",
      reviewedBy: adminId,
      reviewedAt: now,
      reviewNote: note ? note.slice(0, 1000) : undefined,
      ...(tr.to === "verified" ? { verifiedAt: now } : {}),
      updatedAt: now,
    });
    await logHotelEvent(ctx, hotel._id, tr.event, from, tr.to, { id: adminId, role: "admin" }, note);
    await ctx.db.insert("audit_logs", {
      adminUserId: adminId,
      action: "VERIFICATION_DECISION",
      targetTransactionId: hotel._id as string,
      snapshot: JSON.stringify({ kind: "hotel", decision: args.decision, from, to: tr.to, operatorId: hotel.userId, note: note || null }),
      timestamp: now,
    });
    await ctx.db.insert("user_notifications", {
      userId: hotel.userId as string,
      targetType: "single_user",
      title: `Hotel ${tr.to === "verified" ? "approved" : tr.to}`,
      body:
        tr.to === "verified"
          ? `"${hotel.businessName}" was verified. A paid subscription is still required to add rooms and take bookings.`
          : `"${hotel.businessName}" was ${tr.to}.${note ? ` Reason: ${note}` : ""}`,
      read: false,
      createdAt: now,
    });
    return { success: true, status: tr.to };
  },
});

/** Owner: resubmit a REJECTED application for another review (explicit pending state again). */
export const resubmitHotelApplication = mutation({
  args: { sessionToken: v.optional(v.string()), hotelId: v.id("hotel_profiles"), note: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const hotel = await ctx.db.get(args.hotelId);
    if (!hotel || hotel.userId !== userId) throw new Error("You do not have permission to manage this property.");
    if (hotel.verificationStatus !== "rejected") throw new Error("Only a rejected application can be resubmitted.");
    const now = Date.now();
    await ctx.db.patch(hotel._id, { verificationStatus: "pending", isVerified: false, submittedAt: now, updatedAt: now });
    await logHotelEvent(ctx, hotel._id, "RESUBMITTED", "rejected", "pending", { id: userId, role: "owner" }, args.note);
    return { success: true, status: "pending" as const };
  },
});
