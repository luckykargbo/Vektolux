/// <reference types="vite/client" />
// The public HTTP surface exposes only provider webhooks; the removed unauthenticated endpoints
// (including two "escrow webhooks" that marked escrows funded for anyone) must stay gone.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);

const REMOVED = [
  "/api/webhooks/orange-money-escrow",
  "/api/webhooks/africell-escrow",
  "/api/v1/vehicles/escrow/initiate",
  "/api/v1/vehicles/escrow/release-milestone",
  "/api/v1/real-estate/escrow/initiate",
  "/api/v1/real-estate/escrow/land-milestone/verify",
  "/payments/initialize",
  "/api/payments/topup",
];

describe("http surface", () => {
  test.each(REMOVED)("%s is not routed", async (path) => {
    const t = convexTest(schema, modules);
    const res = await t.fetch(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ orderCode: "ESC-1", transactionId: "x", amount: 100, status: "SUCCESS" }),
    });
    expect(res.status).toBe(404);
  });

  test("wallet-profile lookup by userId is gone", async () => {
    const t = convexTest(schema, modules);
    const res = await t.fetch("/api/user/wallet-profile?userId=abc", { method: "GET" });
    expect(res.status).toBe(404);
  });

  test("webhooks grant no cross-origin browser access (whatever the outcome)", async () => {
    const t = convexTest(schema, modules);
    const send = () =>
      t.fetch("/webhooks/monime", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ event: { name: "noop" }, object: { id: "x" } }),
      });
    // no secret configured: refused (fail closed)
    delete process.env.MONIME_WEBHOOK_SECRET;
    const a = await send();
    expect(a.status).toBe(503);
    expect(a.headers.get("access-control-allow-origin")).toBeNull();
    // secret configured, unsigned request: refused
    process.env.MONIME_WEBHOOK_SECRET = "synthetic-http-surface-secret-0123456789-abcdef";
    try {
      const b = await send();
      expect(b.status).toBe(401);
      expect(b.headers.get("access-control-allow-origin")).toBeNull();
    } finally {
      delete process.env.MONIME_WEBHOOK_SECRET;
    }
  });

  test("the removed Paystack/Flutterwave webhook route no longer exists", async () => {
    const t = convexTest(schema, modules);
    const res = await t.fetch("/payments/webhook", {
      method: "POST",
      headers: { "content-type": "application/json", "verif-hash": "anything" },
      body: JSON.stringify({ data: { tx_ref: "vktlx_x_1", status: "successful", amount: 1 } }),
    });
    expect(res.status).toBe(404);
  });
});
