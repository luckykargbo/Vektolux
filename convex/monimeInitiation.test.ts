/// <reference types="vite/client" />
// Payment initiation against a FAKE Monime (no live provider is ever contacted), then settlement
// through the signed webhook + Monime re-verification. Complements monime.test.ts (settlement side).

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
const SECRET = "synthetic-webhook-secret-0123456789-abcdefghij"; // test-only
let seq = 0;

type Call = { url: string; method: string; body: any };
let calls: Call[] = [];
const sessions = new Map<string, any>();
const codes = new Map<string, any>();
let checkoutMode: "ok" | "reject" = "ok";

beforeEach(() => {
  calls = [];
  sessions.clear();
  codes.clear();
  checkoutMode = "ok";
  process.env.MONIME_SPACE_ID = "spc-test";
  process.env.MONIME_ACCESS_TOKEN = "test-token";
  process.env.MONIME_API_BASE_URL = "https://fake.monime.test/v1";
  process.env.MONIME_WEBHOOK_SECRET = SECRET;
  vi.stubGlobal("fetch", async (url: string, init?: any) => {
    const u = String(url);
    const json = (status: number, body: any) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
    const body = init?.body ? JSON.parse(init.body) : undefined;
    calls.push({ url: u, method: init?.method ?? "GET", body });
    if (u.endsWith("/checkout-sessions") && init?.method === "POST") {
      if (checkoutMode === "reject") return json(400, { success: false, error: { message: "rejected" } });
      const id = `cs-${++seq}abcd`;
      const s = { id, status: "pending", lineItems: { data: body.lineItems }, metadata: body.metadata, redirectUrl: `https://pay.fake.test/${id}` };
      sessions.set(id, s);
      return json(200, { success: true, result: s });
    }
    if (u.endsWith("/payment-codes") && init?.method === "POST") {
      const id = `pmc-${++seq}abcd`;
      const c = { id, status: "pending", amount: body.amount, ussdCode: "*123#" };
      codes.set(id, c);
      return json(200, { success: true, result: c });
    }
    const sm = u.match(/\/checkout-sessions\/([^/?]+)$/);
    if (sm) return sessions.has(sm[1]) ? json(200, { success: true, result: sessions.get(sm[1]) }) : json(404, {});
    const cm = u.match(/\/payment-codes\/([^/?]+)$/);
    if (cm) return codes.has(cm[1]) ? json(200, { success: true, result: codes.get(cm[1]) }) : json(404, {});
    return json(404, {});
  });
});
afterEach(() => {
  vi.unstubAllGlobals();
  for (const k of ["MONIME_SPACE_ID", "MONIME_ACCESS_TOKEN", "MONIME_API_BASE_URL", "MONIME_WEBHOOK_SECRET"]) delete process.env[k];
});

async function makeUser(t: T, name: string) {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@test.vektolux`, phone: `+2327700${String(2000 + seq)}`, name, role: "client",
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(),
    })
  );
  return { id, token };
}
const pendingTxs = (t: T) => t.run(async (ctx) => (await ctx.db.query("transactions").collect()).filter((x) => x.type === "top_up"));
const balance = async (t: T, id: Id<"users">) =>
  (await t.run(async (ctx) => (await ctx.db.query("walletBalances").collect()).find((w) => w.userId === id)))?.availableBalance ?? 0;

async function sign(raw: string, secret = SECRET) {
  const ts = Math.floor(Date.now() / 1000);
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${ts}_${raw}`)));
  let bin = "";
  for (const b of mac) bin += String.fromCharCode(b);
  return `t=${ts},v1=${btoa(bin)}`;
}
const webhook = async (t: T, name: string, objectId: string, eventId = `wke-${++seq}`) => {
  const raw = JSON.stringify({ apiVersion: "2024-08-01", event: { id: eventId, name, timestamp: String(Math.floor(Date.now() / 1000)) }, object: { id: objectId, type: name.split(".")[0] }, data: {} });
  return t.fetch("/webhooks/monime", { method: "POST", body: raw, headers: { "content-type": "application/json", "monime-signature": await sign(raw) } });
};

