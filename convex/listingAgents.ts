// convex/listingAgents.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Owner-authorised listing agents.
//
//   Owner → authorises Agent → Agent represents THAT specific listing.
//
//  • Only the listing's owner can invite an agent; only that agent can accept or decline.
//  • The owner can revoke at any time; the agent can withdraw; an admin can revoke.
//  • At most one pending/active agent per listing. Rows are never deleted; every change is
//    appended to listing_agent_events (who, when, what, note).
//  • An agent commission is charged ONLY when the listing has a valid active authorisation at the
//    moment the order is priced AND the fee rule for that vertical has an agent commission
//    (activeListingAgent + lib/fees.ts). The order records which authorisation it relied on;
//    revoking later does not rewrite orders already priced (their fee snapshot is immutable).
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query, MutationCtx } from "./_generated/server";
import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { requireAdminSession, requireSelf } from "./lib/auth";
import { businessRole, isRoleApproved, postingPermission } from "./lib/permissions";

type ListingType = "property" | "vehicle";
const listingTypeValidator = v.union(v.literal("property"), v.literal("vehicle"));
type ActorRole = "owner" | "agent" | "admin";

async function loadListing(
  ctx: { db: any },
  listingType: ListingType,
  listingId: string
): Promise<{ ownerId: Id<"users">; title: string } | null> {
  if (listingType === "property") {
    const id = ctx.db.normalizeId("realEstateListings", listingId);
    const p = id ? await ctx.db.get(id) : null;
    if (!p || p.isDeleted === true) return null;
    return { ownerId: p.ownerId, title: p.title ?? "your listing" };
  }
  const id = ctx.db.normalizeId("vehicleListings", listingId);
  const veh = id ? await ctx.db.get(id) : null;
  if (!veh || veh.isDeleted === true) return null;
  return { ownerId: veh.ownerId, title: veh.title ?? "your listing" };
}

/** Why a user cannot act as a listing agent right now (null when they can). */
export async function agentIneligibility(ctx: { db: any }, agent: Doc<"users"> | null, now = Date.now()): Promise<string | null> {
  if (!agent || agent.isActive === false) return "The agent account is not active.";
  if (businessRole(agent) !== "real_estate_agent" || !isRoleApproved(agent)) {
    return "This user is not an approved Real Estate Agent.";
  }
  const perm = await postingPermission(ctx, agent, "property", now);
  if (!perm.allowed) return "The agent does not have an active professional subscription.";
  return null;
}

/**
 * The listing's agent for pricing/payment: the ACTIVE authorisation whose owner is still the
 * listing's owner and whose agent is still eligible. Anything else means "no agent".
 */
export async function activeListingAgent(
  ctx: { db: any },
  listingType: ListingType,
  listingId: string,
  now = Date.now()
): Promise<{ authorizationId: Id<"listing_agent_authorizations">; agentId: Id<"users"> } | null> {
  const listing = await loadListing(ctx, listingType, listingId);
  if (!listing) return null;
  const rows: Doc<"listing_agent_authorizations">[] = await ctx.db
    .query("listing_agent_authorizations")
    .withIndex("by_listing", (q: any) => q.eq("listingType", listingType).eq("listingId", listingId))
    .collect();
  const active = rows.find((r) => r.status === "active");
  if (!active || active.ownerId !== listing.ownerId) return null;
  if (active.agentId === listing.ownerId) return null;
  const agent = await ctx.db.get(active.agentId);
  if (await agentIneligibility(ctx, agent, now)) return null;
  return { authorizationId: active._id, agentId: active.agentId };
}

async function logEvent(
  ctx: MutationCtx,
  authorizationId: Id<"listing_agent_authorizations">,
  action: "INVITED" | "ACCEPTED" | "DECLINED" | "REVOKED",
  actorId: Id<"users">,
  actorRole: ActorRole,
  note?: string
) {
  await ctx.db.insert("listing_agent_events", {
    authorizationId,
    action,
    actorId,
    actorRole,
    note: note ? note.slice(0, 500) : undefined,
    at: Date.now(),
  });
}

async function notify(ctx: MutationCtx, userId: Id<"users">, title: string, body: string) {
  await ctx.db.insert("user_notifications", {
    userId: userId as string,
    targetType: "single_user",
    title,
    body,
    read: false,
    createdAt: Date.now(),
  });
}

