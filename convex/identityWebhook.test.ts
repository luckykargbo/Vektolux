/// <reference types="vite/client" />
// eIDV (identity verification) webhook: signature, strict result validation, fail-closed defaults,
// idempotency, and "a finished check cannot be flipped by a later delivery".

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
const SECRET = "eidv-test-secret-0123456789abcdef";
const PATH = "/api/v1/verifications/webhook";
let seq = 0;

beforeEach(() => vi.stubEnv("EIDV_WEBHOOK_SECRET", SECRET));
afterEach(() => vi.unstubAllEnvs());

async function sign(body: string, secret = SECRET) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(body));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function setup(t: T) {
  seq += 1;
  const referenceId = `vkt_idv_test_${seq}`;
  const userId: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `idv${seq}@t.vx`, phone: `+2327660${String(seq).padStart(4, "0")}`, name: "Idv", role: "client",
      isVerified: false, isActive: true, verificationStatus: "pending", updatedAt: Date.now(),
    } as any)
  );
  const checkId = await t.run(async (ctx) =>
    ctx.db.insert("identity_checks", {
      userId, referenceId, documentType: "national_id", idNumberHash: `h${seq}`, status: "pending", provider: "smile_id",
      attemptNumber: 1, createdAt: Date.now(),
    } as any)
  );
  return { referenceId, userId, checkId };
}

const good = (referenceId: string, o: Record<string, unknown> = {}) => ({
  referenceId, isSuccess: true, livenessPassed: true, faceMatchScore: 0.93, livenessScore: 0.97, tamperCheckPassed: true,
  mrzValid: true, resultCode: "0810", ...o,
});
async function post(t: T, payload: unknown, opts: { sig?: string | null; eventId?: string; raw?: string } = {}) {
  const body = opts.raw ?? JSON.stringify(payload);
  const sig = opts.sig === undefined ? await sign(body) : opts.sig;
  return t.fetch(PATH, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(sig ? { "x-signature": sig } : {}),
      ...(opts.eventId ? { "x-event-id": opts.eventId } : {}),
    },
    body,
  });
}
const userOf = (t: T, id: Id<"users">) => t.run(async (ctx) => ctx.db.get(id)) as Promise<any>;
const checkOf = (t: T, id: any) => t.run(async (ctx) => ctx.db.get(id)) as Promise<any>;

describe("eIDV webhook: authentication", () => {
  test("missing, wrong and unset-secret signatures are rejected and change nothing", async () => {
    const t = convexTest(schema, modules);
    const s = await setup(t);
    expect((await post(t, good(s.referenceId), { sig: null })).status).toBe(401);
    expect((await post(t, good(s.referenceId), { sig: "0".repeat(64) })).status).toBe(403);
    expect((await post(t, good(s.referenceId), { sig: await sign(JSON.stringify(good(s.referenceId)), "other-secret-xxxxxxxxxx") })).status).toBe(403);
    vi.stubEnv("EIDV_WEBHOOK_SECRET", "");
    expect((await post(t, good(s.referenceId))).status).toBe(403);
    expect((await userOf(t, s.userId)).isVerified).toBe(false);
    expect((await checkOf(t, s.checkId)).status).toBe("pending");
  });

  test("a signature over a different body is rejected (no tampering of the score)", async () => {
    const t = convexTest(schema, modules);
    const s = await setup(t);
    const real = JSON.stringify(good(s.referenceId, { isSuccess: false, faceMatchScore: 0.1 }));
    const forged = JSON.stringify(good(s.referenceId));
    expect((await post(t, null, { raw: forged, sig: await sign(real) })).status).toBe(403);
    expect((await userOf(t, s.userId)).isVerified).toBe(false);
  });
});

