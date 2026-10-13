// convex/vehicleClassificationReport.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — READ-ONLY report on how vehicle listings are classified (`postedAs`).
//
// Legacy listings (created before the car-company capability) carry no `postedAs`, and nothing on
// the listing proves whether the inventory belongs to an individual or to a company. This report
// counts them by non-sensitive categories so an administrator can decide how to handle them. It
// never writes, never returns record IDs (other than the opaque pagination cursor, which may embed
// an internal record id and carries no personal data), names, contact details, addresses or listing
// content, and guesses nothing: "untagged" stays "untagged".
//
// Classification is by what the STORED fields show (category, pricing type, which prices exist,
// provenance signature). It does not infer an owner's intended service: ambiguous or inconsistent
// records get their own buckets and are meant for human review, never for automatic action.
//
// INTERNAL: run it from the Convex dashboard / CLI against an authorised deployment, page by page
// (pass back `continueCursor` until `isDone`), and add the `counts` (and `byClass`) of each page
// together. Run it on a disposable deployment first; a production read needs separate authorisation.
//
// TWO views of outstanding transactions, deliberately kept apart:
//  * classificationPage     per-LISTING flags. These come from a bounded per-listing read, so each flag
//                           is tri-state: "open" (one was found: definitely true), "none" (every
//                           record of that listing was read: definitely false) or "unknown" (the per-
//                           listing read cap was reached before all records were seen: NOT zero).
//  * openTransactionsPage   AUTHORITATIVE totals, counted per listing class from the existing indexes.
//                           Complete once every source of a kind has been traversed to `isDone`.
//
// SCOPE: orders cover the `escrow_orders` table only; bookings cover the `bookings` table only.
// Hotel bookings (`hotel_bookings`), real-estate escrow contracts (`re_escrow_contracts`), viewing
// passes (`re_inspection_passes`) and every other obligation-bearing table are NOT included. A full
// cross-system obligation inventory is separate future work.
//
// BOOKING OBLIGATIONS (see classifyBookingObligation): a booking's ordinary `status` is NOT evidence of
// an obligation (free inspections stay "confirmed" forever). Bookings are enumerated by their
// SETTLEMENT state through the existing `by_settlement_eligible` index, in three DISJOINT ranges
// (held, disputed, no settlement record), so no booking can be counted twice in a completed
// traversal. A booking with no settlement record is never called "funds held" because its payment
// status or escrow id says so: its escrow transaction is read (bookingEscrowSummary, read-only) and
// only a verified LOCKED escrow counts as held funds. Anything that cannot be verified is reported as
// an anomaly or unresolved candidate for manual review. Free visits, unpaid bookings and closed
// records are reported separately.
// ═══════════════════════════════════════════════════════════════════════

import { internalQuery } from "./_generated/server";
import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { businessRole, hasCarCompanyCapability, hasCarDealerCapability } from "./lib/permissions";
import { bookingEscrowSummary } from "./lib/bookingEscrow";

export const OPEN_ORDER_STATUSES = new Set([
  "INITIATED",
  "PENDING_PAYMENT",
  "HELD_IN_ESCROW",
  "ESCROW_LOCKED",
  "PARTIALLY_RELEASED",
  "POST_INSPECTION_PENDING",
  "DISPUTED",
]);
// Booking sources traversed by openTransactionsPage: disjoint ranges of the existing
// `by_settlement_eligible` index ["settlementStatus", "releaseEligibleAt"].
//   settlement:held      settlementStatus = "held"        work ~ money held
//   settlement:disputed  settlementStatus = "disputed"    work ~ disputes
//   settlement:none      settlementStatus undefined       EVERY booking with no settlement record, in
//                        any status (free visits, unpaid, legacy paid, completed, declined, cancelled);
//                        work ~ the number of such bookings (grows with free-visit history)
// NOT traversed: settlementStatus "released" and "refunded" (financially settled records; including
// them would only add inconsistent-status reporting and the full released history).
export const BOOKING_COUNT_SOURCES = ["settlement:none", "settlement:held", "settlement:disputed"] as const;
export type BookingCountSource = (typeof BOOKING_COUNT_SOURCES)[number];

