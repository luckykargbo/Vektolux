// convex/lib/hotelAccess.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Who may operate a hotel / guest house (server-side, never the client).
//
// Three INDEPENDENT conditions, each decided by the server:
//   1. the operator's business role was approved by an admin      (roles.ts → users.roleApprovedAt)
//   2. THIS hotel was reviewed and verified by an admin           (hotelVerification.ts)
//   3. the operator has an ACTIVE paid subscription               (subscriptions.ts, payment verified)
// Approving a hotel never starts a subscription, and a subscription never verifies a hotel.
//
// A hotel can be listed publicly only when (2) holds. It can take bookings (and so receive booking
// money) and gain rooms only when (1), (2) and (3) all hold at that moment.
// ═══════════════════════════════════════════════════════════════════════

import { Doc } from "../_generated/dataModel";
import { postingPermission } from "./permissions";

/** Verified = an admin explicitly approved it. Legacy rows without that approval are NOT verified. */
export function hotelIsVerified(h: Pick<Doc<"hotel_profiles">, "isVerified" | "verificationStatus">): boolean {
  return h.isVerified === true && h.verificationStatus === "verified";
}

export function hotelVerificationReason(h: Pick<Doc<"hotel_profiles">, "verificationStatus">): string {
  switch (h.verificationStatus) {
    case "verified":
      return "This property is not verified.";
    case "rejected":
      return "This property's application was rejected.";
    case "suspended":
      return "This property is suspended.";
    default:
      return "This property is awaiting verification by Vektolux.";
  }
}

/** May this hotel (right now) gain rooms or accept bookings? */
export async function hotelOperatingPermission(
  ctx: { db: any },
  hotel: Doc<"hotel_profiles">,
  now: number = Date.now()
): Promise<{ allowed: true } | { allowed: false; reason: string }> {
  if (!hotelIsVerified(hotel)) return { allowed: false, reason: hotelVerificationReason(hotel) };
  const operator: Doc<"users"> | null = await ctx.db.get(hotel.userId);
  if (!operator) return { allowed: false, reason: "The property's operator account was not found." };
  return postingPermission(ctx, operator, "hotel", now);
}
