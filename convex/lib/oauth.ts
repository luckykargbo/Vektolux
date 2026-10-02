// convex/lib/oauth.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Server-side verification of Google / Apple ID tokens.
//
// A social sign-in is only trusted after the provider's own signed ID token has been
// verified on the server. The client-supplied email / name are never used to decide WHO
// is signing in (previously any caller could obtain a session for any account by email).
//
// Allowed audiences (OAuth client IDs / bundle IDs are public identifiers, not secrets):
//   GOOGLE_OAUTH_CLIENT_IDS  comma-separated; defaults to the client ID the app ships with
//   APPLE_OAUTH_CLIENT_IDS   comma-separated; defaults to the app's current bundle ID
// ═══════════════════════════════════════════════════════════════════════

export type VerifiedIdentity = {
  provider: "google" | "apple";
  sub: string; // stable provider user id
  email?: string;
  emailVerified: boolean;
  name?: string;
};

// Public identifiers (also present in the Flutter app / web/index.html). Override via env.
const DEFAULT_GOOGLE_CLIENT_IDS = ["489916570762-vfc729r27jha8q4s0o55piskj5a67bv3.apps.googleusercontent.com"];
const DEFAULT_APPLE_CLIENT_IDS = ["com.vektolux.app"];

const JWT_SHAPE = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;

function allowedAudiences(envName: string, defaults: string[]): string[] {
  const raw = process.env[envName];
  if (!raw || !raw.trim()) return defaults;
  return raw.split(",").map((s) => s.trim()).filter(Boolean);
}

function b64urlToBytes(s: string): Uint8Array<ArrayBuffer> {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
  const out = new Uint8Array(new ArrayBuffer(bin.length));
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function decodeJson(seg: string): any {
  return JSON.parse(new TextDecoder().decode(b64urlToBytes(seg)));
}

const truthy = (v: unknown) => v === true || v === "true";

/** Verifies a Google ID token via Google's official tokeninfo endpoint (signature + expiry checked by Google). */
export async function verifyGoogleIdToken(idToken: string): Promise<VerifiedIdentity> {
  if (!JWT_SHAPE.test(idToken)) throw new Error("Google sign-in could not be verified.");
  const res = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`);
  if (!res.ok) throw new Error("Google sign-in could not be verified.");
  const c: any = await res.json();
  if (!allowedAudiences("GOOGLE_OAUTH_CLIENT_IDS", DEFAULT_GOOGLE_CLIENT_IDS).includes(String(c.aud))) {
    throw new Error("Google sign-in was issued for a different application.");
  }
  if (c.iss !== "accounts.google.com" && c.iss !== "https://accounts.google.com") {
    throw new Error("Google sign-in could not be verified.");
  }
  if (!(Number(c.exp) * 1000 > Date.now())) throw new Error("Google sign-in has expired. Please try again.");
  if (!c.sub) throw new Error("Google sign-in could not be verified.");
  return {
    provider: "google",
    sub: String(c.sub),
    email: c.email ? String(c.email).toLowerCase() : undefined,
    emailVerified: truthy(c.email_verified),
    name: c.name ? String(c.name) : undefined,
  };
}

/** Verifies an Apple identity token: RS256 signature against Apple's JWKS, issuer, audience, expiry. */
export async function verifyAppleIdToken(idToken: string): Promise<VerifiedIdentity> {
  if (!JWT_SHAPE.test(idToken)) throw new Error("Apple sign-in could not be verified.");
  const [h, p, sig] = idToken.split(".");
  let header: any;
  let payload: any;
  try {
    header = decodeJson(h);
    payload = decodeJson(p);
  } catch {
    throw new Error("Apple sign-in could not be verified.");
  }
  if (header.alg !== "RS256" || !header.kid) throw new Error("Apple sign-in could not be verified.");

  const jwksRes = await fetch("https://appleid.apple.com/auth/keys");
  if (!jwksRes.ok) throw new Error("Apple sign-in is temporarily unavailable. Please try again.");
  const jwks: any = await jwksRes.json();
  const jwk = (jwks.keys ?? []).find((k: any) => k.kid === header.kid);
  if (!jwk) throw new Error("Apple sign-in could not be verified.");

  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    b64urlToBytes(sig),
    new TextEncoder().encode(`${h}.${p}`)
  );
  if (!valid) throw new Error("Apple sign-in could not be verified.");

  if (payload.iss !== "https://appleid.apple.com") throw new Error("Apple sign-in could not be verified.");
  if (!allowedAudiences("APPLE_OAUTH_CLIENT_IDS", DEFAULT_APPLE_CLIENT_IDS).includes(String(payload.aud))) {
    throw new Error("Apple sign-in was issued for a different application.");
  }
  if (!(Number(payload.exp) * 1000 > Date.now())) throw new Error("Apple sign-in has expired. Please try again.");
  if (!payload.sub) throw new Error("Apple sign-in could not be verified.");
  return {
    provider: "apple",
    sub: String(payload.sub),
    email: payload.email ? String(payload.email).toLowerCase() : undefined,
    emailVerified: truthy(payload.email_verified),
  };
}
