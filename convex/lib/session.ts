// convex/lib/session.ts
// Session issuance shared by every sign-in path (password, social, reset, registration).

export const USER_SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days
export const ADMIN_SESSION_TTL_MS = 8 * 60 * 60 * 1000; // 8 hours (strict admin session limit)
export const SESSION_TTL_MS = USER_SESSION_TTL_MS;

/** Cryptographically random 256-bit session token. */
export function newSessionToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Fields to patch onto a user when issuing a new session. */
export function issueSession(
  now = Date.now(),
  isAdmin = false
): { sessionToken: string; sessionExpiresAt: number } {
  const ttl = isAdmin ? ADMIN_SESSION_TTL_MS : USER_SESSION_TTL_MS;
  return { sessionToken: newSessionToken(), sessionExpiresAt: now + ttl };
}

/** True when the user's current session has an expiry and it has passed. */
export function isSessionExpired(user: { sessionExpiresAt?: number }, now = Date.now()): boolean {
  return typeof user.sessionExpiresAt === "number" && user.sessionExpiresAt <= now;
}

/** The fields session validity depends on (a subset of a users document). */
export interface SessionSubject {
  role?: string;
  sessionExpiresAt?: number;
  lastLoginAt?: number;
  _creationTime: number;
}

/**
 * The moment this user's CURRENT session stops being valid.
 *
 * - A session issued with an explicit `sessionExpiresAt` ends exactly then.
 * - A LEGACY session (issued before expiry existed, so `sessionExpiresAt` is missing) ends one
 *   maximum lifetime after the owner's last sign-in (`lastLoginAt`, else the account's creation time).
 *   The deadline depends only on stored timestamps, never on "now", so merely checking a legacy
 *   session can never extend it; only a real sign-in can.
 * - An administrator session can never outlive 8 hours from the last sign-in, whatever its stored
 *   expiry says (covers a missing field and an account promoted to admin with an older session).
 */
export function sessionDeadline(user: SessionSubject): number {
  const isAdmin = user.role === "admin";
  const anchor = typeof user.lastLoginAt === "number" ? user.lastLoginAt : user._creationTime;
  const ttl = isAdmin ? ADMIN_SESSION_TTL_MS : USER_SESSION_TTL_MS;
  const base = typeof user.sessionExpiresAt === "number" ? user.sessionExpiresAt : anchor + ttl;
  return isAdmin ? Math.min(base, anchor + ADMIN_SESSION_TTL_MS) : base;
}

/** Why a session is no longer valid, or null while it still is. Boundary: deadline == now is expired. */
export function sessionInvalidReason(
  user: SessionSubject,
  now = Date.now()
): "expired" | "admin_limit" | null {
  if (user.role === "admin") {
    const anchor = typeof user.lastLoginAt === "number" ? user.lastLoginAt : user._creationTime;
    const base = typeof user.sessionExpiresAt === "number" ? user.sessionExpiresAt : anchor + ADMIN_SESSION_TTL_MS;
    if (base <= now) return "expired";
    if (anchor + ADMIN_SESSION_TTL_MS <= now) return "admin_limit";
    return null;
  }
  return sessionDeadline(user) <= now ? "expired" : null;
}

export function isSessionValid(user: SessionSubject, now = Date.now()): boolean {
  return sessionInvalidReason(user, now) === null;
}