export const REPORT_SCOPE_BOOKINGS = "bookings_table_only";
export const REPORT_SCOPE_ORDERS = "escrow_orders_table_only";
export const SCOPE_EXCLUDES = ["hotel_bookings", "re_escrow_contracts", "re_inspection_passes", "other_tables"] as const;

export type BookingObligation =
  // settlement record present
  | "funds_disputed"
  | "funds_held"
  | "closed_released"
  | "closed_refunded"
  // no settlement record, escrow verified
  | "verified_funds_locked_no_settlement"
  | "closed_escrow_closed_no_settlement"
  // no settlement record, nothing paid / free / closed
  | "unpaid_pending_payment"
  | "free_visit_requested"
  | "free_visit_confirmed"
  | "closed_completed"
  | "closed_cancelled"
  | "closed_declined"
  | "closed_cancelled_unpaid"
  // not verified in this path
  | "unresolved_paid_with_escrow_id"
  // anomalies: contradictory or unverifiable money fields, for manual review
  | "anomaly_escrow_missing_or_invalid"
  | "anomaly_escrow_state_unknown"
  | "anomaly_escrow_id_without_payment"
  | "anomaly_free_with_escrow_id"
  | "anomaly_free_status_mismatch"
  | "anomaly_status_payment_mismatch"
  | "anomaly_refunded_without_settlement"
  | "anomaly_paid_but_pending_payment"
  | "anomaly_paid_without_escrow_unverified"
  | "anomaly_cancelled_paid_without_refund_evidence"
  | "anomaly_terminal_paid_without_settlement"
  | "anomaly_ambiguous_paid";
export type BookingGroup =
  | "financial_outstanding" // verified: a settlement record or a verified locked escrow
  | "unpaid"
  | "free_visit"
  | "closed"
  | "unresolved_candidate" // looks paid with an escrow id but the escrow was not read in this path
  | "anomaly"; // contradictory or unverifiable: manual investigation
export type BookingConsistency = "ok" | "status_terminal_but_funds_held";

/** What reading the booking's escrow transaction showed (see resolveEscrowEvidence). */
export type EscrowEvidence =
  | { state: "not_needed" } // not a paid-with-escrow-id candidate
  | { state: "not_checked" } // candidate, but this path does not read transactions
  | { state: "locked" }
  | { state: "closed"; status: "released" | "refunded" }
  | { state: "missing" } // escrow id does not resolve to a valid escrow lock for this booking
  | { state: "unknown" }; // a valid escrow lock whose escrowStatus is not recorded

type ClassifiableBooking = Pick<
  Doc<"bookings">,
  "status" | "paymentStatus" | "settlementStatus" | "escrowId" | "totalAmount"
>;

/** A paid-with-escrow-id booking that has no settlement record: the only case needing an escrow read. */
export function needsEscrowVerification(b: ClassifiableBooking): boolean {
  return !b.settlementStatus && b.paymentStatus === "completed" && b.totalAmount > 0 && !!b.escrowId;
}

