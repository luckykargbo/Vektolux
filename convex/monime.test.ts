/// <reference types="vite/client" />
// MoniMe integration: webhooks are HINTS; MoniMe's own API decides. A fake MoniMe server stands in
// for the provider so every branch (paid, failed, pending, unreachable, forged) can be exercised.

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { hashWalletPin } from "./lib/pin";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
const PIN = "1234";
const WEBHOOK_SECRET = "synthetic-webhook-secret-0123456789-abcdefghij"; // test-only, not a real credential
const OLD_SECRET = "synthetic-legacy-secret-9876543210-zyxwvutsrq"; // test-only
let seq = 0;

// ── fake MoniMe ─────────────────────────────────────────────────────
type FakePayout = { id: string; status: string; amount: any; metadata: any; failureDetail?: any };
const payouts = new Map<string, FakePayout>();
const codes = new Map<string, any>();
const checkoutSessions = new Map<string, any>();
let payoutPostMode: "ok" | "reject" | "unreachable" = "ok";
let payoutPostStatus = "processing";

function installFakeMonime() {
  payouts.clear();
  codes.clear();
  checkoutSessions.clear();
  process.env.MONIME_WEBHOOK_SECRET = WEBHOOK_SECRET;
  delete process.env.MONIME_WEBHOOK_SECRET_OLD;
  payoutPostMode = "ok";
  payoutPostStatus = "processing";
  process.env.MONIME_SPACE_ID = "spc-test";
  process.env.MONIME_ACCESS_TOKEN = "test-token";
  process.env.MONIME_API_BASE_URL = "https://fake.monime.test/v1";
  vi.stubGlobal("fetch", async (url: string, init?: any) => {
    const u = String(url);
    const json = (status: number, body: any) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
    if (u.endsWith("/payouts") && init?.method === "POST") {
      if (payoutPostMode === "unreachable") throw new Error("network down");
      if (payoutPostMode === "reject") return json(400, { success: false, error: { message: "bad destination" } });
      const body = JSON.parse(init.body);
      const id = `pyt-${++seq}abcd`;
      const p: FakePayout = { id, status: payoutPostStatus, amount: body.amount, metadata: body.metadata };
      payouts.set(id, p);
      return json(200, { success: true, result: p });
    }
    const pm = u.match(/\/payouts\/([^/?]+)$/);
    if (pm) {
      const p = payouts.get(pm[1]);
      return p ? json(200, { success: true, result: p }) : json(404, { success: false });
    }
    const sm = u.match(/\/checkout-sessions\/([^/?]+)$/);
    if (sm) {
      const c = checkoutSessions.get(sm[1]);
      return c ? json(200, { success: true, result: c }) : json(404, { success: false });
    }
    const cm = u.match(/\/payment-codes\/([^/?]+)$/);
    if (cm) {
      const c = codes.get(cm[1]);
      return c ? json(200, { success: true, result: c }) : json(404, { success: false });
    }
    return json(404, {});
  });
}

beforeEach(() => installFakeMonime());
afterEach(() => {
  vi.unstubAllGlobals();
  delete process.env.MONIME_SPACE_ID;
  delete process.env.MONIME_ACCESS_TOKEN;
  delete process.env.MONIME_API_BASE_URL;
  delete process.env.MONIME_WEBHOOK_SECRET;
  delete process.env.MONIME_WEBHOOK_SECRET_OLD;
});

// ── helpers ─────────────────────────────────────────────────────────
async function makeUser(t: T, name: string) {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@test.vektolux`, phone: `+2327700${String(1000 + seq)}`, name, role: "client",
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(),
    })
  );
  const h = await hashWalletPin(id, PIN);
  await t.run(async (ctx) => ctx.db.patch(id, { walletPinHash: h }));
  return { id, token };
}
const fund = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount, provider: "TEST", providerReference: `f-${userId}-${seq++}` });
const balance = (t: T, u: { token: string }) => t.query(api.wallet.getUserBalance, { sessionToken: u.token });

/** Monime-Signature: t=<unix>,v1=<base64 HMAC-SHA256 of "<t>_" + raw body> (synthetic secret, test only). */
async function signHeader(rawBody: string, secret = WEBHOOK_SECRET, ts = Math.floor(Date.now() / 1000)) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${ts}_${rawBody}`)));
  let bin = "";
  for (const b of mac) bin += String.fromCharCode(b);
  return `t=${ts},v1=${btoa(bin)}`;
}
/** Sends an exact raw body with an exact header value (or none). */
const rawWebhook = (t: T, rawBody: string, signature: string | null, extra: Record<string, string> = {}) =>
  t.fetch("/webhooks/monime", {
    method: "POST",
    body: rawBody,
    headers: { "content-type": "application/json", ...(signature === null ? {} : { "monime-signature": signature }), ...extra },
  });
