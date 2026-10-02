/// <reference types="vite/client" />
// Identity, roles and privacy: no account takeover, no self-promotion, no fake badges.

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;

const GOOGLE_AUD = "489916570762-vfc729r27jha8q4s0o55piskj5a67bv3.apps.googleusercontent.com";
const APPLE_AUD = "com.vektolux.app";

async function makeUser(t: T, name: string, role: string = "client", email?: string) {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: email ?? `${name}${seq}@test.vektolux`,
      phone: `+2327500${String(1000 + seq)}`,
      name,
      role: role as any,
      isVerified: false,
      isActive: true,
      sessionToken: token,
      updatedAt: Date.now(),
    })
  );
  return { id, token };
}

// ── fake Google tokeninfo + Apple JWKS ──────────────────────────────
const googleTokens = new Map<string, any>();
let appleJwks: any = { keys: [] };

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlJson = (o: any) => b64url(new TextEncoder().encode(JSON.stringify(o)));

async function appleKeyPair() {
  const kp = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"]
  )) as CryptoKeyPair;
  const jwk: any = await crypto.subtle.exportKey("jwk", kp.publicKey);
  appleJwks = { keys: [{ ...jwk, kid: "test-kid", alg: "RS256", use: "sig" }] };
  return kp;
}

async function appleToken(kp: CryptoKeyPair, claims: any) {
  const h = b64urlJson({ alg: "RS256", kid: "test-kid" });
  const p = b64urlJson({ iss: "https://appleid.apple.com", aud: APPLE_AUD, exp: Math.floor(Date.now() / 1000) + 600, ...claims });
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", kp.privateKey, new TextEncoder().encode(`${h}.${p}`)));
  return `${h}.${p}.${b64url(sig)}`;
}

function googleToken(claims: any) {
  const tok = `${b64urlJson({ alg: "RS256" })}.${b64urlJson({ n: seq++ })}.sig${seq}`;
  googleTokens.set(tok, {
    iss: "https://accounts.google.com",
    aud: GOOGLE_AUD,
    exp: String(Math.floor(Date.now() / 1000) + 600),
    email_verified: "true",
    ...claims,
  });
  return tok;
}

beforeEach(() => {
  googleTokens.clear();
  vi.stubGlobal("fetch", async (url: string) => {
    const u = String(url);
    const json = (status: number, body: any) => new Response(JSON.stringify(body), { status });
    if (u.startsWith("https://oauth2.googleapis.com/tokeninfo")) {
      const tok = decodeURIComponent(u.split("id_token=")[1] ?? "");
      const c = googleTokens.get(tok);
      return c ? json(200, c) : json(400, { error: "invalid_token" });
    }
    if (u === "https://appleid.apple.com/auth/keys") return json(200, appleJwks);
    return json(404, {});
  });
});
afterEach(() => vi.unstubAllGlobals());

const social = (t: T, provider: string, providerId: string, email = "attacker-chosen@evil.test") =>
  t.action(api.users.socialSignIn, { provider, providerId, email });

