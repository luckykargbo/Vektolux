// convex/lib/auth.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Server-Side Authentication & Authorization Helpers
// Ensures that all user operations, financial mutations, and admin tasks
// verify the caller's identity server-side. Never trusts raw client args.
// ═══════════════════════════════════════════════════════════════════════

import { Doc, Id } from "../_generated/dataModel";

export interface AuthenticatedUser {
  userId: Id<"users">;
  user: Doc<"users">;
}

export interface AuthContextArgs {
  sessionToken?: string;
  userId?: string | Id<"users">;
}

/**
 * Validates caller identity either via:
 * 1. ctx.auth.getUserIdentity() (when JWT/OIDC identity is configured), OR
 * 2. sessionToken validated against users table index "by_sessionToken", OR
 * 3. explicit userId validated with corresponding sessionToken.
 *
 * CRITICAL SECURITY PRINCIPLE:
 * We NEVER trust `userId` alone for authorization. If `userId` is passed alongside
 * a `sessionToken`, the token MUST belong to that specific user (or an admin).
 * If neither valid sessionToken nor valid auth identity is provided, this throws.
 */
export async function requireAuthenticatedUser(
  ctx: { db: any; auth: any },
  args?: AuthContextArgs
): Promise<AuthenticatedUser> {
  // 1. Check ctx.auth.getUserIdentity() (JWT / OIDC)
  try {
    const identity = await ctx.auth.getUserIdentity();
    if (identity) {
      // Find user by externalAuthId or email
      let user = await ctx.db
        .query("users")
        .withIndex("by_external_auth", (q: any) =>
          q.eq("authProvider", "convex").eq("externalAuthId", identity.tokenIdentifier)
        )
        .first();

      if (!user && identity.email) {
        user = await ctx.db
          .query("users")
          .withIndex("by_email", (q: any) => q.eq("email", identity.email.toLowerCase()))
          .first();
      }

      if (user && user.isActive) {
        // If an explicit userId was requested, ensure it matches or caller is admin
        if (args?.userId) {
          const normRequested = ctx.db.normalizeId("users", args.userId as string);
          if (normRequested && normRequested !== user._id && user.role !== "admin") {
            throw new Error("Unauthorized: Cannot perform operations for another user.");
          }
        }
        return { userId: user._id, user };
      }
    }
  } catch (err: any) {
    if (err.message?.includes("Unauthorized")) throw err;
  }

  // 2. Check sessionToken from args
  const rawToken = args?.sessionToken?.trim();
  if (rawToken && rawToken.length >= 16) {
    const user = await ctx.db
      .query("users")
      .withIndex("by_sessionToken", (q: any) => q.eq("sessionToken", rawToken))
      .first();

    if (user) {
      if (!user.isActive) {
        throw new Error("Account has been deactivated. Please contact support.");
      }
      if (typeof user.sessionExpiresAt === "number" && user.sessionExpiresAt <= Date.now()) {
        throw new Error("Authentication required: Your session has expired. Please log in again.");
      }

      // If an explicit userId was also passed, ensure it matches or caller is admin
      if (args?.userId) {
        const normRequested = ctx.db.normalizeId("users", args.userId as string);
        if (normRequested && normRequested !== user._id && user.role !== "admin") {
          throw new Error("Unauthorized: Session does not match requested user.");
        }
      }

      return { userId: user._id, user };
    }
  }

  throw new Error("Authentication required: Please log in to perform this operation.");
}

/**
 * Validates that the caller is authenticated AND has role === "admin".
 */
export async function requireAdmin(
  ctx: { db: any; auth: any },
  args?: AuthContextArgs
): Promise<AuthenticatedUser> {
  const auth = await requireAuthenticatedUser(ctx, args);
  if (auth.user.role !== "admin") {
    throw new Error("Unauthorized: Administrator privileges required.");
  }
  return auth;
}

/**
 * Strict "acting as myself" guard for wallet/financial/ownership operations.
 *
 * Unlike requireAuthenticatedUser this has NO admin impersonation: an admin
 * session cannot act as another user. A client-supplied user id is only ever a
 * consistency check against the authenticated identity, never a source of
 * identity. A missing/invalid session token always fails.
 */
export async function requireSelf(
  ctx: { db: any; auth: any },
  sessionToken: string | undefined,
  claimedUserId?: string
): Promise<AuthenticatedUser> {
  const auth = await requireAuthenticatedUser(ctx, { sessionToken });
  if (claimedUserId) {
    const normalized = ctx.db.normalizeId("users", claimedUserId);
    const matchesEmail = auth.user.email?.toLowerCase() === claimedUserId.toLowerCase();
    if (normalized ? normalized !== auth.userId : !matchesEmail) {
      throw new Error("Unauthorized: Cannot access another user's data.");
    }
  }
  return auth;
}

/**
 * The caller must be one of the named participants of a financial record, or an admin.
 * Used for escrow release/settlement/view so third parties can never move or read
 * someone else's protected funds.
 */
export async function requireParticipantOrAdmin(
  ctx: { db: any; auth: any },
  sessionToken: string | undefined,
  participantIds: Array<Id<"users"> | string | null | undefined>
): Promise<AuthenticatedUser & { isAdmin: boolean }> {
  const auth = await requireSelf(ctx, sessionToken);
  const isAdmin = auth.user.role === "admin";
  const isParty = participantIds.some((p) => p && String(p) === String(auth.userId));
  if (!isAdmin && !isParty) {
    throw new Error("Unauthorized: You are not a party to this transaction.");
  }
  return { ...auth, isAdmin };
}

/**
 * The caller must be an admin acting on their own session (no impersonation).
 */
export async function requireAdminSession(
  ctx: { db: any; auth: any },
  sessionToken: string | undefined
): Promise<AuthenticatedUser> {
  const auth = await requireSelf(ctx, sessionToken);
  if (auth.user.role !== "admin") {
    throw new Error("Unauthorized: Administrator privileges required.");
  }
  return auth;
}

/**
 * Loads a document and verifies the authenticated caller owns it.
 * `ownerField` is the field on the document holding the owner's user id.
 * Admins are NOT exempt here; admin moderation goes through admin-only endpoints.
 */
export async function requireOwnedDoc(
  ctx: { db: any; auth: any },
  table: string,
  rawId: string,
  sessionToken: string | undefined,
  ownerField: string = "ownerId"
): Promise<{ auth: AuthenticatedUser; doc: any }> {
  const auth = await requireSelf(ctx, sessionToken);
  const id = ctx.db.normalizeId(table, rawId);
  if (!id) throw new Error("Listing not found");
  const doc = await ctx.db.get(id);
  if (!doc) throw new Error("Listing not found");
  if (doc[ownerField] !== auth.userId) {
    throw new Error("You do not have permission to modify this listing");
  }
  return { auth, doc };
}

/**
 * Optional helper for read queries that want to resolve a user if authenticated,
 * but safely return null if unauthenticated without throwing.
 */
export async function resolveOptionalUser(
  ctx: { db: any; auth: any },
  args?: AuthContextArgs
): Promise<AuthenticatedUser | null> {
  try {
    return await requireAuthenticatedUser(ctx, args);
  } catch {
    return null;
  }
}
