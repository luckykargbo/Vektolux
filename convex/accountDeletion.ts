// convex/accountDeletion.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Completion of scheduled account deletion.
//
// users.requestAccountDeletion only SCHEDULES (deletionScheduledFor = request + 30 days) and
// signing in cancels it. This module performs the final, retention-aware erasure for accounts
// whose window has elapsed.
//
// What it does for a due account:
//   • removes sign-in methods, sessions, push tokens, saved listings, follows, notifications,
//     pending verification/reset codes (auth data and personal convenience data);
//   • ANONYMISES the users row IN PLACE (same _id) so every financial, escrow, dispute, booking
//     and audit record keeps a valid reference, but no longer identifies a person.
//   • unpublishes the account's listings and clears their private contact phone, cancels open QR
//     payment requests, and blanks public contact fields on agent / hotel profiles.
// What it deliberately KEEPS: wallet balances, transactions, ledger entries, escrow orders,
// real-estate escrow contracts / milestones / caution deposits, disputes, bookings, withdrawal
// records, payment reversals and audit logs, KYC / identity-verification artifacts and role
// applications, and contact requests / messages (the counterparty's record). How long KYC and
// communications are kept is an owner / legal decision; nothing here deletes them.
//
// It is idempotent and retry-safe, never touches an account with funds or open obligations
// (the account stays scheduled and is re-checked on the next run), and never acts on admins.
//
// NOT scheduled: nothing in crons.ts calls this until the owner enables background jobs.
// ═══════════════════════════════════════════════════════════════════════

import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import type { Doc } from "./_generated/dataModel";

const BATCH_USERS_DEFAULT = 20;
const CHILD_ROW_CAP = 200;

const ESCROW_TERMINAL = new Set(["SETTLED", "REFUNDED", "CANCELLED"]);
const BOOKING_OPEN_STATUS = new Set(["pending_payment", "confirmed", "in_progress", "disputed"]);
const BOOKING_OPEN_SETTLEMENT = new Set(["held", "disputed"]);
// Real-estate escrow (reMilestoneState): anything not finished is an open obligation.
const RE_STATE_TERMINAL = new Set(["FULLY_SETTLED", "REFUNDED", "CANCELLED"]);
const CAUTION_OPEN = new Set(["LOCKED", "REFUND_INITIATED", "IN_DISPUTE"]);
const RE_DISPUTE_OPEN = new Set(["OPENED", "EVIDENCE_SUBMITTED", "IN_CONCILIATION"]);
const ESCROW_DISPUTE_OPEN = new Set(["OPENED", "UNDER_REVIEW"]);
const HOTEL_BOOKING_CLOSED = new Set(["completed_payout", "cancelled", "refunded"]);
const PAYMENT_IN_FLIGHT = new Set(["pending", "processing"]);
const CLAIM_OPEN = new Set(["PENDING_PAYMENT", "PENDING_APPROVAL", "ESCROW_LOCKED"]);

