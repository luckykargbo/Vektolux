/// <reference types="vite/client" />
// Identity, roles and privacy: no account takeover, no self-promotion, no fake badges.

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { hashWalletPin } from "./lib/pin";
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

const social = (t: T, provider: string, providerId: string, email = "attacker-chosen@evil.test", nonce?: string) =>
  t.action(api.users.socialSignIn, { provider, providerId, email, ...(nonce ? { nonce } : {}) });

/** An Apple identity token that carries a server-issued nonce, plus the raw nonce to send with it. */
async function appleAttempt(t: T, kp: CryptoKeyPair, claims: any) {
  const ch: any = await t.mutation(api.users.createOAuthChallenge, { provider: "apple" });
  const token = await appleToken(kp, { email_verified: "true", ...claims, nonce: ch.nonceHash });
  return { token, nonce: ch.nonce as string, nonceHash: ch.nonceHash as string };
}

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

  test("a Google identity with the SAME verified email does NOT sign in to the existing account", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "client", "owner@gmail.com");
    const tok = googleToken({ sub: "g-owner", email: "owner@gmail.com" });
    const r: any = await social(t, "google", tok);
    expect(r.blocked).toBe(true);
    expect(r.code).toBe("ACCOUNT_LINK_REQUIRED");
    expect(r.sessionToken).toBeUndefined();
    const after = await t.run(async (ctx) => ctx.db.get(owner.id));
    expect(after?.sessionToken).toBe(owner.token);
    expect(after?.externalAuthId).toBeUndefined();
  });

  test("an already-linked Google identity keeps signing in by its stable subject id, even if the email changes", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "client", "owner@gmail.com");
    await t.run(async (ctx) => ctx.db.patch(owner.id, { authProvider: "google", externalAuthId: "g-owner" }));
    const r: any = await social(t, "google", googleToken({ sub: "g-owner", email: "owner@gmail.com" }));
    expect(r.userId).toBe(owner.id);
    expect(r.sessionToken).toBeTruthy();
    const r2: any = await social(t, "google", googleToken({ sub: "g-owner", email: "renamed@gmail.com" }));
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

  test("Apple: a correctly signed token with the server nonce signs in; tampered or wrong-key tokens are refused", async () => {
    const t = convexTest(schema, modules);
    const kp = await appleKeyPair();
    const good = await appleAttempt(t, kp, { sub: "apple-sub-1", email: "a@privaterelay.appleid.com" });
    const r: any = await social(t, "apple", good.token, undefined, good.nonce);
    expect(r.user.role).toBe("client");
    expect(r.user.isVerified).toBe(false); // social login is not KYC

    const [h, , sg] = good.token.split(".");
    const forgedPayload = b64urlJson({ iss: "https://appleid.apple.com", aud: APPLE_AUD, exp: Math.floor(Date.now() / 1000) + 600, sub: "apple-sub-VICTIM", nonce: good.nonceHash });
    const again = await appleAttempt(t, kp, { sub: "x" });
    await expect(social(t, "apple", `${h}.${forgedPayload}.${sg}`, undefined, again.nonce)).rejects.toThrow(/could not be verified/i);

    const other = (await crypto.subtle.generateKey(
      { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
      true, ["sign", "verify"]
    )) as CryptoKeyPair;
    const ch: any = await t.mutation(api.users.createOAuthChallenge, { provider: "apple" });
    const wrongKey = await appleToken(other, { sub: "apple-sub-2", nonce: ch.nonceHash });
    await expect(social(t, "apple", wrongKey, undefined, ch.nonce)).rejects.toThrow(/could not be verified/i);
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

// ──────────────────────────────────────────────────────
// Phase 0 / Task 2: account-takeover protection
// ──────────────────────────────────────────────────────
const PASSWORD = "Correct-Horse-9";
const VICTIM_EMAIL = "victim@gmail.com";

async function registerPasswordAccount(t: T, email = VICTIM_EMAIL, phone = "+23277000111") {
  const r: any = await t.mutation(api.auth.registerUser, { name: "Victim Verified", email, phone, password: PASSWORD, role: "client" });
  expect(r.success).toBe(true);
  return { id: r.userId as Id<"users">, token: r.sessionToken as string };
}

/** Everything the blocked attempt must leave untouched. */
const snapshot = (t: T) =>
  t.run(async (ctx) => ({
    users: await ctx.db.query("users").collect(),
    wallets: await ctx.db.query("walletBalances").collect(),
    escrows: await ctx.db.query("escrow_orders").collect(),
    vehicles: await ctx.db.query("vehicleListings").collect(),
    properties: await ctx.db.query("realEstateListings").collect(),
    identities: await ctx.db.query("auth_identities").collect(),
  }));

/** A password account whose email ownership is already proven (so it may link providers). */
async function verifiedPasswordAccount(t: T, email = VICTIM_EMAIL, phone = "+23277000111") {
  const u = await registerPasswordAccount(t, email, phone);
  await t.run(async (ctx) => ctx.db.patch(u.id, { emailVerifiedAt: Date.now() }));
  return u;
}

/** Gives the victim a verified identity, a listing-owning counterparty and a REAL escrow order. */
async function seedVictimAssets(t: T, userId: Id<"users">, token: string) {
  const owner = await makeUser(t, "dealer", "merchant");
  const vehicleId = await t.run(async (ctx) =>
    ctx.db.insert("vehicleListings", {
      ownerId: owner.id, title: "Toyota Hilux", category: "car_rental", price: 100, pricingType: "per_day", images: [],
      createdAt: Date.now(), location: "Bo", latitude: 0, longitude: 0, geohash: "", status: "AVAILABLE", isPublished: true, updatedAt: Date.now(),
    } as any)
  );
  await t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount: 5000, provider: "TEST", providerReference: `seed-${userId}` });
  await t.run(async (ctx) =>
    ctx.db.patch(userId, { name: "Victim Verified", isVerified: true, verificationStatus: "verified", role: "agent" } as any)
  );
  const order: any = await t.mutation(api.escrow.initiateEscrowOrder, {
    sessionToken: token, orderType: "VEHICLE_RENTAL", vehicleListingId: vehicleId, numberOfDays: 3, payFromWallet: true,
  } as any);
  expect(order.status).toBe("HELD_IN_ESCROW");
}

describe("Google: takeover protection", () => {
  test("a new Google identity creates a new, linked, verified-email client account", async () => {
    const t = convexTest(schema, modules);
    const r: any = await social(t, "google", googleToken({ sub: "g-new", email: "fresh@gmail.com" }));
    expect(r.sessionToken).toBeTruthy();
    expect(r.user.role).toBe("client");
    expect(r.user.isVerified).toBe(false);
    expect(r.emailVerified).toBe(true);
    const idRows = await t.run(async (ctx) => ctx.db.query("auth_identities").collect());
    expect(idRows).toHaveLength(1);
    expect(idRows[0]).toMatchObject({ provider: "google", subject: "g-new", userId: r.userId });
    // …and that identity signs straight back in.
    const again: any = await social(t, "google", googleToken({ sub: "g-new", email: "fresh@gmail.com" }));
    expect(again.userId).toBe(r.userId);
  });

  test("SECURITY BOUNDARY: a Google identity with the victim's email cannot become the victim; nothing changes", async () => {
    const t = convexTest(schema, modules);
    const victim = await registerPasswordAccount(t);
    await seedVictimAssets(t, victim.id, victim.token);
    const before = await snapshot(t);
    expect(before.escrows).toHaveLength(1); // a real escrow order is part of what must not change
    expect(before.wallets.some((w) => (w.escrowBalance ?? 0) > 0)).toBe(true);
    expect(before.vehicles).toHaveLength(1);

    const attacker = googleToken({ sub: "g-attacker", email: VICTIM_EMAIL, email_verified: "true" });
    const r: any = await social(t, "google", attacker);
    expect(r.blocked).toBe(true);
    expect(r.sessionToken).toBeUndefined();
    expect(r.userId).toBeUndefined();
    expect(String(r.message)).toMatch(/sign in with your vektolux password/i);

    expect(await snapshot(t)).toEqual(before); // password, email, name, phone, sessions, role, wallet, escrow, listings
    const u: any = await t.run(async (ctx) => ctx.db.get(victim.id));
    expect(u.sessionToken).toBe(victim.token);
    expect(u.name).toBe("Victim Verified");
    // the genuine owner can still sign in with the password
    const login: any = await t.mutation(api.auth.loginWithPhoneOrEmail, { identifier: VICTIM_EMAIL, password: PASSWORD });
    expect(login.success).toBe(true);
    expect(login.userId).toBe(victim.id);
    // The blocked identity did not become linked: trying again is still blocked.
    const again: any = await social(t, "google", googleToken({ sub: "g-attacker", email: VICTIM_EMAIL }));
    expect(again.blocked).toBe(true);
  });

  test("a replayed Google token is refused", async () => {
    const t = convexTest(schema, modules);
    const tok = googleToken({ sub: "g-replay", email: "replay@gmail.com" });
    await social(t, "google", tok);
    await expect(social(t, "google", tok)).rejects.toThrow(/could not be verified/i);
  });

  test("explicit linking: the signed-in owner can link Google, and then signs in with it", async () => {
    const t = convexTest(schema, modules);
    const victim = await verifiedPasswordAccount(t);
    const tok = googleToken({ sub: "g-owner-link", email: "different-mailbox@gmail.com" });
    const link: any = await t.action(api.users.linkSocialIdentity, { sessionToken: victim.token, provider: "google", providerId: tok, currentPin: PASSWORD });
    expect(link.success).toBe(true);
    const r: any = await social(t, "google", googleToken({ sub: "g-owner-link", email: "different-mailbox@gmail.com" }));
    expect(r.userId).toBe(victim.id);
  });

  test("linking needs a valid session, and cannot steal an identity already linked elsewhere", async () => {
    const t = convexTest(schema, modules);
    const a = await verifiedPasswordAccount(t, "a@gmail.com", "+23277000211");
    const b = await verifiedPasswordAccount(t, "b@gmail.com", "+23277000212");
    await expect(
      t.action(api.users.linkSocialIdentity, { sessionToken: "not-a-session-token-0123456789abcdef", provider: "google", providerId: googleToken({ sub: "g-x", email: "x@gmail.com" }) })
    ).rejects.toThrow();
    const ok: any = await t.action(api.users.linkSocialIdentity, { sessionToken: a.token, provider: "google", providerId: googleToken({ sub: "g-shared", email: "x@gmail.com" }), currentPin: PASSWORD });
    expect(ok.success).toBe(true);
    const stolen: any = await t.action(api.users.linkSocialIdentity, { sessionToken: b.token, provider: "google", providerId: googleToken({ sub: "g-shared", email: "x@gmail.com" }), currentPin: PASSWORD });
    expect(stolen.success).toBe(false);
    expect(stolen.errorCode).toBe("ALREADY_LINKED");
    // a second, different Google account cannot be stacked onto the same Vektolux account
    const second: any = await t.action(api.users.linkSocialIdentity, { sessionToken: a.token, provider: "google", providerId: googleToken({ sub: "g-other", email: "y@gmail.com" }), currentPin: PASSWORD });
    expect(second.errorCode).toBe("PROVIDER_ALREADY_LINKED");
  });
});

describe("Apple: takeover protection and nonce", () => {
  test("a new Apple identity (with the server nonce) creates a new account", async () => {
    const t = convexTest(schema, modules);
    const kp = await appleKeyPair();
    const a = await appleAttempt(t, kp, { sub: "apple-new", email: "fresh@icloud.com" });
    const r: any = await social(t, "apple", a.token, undefined, a.nonce);
    expect(r.sessionToken).toBeTruthy();
    expect(r.user.email).toBe("fresh@icloud.com");
    expect(r.user.role).toBe("client");
  });

  test("SECURITY BOUNDARY: an Apple identity with the victim's email cannot become the victim; nothing changes", async () => {
    const t = convexTest(schema, modules);
    const kp = await appleKeyPair();
    const victim = await registerPasswordAccount(t);
    await seedVictimAssets(t, victim.id, victim.token);
    const before = await snapshot(t);

    const a = await appleAttempt(t, kp, { sub: "apple-attacker", email: VICTIM_EMAIL });
    const r: any = await social(t, "apple", a.token, undefined, a.nonce);
    expect(r.blocked).toBe(true);
    expect(r.sessionToken).toBeUndefined();
    expect(await snapshot(t)).toEqual(before);
    const login: any = await t.mutation(api.auth.loginWithPhoneOrEmail, { identifier: VICTIM_EMAIL, password: PASSWORD });
    expect(login.userId).toBe(victim.id);
  });

  test("an already-linked Apple identity signs in even when Apple sends no email the second time", async () => {
    const t = convexTest(schema, modules);
    const kp = await appleKeyPair();
    const owner = await verifiedPasswordAccount(t);
    const first = await appleAttempt(t, kp, { sub: "apple-linked", email: "abc@privaterelay.appleid.com" });
    const link: any = await t.action(api.users.linkSocialIdentity, { sessionToken: owner.token, provider: "apple", providerId: first.token, nonce: first.nonce, currentPin: PASSWORD });
    expect(link.success).toBe(true);
    const later = await appleAttempt(t, kp, { sub: "apple-linked" }); // no email claim
    const r: any = await social(t, "apple", later.token, undefined, later.nonce);
    expect(r.userId).toBe(owner.id);
    expect(r.user.email).toBe(VICTIM_EMAIL);
  });

  test("a missing, wrong, reused or foreign nonce is rejected", async () => {
    const t = convexTest(schema, modules);
    const kp = await appleKeyPair();

    // older client: no nonce at all. Refused (never weakened), with a clear upgrade message.
    const bare = await appleToken(kp, { sub: "apple-n1", email: "n1@icloud.com", email_verified: "true" });
    await expect(social(t, "apple", bare)).rejects.toThrow(/update the vektolux app/i);

    // token carries nonce A but the request sends raw nonce B
    const A = await appleAttempt(t, kp, { sub: "apple-n2", email: "n2@icloud.com" });
    const B: any = await t.mutation(api.users.createOAuthChallenge, { provider: "apple" });
    await expect(social(t, "apple", A.token, undefined, B.nonce)).rejects.toThrow(/could not be verified/i);

    // a made-up nonce the server never issued, hashed into the token by the attacker
    const fake = "ab".repeat(32);
    const fakeHash = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(fake)))).map((x) => x.toString(16).padStart(2, "0")).join("");
    const forged = await appleToken(kp, { sub: "apple-n3", email: "n3@icloud.com", email_verified: "true", nonce: fakeHash });
    await expect(social(t, "apple", forged, undefined, fake)).rejects.toThrow(/could not be verified/i);

    // a valid attempt works once; replaying the same token+nonce fails
    const ok = await appleAttempt(t, kp, { sub: "apple-n4", email: "n4@icloud.com" });
    await social(t, "apple", ok.token, undefined, ok.nonce);
    await expect(social(t, "apple", ok.token, undefined, ok.nonce)).rejects.toThrow(/could not be verified/i);

    // an expired nonce is refused
    const stale = await appleAttempt(t, kp, { sub: "apple-n5", email: "n5@icloud.com" });
    await t.run(async (ctx) => {
      for (const c of await ctx.db.query("oauth_challenges").collect()) await ctx.db.patch(c._id, { expiresAt: Date.now() - 1 });
    });
    await expect(social(t, "apple", stale.token, undefined, stale.nonce)).rejects.toThrow(/could not be verified/i);
  });

  test("a Google nonce challenge cannot be spent on Apple", async () => {
    const t = convexTest(schema, modules);
    const kp = await appleKeyPair();
    const g: any = await t.mutation(api.users.createOAuthChallenge, { provider: "google" });
    const tok = await appleToken(kp, { sub: "apple-x", email: "x@icloud.com", email_verified: "true", nonce: g.nonceHash });
    await expect(social(t, "apple", tok, undefined, g.nonce)).rejects.toThrow(/could not be verified/i);
  });
});

