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
// Real Estate Agent, Hotel/Guest-House Owner and Car Company are subscription-based capabilities:
// each needs ITS OWN active subscription (one never satisfies another). Real Estate Owners and
// individual Vehicle Dealers post once their role is approved and never need a subscription, even if
// the same account also holds a subscription-required capability. A client never posts.
// ═══════════════════════════════════════════════════════════════════════

import { Doc, Id } from "../_generated/dataModel";

export type BusinessRole =
  | "client"
  | "real_estate_agent"
  | "real_estate_owner"
  | "vehicle_dealer"
  | "hotel_owner"
  | "admin";

/** Subscription-required capabilities. "merchant" (legacy plan target) is deliberately NOT one. */
export type SubscriptionRole = "agent" | "hotel_operator" | "car_company";

/** Capability a vehicle listing is posted under. Only "car_company" needs a subscription. */
export type VehiclePostingCapability = "individual_dealer" | "car_company";

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

/**
 * Car Dealer capability: an approved dealer, or an approved Real Estate Agent whose separate Car
 * Dealer application was approved by an administrator (roles.ts). Never implied by any other role.
 */
export function hasCarDealerCapability(user: Doc<"users">): boolean {
  if (!user.isActive || !isRoleApproved(user)) return false;
  const role = businessRole(user);
  if (role === "vehicle_dealer") return true;
  return role === "real_estate_agent" && typeof user.vehicleDealerApprovedAt === "number";
}

/**
 * Car Company capability: explicitly approved by an administrator (users.carCompanyApprovedAt, set
 * only by roles:adminDecideRoleApplication) AND linked to a verified BUSINESS account. It lapses
 * when the account is deactivated, its business verification is no longer approved, or its business
 * identity (name + TIN) is no longer the one the approval was granted for. It is never implied by
 * any role, by the individual dealer capability, or by a subscription.
 */
export function hasCarCompanyCapability(user: Doc<"users">): boolean {
  if (!user.isActive) return false;
  if (typeof user.carCompanyApprovedAt !== "number") return false;
  if (!(user.accountType === "BUSINESS" && isIdentityVerified(user))) return false;
  return carCompanyIdentityMatchesApproval(user);
}

