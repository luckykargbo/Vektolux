/// <reference types="vite/client" />
// Buyer ↔ seller conversations on a listing (messaging.ts + the inquiry relay), follower
// notifications, and property videos. Only the two participants can read or write a thread;
// nothing private (phone, email, street address) ever appears in what the other side receives.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string; phone: string; email: string };
let seq = 0;

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const phone = `+2327600${1000 + seq}`;
  const email = `${name.toLowerCase()}${seq}@private.vx`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email, phone, name, role: role as any, isVerified: true, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    } as any)
  );
  return { id, token, phone, email };
}

const SECRET_STREET = "17 Hidden Close";
const SECRET_PHONE = "+23277555999";

async function listing(t: T, ownerId: Id<"users">) {
  return t.run(async (ctx) =>
    ctx.db.insert("realEstateListings", {
      ownerId, title: "Hill House", description: "d", category: "sale", price: 320000, currency: "SLE", address: SECRET_STREET,
      city: "Freetown", country: "Sierra Leone", latitude: 8.4012, longitude: -13.2123, geohash: "abc", imageUrls: [],
      privateContactPhone: SECRET_PHONE, availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
    } as any)
  );
}

async function setup(t: T) {
  const seller = await makeUser(t, "Seller", "agent", { roleApprovedAt: Date.now() });
  const buyer = await makeUser(t, "Buyer");
  const listingId = await listing(t, seller.id);
  const res: any = await t.mutation(api.adminPortal.submitContactRequest, {
    sessionToken: buyer.token, buyerId: buyer.id, listingId, listingType: "property", message: "Hello, is this property still available?",
  });
  return { seller, buyer, listingId, requestId: res.requestId as string };
}

const notificationsOf = (t: T, userId: Id<"users">) =>
  t.run(async (ctx) => (await ctx.db.query("user_notifications").collect()).filter((n) => n.userId === (userId as string)));