/** A correctly signed webhook. */
const webhook = async (t: T, body: any, headers: Record<string, string> = {}) => {
  const rawBody = JSON.stringify(body);
  return rawWebhook(t, rawBody, await signHeader(rawBody), headers);
};

const evt = (name: string, objectId: string, data: any = {}) => ({
  apiVersion: "2024-08-01",
  event: { id: `wke-${++seq}`, name, timestamp: String(Math.floor(Date.now() / 1000)) },
  object: { id: objectId, type: name.split(".")[0] },
  data,
});

async function pendingDeposit(t: T, userId: Id<"users">, ref: string, amount: number) {
  await t.run(async (ctx) => {
    const w = await ctx.db.insert("walletBalances", { userId, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: Date.now() });
    await ctx.db.insert("transactions", {
      transactionId: `TOPUP-${ref}`, walletId: w, userId, type: "top_up", amount, currency: "SLE",
      gatewayProvider: "MONIME_ORANGE", gatewayReference: ref, status: "pending", createdAt: Date.now(), updatedAt: Date.now(),
    });
  });
}

const bankless = (token: string, key: string) => ({
  sessionToken: token, amount: 100, method: "mobile_money" as const, destinationProviderCode: "orange",
  destinationAccountNumber: "+23276123456", pin: PIN, idempotencyKey: key,
});

