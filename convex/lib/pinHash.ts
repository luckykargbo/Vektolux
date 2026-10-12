// convex/lib/pinHash.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Wallet PIN hashing.
//
//   v2  "pin2$<iterations>$<saltHex>$<hashHex>"   PBKDF2-HMAC-SHA256, unique random 16-byte salt,
//                                                  bound to the account id. Work factor is stored per hash
//                                                  so it can be raised later without invalidating anyone.
//   v1  "0x<sha256hex>"                            LEGACY: SHA-256 of `wallet_pin_<userId>_<pin>`.
//                                                  Still VERIFIED so no customer is locked out; it is
//                                                  replaced by v2 the first time the right PIN is entered.
//
// A 4-6 digit PIN has a tiny search space, so the hash is only ever a speed bump for someone holding a
// database copy; the real protection is the server-side lockout (lib/pin.ts) and never exposing a
// "is this PIN right?" oracle. Plaintext PINs are never stored or logged.
// ═══════════════════════════════════════════════════════════════════════

export const PIN_HASH_VERSION = "pin2";
export const PIN_PBKDF2_ITERATIONS = 100_000;

const toHex = (buf: ArrayBuffer | Uint8Array) =>
  Array.from(buf instanceof Uint8Array ? buf : new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
const fromHex = (hex: string) => new Uint8Array((hex.match(/.{1,2}/g) ?? []).map((h) => parseInt(h, 16)));

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

async function pbkdf2(userId: string, pin: string, salt: Uint8Array, iterations: number): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(`${userId}:${pin}`), { name: "PBKDF2" }, false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: salt as unknown as BufferSource, iterations, hash: "SHA-256" },
    key,
    256
  );
  return toHex(bits);
}

/** A fresh v2 hash with a new random salt. */
export async function hashPin(userId: string, pin: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await pbkdf2(userId, pin, salt, PIN_PBKDF2_ITERATIONS);
  return `${PIN_HASH_VERSION}$${PIN_PBKDF2_ITERATIONS}$${toHex(salt)}$${hash}`;
}

async function legacySha256(userId: string, pin: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`wallet_pin_${userId}_${pin}`));
  return "0x" + toHex(buf);
}

export function isLegacyPinHash(stored: string): boolean {
  return !stored.startsWith(`${PIN_HASH_VERSION}$`);
}

/**
 * Checks `pin` against a stored hash of any supported version.
 * `needsUpgrade` is true when it matched a legacy hash (caller should store a fresh v2 hash) or a v2
 * hash made with a lower work factor than the current one.
 */
export async function verifyPinHash(
  userId: string,
  pin: string,
  stored: string | undefined
): Promise<{ valid: boolean; needsUpgrade: boolean }> {
  if (!stored) return { valid: false, needsUpgrade: false };
  if (stored.startsWith(`${PIN_HASH_VERSION}$`)) {
    const parts = stored.split("$");
    if (parts.length !== 4) return { valid: false, needsUpgrade: false };
    const iterations = Number(parts[1]);
    if (!Number.isInteger(iterations) || iterations < 1 || iterations > 2_000_000 || !/^[0-9a-f]{32}$/.test(parts[2])) {
      return { valid: false, needsUpgrade: false };
    }
    const computed = await pbkdf2(userId, pin, fromHex(parts[2]), iterations);
    const valid = constantTimeEqual(computed, parts[3]);
    return { valid, needsUpgrade: valid && iterations < PIN_PBKDF2_ITERATIONS };
  }
  const valid = constantTimeEqual(await legacySha256(userId, pin), stored);
  return { valid, needsUpgrade: valid };
}