/**
 * Classifies one booking. Precedence (first match wins, so a booking has exactly one category):
 *  A. settlement record present
 *     1. "disputed" -> funds_disputed        2. "held" -> funds_held
 *     3. "released" -> closed_released       4. "refunded" -> closed_refunded
 *     (3 and 4 are settled; openTransactionsPage does not enumerate them, but a listing's own
 *      booking list contains them)
 *  B. no settlement record, amount 0 (a free visit/inspection)
 *     escrow id present -> anomaly_free_with_escrow_id
 *     requested -> free_visit_requested; confirmed/in_progress -> free_visit_confirmed;
 *     completed/cancelled/declined -> closed_*; other -> anomaly_free_status_mismatch
 *  C. no settlement record, amount > 0
 *     payment pending/processing/failed:
 *        escrow id present -> anomaly_escrow_id_without_payment
 *        pending_payment -> unpaid_pending_payment; cancelled -> closed_cancelled_unpaid;
 *        anything else -> anomaly_status_payment_mismatch
 *     payment refunded -> anomaly_refunded_without_settlement (no settlement record proves it)
 *     payment completed:
 *        escrow id present -> decided by the ESCROW EVIDENCE:
 *             locked  -> verified_funds_locked_no_settlement (financial_outstanding)
 *             closed  -> closed_escrow_closed_no_settlement (record gap only, no money held)
 *             missing -> anomaly_escrow_missing_or_invalid
 *             unknown -> anomaly_escrow_state_unknown
 *             not_checked -> unresolved_paid_with_escrow_id
 *        no escrow id (old flow: paid, never escrowed):
 *             cancelled -> anomaly_cancelled_paid_without_refund_evidence
 *             completed/declined -> anomaly_terminal_paid_without_settlement
 *             confirmed/in_progress -> anomaly_paid_without_escrow_unverified
 *             pending_payment -> anomaly_paid_but_pending_payment
 *             anything else -> anomaly_ambiguous_paid
 * `paymentStatus = completed` or an escrow id alone NEVER yields funds held. `consistency` flags
 * held funds under a terminal booking status.
 */
export function classifyBookingObligation(
  b: ClassifiableBooking,
  escrow: EscrowEvidence = { state: "not_needed" }
): { obligation: BookingObligation; group: BookingGroup; consistency: BookingConsistency } {
  const terminalStatus = b.status === "completed" || b.status === "cancelled" || b.status === "declined";
  const heldConsistency: BookingConsistency = terminalStatus ? "status_terminal_but_funds_held" : "ok";
  const out = (obligation: BookingObligation, group: BookingGroup, consistency: BookingConsistency = "ok") => ({
    obligation,
    group,
    consistency,
  });

  // A. a settlement record exists
  if (b.settlementStatus === "disputed") return out("funds_disputed", "financial_outstanding", heldConsistency);
  if (b.settlementStatus === "held") return out("funds_held", "financial_outstanding", heldConsistency);
  if (b.settlementStatus === "released") return out("closed_released", "closed");
  if (b.settlementStatus === "refunded") return out("closed_refunded", "closed");
  if (b.settlementStatus) return out("anomaly_ambiguous_paid", "anomaly"); // not a known settlement value

  // B. free
  const hasEscrowId = !!b.escrowId;
  if (b.totalAmount === 0) {
    if (hasEscrowId) return out("anomaly_free_with_escrow_id", "anomaly");
    if (b.status === "requested") return out("free_visit_requested", "free_visit");
    if (b.status === "confirmed" || b.status === "in_progress") return out("free_visit_confirmed", "free_visit");
    if (b.status === "completed") return out("closed_completed", "closed");
    if (b.status === "cancelled") return out("closed_cancelled", "closed");
    if (b.status === "declined") return out("closed_declined", "closed");
    return out("anomaly_free_status_mismatch", "anomaly");
  }

  // C. a positive amount
  if (b.paymentStatus === "pending" || b.paymentStatus === "processing" || b.paymentStatus === "failed") {
    if (hasEscrowId) return out("anomaly_escrow_id_without_payment", "anomaly");
    if (b.status === "pending_payment") return out("unpaid_pending_payment", "unpaid");
    if (b.status === "cancelled") return out("closed_cancelled_unpaid", "closed");
    return out("anomaly_status_payment_mismatch", "anomaly");
  }
  if (b.paymentStatus === "refunded") return out("anomaly_refunded_without_settlement", "anomaly");

  // payment completed
  if (hasEscrowId) {
    switch (escrow.state) {
      case "locked":
        return out("verified_funds_locked_no_settlement", "financial_outstanding", heldConsistency);
      case "closed":
        return out("closed_escrow_closed_no_settlement", "closed");
      case "missing":
        return out("anomaly_escrow_missing_or_invalid", "anomaly");
      case "unknown":
        return out("anomaly_escrow_state_unknown", "anomaly");
      default:
        return out("unresolved_paid_with_escrow_id", "unresolved_candidate");
    }
  }
  if (b.status === "cancelled") return out("anomaly_cancelled_paid_without_refund_evidence", "anomaly");
  if (b.status === "completed" || b.status === "declined") return out("anomaly_terminal_paid_without_settlement", "anomaly");
  if (b.status === "confirmed" || b.status === "in_progress") return out("anomaly_paid_without_escrow_unverified", "anomaly");
  if (b.status === "pending_payment") return out("anomaly_paid_but_pending_payment", "anomaly");
  return out("anomaly_ambiguous_paid", "anomaly");
}