/** Reason the account cannot be erased yet, or null when it is safe to proceed. */
async function openObligation(ctx: MutationCtx, user: Doc<"users">, now: number): Promise<string | null> {
  const balances = await ctx.db.query("walletBalances").withIndex("by_user", (q) => q.eq("userId", user._id)).take(20);
  if (balances.some((b) => b.availableBalance > 0 || b.pendingBalance > 0 || (b.escrowBalance ?? 0) > 0)) {
    return "FUNDS_REMAINING";
  }
  const withdrawals = await ctx.db.query("withdrawal_requests").withIndex("by_user", (q) => q.eq("userId", user._id)).take(100);
  if (withdrawals.some((w) => w.status === "pending" || w.status === "processing")) return "WITHDRAWAL_IN_FLIGHT";

  const asBuyer = await ctx.db.query("escrow_orders").withIndex("by_renter_or_buyer", (q) => q.eq("renterOrBuyerId", user._id)).take(100);
  const asSeller = await ctx.db.query("escrow_orders").withIndex("by_owner_or_seller", (q) => q.eq("ownerOrSellerId", user._id)).take(100);
  if ([...asBuyer, ...asSeller].some((o) => !ESCROW_TERMINAL.has(o.status))) return "ESCROW_OPEN";

  const idStr = user._id as string;
  const buying = await ctx.db.query("bookings").withIndex("by_buyer", (q) => q.eq("buyerId", idStr)).take(100);
  const selling = await ctx.db.query("bookings").withIndex("by_vendor", (q) => q.eq("vendorId", idStr)).take(100);
  if (
    [...buying, ...selling].some(
      (b) => BOOKING_OPEN_STATUS.has(b.status) || (b.settlementStatus !== undefined && BOOKING_OPEN_SETTLEMENT.has(b.settlementStatus))
    )
  ) {
    return "BOOKING_OPEN";
  }

  // Vehicle escrow disputes (disputes hang off the user's escrow orders).
  for (const order of [...asBuyer, ...asSeller]) {
    const disputes = await ctx.db.query("escrow_disputes").withIndex("by_order", (q) => q.eq("escrowOrderId", order._id)).take(20);
    if (disputes.some((d) => ESCROW_DISPUTE_OPEN.has(d.status))) return "ESCROW_DISPUTE_OPEN";
  }

  // Real-estate escrow: contracts, caution deposits and disputes where the user is client,
  // beneficiary (owner) or the agent.
  const contracts = new Map<string, Doc<"re_escrow_contracts">>();
  for (const rows of [
    await ctx.db.query("re_escrow_contracts").withIndex("by_client", (q) => q.eq("clientId", user._id)).take(100),
    await ctx.db.query("re_escrow_contracts").withIndex("by_beneficiary", (q) => q.eq("beneficiaryId", user._id)).take(100),
    await ctx.db.query("re_escrow_contracts").withIndex("by_agentId", (q) => q.eq("agentId", user._id)).take(100),
  ]) {
    for (const c of rows) contracts.set(c._id as string, c);
  }
  for (const c of contracts.values()) {
    if (!RE_STATE_TERMINAL.has(c.currentState)) return "RE_ESCROW_OPEN";
    const deposits = await ctx.db.query("re_caution_deposits").withIndex("by_contract", (q) => q.eq("contractId", c._id)).take(20);
    if (deposits.some((d) => CAUTION_OPEN.has(d.status))) return "CAUTION_DEPOSIT_OPEN";
    const disputes = await ctx.db.query("re_escrow_disputes").withIndex("by_contract", (q) => q.eq("contractId", c._id)).take(20);
    if (disputes.some((d) => RE_DISPUTE_OPEN.has(d.status))) return "RE_DISPUTE_OPEN";
  }
  const passes = [
    ...(await ctx.db.query("re_inspection_passes").withIndex("by_client", (q) => q.eq("clientId", user._id)).take(100)),
    ...(await ctx.db.query("re_inspection_passes").withIndex("by_agent", (q) => q.eq("agentId", user._id)).take(100)),
  ];
  if (passes.some((p) => !RE_STATE_TERMINAL.has(p.status))) return "INSPECTION_PASS_OPEN";

  const reBookings = [
    ...(await ctx.db.query("realEstateBookings").withIndex("by_buyer", (q) => q.eq("buyerId", user._id)).take(100)),
    ...(await ctx.db.query("realEstateBookings").withIndex("by_owner", (q) => q.eq("ownerId", user._id)).take(100)),
  ];
  if (reBookings.some((b) => PAYMENT_IN_FLIGHT.has(b.paymentStatus))) return "PROPERTY_BOOKING_PAYMENT_OPEN";

  // Hotels: as a guest, and as the operator of any hotel profile.
  const stays = await ctx.db.query("hotel_bookings").withIndex("by_guestId", (q) => q.eq("guestId", user._id)).take(100);
  if (stays.some((b) => !HOTEL_BOOKING_CLOSED.has(b.status))) return "HOTEL_BOOKING_OPEN";
  const hotels = await ctx.db.query("hotel_profiles").withIndex("by_userId", (q) => q.eq("userId", user._id)).take(20);
  for (const h of hotels) {
    const hostStays = await ctx.db.query("hotel_bookings").withIndex("by_hotelId", (q) => q.eq("hotelId", h._id)).take(200);
    if (hostStays.some((b) => !HOTEL_BOOKING_CLOSED.has(b.status))) return "HOTEL_BOOKING_OPEN";
  }

  // Refund / recovery cases and money still in flight.
  const asRecipient = await ctx.db
    .query("payment_reversals")
    .withIndex("by_recipient_status", (q) => q.eq("recipientId", user._id).eq("status", "pending_recovery"))
    .take(1);
  if (asRecipient.length > 0) return "REVERSAL_RECOVERY_OPEN";
  const openReversals = await ctx.db.query("payment_reversals").withIndex("by_status", (q) => q.eq("status", "pending_recovery")).take(200);
  if (openReversals.some((r) => r.buyerId === user._id)) return "REVERSAL_RECOVERY_OPEN";

  for (const status of CLAIM_OPEN) {
    const claims = await ctx.db
      .query("escrow_payment_claims")
      .withIndex("by_userId_status", (q) => q.eq("userId", user._id).eq("status", status as any))
      .take(1);
    if (claims.length > 0) return "PAYMENT_CLAIM_OPEN";
  }
  const intents = await ctx.db.query("paymentIntents").withIndex("by_user", (q) => q.eq("userId", user._id)).take(100);
  if (intents.some((i) => PAYMENT_IN_FLIGHT.has(i.status))) return "PAYMENT_INTENT_OPEN";

  // A paid professional subscription still running (or in payment dunning) is not forfeited silently:
  // the account waits until it has expired or been cancelled.
  const subs = await ctx.db.query("vendor_subscriptions").withIndex("by_userId", (q) => q.eq("userId", user._id)).take(50);
  if (subs.some((sub) => sub.status === "dunning" || (sub.status === "active" && sub.expiryDate > now))) {
    return "SUBSCRIPTION_ACTIVE";
  }

  // Listing-agent relationships (invited or active) must be ended first: another professional's
  // authority over a listing cannot outlive the person who granted or holds it.
  const asOwner = await ctx.db.query("listing_agent_authorizations").withIndex("by_owner", (q) => q.eq("ownerId", user._id)).take(100);
  const asAgent = await ctx.db.query("listing_agent_authorizations").withIndex("by_agent", (q) => q.eq("agentId", user._id)).take(100);
  if ([...asOwner, ...asAgent].some((a) => a.status === "pending" || a.status === "active")) {
    return "AGENT_AUTHORIZATION_ACTIVE";
  }
  return null;
}