/** Case-, spacing- and punctuation-insensitive form used to compare business names and TINs. */
export function normalizeBusinessIdentity(value: unknown): string {
  return String(value ?? "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "");
}

/** The business identity currently on the account (what KYC verified). */
export function currentBusinessIdentity(user: Doc<"users">): { name: string; tin: string } {
  return {
    name: String(user.businessName ?? "").trim(),
    tin: String(user.tinNumber ?? user.tin ?? "").trim(),
  };
}

/**
 * Does the account's current business name and TIN still match the identity its car-company approval
 * was granted for? Fails closed: an approval without a recorded identity never matches, so a changed
 * (or never-recorded) identity needs a fresh car-company review, never a silent carry-over.
 */
export function carCompanyIdentityMatchesApproval(user: Doc<"users">): boolean {
  const approvedName = normalizeBusinessIdentity(user.carCompanyApprovedName);
  const approvedTin = normalizeBusinessIdentity(user.carCompanyApprovedTin);
  if (!approvedName || !approvedTin) return false;
  const now = currentBusinessIdentity(user);
  return normalizeBusinessIdentity(now.name) === approvedName && normalizeBusinessIdentity(now.tin) === approvedTin;
}

/** An approval is on record but the business identity has since changed (re-review required). */
export function carCompanyReapprovalRequired(user: Doc<"users">): boolean {
  return typeof user.carCompanyApprovedAt === "number" && !carCompanyIdentityMatchesApproval(user);
}

/** Identity/business verification approved by an administrator (any of the stored spellings). */
export function isIdentityVerified(user: Doc<"users">): boolean {
  const s = String(user.verificationStatus ?? "").toLowerCase();
  return user.isVerified === true && (s === "verified" || s === "approved");
}

/**
 * Business-verification state for display and approval gating, from authoritative server data only
 * (never from the client): "approved" | "pending" | "rejected" | "missing".
 * "missing" = not a BUSINESS account, or no business name / TIN on record, or never submitted.
 */
export function businessVerificationState(user: Doc<"users">): "approved" | "pending" | "rejected" | "missing" {
  if (user.accountType !== "BUSINESS") return "missing";
  if (!String(user.businessName ?? "").trim() || !String(user.tinNumber ?? "").trim()) return "missing";
  if (isIdentityVerified(user)) return "approved";
  const s = String(user.verificationStatus ?? "").toLowerCase();
  if (s === "rejected") return "rejected";
  if (s === "pending_review" || s === "pending") return "pending";
  return "missing";
}

/** Professional identity shown to the user and on public profiles (server-derived). */
export function professionalTitle(user: Doc<"users">): string {
  const base = baseProfessionalTitle(user);
  if (!hasCarCompanyCapability(user)) return base;
  return base === "Client" ? "Car Company" : `${base} & Car Company`;
}

function baseProfessionalTitle(user: Doc<"users">): string {
  const role = businessRole(user);
  if (role === "real_estate_agent") {
    if (!isRoleApproved(user)) return "Client";
    return hasCarDealerCapability(user) ? "Real Estate Agent & Car Dealer" : "Real Estate Agent";
  }
  if (!isRoleApproved(user)) return role === "admin" ? "Administrator" : "Client";
  switch (role) {
    case "real_estate_owner":
      return "Real Estate Owner";
    case "vehicle_dealer":
      return "Car Dealer";
    case "hotel_owner":
      return "Hotel / Guest House Owner";
    case "admin":
      return "Administrator";
    default:
      return "Client";
  }
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

export type PostingDecision =
  | { allowed: true; capability?: VehiclePostingCapability }
  | { allowed: false; reason: string; code?: "CAPABILITY_REQUIRED" };

/**
 * Server-side decision: may this user create/publish this kind of listing right now?
 *
 * Vehicles are posted under ONE explicit capability, and only that capability's rules apply:
 *   individual_dealer  free (approved Car Dealer / Vehicle Owner, or an agent's dealer add-on)
 *   car_company        needs the approved Car Company capability AND an active car_company
 *                      subscription; no other subscription (agent, hotel) ever satisfies it.
 * An account holding both must choose; the stricter rule is never inferred away. An account holding
 * a single capability does not have to say which.
 */
export async function postingPermission(
  ctx: { db: any },
  user: Doc<"users">,
  kind: PostingKind,
  now: number = Date.now(),
  opts: { capability?: VehiclePostingCapability } = {}
): Promise<PostingDecision> {
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
    const company = hasCarCompanyCapability(user);
    const dealer = hasCarDealerCapability(user);
    let chosen: VehiclePostingCapability | undefined = opts.capability;
    if (!chosen) {
      if (company && dealer) {
        return {
          allowed: false,
          code: "CAPABILITY_REQUIRED",
          reason: "Your account is both a Car Company and a Car Dealer. Choose which one this vehicle is posted under.",
        };
      }
      chosen = company ? "car_company" : "individual_dealer";
    }
    if (chosen === "car_company") {
      if (!company) return needApproval("Car Company");
      return (await activeSubscription(ctx, user._id, "car_company", now))
        ? { allowed: true, capability: "car_company" }
        : { allowed: false, reason: "Your Car Company subscription is not active. Subscribe to post vehicles." };
    }
    // individual dealer: free. (A Real Estate Agent needs the separately approved add-on.)
    if (dealer) return { allowed: true, capability: "individual_dealer" };
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
): Promise<{ verifiedAgent: boolean; verifiedHotel: boolean; verifiedCarCompany: boolean; agentExpiresAt: number | null; hotelExpiresAt: number | null; carCompanyExpiresAt: number | null }> {
  const role = businessRole(user);
  const ok = user.isActive && isRoleApproved(user);
  const agent = ok && role === "real_estate_agent" ? await activeSubscription(ctx, user._id, "agent", now) : null;
  const hotel = ok && role === "hotel_owner" ? await activeSubscription(ctx, user._id, "hotel_operator", now) : null;
  const company = hasCarCompanyCapability(user) ? await activeSubscription(ctx, user._id, "car_company", now) : null;
  return {
    verifiedAgent: !!agent,
    verifiedHotel: !!hotel,
    verifiedCarCompany: !!company,
    agentExpiresAt: agent?.expiryDate ?? null,
    hotelExpiresAt: hotel?.expiryDate ?? null,
    carCompanyExpiresAt: company?.expiryDate ?? null,
  };
}

/** Role requested in an application -> stored users.role on approval. */
export function roleForApplication(target: string): "agent" | "property_owner" | "dealer" | "hotel_operator" | null {
  // "car_company" is a capability add-on, not a primary role: it never maps to users.role.
  if (target === "agent") return "agent";
  if (target === "property_owner") return "property_owner";
  if (target === "dealer" || target === "merchant") return "dealer";
  if (target === "hotel_operator") return "hotel_operator";
  return null;
}