// ─────────────────────────────────────────────────────────────────────
describe("deposit webhooks are hints; MoniMe decides", () => {
  test("a forged 'paid' webhook cannot credit anyone (space id and body are not authentication)", async () => {
    const t = convexTest(schema, modules);
    const victim = await makeUser(t, "victim");
    const attacker = await makeUser(t, "attacker");
    // No such payment code exists at MoniMe and our victim has a pending top-up.
    await pendingDeposit(t, victim.id, "pmc-forged1", 5000);

    const res = await webhook(
      t,
      { ...evt("payment_code.completed", "pmc-forged1", { amount: { value: 500000, currency: "SLE" }, metadata: { userId: attacker.id } }), spaceId: "spc-test" },
      { "monime-space-id": "spc-test" }
    );
    expect(res.status).toBe(200);
    expect((await balance(t, victim)).availableBalance).toBe(0);
    expect((await balance(t, attacker)).availableBalance).toBe(0);
  });

  test("a paid code is credited to the owner of OUR pending transaction, for MoniMe's amount, once", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const other = await makeUser(t, "other");
    await pendingDeposit(t, owner.id, "pmc-real1", 9999); // our pending record says 9999…
    codes.set("pmc-real1", { id: "pmc-real1", status: "completed", amount: { value: 1000, currency: "SLE" } }); // …MoniMe says 10.00

    // The webhook claims a different user and a huge amount: both are ignored.
    const body = evt("payment_code.completed", "pmc-real1", { amount: { value: 99999900, currency: "SLE" }, metadata: { userId: other.id } });
    await webhook(t, body);
    await webhook(t, body); // replay

    const b = await balance(t, owner);
    expect(b.availableBalance).toBe(10); // exactly MoniMe's verified 10.00 — no invented fee
    expect(b.escrowBalance).toBe(0);
    expect((await balance(t, other)).availableBalance).toBe(0);
  });

  test("a code MoniMe reports as still pending is not credited", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    await pendingDeposit(t, owner.id, "pmc-wait1", 20);
    codes.set("pmc-wait1", { id: "pmc-wait1", status: "pending", amount: { value: 2000, currency: "SLE" } });
    await webhook(t, evt("payment_code.completed", "pmc-wait1"));
    expect((await balance(t, owner)).availableBalance).toBe(0);
  });

  test("payout events are never treated as deposits", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    await pendingDeposit(t, owner.id, "pmc-x1", 20);
    codes.set("pmc-x1", { id: "pmc-x1", status: "completed", amount: { value: 2000, currency: "SLE" } });
    // A payout.completed event that names a payment-code id must not settle the deposit.
    await webhook(t, evt("payout.completed", "pmc-x1"));
    expect((await balance(t, owner)).availableBalance).toBe(0);
  });

  test("the background poller credits a paid deposit whose webhook was missed", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    await pendingDeposit(t, owner.id, "pmc-poll1", 50);
    codes.set("pmc-poll1", { id: "pmc-poll1", status: "completed", amount: { value: 5000, currency: "SLE" } });
    const r: any = await t.action(internal.payments.reconcilePendingDeposits, {});
    expect(r.checked).toBe(1);
    expect((await balance(t, owner)).availableBalance).toBeGreaterThan(49);
  });

  test("the user-triggered check only works on your own payment", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const other = await makeUser(t, "other");
    await pendingDeposit(t, owner.id, "pmc-own1", 10);
    await expect(
      t.action(api.payments.verifyAndSettleMoniMePayment, { reference: "pmc-own1", sessionToken: other.token })
    ).rejects.toThrow(/does not belong/i);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("mobile-money withdrawals follow MoniMe's confirmed payout status", () => {
  async function startWithdrawal(t: T, funds = 500) {
    const user = await makeUser(t, "alice");
    await fund(t, user.id, funds);
    const res: any = await t.action(api.withdrawals.requestWithdrawal, bankless(user.token, `wd-monime-key-${seq++}00`));
    return { user, res };
  }

  test("an accepted-but-unconfirmed payout stays 'processing' with funds reserved", async () => {
    const t = convexTest(schema, modules);
    const { user, res } = await startWithdrawal(t);
    expect(res.status).toBe("processing");
    const b = await balance(t, user);
    expect(b.availableBalance).toBe(400);
    expect(b.pendingBalance).toBe(100);
  });

  test("payout.completed from MoniMe completes it: reserved funds leave the wallet", async () => {
    const t = convexTest(schema, modules);
    const { user } = await startWithdrawal(t);
    const [id, p] = [...payouts.entries()][0];
    p.status = "completed";
    await webhook(t, evt("payout.completed", id, { metadata: { withdrawalId: p.metadata.withdrawalId } }));
    const b = await balance(t, user);
    expect(b.availableBalance).toBe(400);
    expect(b.pendingBalance).toBe(0);
    const wd = await t.query(api.withdrawals.getMyWithdrawals, { sessionToken: user.token });
    expect(wd[0].status).toBe("completed");
  });

  test("payout.failed releases the reserved funds back to available", async () => {
    const t = convexTest(schema, modules);
    const { user } = await startWithdrawal(t);
    const [id, p] = [...payouts.entries()][0];
    p.status = "failed";
    p.failureDetail = { code: "provider_account_missing", message: "No such account" };
    await webhook(t, evt("payout.failed", id));
    const b = await balance(t, user);
    expect(b.availableBalance).toBe(500);
    expect(b.pendingBalance).toBe(0);
    const wd = await t.query(api.withdrawals.getMyWithdrawals, { sessionToken: user.token });
    expect(wd[0].status).toBe("failed");
    expect(wd[0].failureReason).toMatch(/No such account/);
  });

  test("a forged payout.completed (MoniMe says it is not completed) changes nothing", async () => {
    const t = convexTest(schema, modules);
    const { user } = await startWithdrawal(t);
    const [id] = [...payouts.entries()][0]; // still "processing" at MoniMe
    await webhook(t, evt("payout.completed", id));
    await webhook(t, evt("payout.completed", "pyt-doesnotexist1"));
    const b = await balance(t, user);
    expect(b.availableBalance).toBe(400);
    expect(b.pendingBalance).toBe(100);
  });

  test("a payout whose metadata or amount does not match OUR withdrawal is never applied", async () => {
    const t = convexTest(schema, modules);
    const { user } = await startWithdrawal(t);
    const [id, p] = [...payouts.entries()][0];
    p.status = "completed";
    p.metadata = { withdrawalId: "someone-elses" };
    await webhook(t, evt("payout.completed", id));
    expect((await balance(t, user)).pendingBalance).toBe(100);

    p.metadata = { withdrawalId: [...payouts.values()][0].metadata.withdrawalId }; // still mismatched id from a different source
    p.metadata.withdrawalId = "x";
    p.amount = { currency: "SLE", value: 1 };
    await webhook(t, evt("payout.completed", id));
    expect((await balance(t, user)).pendingBalance).toBe(100);
  });

  test("the poller completes a payout even if the webhook never arrived", async () => {
    const t = convexTest(schema, modules);
    const { user } = await startWithdrawal(t);
    const [, p] = [...payouts.entries()][0];
    p.status = "completed";
    const r: any = await t.action(internal.withdrawals.reconcileProcessing, {});
    expect(r.checked).toBe(1);
    const b = await balance(t, user);
    expect(b.pendingBalance).toBe(0);
    expect(b.availableBalance).toBe(400);
  });

  test("an unreachable provider never releases funds (the payout may have happened)", async () => {
    const t = convexTest(schema, modules);
    const user = await makeUser(t, "alice");
    await fund(t, user.id, 500);
    payoutPostMode = "unreachable";
    const res: any = await t.action(api.withdrawals.requestWithdrawal, bankless(user.token, "wd-unreach-key-0001"));
    expect(res.status).toBe("processing");
    const b = await balance(t, user);
    expect(b.availableBalance).toBe(400);
    expect(b.pendingBalance).toBe(100);
  });

  test("a definite provider rejection releases the funds and reports failure", async () => {
    const t = convexTest(schema, modules);
    const user = await makeUser(t, "alice");
    await fund(t, user.id, 500);
    payoutPostMode = "reject";
    const res: any = await t.action(api.withdrawals.requestWithdrawal, bankless(user.token, "wd-reject-key-0001"));
    expect(res.status).toBe("failed");
    const b = await balance(t, user);
    expect(b.availableBalance).toBe(500);
    expect(b.pendingBalance).toBe(0);
  });

  test("a payout MoniMe already reports completed at creation completes immediately", async () => {
    const t = convexTest(schema, modules);
    const user = await makeUser(t, "alice");
    await fund(t, user.id, 500);
    payoutPostStatus = "completed";
    const res: any = await t.action(api.withdrawals.requestWithdrawal, bankless(user.token, "wd-instant-key-0001"));
    expect(res.status).toBe("completed");
    const b = await balance(t, user);
    expect(b.availableBalance).toBe(400);
    expect(b.pendingBalance).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("webhook authentication (Monime-Signature, raw body, freshness)", () => {
  async function paidCode(t: T, ref = "pmc-auth1") {
    const owner = await makeUser(t, "owner");
    await pendingDeposit(t, owner.id, ref, 10);
    codes.set(ref, { id: ref, status: "completed", amount: { value: 1000, currency: "SLE" } });
    return owner;
  }
  const body = (ref = "pmc-auth1") => JSON.stringify(evt("payment_code.completed", ref));

  test("a valid signature is accepted and the payment is settled", async () => {
    const t = convexTest(schema, modules);
    const owner = await paidCode(t);
    const raw = body();
    const res = await rawWebhook(t, raw, await signHeader(raw));
    expect(res.status).toBe(200);
    expect(((await res.json()) as any).outcome).toBe("settled");
    expect((await balance(t, owner)).availableBalance).toBe(10);
  });

  test("an invalid signature (wrong secret) is rejected and nothing is processed", async () => {
    const t = convexTest(schema, modules);
    const owner = await paidCode(t);
    const raw = body();
    const res = await rawWebhook(t, raw, await signHeader(raw, "some-other-secret-0123456789-0123456789-ab"));
    expect(res.status).toBe(401);
    expect((await balance(t, owner)).availableBalance).toBe(0);
  });

  test("a missing signature is rejected", async () => {
    const t = convexTest(schema, modules);
    const owner = await paidCode(t);
    expect((await rawWebhook(t, body(), null)).status).toBe(401);
    expect((await balance(t, owner)).availableBalance).toBe(0);
  });

  test("a modified body is rejected (signature over a different byte string)", async () => {
    const t = convexTest(schema, modules);
    const owner = await paidCode(t);
    const signedFor = body("pmc-auth1");
    const sig = await signHeader(signedFor);
    const tampered = signedFor.replace("pmc-auth1", "pmc-auth2");
    expect((await rawWebhook(t, tampered, sig)).status).toBe(401);
    // even a harmless-looking whitespace change alters the signed bytes
    expect((await rawWebhook(t, signedFor + " ", sig)).status).toBe(401);
    expect((await balance(t, owner)).availableBalance).toBe(0);
  });

  test("the RAW bytes are verified: pretty-printed / unicode bodies verify, a re-serialised copy does not", async () => {
    const t = convexTest(schema, modules);
    const owner = await paidCode(t);
    const obj = { ...evt("payment_code.completed", "pmc-auth1"), note: "Kaffu Bullom \u00e9\u00e8 \u2713" };
    const pretty = JSON.stringify(obj, null, 4); // exactly what the sender signed
    expect((await rawWebhook(t, pretty, await signHeader(pretty))).status).toBe(200);
    expect((await balance(t, owner)).availableBalance).toBe(10);
    // a receiver that parsed and re-serialised would verify a DIFFERENT string: must not authenticate
    const t2 = convexTest(schema, modules);
    await paidCode(t2, "pmc-auth1");
    const reserialised = JSON.stringify(JSON.parse(pretty));
    expect((await rawWebhook(t2, reserialised, await signHeader(pretty))).status).toBe(401);
  });

  test("stale and future timestamps are rejected (replay window 300 s); fresh ones within the window pass", async () => {
    const t = convexTest(schema, modules);
    await paidCode(t);
    const now = Math.floor(Date.now() / 1000);
    const raw = body();
    expect((await rawWebhook(t, raw, await signHeader(raw, WEBHOOK_SECRET, now - 400))).status).toBe(401); // replayed old capture
    expect((await rawWebhook(t, raw, await signHeader(raw, WEBHOOK_SECRET, now + 400))).status).toBe(401); // future
    expect((await rawWebhook(t, raw, await signHeader(raw, WEBHOOK_SECRET, now - 200))).status).toBe(200);
  });

  test("malformed Monime-Signature headers are rejected", async () => {
    const t = convexTest(schema, modules);
    await paidCode(t);
    const raw = body();
    const good = await signHeader(raw);
    const [tPart, vPart] = good.split(",");
    const hex = Array.from(atob(vPart.slice(3)), (c) => c.charCodeAt(0).toString(16).padStart(2, "0")).join("");
    for (const bad of [
      vPart, // no timestamp
      tPart, // no mac
      `${tPart},${vPart},extra=1`, // extra component
      `${vPart},${tPart},${tPart}`, // duplicate key
      `${tPart},v1=${hex}`, // wrong encoding
      `${tPart},v1=AAAA`, // wrong length
      `t=abc,${vPart}`, // non-numeric timestamp
      "garbage",
      "sha256=" + hex,
    ]) {
      expect((await rawWebhook(t, raw, bad)).status).toBe(401);
    }
  });

  test("only the Monime-Signature header counts (look-alike headers are ignored)", async () => {
    const t = convexTest(schema, modules);
    await paidCode(t);
    const raw = body();
    const sig = await signHeader(raw);
    expect((await rawWebhook(t, raw, null, { "x-monime-signature": sig, "x-signature": sig, signature: sig })).status).toBe(401);
  });

  test("fail closed: with no secret configured every request is refused (the pollers still settle)", async () => {
    const t = convexTest(schema, modules);
    const owner = await paidCode(t);
    delete process.env.MONIME_WEBHOOK_SECRET;
    const raw = body();
    const res = await rawWebhook(t, raw, await signHeader(raw));
    expect(res.status).toBe(503);
    expect((await balance(t, owner)).availableBalance).toBe(0);
    await t.action(internal.payments.reconcilePendingDeposits, {}); // safety net still works
    expect((await balance(t, owner)).availableBalance).toBe(10);
  });

  test("migration window: the legacy secret is accepted ONLY while MONIME_WEBHOOK_SECRET_OLD is set; the new secret always works", async () => {
    const t = convexTest(schema, modules);
    await paidCode(t, "pmc-mig1");
    await paidCode(t, "pmc-mig2");
    const legacyRaw = body("pmc-mig1");
    // not configured: a body signed with the legacy secret is refused
    expect((await rawWebhook(t, legacyRaw, await signHeader(legacyRaw, OLD_SECRET))).status).toBe(401);
    process.env.MONIME_WEBHOOK_SECRET_OLD = OLD_SECRET;
    expect((await rawWebhook(t, legacyRaw, await signHeader(legacyRaw, OLD_SECRET))).status).toBe(200);
    const newRaw = body("pmc-mig2");
    expect((await rawWebhook(t, newRaw, await signHeader(newRaw))).status).toBe(200);
    // an unknown secret is still refused, and the response never echoes any secret
    const bad = body("pmc-mig1");
    const res = await rawWebhook(t, bad, await signHeader(bad, "attacker-secret-0123456789-0123456789-abcd"));
    expect(res.status).toBe(401);
    const text = await res.text();
    expect(text).not.toContain(WEBHOOK_SECRET);
    expect(text).not.toContain(OLD_SECRET);
  });

  test("no response ever contains a secret or the signature", async () => {
    const t = convexTest(schema, modules);
    await paidCode(t);
    const raw = body();
    const sig = await signHeader(raw);
    const res = await rawWebhook(t, raw, sig);
    const text = await res.text();
    expect(text).not.toContain(WEBHOOK_SECRET);
    expect(text).not.toContain(sig);
    expect(text).not.toContain(sig.split("v1=")[1]);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("duplicate and migration-overlap deliveries never repeat a financial effect", () => {
  test("the same event delivered twice (Monime retry) is processed once", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    await pendingDeposit(t, owner.id, "pmc-dup1", 10);
    codes.set("pmc-dup1", { id: "pmc-dup1", status: "completed", amount: { value: 1000, currency: "SLE" } });
    const raw = JSON.stringify(evt("payment_code.completed", "pmc-dup1"));
    const first: any = await (await rawWebhook(t, raw, await signHeader(raw))).json();
    const second: any = await (await rawWebhook(t, raw, await signHeader(raw))).json();
    expect(first.outcome).toBe("settled");
    expect(second.duplicate).toBe(true);
    expect((await balance(t, owner)).availableBalance).toBe(10);
  });

  test("old + new webhook for the SAME payment (different event ids) credit exactly once", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    process.env.MONIME_WEBHOOK_SECRET_OLD = OLD_SECRET;
    await pendingDeposit(t, owner.id, "pmc-dup2", 10);
    codes.set("pmc-dup2", { id: "pmc-dup2", status: "completed", amount: { value: 1000, currency: "SLE" } });
    const viaNew = JSON.stringify(evt("payment_code.completed", "pmc-dup2"));
    const viaLegacy = JSON.stringify(evt("payment_code.completed", "pmc-dup2")); // different event id
    expect((await rawWebhook(t, viaNew, await signHeader(viaNew))).status).toBe(200);
    expect((await rawWebhook(t, viaLegacy, await signHeader(viaLegacy, OLD_SECRET))).status).toBe(200);
    expect((await balance(t, owner)).availableBalance).toBe(10);
    const txs = await t.run(async (ctx) => ctx.db.query("transactions").collect());
    expect(txs.filter((x) => x.type === "top_up" && x.status === "completed")).toHaveLength(1);
    const entries = await t.run(async (ctx) => ctx.db.query("ledger_entries").collect());
    expect(entries.filter((e) => e.accountType === "CLIENT_AVAILABLE" && e.direction === "CREDIT")).toHaveLength(1);
  });

  test("a duplicate payout.completed completes the withdrawal once", async () => {
    const t = convexTest(schema, modules);
    const user = await makeUser(t, "alice");
    await fund(t, user.id, 500);
    await t.action(api.withdrawals.requestWithdrawal, bankless(user.token, "wd-dup-key-0000001"));
    const [id, p] = [...payouts.entries()][0];
    p.status = "completed";
    const raw = JSON.stringify(evt("payout.completed", id, { metadata: { withdrawalId: p.metadata.withdrawalId } }));
    await rawWebhook(t, raw, await signHeader(raw));
    await rawWebhook(t, raw, await signHeader(raw));
    const other = JSON.stringify(evt("payout.completed", id, { metadata: { withdrawalId: p.metadata.withdrawalId } }));
    await rawWebhook(t, other, await signHeader(other)); // a different event id for the same payout
    const b = await balance(t, user);
    expect(b.availableBalance).toBe(400); // 500 - 100, charged once
    expect(b.pendingBalance).toBe(0);
    const entries = await t.run(async (ctx) => ctx.db.query("ledger_entries").collect());
    expect(entries.filter((e) => e.accountType === "TELCO_CLEARING_LIABILITY" && e.direction === "CREDIT" && e.amount === 100)).toHaveLength(1);
  });

  test("a duplicate payout.failed returns the funds once", async () => {
    const t = convexTest(schema, modules);
    const user = await makeUser(t, "alice");
    await fund(t, user.id, 500);
    await t.action(api.withdrawals.requestWithdrawal, bankless(user.token, "wd-dup-key-0000002"));
    const [id, p] = [...payouts.entries()][0];
    p.status = "failed";
    p.failureDetail = { code: "x", message: "failed" };
    for (let i = 0; i < 3; i++) {
      const raw = JSON.stringify(evt("payout.failed", id));
      await rawWebhook(t, raw, await signHeader(raw));
    }
    const b = await balance(t, user);
    expect(b.availableBalance).toBe(500);
    expect(b.pendingBalance).toBe(0);
  });

  test("the event ledger: done events are skipped, failed ones may be retried, in-flight ones are not duplicated", async () => {
    const t = convexTest(schema, modules);
    const claim = (id: string) => t.mutation(internal.monimeWebhooks.claimEvent, { eventId: id, eventName: "payout.failed", objectId: "pyt-x1234" });
    expect(((await claim("wke-a")) as any).fresh).toBe(true);
    expect(((await claim("wke-a")) as any).fresh).toBe(false); // still processing
    await t.mutation(internal.monimeWebhooks.finishEvent, { eventId: "wke-a", ok: false });
    expect(((await claim("wke-a")) as any).fresh).toBe(true); // failed -> retry allowed
    await t.mutation(internal.monimeWebhooks.finishEvent, { eventId: "wke-a", ok: true, outcome: "settled" });
    expect(((await claim("wke-a")) as any).fresh).toBe(false); // done -> never again
    // housekeeping removes only old rows
    await t.run(async (ctx) => {
      const row = await ctx.db.query("monime_webhook_events").first();
      await ctx.db.patch(row!._id, { receivedAt: Date.now() - 40 * 24 * 3600 * 1000 });
    });
    expect(((await t.mutation(internal.monimeWebhooks.purgeOldEvents, {})) as any).deleted).toBe(1);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("Caph event handlers", () => {
  const owner = async (t: T) => makeUser(t, "owner");

  test("checkout_session.completed credits the owner of OUR pending transaction for the amount MONIME reports", async () => {
    const t = convexTest(schema, modules);
    const u = await owner(t);
    const other = await makeUser(t, "other");
    await pendingDeposit(t, u.id, "scs-co1abc", 9999); // our record says 9999...
    checkoutSessions.set("scs-co1abc", {
      id: "scs-co1abc", status: "completed", lineItems: { data: [{ name: "Deposit", quantity: 1, price: { currency: "SLE", value: 2500 } }] },
      metadata: {},
    }); // ...Monime says 25.00
    const res = await webhook(t, evt("checkout_session.completed", "scs-co1abc", { amount: { value: 99999900, currency: "SLE" }, metadata: { userId: other.id } }));
    expect(((await res.json()) as any).outcome).toBe("settled");
    expect((await balance(t, u)).availableBalance).toBe(25);
    expect((await balance(t, other)).availableBalance).toBe(0);
  });

  test("checkout_session.completed for a session Monime does not report completed credits nothing", async () => {
    const t = convexTest(schema, modules);
    const u = await owner(t);
    await pendingDeposit(t, u.id, "scs-co2abc", 20);
    checkoutSessions.set("scs-co2abc", { id: "scs-co2abc", status: "pending", lineItems: { data: [{ quantity: 1, price: { currency: "SLE", value: 2000 } }] } });
    await webhook(t, evt("checkout_session.completed", "scs-co2abc"));
    await webhook(t, evt("checkout_session.completed", "scs-unknown1")); // not one of ours
    expect((await balance(t, u)).availableBalance).toBe(0);
  });

  test("checkout_session.expired / payment_code.expired close the pending deposit; no money moves", async () => {
    const t = convexTest(schema, modules);
    const u = await owner(t);
    await pendingDeposit(t, u.id, "scs-ex1abc", 20);
    checkoutSessions.set("scs-ex1abc", { id: "scs-ex1abc", status: "expired", lineItems: { data: [{ quantity: 1, price: { currency: "SLE", value: 2000 } }] } });
    await webhook(t, evt("checkout_session.expired", "scs-ex1abc"));
    const u2 = await makeUser(t, "second");
    await pendingDeposit(t, u2.id, "pmc-ex2abc", 20);
    codes.set("pmc-ex2abc", { id: "pmc-ex2abc", status: "expired", amount: { value: 2000, currency: "SLE" } });
    await webhook(t, evt("payment_code.expired", "pmc-ex2abc"));
    const txs = await t.run(async (ctx) => ctx.db.query("transactions").collect());
    expect(txs.map((x) => x.status)).toEqual(["failed", "failed"]);
    expect((await balance(t, u)).availableBalance).toBe(0);
    expect((await balance(t, u2)).availableBalance).toBe(0);
  });

  test("payment_code.processed (not final) never credits, even if Monime would now say completed", async () => {
    const t = convexTest(schema, modules);
    const u = await owner(t);
    await pendingDeposit(t, u.id, "pmc-pr1abc", 10);
    codes.set("pmc-pr1abc", { id: "pmc-pr1abc", status: "completed", amount: { value: 1000, currency: "SLE" } });
    const res = await webhook(t, evt("payment_code.processed", "pmc-pr1abc"));
    expect(((await res.json()) as any).outcome).toBe("ignored_not_final");
    expect((await balance(t, u)).availableBalance).toBe(0);
  });

  test("payout.delayed leaves the funds reserved (state is ambiguous)", async () => {
    const t = convexTest(schema, modules);
    const user = await makeUser(t, "alice");
    await fund(t, user.id, 500);
    await t.action(api.withdrawals.requestWithdrawal, bankless(user.token, "wd-delay-key-000001"));
    const [id, p] = [...payouts.entries()][0];
    p.status = "processing";
    await webhook(t, evt("payout.delayed", id));
    const b = await balance(t, user);
    expect(b.availableBalance).toBe(400);
    expect(b.pendingBalance).toBe(100);
  });

  test("payment.created, ussd_otp.* and internal_transfer.* are acknowledged with NO financial effect", async () => {
    const t = convexTest(schema, modules);
    const u = await owner(t);
    await pendingDeposit(t, u.id, "pmc-ig1abc", 10);
    codes.set("pmc-ig1abc", { id: "pmc-ig1abc", status: "completed", amount: { value: 1000, currency: "SLE" } });
    for (const name of ["payment.created", "ussd_otp.verified", "ussd_otp.expired", "internal_transfer.failed", "totally.unknown"]) {
      const res = await webhook(t, evt(name, "pmc-ig1abc", { amount: { value: 99999900, currency: "SLE" } }));
      expect(res.status).toBe(200);
      expect(((await res.json()) as any).outcome).toMatch(/^ignored/);
    }
    expect((await balance(t, u)).availableBalance).toBe(0);
  });

  test("a body that is not JSON is rejected after authentication (no crash)", async () => {
    const t = convexTest(schema, modules);
    const raw = "not json at all";
    expect((await rawWebhook(t, raw, await signHeader(raw))).status).toBe(400);
  });
});
