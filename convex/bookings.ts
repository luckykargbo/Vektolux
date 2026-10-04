// convex/bookings.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Universal Booking Engine
// Handles: hourly stays, vehicle rentals, site visits, and inspection bookings.
// Includes collision check to prevent double bookings & platform fee calc.
// ═══════════════════════════════════════════════════════════════════════

import { internalMutation, mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { universalBookingType, paymentMethod } from "./schema";
import { requireAdminSession, requireSelf } from "./lib/auth";
import { isListingPublic, toPublicProperty } from "./lib/publicListing";
import { activeListingAgent } from "./listingAgents";
import { bumpListingCounter } from "./listingStats";
import { FeeSnapshot, priceOrder } from "./lib/fees";
import {
  BOOKING_RELEASE_DELAY_MS,
  bookingEscrowSummary,
  buyerConfirmCompletion,
  logBookingEvent,
  refundBookingEscrow,
  releaseBookingEscrow,
  settlementOf,
} from "./lib/bookingEscrow";

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "10 Oct 2026, 14:30" — Sierra Leone time is GMT, so UTC is local time. */
function formatWhen(ms: number): string {
  const d = new Date(ms);
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const mm = String(d.getUTCMinutes()).padStart(2, "0");
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}, ${hh}:${mm}`;
}

async function notify(ctx: { db: any }, userId: string, title: string, body: string, screen: string, id: string) {
  await ctx.db.insert("user_notifications", {
    userId,
    targetType: "single_user",
    title,
    body,
    deepLinkScreen: screen,
    deepLinkId: id,
    read: false,
    createdAt: Date.now(),
  });
}

function publicLocationOf(listing: Doc<"realEstateListings">): string {
  return String(toPublicProperty(listing).publicLocation ?? "Sierra Leone");
}

/** Owner of the listing, or its active owner-authorised agent: the people who manage site visits. */
async function siteVisitManager(ctx: { db: any }, booking: Doc<"bookings">, callerId: Id<"users">, now = Date.now()) {
  const isOwner = booking.vendorId === (callerId as string);
  const agent = booking.listingType === "property" ? await activeListingAgent(ctx, "property", booking.listingId, now) : null;
  const isAgent = !!agent && agent.agentId === callerId;
  return { isOwner, isAgent, agentId: agent?.agentId ?? null };
}

// ═══════════════════════════════════════════════════════════════════════
//                        CREATE BOOKING
// ═══════════════════════════════════════════════════════════════════════

export const createBooking = mutation({
  args: {
    listingId: v.string(),
    listingType: v.union(v.literal("property"), v.literal("vehicle")),
    listingTitle: v.string(),
    buyerId: v.optional(v.string()), // consistency check only: the buyer is the authenticated user
    sessionToken: v.optional(v.string()),
    buyerName: v.optional(v.string()),
    buyerPhone: v.optional(v.string()),
    vendorId: v.optional(v.string()), // ignored: the vendor is the listing's owner
    bookingType: universalBookingType,
    startTime: v.number(),
    endTime: v.number(),
    hours: v.optional(v.number()),
    days: v.optional(v.number()),
    rate: v.optional(v.number()), // ignored: the price comes from the listing
    paymentMethod: v.optional(paymentMethod),
    notes: v.optional(v.string()),
  },
  returns: v.object({
    bookingId: v.string(),
    txRef: v.string(),
    totalAmount: v.number(),
    subtotal: v.number(),
    serviceFee: v.number(),
    status: v.string(),
    paymentStatus: v.string(),
    vendorId: v.string(),
  }),
  handler: async (ctx, args) => {
    // Identity, vendor and price are all decided by the SERVER, never by the client.
    const { userId: buyerUserId, user: buyer } = await requireSelf(ctx, args.sessionToken, args.buyerId);
    if (!(args.endTime > args.startTime)) throw new Error("End time must be after start time.");

    let vendorUserId: string;
    let serverRate: number | undefined;
    let listingTitle: string;
    if (args.listingType === "property") {
      const propId = ctx.db.normalizeId("realEstateListings", args.listingId);
      const prop = propId ? await ctx.db.get(propId) : null;
      // Only public listings can be booked (not drafts, listings under review, rejected or removed).
      if (!prop || !isListingPublic(prop)) throw new Error("Listing not found.");
      vendorUserId = prop.ownerId as string;
      serverRate = prop.hourlyRate;
      listingTitle = prop.title;
    } else {
      const vehId = ctx.db.normalizeId("vehicleListings", args.listingId);
      const veh = vehId ? await ctx.db.get(vehId) : null;
      if (!veh || veh.isDeleted === true) throw new Error("Listing not found.");
      vendorUserId = veh.ownerId as string;
      serverRate = veh.pricePerDay;
      listingTitle = veh.title;
    }
    if (args.bookingType === "property_inspection" && args.listingType !== "property") {
      throw new Error("A property site visit needs a property listing.");
    }
    if (vendorUserId === (buyerUserId as string)) throw new Error("You cannot book your own listing.");

    // 1. Double-booking check: verify slot availability
    const existingBookings = await ctx.db
      .query("bookings")
      .withIndex("by_listing", (q) => q.eq("listingId", args.listingId))
      .filter((q) =>
        q.and(
          q.neq(q.field("status"), "cancelled"),
          q.neq(q.field("status"), "declined"),
          q.lt(q.field("startTime"), args.endTime),
          q.gt(q.field("endTime"), args.startTime)
        )
      )
      .take(1);

    if (existingBookings.length > 0) {
      throw new Error(
        "This time slot is already booked. Please select another time or date."
      );
    }

    const now = Date.now();
    const txRef = `vktlx_booking_${now}_${Math.random().toString(36).substring(2, 8)}`;

    let subtotal = 0;
    let serviceFee = 0;
    let fees: FeeSnapshot | undefined;
    let totalAmount = 0;
    let status: "requested" | "pending_payment" | "confirmed" = "pending_payment";
    let paymentStatus: "pending" | "completed" = "pending";

    // 2. Financial calculation per booking type
    if (
      args.bookingType === "property_inspection" ||
      args.bookingType === "vehicle_inspection"
    ) {
      // Free complimentary inspection. A property site visit is a REQUEST: the owner or the
      // listing's authorised agent accepts or declines it (respondToViewingRequest).
      subtotal = 0;
      serviceFee = 0;
      totalAmount = 0;
      status = args.bookingType === "property_inspection" ? "requested" : "confirmed";
      paymentStatus = "completed";
    } else if (args.bookingType === "hourly_guesthouse") {
      const hours =
        args.hours ??
        Math.max(
          1,
          Math.round((args.endTime - args.startTime) / (1000 * 60 * 60))
        );
      // The price is the listing's own rate. No client rate and no invented default price.
      const unitRate = serverRate;
      if (!unitRate || !(unitRate > 0)) throw new Error("This listing has no hourly rate configured.");
      subtotal = Math.round(unitRate * hours);
      fees = await priceOrder(ctx, "marketplace_booking", subtotal, { hasAgent: false, now });
      serviceFee = fees.buyerFee; // default 5% service fee
      totalAmount = fees.buyerTotal;
      status = "pending_payment";
      paymentStatus = "pending";
    } else if (args.bookingType === "vehicle_rental") {
      const days =
        args.days ??
        Math.max(
          1,
          Math.round((args.endTime - args.startTime) / (1000 * 60 * 60 * 24))
        );
      const unitRate = serverRate;
      if (!unitRate || !(unitRate > 0)) throw new Error("This listing has no daily rate configured.");
      subtotal = Math.round(unitRate * days);
      fees = await priceOrder(ctx, "marketplace_booking", subtotal, { hasAgent: false, now });
      serviceFee = fees.buyerFee;
      totalAmount = fees.buyerTotal;
      status = "pending_payment";
      paymentStatus = "pending";
    }

    // 3. Insert record into bookings collection
    const bookingId = await ctx.db.insert("bookings", {
      listingId: args.listingId,
      listingType: args.listingType,
      // Server values only: the listing's own title and the buyer's own account details.
      listingTitle,
      buyerId: buyerUserId as string,
      buyerName: buyer.name,
      buyerPhone: buyer.phone && buyer.phone.trim() !== "+232" ? buyer.phone : undefined,
      vendorId: vendorUserId,
      bookingType: args.bookingType,
      status,
      startTime: args.startTime,
      endTime: args.endTime,
      hours: args.hours,
      days: args.days,
      subtotal,
      serviceFee,
      totalAmount,
      currency: "SLE",
      paymentStatus,
      paymentMethod: args.paymentMethod,
      txRef,
      notes: args.notes?.trim().slice(0, 500) || undefined,
      ...(fees ? { feeSnapshot: fees } : {}),
      updatedAt: now,
    });

    if (args.bookingType === "property_inspection") {
      await bumpListingCounter(ctx, args.listingId, "viewingRequestCount");
      const when = formatWhen(args.startTime);
      await notify(ctx, buyerUserId as string, "Viewing request sent", `"${listingTitle}" on ${when}. Waiting for the agent to confirm.`, "bookings", bookingId as string);
      const agent = await activeListingAgent(ctx, "property", args.listingId, now);
      const managers = new Set<string>([vendorUserId, ...(agent ? [agent.agentId as string] : [])]);
      for (const m of managers) {
        await notify(ctx, m, "New viewing request", `${buyer.name} wants to view "${listingTitle}" on ${when}.`, "viewings", bookingId as string);
      }
    }

    // (Bookings are paid through payments.createEscrowPayment — wallet escrow, split from the
    // booking's fee snapshot — or Monime. No payment-intent record is created any more.)

    return {
      bookingId: bookingId as string,
      txRef,
      totalAmount,
      subtotal,
      serviceFee,
      status,
      paymentStatus,
      vendorId: vendorUserId,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                        GET USER BOOKINGS
// ═══════════════════════════════════════════════════════════════════════

export const getUserBookings = query({
  args: {
    sessionToken: v.optional(v.string()),
    buyerId: v.string(),
  },
  handler: async (ctx, args) => {
    // Only the account owner (valid session) may act on this account.
    await requireSelf(ctx, args.sessionToken, String(args.buyerId));
    const list = await ctx.db
      .query("bookings")
      .withIndex("by_buyer", (q) => q.eq("buyerId", args.buyerId))
      .order("desc")
      .take(300);

    // Order descending by start time
    return list.sort((a, b) => b.startTime - a.startTime);
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                       GET VENDOR BOOKINGS
// ═══════════════════════════════════════════════════════════════════════

export const getVendorBookings = query({
  args: {
    sessionToken: v.optional(v.string()),
    vendorId: v.string(),
  },
  handler: async (ctx, args) => {
    // Only the account owner (valid session) may act on this account.
    await requireSelf(ctx, args.sessionToken, String(args.vendorId));
    const list = await ctx.db
      .query("bookings")
      .withIndex("by_vendor", (q) => q.eq("vendorId", args.vendorId))
      .order("desc")
      .take(300);

    return list.sort((a, b) => b.startTime - a.startTime);
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                       GET BOOKING BY ID
// ═══════════════════════════════════════════════════════════════════════

export const getBookingById = query({
  args: {
    sessionToken: v.optional(v.string()),
    bookingId: v.string(),
  },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("bookings", args.bookingId);
    if (!id) return null;
    const { userId: __caller, user: __u } = await requireSelf(ctx, args.sessionToken);
    const booking = await ctx.db.get(id);
    if (!booking) return null;
    if (__u.role !== "admin" && booking.buyerId !== (__caller as string) && booking.vendorId !== (__caller as string)) {
      return null;
    }
    return booking;
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                CANCEL BOOKING (refunds a paid booking in full)
// ═══════════════════════════════════════════════════════════════════════

export const cancelBooking = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    bookingId: v.string(),
    userId: v.string(),
    reason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Only the account owner (valid session) may act on this account.
    const { userId } = await requireSelf(ctx, args.sessionToken, String(args.userId));
    const id = ctx.db.normalizeId("bookings", args.bookingId);
    if (!id) throw new Error("Booking not found");
    const booking = await ctx.db.get(id);
    if (!booking) throw new Error("Booking not found");
    const caller = userId as string;
    const isBuyer = booking.buyerId === caller;
    const isSiteVisit = booking.bookingType === "property_inspection" && booking.listingType === "property";
    const manager = isSiteVisit ? await siteVisitManager(ctx, booking, userId) : null;
    // The listing's authorised agent may cancel a (free) site visit like the owner.
    const isVendor = booking.vendorId === caller || (manager?.isAgent ?? false);
    if (!isBuyer && !isVendor) throw new Error("You are not authorized to cancel this booking");
    if (booking.status === "completed") throw new Error("Cannot cancel an already completed booking");
    if (booking.status === "cancelled") throw new Error("This booking is already cancelled");
    if (booking.status === "declined") throw new Error("This viewing request was declined.");
    if (booking.status === "requested" && !isBuyer) {
      // A request is answered, not cancelled: accept or decline it (with a reason).
      throw new Error("Accept or decline this viewing request instead.");
    }

    const state = settlementOf(booking);
    const reason = (args.reason ?? "").trim() || (isBuyer ? "Cancelled by the buyer" : "Cancelled by the vendor");
    if (state === "disputed") throw new Error("This booking is disputed; an administrator will resolve it.");
    if (state === "released" || state === "refunded") throw new Error("This booking is already settled.");
    if (state === "held") {
      // Paid: a full refund (including the service fee). The buyer may cancel only before the
      // start; afterwards a problem is raised as a dispute. The vendor may cancel until settlement.
      if (isBuyer && Date.now() >= booking.startTime) {
        throw new Error("This booking has started. Report a problem (dispute) instead of cancelling.");
      }
      const r = await refundBookingEscrow(ctx, booking, reason, { id: userId, role: isBuyer ? "buyer" : "vendor" });
      return { success: true, refunded: r.refunded };
    }

    // Not paid: nothing to refund.
    const now = Date.now();
    const cancelReason = booking.status === "requested" && isBuyer ? "Request withdrawn by the client" : reason;
    await ctx.db.patch(id, { status: "cancelled", cancelledAt: now, cancelReason: cancelReason.slice(0, 500), updatedAt: now });
    if (isSiteVisit) {
      // The other side of a site visit is told (the client, or the owner and the authorised agent).
      const when = formatWhen(booking.startTime);
      if (isBuyer) {
        const others = new Set<string>([booking.vendorId, ...(manager?.agentId ? [manager.agentId as string] : [])]);
        for (const o of others) {
          await notify(ctx, o, "Viewing cancelled", `The client cancelled the visit to "${booking.listingTitle}" on ${when}.`, "viewings", booking._id as string);
        }
      } else {
        await notify(
          ctx,
          booking.buyerId,
          "Viewing cancelled",
          `Your visit to "${booking.listingTitle}" on ${when} was cancelled: ${cancelReason.slice(0, 200)}`,
          "bookings",
          booking._id as string
        );
      }
    }
    return { success: true, refunded: 0 };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//            SITE-VISIT REQUESTS (owner / authorised agent decides)
// ═══════════════════════════════════════════════════════════════════════

/**
 * Accept or decline a free property site-visit request. Only the listing's owner or its active
 * owner-authorised agent may answer, only while it is still "requested" (a transaction: a second
 * answer, or a race between two, is refused). Declining needs a reason. The client is notified.
 */
export const respondToViewingRequest = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    bookingId: v.string(),
    decision: v.union(v.literal("accept"), v.literal("decline")),
    reason: v.optional(v.string()),
  },
  returns: v.object({ status: v.string() }),
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const booking = await loadBooking(ctx, args.bookingId);
    if (booking.bookingType !== "property_inspection" || booking.listingType !== "property") {
      throw new Error("Only property site-visit requests can be accepted or declined.");
    }
    const now = Date.now();
    const { isOwner, isAgent } = await siteVisitManager(ctx, booking, userId, now);
    if (!isOwner && !isAgent) throw new Error("You can only answer viewing requests for listings you manage.");
    if (booking.buyerId === (userId as string)) throw new Error("You cannot answer your own viewing request.");
    if (booking.status !== "requested") {
      throw new Error(
        booking.status === "confirmed"
          ? "This request was already accepted."
          : booking.status === "declined"
            ? "This request was already declined."
            : "This request can no longer be answered."
      );
    }
    const when = formatWhen(booking.startTime);
    if (args.decision === "accept") {
      if (booking.endTime <= now) throw new Error("The requested time has already passed. Decline the request instead.");
      await ctx.db.patch(booking._id, { status: "confirmed", acceptedAt: now, acceptedBy: userId, updatedAt: now });
      await notify(ctx, booking.buyerId, "Your viewing request has been accepted.", `"${booking.listingTitle}" on ${when}.`, "bookings", booking._id as string);
      return { status: "confirmed" };
    }
    const reason = (args.reason ?? "").trim();
    if (reason.length < 3) throw new Error("Please give a reason for declining.");
    await ctx.db.patch(booking._id, {
      status: "declined",
      declinedAt: now,
      declinedBy: userId,
      declineReason: reason.slice(0, 500),
      updatedAt: now,
    });
    await notify(
      ctx,
      booking.buyerId,
      "Your viewing request was declined.",
      `"${booking.listingTitle}" on ${when}: ${reason.slice(0, 200)}`,
      "bookings",
      booking._id as string
    );
    return { status: "declined" };
  },
});

/**
 * Site-visit requests on the listings the caller manages: their own listings and the listings an
 * owner currently authorises them to represent. The client's phone is shared only once a visit
 * is accepted.
 */
export const getMyViewingRequests = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const me = userId as string;
    const rows = new Map<string, { b: Doc<"bookings">; representing: boolean }>();
    const own = await ctx.db
      .query("bookings")
      .withIndex("by_vendor", (q) => q.eq("vendorId", me))
      .order("desc")
      .take(300);
    for (const b of own) rows.set(b._id as string, { b, representing: false });

    const auths = await ctx.db
      .query("listing_agent_authorizations")
      .withIndex("by_agent", (q) => q.eq("agentId", userId))
      .take(100);
    for (const a of auths) {
      if (a.listingType !== "property" || a.status !== "active") continue;
      const link = await activeListingAgent(ctx, "property", a.listingId);
      if (!link || link.agentId !== userId) continue;
      const list = await ctx.db
        .query("bookings")
        .withIndex("by_listing", (q) => q.eq("listingId", a.listingId))
        .order("desc")
        .take(100);
      for (const b of list) if (!rows.has(b._id as string)) rows.set(b._id as string, { b, representing: true });
    }

    const out = [];
    for (const { b, representing } of rows.values()) {
      if (b.bookingType !== "property_inspection" || b.listingType !== "property") continue;
      const propId = ctx.db.normalizeId("realEstateListings", b.listingId);
      const listing = propId ? await ctx.db.get(propId) : null;
      const clientId = ctx.db.normalizeId("users", b.buyerId);
      const client = clientId ? await ctx.db.get(clientId) : null;
      const cover = (listing?.imageUrls ?? []).find((u) => typeof u === "string" && u.startsWith("http")) ?? null;
      out.push({
        id: b._id as string,
        listingId: b.listingId,
        listingTitle: listing?.title ?? b.listingTitle,
        listingImage: cover,
        publicLocation: listing ? publicLocationOf(listing) : null,
        representing,
        clientName: client?.name ?? b.buyerName ?? "Client",
        clientAvatarUrl: client?.avatarUrl ?? null,
        clientPhone: b.status === "confirmed" ? (b.buyerPhone ?? null) : null,
        status: b.status,
        startTime: b.startTime,
        endTime: b.endTime,
        notes: b.notes ?? null,
        declineReason: b.declineReason ?? null,
        cancelReason: b.cancelReason ?? null,
        acceptedAt: b.acceptedAt ?? null,
        declinedAt: b.declinedAt ?? null,
        cancelledAt: b.cancelledAt ?? null,
        requestedAt: b._creationTime,
      });
    }
    out.sort((x, y) => x.startTime - y.startTime);
    return out;
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                  SETTLEMENT: CONFIRM / DISPUTE / ADMIN
// ═══════════════════════════════════════════════════════════════════════

async function loadBooking(ctx: { db: any }, bookingId: string): Promise<Doc<"bookings">> {
  const id = ctx.db.normalizeId("bookings", bookingId);
  const booking = id ? await ctx.db.get(id) : null;
  if (!booking) throw new Error("Booking not found");
  return booking;
}

/** The BUYER confirms the service took place → the escrow is released to the vendor. */
export const confirmBookingCompletion = mutation({
  args: { sessionToken: v.optional(v.string()), bookingId: v.string() },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const booking = await loadBooking(ctx, args.bookingId);
    const r = await buyerConfirmCompletion(ctx, booking, userId as string);
    return { success: true, status: "completed", vendorAmount: r.partnerAmount, platformFee: r.platformFeeAmount };
  },
});

/** Buyer or vendor reports a problem: the escrow is frozen (no release) until an admin decides. */
export const raiseBookingDispute = mutation({
  args: { sessionToken: v.optional(v.string()), bookingId: v.string(), reason: v.string() },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const booking = await loadBooking(ctx, args.bookingId);
    const caller = userId as string;
    const role = booking.buyerId === caller ? "buyer" : booking.vendorId === caller ? "vendor" : null;
    if (!role) throw new Error("Booking not found");
    if (settlementOf(booking) !== "held") throw new Error("Only a paid booking awaiting release can be disputed.");
    const reason = args.reason.trim();
    if (reason.length < 5) throw new Error("Please describe the problem.");
    const now = Date.now();
    await ctx.db.patch(booking._id, {
      status: "disputed",
      settlementStatus: "disputed",
      disputeReason: reason.slice(0, 1000),
      disputedAt: now,
      disputedBy: role,
      updatedAt: now,
    });
    await logBookingEvent(ctx, booking._id, "DISPUTE_OPENED", { id: userId, role }, { note: reason });
    const other = role === "buyer" ? booking.vendorId : booking.buyerId;
    await ctx.db.insert("user_notifications", {
      userId: other,
      targetType: "single_user",
      title: "Booking disputed",
      body: `A problem was reported for "${booking.listingTitle}". The payment is on hold until Vektolux resolves it.`,
      read: false,
      createdAt: now,
    });
    return { success: true, status: "disputed" };
  },
});

/** Admin settles a held or disputed booking: release to the vendor, or full refund to the buyer. */
export const adminResolveBookingDispute = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    bookingId: v.string(),
    resolution: v.union(v.literal("release_to_vendor"), v.literal("refund_buyer")),
    note: v.string(),
    // The amount the admin was shown and confirmed. Optional; when given it must equal what the
    // SERVER would move now (protects against acting on a stale screen). Never used as the amount.
    expectedAmount: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    const note = args.note.trim();
    if (note.length < 5) throw new Error("A note explaining the decision is required.");
    const booking = await loadBooking(ctx, args.bookingId);
    const state = settlementOf(booking);
    if (state !== "held" && state !== "disputed") throw new Error("This booking has no escrow to settle.");
    const summary = await bookingEscrowSummary(ctx, booking);
    if (!summary || summary.heldAmount <= 0) throw new Error("This booking has no escrow to settle.");
    if (args.expectedAmount !== undefined) {
      const serverAmount = args.resolution === "release_to_vendor" ? summary.vendorAmount : summary.refundableAmount;
      if (Math.abs(serverAmount - args.expectedAmount) > 0.005) {
        throw new Error("The amount has changed since you loaded this page. Refresh and review it again.");
      }
    }
    const admin = { id: adminId, role: "admin" as const, note };
    await logBookingEvent(ctx, booking._id, "ADMIN_DECISION", admin, {
      note: `${args.resolution === "release_to_vendor" ? "Release to vendor" : "Refund buyer"}: ${note}`,
    });
    let amount: number;
    if (args.resolution === "release_to_vendor") {
      const r = await releaseBookingEscrow(ctx, booking, "admin", admin);
      amount = r.partnerAmount;
    } else {
      amount = (await refundBookingEscrow(ctx, booking, `Refunded by Vektolux: ${note}`, admin)).refunded;
    }
    await ctx.db.insert("audit_logs", {
      adminUserId: adminId,
      action: "BOOKING_SETTLED",
      targetTransactionId: booking._id as string,
      snapshot: JSON.stringify({ resolution: args.resolution, previousState: state, amount, disputeReason: booking.disputeReason ?? null, note }),
      timestamp: Date.now(),
    });
    return { success: true, resolution: args.resolution, amount };
  },
});

/** Bookings with money in escrow (held or disputed), for the admin. */
export const adminListBookingEscrows = query({
  args: { sessionToken: v.optional(v.string()), state: v.optional(v.union(v.literal("held"), v.literal("disputed"))) },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const states = args.state ? [args.state] : (["disputed", "held"] as const);
    const out: Doc<"bookings">[] = [];
    for (const st of states) {
      out.push(...(await ctx.db.query("bookings").withIndex("by_settlement_eligible", (q) => q.eq("settlementStatus", st)).take(200)));
    }
    return out;
  },
});

/**
 * Cron: releases held bookings whose 24h window after the end time passed without a dispute.
 * Idempotent (each release is keyed to the escrow lock); a failure on one booking does not block others.
 */
export const releaseDueBookings = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const due = await ctx.db
      .query("bookings")
      .withIndex("by_settlement_eligible", (q) => q.eq("settlementStatus", "held").lte("releaseEligibleAt", now))
      .take(50);
    let released = 0;
    let failed = 0;
    for (const b of due) {
      if (b.status !== "confirmed" && b.status !== "in_progress") continue;
      try {
        await releaseBookingEscrow(ctx, b, "auto");
        released += 1;
      } catch {
        failed += 1;
        console.error("[releaseDueBookings] release failed for a booking");
      }
    }
    return { released, failed };
  },
});

/**
 * Admin → Booking Disputes. Everything shown is read from the server (booking, escrow lock, wallet
 * transactions, settlement history, audit log); the dashboard computes nothing.
 * view: "open" = disputed; "held" = paid, awaiting release; "resolved" = disputes already settled.
 */
export const adminListBookingDisputes = query({
  args: {
    sessionToken: v.optional(v.string()),
    view: v.optional(v.union(v.literal("open"), v.literal("held"), v.literal("resolved"))),
  },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const view = args.view ?? "open";
    const byState = (st: "held" | "disputed" | "released" | "refunded") =>
      ctx.db.query("bookings").withIndex("by_settlement_eligible", (q) => q.eq("settlementStatus", st)).order("desc").take(200);
    let rows: Doc<"bookings">[];
    if (view === "open") rows = await byState("disputed");
    else if (view === "held") rows = await byState("held");
    else rows = [...(await byState("released")), ...(await byState("refunded"))].filter((b) => b.disputedAt !== undefined);

    const people = new Map<string, { name: string; email: string | null } | null>();
    const person = async (raw: string | undefined) => {
      if (!raw) return null;
      if (!people.has(raw)) {
        const id = ctx.db.normalizeId("users", raw);
        const u = id ? await ctx.db.get(id) : null;
        people.set(raw, u ? { name: u.name ?? "Unknown user", email: u.email ?? null } : null);
      }
      return people.get(raw)!;
    };

    const out = [];
    for (const b of rows.slice(0, 200)) {
      const escrow = await bookingEscrowSummary(ctx, b);
      const events = await ctx.db.query("booking_events").withIndex("by_booking", (q) => q.eq("bookingId", b._id)).collect();
      const eventsOut = [];
      for (const e of events) {
        eventsOut.push({
          action: e.action,
          actorRole: e.actorRole,
          actorName: (await person(e.actorId as string | undefined))?.name ?? null,
          amount: e.amount ?? null,
          platformFee: e.platformFee ?? null,
          transactionCode: e.transactionCode ?? null,
          ledgerCode: e.ledgerCode ?? null,
          note: e.note ?? null,
          at: e.at,
        });
      }
      const audit = [];
      for (const a of await ctx.db.query("audit_logs").withIndex("by_target", (q) => q.eq("targetTransactionId", b._id as string)).collect()) {
        let detail: any = {};
        try {
          detail = JSON.parse(a.snapshot);
        } catch {
          detail = {};
        }
        audit.push({
          action: a.action,
          adminName: (await person(a.adminUserId as string))?.name ?? null,
          resolution: detail.resolution ?? null,
          amount: typeof detail.amount === "number" ? detail.amount : null,
          note: detail.note ?? null,
          at: a.timestamp,
        });
      }
      const txs = await ctx.db
        .query("transactions")
        .withIndex("by_reference", (q) => q.eq("referenceType", b.bookingType).eq("referenceId", b._id as string))
        .collect();
      out.push({
        id: b._id as string,
        listingTitle: b.listingTitle,
        listingType: b.listingType,
        bookingType: b.bookingType,
        buyer: await person(b.buyerId),
        vendor: await person(b.vendorId),
        startTime: b.startTime,
        endTime: b.endTime,
        subtotal: b.subtotal,
        serviceFee: b.serviceFee,
        totalAmount: b.totalAmount,
        currency: b.currency,
        status: b.status,
        paymentStatus: b.paymentStatus,
        settlementStatus: settlementOf(b),
        disputedBy: b.disputedBy ?? null,
        disputeReason: b.disputeReason ?? null,
        disputedAt: b.disputedAt ?? null,
        // auto-release applies only while held (a dispute stops it)
        autoReleaseAt: settlementOf(b) === "held" ? b.releaseEligibleAt ?? null : null,
        releasedAt: b.releasedAt ?? null,
        releasedBy: b.releasedBy ?? null,
        refundedAt: b.refundedAt ?? null,
        refundReason: b.refundReason ?? null,
        escrow,
        transactions: txs.map((t) => ({
          transactionCode: t.transactionId ?? null,
          type: t.type,
          amount: t.amount,
          netAmount: t.netAmount ?? null,
          status: t.status,
          escrowStatus: t.escrowStatus ?? null,
          createdAt: t.createdAt ?? null,
          party: t.userId === (b.buyerId as unknown as Id<"users">) ? "buyer" : t.userId === (b.vendorId as unknown as Id<"users">) ? "vendor" : "other",
        })),
        events: eventsOut,
        audit,
      });
    }
    return out;
  },
});

/**
 * One-off repair for bookings paid BEFORE settlement tracking existed: their escrow is locked but
 * they have no settlementStatus/releaseEligibleAt, so neither the auto-release job nor the admin
 * views would ever find them (money stuck forever). Marks them "held" with the normal 24h window
 * after their end time. Moves no money; idempotent. Run once after deploying (internal only).
 */
export const backfillBookingSettlement = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())) },
  handler: async (ctx, args) => {
    const page = await ctx.db
      .query("bookings")
      .withIndex("by_settlement_eligible", (q) => q.eq("settlementStatus", undefined))
      .paginate({ numItems: 100, cursor: args.cursor ?? null });
    let fixed = 0;
    for (const b of page.page) {
      if (b.paymentStatus !== "completed" || !b.escrowId || b.status === "completed" || b.status === "cancelled") continue;
      const escrow = await bookingEscrowSummary(ctx, b);
      if (!escrow || escrow.escrowStatus !== "locked") continue;
      await ctx.db.patch(b._id, { settlementStatus: "held", releaseEligibleAt: b.endTime + BOOKING_RELEASE_DELAY_MS, updatedAt: Date.now() });
      await logBookingEvent(ctx, b._id, "SETTLEMENT_BACKFILLED", { role: "system" }, { amount: escrow.heldAmount, note: "Settlement tracking added to a booking paid earlier." });
      fixed += 1;
    }
    return { fixed, isDone: page.isDone, continueCursor: page.continueCursor };
  },
});
