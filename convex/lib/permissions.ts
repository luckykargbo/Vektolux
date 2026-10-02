// convex/lib/permissions.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Business roles, professional subscriptions and posting privileges.
//
// Four separate concepts, all decided server-side:
//   1. Identity verification (KYC)      users.verificationStatus / isVerified (admin-reviewed)
//   2. Business role                    users.role — granted ONLY by an admin-approved application
//   3. Professional subscription        vendor_subscriptions (active AND not expired)
//   4. Posting privilege / pro badge    computed from 2 + 3 (never a stored permanent flag)
//
// Real Estate Agent and Hotel/Guest-House Owner are subscription-based professionals: they can
// post only while their subscription is active. Real Estate Owners and Vehicle Dealers post once
// their role is approved. A client never posts.
// ═══════════════════════════════════════════════════════════════════════

import { Doc, Id } from "../_generated/dataModel";

export type BusinessRole =
  | "client"
  | "real_estate_agent"
  | "real_estate_owner"
  | "vehicle_dealer"
  | "hotel_owner"
  | "admin";

export type SubscriptionRole = "agent" | "hotel_operator";

/** Maps the stored role (including legacy spellings) to a business role. */
export function businessRole(user: Pick<Doc<"users">, "role">): BusinessRole {
  const r = String(user.role ?? "").toLowerCase();
  if (r === "admin") return "admin";
  if (r === "agent") return "real_estate_agent";
  if (r === "property_owner" || r === "seller") return "real_estate_owner";
  if (r === "merchant" || r === "dealer") return "vehicle_dealer";
  if (r === "hotel_operator") return "hotel_owner";
  return "client"; // client, buyer, driver (legacy) …
}

/**
 * True when the user's business role was actually approved by an administrator.
 * New approvals set roleApprovedAt; legacy approvals are recognised by the flags the old
 * admin flows set. Self-selected roles at registration are NOT approvals.
 */
export function isRoleApproved(user: Doc<"users">): boolean {
  if (user.role === "admin") return true;
  if (user.roleApprovedAt) return true;
  return (
    user.isVerifiedAgent === true ||
    user.isVerifiedMerchant === true ||
    user.isVerifiedSeller === true
  );
}

/** The user's subscription for a professional role, only if active AND not expired. */
export async function activeSubscription(
  ctx: { db: any },
  userId: Id<"users">,
  roleTarget: SubscriptionRole,
  now: number = Date.now()
): Promise<Doc<"vendor_subscriptions"> | null> {
  const subs = await ctx.db
    .query("vendor_subscriptions")
    .withIndex("by_userId_and_status", (q: any) => q.eq("userId", userId).eq("status", "active"))
    .take(20);
  for (const s of subs) {
    if (s.expiryDate <= now) continue;
    const plan = await ctx.db.get(s.planId);
    if (plan?.roleTarget === roleTarget) return s;
  }
  return null;
}

// ─── Legacy-agent subscription policy ────────────────────────────────
//
// Real Estate Agents approved BEFORE the subscription policy launched get ONE fixed grace period:
//   gracePeriodEndsAt = LEGACY_SUBSCRIPTION_POLICY_LAUNCH_TIMESTAMP + 14 days
// It is computed from constants only (never "now + 14 days") and nothing is stored per user, so no
// query, login, device, reinstall, listing or subscription check can start, move or extend it.
//
// ⚠ PRODUCTION CONFIGURATION — REQUIRED BEFORE THE POLICY CAN APPLY:
// Set the value below to the exact launch moment as a literal Unix timestamp in MILLISECONDS (UTC),
// e.g. 1792800000000, in the same commit/deploy that ships the policy. It is deliberately null:
// while null (or invalid), NO grace period is granted to anyone (fail safe) and every agent needs a
// paid, active subscription to publish.
export const LEGACY_SUBSCRIPTION_POLICY_LAUNCH_TIMESTAMP: number | null = null;

export const LEGACY_GRACE_PERIOD_MS = 14 * 24 * 60 * 60 * 1000;

// Plausibility bounds: catches a value typed in seconds instead of milliseconds, or a typo.
const MIN_PLAUSIBLE_LAUNCH = Date.UTC(2025, 0, 1);
const MAX_PLAUSIBLE_LAUNCH = Date.UTC(2100, 0, 1);

function validLaunch(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= MIN_PLAUSIBLE_LAUNCH && value < MAX_PLAUSIBLE_LAUNCH
    ? value
    : null;
}

/**
 * The launch timestamp in force, or null when the policy is not configured.
 * Tests inject a value through `globalThis.__VEKTOLUX_TEST_POLICY_LAUNCH_TS__`; that hook is honoured
 * ONLY inside the Vitest runner and can never be reached by a client.
 */
export function configuredPolicyLaunchTimestamp(): number | null {
  if (process.env.VITEST === "true") {
    const injected = (globalThis as any).__VEKTOLUX_TEST_POLICY_LAUNCH_TS__;
    if (injected !== undefined) return validLaunch(injected);
  }
  return validLaunch(LEGACY_SUBSCRIPTION_POLICY_LAUNCH_TIMESTAMP);
}