describe("existing linked accounts are preserved", () => {
  test("a legacy account linked through users.authProvider/externalAuthId keeps working and gains an identity row", async () => {
    const t = convexTest(schema, modules);
    const legacy = await makeUser(t, "legacy", "client", "legacy@gmail.com");
    await t.run(async (ctx) => ctx.db.patch(legacy.id, { authProvider: "google", externalAuthId: "g-legacy" }));
    const r: any = await social(t, "google", googleToken({ sub: "g-legacy", email: "legacy@gmail.com" }));
    expect(r.userId).toBe(legacy.id);
    const rows = await t.run(async (ctx) => ctx.db.query("auth_identities").collect());
    expect(rows.map((x) => x.subject)).toEqual(["g-legacy"]);
    // the provider just proved this mailbox, so ownership is now recorded
    const u: any = await t.run(async (ctx) => ctx.db.get(legacy.id));
    expect(u.emailVerifiedAt).toBeGreaterThan(0);
    expect(u.name).toBe("legacy");
  });
});

describe("linking: re-authentication, verified email, and failed attempts leave links untouched", () => {
  const link = (t: T, token: string, providerId: string, extra: Record<string, unknown> = {}) =>
    t.action(api.users.linkSocialIdentity, { sessionToken: token, provider: "google", providerId, ...extra } as any) as Promise<any>;
  const identities = (t: T) => t.run(async (ctx) => ctx.db.query("auth_identities").collect());

  test("PIN-configured account: missing and wrong PIN fail safely; the right PIN links", async () => {
    const t = convexTest(schema, modules);
    const u = await verifiedPasswordAccount(t);
    await t.run(async (ctx) => ctx.db.patch(u.id, { walletPinHash: await hashWalletPin(u.id, "4821") }));
    const tok = () => googleToken({ sub: "g-pin", email: "pin@gmail.com" });

    const missing = await link(t, u.token, tok());
    expect(missing).toMatchObject({ success: false, errorCode: "REQUIRED" });
    const wrong = await link(t, u.token, tok(), { currentPin: "0000" });
    expect(wrong).toMatchObject({ success: false, errorCode: "INVALID" });
    expect(await identities(t)).toHaveLength(0);
    const afterFail: any = await t.run(async (ctx) => ctx.db.get(u.id));
    expect(afterFail.pinFailedAttempts).toBe(1); // the attempt counter persisted (returned, not thrown)
    const uses = await t.run(async (ctx) => ctx.db.query("oauth_token_uses").collect());
    expect(uses).toHaveLength(0); // a refused attempt does not burn the provider token

    const ok = await link(t, u.token, tok(), { currentPin: "4821" });
    expect(ok.success).toBe(true);
    expect(await identities(t)).toHaveLength(1);
  });

  test("repeated wrong PINs lock the attempt; linking stays refused even with the right PIN", async () => {
    const t = convexTest(schema, modules);
    const u = await verifiedPasswordAccount(t);
    await t.run(async (ctx) => ctx.db.patch(u.id, { walletPinHash: await hashWalletPin(u.id, "4821") }));
    for (let i = 0; i < 5; i++) await link(t, u.token, googleToken({ sub: `g-l${i}`, email: "l@gmail.com" }), { currentPin: "0000" });
    const locked = await link(t, u.token, googleToken({ sub: "g-l-final", email: "l@gmail.com" }), { currentPin: "4821" });
    expect(locked).toMatchObject({ success: false, errorCode: "LOCKED" });
    expect(await identities(t)).toHaveLength(0);
  });

  test("a password account with no PIN must present its password", async () => {
    const t = convexTest(schema, modules);
    const u = await verifiedPasswordAccount(t);
    const missing = await link(t, u.token, googleToken({ sub: "g-pw", email: "pw@gmail.com" }));
    expect(missing.errorCode).toBe("REQUIRED");
    expect(missing.message).toMatch(/password/i);
    const wrong = await link(t, u.token, googleToken({ sub: "g-pw", email: "pw@gmail.com" }), { currentPin: "not-the-password" });
    expect(wrong.success).toBe(false);
    const ok = await link(t, u.token, googleToken({ sub: "g-pw", email: "pw@gmail.com" }), { currentPin: PASSWORD });
    expect(ok.success).toBe(true);
  });

  test("a social-only account (no PIN, no password) links with its session alone", async () => {
    const t = convexTest(schema, modules);
    const first: any = await social(t, "google", googleToken({ sub: "g-only", email: "only@gmail.com" }));
    const kp = await appleKeyPair();
    const a = await appleAttempt(t, kp, { sub: "apple-only", email: "only@gmail.com" });
    const r = await t.action(api.users.linkSocialIdentity, { sessionToken: first.sessionToken, provider: "apple", providerId: a.token, nonce: a.nonce });
    expect(r.success).toBe(true);
    expect((await identities(t)).map((x) => x.provider).sort()).toEqual(["apple", "google"]);
  });

  test("an unverified email cannot carry a new sign-in method, unless the provider proves that very address", async () => {
    const t = convexTest(schema, modules);
    const squatted = await registerPasswordAccount(t, "claimed@gmail.com", "+23277000311"); // never verified
    const refused = await link(t, squatted.token, googleToken({ sub: "g-squat", email: "attacker@gmail.com" }), { currentPin: PASSWORD });
    expect(refused).toMatchObject({ success: false, errorCode: "EMAIL_NOT_VERIFIED" });
    expect(await identities(t)).toHaveLength(0);
    const unchanged: any = await t.run(async (ctx) => ctx.db.get(squatted.id));
    expect(unchanged.emailVerifiedAt).toBeUndefined();

    // the provider verifying THIS address is proof of ownership
    const proven = await link(t, squatted.token, googleToken({ sub: "g-owner", email: "claimed@gmail.com" }), { currentPin: PASSWORD });
    expect(proven.success).toBe(true);
    const after: any = await t.run(async (ctx) => ctx.db.get(squatted.id));
    expect(after.emailVerifiedAt).toBeGreaterThan(0);
  });

  test("failed attempts leave every existing link and the account untouched", async () => {
    const t = convexTest(schema, modules);
    const a = await verifiedPasswordAccount(t, "a@gmail.com", "+23277000411");
    const b = await verifiedPasswordAccount(t, "b@gmail.com", "+23277000412");
    expect((await link(t, a.token, googleToken({ sub: "g-a", email: "a@gmail.com" }), { currentPin: PASSWORD })).success).toBe(true);
    const before = { ids: await identities(t), users: await t.run(async (ctx) => ctx.db.query("users").collect()) };

    await link(t, a.token, googleToken({ sub: "g-new", email: "a2@gmail.com" }), { currentPin: "wrong" }); // wrong secret
    await link(t, a.token, googleToken({ sub: "g-new", email: "a2@gmail.com" }), { currentPin: PASSWORD }); // second Google
    await link(t, b.token, googleToken({ sub: "g-a", email: "a@gmail.com" }), { currentPin: PASSWORD }); // someone else's identity
    const after = { ids: await identities(t), users: await t.run(async (ctx) => ctx.db.query("users").collect()) };
    expect(after.ids).toEqual(before.ids);
    // the only user-document change allowed is the wrong-PIN attempt counter
    const strip = (rows: any[]) => rows.map(({ pinFailedAttempts, ...r }) => r);
    expect(strip(after.users)).toEqual(strip(before.users));
  });

  test("getAccountSecurityStatus reports the real state, to the owner only", async () => {
    const t = convexTest(schema, modules);
    const u = await registerPasswordAccount(t);
    const s0: any = await t.query(api.users.getAccountSecurityStatus, { sessionToken: u.token });
    expect(s0).toEqual({ email: VICTIM_EMAIL, emailVerified: false, hasPin: false, hasPassword: true, linked: { google: false, apple: false } });
    await t.run(async (ctx) => ctx.db.patch(u.id, { emailVerifiedAt: Date.now(), authProvider: "google", externalAuthId: "g-legacy-status" }));
    const s1: any = await t.query(api.users.getAccountSecurityStatus, { sessionToken: u.token });
    expect(s1.emailVerified).toBe(true);
    expect(s1.linked).toEqual({ google: true, apple: false }); // legacy single-provider fields are honoured
    expect(JSON.stringify(s1)).not.toContain("g-legacy-status"); // no subject ids leave the server
    await expect(t.query(api.users.getAccountSecurityStatus, { sessionToken: "not-a-session-token-0123456789abcdef" })).rejects.toThrow();
  });
});
