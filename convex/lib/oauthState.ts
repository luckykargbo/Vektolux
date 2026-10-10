// convex/lib/oauthState.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — State for Google / Apple sign-in attempts.
//
//  • Nonce (Apple): the server issues a random nonce per attempt. The app hands Apple only its
//    SHA-256 (`nonceHash`); Apple signs that value into the identity token. The server later
//    receives the RAW nonce, so a token alone — without the raw value the server issued to this
//    attempt — is useless. Each nonce works once and expires after 5 minutes.
//  • Token replay (Google and Apple): an accepted ID token is recorded until it expires and can
//    never be accepted twice. (google_sign_in 6.x offers no nonce, so this is the replay defence
//    available for Google.)
//
// Everything here runs inside a mutation, so check-then-write is one serializable transaction.
// ═══════════════════════════════════════════════════════════════════════

import type { MutationCtx } from "../_generated/server";

export const OAUTH_NONCE_TTL_MS = 5 * 60 * 1000;
const PURGE_BATCH = 25;

export async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function randomHex(bytes = 32): string {
  const a = new Uint8Array(bytes);
  crypto.getRandomValues(a);
  return Array.from(a).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Deletes a bounded number of expired rows so the tables cannot grow without limit. */
export async function purgeExpiredOAuthState(ctx: Pick<MutationCtx, "db">, now = Date.now()): Promise<void> {
  const challenges = await ctx.db
    .query("oauth_challenges")
    .withIndex("by_expiresAt", (q) => q.lt("expiresAt", now))
    .take(PURGE_BATCH);
  for (const c of challenges) await ctx.db.delete(c._id);
  const tokens = await ctx.db
    .query("oauth_token_uses")
    .withIndex("by_expiresAt", (q) => q.lt("expiresAt", now))
    .take(PURGE_BATCH);
  for (const t of tokens) await ctx.db.delete(t._id);
}

/** Issues a fresh nonce for one sign-in attempt. The raw value is returned once and never stored. */
export async function issueChallenge(
  ctx: Pick<MutationCtx, "db">,
  provider: string,
  now = Date.now()
): Promise<{ nonce: string; nonceHash: string; expiresAt: number }> {
  const nonce = randomHex(32);
  const nonceHash = await sha256Hex(nonce);
  const expiresAt = now + OAUTH_NONCE_TTL_MS;
  await ctx.db.insert("oauth_challenges", { nonceHash, provider, expiresAt, createdAt: now });
  await purgeExpiredOAuthState(ctx, now);
  return { nonce, nonceHash, expiresAt };
}

/**
 * Burns the nonce for this provider. False when it is unknown, for another provider, already
 * used or expired — the caller must then refuse the sign-in.
 */
export async function consumeChallenge(
  ctx: Pick<MutationCtx, "db">,
  provider: string,
  rawNonce: string | undefined,
  now = Date.now()
): Promise<boolean> {
  if (!rawNonce || !/^[0-9a-f]{64}$/.test(rawNonce)) return false;
  const nonceHash = await sha256Hex(rawNonce);
  const row = await ctx.db.query("oauth_challenges").withIndex("by_nonceHash", (q) => q.eq("nonceHash", nonceHash)).first();
  if (!row || row.provider !== provider || row.usedAt !== undefined || row.expiresAt <= now) return false;
  await ctx.db.patch(row._id, { usedAt: now });
  return true;
}

export async function tokenAlreadyUsed(ctx: Pick<MutationCtx, "db">, provider: string, tokenHash: string): Promise<boolean> {
  const row = await ctx.db.query("oauth_token_uses").withIndex("by_tokenHash", (q) => q.eq("tokenHash", tokenHash)).first();
  return !!row && row.provider === provider;
}

export async function recordTokenUse(
  ctx: Pick<MutationCtx, "db">,
  provider: string,
  tokenHash: string,
  tokenExpiresAt: number,
  now = Date.now()
): Promise<void> {
  await ctx.db.insert("oauth_token_uses", { tokenHash, provider, expiresAt: Math.max(tokenExpiresAt, now + 60_000), usedAt: now });
}
