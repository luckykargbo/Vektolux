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
] as const;

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
