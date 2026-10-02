// convex/lib/pin.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Transaction PIN / password authorization with brute-force lockout
//
// Authorizes money movement. The caller MUST already be authenticated (session).
// IMPORTANT: a thrown error rolls the whole mutation back, including the failed-
// attempt counter. Callers must therefore RETURN a failure result when this
// returns { ok: false } (after the counter has been written), not throw.
// ═══════════════════════════════════════════════════════════════════════

import { Doc } from "../_generated/dataModel";
import { verifyPassword } from "../auth";

export const PIN_MAX_ATTEMPTS = 5;
export const PIN_LOCK_MS = 15 * 60 * 1000;

async function sha256Hex(payload: string): Promise<string> {
  const data = new TextEncoder().encode(payload);
  const buf = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Hash exactly as `payments.setWalletPin` stores it ("0x" + sha256 hex). */
export async function hashWalletPin(userId: string, pin: string): Promise<string> {
  return "0x" + (await sha256Hex(`wallet_pin_${userId}_${pin}`));
}

export type PinCheck =
  | { ok: true }
  | { ok: false; code: "LOCKED" | "INVALID" | "NOT_CONFIGURED" | "REQUIRED"; message: string };

/**
 * Verifies the PIN (or account password) for `user`, applying lockout.
 * Persists the failed-attempt counter / clears it on success.
 */
export async function verifyAndTrackPin(
  ctx: { db: any },
  user: Doc<"users">,
  pin: string | undefined
): Promise<PinCheck> {
  const now = Date.now();

  if (user.pinLockedUntil && user.pinLockedUntil > now) {
    const mins = Math.ceil((user.pinLockedUntil - now) / 60000);
    return {
      ok: false,
      code: "LOCKED",
      message: `Too many incorrect attempts. Try again in ${mins} minute(s).`,
    };
  }

  const pinStr = (pin ?? "").trim();
  if (!pinStr) {
    return { ok: false, code: "REQUIRED", message: "Security PIN is required to authorize this payment." };
  }
  if (!user.walletPinHash && !user.passwordHash) {
    // Never allow unauthenticated-by-secret money movement.
    return {
      ok: false,
      code: "NOT_CONFIGURED",
      message: "Please set a wallet PIN in Settings before moving funds.",
    };
  }

  let valid = false;
  if (user.walletPinHash) {
    valid = (await hashWalletPin(user._id, pinStr)) === user.walletPinHash;
  }
  if (!valid && user.passwordHash) {
    valid = await verifyPassword(pinStr, user.passwordHash);
  }

  if (valid) {
    if (user.pinFailedAttempts || user.pinLockedUntil) {
      await ctx.db.patch(user._id, { pinFailedAttempts: 0, pinLockedUntil: undefined });
    }
    return { ok: true };
  }

  const failures = (user.pinFailedAttempts ?? 0) + 1;
  if (failures >= PIN_MAX_ATTEMPTS) {
    await ctx.db.patch(user._id, { pinFailedAttempts: 0, pinLockedUntil: now + PIN_LOCK_MS });
    return {
      ok: false,
      code: "LOCKED",
      message: "Too many incorrect attempts. Your wallet is locked for 15 minutes.",
    };
  }
  await ctx.db.patch(user._id, { pinFailedAttempts: failures });
  return {
    ok: false,
    code: "INVALID",
    message: `Incorrect PIN. ${PIN_MAX_ATTEMPTS - failures} attempt(s) remaining.`,
  };
}
