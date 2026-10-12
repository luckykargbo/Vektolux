/// <reference types="vite/client" />
// Orange Money webhook, exercised through the real HTTP routes with real signatures.
//
// What is verified: signature checked on the raw body before anything else; missing / malformed /
// altered requests rejected; duplicates and replays credit at most once; failed events never credit;
// the caller cannot choose the user, the amount for an order, or the currency; concurrent duplicate
// deliveries credit once.
// What is NOT independently verifiable here (no provider API is invented): that an Orange Money
// delivery really originated from Orange beyond the shared secret / HMAC it carries, and Moneroo's
// own record of a payment (the webhook is only a hint; an admin approves after checking Moneroo).

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string };
let seq = 0;

const ORANGE_SECRET = "orange-test-secret-0123456789";

beforeEach(() => {
  process.env.ORANGE_MONEY_WEBHOOK_SECRET = ORANGE_SECRET;
});
afterEach(() => {
  delete process.env.ORANGE_MONEY_WEBHOOK_SECRET;
});

// `phoneVerified` models an account whose owner has proven control of its number (the only kind of
// account a carrier deposit may be matched to). Tests for the exploit paths pass `false`.
async function makeUser(t: T, name: string, phone: string, role = "client", phoneVerified = true): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", { email: `${name}${seq}@t.vx`, phone, name, role: role as any, isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(), ...(phoneVerified ? { phoneVerifiedAt: Date.now(), phoneVerifiedNumber: phone } : {}) } as any)
  );
  return { id, token };
}
const balance = async (t: T, userId: Id<"users">) =>
  (await t.run(async (ctx) => (await ctx.db.query("walletBalances").collect()).find((w) => w.userId === userId)))?.availableBalance ?? 0;
const topUps = (t: T) => t.run(async (ctx) => (await ctx.db.query("transactions").collect()).filter((x) => x.type === "top_up"));

// ═════════════════════════════ Orange Money ═════════════════════════════
async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const ORANGE_PATHS = ["/webhooks/orange-money", "/api/webhooks/orange-money", "/payments/orange-money/webhook"];
const orangeBody = (o: Record<string, unknown> = {}) => JSON.stringify({ carrierTransactionId: "OM-1001", phoneNumber: "+23276123456", amount: 250, status: "SUCCESS", currency: "SLE", ...o });
const orangePost = (t: T, body: string, headers: Record<string, string>, path = "/webhooks/orange-money") =>
  t.fetch(path, { method: "POST", headers: { "content-type": "application/json", ...headers }, body });
const orangeSig = (body: string) => hmacSha256Hex(ORANGE_SECRET, body);