/** The listing's owner invites an approved agent to represent this listing. */
export const authorizeListingAgent = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    listingType: listingTypeValidator,
    listingId: v.string(),
    agentUserId: v.string(),
    note: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const listing = await loadListing(ctx, args.listingType, args.listingId);
    if (!listing || listing.ownerId !== userId) throw new Error("Listing not found.");
    const agentId = ctx.db.normalizeId("users", args.agentUserId);
    if (!agentId) throw new Error("Agent not found.");
    if (agentId === userId) throw new Error("You cannot authorise yourself as the agent.");
    const why = await agentIneligibility(ctx, await ctx.db.get(agentId));
    if (why) throw new Error(why);

    const existing = await ctx.db
      .query("listing_agent_authorizations")
      .withIndex("by_listing", (q) => q.eq("listingType", args.listingType).eq("listingId", args.listingId))
      .collect();
    if (existing.some((r) => r.status === "pending" || r.status === "active")) {
      throw new Error("This listing already has an agent or a pending invitation. Revoke it first.");
    }
    const now = Date.now();
    const authorizationId = await ctx.db.insert("listing_agent_authorizations", {
      listingType: args.listingType,
      listingId: args.listingId,
      ownerId: userId,
      agentId,
      status: "pending",
      invitedAt: now,
      updatedAt: now,
    });
    await logEvent(ctx, authorizationId, "INVITED", userId, "owner", args.note?.trim());
    await notify(ctx, agentId, "Listing agent invitation", `You have been invited to represent "${listing.title}". Accept or decline it in the app.`);
    return { authorizationId: authorizationId as string, status: "pending" as const };
  },
});

/** The invited agent accepts or declines. */
export const respondToListingAgentInvitation = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    authorizationId: v.id("listing_agent_authorizations"),
    accept: v.boolean(),
    note: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId, user } = await requireSelf(ctx, args.sessionToken);
    const auth = await ctx.db.get(args.authorizationId);
    if (!auth || auth.agentId !== userId) throw new Error("Invitation not found.");
    if (auth.status !== "pending") throw new Error(`This invitation is already ${auth.status}.`);
    const listing = await loadListing(ctx, auth.listingType, auth.listingId);
    if (!listing || listing.ownerId !== auth.ownerId) throw new Error("This listing is no longer available.");
    const now = Date.now();
    if (args.accept) {
      const why = await agentIneligibility(ctx, user, now);
      if (why) throw new Error(why);
      await ctx.db.patch(auth._id, { status: "active", acceptedAt: now, updatedAt: now });
      await logEvent(ctx, auth._id, "ACCEPTED", userId, "agent", args.note?.trim());
      await notify(ctx, auth.ownerId, "Agent accepted", `Your agent accepted to represent "${listing.title}".`);
      return { status: "active" as const };
    }
    await ctx.db.patch(auth._id, { status: "declined", declinedAt: now, updatedAt: now });
    await logEvent(ctx, auth._id, "DECLINED", userId, "agent", args.note?.trim());
    await notify(ctx, auth.ownerId, "Agent declined", `The agent declined to represent "${listing.title}".`);
    return { status: "declined" as const };
  },
});

/**
 * Ends a pending or active authorisation: the owner revokes, the agent withdraws, or an admin
 * revokes. Orders already priced keep the terms recorded in their fee snapshot.
 */
export const revokeListingAgent = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    authorizationId: v.id("listing_agent_authorizations"),
    reason: v.string(),
  },
  handler: async (ctx, args) => {
    const { userId, user } = await requireSelf(ctx, args.sessionToken);
    const auth = await ctx.db.get(args.authorizationId);
    if (!auth) throw new Error("Authorisation not found.");
    let role: ActorRole;
    if (auth.ownerId === userId) role = "owner";
    else if (auth.agentId === userId) role = "agent";
    else if (user.role === "admin") role = "admin";
    else throw new Error("Authorisation not found.");
    if (auth.status !== "pending" && auth.status !== "active") throw new Error(`This authorisation is already ${auth.status}.`);
    const reason = args.reason.trim();
    if (reason.length < 3) throw new Error("A reason is required.");
    const now = Date.now();
    await ctx.db.patch(auth._id, {
      status: "revoked",
      revokedAt: now,
      revokedBy: userId,
      revokedByRole: role,
      revokeReason: reason.slice(0, 500),
      updatedAt: now,
    });
    await logEvent(ctx, auth._id, "REVOKED", userId, role, reason);
    const other = role === "agent" ? auth.ownerId : auth.agentId;
    await notify(ctx, other, "Listing agent authorisation ended", "An agent authorisation for one of your listings has ended.");
    if (role === "admin") await notify(ctx, auth.ownerId, "Listing agent authorisation ended", "An administrator ended an agent authorisation for your listing.");
    return { status: "revoked" as const };
  },
});

function view(r: Doc<"listing_agent_authorizations">) {
  return {
    id: r._id as string,
    listingType: r.listingType,
    listingId: r.listingId,
    ownerId: r.ownerId as string,
    agentId: r.agentId as string,
    status: r.status,
    invitedAt: r.invitedAt,
    acceptedAt: r.acceptedAt ?? null,
    declinedAt: r.declinedAt ?? null,
    revokedAt: r.revokedAt ?? null,
    revokedByRole: r.revokedByRole ?? null,
    revokeReason: r.revokeReason ?? null,
  };
}