export type LegacyGrace = {
  /** The policy launch timestamp is configured. */
  configured: boolean;
  /** This user is an approved legacy agent (whatever the date). */
  eligible: boolean;
  /** Eligible AND the fixed grace window has not ended yet. */
  active: boolean;
  /** Fixed end of the grace window (launch + 14 days) for eligible agents, else null. */
  endsAt: number | null;
};

/**
 * Legacy-agent eligibility (server data only):
 *   an ACTIVE, APPROVED Real Estate Agent who either
 *     A) was approved by the old flow: isVerifiedAgent === true and NO roleApprovedAt, or
 *     B) was approved before the launch: roleApprovedAt < launch.
 * Not eligible: users who only selected the agent role, pending applications, suspended agents
 * (their role reverts to client), other roles (incl. the admin/seed account), and agents approved
 * at/after the launch. Nothing is eligible while the launch timestamp is not configured.
 */
export function legacyAgentGrace(
  user: Doc<"users">,
  now: number = Date.now(),
  launch: number | null = configuredPolicyLaunchTimestamp()
): LegacyGrace {
  if (launch === null) return { configured: false, eligible: false, active: false, endsAt: null };
  const isApprovedAgent = user.isActive && businessRole(user) === "real_estate_agent" && isRoleApproved(user);
  const approvedAt = user.roleApprovedAt;
  const pathA = user.isVerifiedAgent === true && (approvedAt === undefined || approvedAt === null);
  const pathB = typeof approvedAt === "number" && approvedAt < launch;
  const eligible = isApprovedAgent && (pathA || pathB);
  const endsAt = launch + LEGACY_GRACE_PERIOD_MS;
  return { configured: true, eligible, active: eligible && now < endsAt, endsAt: eligible ? endsAt : null };
}

export type PostingKind = "property" | "vehicle" | "hotel";

/** Server-side decision: may this user create/publish this kind of listing right now? */
export async function postingPermission(
  ctx: { db: any },
  user: Doc<"users">,
  kind: PostingKind,
  now: number = Date.now()
): Promise<{ allowed: true } | { allowed: false; reason: string }> {
  if (!user.isActive) return { allowed: false, reason: "Your account is not active." };
  const role = businessRole(user);
  if (role === "admin") return { allowed: true };

  const approved = isRoleApproved(user);
  const needApproval = (label: string) => ({
    allowed: false as const,
    reason: `Posting requires an approved ${label} account. Apply from your account and wait for review.`,
  });

  if (kind === "property") {
    if (role === "real_estate_owner") return approved ? { allowed: true } : needApproval("Real Estate Owner");
    if (role === "real_estate_agent") {
      if (!approved) return needApproval("Real Estate Agent");
      // 1) A paid, active subscription is authoritative.
      if (await activeSubscription(ctx, user._id, "agent", now)) return { allowed: true };
      // 2) Otherwise only an eligible legacy agent inside the FIXED grace window may post.
      const grace = legacyAgentGrace(user, now);
      if (grace.active) return { allowed: true };
      if (grace.eligible && grace.endsAt !== null) {
        return {
          allowed: false,
          reason: `Your legacy-agent grace period ended on ${new Date(grace.endsAt).toUTCString()}. Subscribe to keep posting listings.`,
        };
      }
      return { allowed: false, reason: "Your Real Estate Agent subscription is not active. Subscribe to post listings." };
    }
    return needApproval("Real Estate Owner or Real Estate Agent");
  }
  if (kind === "vehicle") {
    if (role === "vehicle_dealer") return approved ? { allowed: true } : needApproval("Car Dealer / Vehicle Owner");
    return needApproval("Car Dealer / Vehicle Owner");
  }
  // hotel
  if (role === "hotel_owner") {
    if (!approved) return needApproval("Hotel / Guest House Owner");
    return (await activeSubscription(ctx, user._id, "hotel_operator", now))
      ? { allowed: true }
      : { allowed: false, reason: "Your Hotel / Guest House subscription is not active. Renew it to manage listings." };
  }
  return needApproval("Hotel / Guest House Owner");
}

/** Computed professional badge (never stored). */
export async function professionalBadge(
  ctx: { db: any },
  user: Doc<"users">,
  now: number = Date.now()
): Promise<{ verifiedAgent: boolean; verifiedHotel: boolean; agentExpiresAt: number | null; hotelExpiresAt: number | null }> {
  const role = businessRole(user);
  const ok = user.isActive && isRoleApproved(user);
  const agent = ok && role === "real_estate_agent" ? await activeSubscription(ctx, user._id, "agent", now) : null;
  const hotel = ok && role === "hotel_owner" ? await activeSubscription(ctx, user._id, "hotel_operator", now) : null;
  return {
    verifiedAgent: !!agent,
    verifiedHotel: !!hotel,
    agentExpiresAt: agent?.expiryDate ?? null,
    hotelExpiresAt: hotel?.expiryDate ?? null,
  };
}

/** Role requested in an application -> stored users.role on approval. */
export function roleForApplication(target: string): "agent" | "property_owner" | "dealer" | "hotel_operator" | null {
  if (target === "agent") return "agent";
  if (target === "property_owner") return "property_owner";
  if (target === "dealer" || target === "merchant") return "dealer";
  if (target === "hotel_operator") return "hotel_operator";
  return null;
}