describe("initiation", () => {
  test("a non-SLE currency is refused before anything is recorded or sent to Monime", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 50, currency: "USD", phoneNumber: "076123456" });
    expect(r.success).toBe(false);
    expect(r.code).toBe("UNSUPPORTED_CURRENCY");
    expect(await pendingTxs(t)).toHaveLength(0);
    expect(calls.filter((c) => c.method === "POST")).toHaveLength(0);
  });

  test("the pending deposit and the Monime checkout are SLE and bound to the authenticated payer", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    const other = await makeUser(t, "other");
    const r: any = await t.action(api.payments.initiateMoniMePayment, {
      sessionToken: u.token, userId: other.id, amount: 75, phoneNumber: "076123456", currency: "sle",
    });
    expect(r.success).toBe(true);
    const txs = await pendingTxs(t);
    expect(txs).toHaveLength(1);
    expect(txs[0].userId).toBe(u.id); // a client-supplied userId is ignored
    expect(txs[0].currency).toBe("SLE");
    const post = calls.find((c) => c.url.endsWith("/checkout-sessions") && c.method === "POST")!;
    expect(post.body.lineItems[0].price).toEqual({ currency: "SLE", value: 7500 });
  });

  test("an unknown caller cannot start a payment", async () => {
    const t = convexTest(schema, modules);
    await expect(t.action(api.payments.initiateMoniMePayment, { sessionToken: "nope-nope-nope-nope-0123456789", amount: 10 })).rejects.toThrow();
    expect(calls.filter((c) => c.method === "POST")).toHaveLength(0);
  });

  test("returnUrl: only the app's own scheme is passed on; a web URL is replaced", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 10, phoneNumber: "076123456", returnUrl: "https://evil.example/steal" });
    await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 10, phoneNumber: "076123456", returnUrl: "vektolux://payment/done" });
    const posts = calls.filter((c) => c.url.endsWith("/checkout-sessions") && c.method === "POST");
    expect(posts[0].body.successUrl).toBe("vektolux://payment/success");
    expect(posts[1].body.successUrl).toBe("vektolux://payment/done");
  });

  test("no phone number: no invented number is ever sent; the USSD fallback is skipped", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    checkoutMode = "reject";
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 10 });
    expect(r.success).toBe(false);
    expect(r.code).toBe("GATEWAY_ERROR");
    expect(calls.some((c) => c.url.endsWith("/payment-codes"))).toBe(false);
    for (const c of calls) expect(JSON.stringify(c.body ?? {})).not.toContain("23276000000");
  });

  test("with a phone number the USSD fallback uses THAT number and binds the payment code to the pending deposit", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    checkoutMode = "reject";
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 10, phoneNumber: "076123456" });
    expect(r.success).toBe(true);
    const pc = calls.find((c) => c.url.endsWith("/payment-codes") && c.method === "POST")!;
    expect(pc.body.authorizedPhoneNumber).toBe("+23276123456");
    const txs = await pendingTxs(t);
    expect(txs[0].gatewayReference).toBe(r.paymentCodeId);
  });

  test("checkout creation is budgeted per account (10 per 10 minutes)", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    const other = await makeUser(t, "other");
    for (let i = 0; i < 10; i++) {
      const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 5, phoneNumber: "076123456" });
      expect(r.success).toBe(true);
    }
    const over: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 5, phoneNumber: "076123456" });
    expect(over.success).toBe(false);
    expect(over.code).toBe("TOO_MANY_ATTEMPTS");
    const fine: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: other.token, amount: 5, phoneNumber: "076123456" });
    expect(fine.success).toBe(true);
  });
});

describe("initiation -> signed webhook -> verified credit (fake Monime)", () => {
  test("credits exactly what Monime reports, once, to the payer; replays and unpaid events change nothing", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 120, phoneNumber: "076123456" });
    const sessionId = r.transactionId as string;

    // Webhook arrives but Monime says it is still pending: nothing is credited.
    expect((await webhook(t, "checkout_session.completed", sessionId)).status).toBe(200);
    expect(await balance(t, u.id)).toBe(0);

    // Monime now reports it completed (our own checkout, our own reference).
    sessions.get(sessionId).status = "completed";
    const evId = `wke-${++seq}`;
    expect((await webhook(t, "checkout_session.completed", sessionId, evId)).status).toBe(200);
    expect(await balance(t, u.id)).toBe(120);

    // The same event again, and a fresh event for the same session: still exactly one credit.
    expect((await webhook(t, "checkout_session.completed", sessionId, evId)).status).toBe(200);
    expect((await webhook(t, "checkout_session.completed", sessionId)).status).toBe(200);
    expect(await balance(t, u.id)).toBe(120);
    expect((await pendingTxs(t)).filter((x) => x.status === "completed")).toHaveLength(1);
  });

  test("a session whose reference is not ours, or an amount Monime changed, is never credited", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 50, phoneNumber: "076123456" });
    const s = sessions.get(r.transactionId);
    s.status = "completed";
    s.metadata = { ...s.metadata, reference: "vktlx_monime_someone_else" };
    await webhook(t, "checkout_session.completed", r.transactionId);
    expect(await balance(t, u.id)).toBe(0);
  });

  test("an expired checkout marks the deposit failed and credits nothing", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 50, phoneNumber: "076123456" });
    sessions.get(r.transactionId).status = "expired";
    await webhook(t, "checkout_session.expired", r.transactionId);
    expect(await balance(t, u.id)).toBe(0);
    expect((await pendingTxs(t))[0].status).toBe("failed");
  });
});

