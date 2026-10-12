/// <reference types="vite/client" />
// Completion of scheduled account deletion: erasure, retention, safety, idempotence.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
const PASSWORD = "Correct-Horse-9";
const DAY = 86_400_000;
let seq = 0;

async function makeUser(t: T, label: string) {
  const n = ++seq;
  const r: any = await t.mutation(api.auth.registerUser, {
    name: `Person ${label}`, email: `${label}${n}@test.vektolux`, phone: `+2327630${String(n).padStart(4, "0")}`,
    password: PASSWORD, role: "client",
  });
  expect(r.success).toBe(true);
  return { id: r.userId as Id<"users">, email: `${label}${n}@test.vektolux` };
}

/** Marks the account deletion-pending and signed out, as requestAccountDeletion does. */
async function schedule(t: T, id: Id<"users">, scheduledFor: number) {
  await t.run(async (ctx) =>
    ctx.db.patch(id, {
      deletionRequestedAt: scheduledFor - 30 * DAY, deletionScheduledFor: scheduledFor,
      sessionToken: undefined, sessionExpiresAt: undefined,
      bio: "my bio", address: "1 Main St", region: "Western", avatarUrl: "https://x/y.png",
      pinFailedAttempts: 1,
    } as any)
  );
}

async function seedPersonalData(t: T, id: Id<"users">, email: string) {
  await t.run(async (ctx) => {
    await ctx.db.insert("auth_identities", { userId: id, provider: "google", subject: `s-${id}`, linkedAt: 1 });
    await ctx.db.insert("user_fcm_tokens", { userId: id as string, fcmToken: `tok-${id}`, deviceType: "android", lastUpdated: 1 });
    await ctx.db.insert("saved_listings", { userId: id, listingType: "property", listingId: "abc", createdAt: 1 });
    await ctx.db.insert("password_resets", {
      identifier: email, deliveryChannel: "email", otpCode: "h1:x", expiresAt: 1, isUsed: false, createdAt: 1,
    });
    await ctx.db.insert("user_notifications", {
      userId: id as string, targetType: "single_user", title: "t", body: "b", read: false, createdAt: 1,
    });
  });
}

const count = (t: T, table: any) => t.run(async (ctx) => (await ctx.db.query(table).collect()).length);