/**
 * Reads the booking's escrow transaction (bookingEscrowSummary: read-only, checks that the
 * transaction is an escrow_lock of this buyer for this booking) and reduces it to evidence.
 */
export async function resolveEscrowEvidence(ctx: { db: any }, b: Doc<"bookings">): Promise<EscrowEvidence> {
  if (!needsEscrowVerification(b)) return { state: "not_needed" };
  const summary = await bookingEscrowSummary(ctx, b);
  if (!summary) return { state: "missing" };
  if (summary.escrowStatus === "locked") return { state: "locked" };
  if (summary.escrowStatus === "released" || summary.escrowStatus === "refunded") {
    return { state: "closed", status: summary.escrowStatus };
  }
  return { state: "unknown" };
}

export type ListingTag = "individual_dealer" | "car_company" | "untagged";
export type ListingLifecycle = "active" | "unpublished" | "sold" | "taken_down" | "deleted";
export type OwnerClass =
  | "admin"
  | "company_approved"
  | "company_approval_lapsed"
  | "dealer_capability"
  | "other"
  | "missing";

/**
 * Mutually exclusive classification of a stored vehicle listing, evaluated in this order:
 *  sale_standard                    total_sale with the car_sale category (purchasable)
 *  sale_commercial                  total_sale with any other category (purchasable)
 *  seed_or_demo_signature           NOT total_sale, and the row carries a seed / pre-fleet signature
 *  sale_intent_under_hire_pricing   NOT total_sale, but a sale price exists and no daily price
 *                                   (a possible sale: checked before the hire buckets so it is never
 *                                   counted as a confirmed hire)
 *  hire_daily_car                   car_rental priced per day
 *  hire_or_service_van              delivery_van priced per day (daily hire or delivery service: unknown)
 *  haulage_service                  sand_dump_truck / container_freight_truck priced per trip
 *  inconsistent_or_other            anything else
 * Only the first two are purchasable (escrow requires pricingType === "total_sale").
 */
export type ListingClass =
  | "sale_standard"
  | "sale_commercial"
  | "seed_or_demo_signature"
  | "hire_daily_car"
  | "hire_or_service_van"
  | "haulage_service"
  | "sale_intent_under_hire_pricing"
  | "inconsistent_or_other";

type ClassifiableListing = Pick<
  Doc<"vehicleListings">,
  "category" | "pricingType" | "salePrice" | "pricePerDay"
> & { listingIntent?: string; vehicleType?: string };

/**
 * A row that the app's create path cannot have produced: `listingIntent` / `vehicleType` are never
 * stored by the app (only by seeds and the pre-fleet schema), and the form never sets both a sale
 * price and a daily price.
 */
export function hasSeedOrLegacySignature(l: ClassifiableListing): boolean {
  if (l.listingIntent !== undefined || l.vehicleType !== undefined) return true;
  return typeof l.salePrice === "number" && typeof l.pricePerDay === "number";
}