describe("conversations", () => {
  test("an inquiry opens a conversation: the seller is notified and sees it unread, with nothing private", async () => {
    const t = convexTest(schema, modules);
    const { seller, buyer, requestId } = await setup(t);

    const convs: any[] = await t.query(api.messaging.getMyConversations, { sessionToken: seller.token, role: "seller" });
    expect(convs).toHaveLength(1);
    expect(convs[0]).toMatchObject({ id: requestId, myRole: "seller", status: "pending", unread: 1, lastMessageFromMe: false });
    expect(convs[0].counterpart.name).toBe("Buyer");
    expect(convs[0].listing).toMatchObject({ title: "Hill House", type: "property" });

    const notes = await notificationsOf(t, seller.id);
    expect(notes.map((n) => n.title)).toContain("New inquiry from Buyer");

    const thread: any = await t.query(api.messaging.getThread, { sessionToken: seller.token, requestId });
    const text = JSON.stringify([convs, thread]);
    for (const secret of [SECRET_STREET, SECRET_PHONE, buyer.phone, buyer.email, seller.phone, seller.email, "8.4012"]) {
      expect(text).not.toContain(secret);
    }
  });

  test("replies flow both ways with unread counters and one notification per unread burst", async () => {
    const t = convexTest(schema, modules);
    const { seller, buyer, requestId } = await setup(t);

    await t.mutation(api.messaging.sendMessage, { sessionToken: seller.token, requestId, body: "Yes, it is. When would you like a viewing?" });
    await t.mutation(api.messaging.sendMessage, { sessionToken: seller.token, requestId, body: "I am free on Saturday." });
    let buyerConvs: any[] = await t.query(api.messaging.getMyConversations, { sessionToken: buyer.token, role: "buyer" });
    expect(buyerConvs[0]).toMatchObject({ unread: 2, lastMessage: "I am free on Saturday.", lastMessageFromMe: false });
    const msgNotes = (await notificationsOf(t, buyer.id)).filter((n) => n.title === "New message from Seller");
    expect(msgNotes).toHaveLength(1);

    const thread: any = await t.query(api.messaging.getThread, { sessionToken: buyer.token, requestId });
    expect(thread.canSend).toBe(true);
    expect(thread.messages.map((m: any) => [m.fromMe, m.body])).toEqual([
      [true, "Hello, is this property still available?"],
      [false, "Yes, it is. When would you like a viewing?"],
      [false, "I am free on Saturday."],
    ]);

    await t.mutation(api.messaging.markThreadRead, { sessionToken: buyer.token, requestId });
    buyerConvs = await t.query(api.messaging.getMyConversations, { sessionToken: buyer.token, role: "buyer" });
    expect(buyerConvs[0].unread).toBe(0);
    const sellerView: any = await t.query(api.messaging.getThread, { sessionToken: seller.token, requestId });
    expect(sellerView.messages.filter((m: any) => m.fromMe).every((m: any) => m.readAt !== null)).toBe(true);

    // the seller never opened the thread: the inquiry is still unread, so no extra notification
    await t.mutation(api.messaging.sendMessage, { sessionToken: buyer.token, requestId, body: "Saturday works." });
    const sellerConvs: any[] = await t.query(api.messaging.getMyConversations, { sessionToken: seller.token, role: "seller" });
    expect(sellerConvs[0].unread).toBe(2);
    expect((await notificationsOf(t, seller.id)).filter((n) => n.title === "New message from Buyer")).toHaveLength(0);
  });

  test("only the two participants can read or write a conversation", async () => {
    const t = convexTest(schema, modules);
    const { requestId } = await setup(t);
    const stranger = await makeUser(t, "Stranger");
    await expect(t.query(api.messaging.getThread, { sessionToken: stranger.token, requestId })).rejects.toThrow(/Conversation not found/);
    await expect(t.mutation(api.messaging.sendMessage, { sessionToken: stranger.token, requestId, body: "hi" })).rejects.toThrow(/Conversation not found/);
    await expect(t.mutation(api.messaging.markThreadRead, { sessionToken: stranger.token, requestId })).rejects.toThrow(/Conversation not found/);
    const convs: any[] = await t.query(api.messaging.getMyConversations, { sessionToken: stranger.token });
    expect(convs).toHaveLength(0);
  });

  test("a declined inquiry closes the conversation and tells the buyer", async () => {
    const t = convexTest(schema, modules);
    const { seller, buyer, requestId } = await setup(t);
    await t.mutation(api.adminPortal.respondToContactRequest, { sessionToken: seller.token, sellerId: seller.id, requestId, action: "declined" });
    expect((await notificationsOf(t, buyer.id)).map((n) => n.title)).toContain("Your inquiry was declined");
    const thread: any = await t.query(api.messaging.getThread, { sessionToken: buyer.token, requestId });
    expect(thread.canSend).toBe(false);
    await expect(t.mutation(api.messaging.sendMessage, { sessionToken: buyer.token, requestId, body: "Please?" })).rejects.toThrow(/closed/);
    await expect(t.mutation(api.messaging.sendMessage, { sessionToken: seller.token, requestId, body: "Sorry" })).rejects.toThrow(/closed/);
  });

  test("message limits: not empty, at most 2000 characters, at most 20 per minute", async () => {
    const t = convexTest(schema, modules);
    const { seller, requestId } = await setup(t);
    await expect(t.mutation(api.messaging.sendMessage, { sessionToken: seller.token, requestId, body: "   " })).rejects.toThrow(/Write a message/);
    await expect(t.mutation(api.messaging.sendMessage, { sessionToken: seller.token, requestId, body: "x".repeat(2001) })).rejects.toThrow(/2000/);
    for (let i = 0; i < 20; i++) await t.mutation(api.messaging.sendMessage, { sessionToken: seller.token, requestId, body: `m${i}` });
    await expect(t.mutation(api.messaging.sendMessage, { sessionToken: seller.token, requestId, body: "one more" })).rejects.toThrow(/too quickly/);
  });

  test("nobody can send an inquiry about their own listing", async () => {
    const t = convexTest(schema, modules);
    const seller = await makeUser(t, "Seller", "agent", { roleApprovedAt: Date.now() });
    const listingId = await listing(t, seller.id);
    await expect(
      t.mutation(api.adminPortal.submitContactRequest, { sessionToken: seller.token, buyerId: seller.id, listingId, listingType: "property", message: "hi" })
    ).rejects.toThrow(/your own listing/);
  });
});