describe("Orange Money webhook — authentication", () => {
  test("no signature, wrong secret, wrong HMAC, and an unset secret are all rejected; nothing is credited", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer", "+23276123456");
    const body = orangeBody();
    expect((await orangePost(t, body, {})).status).toBe(401);
    expect((await orangePost(t, body, { "x-orange-signature": "wrong" })).status).toBe(401);
    expect((await orangePost(t, body, { "x-orange-signature": "0".repeat(64) })).status).toBe(401);
    expect((await orangePost(t, body, { authorization: "Bearer nope" })).status).toBe(401);
    delete process.env.ORANGE_MONEY_WEBHOOK_SECRET;
    expect((await orangePost(t, body, { "x-orange-signature": ORANGE_SECRET })).status).toBe(401); // no secret => fail closed
    expect(await balance(t, u.id)).toBe(0);
    expect(await topUps(t)).toHaveLength(0);
  });

  test("an HMAC over a DIFFERENT body is rejected: altered amount, phone, reference or status", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer", "+23276123456");
    const original = orangeBody();
    const sig = await orangeSig(original);
    for (const altered of [
      orangeBody({ amount: 25_000 }),
      orangeBody({ phoneNumber: "+23276999999" }),
      orangeBody({ carrierTransactionId: "OM-9999" }),
      orangeBody({ status: "PENDING" }),
    ]) {
      expect((await orangePost(t, altered, { "x-orange-signature": sig })).status).toBe(401);
    }
    expect(await balance(t, u.id)).toBe(0);
    // the untouched body with its own signature is accepted and credits the exact amount
    expect((await orangePost(t, original, { "x-orange-signature": sig })).status).toBe(200);
    expect(await balance(t, u.id)).toBe(250);
  });

  test("the signature is checked before the body is parsed (garbage + bad signature => 401, not 400)", async () => {
    const t = convexTest(schema, modules);
    expect((await orangePost(t, "{not json", { "x-orange-signature": "bad" })).status).toBe(401);
    // valid signature over malformed JSON => 400 (authenticated, but unusable)
    expect((await orangePost(t, "{not json", { "x-orange-signature": await orangeSig("{not json") })).status).toBe(400);
  });

  test.each(ORANGE_PATHS)("all routes (%s) enforce the same checks", async (path) => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer", "+23276123456");
    const body = orangeBody({ carrierTransactionId: `OM-${path.length}` });
    expect((await orangePost(t, body, {}, path)).status).toBe(401);
    expect((await orangePost(t, body, { "x-orange-signature": await orangeSig(body) }, path)).status).toBe(200);
    expect(await balance(t, u.id)).toBe(250);
  });
});

describe("Orange Money webhook — shared secret is not a signature", () => {
  test("the raw secret as the signature header or as a Bearer token is rejected and credits nothing", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer", "+23276123456");
    const body = orangeBody({ carrierTransactionId: "OM-SECRET-1" });
    expect((await orangePost(t, body, { "x-orange-signature": ORANGE_SECRET })).status).toBe(401);
    expect((await orangePost(t, body, { "x-orange-signature": `sha256=${ORANGE_SECRET}` })).status).toBe(401);
    expect((await orangePost(t, body, { authorization: `Bearer ${ORANGE_SECRET}` })).status).toBe(401);
    expect((await orangePost(t, body, { authorization: ORANGE_SECRET })).status).toBe(401);
    // a valid-looking but unrelated 64-hex value is no better
    expect((await orangePost(t, body, { "x-orange-signature": "a".repeat(64) })).status).toBe(401);
    expect(await balance(t, u.id)).toBe(0);
    expect(await topUps(t)).toHaveLength(0);
  });

  test("a correct body HMAC alongside a wrong Bearer token is accepted (header is ignored), a wrong HMAC alongside the right secret is not", async () => {
    const t = convexTest(schema, modules);
    await makeUser(t, "payer", "+23276123456");
    const body = orangeBody({ carrierTransactionId: "OM-SECRET-2" });
    expect((await orangePost(t, body, { "x-orange-signature": "b".repeat(64), authorization: `Bearer ${ORANGE_SECRET}` })).status).toBe(401);
    expect((await orangePost(t, body, { "x-orange-signature": await orangeSig(body), authorization: "Bearer nope" })).status).toBe(200);
  });

  test("an uppercase / sha256=-prefixed HMAC of the right body is accepted (format only), still keyed on the body", async () => {
    const t = convexTest(schema, modules);
    await makeUser(t, "payer", "+23276123456");
    const body = orangeBody({ carrierTransactionId: "OM-SECRET-3" });
    const sig = (await orangeSig(body)).toUpperCase();
    expect((await orangePost(t, body, { "x-orange-signature": `sha256=${sig}` })).status).toBe(200);
  });
});

