/// <reference types="vite/client" />
// Hotel / guest-house verification: three independent server-side conditions (approved role,
// admin-verified property, active PAID subscription) gate public listing, rooms, bookings and payouts.

import { convexTest } from "convex-test";
import { afterEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { hashWalletPin } from "./lib/pin";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string };
const DAY = 24 * 3600 * 1000;
const PIN = "1234";
let seq = 0;

afterEach(() => vi.useRealTimers());

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", { email: `${name}${seq}@t.vx`, phone: `+2327200${1000 + seq}`, name, role: role as any, isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra } as any)
  );
  await t.run(async (ctx) => ctx.db.patch(id, { walletPinHash: await hashWalletPin(id, PIN) }));
  return { id, token };
}
const fund = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount, provider: "TEST", providerReference: `f-${userId}-${seq++}` });
const wallet = async (t: T, userId: Id<"users">) =>
  (await t.run(async (ctx) => (await ctx.db.query("walletBalances").collect()).find((w) => w.userId === userId))) ??
  ({ availableBalance: 0, escrowBalance: 0, pendingBalance: 0 } as { availableBalance: number; escrowBalance?: number; pendingBalance: number });

const profileArgs = (u: U) => ({
  sessionToken: u.token, userId: u.id, businessName: "Palm Guest House", operationalType: "guest_house" as const, address: "12 Hill Street", city: "Freetown",
  phone: "+23276000000", description: "d", amenities: [], supportsHourlyStays: false, tinNumber: "TIN123456", commercialLicenseUrl: "private/licence.pdf",
});
const roomArgs = (u: U, hotelId: Id<"hotel_profiles">) => ({
  sessionToken: u.token, hotelId, name: "R1", roomType: "Standard" as const, pricePerNight: 1000, supportsHourly: false, capacityGuests: 2, bedConfiguration: "1", amenities: [], images: [], totalRoomUnits: 1,
});
const hotelDoc = (t: T, id: Id<"hotel_profiles">) => t.run(async (ctx) => ctx.db.get(id)) as Promise<any>;
const review = (t: T, who: U, hotelId: Id<"hotel_profiles">, decision: "approve" | "reject" | "suspend" | "reinstate", note?: string) =>
  t.mutation(api.hotelVerification.adminReviewHotel, { sessionToken: who.token, hotelId, decision, note }) as Promise<any>;

/** Everyone, a plan, and a SUBMITTED (pending) hotel. The owner's role is admin-approved. */
async function setup(t: T) {
  const admin = await makeUser(t, "admin", "admin");
  const owner = await makeUser(t, "owner", "hotel_operator", { roleApprovedAt: Date.now() });
  const guest = await makeUser(t, "guest");
  await t.mutation(api.subscriptions.adminUpsertPlan, {
    sessionToken: admin.token, tierCode: "HOTEL_M", name: "Hotel Monthly", roleTarget: "hotel_operator", basePrice: 150, currency: "SLE",
    billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
  });
  const created: any = await t.mutation(api.hotels.createHotelProfile, profileArgs(owner));
  const hotelId = created.hotelId as Id<"hotel_profiles">;
  /** pays the subscription through the real, server-verified wallet path */
  const subscribe = async () => {
    await fund(t, owner.id, 500);
    await t.mutation(api.subscriptions.subscribeWithWallet, { sessionToken: owner.token, tierCode: "HOTEL_M", pin: PIN, idempotencyKey: `hotel-sub-${seq++}-0123456789abcdef` });
  };
  /** a room added directly (as data), so bookings can be tested independently of room permissions */
  const addRoomData = (price = 1000) =>
    t.run(async (ctx) =>
      ctx.db.insert("hotel_rooms", { hotelId, name: "R", roomType: "Standard", pricePerNight: price, supportsHourly: false, capacityGuests: 2, bedConfiguration: "1", amenities: [], images: [], isAvailable: true, totalRoomUnits: 1, createdAt: Date.now(), updatedAt: Date.now() } as any)
    );
  const book = async (roomId: Id<"hotel_rooms">, offsetDays = 1) =>
    (await t.mutation(api.hotelBookings.createBookingWithEscrow, {
      sessionToken: guest.token, hotelId, roomId, guestName: "G", guestPhone: "+23276111111", bookingCategory: "nightly",
      checkInTimestamp: Date.now() + offsetDays * DAY, checkOutTimestamp: Date.now() + (offsetDays + 1) * DAY, numberOfGuests: 1, numberOfNights: 1,
    })) as any;
  return { admin, owner, guest, hotelId, subscribe, addRoomData, book };
}

