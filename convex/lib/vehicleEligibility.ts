// convex/lib/vehicleEligibility.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Is a vehicle listing currently OFFERABLE to the public?
//
// A listing posted under the car-company capability (postedAs === "car_company") is offerable only
// while its owner is an active, admin-approved car company on a verified business account AND holds
// an active subscription that targets car_company. Every other listing (individual dealers, legacy
// listings without postedAs, admin listings) is unaffected: this check never makes a free capability
// subscription-required, and no other plan (agent, hotel) can satisfy it.
//
// It only decides DISCOVERY and NEW orders. It never writes, never un-publishes and never touches
// existing orders, escrow, payments or history; when the company is eligible again the listing is
// offered again, provided its own published/deleted/status flags still allow it.
// ═══════════════════════════════════════════════════════════════════════

import { Doc } from "../_generated/dataModel";
import { activeSubscription, hasCarCompanyCapability } from "./permissions";

export type VehicleOfferability =
  | { offerable: true }
  | { offerable: false; reason: "OWNER_NOT_FOUND" | "OWNER_INACTIVE" | "COMPANY_NOT_APPROVED" | "SUBSCRIPTION_INACTIVE" };

type Reader = { db: any };

export async function vehicleOfferability(
  ctx: Reader,
  listing: Pick<Doc<"vehicleListings">, "ownerId"> & { postedAs?: string },
  now: number = Date.now()
): Promise<VehicleOfferability> {
  if (listing.postedAs !== "car_company") return { offerable: true };
  const owner: Doc<"users"> | null = await ctx.db.get(listing.ownerId);
  if (!owner) return { offerable: false, reason: "OWNER_NOT_FOUND" };
  if (owner.isActive === false) return { offerable: false, reason: "OWNER_INACTIVE" };
  if (!hasCarCompanyCapability(owner)) return { offerable: false, reason: "COMPANY_NOT_APPROVED" };
  if (!(await activeSubscription(ctx, owner._id, "car_company", now))) {
    return { offerable: false, reason: "SUBSCRIPTION_INACTIVE" };
  }
  return { offerable: true };
}

/** A per-request checker that evaluates each company owner once (lists share one owner). */
export function vehicleOfferabilityChecker(ctx: Reader, now: number = Date.now()) {
  const byOwner = new Map<string, Promise<VehicleOfferability>>();
  return async (listing: Pick<Doc<"vehicleListings">, "ownerId"> & { postedAs?: string }): Promise<VehicleOfferability> => {
    if (listing.postedAs !== "car_company") return { offerable: true };
    const key = String(listing.ownerId);
    let p = byOwner.get(key);
    if (!p) {
      p = vehicleOfferability(ctx, listing, now);
      byOwner.set(key, p);
    }
    return p;
  };
}

/** Filters a list of listings down to the offerable ones. */
export async function filterOfferableVehicles<T extends Pick<Doc<"vehicleListings">, "ownerId"> & { postedAs?: string }>(
  ctx: Reader,
  listings: T[],
  now: number = Date.now()
): Promise<T[]> {
  const check = vehicleOfferabilityChecker(ctx, now);
  const out: T[] = [];
  for (const l of listings) if ((await check(l)).offerable) out.push(l);
  return out;
}

export type VehicleTransactionBlock =
  | "NOT_FOUND"
  | "DELETED"
  | "UNPUBLISHED"
  | "TAKEN_DOWN"
  | "SOLD"
  | "NOT_OFFERABLE";

/**
 * May a NEW transaction (escrow order, booking, inquiry) start on this vehicle listing right now?
 * Rejects listings that are missing, deleted, unpublished, taken down, sold, or posted by a car
 * company that is no longer eligible. It is only for creating NEW transactions: funding, release,
 * refund, dispute and every other step of an EXISTING order or booking must not call it.
 * (A BOOKED listing is still accepted: availability by date is not modelled on the listing.)
 */
export async function vehicleAcceptsNewTransactions(
  ctx: Reader,
  listing: (Pick<Doc<"vehicleListings">, "ownerId"> & {
    postedAs?: string;
    isDeleted?: boolean;
    isPublished?: boolean;
    status?: string;
  }) | null | undefined,
  now: number = Date.now()
): Promise<{ ok: true } | { ok: false; reason: VehicleTransactionBlock }> {
  if (!listing) return { ok: false, reason: "NOT_FOUND" };
  if (listing.isDeleted === true) return { ok: false, reason: "DELETED" };
  if (listing.isPublished === false) return { ok: false, reason: "UNPUBLISHED" };
  if (listing.status === "TAKEN_DOWN") return { ok: false, reason: "TAKEN_DOWN" };
  if (listing.status === "SOLD") return { ok: false, reason: "SOLD" };
  if (!(await vehicleOfferability(ctx, listing, now)).offerable) return { ok: false, reason: "NOT_OFFERABLE" };
  return { ok: true };
}

export const VEHICLE_UNAVAILABLE_MESSAGE = "This vehicle listing is not available.";