describe("followers", () => {
  test("following someone notifies them; unfollowing does not", async () => {
    const t = convexTest(schema, modules);
    const agent = await makeUser(t, "Agent", "agent");
    const fan = await makeUser(t, "Fan");
    await t.mutation(api.social.toggleFollow, { sessionToken: fan.token, currentUserId: fan.id, targetUserId: agent.id });
    await t.mutation(api.social.toggleFollow, { sessionToken: fan.token, currentUserId: fan.id, targetUserId: agent.id });
    const notes = await notificationsOf(t, agent.id);
    expect(notes).toHaveLength(1);
    expect(notes[0]).toMatchObject({ title: "New follower", body: "Fan started following you." });
  });
});

describe("property media", () => {
  async function owner(t: T) {
    return makeUser(t, "Owner", "property_owner", { roleApprovedAt: Date.now() });
  }
  const base = (o: U) => ({
    ownerId: o.id as string, sessionToken: o.token, title: "Hill House", description: "A family home", category: "sale" as const,
    price: 320000, address: SECRET_STREET, city: "Freetown", district: "Western Area Urban", privateContactPhone: SECRET_PHONE,
  });

  test("photos and videos are stored as public media; the private address and phone are not", async () => {
    const t = convexTest(schema, modules);
    const o = await owner(t);
    const imageId = await t.run(async (ctx) => ctx.storage.store(new Blob(["img"], { type: "image/jpeg" })));
    const videoId = await t.run(async (ctx) => ctx.storage.store(new Blob(["vid"], { type: "video/mp4" })));
    const id = await t.mutation(api.realEstate.createPropertyListing, { ...base(o), imageStorageIds: [imageId], videoStorageIds: [videoId] });
    const pub: any = await t.query(api.realEstate.getPropertyById, { listingId: id });
    expect(pub.imageUrls).toHaveLength(1);
    expect(pub.videoUrls).toHaveLength(1);
    expect(typeof pub.videoUrls[0]).toBe("string");
    const text = JSON.stringify(pub);
    expect(text).not.toContain(SECRET_STREET);
    expect(text).not.toContain(SECRET_PHONE);
  });

  test("media that never finished uploading is refused, not stored as a fake path", async () => {
    const t = convexTest(schema, modules);
    const o = await owner(t);
    await expect(
      t.mutation(api.realEstate.createPropertyListing, { ...base(o), imageStorageIds: ["local_media_123"] })
    ).rejects.toThrow(/did not finish uploading/);
    await expect(
      t.mutation(api.realEstate.createPropertyListing, { ...base(o), imageStorageIds: [], videoStorageIds: ["local_video_1"] })
    ).rejects.toThrow(/did not finish uploading/);
  });

  test("at most 3 videos per listing", async () => {
    const t = convexTest(schema, modules);
    const o = await owner(t);
    const ids = await t.run(async (ctx) =>
      Promise.all([1, 2, 3, 4].map((i) => ctx.storage.store(new Blob([`v${i}`], { type: "video/mp4" }))))
    );
    await expect(
      t.mutation(api.realEstate.createPropertyListing, { ...base(o), imageStorageIds: [], videoStorageIds: ids })
    ).rejects.toThrow(/at most 3 videos/);
  });
});