describe("processDueDeletions", () => {
  test("anonymises a due account, removes personal rows, keeps ledger/financial references", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "due");
    await seedPersonalData(t, u.id, u.email);
    const now = Date.now();
    await schedule(t, u.id, now - 1000);
    const res = await t.mutation(internal.accountDeletion.processDueDeletions, { now });
    expect(res.processed).toBe(1);

    const user: any = await t.run(async (ctx) => ctx.db.get(u.id));
    expect(user).not.toBeNull(); // row kept so every reference stays valid
    expect(user.anonymizedAt).toBe(now);
    expect(user.isActive).toBe(false);
    expect(user.name).toBe("Deleted user");
    expect(user.email).toBe(`deleted-${u.id}@users.vektolux.invalid`);
    expect(user.phone).toBe("");
    for (const f of ["bio", "address", "region", "avatarUrl", "passwordHash", "sessionToken", "walletPinHash"]) {
      expect(user[f]).toBeUndefined();
    }
    expect(JSON.stringify(user)).not.toContain(u.email);

    expect(await count(t, "auth_identities")).toBe(0);
    expect(await count(t, "user_fcm_tokens")).toBe(0);
    expect(await count(t, "saved_listings")).toBe(0);
    expect(await count(t, "password_resets")).toBe(0);
    expect(await count(t, "user_notifications")).toBe(0);
    // Wallet record (financial) is retained.
    expect(await count(t, "walletBalances")).toBe(1);

    const events: any[] = await t.run(async (ctx) => ctx.db.query("account_deletion_events").collect());
    expect(events).toHaveLength(1);
    expect(events[0].userId).toBe(u.id);
    expect(JSON.stringify(events[0])).not.toContain(u.email);
  });

  test("the erased account can no longer sign in", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "gone");
    const now = Date.now();
    await schedule(t, u.id, now - 1);
    await t.mutation(internal.accountDeletion.processDueDeletions, { now });
    const r: any = await t.mutation(api.auth.loginWithPhoneOrEmail, { identifier: u.email, password: PASSWORD });
    expect(r.success).toBe(false);
  });

  test("not-yet-due, cancelled (never scheduled) and unrelated accounts are untouched", async () => {
    const t = convexTest(schema, modules);
    const notDue = await makeUser(t, "later");
    const cancelled = await makeUser(t, "cancelled"); // signing in cleared the schedule
    const other = await makeUser(t, "other");
    const now = Date.now();
    await schedule(t, notDue.id, now + 5 * DAY);
    await seedPersonalData(t, other.id, other.email);

    const res = await t.mutation(internal.accountDeletion.processDueDeletions, { now });
    expect(res.processed).toBe(0);
    for (const x of [notDue, cancelled, other]) {
      const d: any = await t.run(async (ctx) => ctx.db.get(x.id));
      expect(d.anonymizedAt).toBeUndefined();
      expect(d.email).toBe(x.email);
    }
    expect(await count(t, "auth_identities")).toBe(1);
  });

  test("an account that still holds funds is deferred, not erased", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "funds");
    const now = Date.now();
    await schedule(t, u.id, now - 1);
    await t.run(async (ctx) => {
      const w = await ctx.db.query("walletBalances").withIndex("by_user", (q) => q.eq("userId", u.id)).first();
      await ctx.db.patch(w!._id, { availableBalance: 50 });
    });
    const res = await t.mutation(internal.accountDeletion.processDueDeletions, { now });
    expect(res.processed).toBe(0);
    expect(res.deferred).toEqual([{ userId: u.id, reason: "FUNDS_REMAINING" }]);
    const d: any = await t.run(async (ctx) => ctx.db.get(u.id));
    expect(d.email).toBe(u.email);
    expect(d.deletionScheduledFor).toBeDefined(); // still scheduled; re-checked next run
  });

  test("admin accounts are never auto-erased", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "adm");
    const now = Date.now();
    await schedule(t, u.id, now - 1);
    await t.run(async (ctx) => ctx.db.patch(u.id, { role: "admin" } as any));
    const res = await t.mutation(internal.accountDeletion.processDueDeletions, { now });
    expect(res.processed).toBe(0);
    expect(res.deferred[0].reason).toBe("ADMIN_ACCOUNT");
  });

  test("a live session blocks erasure (user came back)", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "back");
    const now = Date.now();
    await schedule(t, u.id, now - 1);
    await t.run(async (ctx) => ctx.db.patch(u.id, { sessionToken: "live", sessionExpiresAt: now + DAY }));
    const res = await t.mutation(internal.accountDeletion.processDueDeletions, { now });
    expect(res.processed).toBe(0);
    expect(res.deferred[0].reason).toBe("ACTIVE_SESSION");
  });

  test("an open booking blocks erasure", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "booker");
    const now = Date.now();
    await schedule(t, u.id, now - 1);
    await t.run(async (ctx) =>
      ctx.db.insert("bookings", {
        listingId: "l", listingType: "property", listingTitle: "T", buyerId: u.id as string, vendorId: "someone",
        bookingType: "vehicle_rental", status: "confirmed", startTime: 1, endTime: 2, subtotal: 1, serviceFee: 0,
        totalAmount: 1, currency: "SLE", paymentStatus: "completed", updatedAt: 1,
      } as any)
    );
    const res = await t.mutation(internal.accountDeletion.processDueDeletions, { now });
    expect(res.deferred[0].reason).toBe("BOOKING_OPEN");
  });

  test("idempotent: a second run (retry) does nothing and does not duplicate the audit row", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "twice");
    const now = Date.now();
    await schedule(t, u.id, now - 1);
    const a = await t.mutation(internal.accountDeletion.processDueDeletions, { now });
    const b = await t.mutation(internal.accountDeletion.processDueDeletions, { now: now + 1000 });
    expect(a.processed).toBe(1);
    expect(b.processed).toBe(0);
    expect(await count(t, "account_deletion_events")).toBe(1);
  });

  test("request -> cancel by sign-in -> not processed", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "regret");
    const req: any = await t.mutation(api.users.requestAccountDeletion, {
      sessionToken: (await t.mutation(api.auth.loginWithPhoneOrEmail, { identifier: u.email, password: PASSWORD }) as any).sessionToken,
    });
    expect(req.success).toBe(true);
    const back: any = await t.mutation(api.auth.loginWithPhoneOrEmail, { identifier: u.email, password: PASSWORD });
    expect(back.success).toBe(true);
    const res = await t.mutation(internal.accountDeletion.processDueDeletions, { now: Date.now() + 40 * DAY });
    expect(res.processed).toBe(0);
  });
});