describe("Orange Money webhook — an unverified phone number is never a reason to credit", () => {
  const sign = async (b: string) => ({ "x-orange-signature": await orangeSig(b) });

  test("a squatter holding the paying number (unverified) is NOT credited; the deposit is held", async () => {
    const t = convexTest(schema, modules);
    const squatter = await makeUser(t, "squatter", "+23276123456", "client", false);
    const body = orangeBody({ carrierTransactionId: "OM-SQ-1" });
    const res = await orangePost(t, body, await sign(body));
    expect(res.status).toBe(200);
    expect(await balance(t, squatter.id)).toBe(0);
    expect(await topUps(t)).toHaveLength(0);
    const log: any = await t.run(async (ctx) => ctx.db.query("telco_webhook_logs").first());
    expect(log.status).toBe("HELD_UNVERIFIED_PHONE");
    expect(log.isProcessed).toBe(false);
  });

  test("when the real owner has verified the number, only the owner is credited, even if a squatter holds the same number", async () => {
    const t = convexTest(schema, modules);
    const squatter = await makeUser(t, "squatter", "+23276123456", "client", false);
    const owner = await makeUser(t, "owner", "+23276123456", "client", true);
    const body = orangeBody({ carrierTransactionId: "OM-SQ-2" });
    expect((await orangePost(t, body, await sign(body))).status).toBe(200);
    expect(await balance(t, owner.id)).toBe(250);
    expect(await balance(t, squatter.id)).toBe(0);
  });

  test("a verified number that the user later changed away from no longer receives credits", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "mover", "+23276123456");
    await t.run(async (ctx) => ctx.db.patch(u.id, { phone: "+23279000000" }));
    const body = orangeBody({ carrierTransactionId: "OM-MOVE-1" });
    await orangePost(t, body, await sign(body));
    expect(await balance(t, u.id)).toBe(0);
  });

  test("held deposit is credited exactly once after the owner verifies the number and the provider redelivers", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "late", "+23276123456", "client", false);
    const body = orangeBody({ carrierTransactionId: "OM-LATE-1" });
    await orangePost(t, body, await sign(body));
    expect(await balance(t, u.id)).toBe(0);
    const v: any = await t.mutation(internal.users.markPhoneVerified, { userId: u.id, phone: "+23276123456", method: "test" });
    expect(v.success).toBe(true);
    await orangePost(t, body, await sign(body));
    await orangePost(t, body, await sign(body));
    expect(await balance(t, u.id)).toBe(250);
    expect(await topUps(t)).toHaveLength(1);
  });

  test("one number cannot be verified for two accounts", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "a", "+23276123456", "client", false);
    const b = await makeUser(t, "b", "+23276123456", "client", false);
    expect(((await t.mutation(internal.users.markPhoneVerified, { userId: a.id, phone: "+23276123456", method: "t" })) as any).success).toBe(true);
    const second: any = await t.mutation(internal.users.markPhoneVerified, { userId: b.id, phone: "+23276123456", method: "t" });
    expect(second.success).toBe(false);
    expect(second.reason).toBe("PHONE_ALREADY_VERIFIED_ELSEWHERE");
  });

  test("an inactive account is never credited through its verified number", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "gone", "+23276123456");
    await t.run(async (ctx) => ctx.db.patch(u.id, { isActive: false }));
    const body = orangeBody({ carrierTransactionId: "OM-GONE-1" });
    await orangePost(t, body, await sign(body));
    expect(await balance(t, u.id)).toBe(0);
  });

  test("malformed amounts, currencies and bodies never credit even with a valid signature", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer", "+23276123456");
    for (const o of [{ amount: -5 }, { amount: 0 }, { amount: "abc" }, { currency: "USD" }, { carrierTransactionId: "" }]) {
      const b = orangeBody({ carrierTransactionId: "OM-MAL-1", ...o });
      const r = await orangePost(t, b, await sign(b));
      expect([400]).toContain(r.status);
    }
    expect(await balance(t, u.id)).toBe(0);
  });
});

