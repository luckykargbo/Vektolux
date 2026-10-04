/// <reference types="vite/client" />
// Free property site visits are REQUESTS: they start as "requested" (never auto-confirmed); only the
// listing's owner or its active owner-authorised agent can accept or decline (decline needs a
// reason); the client is notified either way; a request is answered once; cancelling is separate.
// Paid inspection passes keep their own flow.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string; phone: string };
const DAY = 24 * 60 * 60 * 1000;
let seq = 0;

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const phone = `+2327800${1000 + seq}`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone, name, role: role as any,
      isVerified: true, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    } as any)
  );
  return { id, token, phone };
}

async function subscribedAgent(t: T, admin: U, name: string): Promise<U> {
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

const property = (t: T, ownerId: Id<"users">, title = "Lumley Family House") =>
  t.run(async (ctx) =>
    ctx.db.insert("realEstateListings", {
      ownerId, title, description: "d", category: "sale", price: 900000, currency: "SLE", address: "4 Private Road", city: "Lumley",
      country: "Sierra Leone", latitude: 0, longitude: 0, geohash: "", imageUrls: [], availabilityStatus: "available",
      isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
    } as any)
  );

const request = (t: T, client: U, listingId: string, at = Date.now() + 2 * DAY, extra: Record<string, unknown> = {}) =>
  t.mutation(api.bookings.createBooking, {
    sessionToken: client.token, listingId, listingType: "property", listingTitle: "anything", bookingType: "property_inspection",
    startTime: at, endTime: at + 3600_000, notes: "Can we meet at the gate?", ...extra,
  } as any) as Promise<any>;
const respond = (t: T, who: U, bookingId: string, decision: "accept" | "decline", reason?: string) =>
  t.mutation(api.bookings.respondToViewingRequest, { sessionToken: who.token, bookingId, decision, ...(reason ? { reason } : {}) });
const booking = (t: T, id: string) => t.run(async (ctx) => ctx.db.get(id as Id<"bookings">)) as Promise<any>;
const titlesOf = async (t: T, u: U) =>
  (await t.run(async (ctx) => ctx.db.query("user_notifications").collect())).filter((n) => n.userId === (u.id as string)).map((n) => n.title);

async function setup(t: T) {
  const admin = await makeUser(t, "admin", "admin");
  const owner = await makeUser(t, "owner", "property_owner", { roleApprovedAt: Date.now() });
  const client = await makeUser(t, "client");
  const agent = await subscribedAgent(t, admin, "agent");
  const outsider = await subscribedAgent(t, admin, "outsider");
  const listingId = await property(t, owner.id);
  // the owner authorises the agent for this listing; the agent accepts
  const inv: any = await t.mutation(api.listingAgents.authorizeListingAgent, {
    sessionToken: owner.token, listingType: "property", listingId, agentUserId: agent.id,
  });
  await t.mutation(api.listingAgents.respondToListingAgentInvitation, {
    sessionToken: agent.token, authorizationId: inv.authorizationId as Id<"listing_agent_authorizations">, accept: true,
  });
  return { admin, owner, client, agent, outsider, listingId };
}

describe("free site-visit requests", () => {
  test("a request starts PENDING (never confirmed) with server-derived details; both managers are notified", async () => {
    const t = convexTest(schema, modules);
    const { owner, client, agent, listingId } = await setup(t);
    const r = await request(t, client, listingId, Date.now() + 2 * DAY, { buyerName: "Spoofed Name", buyerPhone: "+000" });
    expect(r.status).toBe("requested");
    const b = await booking(t, r.bookingId);
    expect(b.status).toBe("requested");
    expect(b.listingTitle).toBe("Lumley Family House"); // not the client's "anything"
    expect(b.buyerName).toBe("client");
    expect(b.buyerPhone).toBe(client.phone);
    expect(await titlesOf(t, client)).toContain("Viewing request sent");
    expect(await titlesOf(t, owner)).toContain("New viewing request");
    expect(await titlesOf(t, agent)).toContain("New viewing request");
  });

  test("the owner and the authorised agent see it; an unrelated agent does not; the phone is hidden until accepted", async () => {
    const t = convexTest(schema, modules);
    const { owner, client, agent, outsider, listingId } = await setup(t);
    const r = await request(t, client, listingId);
    const forOwner: any[] = await t.query(api.bookings.getMyViewingRequests, { sessionToken: owner.token });
    const forAgent: any[] = await t.query(api.bookings.getMyViewingRequests, { sessionToken: agent.token });
    const forOutsider: any[] = await t.query(api.bookings.getMyViewingRequests, { sessionToken: outsider.token });
    expect(forOwner.map((x) => x.id)).toEqual([r.bookingId]);
    expect(forAgent[0]).toMatchObject({ id: r.bookingId, status: "requested", representing: true, clientName: "client", notes: "Can we meet at the gate?" });
    expect(forAgent[0].clientPhone).toBeNull();
    expect(forOutsider).toEqual([]);
    expect(JSON.stringify(forAgent)).not.toContain("4 Private Road");
  });

  test("an authorised agent accepts → CONFIRMED (recorded) and the client is notified; a second answer is refused", async () => {
    const t = convexTest(schema, modules);
    const { client, agent, owner, listingId } = await setup(t);
    const r = await request(t, client, listingId);
    expect(await respond(t, agent, r.bookingId, "accept")).toEqual({ status: "confirmed" });
    const b = await booking(t, r.bookingId);
    expect(b.status).toBe("confirmed");
    expect(b.acceptedBy).toBe(agent.id);
    expect(typeof b.acceptedAt).toBe("number");
    expect(await titlesOf(t, client)).toContain("Your viewing request has been accepted.");
    await expect(respond(t, owner, r.bookingId, "accept")).rejects.toThrow(/already accepted/i);
    await expect(respond(t, owner, r.bookingId, "decline", "Changed my mind")).rejects.toThrow(/already accepted/i);
    const forAgent: any[] = await t.query(api.bookings.getMyViewingRequests, { sessionToken: agent.token });
    expect(forAgent[0].clientPhone).toBe(client.phone); // shared only now
  });

  test("declining needs a reason, is recorded with it, and notifies the client", async () => {
    const t = convexTest(schema, modules);
    const { client, owner, listingId } = await setup(t);
    const r = await request(t, client, listingId);
    await expect(respond(t, owner, r.bookingId, "decline")).rejects.toThrow(/reason/i);
    expect(await respond(t, owner, r.bookingId, "decline", "The house is being repainted that week.")).toEqual({ status: "declined" });
    const b = await booking(t, r.bookingId);
    expect(b).toMatchObject({ status: "declined", declinedBy: owner.id, declineReason: "The house is being repainted that week." });
    expect(await titlesOf(t, client)).toContain("Your viewing request was declined.");
    await expect(respond(t, owner, r.bookingId, "accept")).rejects.toThrow(/already declined/i);
    // a declined request frees the slot for someone else
    const other = await makeUser(t, "other");
    await expect(request(t, other, listingId, b.startTime)).resolves.toMatchObject({ status: "requested" });
  });

  test("nobody else can answer: unrelated agents, the client, or anyone without a session", async () => {
    const t = convexTest(schema, modules);
    const { client, outsider, listingId } = await setup(t);
    const r = await request(t, client, listingId);
    await expect(respond(t, outsider, r.bookingId, "accept")).rejects.toThrow(/listings you manage/i);
    await expect(respond(t, client, r.bookingId, "accept")).rejects.toThrow(/listings you manage/i);
    await expect(
      t.mutation(api.bookings.respondToViewingRequest, { bookingId: r.bookingId, decision: "accept" })
    ).rejects.toThrow(/log in/i);
    expect((await booking(t, r.bookingId)).status).toBe("requested");
  });

  test("cancelling is separate: the listing side must answer a request; the client can withdraw it, and it can't be accepted afterwards", async () => {
    const t = convexTest(schema, modules);
    const { client, owner, agent, listingId } = await setup(t);
    const r = await request(t, client, listingId);
    await expect(
      t.mutation(api.bookings.cancelBooking, { sessionToken: owner.token, bookingId: r.bookingId, userId: owner.id, reason: "no" })
    ).rejects.toThrow(/accept or decline/i);
    await t.mutation(api.bookings.cancelBooking, { sessionToken: client.token, bookingId: r.bookingId, userId: client.id });
    const b = await booking(t, r.bookingId);
    expect(b.status).toBe("cancelled");
    expect(b.cancelReason).toBe("Request withdrawn by the client");
    await expect(respond(t, agent, r.bookingId, "accept")).rejects.toThrow(/no longer be answered/i);
    expect(await titlesOf(t, owner)).toContain("Viewing cancelled");
  });

  test("a confirmed visit can be cancelled by the listing side (the client is told)", async () => {
    const t = convexTest(schema, modules);
    const { client, agent, listingId } = await setup(t);
    const r = await request(t, client, listingId);
    await respond(t, agent, r.bookingId, "accept");
    await t.mutation(api.bookings.cancelBooking, { sessionToken: agent.token, bookingId: r.bookingId, userId: agent.id, reason: "Owner travelling" });
    expect((await booking(t, r.bookingId)).status).toBe("cancelled");
    expect(await titlesOf(t, client)).toContain("Viewing cancelled");
  });

  test("viewing request counts come from the server records", async () => {
    const t = convexTest(schema, modules);
    const { owner, client, listingId } = await setup(t);
    const other = await makeUser(t, "other");
    await request(t, client, listingId, Date.now() + 2 * DAY);
    await request(t, other, listingId, Date.now() + 3 * DAY);
    const mine: any[] = await t.query(api.realEstate.getMyPropertyListings, { ownerId: owner.id, sessionToken: owner.token });
    expect(mine.find((l) => l._id === listingId).viewingRequestCount).toBe(2);
  });

  test("private or unpublished listings cannot be requested", async () => {
    const t = convexTest(schema, modules);
    const { client, listingId } = await setup(t);
    await t.run(async (ctx) => ctx.db.patch(listingId, { moderationStatus: "pending_review" }));
    await expect(request(t, client, listingId)).rejects.toThrow(/not found/i);
  });

  test("paid inspection passes keep their own flow (paid, held, counted)", async () => {
    const t = convexTest(schema, modules);
    const { owner, client, listingId } = await setup(t);
    await t.mutation(internal.walletCore.creditVerifiedDeposit, { userId: client.id, amount: 500, provider: "TEST", providerReference: `f-${seq++}` });
    const pass: any = await t.mutation(api.realEstateEscrow.initiateInspectionPass, {
      sessionToken: client.token, propertyListingId: listingId, scheduledTimestamp: Date.now() + 3600_000, paymentRail: "WALLET",
    } as any);
    expect(pass.status).toBe("FUNDS_LOCKED");
    expect((await t.run(async (ctx) => ctx.db.query("bookings").collect()))).toHaveLength(0);
    const mine: any[] = await t.query(api.realEstate.getMyPropertyListings, { ownerId: owner.id, sessionToken: owner.token });
    expect(mine.find((l) => l._id === listingId).viewingRequestCount).toBe(1);
  });
});
