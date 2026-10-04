// convex/lib/publicListing.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — the ONLY shape in which listings leave the backend to the public.
//
// Every public query that returns a property / vehicle / hotel must pass documents through
// these functions. They remove private contact data and every form of exact location
// (street address, latitude/longitude, geohash), and replace the address with a generalized,
// allow-listed location string (see lib/slLocations.ts). Owners and admins use their own,
// authenticated queries for the full record.
// ═══════════════════════════════════════════════════════════════════════

import { publicLocation, publicTown } from "./slLocations";

const PRIVATE_FIELDS = [
  "privateContactPhone",
  "contactPhone",
  "ownerPhone",
  "latitude",
  "longitude",
  "geohash",
  "currentLat",
  "currentLng",
  // moderation internals and the owner's business statistics
  "moderationReason",
  "moderatedAt",
  "moderatedBy",
  "submittedForReviewAt",
  "archivedAt",
  "saveCount",
  "inquiryCount",
  "viewingRequestCount",
] as const;

/**
 * May the public (anyone but the owner, the authorised agent and admins) see or act on this
 * real-estate listing? Drafts, unpublished, archived, deleted, pending-review, rejected and
 * removed listings are NOT public. Unset moderationStatus = legacy / not reviewed = approved.
 */
export function isListingPublic(doc: {
  isDeleted?: boolean;
  isPublished?: boolean;
  archivedAt?: number;
  moderationStatus?: string;
} | null | undefined): boolean {
  if (!doc) return false;
  if (doc.isDeleted === true || doc.isPublished === false) return false;
  if (typeof doc.archivedAt === "number") return false;
  return doc.moderationStatus === undefined || doc.moderationStatus === "approved";
}

export type ListingLifecycle =
  | "active"
  | "off_market"
  | "pending_review"
  | "rejected"
  | "removed"
  | "draft"
  | "unpublished"
  | "archived";

/** The listing's state as its owner sees it (derived from server fields only). */
export function listingLifecycle(doc: {
  isPublished?: boolean;
  archivedAt?: number;
  moderationStatus?: string;
  availabilityStatus?: string;
}): ListingLifecycle {
  if (doc.moderationStatus === "removed") return "removed";
  if (typeof doc.archivedAt === "number") return "archived";
  if (doc.moderationStatus === "rejected") return "rejected";
  if (doc.moderationStatus === "pending_review") return "pending_review";
  if (doc.isPublished === false) return doc.moderationStatus === "approved" ? "unpublished" : "draft";
  if (doc.availabilityStatus && doc.availabilityStatus !== "available") return "off_market";
  return "active";
}

function strip<T extends Record<string, any>>(doc: T): Record<string, any> {
  const out: Record<string, any> = { ...doc };
  for (const k of PRIVATE_FIELDS) delete out[k];
  return out;
}

/** Real-estate listing as shown to the public. */
export function toPublicProperty<T extends Record<string, any>>(doc: T): Record<string, any> {
  const out = strip(doc);
  const loc = publicLocation(doc.city, doc.district);
  out.address = loc; // never the street address
  out.publicLocation = loc;
  out.city = publicTown(doc.city) ?? "";
  return out;
}

/** Vehicle listing as shown to the public (no seller coordinates or private phone). */
export function toPublicVehicle<T extends Record<string, any>>(doc: T): Record<string, any> {
  const out = strip(doc);
  if (typeof doc.location === "string") out.location = publicLocation(doc.location, doc.district);
  out.publicLocation = publicLocation(doc.city ?? doc.location, doc.district);
  return out;
}

/** Hotel / guest house as shown to the public (business city only, no coordinates). */
export function toPublicHotel<T extends Record<string, any>>(doc: T): Record<string, any> {
  const out = strip(doc);
  const loc = publicLocation(doc.city, doc.district);
  out.address = loc;
  out.publicLocation = loc;
  return out;
}