// ─── obligations beyond wallet / withdrawals / vehicle escrow / bookings ─────────────────────────
describe("processDueDeletions: extended obligation audit", () => {
  const NOW = () => Date.now();

  async function dueUser(t: T, label: string) {
    const u = await makeUser(t, label);
    await schedule(t, u.id, NOW() - 1);
    return u;
  }
  async function listingFor(t: T, ownerId: Id<"users">, extra: Record<string, unknown> = {}) {
    return await t.run(async (ctx) =>
      ctx.db.insert("realEstateListings", {
        ownerId, title: "House", description: "d", category: "hourly_guesthouse", price: 0, hourlyRate: 10,
        currency: "SLE", address: "a", city: "Freetown", country: "SL", latitude: 8.4, longitude: -13.2, geohash: "abc",
        imageUrls: [], availabilityStatus: "available", isFeatured: false, viewCount: 0, updatedAt: Date.now(),
        isPublished: true, privateContactPhone: "+23276999999", ...extra,
      } as any)
    );
  }
  async function contract(t: T, clientId: Id<"users">, beneficiaryId: Id<"users">, listingId: any, state: string) {
    return await t.run(async (ctx) =>
      ctx.db.insert("re_escrow_contracts", {
        contractCode: `C-${Math.random()}`, contractType: "SHORT_STAY_BOOKING", propertyListingId: listingId,
        clientId, beneficiaryId, grossAmount: 100, cautionDepositAmount: 10, platformFeeAmount: 5, agentCommissionAmount: 0,
        netBeneficiaryExpected: 95, releasedBeneficiaryAmount: 0, refundedClientAmount: 0, paymentRail: "WALLET",
        currentState: state, createdAt: Date.now(), updatedAt: Date.now(),
      } as any)
    );
  }
  const deferredReason = async (t: T) => {
    const r = await t.mutation(internal.accountDeletion.processDueDeletions, { now: NOW() });
    return r.deferred.map((d: any) => d.reason);
  };
  const stillIntact = async (t: T, u: { id: Id<"users">; email: string }) => {
    const d: any = await t.run(async (ctx) => ctx.db.get(u.id));
    expect(d.anonymizedAt).toBeUndefined();
    expect(d.email).toBe(u.email);
  };

  test("an unsettled real-estate escrow contract blocks erasure (as client and as beneficiary)", async () => {
    const t = convexTest(schema, modules);
    const client = await dueUser(t, "reclient");
    const owner = await makeUser(t, "reowner");
    const listing = await listingFor(t, owner.id);
    await contract(t, client.id, owner.id, listing, "FUNDS_LOCKED");
    expect(await deferredReason(t)).toEqual(["RE_ESCROW_OPEN"]);
    await stillIntact(t, client);

    const t2 = convexTest(schema, modules);
    const ben = await dueUser(t2, "rebeneficiary");
    const c2 = await makeUser(t2, "reclient2");
    await contract(t2, c2.id, ben.id, await listingFor(t2, ben.id), "UNDER_ARBITRATION");
    expect(await deferredReason(t2)).toEqual(["RE_ESCROW_OPEN"]);
  });

  test("a settled contract with a still-locked caution deposit blocks erasure", async () => {
    const t = convexTest(schema, modules);
    const client = await dueUser(t, "caution");
    const owner = await makeUser(t, "cautionowner");
    const id = await contract(t, client.id, owner.id, await listingFor(t, owner.id), "FULLY_SETTLED");
    await t.run(async (ctx) =>
      ctx.db.insert("re_caution_deposits", {
        contractId: id, originalDepositAmount: 10, heldAmount: 10, deductionClaimAmount: 0, refundedAmount: 0,
        status: "LOCKED", inventoryChecklistSigned: false, createdAt: Date.now(),
      } as any)
    );
    expect(await deferredReason(t)).toEqual(["CAUTION_DEPOSIT_OPEN"]);
    await stillIntact(t, client);
  });

  test("a settled contract with an open dispute blocks erasure", async () => {
    const t = convexTest(schema, modules);
    const client = await dueUser(t, "redispute");
    const owner = await makeUser(t, "redisputeowner");
    const id = await contract(t, client.id, owner.id, await listingFor(t, owner.id), "FULLY_SETTLED");
    await t.run(async (ctx) =>
      ctx.db.insert("re_escrow_disputes", {
        contractId: id, openedByUserId: client.id, claimantRole: "client", reason: "r", claimedRepairCost: 0,
        evidenceMediaUrls: [], status: "OPENED", openedAt: Date.now(),
      } as any)
    );
    expect(await deferredReason(t)).toEqual(["RE_DISPUTE_OPEN"]);
  });

  test("an unfinished inspection pass blocks erasure", async () => {
    const t = convexTest(schema, modules);
    const client = await dueUser(t, "pass");
    const agent = await makeUser(t, "passagent");
    await t.run(async (ctx) =>
      ctx.db.insert("re_inspection_passes", {
        propertyListingId: await ctx.db.insert("realEstateListings", {
          ownerId: agent.id, title: "H", description: "d", category: "hourly_guesthouse", price: 0, currency: "SLE", address: "a",
          city: "F", country: "SL", latitude: 1, longitude: 1, geohash: "a", imageUrls: [], availabilityStatus: "available",
          isFeatured: false, viewCount: 0, updatedAt: 1,
        } as any),
        clientId: client.id, agentId: agent.id, tourFee: 1, platformFee: 0, agentNetFee: 1, qrHash: "q", otpCode: "o",
        otpExpiresAt: 1, status: "FUNDS_LOCKED", scheduledAt: 1, isAddressUnmasked: false, createdAt: 1,
      } as any)
    );
    expect(await deferredReason(t)).toEqual(["INSPECTION_PASS_OPEN"]);
  });

  test("an open hotel stay blocks erasure (guest side)", async () => {
    const t = convexTest(schema, modules);
    const guest = await dueUser(t, "guest");
    const op = await makeUser(t, "hotelop");
    await t.run(async (ctx) => {
      const hotelId = await ctx.db.insert("hotel_profiles", {
        userId: op.id, businessName: "H", operationalType: "hotel", isVerified: true, verificationStatus: "verified",
        address: "a", city: "Freetown", phone: "+23276000000", amenities: [], mediaUrls: [], description: "d",
        supportsHourlyStays: false, updatedAt: 1,
      });
      const roomId = await ctx.db.insert("hotel_rooms", {
        hotelId, name: "R", roomType: "Standard", pricePerNight: 1, supportsHourly: false, capacityGuests: 1, bedConfiguration: "1",
        amenities: [], images: [], isAvailable: true, totalRoomUnits: 1, createdAt: 1, updatedAt: 1,
      } as any);
      await ctx.db.insert("hotel_bookings", {
        bookingReference: "HB-1", hotelId, roomId, guestId: guest.id, guestName: "G", guestPhone: "1", bookingCategory: "nightly",
        checkInTimestamp: 1, checkOutTimestamp: 2, numberOfGuests: 1, subtotalAmount: 5, platformCommissionRate: 0.1,
        platformCommissionAmount: 1, operatorPayoutAmount: 4, currency: "SLE", status: "in_escrow", createdAt: 1, updatedAt: 1,
      } as any);
    });
    expect(await deferredReason(t)).toEqual(["HOTEL_BOOKING_OPEN"]);
  });

  test("an open refund-recovery case blocks erasure", async () => {
    const t = convexTest(schema, modules);
    const recipient = await dueUser(t, "recovery");
    const buyer = await makeUser(t, "recoverybuyer");
    const admin = await makeUser(t, "recoveryadmin");
    await t.run(async (ctx) => {
      const wallet = await ctx.db.query("walletBalances").withIndex("by_user", (q) => q.eq("userId", buyer.id)).first();
      const tx = await ctx.db.insert("transactions", {
        walletId: wallet!._id, userId: buyer.id, counterpartyId: recipient.id, type: "escrow_release", amount: 300,
        currency: "SLE", status: "completed", updatedAt: Date.now(),
      } as any);
      await ctx.db.insert("payment_reversals", {
        releaseTransactionId: tx, buyerId: buyer.id, recipientId: recipient.id, currency: "SLE", referenceType: "x", referenceId: "y",
        originalAmount: 300, platformFeeReversed: 0, recipientNetOwed: 300, recoveredFromRecipient: 0, platformCoveredAmount: 0,
        writtenOffAmount: 0, refundedToBuyer: 0, outstandingAmount: 300, status: "pending_recovery", withdrawalProtection: "active",
        reason: "t", createdBy: admin.id, createdAt: 1, updatedAt: 1,
      } as any);
    });
    expect(await deferredReason(t)).toEqual(["REVERSAL_RECOVERY_OPEN"]);
  });

  test("a running subscription (or one in dunning) blocks erasure; an expired one does not", async () => {
    const mk = async (t: T, userId: Id<"users">, status: string, expiryDate: number) =>
      t.run(async (ctx) => {
        const planId = await ctx.db.insert("subscription_plans", {
          name: "T", tierCode: "t", roleTarget: "agent", basePrice: 1, currency: "SLE", billingInterval: "monthly",
          intervalDays: 30, discountPercent: 0, isActive: true, features: [], createdAt: 1, updatedAt: 1,
        });
        await ctx.db.insert("vendor_subscriptions", {
          userId, planId, tierCode: "t", status: status as any, startDate: 1, expiryDate, amountPaid: 1, currency: "SLE",
          paymentReference: `ref-${status}`, paymentMethod: "wallet", autoRenew: false, createdAt: 1, updatedAt: 1,
        });
      });

    const t = convexTest(schema, modules);
    const u = await dueUser(t, "sub");
    await mk(t, u.id, "active", Date.now() + 10 * DAY);
    expect(await deferredReason(t)).toEqual(["SUBSCRIPTION_ACTIVE"]);
    await stillIntact(t, u);

    const t2 = convexTest(schema, modules);
    const d = await dueUser(t2, "dun");
    await mk(t2, d.id, "dunning", Date.now() - DAY);
    expect(await deferredReason(t2)).toEqual(["SUBSCRIPTION_ACTIVE"]);

    const t3 = convexTest(schema, modules);
    const e = await dueUser(t3, "exp");
    await mk(t3, e.id, "active", Date.now() - DAY); // ran out: not an obligation
    expect((await t3.mutation(internal.accountDeletion.processDueDeletions, { now: NOW() })).processed).toBe(1);
  });

  test("a pending or active listing-agent authorization blocks erasure (owner or agent)", async () => {
    const t = convexTest(schema, modules);
    const owner = await dueUser(t, "authowner");
    const agent = await makeUser(t, "authagent");
    const listing = await listingFor(t, owner.id);
    await t.run(async (ctx) =>
      ctx.db.insert("listing_agent_authorizations", {
        listingType: "property", listingId: listing as any, ownerId: owner.id, agentId: agent.id, status: "active",
        invitedAt: 1, acceptedAt: 2, updatedAt: 2,
      } as any)
    );
    expect(await deferredReason(t)).toEqual(["AGENT_AUTHORIZATION_ACTIVE"]);
  });

  test("with no open obligation: listings unpublished, QR cancelled, profile contact blanked, records retained", async () => {
    const t = convexTest(schema, modules);
    const u = await dueUser(t, "cleanup");
    const other = await makeUser(t, "cleanupother");
    const mine = await listingFor(t, u.id);
    const theirs = await listingFor(t, other.id);
    // a FINISHED contract and a settled caution deposit are retained as the financial record
    const settled = await contract(t, u.id, other.id, theirs, "FULLY_SETTLED");
    await t.run(async (ctx) => {
      await ctx.db.insert("re_caution_deposits", {
        contractId: settled, originalDepositAmount: 10, heldAmount: 0, deductionClaimAmount: 0, refundedAmount: 10,
        status: "REFUNDED_CLEAN", inventoryChecklistSigned: true, createdAt: 1,
      } as any);
      await ctx.db.insert("qr_payment_requests", {
        token: "qr-1", receiverId: u.id, currency: "SLE", singleUse: false, status: "active", createdAt: 1, updatedAt: 1,
      });
      await ctx.db.insert("agent_profiles", {
        userId: u.id, businessName: "Biz", businessType: "dual", tinNumber: "TIN-1", officeAddress: "1 Main", officeCity: "F",
        publicContactPhone: "+23276111111", bio: "hello", isVerified: true, allowDirectBuyerLeads: true, updatedAt: 1,
      } as any);
    });

    const res = await t.mutation(internal.accountDeletion.processDueDeletions, { now: NOW() });
    expect(res.processed).toBe(1);

    const a: any = await t.run(async (ctx) => ctx.db.get(mine));
    expect(a.isPublished).toBe(false);
    expect(a.privateContactPhone).toBeUndefined();
    const b: any = await t.run(async (ctx) => ctx.db.get(theirs));
    expect(b.isPublished).toBe(true); // unrelated user's listing untouched
    expect(b.privateContactPhone).toBe("+23276999999");

    const qr: any = await t.run(async (ctx) => ctx.db.query("qr_payment_requests").first());
    expect(qr.status).toBe("cancelled");
    const ap: any = await t.run(async (ctx) => ctx.db.query("agent_profiles").first());
    expect(ap.publicContactPhone).toBe("");
    expect(ap.bio).toBeUndefined();
    expect(ap.tinNumber).toBe("TIN-1"); // KYC field retained

    expect(await count(t, "re_escrow_contracts")).toBe(1);
    expect(await count(t, "re_caution_deposits")).toBe(1);
    expect(await count(t, "walletBalances")).toBe(2);
  });

  test("an unrelated user's open contract does not block someone else's erasure", async () => {
    const t = convexTest(schema, modules);
    await dueUser(t, "free");
    const b = await makeUser(t, "busy1");
    const c = await makeUser(t, "busy2");
    await contract(t, b.id, c.id, await listingFor(t, c.id), "FUNDS_LOCKED");
    const res = await t.mutation(internal.accountDeletion.processDueDeletions, { now: NOW() });
    expect(res.processed).toBe(1);
    expect(res.deferred).toEqual([]);
  });
});

