// convex/lib/session.ts
// Session issuance shared by every sign-in path (password, social, reset, registration).

export const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

/** Cryptographically random 256-bit session token. */
export function newSessionToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Fields to patch onto a user when issuing a new session. */
export function issueSession(now = Date.now()): { sessionToken: string; sessionExpiresAt: number } {
  return { sessionToken: newSessionToken(), sessionExpiresAt: now + SESSION_TTL_MS };
}

/** True when the user's current session has an expiry and it has passed. */
export function isSessionExpired(user: { sessionExpiresAt?: number }, now = Date.now()): boolean {
  return typeof user.sessionExpiresAt === "number" && user.sessionExpiresAt <= now;
}