export function classifyVehicleListing(l: ClassifiableListing): ListingClass {
  if (l.pricingType === "total_sale") return l.category === "car_sale" ? "sale_standard" : "sale_commercial";
  if (hasSeedOrLegacySignature(l)) return "seed_or_demo_signature";
  if (typeof l.salePrice === "number" && typeof l.pricePerDay !== "number") return "sale_intent_under_hire_pricing";
  if (l.category === "car_rental" && l.pricingType === "per_day") return "hire_daily_car";
  if (l.category === "delivery_van" && l.pricingType === "per_day") return "hire_or_service_van";
  if (
    (l.category === "sand_dump_truck" || l.category === "container_freight_truck") &&
    l.pricingType === "per_trip"
  ) {
    return "haulage_service";
  }
  return "inconsistent_or_other";
}

/** Do the category and the pricing type contradict each other (e.g. a rental priced as a sale)? */
export function categoryPricingContradicts(l: Pick<Doc<"vehicleListings">, "category" | "pricingType">): boolean {
  if (l.pricingType === "total_sale") return l.category === "car_rental";
  return l.category === "car_sale";
}

export function listingLifecycleOf(l: Pick<Doc<"vehicleListings">, "isDeleted" | "isPublished" | "status">): ListingLifecycle {
  if (l.isDeleted === true) return "deleted";
  if (l.status === "TAKEN_DOWN") return "taken_down";
  if (l.isPublished === false) return "unpublished";
  if (l.status === "SOLD") return "sold";
  return "active";
}

export function ownerClassOf(owner: Doc<"users"> | null): OwnerClass {
  if (!owner) return "missing";
  if (businessRole(owner) === "admin") return "admin";
  if (hasCarCompanyCapability(owner)) return "company_approved";
  if (typeof owner.carCompanyApprovedAt === "number") return "company_approval_lapsed";
  if (hasCarDealerCapability(owner)) return "dealer_capability";
  return "other";
}

// Page size: small on purpose. Each listing also costs bounded transaction lookups, and a query has a
// hard 1-second execution limit.
export const DEFAULT_PAGE_SIZE = 50;
export const MAX_PAGE_SIZE = 100;
// Per listing, at most PER_LISTING_SCAN + 1 of the MOST RECENT orders and PER_LISTING_SCAN + 1 of the
// most recent bookings are read (the extra one only proves whether more exist). The result for one
// listing therefore never depends on page boundaries or page size, and a page costs at most
// MAX_PAGE_SIZE x 2 x (PER_LISTING_SCAN + 1) transaction reads.
export const PER_LISTING_SCAN = 10;

type Presence = "open" | "none" | "unknown";

