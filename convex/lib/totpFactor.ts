// convex/lib/totpFactor.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Second-factor (TOTP / backup code) verification shared by every path that must
// prove the second factor: password login, social sign-in, and managing 2FA itself.
//
// All paths share ONE attempt counter per account (`login:totp:<userId>`), so switching between
// sign-in methods never resets the guess budget.
// IMPORTANT: callers must RETURN a failure result (not throw) so the counter write persists.
// ═══════════════════════════════════════════════════════════════════════

import { clearLimit, lockRemainingMs, recordFailure } from "./rateLimit";
import { decryptTotpSecret, hashBackupCode, verifyTotpCode } from "./totp";

export const TOTP_ATTEMPT_POLICY = { max: 5, windowMs: 15 * 60 * 1000, lockMs: 15 * 60 * 1000 };

export type SecondFactorResult =
  | { ok: true; usedBackupCode: boolean }
  | { ok: false; lockedMs: number };

/**
 * Verifies a 6-digit authenticator code or a single-use backup code for `user`.
 * Fails closed: a missing/undecryptable secret or a missing TOTP_ENCRYPTION_KEY never verifies.
 * A used backup code is removed in the same transaction.
 */
export async function verifySecondFactor(
  ctx: { db: any },
  user: { _id: any; totpSecretEncrypted?: string; totpBackupCodesHashed?: string[] },
  code: string | undefined,
  now = Date.now()
): Promise<SecondFactorResult> {
  const key = `login:totp:${user._id}`;
  const lockedMs = await lockRemainingMs(ctx, key, now);
  if (lockedMs > 0) return { ok: false, lockedMs };

  const candidate = (code ?? "").trim();
  let valid = false;
  let backupIndex = -1;

  if (candidate && user.totpSecretEncrypted) {
    try {
      const plain = await decryptTotpSecret(user.totpSecretEncrypted);
      valid = await verifyTotpCode(plain, candidate, now);
    } catch (e) {
      console.error("[TOTP] Secret decryption failed:", e instanceof Error ? e.message : String(e));
    }
  }

  if (!valid && candidate && Array.isArray(user.totpBackupCodesHashed) && user.totpBackupCodesHashed.length > 0) {
    backupIndex = user.totpBackupCodesHashed.indexOf(await hashBackupCode(candidate));
    if (backupIndex !== -1) valid = true;
  }

  if (!valid) {
    const locked = await recordFailure(ctx, key, TOTP_ATTEMPT_POLICY, now);
    return { ok: false, lockedMs: locked };
  }

  await clearLimit(ctx, key);
  if (backupIndex !== -1 && user.totpBackupCodesHashed) {
    const remaining = [...user.totpBackupCodesHashed];
    remaining.splice(backupIndex, 1);
    await ctx.db.patch(user._id, { totpBackupCodesHashed: remaining });
  }
  return { ok: true, usedBackupCode: backupIndex !== -1 };
}