describe("Orange Money webhook — what the caller can and cannot choose", () => {
  test("the wallet owner comes ONLY from the paying phone; a userId in the body is ignored", async () => {
    const t = convexTest(schema, modules);
    const payer = await makeUser(t, "payer", "+23276123456");
    const victim = await makeUser(t, "victim", "+23277000000");
    const body = orangeBody({ userId: victim.id, metadata: { userId: victim.id } });
    expect((await orangePost(t, body, { "x-orange-signature": await orangeSig(body) })).status).toBe(200);
    expect(await balance(t, payer.id)).toBe(250);
    expect(await balance(t, victim.id)).toBe(0);
  });

  test("a status is required; missing, pending and failed deliveries never credit", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer", "+23276123456");
    const noStatus = JSON.stringify({ carrierTransactionId: "OM-2", phoneNumber: "+23276123456", amount: 250 });
    expect((await orangePost(t, noStatus, { "x-orange-signature": await orangeSig(noStatus) })).status).toBe(400);
    for (const status of ["PENDING", "FAILED", "CANCELLED", "ERROR"]) {
      const b = orangeBody({ carrierTransactionId: "OM-3", status });
      expect((await orangePost(t, b, { "x-orange-signature": await orangeSig(b) })).status).toBe(200);
    }
    expect(await balance(t, u.id)).toBe(0);
    expect(await topUps(t)).toHaveLength(0);
  });

  test("a later success after a pending delivery for the same transaction IS credited, once", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer", "+23276123456");
    const pending = orangeBody({ carrierTransactionId: "OM-4", status: "PENDING" });
    await orangePost(t, pending, { "x-orange-signature": await orangeSig(pending) });
    const ok = orangeBody({ carrierTransactionId: "OM-4", status: "SUCCESS" });
    await orangePost(t, ok, { "x-orange-signature": await orangeSig(ok) });
    await orangePost(t, ok, { "x-orange-signature": await orangeSig(ok) });
    expect(await balance(t, u.id)).toBe(250);
  });

  test("invalid amounts (0, negative, NaN, Infinity, text) and non-SLE currencies are refused", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer", "+23276123456");
    for (const [i, o] of [{ amount: 0 }, { amount: -5 }, { amount: "abc" }, { amount: "Infinity" }, { currency: "USD" }, { currency: "NGN" }].entries()) {
      const b = orangeBody({ carrierTransactionId: `OM-5${i}`, ...o });
      const res = await orangePost(t, b, { "x-orange-signature": await orangeSig(b) });
      expect(res.status, JSON.stringify(o)).toBe(400);
    }
    expect(await balance(t, u.id)).toBe(0);
  });

  test("an unknown paying phone credits nobody (held as ORPHANED_USER for manual resolution)", async () => {
    const t = convexTest(schema, modules);
    const b = orangeBody({ phoneNumber: "+23270000000" });
    const res = await orangePost(t, b, { "x-orange-signature": await orangeSig(b) });
    expect(res.status).toBe(200);
    expect(await topUps(t)).toHaveLength(0);
  });
});

describe("Orange Money webhook — duplicates, replays and concurrency", () => {
  test("the same signed delivery, replayed any number of times, credits once", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer", "+23276123456");
    const body = orangeBody();
    const sig = await orangeSig(body);
    for (let i = 0; i < 4; i++) expect((await orangePost(t, body, { "x-orange-signature": sig })).status).toBe(200);
    expect(await balance(t, u.id)).toBe(250);
    expect(await topUps(t)).toHaveLength(1);
  });

  test("the same transaction re-sent with a different amount cannot credit again", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer", "+23276123456");
    const a = orangeBody();
    await orangePost(t, a, { "x-orange-signature": await orangeSig(a) });
    const b = orangeBody({ amount: 5000 }); // validly signed, same transaction id
    await orangePost(t, b, { "x-orange-signature": await orangeSig(b) });
    expect(await balance(t, u.id)).toBe(250);
  });

  test("concurrent duplicate deliveries credit once", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer", "+23276123456");
    const body = orangeBody({ carrierTransactionId: "OM-CONC" });
    const sig = await orangeSig(body);
    const results = await Promise.all(Array.from({ length: 6 }, () => orangePost(t, body, { "x-orange-signature": sig })));
    expect(results.every((r) => r.status === 200)).toBe(true);
    expect(await balance(t, u.id)).toBe(250);
    expect(await topUps(t)).toHaveLength(1);
  });

  test("the provider reference is unique per provider: another user cannot be credited under it", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "a", "+23276123456");
    const b = await makeUser(t, "b", "+23276555555");
    const body1 = orangeBody({ carrierTransactionId: "OM-SHARED" });
    await orangePost(t, body1, { "x-orange-signature": await orangeSig(body1) });
    const body2 = orangeBody({ carrierTransactionId: "OM-SHARED", phoneNumber: "+23276555555" });
    await orangePost(t, body2, { "x-orange-signature": await orangeSig(body2) });
    expect(await balance(t, a.id)).toBe(250);
    expect(await balance(t, b.id)).toBe(0);
  });
});