export const classificationPage = internalQuery({
  args: {
    cursor: v.optional(v.union(v.string(), v.null())),
    numItems: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const requested = Math.floor(args.numItems ?? DEFAULT_PAGE_SIZE);
    const numItems = Math.max(1, Math.min(Number.isFinite(requested) ? requested : DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE));
    const page = await ctx.db.query("vehicleListings").paginate({ cursor: args.cursor ?? null, numItems });

    const owners = new Map<string, OwnerClass>();
    const counts: Record<string, number> = {};
    const byClass: Record<string, number> = {};
    let transactionReads = 0;
    let unknownListings = 0;

    for (const l of page.page) {
      const ownerKey = String(l.ownerId);
      let ownerClass = owners.get(ownerKey);
      if (!ownerClass) {
        ownerClass = ownerClassOf(await ctx.db.get(l.ownerId));
        owners.set(ownerKey, ownerClass);
      }

      // Read at most cap + 1 of the most recent records; "complete" means we saw ALL of them.
      const orders = await ctx.db
        .query("escrow_orders")
        .withIndex("by_vehicle", (q) => q.eq("vehicleListingId", l._id))
        .order("desc")
        .take(PER_LISTING_SCAN + 1);
      transactionReads += orders.length;
      const ordersComplete = orders.length <= PER_LISTING_SCAN;

      const bookings = await ctx.db
        .query("bookings")
        .withIndex("by_listing", (q) => q.eq("listingId", l._id as string))
        .order("desc")
        .take(PER_LISTING_SCAN + 1);
      transactionReads += bookings.length;
      const bookingsComplete = bookings.length <= PER_LISTING_SCAN;

      const presence = (found: boolean, complete: boolean, foundLabel: "open" | "any"): string =>
        found ? foundLabel : complete ? "none" : "unknown";
      const orderOpen = (type: string) =>
        presence(orders.some((o) => o.orderType === type && OPEN_ORDER_STATUSES.has(o.status)), ordersComplete, "open");
      // Per-listing flag: escrow transactions are NOT read here (cost), so a paid booking that needs
      // verification is "unresolved", which makes the flag "unknown", never "none".
      const rentalGroups = bookings.filter((b) => b.bookingType === "vehicle_rental").map((b) => classifyBookingObligation(b, needsEscrowVerification(b) ? { state: "not_checked" } : { state: "not_needed" }).group);
      const rentalOpen = rentalGroups.some((g) => g === "financial_outstanding" || g === "unpaid");
      const rentalUnresolved = rentalGroups.some((g) => g === "unresolved_candidate" || g === "anomaly");
      const rentalBookings = rentalOpen ? "open" : bookingsComplete && !rentalUnresolved ? "none" : "unknown";
      const inspections = presence(bookings.some((b) => b.bookingType === "vehicle_inspection"), bookingsComplete, "any");
      if (!ordersComplete || !bookingsComplete) unknownListings++;

      const cls = classifyVehicleListing(l);
      const tag: ListingTag = l.postedAs ?? "untagged";
      const provenance = hasSeedOrLegacySignature(l) ? "seed_or_legacy_signature" : "app_signature";
      const bucket = [
        `class=${cls}`,
        `provenance=${provenance}`,
        `consistent=${categoryPricingContradicts(l) ? "no" : "yes"}`,
        `tag=${tag}`,
        `lifecycle=${listingLifecycleOf(l)}`,
        `owner=${ownerClass}`,
        `rentalOrders=${orderOpen("VEHICLE_RENTAL")}`,
        `purchaseOrders=${orderOpen("VEHICLE_PURCHASE")}`,
        `rentalBookings=${rentalBookings}`,
        `inspections=${inspections}`,
      ].join("|");
      counts[bucket] = (counts[bucket] ?? 0) + 1;
      byClass[cls] = (byClass[cls] ?? 0) + 1;
    }
    return {
      scanned: page.page.length,
      counts,
      byClass,
      // Monitoring for completeness: listings with at least one "unknown" transaction flag. Use
      // openTransactionsPage for the authoritative outstanding totals.
      unknownListings,
      transactionReads,
      isDone: page.isDone,
      continueCursor: page.continueCursor,
    };
  },
});

/**
 * AUTHORITATIVE outstanding-transaction totals, grouped by the class of the listing they belong to.
 *
 * LIMITS (stage 1C-6D, M8): the ORDER side walks only the seven outstanding statuses, so a terminal
 * order (SETTLED / REFUNDED / CANCELLED) that still has an open dispute, claim, checkout or recovery
 * is NOT found here. This is a per-listing-class view of open orders and open/held bookings, NOT an
 * obligations inventory. For historical vehicle-rental exposure use legacyRentalExposureReport.ts.
 *
 * `kind: "orders"` walks `escrow_orders` by outstanding status (`status` = one order status).
 * `kind: "bookings"` walks the `bookings` table by SOURCE (`status` = one of BOOKING_COUNT_SOURCES): the
 * disjoint settlement ranges held / disputed / none of the existing `by_settlement_eligible` index.
 * Each booking is in exactly one range, so a completed traversal counts it once. Paid-with-escrow-id
 * candidates without a settlement record have their escrow transaction read (read-only).
 * Not a transactional snapshot: a booking whose settlement changes mid-run can be counted in two
 * ranges or in neither; run in a quiet window and treat totals accordingly.
 *
 * Complete for a source once `isDone` is true. Every response states its table scope.
 * Counts only: no ids, titles, names, contact details or amounts.
 */