type Counts = Record<string, number>;

/** Deletes up to CHILD_ROW_CAP rows; returns how many were deleted and whether more remain. */
async function drain(ctx: MutationCtx, rows: Array<{ _id: any }>): Promise<{ n: number; more: boolean }> {
  for (const r of rows) await ctx.db.delete(r._id);
  return { n: rows.length, more: rows.length >= CHILD_ROW_CAP };
}

/** Removes auth + convenience rows for the user. Returns null when more rows remain (run again). */
async function eraseChildRows(ctx: MutationCtx, user: Doc<"users">): Promise<Counts | null> {
  const id = user._id;
  const idStr = id as string;
  const counts: Counts = {};
  let more = false;
  const run = async (name: string, rows: Array<{ _id: any }>) => {
    const r = await drain(ctx, rows);
    counts[name] = r.n;
    more = more || r.more;
  };

  await run("auth_identities", await ctx.db.query("auth_identities").withIndex("by_userId", (q) => q.eq("userId", id)).take(CHILD_ROW_CAP));
  await run("user_fcm_tokens", await ctx.db.query("user_fcm_tokens").withIndex("by_user", (q) => q.eq("userId", idStr)).take(CHILD_ROW_CAP));
  await run("user_sessions", await ctx.db.query("user_sessions").withIndex("by_userId", (q) => q.eq("userId", id)).take(CHILD_ROW_CAP));
  await run("email_verifications", await ctx.db.query("email_verifications").withIndex("by_userId", (q) => q.eq("userId", id)).take(CHILD_ROW_CAP));
  await run("saved_listings", await ctx.db.query("saved_listings").withIndex("by_userId_and_createdAt", (q) => q.eq("userId", id)).take(CHILD_ROW_CAP));
  await run("follows_out", await ctx.db.query("follows").withIndex("by_follower", (q) => q.eq("followerId", id)).take(CHILD_ROW_CAP));
  await run("follows_in", await ctx.db.query("follows").withIndex("by_following", (q) => q.eq("followingId", id)).take(CHILD_ROW_CAP));
  await run(
    "user_notifications",
    (await ctx.db.query("user_notifications").withIndex("by_user", (q) => q.eq("userId", idStr)).take(CHILD_ROW_CAP)).filter(
      (n) => n.targetType === "single_user"
    )
  );
  // Public surfaces: the account's listings stop being shown and lose their private contact phone;
  // open QR payment requests are cancelled so nobody can pay an erased account.
  // (Only rows that still need the change are counted, so a re-run converges instead of looping.)
  const propertyListings = (
    await ctx.db.query("realEstateListings").withIndex("by_owner", (q) => q.eq("ownerId", id)).take(CHILD_ROW_CAP)
  ).filter((l) => l.isPublished !== false || l.privateContactPhone !== undefined);
  for (const l of propertyListings) {
    await ctx.db.patch(l._id, { isPublished: false, privateContactPhone: undefined });
  }
  counts["property_listings_unpublished"] = propertyListings.length;
  more = more || propertyListings.length >= CHILD_ROW_CAP;
  const vehicleListings = (
    await ctx.db.query("vehicleListings").withIndex("by_owner", (q) => q.eq("ownerId", id)).take(CHILD_ROW_CAP)
  ).filter((l) => l.isPublished !== false);
  for (const l of vehicleListings) {
    await ctx.db.patch(l._id, { isPublished: false });
  }
  counts["vehicle_listings_unpublished"] = vehicleListings.length;
  more = more || vehicleListings.length >= CHILD_ROW_CAP;
  const qrs = (
    await ctx.db.query("qr_payment_requests").withIndex("by_receiver", (q) => q.eq("receiverId", id)).take(CHILD_ROW_CAP)
  ).filter((q) => q.status === "active");
  for (const q of qrs) await ctx.db.patch(q._id, { status: "cancelled", updatedAt: Date.now() });
  counts["qr_requests_cancelled"] = qrs.length;
  more = more || qrs.length >= CHILD_ROW_CAP;

  // Public contact details on professional profiles (KYC fields such as TIN are retained).
  const agentProfiles = await ctx.db.query("agent_profiles").withIndex("by_userId", (q) => q.eq("userId", id)).take(5);
  for (const ap of agentProfiles) {
    await ctx.db.patch(ap._id, {
      publicContactPhone: "", publicWhatsAppPhone: undefined, officeAddress: "", officeLatitude: undefined,
      officeLongitude: undefined, bio: undefined, logoUrl: undefined, bannerUrl: undefined,
      allowDirectBuyerLeads: false, updatedAt: Date.now(),
    });
  }
  counts["agent_profiles_blanked"] = agentProfiles.length;
  const hotelProfiles = await ctx.db.query("hotel_profiles").withIndex("by_userId", (q) => q.eq("userId", id)).take(20);
  for (const hp of hotelProfiles) {
    await ctx.db.patch(hp._id, { phone: "", email: undefined, address: "", latitude: undefined, longitude: undefined, updatedAt: Date.now() });
  }
  counts["hotel_profiles_blanked"] = hotelProfiles.length;

  // Reset codes are keyed by the identifier they were sent to (hashed codes, but keyed by PII).
  for (const ident of [user.email, user.phone, user.phoneNumber]) {
    if (!ident) continue;
    await run(
      `password_resets:${ident === user.email ? "email" : "phone"}`,
      await ctx.db.query("password_resets").withIndex("by_identifier", (q) => q.eq("identifier", ident)).take(CHILD_ROW_CAP)
    );
  }
  return more ? null : counts;
}

