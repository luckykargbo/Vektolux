// convex/lib/legacyRoles.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Accounts approved as Real Estate Agents by the OLD admin flow.
//
// Before roles.ts existed, an admin approved an agent with businessVerification.approveAgent. That
// function set `isVerifiedAgent: true` and marked the user's role application (targetRole "agent")
// "approved" — but it NEVER changed `users.role`. An agent who had registered as a client therefore
// still has `role: "client"`, and every current check (businessRole → "client") treats them as a
// client: no agent workspace, no agent posting rights.
//
// `isVerifiedAgent` alone is NOT proof of an agent approval. The same old admin queue approved plain
// identity (KYC) submissions and merchants with that very function, and the admin seed account carries
// it as well. So the role is restored only when ALL the evidence of an old agent approval is present:
//   • isVerifiedAgent === true                     (the old approval flag, never cleared by a suspension)
//   • the account has no other business role       (owners, dealers, hotels and admins are never touched)
//   • the NEWEST agent application is "approved"   (an admin decision; a later suspension/rejection wins)
//   • the account is active and its verification was not rejected or suspended
//
// The restore writes only role/activeRole (+ who approved it and when it was restored). It does NOT
// set roleApprovedAt: these accounts stay "approved by the old flow" for the legacy-agent subscription
// policy (permissions.ts legacyAgentGrace, path A), exactly as they were. Nothing is removed.
// ═══════════════════════════════════════════════════════════════════════

import type { Doc } from "../_generated/dataModel";
import { businessRole } from "./permissions";

export type LegacySkipReason =
  | "not_legacy_flagged"
  | "already_has_business_role"
  | "inactive"
  | "verification_withdrawn"
  | "no_agent_application"
  | "agent_application_not_approved";

export type LegacyAgentDecision = { restore: true } | { restore: false; reason: LegacySkipReason };

type AppLike = Pick<Doc<"role_applications">, "targetRole" | "status">;

/**
 * Pure decision (no database access) — `applications` must be the user's role applications,
 * NEWEST FIRST.
 */
export function legacyAgentRestoreDecision(
  user: Pick<Doc<"users">, "role" | "isVerifiedAgent" | "isActive" | "verificationStatus">,
  applications: AppLike[]
): LegacyAgentDecision {
  if (user.isVerifiedAgent !== true) return { restore: false, reason: "not_legacy_flagged" };
  // Already an agent (works today), or another business role / admin: never changed here.
  if (businessRole(user) !== "client") return { restore: false, reason: "already_has_business_role" };
  if (user.isActive === false) return { restore: false, reason: "inactive" };
  const v = String(user.verificationStatus ?? "").toLowerCase();
  if (v === "rejected" || v === "suspended" || v === "revoked") return { restore: false, reason: "verification_withdrawn" };
  const latest = applications.find((a) => a.targetRole === "agent");
  if (!latest) return { restore: false, reason: "no_agent_application" };
  if (latest.status !== "approved") return { restore: false, reason: "agent_application_not_approved" };
  return { restore: true };
}

export type LegacyRestoreResult = { restored: boolean; wouldRestore: boolean; reason?: LegacySkipReason };

/**
 * Applies the decision to one account (idempotent: an account that was restored already has
 * role "agent" and is skipped as "already_has_business_role"). With `dryRun` nothing is written.
 */
export async function restoreLegacyAgentRole(
  ctx: { db: any },
  user: Doc<"users">,
  opts: { now?: number; dryRun?: boolean } = {}
): Promise<LegacyRestoreResult> {
  // Cheap exit for nearly every account: no old agent flag, or already a business role.
  if (user.isVerifiedAgent !== true || businessRole(user) !== "client") {
    return { restored: false, wouldRestore: false, reason: user.isVerifiedAgent !== true ? "not_legacy_flagged" : "already_has_business_role" };
  }
  const applications: Doc<"role_applications">[] = await ctx.db
    .query("role_applications")
    .withIndex("by_user", (q: any) => q.eq("userId", user._id))
    .order("desc")
    .take(20);
  const decision = legacyAgentRestoreDecision(user, applications);
  if (!decision.restore) return { restored: false, wouldRestore: false, reason: decision.reason };
  if (opts.dryRun) return { restored: false, wouldRestore: true };

  const now = opts.now ?? Date.now();
  const approvedApp = applications.find((a) => a.targetRole === "agent")!;
  await ctx.db.patch(user._id, {
    role: "agent",
    activeRole: "agent",
    // who approved it in the old flow, when the application recorded it (never invented)
    ...(user.roleApprovedBy === undefined && approvedApp.reviewedBy ? { roleApprovedBy: approvedApp.reviewedBy } : {}),
    legacyRoleRestoredAt: now,
    updatedAt: now,
  });
  return { restored: true, wouldRestore: true };
}