export const openTransactionsPage = internalQuery({
  args: {
    kind: v.union(v.literal("orders"), v.literal("bookings")),
    status: v.string(),
    cursor: v.optional(v.union(v.string(), v.null())),
    numItems: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    if (args.kind === "orders") {
      if (!OPEN_ORDER_STATUSES.has(args.status)) throw new Error("Not an outstanding order status.");
    } else if (!(BOOKING_COUNT_SOURCES as readonly string[]).includes(args.status)) {
      throw new Error("Not a booking count source.");
    }
    const requested = Math.floor(args.numItems ?? DEFAULT_PAGE_SIZE);
    const numItems = Math.max(1, Math.min(Number.isFinite(requested) ? requested : DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE));

    const listingInfo = new Map<string, string>();
    const describe = async (id: Id<"vehicleListings"> | null | undefined): Promise<string> => {
      if (!id) return "listingClass=listing_missing";
      const key = String(id);
      let info = listingInfo.get(key);
      if (!info) {
        const l = await ctx.db.get(id);
        info = l ? `listingClass=${classifyVehicleListing(l)}|lifecycle=${listingLifecycleOf(l)}` : "listingClass=listing_missing";
        listingInfo.set(key, info);
      }
      return info;
    };

    const counts: Record<string, number> = {};
    let scanned = 0;
    let isDone = true;
    let continueCursor = "";
    const scope = {
      table: args.kind === "orders" ? "escrow_orders" : "bookings",
      scopeLabel: args.kind === "orders" ? REPORT_SCOPE_ORDERS : REPORT_SCOPE_BOOKINGS,
      excludes: [...SCOPE_EXCLUDES],
    };

    if (args.kind === "orders") {
      const page = await ctx.db
        .query("escrow_orders")
        .withIndex("by_status", (q) => q.eq("status", args.status as any))
        .paginate({ cursor: args.cursor ?? null, numItems });
      for (const o of page.page) {
        scanned++;
        const key = `scope=${REPORT_SCOPE_ORDERS}|kind=orders|status=${o.status}|type=${o.orderType}|${await describe(o.vehicleListingId)}`;
        counts[key] = (counts[key] ?? 0) + 1;
      }
      isDone = page.isDone;
      continueCursor = page.continueCursor;
    } else {
      // One disjoint range of the existing by_settlement_eligible index per source.
      const value = args.status.split(":")[1] as "none" | "held" | "disputed";
      const page = await ctx.db
        .query("bookings")
        .withIndex("by_settlement_eligible", (q) =>
          q.eq("settlementStatus", value === "none" ? undefined : (value as "held" | "disputed"))
        )
        .paginate({ cursor: args.cursor ?? null, numItems });
      for (const b of page.page) {
        scanned++;
        const evidence = await resolveEscrowEvidence(ctx, b);
        const c = classifyBookingObligation(b, evidence);
        let info = "listingClass=not_vehicle";
        if (b.listingType === "vehicle") {
          info = await describe(ctx.db.normalizeId("vehicleListings", b.listingId));
        }
        const escrow = evidence.state === "closed" ? `closed:${evidence.status}` : evidence.state;
        const key =
          `scope=${REPORT_SCOPE_BOOKINGS}|kind=bookings|group=${c.group}|obligation=${c.obligation}|status=${b.status}` +
          `|settlement=${b.settlementStatus ?? "none"}|payment=${b.paymentStatus}|escrow=${escrow}|type=${b.bookingType}` +
          `|consistency=${c.consistency}|${info}`;
        counts[key] = (counts[key] ?? 0) + 1;
      }
      isDone = page.isDone;
      continueCursor = page.continueCursor;
    }
    return { kind: args.kind, status: args.status, scope, scanned, counts, isDone, continueCursor };
  },
});