export const processDueDeletions = internalMutation({
  args: {
    now: v.optional(v.number()), // injectable for tests; defaults to Date.now()
    limit: v.optional(v.number()),
  },
  returns: v.object({
    processed: v.number(),
    deferred: v.array(v.object({ userId: v.string(), reason: v.string() })),
  }),
  handler: async (ctx, args) => {
    const now = args.now ?? Date.now();
    const limit = Math.min(Math.max(args.limit ?? BATCH_USERS_DEFAULT, 1), 100);
    const due = await ctx.db
      .query("users")
      .withIndex("by_deletion_scheduled", (q) => q.gte("deletionScheduledFor", 0).lte("deletionScheduledFor", now))
      .take(limit);

    let processed = 0;
    const deferred: Array<{ userId: string; reason: string }> = [];

    for (const user of due) {
      // Idempotence / safety gates: already erased, never admins, never an account that is signed in.
      if (user.anonymizedAt !== undefined) continue;
      if (user.role === "admin") {
        deferred.push({ userId: user._id as string, reason: "ADMIN_ACCOUNT" });
        continue;
      }
      if (user.sessionToken && (!user.sessionExpiresAt || user.sessionExpiresAt > now)) {
        deferred.push({ userId: user._id as string, reason: "ACTIVE_SESSION" });
        continue;
      }
      const blocker = await openObligation(ctx, user, now);
      if (blocker) {
        deferred.push({ userId: user._id as string, reason: blocker });
        continue;
      }
      const counts = await eraseChildRows(ctx, user);
      if (!counts) {
        deferred.push({ userId: user._id as string, reason: "MORE_ROWS_REMAIN" });
        continue; // this run's deletions are kept; the next run continues and finishes.
      }

      await ctx.db.patch(user._id, {
        name: "Deleted user",
        email: `deleted-${user._id}@users.vektolux.invalid`,
        phone: "",
        phoneNumber: undefined,
        avatarUrl: undefined,
        address: undefined,
        region: undefined,
        bio: undefined,
        gender: undefined,
        businessName: undefined,
        passwordHash: undefined,
        sessionToken: undefined,
        sessionExpiresAt: undefined,
        walletPinHash: undefined,
        pinFailedAttempts: undefined,
        pinLockedUntil: undefined,
        authProvider: undefined,
        externalAuthId: undefined,
        totpEnabled: undefined,
        totpSecretEncrypted: undefined,
        totpPendingSecretEncrypted: undefined,
        totpBackupCodesHashed: undefined,
        totpPendingBackupCodesHashed: undefined,
        currentLat: undefined,
        currentLng: undefined,
        currentGeohash: undefined,
        locationUpdatedAt: undefined,
        isActive: false,
        anonymizedAt: now,
        updatedAt: now,
      });
      await ctx.db.insert("account_deletion_events", {
        userId: user._id,
        processedAt: now,
        requestedAt: user.deletionRequestedAt,
        scheduledFor: user.deletionScheduledFor!,
        erasedCounts: JSON.stringify(counts),
      });
      processed++;
    }
    return { processed, deferred };
  },
});