// ─────────────────────────────────────────────────────────────────────
describe("becoming a hotel operator and submitting a hotel", () => {
  test("a user cannot self-upgrade to hotel operator, and a self-declared role without admin approval cannot submit", async () => {
    const t = convexTest(schema, modules);
    const client = await makeUser(t, "client");
    await expect(t.mutation(api.hotels.createHotelProfile, profileArgs(client))).rejects.toThrow(/approved Hotel/i);
    expect(((await t.run(async (ctx) => ctx.db.get(client.id))) as any).role).toBe("client"); // not upgraded
    // the role string alone (as registration/social sign-in can never grant it) is not an approval
    const selfDeclared = await makeUser(t, "selfdeclared", "hotel_operator");
    await expect(t.mutation(api.hotels.createHotelProfile, profileArgs(selfDeclared))).rejects.toThrow(/approved Hotel/i);
    expect(await t.run(async (ctx) => (await ctx.db.query("hotel_profiles").collect()).length)).toBe(0);
  });

  test("an approved owner's submission enters an explicit PENDING state, with a history entry and no invented dates", async () => {
    const t = convexTest(schema, modules);
    const { hotelId, owner } = await setup(t);
    const h = await hotelDoc(t, hotelId);
    expect(h).toMatchObject({ verificationStatus: "pending", isVerified: false });
    expect(h.submittedAt).toBeTypeOf("number");
    expect(h.verifiedAt).toBeUndefined();
    expect(h.reviewedAt).toBeUndefined();
    const events = await t.run(async (ctx) => ctx.db.query("hotel_verification_events").collect());
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ action: "SUBMITTED", toStatus: "pending", actorRole: "owner", actorId: owner.id });
    // only one hotel per account
    await expect(t.mutation(api.hotels.createHotelProfile, profileArgs(owner))).rejects.toThrow(/already exists/i);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("an unverified (pending) hotel can do nothing public", () => {
  test("not listed, no public details, cannot add rooms, cannot accept a booking, cannot pull a payout", async () => {
    const t = convexTest(schema, modules);
    const { owner, guest, hotelId, subscribe, addRoomData, book } = await setup(t);
    await subscribe(); // even with a PAID subscription, verification is a separate requirement
    expect(await t.query(api.hotels.getHotels, {})).toHaveLength(0);
    expect(await t.query(api.hotels.getHotelDetails, { hotelId })).toBeNull();
    await expect(t.mutation(api.hotels.addRoom, roomArgs(owner, hotelId))).rejects.toThrow(/awaiting verification/i);
    const roomId = await addRoomData();
    await fund(t, guest.id, 5000);
    await expect(book(roomId)).rejects.toThrow(/cannot take bookings.*awaiting verification/i);
    expect((await wallet(t, guest.id)).escrowBalance ?? 0).toBe(0);
    expect(await t.run(async (ctx) => (await ctx.db.query("hotel_bookings").collect()).length)).toBe(0);
  });

  test("the owner's dashboard still shows their pending application", async () => {
    const t = convexTest(schema, modules);
    const { owner } = await setup(t);
    const d: any = await t.query(api.hotels.getOperatorDashboardData, { sessionToken: owner.token, userId: owner.id });
    expect(d.hotel.verificationStatus).toBe("pending");
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("admin review", () => {
  test("only an admin can list or decide; operators and clients cannot approve", async () => {
    const t = convexTest(schema, modules);
    const { owner, guest, hotelId } = await setup(t);
    for (const who of [owner, guest]) {
      await expect(review(t, who, hotelId, "approve")).rejects.toThrow(/administrator/i);
      await expect(t.query(api.hotelVerification.adminListHotelApplications, { sessionToken: who.token })).rejects.toThrow(/administrator/i);
    }
    expect((await hotelDoc(t, hotelId)).verificationStatus).toBe("pending");
  });

  test("the pending list shows reviewer info without private extras; TIN masked, no licence URL or coordinates", async () => {
    const t = convexTest(schema, modules);
    const { admin, hotelId } = await setup(t);
    const rows: any[] = await t.query(api.hotelVerification.adminListHotelApplications, { sessionToken: admin.token });
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      id: hotelId, businessName: "Palm Guest House", status: "pending", hasCommercialLicense: true, tinMasked: "••••••456",
      operator: { name: "owner", roleApproved: true, hasActiveSubscription: false },
    });
    const text = JSON.stringify(rows[0]);
    expect(text).not.toContain("TIN123456");
    expect(text).not.toContain("licence.pdf");
    expect(text).not.toMatch(/latitude|longitude|sessionToken|passwordHash/);
  });

  test("approval records actor, time, event and audit; it does NOT start a subscription; a repeat is refused", async () => {
    const t = convexTest(schema, modules);
    const { admin, owner, hotelId } = await setup(t);
    const before = Date.now();
    expect(await review(t, admin, hotelId, "approve", "documents checked")).toMatchObject({ status: "verified" });
    const h = await hotelDoc(t, hotelId);
    expect(h).toMatchObject({ verificationStatus: "verified", isVerified: true, reviewedBy: admin.id, reviewNote: "documents checked" });
    expect(h.verifiedAt).toBeGreaterThanOrEqual(before);

    const events = await t.run(async (ctx) => ctx.db.query("hotel_verification_events").collect());
    expect(events.map((e) => [e.action, e.fromStatus, e.toStatus])).toEqual([["SUBMITTED", undefined, "pending"], ["APPROVED", "pending", "verified"]]);
    expect(events[1]).toMatchObject({ actorId: admin.id, actorRole: "admin", note: "documents checked" });
    const audits = await t.run(async (ctx) => (await ctx.db.query("audit_logs").collect()).filter((a) => a.action === "VERIFICATION_DECISION"));
    expect(audits).toHaveLength(1);
    expect(JSON.parse(audits[0].snapshot)).toMatchObject({ kind: "hotel", decision: "approve", from: "pending", to: "verified" });
    expect(audits[0].adminUserId).toBe(admin.id);

    // approval alone activates no subscription
    expect(await t.run(async (ctx) => (await ctx.db.query("vendor_subscriptions").collect()).length)).toBe(0);
    const note = await t.run(async (ctx) => (await ctx.db.query("user_notifications").collect()).filter((n) => n.userId === (owner.id as string)));
    expect(note.some((n) => /approved/i.test(n.title))).toBe(true);

    // duplicate approval: refused, and nothing extra is recorded
    await expect(review(t, admin, hotelId, "approve")).rejects.toThrow(/already verified/i);
    expect(await t.run(async (ctx) => (await ctx.db.query("hotel_verification_events").collect()).length)).toBe(2);
    expect(await t.run(async (ctx) => (await ctx.db.query("audit_logs").collect()).filter((a) => a.action === "VERIFICATION_DECISION").length)).toBe(1);
  });

  test("rejection needs a reason, works, is audited, blocks everything, and the owner can resubmit (explicit pending again)", async () => {
    const t = convexTest(schema, modules);
    const { admin, owner, guest, hotelId, subscribe, addRoomData, book } = await setup(t);
    await subscribe();
    await expect(review(t, admin, hotelId, "reject")).rejects.toThrow(/note/i);
    await expect(review(t, admin, hotelId, "reject", "no")).rejects.toThrow(/note/i);
    await review(t, admin, hotelId, "reject", "licence is expired");
    const h = await hotelDoc(t, hotelId);
    expect(h).toMatchObject({ verificationStatus: "rejected", isVerified: false, reviewNote: "licence is expired" });
    expect(h.verifiedAt).toBeUndefined();
    // a rejected hotel is not listed, takes no rooms, no bookings
    expect(await t.query(api.hotels.getHotels, {})).toHaveLength(0);
    await expect(t.mutation(api.hotels.addRoom, roomArgs(owner, hotelId))).rejects.toThrow(/rejected/i);
    await fund(t, guest.id, 5000);
    await expect(book(await addRoomData())).rejects.toThrow(/rejected/i);
    // it cannot be approved straight from rejected, only after a resubmission
    await expect(review(t, admin, hotelId, "approve")).rejects.toThrow(/Cannot approve.*rejected/i);
    await expect(t.mutation(api.hotelVerification.resubmitHotelApplication, { sessionToken: guest.token, hotelId })).rejects.toThrow(/permission/i);
    await t.mutation(api.hotelVerification.resubmitHotelApplication, { sessionToken: owner.token, hotelId, note: "new licence attached" });
    expect(await hotelDoc(t, hotelId)).toMatchObject({ verificationStatus: "pending", isVerified: false });
    await expect(t.mutation(api.hotelVerification.resubmitHotelApplication, { sessionToken: owner.token, hotelId })).rejects.toThrow(/Only a rejected/i);
    await review(t, admin, hotelId, "approve");
    const trail = (await t.run(async (ctx) => ctx.db.query("hotel_verification_events").collect())).map((e) => e.action);
    expect(trail).toEqual(["SUBMITTED", "REJECTED", "RESUBMITTED", "APPROVED"]);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("verified, and the subscription is a separate requirement", () => {
  test("verified but UNSUBSCRIBED: listed publicly, but no rooms and no bookings", async () => {
    const t = convexTest(schema, modules);
    const { admin, owner, guest, hotelId, addRoomData, book } = await setup(t);
    await review(t, admin, hotelId, "approve");
    expect(await t.query(api.hotels.getHotels, {})).toHaveLength(1); // verification makes it visible
    await expect(t.mutation(api.hotels.addRoom, roomArgs(owner, hotelId))).rejects.toThrow(/subscription is not active/i);
    await fund(t, guest.id, 5000);
    await expect(book(await addRoomData())).rejects.toThrow(/subscription is not active/i);
    expect((await wallet(t, guest.id)).escrowBalance ?? 0).toBe(0);
  });

  test("verified + ACTIVE paid subscription: can add rooms, appears with rooms, accepts a booking (money held, not paid out)", async () => {
    const t = convexTest(schema, modules);
    const { admin, owner, guest, hotelId, subscribe, book } = await setup(t);
    await review(t, admin, hotelId, "approve");
    await subscribe();
    const added: any = await t.mutation(api.hotels.addRoom, roomArgs(owner, hotelId));
    const details: any = await t.query(api.hotels.getHotelDetails, { hotelId });
    expect(details.rooms).toHaveLength(1);
    expect(details.hotel.address).toBe("Inside Freetown, Sierra Leone"); // generalised, never the street
    await fund(t, guest.id, 5000);
    const ownerBefore = (await wallet(t, owner.id)).availableBalance; // what is left after paying the subscription
    const res = await book(added.roomId);
    expect(res.status).toBe("in_escrow");
    expect((await wallet(t, guest.id)).escrowBalance).toBe(1000);
    expect((await wallet(t, owner.id)).availableBalance).toBe(ownerBefore); // paid out only on release
  });

  test("an expired subscription stops new rooms and bookings again", async () => {
    const t = convexTest(schema, modules);
    const { admin, owner, guest, hotelId, subscribe, addRoomData, book } = await setup(t);
    await review(t, admin, hotelId, "approve");
    await subscribe();
    await t.run(async (ctx) => {
      for (const s of await ctx.db.query("vendor_subscriptions").collect()) await ctx.db.patch(s._id, { expiryDate: Date.now() - 1 });
    });
    await expect(t.mutation(api.hotels.addRoom, roomArgs(owner, hotelId))).rejects.toThrow(/subscription is not active/i);
    await fund(t, guest.id, 5000);
    await expect(book(await addRoomData())).rejects.toThrow(/subscription is not active/i);
  });

  test("the operator's role approval is also required (a revoked role stops bookings)", async () => {
    const t = convexTest(schema, modules);
    const { admin, owner, guest, hotelId, subscribe, addRoomData, book } = await setup(t);
    await review(t, admin, hotelId, "approve");
    await subscribe();
    await t.run(async (ctx) => ctx.db.patch(owner.id, { role: "client" as any }));
    await fund(t, guest.id, 5000);
    await expect(book(await addRoomData())).rejects.toThrow(/cannot take bookings/i);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("suspension", () => {
  test("a suspended hotel is delisted and takes no new bookings; an escrowed booking can't be pulled by the operator", async () => {
    const t = convexTest(schema, modules);
    const { admin, owner, guest, hotelId, subscribe, addRoomData, book } = await setup(t);
    await review(t, admin, hotelId, "approve");
    await subscribe();
    const roomId = await addRoomData();
    await fund(t, guest.id, 5000);
    const first = await book(roomId, 1);
    const ownerBefore = (await wallet(t, owner.id)).availableBalance;

    await expect(review(t, admin, hotelId, "suspend")).rejects.toThrow(/note/i);
    await review(t, admin, hotelId, "suspend", "complaints under investigation");
    expect(await hotelDoc(t, hotelId)).toMatchObject({ verificationStatus: "suspended", isVerified: false });
    expect(await t.query(api.hotels.getHotels, {})).toHaveLength(0);
    await expect(book(roomId, 5)).rejects.toThrow(/suspended/i);
    await expect(t.mutation(api.hotels.addRoom, roomArgs(owner, hotelId))).rejects.toThrow(/suspended/i);

    // the guest's money is safe: the operator cannot pull the payout, even long after check-out
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(Date.now() + 10 * DAY));
    await expect(t.mutation(api.hotelBookings.releaseEscrowPayout, { sessionToken: owner.token, bookingId: first.bookingId })).rejects.toThrow(/not eligible/i);
    expect((await wallet(t, owner.id)).availableBalance).toBe(ownerBefore);
    // the guest (or an admin) still decides
    await t.mutation(api.hotelBookings.releaseEscrowPayout, { sessionToken: guest.token, bookingId: first.bookingId });
    expect((await wallet(t, owner.id)).availableBalance).toBe(ownerBefore + 900);
    vi.useRealTimers();

    // reinstating restores verification (and nothing else)
    await expect(review(t, admin, hotelId, "reinstate")).rejects.toThrow(/note/i);
    await review(t, admin, hotelId, "reinstate", "investigation closed");
    expect(await hotelDoc(t, hotelId)).toMatchObject({ verificationStatus: "verified", isVerified: true });
    await expect(review(t, admin, hotelId, "suspend", "x")).rejects.toThrow(/note/i);
    const trail = (await t.run(async (ctx) => ctx.db.query("hotel_verification_events").collect())).map((e) => e.action);
    expect(trail).toEqual(["SUBMITTED", "APPROVED", "SUSPENDED", "REINSTATED"]);
  });

  test("only a verified property can be suspended, and only a suspended one reinstated", async () => {
    const t = convexTest(schema, modules);
    const { admin, hotelId } = await setup(t);
    await expect(review(t, admin, hotelId, "suspend", "not even verified")).rejects.toThrow(/Cannot suspend.*pending/i);
    await expect(review(t, admin, hotelId, "reinstate", "not suspended")).rejects.toThrow(/Cannot reinstate.*pending/i);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("existing hotels are never auto-verified", () => {
  test("legacy rows stay unverified and unlisted, appear for review, and get a date only when an admin approves", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "oldowner", "hotel_operator");
    const legacy = await t.run(async (ctx) => {
      // pre-existing data: flagged verified but never reviewed through the new workflow
      const a = await ctx.db.insert("hotel_profiles", {
        userId: owner.id, businessName: "Old Hotel", operationalType: "hotel", isVerified: true, verificationStatus: "pending", address: "a", city: "Bo",
        phone: "+23276000001", amenities: [], mediaUrls: [], description: "d", supportsHourlyStays: false, updatedAt: Date.now(),
      } as any);
      return a;
    });
    // inconsistent flags (isVerified without an approved status) do not make it public
    expect(await t.query(api.hotels.getHotels, {})).toHaveLength(0);
    expect(await t.query(api.hotels.getHotelDetails, { hotelId: legacy })).toBeNull();
    const pending: any[] = await t.query(api.hotelVerification.adminListHotelApplications, { sessionToken: admin.token });
    expect(pending.map((p) => p.id)).toEqual([legacy]);
    expect(pending[0].verifiedAt).toBeNull();
    expect(pending[0].submittedAt).toBeNull(); // no invented date
    await review(t, admin, legacy, "approve", "reviewed");
    expect((await hotelDoc(t, legacy)).verifiedAt).toBeTypeOf("number");
    expect(await t.query(api.hotels.getHotels, {})).toHaveLength(1);
  });

  test("a row marked 'verified' without the flag is treated as pending review (and can be approved)", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "oldowner", "hotel_operator");
    const id = await t.run(async (ctx) =>
      ctx.db.insert("hotel_profiles", {
        userId: owner.id, businessName: "Odd", operationalType: "hotel", isVerified: false, verificationStatus: "verified", address: "a", city: "Bo",
        phone: "+23276000001", amenities: [], mediaUrls: [], description: "d", supportsHourlyStays: false, updatedAt: Date.now(),
      } as any)
    );
    expect(await t.query(api.hotels.getHotels, {})).toHaveLength(0);
    expect(((await t.query(api.hotelVerification.adminListHotelApplications, { sessionToken: admin.token })) as any[]).map((p) => p.id)).toEqual([id]);
    await review(t, admin, id, "approve");
    expect(await hotelDoc(t, id)).toMatchObject({ verificationStatus: "verified", isVerified: true });
  });
});