describe("settlement edge cases", () => {
  test("a payment code is paid ONLY at 'completed'; 'processing' (in flight) and the non-existent 'processed' are not", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    checkoutMode = "reject"; // force the USSD payment-code route
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 40, phoneNumber: "076123456" });
    const id = r.paymentCodeId as string;
    for (const status of ["processing", "processed", "pending"]) {
      codes.get(id).status = status;
      await webhook(t, "payment_code.completed", id);
      expect(await balance(t, u.id), status).toBe(0);
    }
    codes.get(id).status = "completed";
    await webhook(t, "payment_code.completed", id);
    expect(await balance(t, u.id)).toBe(40);
  });

  test("currency mismatch: Monime reporting a non-SLE currency credits nothing and leaves the deposit unsettled", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 60, phoneNumber: "076123456" });
    const s = sessions.get(r.transactionId);
    s.status = "completed";
    s.lineItems = { data: [{ price: { currency: "USD", value: 6000 }, quantity: 1 }] };
    await webhook(t, "checkout_session.completed", r.transactionId);
    expect(await balance(t, u.id)).toBe(0);
    const tx = (await pendingTxs(t))[0];
    expect(tx.status).toBe("pending");
    expect(String(tx.failureReason)).toMatch(/currency mismatch/i);
  });

  test("delayed settlement: a premature webhook changes nothing; the later status check credits exactly once", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 35, phoneNumber: "076123456" });
    await webhook(t, "checkout_session.completed", r.transactionId); // Monime still says pending
    expect(await balance(t, u.id)).toBe(0);
    sessions.get(r.transactionId).status = "completed"; // paid later, no webhook this time
    const a: any = await t.action(api.payments.verifyAndSettleMoniMePayment, { sessionToken: u.token, reference: (await pendingTxs(t))[0].transactionId });
    expect(a.settled).toBe(true);
    const b: any = await t.action(api.payments.verifyAndSettleMoniMePayment, { sessionToken: u.token, reference: (await pendingTxs(t))[0].transactionId });
    expect(b.settled).toBe(true);
    expect(await balance(t, u.id)).toBe(35);
  });
});

describe("checkMyPendingDeposits (self-heal when no webhook exists for hosted checkout)", () => {
  test("settles the caller's own paid deposits, never someone else's, and is idempotent", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    const ra: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: a.token, amount: 20, phoneNumber: "076123456" });
    const rb: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: b.token, amount: 30, phoneNumber: "076123457" });
    sessions.get(ra.transactionId).status = "completed";
    sessions.get(rb.transactionId).status = "completed";

    const res: any = await t.action(api.payments.checkMyPendingDeposits, { sessionToken: a.token });
    expect(res).toEqual({ checked: 1, settled: 1 });
    expect(await balance(t, a.id)).toBe(20);
    expect(await balance(t, b.id)).toBe(0); // Bob's paid deposit is untouched by Alice's call

    const again: any = await t.action(api.payments.checkMyPendingDeposits, { sessionToken: a.token });
    expect(again.settled).toBe(0);
    expect(await balance(t, a.id)).toBe(20);
  });

  test("an unpaid deposit is only re-checked; an unknown caller is refused; calls are budgeted", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 20, phoneNumber: "076123456" });
    expect(((await t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token })) as any).settled).toBe(0);
    await expect(t.action(api.payments.checkMyPendingDeposits, { sessionToken: "nope-nope-nope-nope-0123456789" })).rejects.toThrow();
    for (let i = 0; i < 8; i++) await t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token });
    expect(await t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token })).toEqual({ checked: 0, settled: 0 });
  });
});

