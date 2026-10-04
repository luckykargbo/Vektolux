/// <reference types="vite/client" />
// Admin review of Real Estate Agent listings: a submitted listing waits as pending_review and is
// not public until an administrator approves it; rejection and removal need a reason, are audited
// and notified; agents cannot approve anything or touch other people's listings; drafts and
// non-approved listings never appear in any public query.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string };
const DAY = 24 * 60 * 60 * 1000;
let seq = 0;

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327500${1000 + seq}`, name, role: role as any,
      isVerified: true, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    } as any)
  );
  return { id, token };
}

async function subscribedAgent(t: T, admin: U, name = "agent"): Promise<U> {
  const agent = await makeUser(t, name, "agent", { roleApprovedAt: Date.now() });
  const plans = await t.run(async (ctx) => ctx.db.query("subscription_plans").collect());
  if (!plans.some((p) => p.tierCode === "AGENT_M")) {
    await t.mutation(api.subscriptions.adminUpsertPlan, {
      sessionToken: admin.token, tierCode: "AGENT_M", name: "Agent Monthly", roleTarget: "agent", basePrice: 100, currency: "SLE",
      billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
    });
  }
  await t.run(async (ctx) => {
    const p = (await ctx.db.query("subscription_plans").collect()).find((x) => x.tierCode === "AGENT_M")!;
    await ctx.db.insert("vendor_subscriptions", {
      userId: agent.id, planId: p._id, tierCode: "AGENT_M", status: "active", startDate: Date.now() - DAY, expiryDate: Date.now() + 30 * DAY,
      amountPaid: 100, currency: "SLE", paymentReference: `sub-${agent.id}`, paymentMethod: "wallet", autoRenew: false, createdAt: Date.now(), updatedAt: Date.now(),
    });
  });
  return agent;
}

const create = (t: T, who: U, publish = true, title = "Hill View Villa") =>
  t.mutation(api.realEstate.createPropertyListing, {
    ownerId: who.id, sessionToken: who.token, title, description: "Four bedrooms with a garden.", category: "sale",
    price: 900000, address: "12 Private Street", city: "Lumley", district: "Western Area Urban", imageStorageIds: [], isPublished: publish,
  });

const mine = async (t: T, who: U, id: string) =>
  ((await t.query(api.realEstate.getMyPropertyListings, { ownerId: who.id, sessionToken: who.token })) as any[]).find((l) => l._id === id);

const moderate = (t: T, who: U, listingId: string, decision: "approve" | "reject" | "remove" | "archive", reason?: string) =>
  t.mutation(api.listingModeration.adminModerateListing, { sessionToken: who.token, listingId, decision, ...(reason ? { reason } : {}) });

/** Is the listing visible through every public read path? */
async function publicEverywhere(t: T, id: string, ownerId: Id<"users">) {
  const list: any[] = await t.query(api.realEstate.listProperties, {});
  const detail = await t.query(api.realEstate.getPropertyById, { listingId: id });
  const posts: any[] = await t.query(api.users.getUserPosts, { userId: ownerId });
  const feed: any = await t.query(api.explore.getExploreFeed, {});
  const search: any = await t.query(api.explore.searchExplore, { searchQuery: "hill" });
  const inFeed = JSON.stringify(feed).includes(id);
  return {
    list: list.some((l) => l._id === id),
    detail: detail !== null,
    posts: posts.some((p) => p._id === id),
    feed: inFeed,
    search: (search.properties as any[]).some((p) => (p._id ?? p.id) === id),
  };
}

const titles = async (t: T, userId: Id<"users">) =>
  (await t.run(async (ctx) => ctx.db.query("user_notifications").collect())).filter((n) => n.userId === (userId as string)).map((n) => n.title);

describe("agent listings wait for admin review", () => {
  test("a submitted listing starts as pending review and is NOT public anywhere", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await subscribedAgent(t, admin);
    const id = await create(t, agent);
    const own = await mine(t, agent, id);
    expect(own.lifecycleStatus).toBe("pending_review");
    expect(own.moderationStatus).toBe("pending_review");
    expect(await publicEverywhere(t, id, agent.id)).toEqual({ list: false, detail: false, posts: false, feed: false, search: false });
    // the agent (owner) can still open it
    expect(await t.query(api.realEstate.getPropertyById, { listingId: id, sessionToken: agent.token })).not.toBeNull();
    // the queue shows it to admins
    const queue: any[] = await t.query(api.listingModeration.adminListListings, { sessionToken: admin.token });
    expect(queue.map((r) => r.id)).toContain(id);
  });

  test("approval makes it public; the agent is notified and the decision is audited", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await subscribedAgent(t, admin);
    const id = await create(t, agent);
    await moderate(t, admin, id, "approve");
    expect((await mine(t, agent, id)).lifecycleStatus).toBe("active");
    expect(await publicEverywhere(t, id, agent.id)).toEqual({ list: true, detail: true, posts: true, feed: true, search: true });
    expect(await titles(t, agent.id)).toContain("Listing approved");
    const audit = await t.run(async (ctx) => ctx.db.query("audit_logs").collect());
    expect(audit.map((a) => a.action)).toContain("LISTING_APPROVED");
  });

  test("rejection needs a reason, stores it, is notified, and the listing stays private until approved", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await subscribedAgent(t, admin);
    const id = await create(t, agent);
    await expect(moderate(t, admin, id, "reject")).rejects.toThrow(/reason/i);
    await expect(moderate(t, admin, id, "reject", "no")).rejects.toThrow(/reason/i);
    await moderate(t, admin, id, "reject", "Photos do not show the property.");
    const own = await mine(t, agent, id);
    expect(own.lifecycleStatus).toBe("rejected");
    expect(own.moderationReason).toBe("Photos do not show the property.");
    expect(await titles(t, agent.id)).toContain("Listing not approved");
    expect((await publicEverywhere(t, id, agent.id)).list).toBe(false);

    // edit + resubmit → back to review, still not public
    const r: any = await t.mutation(api.realEstate.updatePropertyListing, {
      listingId: id, ownerId: agent.id, sessionToken: agent.token, title: "Hill View Villa (new photos)", isPublished: true,
    });
    expect(r.message).toBe("Submitted for review");
    expect((await mine(t, agent, id)).lifecycleStatus).toBe("pending_review");
    expect((await publicEverywhere(t, id, agent.id)).detail).toBe(false);
    // a rejected/pending listing cannot be approved by anyone but an admin
    await moderate(t, admin, id, "approve");
    expect((await publicEverywhere(t, id, agent.id)).detail).toBe(true);
  });

  test("removal needs a reason, is recorded and notified, and the listing can never be republished", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await subscribedAgent(t, admin);
    const id = await create(t, agent);
    await moderate(t, admin, id, "approve");
    await expect(moderate(t, admin, id, "remove")).rejects.toThrow(/reason/i);
    await moderate(t, admin, id, "remove", "Reported as a duplicate scam listing.");
    const own = await mine(t, agent, id);
    expect(own.lifecycleStatus).toBe("removed");
    expect(own.moderationReason).toBe("Reported as a duplicate scam listing.");
    expect(await titles(t, agent.id)).toContain("Listing removed by Vektolux");
    expect((await publicEverywhere(t, id, agent.id)).detail).toBe(false);
    await expect(
      t.mutation(api.realEstate.updatePropertyListing, { listingId: id, ownerId: agent.id, sessionToken: agent.token, isPublished: true })
    ).rejects.toThrow(/removed/i);
    const audit = await t.run(async (ctx) => ctx.db.query("audit_logs").collect());
    const removal = audit.find((a) => a.action === "LISTING_REMOVED")!;
    expect(JSON.parse(removal.snapshot).reason).toBe("Reported as a duplicate scam listing.");
  });

  test("an owner cannot delete a listing an administrator removed (it stays on record)", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await subscribedAgent(t, admin);
    const id = await create(t, agent);
    await moderate(t, admin, id, "remove", "Misleading photos and price.");
    await expect(
      t.mutation(api.realEstate.deletePropertyListing, { listingId: id, ownerId: agent.id, sessionToken: agent.token })
    ).rejects.toThrow(/cannot be deleted/i);
    expect((await mine(t, agent, id)).lifecycleStatus).toBe("removed");
    // a normal listing can still be deleted by its owner
    const other = await create(t, agent, false, "Draft to delete");
    await expect(
      t.mutation(api.realEstate.deletePropertyListing, { listingId: other, ownerId: agent.id, sessionToken: agent.token })
    ).resolves.toMatchObject({ success: true });
  });

  test("the legacy admin takedown is a recorded removal with a reason", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await subscribedAgent(t, admin);
    const id = await create(t, agent);
    await moderate(t, admin, id, "approve");
    await expect(
      t.mutation(api.admin.takeDownListing, { adminId: admin.id, sessionToken: admin.token, listingId: id, listingType: "property" })
    ).rejects.toThrow(/reason/i);
    await t.mutation(api.admin.takeDownListing, {
      adminId: admin.id, sessionToken: admin.token, listingId: id, listingType: "property", reason: "Owner asked us to take it down.",
    });
    expect((await mine(t, agent, id)).lifecycleStatus).toBe("removed");
  });

  test("agents cannot approve listings or change another agent's listing", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await subscribedAgent(t, admin, "agentA");
    const other = await subscribedAgent(t, admin, "agentB");
    const id = await create(t, agent);
    await expect(moderate(t, agent, id, "approve")).rejects.toThrow(/administrator/i);
    await expect(t.query(api.listingModeration.adminListListings, { sessionToken: agent.token })).rejects.toThrow(/administrator/i);
    await expect(
      t.mutation(api.realEstate.updatePropertyListing, { listingId: id, ownerId: other.id, sessionToken: other.token, title: "mine now" })
    ).rejects.toThrow(/permission/i);
    await expect(t.mutation(api.realEstate.archivePropertyListing, { listingId: id, sessionToken: other.token })).rejects.toThrow(/permission/i);
    // the other agent cannot read the private draft either
    expect(await t.query(api.realEstate.getPropertyById, { listingId: id, sessionToken: other.token })).toBeNull();
  });
});

describe("drafts, re-publishing and the archive", () => {
  test("a draft stays private; unpublishing and re-publishing goes back through review", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await subscribedAgent(t, admin);
    const id = await create(t, agent, false);
    expect((await mine(t, agent, id)).lifecycleStatus).toBe("draft");
    expect((await publicEverywhere(t, id, agent.id)).detail).toBe(false);

    await t.mutation(api.realEstate.updatePropertyListing, { listingId: id, ownerId: agent.id, sessionToken: agent.token, isPublished: true });
    expect((await mine(t, agent, id)).lifecycleStatus).toBe("pending_review");
    // withdrawing from review → draft again
    await t.mutation(api.realEstate.updatePropertyListing, { listingId: id, ownerId: agent.id, sessionToken: agent.token, isPublished: false });
    expect((await mine(t, agent, id)).lifecycleStatus).toBe("draft");

    await t.mutation(api.realEstate.updatePropertyListing, { listingId: id, ownerId: agent.id, sessionToken: agent.token, isPublished: true });
    await moderate(t, admin, id, "approve");
    await t.mutation(api.realEstate.updatePropertyListing, { listingId: id, ownerId: agent.id, sessionToken: agent.token, isPublished: false });
    expect((await mine(t, agent, id)).lifecycleStatus).toBe("unpublished");
    await t.mutation(api.realEstate.updatePropertyListing, { listingId: id, ownerId: agent.id, sessionToken: agent.token, isPublished: true });
    expect((await mine(t, agent, id)).lifecycleStatus).toBe("pending_review");
    expect((await publicEverywhere(t, id, agent.id)).detail).toBe(false);
  });

  test("archive takes a listing off the marketplace; restore brings it back as a private draft", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await subscribedAgent(t, admin);
    const id = await create(t, agent);
    await moderate(t, admin, id, "approve");
    await t.mutation(api.realEstate.archivePropertyListing, { listingId: id, sessionToken: agent.token });
    expect((await mine(t, agent, id)).lifecycleStatus).toBe("archived");
    expect((await publicEverywhere(t, id, agent.id)).detail).toBe(false);
    await expect(
      t.mutation(api.realEstate.updatePropertyListing, { listingId: id, ownerId: agent.id, sessionToken: agent.token, isPublished: true })
    ).rejects.toThrow(/archive/i);
    await t.mutation(api.realEstate.restorePropertyListing, { listingId: id, sessionToken: agent.token });
    expect((await mine(t, agent, id)).lifecycleStatus).toBe("unpublished");
    expect((await publicEverywhere(t, id, agent.id)).detail).toBe(false);
  });

  test("submitting without an active subscription is refused by the server", async () => {
    const t = convexTest(schema, modules);
    const agent = await makeUser(t, "nosub", "agent", { roleApprovedAt: Date.now() });
    await expect(create(t, agent)).rejects.toThrow(/subscription/i);
  });

  test("a Real Estate Owner's own listing is not part of the agent review (unchanged)", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "property_owner", { roleApprovedAt: Date.now() });
    const id = await create(t, owner);
    expect((await mine(t, owner, id)).lifecycleStatus).toBe("active");
    expect((await publicEverywhere(t, id, owner.id)).detail).toBe(true);
  });

  test("moderation internals and the owner's statistics never reach the public", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await subscribedAgent(t, admin);
    const id = await create(t, agent);
    await moderate(t, admin, id, "approve");
    const detail: any = await t.query(api.realEstate.getPropertyById, { listingId: id });
    for (const k of ["moderatedBy", "moderationReason", "inquiryCount", "viewingRequestCount", "saveCount", "privateContactPhone", "latitude"]) {
      expect(detail).not.toHaveProperty(k);
    }
    expect(JSON.stringify(detail)).not.toContain("12 Private Street");
  });
});