// ═══════════════════════════ Moneroo is gone ═══════════════════════════
describe("Moneroo has been removed", () => {
  test("its webhook route no longer exists, whatever is sent", async () => {
    const t = convexTest(schema, modules);
    const res = await t.fetch("/api/webhooks/moneroo", {
      method: "POST",
      headers: { "content-type": "application/json", "x-moneroo-signature": "f".repeat(64) },
      body: JSON.stringify({ event: "payment.success", data: { id: "py_1", amount: 10_000, currency: "SLE" } }),
    });
    expect(res.status).toBe(404);
  });

  test("no Moneroo function remains, and the aggregator method is never offered or claimable", async () => {
    const payments = (await import("./payments")) as Record<string, unknown>;
    for (const name of ["initializeMonerooPayment", "processMonerooWebhookClaim", "recordMonerooClaimInit"]) {
      expect(name in payments, name).toBe(false);
    }
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "+23276000009", "admin");
    const user = await makeUser(t, "user", "+23276000010");
    // a stale row left in the database from the old integration
    await t.run(async (ctx) =>
      ctx.db.insert("payment_settings", { providerId: "moneroo_auto", displayName: "Old", type: "AGGREGATOR_AUTO", isEnabled: true, updatedAt: Date.now() } as any)
    );
    const offered: any[] = await t.query(api.payments.getActivePaymentMethods, {});
    expect(offered.some((m) => m.providerId === "moneroo_auto")).toBe(false);
    await expect(
      t.mutation(api.payments.submitManualPaymentClaim, { sessionToken: user.token, amount: 100, providerId: "moneroo_auto", transactionReference: "py_fake" })
    ).rejects.toThrow(/no longer available/i);
    // the seeded defaults no longer include it either
    const t2 = convexTest(schema, modules);
    const admin2 = await makeUser(t2, "admin", "+23276000011", "admin");
    await t2.mutation(api.payments.seedDefaultPaymentMethods, { sessionToken: admin2.token });
    const all: any[] = await t2.query(api.payments.getAllPaymentMethods, { sessionToken: admin2.token });
    expect(all.map((m) => m.providerId).sort()).toEqual(["afrimoney_manual", "bank_transfer", "qmoney_manual"]);
    void admin;
  });

  test("a leftover automated claim from the old integration can never be approved", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "+23276000012", "admin");
    const buyer = await makeUser(t, "buyer", "+23276000013");
    const claimId = await t.run(async (ctx) =>
      ctx.db.insert("escrow_payment_claims", {
        userId: buyer.id, amount: 10_000, currency: "SLE", providerId: "moneroo_auto", paymentType: "AUTOMATED",
        transactionReference: "py_old", status: "PENDING_APPROVAL", createdAt: Date.now(),
      } as any)
    );
    await expect(t.mutation(api.payments.approvePaymentClaim, { sessionToken: admin.token, claimId })).rejects.toThrow(/not confirmed/i);
    expect(await balance(t, buyer.id)).toBe(0);
  });
});