/** Authorisations for one listing (owner, an agent on it, or admin), with the audit trail. */
export const getListingAgentAuthorizations = query({
  args: { sessionToken: v.optional(v.string()), listingType: listingTypeValidator, listingId: v.string() },
  handler: async (ctx, args) => {
    const { userId, user } = await requireSelf(ctx, args.sessionToken);
    const listing = await loadListing(ctx, args.listingType, args.listingId);
    if (!listing) throw new Error("Listing not found.");
    const rows = await ctx.db
      .query("listing_agent_authorizations")
      .withIndex("by_listing", (q) => q.eq("listingType", args.listingType).eq("listingId", args.listingId))
      .collect();
    const isOwner = listing.ownerId === userId;
    const isAdmin = user.role === "admin";
    const visible = isOwner || isAdmin ? rows : rows.filter((r) => r.agentId === userId);
    if (visible.length === 0 && !isOwner && !isAdmin) throw new Error("Listing not found.");
    const out = [];
    for (const r of visible.sort((a, b) => b.invitedAt - a.invitedAt).slice(0, 50)) {
      const events = await ctx.db
        .query("listing_agent_events")
        .withIndex("by_authorization", (q) => q.eq("authorizationId", r._id))
        .collect();
      out.push({ ...view(r), events: events.map((e) => ({ action: e.action, actorRole: e.actorRole, note: e.note ?? null, at: e.at })) });
    }
    return out;
  },
});

/** The caller's own authorisations as an agent (invitations and listings they represent). */
export const getMyAgentAuthorizations = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const rows = await ctx.db
      .query("listing_agent_authorizations")
      .withIndex("by_agent", (q) => q.eq("agentId", userId))
      .order("desc")
      .take(100);
    return rows.map(view);
  },
});

/** Admin → Listing Agents: every authorisation with parties, listing, lifecycle, audit trail and orders. */
export const adminListListingAgents = query({
  args: {
    sessionToken: v.optional(v.string()),
    status: v.optional(v.union(v.literal("pending"), v.literal("active"), v.literal("declined"), v.literal("revoked"))),
  },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const all = await ctx.db.query("listing_agent_authorizations").order("desc").take(300);
    const rows = args.status ? all.filter((r) => r.status === args.status) : all;
    const people = new Map<string, { name: string; email: string | null }>();
    const person = async (id: Id<"users"> | undefined) => {
      if (!id) return null;
      if (!people.has(id)) {
        const u = await ctx.db.get(id);
        people.set(id, { name: u?.name ?? "Unknown user", email: u?.email ?? null });
      }
      return people.get(id)!;
    };
    const out = [];
    for (const r of rows.slice(0, 200)) {
      const listing = await loadListing(ctx, r.listingType, r.listingId);
      const events = await ctx.db
        .query("listing_agent_events")
        .withIndex("by_authorization", (q) => q.eq("authorizationId", r._id))
        .collect();
      const eventsOut = [];
      for (const e of events) {
        eventsOut.push({ action: e.action, actorRole: e.actorRole, actorName: (await person(e.actorId))?.name ?? null, note: e.note ?? null, at: e.at });
      }
      const contracts = await ctx.db
        .query("re_escrow_contracts")
        .withIndex("by_agent_authorization", (q) => q.eq("agentAuthorizationId", r._id))
        .take(50);
      const passes = await ctx.db
        .query("re_inspection_passes")
        .withIndex("by_agent_authorization", (q) => q.eq("agentAuthorizationId", r._id))
        .take(50);
      out.push({
        ...view(r),
        owner: await person(r.ownerId),
        agent: await person(r.agentId),
        listingTitle: listing?.title ?? null,
        listingOwnerChanged: listing ? listing.ownerId !== r.ownerId : null,
        revokedByName: (await person(r.revokedBy))?.name ?? null,
        events: eventsOut,
        orders: [
          ...contracts.map((c) => ({
            kind: "contract" as const,
            id: c._id as string,
            code: c.contractCode,
            type: c.contractType,
            amount: c.grossAmount,
            agentCommission: c.agentCommissionAmount,
            state: c.currentState,
            createdAt: c.createdAt,
          })),
          ...passes.map((p) => ({
            kind: "viewing_pass" as const,
            id: p._id as string,
            code: `PASS-${(p._id as string).slice(-8).toUpperCase()}`, // never the QR secret
            type: "VIEWING_PASS",
            amount: p.tourFee,
            agentCommission: p.agentNetFee,
            state: p.status,
            createdAt: p.createdAt,
          })),
        ],
      });
    }
    return out;
  },
});
