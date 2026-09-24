// convex/middleware.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Seller Trust & Listing Gatekeeper Guard
// Enforces automated eIDV verification before listing creation.
// ═══════════════════════════════════════════════════════════════════════

import { MutationCtx, QueryCtx } from "./_generated/server";
import { Id } from "./_generated/dataModel";

export class SellerNotVerifiedException extends Error {
  readonly code = "SELLER_NOT_VERIFIED";
  readonly statusCode = 403;
  readonly redirectUrl = "/verification/identity";
  readonly verificationStatus: string;

  constructor(status: string = "unverified") {
    super("Identity verification required to publish listings on Vektolux.");
    this.name = "SellerNotVerifiedException";
    this.verificationStatus = status;
  }
}

/**
 * Gatekeeper guard for listing creation endpoints.
 * Throws a typed 403 error if the user is not verified.
 */
export async function requireVerifiedSeller(
  ctx: MutationCtx | QueryCtx,
  ownerId: string,
  sessionToken?: string
): Promise<{
  id: Id<"users">;
  name: string;
  email: string;
  isVerified: boolean;
}> {
  // 1. Resolve normalized user ID
  const userId = ctx.db.normalizeId("users", ownerId);
  if (!userId) {
    throw new Error("Invalid owner credentials: Account not found.");
  }

  // 2. Fetch user record
  const user = await ctx.db.get(userId);
  if (!user || !user.isActive) {
    throw new Error("User account is inactive, suspended, or does not exist.");
  }

  // 3. Validate session integrity if provided
  if (sessionToken && user.sessionToken && user.sessionToken !== sessionToken) {
    throw new Error("Session expired or invalid. Please authenticate again.");
  }

  // 4. Role & Seller Verification Check:
  // Standard clients/buyers must NOT publish listings unless approved as a verified seller/dealer.
  const isSellerRole =
    user.role === "agent" ||
    user.role === "merchant" ||
    user.role === "seller" ||
    user.role === "dealer" ||
    user.role === "admin";

  const isVerifiedSeller = Boolean(
    user.isVerifiedSeller === true ||
    user.isVerifiedAgent === true ||
    user.isVerifiedMerchant === true ||
    (isSellerRole &&
      (user.isVerified === true ||
        user.verificationStatus === "verified" ||
        user.verificationStatus === "approved"))
  );

  if (!isVerifiedSeller && user.role !== "admin") {
    throw new SellerNotVerifiedException(
      user.verificationStatus ?? "unverified_seller"
    );
  }

  return {
    id: user._id,
    name: user.name,
    email: user.email,
    isVerified: true,
  };
}
