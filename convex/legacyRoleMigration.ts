// convex/legacyRoleMigration.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — One-off, idempotent restore of Real Estate Agents approved by the OLD admin flow
// (see lib/legacyRoles.ts for the exact evidence required and why).
//
// Run AFTER deploying, first as a dry run to see who would change:
//   npx convex run legacyRoleMigration:backfillLegacyAgentRoles '{"dryRun": true}'
//   npx convex run legacyRoleMigration:backfillLegacyAgentRoles
// It walks only APPROVED agent applications (index by_role_status), 100 per transaction, and
// schedules itself for the rest. Running it again changes nothing. It never removes an approval,
// never touches admins / owners / dealers / hotels, and never sets roleApprovedAt.
// (An affected agent who simply logs in again is restored by login as well — auth.ts.)
// ═══════════════════════════════════════════════════════════════════════

import { internalMutation } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import { restoreLegacyAgentRole } from "./lib/legacyRoles";

export const backfillLegacyAgentRoles = internalMutation({
  args: {
    cursor: v.optional(v.union(v.string(), v.null())),
    dryRun: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const dryRun = args.dryRun === true;
    const now = Date.now();
    const page = await ctx.db
      .query("role_applications")
      .withIndex("by_role_status", (q) => q.eq("targetRole", "agent").eq("status", "approved"))
      .paginate({ numItems: 100, cursor: args.cursor ?? null });

    const seen = new Set<string>();
    const restored: string[] = [];
    const skipped: Record<string, number> = {};
    for (const app of page.page) {
      const key = app.userId as string;
      if (seen.has(key)) continue;
      seen.add(key);
      const user = await ctx.db.get(app.userId);
      if (!user) {
        skipped.user_missing = (skipped.user_missing ?? 0) + 1;
        continue;
      }
      const r = await restoreLegacyAgentRole(ctx, user, { now, dryRun });
      if (r.wouldRestore) restored.push(key);
      else skipped[r.reason ?? "unknown"] = (skipped[r.reason ?? "unknown"] ?? 0) + 1;
    }

    // A dry run reports one page at a time (pass continueCursor back to see the next page).
    if (!dryRun && !page.isDone) {
      await ctx.scheduler.runAfter(0, internal.legacyRoleMigration.backfillLegacyAgentRoles, { cursor: page.continueCursor });
    }
    return {
      dryRun,
      applicationsScanned: page.page.length,
      [dryRun ? "wouldRestore" : "restored"]: restored,
      skipped,
      done: page.isDone,
      continueCursor: page.isDone ? null : page.continueCursor,
    };
  },
});
