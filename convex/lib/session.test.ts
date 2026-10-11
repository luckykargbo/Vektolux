// Pure unit tests for bounded session lifetimes (no database, no hashing).
import { describe, expect, test } from "vitest";
import {
  ADMIN_SESSION_TTL_MS,
  USER_SESSION_TTL_MS,
  isSessionValid,
  issueSession,
  sessionDeadline,
  sessionInvalidReason,
} from "./session";

const NOW = 1_800_000_000_000;
const H = 60 * 60 * 1000;
const D = 24 * H;

describe("issueSession", () => {
  test("users get 30 days, administrators 8 hours, and every session has an explicit expiry", () => {
    const user = issueSession(NOW);
    const admin = issueSession(NOW, true);
    expect(user.sessionExpiresAt).toBe(NOW + 30 * D);
    expect(admin.sessionExpiresAt).toBe(NOW + 8 * H);
    expect(USER_SESSION_TTL_MS).toBe(30 * D);
    expect(ADMIN_SESSION_TTL_MS).toBe(8 * H);
    expect(user.sessionToken).toMatch(/^[0-9a-f]{64}$/);
    expect(user.sessionToken).not.toBe(admin.sessionToken);
  });
});

describe("explicit expiry", () => {
  const user = { role: "client", sessionExpiresAt: NOW + 1000, lastLoginAt: NOW - D, _creationTime: NOW - 99 * D };

  test("valid strictly before the expiry", () => {
    expect(isSessionValid(user, NOW)).toBe(true);
    expect(isSessionValid(user, NOW + 999)).toBe(true);
  });

  test("boundary: expiry == now is already expired", () => {
    expect(isSessionValid(user, NOW + 1000)).toBe(false);
    expect(sessionInvalidReason(user, NOW + 1000)).toBe("expired");
    expect(isSessionValid(user, NOW + 1001)).toBe(false);
  });

  test("an explicit expiry is honoured even if it is far in the future of lastLoginAt", () => {
    expect(sessionDeadline(user)).toBe(NOW + 1000);
  });
});

describe("legacy sessions (no sessionExpiresAt)", () => {
  test("bounded to 30 days after the last sign-in", () => {
    const u = { role: "client", lastLoginAt: NOW - 29 * D, _creationTime: NOW - 400 * D };
    expect(sessionDeadline(u)).toBe(NOW - 29 * D + 30 * D);
    expect(isSessionValid(u, NOW)).toBe(true);
    expect(isSessionValid({ ...u, lastLoginAt: NOW - 31 * D }, NOW)).toBe(false);
  });

  test("boundary: exactly 30 days after the last sign-in is expired", () => {
    const u = { role: "client", lastLoginAt: NOW - 30 * D, _creationTime: NOW - 400 * D };
    expect(isSessionValid(u, NOW)).toBe(false);
    expect(isSessionValid(u, NOW - 1)).toBe(true);
  });

  test("with no lastLoginAt the account creation time is the anchor", () => {
    expect(isSessionValid({ role: "client", _creationTime: NOW - 10 * D }, NOW)).toBe(true);
    expect(isSessionValid({ role: "client", _creationTime: NOW - 31 * D }, NOW)).toBe(false);
  });

  test("checking a session never extends it: the deadline depends only on stored timestamps", () => {
    const u = { role: "client", lastLoginAt: NOW - 20 * D, _creationTime: NOW - 400 * D };
    const first = sessionDeadline(u);
    // however often and whenever it is checked, the answer is the same fixed instant
    expect(sessionDeadline(u)).toBe(first);
    expect(isSessionValid(u, first - 1)).toBe(true);
    expect(isSessionValid(u, first)).toBe(false);
    expect(isSessionValid(u, first + 5 * D)).toBe(false);
  });
});

describe("administrator sessions", () => {
  test("a legacy admin session with no lastLoginAt is bounded by creation time + 8 hours", () => {
    const admin = { role: "admin", _creationTime: NOW - 9 * H };
    expect(isSessionValid(admin, NOW)).toBe(false);
    expect(isSessionValid({ role: "admin", _creationTime: NOW - 7 * H }, NOW)).toBe(true);
  });

  test("a missing lastLoginAt can no longer switch the 8 hour limit off", () => {
    const admin = { role: "admin", sessionExpiresAt: NOW + 29 * D, _creationTime: NOW - 20 * D };
    expect(isSessionValid(admin, NOW)).toBe(false);
    expect(sessionInvalidReason(admin, NOW)).toBe("admin_limit");
  });

  test("a 30 day expiry on an admin is capped at 8 hours after the last sign-in", () => {
    const admin = { role: "admin", sessionExpiresAt: NOW + 30 * D, lastLoginAt: NOW - 7 * H, _creationTime: NOW - 99 * D };
    expect(sessionDeadline(admin)).toBe(NOW - 7 * H + 8 * H);
    expect(isSessionValid(admin, NOW)).toBe(true);
    expect(isSessionValid(admin, NOW + 1 * H)).toBe(false);
    expect(sessionInvalidReason(admin, NOW + 1 * H)).toBe("admin_limit");
  });

  test("boundary: exactly 8 hours after the last sign-in is expired", () => {
    const admin = { role: "admin", lastLoginAt: NOW - 8 * H, _creationTime: NOW - 99 * D };
    expect(isSessionValid(admin, NOW)).toBe(false);
    expect(isSessionValid({ ...admin, lastLoginAt: NOW - 8 * H + 1 }, NOW)).toBe(true);
  });

  test("an explicit expiry that has passed reports 'expired', not the lifetime limit", () => {
    const admin = { role: "admin", sessionExpiresAt: NOW - 1, lastLoginAt: NOW - H, _creationTime: NOW - 99 * D };
    expect(sessionInvalidReason(admin, NOW)).toBe("expired");
  });

  test("a normal user is NOT subject to the admin cap", () => {
    const u = { role: "client", sessionExpiresAt: NOW + 20 * D, lastLoginAt: NOW - 12 * H, _creationTime: NOW - 99 * D };
    expect(isSessionValid(u, NOW)).toBe(true);
  });
});
