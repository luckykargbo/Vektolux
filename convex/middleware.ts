// convex/middleware.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Seller Trust & Listing Gatekeeper Guard
// Enforces automated eIDV verification before listing creation.
// ═══════════════════════════════════════════════════════════════════════

import { MutationCtx, QueryCtx } from "./_generated/server";
import { Id } from "./_generated/dataModel";
import { requireSelf } from "./lib/auth";
import { postingPermission, PostingKind } from "./lib/permissions";

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
 * Gatekeeper for listing creation. The caller is the authenticated user (session), and the
 * decision comes from lib/permissions.ts: approved business role + (for agents / hotel owners)
 * an active, unexpired subscription. Selecting a role at signup grants nothing.
 */
export async function requireVerifiedSeller(
  ctx: MutationCtx | QueryCtx,
  ownerId: string,
  sessionToken: string | undefined,
  kind: PostingKind
): Promise<{
  id: Id<"users">;
  name: string;
  email: string;
  isVerified: boolean;
}> {
  const { user } = await requireSelf(ctx, sessionToken, ownerId);
  if (!user.isActive) {
    throw new Error("User account is inactive, suspended, or does not exist.");
  }
  const permission = await postingPermission(ctx, user, kind);
  if (!permission.allowed) {
    const e = new SellerNotVerifiedException(user.verificationStatus ?? "unverified_seller");
    e.message = permission.reason;
    throw e;
  }
  return { id: user._id, name: user.name, email: user.email, isVerified: true };
}