// ─────────────────────────────────────────────────────────────────────
describe("social sign-in requires a provider-verified ID token", () => {
  test("knowing someone's email is NOT enough to sign in as them", async () => {
    const t = convexTest(schema, modules);
    const victim = await makeUser(t, "victim", "admin", "victim@vektolux.com");
    // Old attack: send the victim's email with any 'providerId'.
    await expect(social(t, "google", "not-a-token", "victim@vektolux.com")).rejects.toThrow(/could not be verified/i);
    // A real Google token for a DIFFERENT person cannot reach the victim's account either.
    const tok = googleToken({ sub: "g-attacker", email: "attacker@gmail.com" });
    const r: any = await social(t, "google", tok, "victim@vektolux.com");
    expect(r.userId).not.toBe(victim.id);
    expect(r.user.role).toBe("client");
    expect(r.user.email).toBe("attacker@gmail.com");
    const v = await t.run(async (ctx) => ctx.db.get(victim.id));
    expect(v?.sessionToken).toBe(victim.token); // victim's session untouched
  });

  test("a verified Google identity signs in (and links to an account with the same VERIFIED email)", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "client", "owner@gmail.com");
    const tok = googleToken({ sub: "g-owner", email: "owner@gmail.com" });
    const r: any = await social(t, "google", tok);
    expect(r.userId).toBe(owner.id);
    expect(r.sessionToken).toBeTruthy();
    // Next time the stable subject id is used, even if the email changes.
    const tok2 = googleToken({ sub: "g-owner", email: "renamed@gmail.com" });
    const r2: any = await social(t, "google", tok2);
    expect(r2.userId).toBe(owner.id);
  });

  test("an UNverified Google email never links to an existing account", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "client", "owner@gmail.com");
    const tok = googleToken({ sub: "g-other", email: "owner@gmail.com", email_verified: "false" });
    const r: any = await social(t, "google", tok);
    expect(r.userId).not.toBe(owner.id);
  });

  test("a token issued for another application is refused", async () => {
    const t = convexTest(schema, modules);
    const tok = googleToken({ sub: "g-x", email: "x@gmail.com", aud: "someone-elses-client-id.apps.googleusercontent.com" });
    await expect(social(t, "google", tok)).rejects.toThrow(/different application/i);
  });

  test("Apple: a correctly signed token signs in; a tampered or wrong-key token is refused", async () => {
    const t = convexTest(schema, modules);
    const kp = await appleKeyPair();
    const good = await appleToken(kp, { sub: "apple-sub-1", email: "a@privaterelay.appleid.com", email_verified: "true" });
    const r: any = await social(t, "apple", good);
    expect(r.user.role).toBe("client");
    expect(r.user.isVerified).toBe(false); // social login is not KYC

    const [h, , s] = good.split(".");
    const forgedPayload = b64urlJson({ iss: "https://appleid.apple.com", aud: APPLE_AUD, exp: Math.floor(Date.now() / 1000) + 600, sub: "apple-sub-VICTIM" });
    await expect(social(t, "apple", `${h}.${forgedPayload}.${s}`)).rejects.toThrow(/could not be verified/i);

    const other = (await crypto.subtle.generateKey(
      { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
      true, ["sign", "verify"]
    )) as CryptoKeyPair;
    const wrongKey = await appleToken(other, { sub: "apple-sub-2" });
    await expect(social(t, "apple", wrongKey)).rejects.toThrow(/could not be verified/i);
  });

  test("unknown providers are refused", async () => {
    const t = convexTest(schema, modules);
    await expect(social(t, "facebook", "x.y.z")).rejects.toThrow(/unsupported/i);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("roles and privileges", () => {
  test("self-registration can never create an administrator", async () => {
    const t = convexTest(schema, modules);
    const r: any = await t.mutation(api.auth.registerUser, {
      name: "Mallory", email: "mallory@test.vektolux", phone: "+23276999001", password: "Str0ng!Passw0rd", role: "admin",
    });
    expect(r.success).toBe(true);
    const u = await t.run(async (ctx) => ctx.db.get(r.userId as Id<"users">));
    expect(u?.role).not.toBe("admin");
  });

  test("identity verification submission is a review request — no automatic badge", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "kyc");
    const r: any = await t.mutation(api.verification.mockCompleteVerification, {
      userId: u.id, sessionToken: u.token, documentType: "national_id", idNumber: "SL123456",
    });
    expect(r.status).toBe("pending");
    expect(r.badge).toBe("NONE");
    const row = await t.run(async (ctx) => ctx.db.get(u.id));
    expect(row?.isVerified).toBe(false);
    expect(row?.verificationBadge).toBeUndefined();
  });

  test("a user cannot change another user's profile or phone", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await expect(
      t.mutation(api.users.updateUserProfile, { userId: a.id, sessionToken: b.token, name: "pwned" })
    ).rejects.toThrow(/another user/i);
    await expect(t.mutation(api.users.updateUserProfile, { userId: a.id, name: "pwned" })).rejects.toThrow(/authentication/i);
    await expect(
      t.mutation(api.users.linkPhoneNumber, { userId: a.id, sessionToken: b.token, phoneNumber: "+23276000999" })
    ).rejects.toThrow(/another user/i);
    const row = await t.run(async (ctx) => ctx.db.get(a.id));
    expect(row?.name).toBe("alice");
  });

  test("private profile fields are only returned to the owner", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    const asOther: any = await t.query(api.users.getUserById, { userId: a.id, sessionToken: b.token });
    expect(asOther.email).toBe("");
    expect(asOther.phone).toBe("");
    const anon: any = await t.query(api.users.getUserById, { userId: a.id });
    expect(anon.phone).toBe("");
    const self: any = await t.query(api.users.getUserById, { userId: a.id, sessionToken: a.token });
    expect(self.phone).toContain("+2327500");
  });

  test("only admins can broadcast notifications or read device tokens", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "user");
    const admin = await makeUser(t, "admin", "admin");
    const n = { targetType: "all_users" as any, title: "Win money", body: "click here" };
    await expect(t.mutation(api.notifications.createNotificationRecord, { ...n, sessionToken: u.token } as any)).rejects.toThrow(/administrator/i);
    await expect(t.mutation(api.notifications.createNotificationRecord, n as any)).rejects.toThrow(/authentication/i);
    await expect(t.query(api.notifications.getUserTokens, { userId: u.id, sessionToken: u.token } as any)).rejects.toThrow(/administrator/i);
    await t.mutation(api.notifications.createNotificationRecord, { ...n, sessionToken: admin.token } as any);
  });

  test("users read only their own notifications", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await expect(
      t.query(api.notifications.getUserNotifications, { userId: a.id, sessionToken: b.token } as any)
    ).rejects.toThrow(/another user/i);
  });

  test("only the hotel owner can change its rooms and prices", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "hotel_operator");
    const attacker = await makeUser(t, "attacker");
    const hotelId = await t.run(async (ctx) =>
      ctx.db.insert("hotel_profiles", {
        userId: owner.id, businessName: "H", operationalType: "hotel", isVerified: true, verificationStatus: "verified",
        address: "a", city: "Freetown", phone: "+23276000000", amenities: [], mediaUrls: [], description: "d",
        supportsHourlyStays: false, updatedAt: Date.now(),
      })
    );
    await expect(
      t.mutation(api.hotels.addRoom, {
        sessionToken: attacker.token, hotelId, name: "Fake", roomType: "Standard", pricePerNight: 1,
        supportsHourly: false, capacityGuests: 1, bedConfiguration: "x", amenities: [], images: [], totalRoomUnits: 1,
      } as any)
    ).rejects.toThrow(/permission/i);
  });

  test("only admins can take down a vehicle listing", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "user");
    await expect(
      t.mutation(api.mobility.takeDownListing, { listingId: "x", reason: "spite", sessionToken: u.token } as any)
    ).rejects.toThrow(/administrator/i);
  });
});