describe("eIDV webhook: a pass needs every signal", () => {
  test("legitimate pass verifies the user", async () => {
    const t = convexTest(schema, modules);
    const s = await setup(t);
    const res = await post(t, good(s.referenceId));
    expect(res.status).toBe(200);
    expect((await res.json()).status).toBe("VERIFIED");
    const u = await userOf(t, s.userId);
    expect(u.isVerified).toBe(true);
    expect(u.verificationBadge).toBe("GREEN_TICK");
    expect((await checkOf(t, s.checkId)).faceMatchScore).toBe(0.93);
  });

  test.each([
    ["missing faceMatchScore", { faceMatchScore: undefined }],
    ["missing livenessPassed", { livenessPassed: undefined }],
    ["missing tamperCheckPassed", { tamperCheckPassed: undefined }],
  ])("%s on a claimed success is refused (422) and nothing is approved", async (_n, o) => {
    const t = convexTest(schema, modules);
    const s = await setup(t);
    const res = await post(t, good(s.referenceId, o));
    expect(res.status).toBe(422);
    expect((await userOf(t, s.userId)).isVerified).toBe(false);
    expect((await checkOf(t, s.checkId)).status).toBe("pending");
  });

  test.each([
    ["score above 1", { faceMatchScore: 1.5 }],
    ["negative score", { faceMatchScore: -0.2 }],
    ["string score", { faceMatchScore: "0.99" }],
    ["NaN-like score", { faceMatchScore: null }],
    ["non-boolean liveness", { livenessPassed: "true" }],
    ["non-boolean isSuccess", { isSuccess: "yes" }],
    ["tamper flag as number", { tamperCheckPassed: 1 }],
  ])("%s is malformed (422), never a pass", async (_n, o) => {
    const t = convexTest(schema, modules);
    const s = await setup(t);
    expect((await post(t, good(s.referenceId, o))).status).toBe(422);
    expect((await userOf(t, s.userId)).isVerified).toBe(false);
  });

  test("scores below the threshold, failed liveness or a failed tamper check reject the check", async () => {
    for (const o of [{ faceMatchScore: 0.84 }, { livenessPassed: false }, { tamperCheckPassed: false }]) {
      const t = convexTest(schema, modules);
      const s = await setup(t);
      const res = await post(t, good(s.referenceId, o));
      expect(res.status).toBe(200);
      expect((await res.json()).status).toBe("REJECTED");
      const u = await userOf(t, s.userId);
      expect(u.isVerified).toBe(false);
      expect(u.verificationStatus).toBe("rejected");
    }
  });

  test("a provider-reported failure without scores is a clean rejection (not a malformed delivery)", async () => {
    const t = convexTest(schema, modules);
    const s = await setup(t);
    const res = await post(t, { referenceId: s.referenceId, isSuccess: false, failureReason: "Document unreadable" });
    expect(res.status).toBe(200);
    expect((await res.json()).status).toBe("REJECTED");
    expect((await checkOf(t, s.checkId)).rejectionReason).toBe("Document unreadable");
  });

  test("malformed JSON and non-object bodies are refused", async () => {
    const t = convexTest(schema, modules);
    await setup(t);
    expect((await post(t, null, { raw: "{not json" })).status).toBe(400);
    expect((await post(t, null, { raw: "[1,2]" })).status).toBe(422);
    expect((await post(t, {})).status).toBe(422);
  });
});

describe("eIDV webhook: idempotency, finality and information hygiene", () => {
  test("the same event id replayed is handled once", async () => {
    const t = convexTest(schema, modules);
    const s = await setup(t);
    const first = await (await post(t, good(s.referenceId), { eventId: "evt-1" })).json();
    const again = await (await post(t, good(s.referenceId), { eventId: "evt-1" })).json();
    expect(first.alreadyHandled).toBe(false);
    expect(again.alreadyHandled).toBe(true);
    const logs = await t.run(async (ctx) => ctx.db.query("verifications_log").collect());
    expect(logs).toHaveLength(1);
  });

  test("a finished check cannot be flipped by a later, differently-keyed delivery", async () => {
    const t = convexTest(schema, modules);
    const s = await setup(t);
    await post(t, good(s.referenceId), { eventId: "evt-a" });
    const flip = await post(t, good(s.referenceId, { isSuccess: false, failureReason: "late" }), { eventId: "evt-b" });
    expect(flip.status).toBe(200);
    expect((await flip.json()).status).toBe("IGNORED");
    const u = await userOf(t, s.userId);
    expect(u.isVerified).toBe(true);
    expect((await checkOf(t, s.checkId)).status).toBe("verified");
  });

  test("an unknown reference gets a generic acknowledgement and no internal error text", async () => {
    const t = convexTest(schema, modules);
    const res = await post(t, good("vkt_idv_does_not_exist"));
    expect(res.status).toBe(200);
    const text = await res.text();
    expect(text).not.toMatch(/not found|referenceId|Error/i);
  });

  test("stored diagnostics hold scores only, not the raw provider body", async () => {
    const t = convexTest(schema, modules);
    const s = await setup(t);
    await post(t, good(s.referenceId, { documentNumber: "SL-SECRET-123", fullName: "A Person" }));
    const log: any = await t.run(async (ctx) => ctx.db.query("verifications_log").first());
    expect(log.diagnosticPayload).not.toContain("SL-SECRET-123");
    expect(log.diagnosticPayload).not.toContain("A Person");
  });
});