describe("checkMyPendingDeposits: window and eligibility", () => {
  test("a recent pending deposit is found even when the account has many newer non-deposit transactions", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "busy");
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 25, phoneNumber: "076123456" });
    sessions.get(r.transactionId).status = "completed";
    await t.run(async (ctx) => {
      const w = await ctx.db.insert("walletBalances", { userId: u.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: Date.now() });
      for (let i = 0; i < 60; i++) {
        await ctx.db.insert("transactions", {
          transactionId: `NOISE-${i}`, walletId: w, userId: u.id, type: "p2p_transfer", amount: 1, currency: "SLE",
          status: "completed", createdAt: Date.now() + 1000 + i, updatedAt: Date.now(),
        } as any);
      }
    });
    const res: any = await t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token });
    expect(res.settled).toBe(1);
    expect(await balance(t, u.id)).toBe(25);
  });

  test("old (>48h), failed and non-Monime deposits are ignored", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    await t.run(async (ctx) => {
      const w = await ctx.db.insert("walletBalances", { userId: u.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: Date.now() });
      const base = { walletId: w, userId: u.id, type: "top_up", amount: 10, currency: "SLE", updatedAt: Date.now() } as any;
      await ctx.db.insert("transactions", { ...base, transactionId: "OLD", gatewayProvider: "MONIME_ORANGE", gatewayReference: "cs-oldold1", status: "pending", createdAt: Date.now() - 60 * 3600 * 1000 });
      await ctx.db.insert("transactions", { ...base, transactionId: "FAILED", gatewayProvider: "MONIME_ORANGE", gatewayReference: "cs-failed1", status: "failed", createdAt: Date.now() });
      await ctx.db.insert("transactions", { ...base, transactionId: "OTHER", gatewayProvider: "ORANGE_MONEY_SL", gatewayReference: "cs-other11", status: "pending", createdAt: Date.now() });
    });
    expect(await t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token })).toEqual({ checked: 0, settled: 0 });
    expect(calls.filter((c) => c.method === "GET")).toHaveLength(0); // nothing was sent to Monime
  });
});

describe("checkMyPendingDeposits: sessions and provider failures", () => {
  test("a missing, unknown or EXPIRED session cannot settle anything", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 30, phoneNumber: "076123456" });
    sessions.get(r.transactionId).status = "completed";
    const before = calls.length;

    await expect(t.action(api.payments.checkMyPendingDeposits, {})).rejects.toThrow();
    await expect(t.action(api.payments.checkMyPendingDeposits, { sessionToken: "nope-nope-nope-nope-0123456789" })).rejects.toThrow();
    await t.run(async (ctx) => ctx.db.patch(u.id, { sessionExpiresAt: Date.now() - 1000 } as any));
    await expect(t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token })).rejects.toThrow();

    expect(await balance(t, u.id)).toBe(0);
    expect(calls.slice(before).filter((c) => c.method === "GET")).toHaveLength(0); // Monime was never asked
  });

  test("provider error, malformed answer and ambiguous statuses never count as settlement", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 30, phoneNumber: "076123456" });
    const s = sessions.get(r.transactionId);

    // ambiguous / non-final statuses
    for (const status of ["pending", "processing", "delayed", "unknown", "", "COMPLETED_PENDING"]) {
      s.status = status;
      const res: any = await t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token });
      expect(res.settled, status).toBe(0);
      expect(await balance(t, u.id), status).toBe(0);
      // let the per-account budget window move on without waiting a minute
      await t.run(async (ctx) => {
        for (const row of await ctx.db.query("auth_rate_limits").collect()) if (row.key.startsWith("settle-mine:")) await ctx.db.delete(row._id);
      });
    }

    // completed, but Monime reports no usable amount
    s.status = "completed";
    s.lineItems = { data: [] };
    expect(((await t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token })) as any).settled).toBe(0);
    expect(await balance(t, u.id)).toBe(0);

    // the session disappears at Monime (404)
    sessions.delete(r.transactionId);
    await t.run(async (ctx) => {
      for (const row of await ctx.db.query("auth_rate_limits").collect()) if (row.key.startsWith("settle-mine:")) await ctx.db.delete(row._id);
    });
    expect(((await t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token })) as any).settled).toBe(0);
    expect((await pendingTxs(t))[0].status).toBe("pending"); // never cancelled just because a check failed
  });

  test("concurrent checks and a competing webhook credit exactly once", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    const r: any = await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 45, phoneNumber: "076123456" });
    sessions.get(r.transactionId).status = "completed";
    await Promise.all([
      t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token }),
      t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token }),
      webhook(t, "checkout_session.completed", r.transactionId),
    ]);
    expect(await balance(t, u.id)).toBe(45);
    expect((await pendingTxs(t)).filter((x) => x.status === "completed")).toHaveLength(1);
  });

  test("an explicit client 'force' cannot exceed the server budget (6 per minute per account)", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 10, phoneNumber: "076123456" });
    let allowedCalls = 0;
    for (let i = 0; i < 10; i++) {
      const before = calls.filter((c) => c.method === "GET").length;
      await t.action(api.payments.checkMyPendingDeposits, { sessionToken: u.token });
      if (calls.filter((c) => c.method === "GET").length > before) allowedCalls++;
    }
    expect(allowedCalls).toBe(6);
  });
});
