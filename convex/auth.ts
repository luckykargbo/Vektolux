// convex/auth.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Authentication Mutations & Queries
// Handles user registration, login, and session management.
// ═══════════════════════════════════════════════════════════════════════

import { markPrivateFile, validateUpload } from "./lib/uploads";
import { mutation, query, internalMutation, internalQuery } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import { userRole } from "./schema";
import { clearLimit, consume, lockRemainingMs, minutes, recordFailure } from "./lib/rateLimit";
import { issueSession, isSessionValid } from "./lib/session";
import { restoreLegacyAgentRole } from "./lib/legacyRoles";
import { requireSelf } from "./lib/auth";
import type { MutationCtx } from "./_generated/server";
import type { Doc } from "./_generated/dataModel";
import { requireAdmin } from "./lib/auth";
import {
  generateTotpSecret,
  generateOtpauthUrl,
  verifyTotpCode,
  encryptTotpSecret,
  decryptTotpSecret,
  generateBackupCodes,
  hashBackupCode,
} from "./lib/totp";

const MIN_PASSWORD_LENGTH = 8;
// Login: 5 wrong attempts within 15 min locks that account/identifier for 15 min.
const LOGIN_POLICY = { max: 5, windowMs: 15 * 60 * 1000, lockMs: 15 * 60 * 1000 };
// Failed logins per client IP: 20 within 15 min blocks that IP for 15 min. Deliberately looser than the
// admin account policy because several customers can share one address (mobile carrier NAT); it
// only ever blocks the address the failures came from, never an account.
const LOGIN_IP_POLICY = { max: 20, windowMs: 15 * 60 * 1000, lockMs: 15 * 60 * 1000 };
// Reset requests: at most 3 codes per 15 min per account (stops inbox flooding).
const RESET_REQUEST_POLICY = { max: 3, windowMs: 15 * 60 * 1000 };
// Reset code guesses: a code is burned after 5 wrong guesses.
const RESET_CODE_MAX_ATTEMPTS = 5;
// Email-verification codes: valid 10 minutes, single use, burned after 5 wrong guesses,
// at most 3 sent per 15 minutes per account.
const EMAIL_VERIFY_TTL_MS = 10 * 60 * 1000;
const EMAIL_VERIFY_MAX_ATTEMPTS = 5;
const EMAIL_VERIFY_SEND_POLICY = { max: 3, windowMs: 15 * 60 * 1000 };

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Reset codes are stored hashed (bound to the identifier), never in plain text. */
async function hashResetCode(identifier: string, code: string): Promise<string> {
  return "h1:" + (await sha256Hex(`vektolux-reset:${identifier}:${code}`));
}

/** Verification codes are stored hashed and bound to BOTH the account and the address they were sent to. */
async function hashEmailVerificationCode(userId: string, email: string, code: string): Promise<string> {
  return "v1:" + (await sha256Hex(`vektolux-emailverify:${userId}:${email}:${code}`));
}

/**
 * Creates a fresh verification challenge for the account's CURRENT email (retiring older ones) and
 * queues the email through the existing Resend sender. Nothing is marked verified here.
 */
async function issueEmailVerification(ctx: MutationCtx, user: Doc<"users">, now: number): Promise<void> {
  const email = user.email?.trim().toLowerCase();
  if (!email || email.endsWith("@users.vektolux.invalid")) return;
  const open = await ctx.db
    .query("email_verifications")
    .withIndex("by_userId", (q) => q.eq("userId", user._id))
    .filter((q) => q.eq(q.field("isUsed"), false))
    .take(20);
  for (const old of open) await ctx.db.patch(old._id, { isUsed: true });
  const code = secureSixDigitCode();
  await ctx.db.insert("email_verifications", {
    userId: user._id,
    email,
    codeHash: await hashEmailVerificationCode(user._id, email, code),
    expiresAt: now + EMAIL_VERIFY_TTL_MS,
    isUsed: false,
    attempts: 0,
    createdAt: now,
  });
  await ctx.scheduler.runAfter(0, internal.emails.sendOtpEmail, {
    to: email,
    otpCode: code,
    recipientName: user.name ?? "User",
  });
}

/**
 * The client address to rate-limit a login by. Never taken from a caller-supplied argument alone:
 *  - the platform-observed request IP (`ctx.meta`), which a client cannot choose; or
 *  - the address forwarded by the admin-dashboard server, accepted ONLY when the call carries the
 *    shared LOGIN_PROXY_SECRET (the dashboard server sees the real browser; Convex sees the server).
 * Returns undefined when neither is available (then only account-level limits apply).
 */
async function resolveLoginClientIp(
  ctx: MutationCtx,
  forwardedIp: string | undefined,
  proxySecret: string | undefined
): Promise<string | undefined> {
  const configured = process.env.LOGIN_PROXY_SECRET;
  const forwarded = forwardedIp?.trim();
  if (
    configured && configured.length >= 16 && proxySecret && safeEqual(proxySecret, configured) &&
    forwarded && /^[0-9a-fA-F:.]{3,45}$/.test(forwarded)
  ) {
    return forwarded.toLowerCase();
  }
  const observed = (await ctx.meta.getRequestMetadata()).ip;
  return observed ? observed.toLowerCase() : undefined;
}

/** Cryptographically random 6-digit code. */
function secureSixDigitCode(): string {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return String(100000 + (buf[0] % 900000));
}

/** Constant-time string comparison. */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

// ─── PBKDF2 Password Hashing with Random Salt (Web Crypto API) ───────
async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    enc.encode(password),
    { name: "PBKDF2" },
    false,
    ["deriveBits", "deriveKey"]
  );
  const derivedKey = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      salt: salt,
      iterations: 100000,
      hash: "SHA-256",
    },
    keyMaterial,
    256
  );
  const saltHex = Array.from(salt)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const hashHex = Array.from(new Uint8Array(derivedKey))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `${saltHex}:${hashHex}`;
}

export async function verifyPassword(
  password: string,
  storedHash: string
): Promise<boolean> {
  const parts = storedHash.split(":");
  if (parts.length !== 2) {
    // SHA-256 or plaintext fallback for legacy accounts
    try {
      const enc = new TextEncoder();
      const data = enc.encode(password);
      const hashBuffer = await crypto.subtle.digest("SHA-256", data);
      const legacyHash = Array.from(new Uint8Array(hashBuffer))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      // Legacy SHA-256 hashes. (Submitting the stored hash itself used to be accepted.)
      if (/^[0-9a-f]{64}$/.test(storedHash)) return safeEqual(legacyHash, storedHash);
      // Very old plaintext records: compared only when the stored value is not a hash.
      return storedHash.length > 0 && safeEqual(password, storedHash);
    } catch {
      return false;
    }
  }
  const [saltHex, hashHex] = parts;

  const saltMatches = saltHex.match(/.{1,2}/g);
  if (!saltMatches) return false;
  const salt = new Uint8Array(saltMatches.map((byte) => parseInt(byte, 16)));

  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    enc.encode(password),
    { name: "PBKDF2" },
    false,
    ["deriveBits", "deriveKey"]
  );
  const derivedKey = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      salt: salt,
      iterations: 100000,
      hash: "SHA-256",
    },
    keyMaterial,
    256
  );
  const computedHashHex = Array.from(new Uint8Array(derivedKey))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return safeEqual(computedHashHex, hashHex);
}

// ─── Multi-Format Phone Candidates Generator ────────────────────────
export function getPhoneCandidates(raw: string): string[] {
  const trimmed = raw.trim();
  const cleaned = trimmed.replace(/[^\d+]/g, "");
  const digits = cleaned.replace(/\D/g, "");
  if (!digits) return [trimmed];

  const candidates = new Set<string>();
  candidates.add(trimmed);
  candidates.add(cleaned);
  candidates.add(digits);
  candidates.add(`+${digits}`);

  if (digits.startsWith("232")) {
    const national = digits.slice(3); // e.g. "0010819"
    candidates.add(national);
    candidates.add(`+232${national}`);
    candidates.add(`232${national}`);
    candidates.add(`0${national}`);
    const stripped = national.replace(/^0+/, "");
    if (stripped) {
      candidates.add(stripped);
      candidates.add(`+232${stripped}`);
      candidates.add(`232${stripped}`);
      candidates.add(`0${stripped}`);
    }
  } else {
    const stripped = digits.replace(/^0+/, "");
    candidates.add(`+232${digits}`);
    candidates.add(`232${digits}`);
    candidates.add(`0${digits}`);
    if (stripped) {
      candidates.add(stripped);
      candidates.add(`+232${stripped}`);
      candidates.add(`232${stripped}`);
      candidates.add(`0${stripped}`);
    }
  }

  return Array.from(candidates);
}

// ─── Case-Insensitive & Format-Agnostic User Lookup ──────────────────
export async function findUserByIdentifier(ctx: any, identifier: string) {
  // Exact, indexed matches only. (Previously: full-table scans and phone-SUFFIX matching, which
  // could resolve a short number to someone else's account.)
  const raw = identifier.trim();
  if (!raw || raw.length > 254) return null;

  if (raw.includes("@")) {
    const lower = raw.toLowerCase();
    const byLower = await ctx.db.query("users").withIndex("by_email", (q: any) => q.eq("email", lower)).first();
    if (byLower) return byLower;
    if (raw !== lower) {
      return await ctx.db.query("users").withIndex("by_email", (q: any) => q.eq("email", raw)).first();
    }
    return null;
  }

  for (const cand of getPhoneCandidates(raw)) {
    const user = await ctx.db.query("users").withIndex("by_phone", (q: any) => q.eq("phone", cand)).first();
    if (user) return user;
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════
//                        REGISTER USER
// ═══════════════════════════════════════════════════════════════════════

/**
 * Canonicalize incoming user role string to standard Convex database enum value.
 * Safely handles UI display names (e.g. "Client / Buyer" -> "client", "Real Estate Agent" -> "agent").
 */
export function canonicalizeUserRole(rawRole: string): "client" | "agent" | "merchant" | "driver" | "admin" {
  const normalized = (rawRole ?? "").toLowerCase().trim();
  if (normalized.includes("agent") || normalized.includes("property")) return "agent";
  if (normalized.includes("merchant") || normalized.includes("dealer") || normalized.includes("dealership")) return "merchant";
  if (normalized.includes("driver") || normalized.includes("logistics") || normalized.includes("fleet")) return "driver";
  if (normalized.includes("admin")) return "admin";
  return "client"; // default for "client", "buyer", "client / buyer", etc.
}

/**
 * Business role a registrant ASKED for (from the UI label). It is only ever recorded as a pending
 * application; the stored role stays "client" until an administrator approves it.
 */
export function requestedApplicationRole(
  rawRole: string
): "agent" | "property_owner" | "dealer" | "hotel_operator" | null {
  const r = (rawRole ?? "").toLowerCase().trim();
  if (r.includes("hotel") || r.includes("guest")) return "hotel_operator";
  if (r.includes("agent")) return "agent";
  if (r.includes("owner") || r.includes("property") || r.includes("landlord")) return "property_owner";
  if (r.includes("merchant") || r.includes("dealer") || r.includes("dealership")) return "dealer";
  return null;
}

export const registerUser = mutation({
  args: {
    name: v.string(),
    email: v.string(),
    phone: v.string(),
    password: v.string(),
    role: v.string(), // Accepts canonical "client" or UI display strings like "Client / Buyer"
    avatarUrl: v.optional(v.string()),
    businessName: v.optional(v.string()),
    tinNumber: v.optional(v.string()),
    documentStorageId: v.optional(v.id("_storage")),
    documentUrl: v.optional(v.string()),
    address: v.optional(v.string()),
    region: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    errorMessage: v.optional(v.string()),
    userId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
    name: v.optional(v.string()),
    email: v.optional(v.string()),
    phone: v.optional(v.string()),
    role: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    address: v.optional(v.string()),
    region: v.optional(v.string()),
    pendingApplicationRole: v.optional(v.string()),
    emailVerified: v.optional(v.boolean()),
    emailVerificationRequired: v.optional(v.boolean()),
  }),
  handler: async (ctx, args) => {
    try {
      const normalizedEmail = args.email.trim().toLowerCase();
      const normalizedPhone = args.phone.trim();
      // Self-registration can NEVER grant administrator rights (any role string containing
      // "admin" previously did). Admins are appointed server-side only.
      // Selecting a business role grants NOTHING: every account starts as a client and the
      // requested role becomes a pending application for admin review.
      const canonicalRole = "client";
      const applicationRole = requestedApplicationRole(args.role);

      // Checked BEFORE any existence lookup so this answer cannot depend on whether the email exists.
      if (!args.password || args.password.length < MIN_PASSWORD_LENGTH) {
        return { success: false, errorMessage: `Password must be at least ${MIN_PASSWORD_LENGTH} characters long.` };
      }

      // 1+2. Duplicate email / phone: ONE answer for both, so the response never says which
      // address or number is already registered (no account enumeration).
      const existingByEmail = await findUserByIdentifier(ctx, normalizedEmail);
      const existingByPhone = existingByEmail ? null : await findUserByIdentifier(ctx, normalizedPhone);
      if (existingByEmail || existingByPhone) {
        return {
          success: false,
          errorMessage:
            "We couldn't create an account with these details. If you already have a Vektolux account, sign in or use Forgot password.",
        };
      }

      // The supporting document (if any) must be a real, acceptable file we hold. The URL stored
      // is derived from the file itself; a client-supplied URL string is never trusted.
      let verifiedDocumentUrl: string | undefined;
      if (args.documentStorageId) {
        const check = await validateUpload(ctx, args.documentStorageId);
        if (!check.ok) return { success: false, errorMessage: check.reason };
        verifiedDocumentUrl = (await ctx.storage.getUrl(args.documentStorageId)) ?? undefined;
      }

      // 3. Hash password
      const passwordHash = await hashPassword(args.password);
      const now = Date.now();
      const { sessionToken, sessionExpiresAt } = issueSession(now);

      const isRestrictedRole = applicationRole !== null;
      const verificationStatus = "unverified"; // identity (KYC) is reviewed separately

      // 4. Insert user record
      const userId = await ctx.db.insert("users", {
        name: args.name.trim(),
        email: normalizedEmail,
        phone: normalizedPhone,
        role: canonicalRole,
        avatarUrl: args.avatarUrl,
        address: args.address,
        region: args.region,
        passwordHash,
        sessionToken,
        sessionExpiresAt,
        isVerified: false,
        isActive: true,
        verificationStatus,
        businessName: args.businessName,
        tinNumber: args.tinNumber,
        documentStorageId: args.documentStorageId,
        documentUrl: verifiedDocumentUrl,
        updatedAt: now,
      });
      if (args.documentStorageId) {
        await markPrivateFile(ctx, args.documentStorageId, "registration_document", userId);
      }

      // 5. Initialize user wallet with zero balance (idempotently)
      const existingWallet = await ctx.db
        .query("walletBalances")
        .withIndex("by_user_currency", (q) =>
          q.eq("userId", userId).eq("currency", "SLE")
        )
        .first();

      if (!existingWallet) {
        await ctx.db.insert("walletBalances", {
          userId,
          availableBalance: 0,
          pendingBalance: 0,
          escrowBalance: 0,
          currency: "SLE",
          updatedAt: now,
        });
      }

      // 6. Record the requested business role as a pending application
      if (isRestrictedRole) {
        await ctx.db.insert("merchant_profiles", {
          userId,
          businessName: args.businessName,
          tinNumber: args.tinNumber,
          documentUrl: verifiedDocumentUrl,
          verificationStatus: "pending",
          updatedAt: now,
        });

        await ctx.db.insert("role_applications", {
          userId,
          targetRole: applicationRole,
          businessName: args.businessName,
          tinNumber: args.tinNumber,
          documentUrls: verifiedDocumentUrl ? [verifiedDocumentUrl] : [],
          status: "pending",
          updatedAt: now,
        });
      }

      // 7. Prove ownership of the address: the account stays UNVERIFIED (no emailVerifiedAt) until
      // the code mailed to it is entered (auth.verifyEmail). Limited access before that is unchanged.
      const created = await ctx.db.get(userId);
      if (created) await issueEmailVerification(ctx, created, now);

      return {
        success: true,
        userId: userId as string,
        sessionToken,
        name: args.name,
        email: args.email,
        phone: args.phone,
        role: canonicalRole,
        avatarUrl: args.avatarUrl,
        emailVerified: false,
        emailVerificationRequired: true,
        ...(applicationRole ? { pendingApplicationRole: applicationRole } : {}),
      };
    } catch (err: any) {
      // No personal data in logs, and no internal error details returned to the client.
      console.error("[registerUser] registration error:", err?.message ?? String(err));
      return {
        success: false,
        errorMessage: "Registration failed. Please try again.",
      };
    }
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                     LOGIN WITH PHONE OR EMAIL
// ═══════════════════════════════════════════════════════════════════════

export const loginWithPhoneOrEmail = mutation({
  args: {
    identifier: v.string(), // email or phone
    password: v.string(),
    // NOT trusted on its own: a caller can send anything here. It is honoured only together with a
    // `proxySecret` that matches LOGIN_PROXY_SECRET (i.e. the admin-dashboard server, which has
    // already derived the real browser IP). Otherwise the platform-observed IP is used.
    ip: v.optional(v.string()),
    proxySecret: v.optional(v.string()),
    totpCode: v.optional(v.string()), // 6-digit TOTP code or backup code
  },
  returns: v.object({
    success: v.boolean(),
    mfaRequired: v.optional(v.boolean()),
    errorMessage: v.optional(v.string()),
    userId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
    name: v.optional(v.string()),
    email: v.optional(v.string()),
    phone: v.optional(v.string()),
    role: v.optional(v.string()),
    address: v.optional(v.string()),
    region: v.optional(v.string()),
    isVerified: v.optional(v.boolean()),
    emailVerified: v.optional(v.boolean()),
    verificationStatus: v.optional(v.string()),
    businessName: v.optional(v.string()),
    tinNumber: v.optional(v.string()),
    documentUrl: v.optional(v.string()),
    rejectionReason: v.optional(v.string()),
    verifiedAt: v.optional(v.number()),
    avatarUrl: v.optional(v.string()),
    walletAddress: v.optional(v.string()),
    bio: v.optional(v.string()),
    kycStatus: v.optional(v.string()),
    active_mode: v.optional(v.string()),
    is_driver_verified: v.optional(v.boolean()),
    driver_status: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    const GENERIC = "Invalid email/phone or password. Please try again or use 'Forgot Password' to reset.";
    try {
      const sanitizedId = args.identifier.trim();
      const now = Date.now();
      const idKey = `login:id:${sanitizedId.toLowerCase()}`;
      // The IP bucket is keyed by an address the SERVER derived: the platform's view of the request
      // (ctx.meta), or the dashboard proxy's forwarded address when it proves it is the proxy.
      const clientIp = await resolveLoginClientIp(ctx, args.ip, args.proxySecret);
      const ipKey = clientIp ? `login:ip:${clientIp}` : undefined;

      if (ipKey) {
        const ipLock = await lockRemainingMs(ctx, ipKey, now);
        if (ipLock > 0) {
          return { success: false, errorMessage: `Too many failed attempts. Please try again in ${minutes(ipLock)} minute(s) or reset your password.` };
        }
      }

      const user = await findUserByIdentifier(ctx, sanitizedId);
      const isAdminAccount = user?.role === "admin" || sanitizedId.toLowerCase().includes("admin@vektolux");

      // Account lockout is applied ONLY to admin accounts so attackers cannot DoS normal mobile users
      if (isAdminAccount) {
        const idLock = await lockRemainingMs(ctx, idKey, now);
        if (idLock > 0) {
          return { success: false, errorMessage: `Too many failed attempts. Please try again in ${minutes(idLock)} minute(s) or reset your password.` };
        }
        const userKey = user ? `login:user:${user._id}` : undefined;
        if (userKey) {
          const userLock = await lockRemainingMs(ctx, userKey, now);
          if (userLock > 0) {
            return { success: false, errorMessage: `Too many failed attempts. Please try again in ${minutes(userLock)} minute(s) or reset your password.` };
          }
        }
      }

      // One generic answer for "no such account", "no password set" and "wrong password", so the
      // response never reveals which emails/phones are registered. Every failure is counted.
      const ok = !!user && !!user.passwordHash && (await verifyPassword(args.password, user.passwordHash));
      if (!ok || !user) {
        if (ipKey) await recordFailure(ctx, ipKey, LOGIN_IP_POLICY, now);
        if (isAdminAccount) {
          await recordFailure(ctx, idKey, LOGIN_POLICY, now);
          const userKey = user ? `login:user:${user._id}` : undefined;
          if (userKey) await recordFailure(ctx, userKey, LOGIN_POLICY, now);
        }
        return { success: false, errorMessage: GENERIC };
      }

      // Correct password: only now is it safe to say the account is deactivated.
      if (!user.isActive) {
        return { success: false, errorMessage: "This account has been deactivated. Please contact support." };
      }

      // ─── TOTP TWO-FACTOR AUTHENTICATION ENFORCEMENT ─────────────────
      // If TOTP is enabled on the account, verify 2FA code before issuing any session token
      if (user.totpEnabled) {
        if (!args.totpCode || !args.totpCode.trim()) {
          // Strictly reject without issuing any session token
          return {
            success: false,
            mfaRequired: true,
            errorMessage: "Two-factor authentication code required.",
          };
        }

        const totpKey = `login:totp:${user._id}`;
        const totpLock = await lockRemainingMs(ctx, totpKey, now);
        if (totpLock > 0) {
          return {
            success: false,
            errorMessage: `Too many failed 2FA attempts. Please try again in ${minutes(totpLock)} minute(s) or use an emergency backup code.`,
          };
        }

        let totpValid = false;
        let usedBackupIndex = -1;

        if (user.totpSecretEncrypted) {
          try {
            const plainSecret = await decryptTotpSecret(user.totpSecretEncrypted);
            totpValid = await verifyTotpCode(plainSecret, args.totpCode, now);
          } catch (e) {
            console.error("[TOTP] Secret decryption failed:", e);
          }
        }

        // Check emergency backup codes if standard TOTP code didn't match
        if (!totpValid && Array.isArray(user.totpBackupCodesHashed) && user.totpBackupCodesHashed.length > 0) {
          const providedHash = await hashBackupCode(args.totpCode);
          usedBackupIndex = user.totpBackupCodesHashed.indexOf(providedHash);
          if (usedBackupIndex !== -1) {
            totpValid = true;
          }
        }

        if (!totpValid) {
          await recordFailure(ctx, totpKey, LOGIN_POLICY, now);
          return {
            success: false,
            errorMessage: "Invalid two-factor authentication code.",
          };
        }

        // Successfully verified TOTP: clear TOTP limit
        await clearLimit(ctx, totpKey);

        // If a single-use backup code was used, remove it from the array
        if (usedBackupIndex !== -1 && Array.isArray(user.totpBackupCodesHashed)) {
          const updatedBackupCodes = [...user.totpBackupCodesHashed];
          updatedBackupCodes.splice(usedBackupIndex, 1);
          await ctx.db.patch(user._id, { totpBackupCodesHashed: updatedBackupCodes });
        }
      }

      await clearLimit(ctx, idKey);
      const userKey = user ? `login:user:${user._id}` : undefined;
      if (userKey) await clearLimit(ctx, userKey);
      // The IP counter is deliberately NOT cleared on success: otherwise an attacker holding one valid
      // account could reset it between guesses. It simply expires with its window.

      // An agent approved by the OLD admin flow (which never changed users.role) gets the role the
      // admin granted, from the stored approval evidence only (lib/legacyRoles.ts). Idempotent.
      const legacy = await restoreLegacyAgentRole(ctx, user, { now });
      const role = legacy.restored ? ("agent" as const) : user.role;

      // Admin sessions strictly enforce 8-hour TTL server-side
      const isAdmin = role === "admin" || user.role === "admin";
      const { sessionToken, sessionExpiresAt } = issueSession(now, isAdmin);
      // Transparently upgrade legacy (SHA-256 / plaintext) password records to salted PBKDF2.
      const upgradedHash = user.passwordHash!.includes(":") ? undefined : await hashPassword(args.password);
      await ctx.db.patch(user._id, {
        sessionToken,
        sessionExpiresAt,
        lastLoginAt: now,
        updatedAt: now,
        ...(upgradedHash ? { passwordHash: upgradedHash } : {}),
        // Signing in within the 30-day window cancels a pending account deletion.
        deletionRequestedAt: undefined,
        deletionScheduledFor: undefined,
      });
      const isDriverVerified = Boolean(
        user.is_driver_verified ?? user.isVerifiedDriver ?? (user.role?.toLowerCase() === "driver")
      );
      const activeMode = user.active_mode ?? (user.activeRole === "driver" ? "driver" : "passenger");
      const driverStatus = user.driver_status ?? (user.role?.toLowerCase() === "driver" ? "online" : "offline");

      return {
        success: true,
        userId: user._id as string,
        sessionToken,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role,
        address: user.address,
        region: user.region,
        isVerified: user.isVerified,
        emailVerified: !!user.emailVerifiedAt,
        verificationStatus: user.verificationStatus ?? (user.isVerified ? "verified" : "unverified"),
        businessName: user.businessName,
        tinNumber: user.tinNumber,
        documentUrl: user.documentUrl,
        rejectionReason: user.rejectionReason,
        verifiedAt: user.verifiedAt,
        avatarUrl: user.avatarUrl,
        walletAddress: user.walletAddress,
        bio: user.bio,
        kycStatus: user.kycStatus,
        active_mode: activeMode,
        is_driver_verified: isDriverVerified,
        driver_status: driverStatus,
      };
    } catch (err: any) {
      console.error("[loginWithPhoneOrEmail] error:", err?.message ?? String(err));
      return { success: false, errorMessage: "An error occurred during login. Please try again." };
    }
  },
});

/**
 * Invalidates an active user or admin session token on logout.
 */
export const logout = mutation({
  args: { sessionToken: v.optional(v.string()) },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const raw = args.sessionToken?.trim();
    if (!raw || raw.length < 16) return false;
    const user = await ctx.db
      .query("users")
      .withIndex("by_sessionToken", (q: any) => q.eq("sessionToken", raw))
      .first();
    if (user) {
      await ctx.db.patch(user._id, {
        sessionToken: undefined,
        sessionExpiresAt: undefined,
        updatedAt: Date.now(),
      });
      return true;
    }
    return false;
  },
});

/**
 * Validates an active admin session token and returns safe admin profile info.
 */
export const getAdminSession = query({
  args: { sessionToken: v.optional(v.string()) },
  returns: v.union(
    v.object({
      userId: v.string(),
      name: v.string(),
      email: v.string(),
      role: v.string(),
    }),
    v.null()
  ),
  handler: async (ctx, args) => {
    try {
      const { user } = await requireAdmin(ctx, { sessionToken: args.sessionToken });
      return {
        userId: user._id as string,
        name: user.name,
        email: user.email,
        role: user.role,
      };
    } catch {
      return null;
    }
  },
});

/**
 * Initiates TOTP 2FA enrollment for an authenticated administrator.
 * Generates secret, otpauth URI, and emergency backup codes, and stores
 * the encrypted secret in totpPendingSecretEncrypted until verified.
 */
export const setupTotp = mutation({
  args: { sessionToken: v.string() },
  returns: v.union(
    v.object({
      success: v.boolean(),
      secret: v.string(),
      otpauthUrl: v.string(),
      backupCodes: v.array(v.string()),
    }),
    v.object({
      success: v.literal(false),
      errorMessage: v.string(),
    })
  ),
  handler: async (ctx, args) => {
    const { user } = await requireAdmin(ctx, { sessionToken: args.sessionToken });
    const secret = generateTotpSecret();
    const otpauthUrl = generateOtpauthUrl(user.email, secret, "Vektolux Admin");
    const backupCodes = generateBackupCodes();
    const encryptedSecret = await encryptTotpSecret(secret);

    await ctx.db.patch(user._id, {
      totpPendingSecretEncrypted: encryptedSecret,
      updatedAt: Date.now(),
    });

    return {
      success: true,
      secret,
      otpauthUrl,
      backupCodes,
    };
  },
});

/**
 * Confirms and activates TOTP 2FA using a valid code from the authenticator app.
 * Promotes totpPendingSecretEncrypted to totpSecretEncrypted, hashes backup codes,
 * and sets totpEnabled: true.
 */
export const enableTotp = mutation({
  args: {
    sessionToken: v.string(),
    code: v.string(),
    backupCodes: v.array(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    errorMessage: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    const { user } = await requireAdmin(ctx, { sessionToken: args.sessionToken });
    if (!user.totpPendingSecretEncrypted) {
      return { success: false, errorMessage: "No pending 2FA setup found. Please generate a new QR code." };
    }

    const plainSecret = await decryptTotpSecret(user.totpPendingSecretEncrypted);
    const valid = await verifyTotpCode(plainSecret, args.code);
    if (!valid) {
      return { success: false, errorMessage: "Invalid verification code. Please check your authenticator app and try again." };
    }

    const hashedBackupCodes = await Promise.all(args.backupCodes.map((c) => hashBackupCode(c)));

    await ctx.db.patch(user._id, {
      totpEnabled: true,
      totpSecretEncrypted: user.totpPendingSecretEncrypted,
      totpPendingSecretEncrypted: undefined,
      totpBackupCodesHashed: hashedBackupCodes,
      updatedAt: Date.now(),
    });

    return { success: true };
  },
});

/**
 * Disables TOTP 2FA. Requires both current admin password and valid TOTP code.
 */
export const disableTotp = mutation({
  args: {
    sessionToken: v.string(),
    password: v.string(),
    code: v.string(),
  },
  returns: v.object({
    success: v.boolean(),
    errorMessage: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    const { user } = await requireAdmin(ctx, { sessionToken: args.sessionToken });
    if (!user.passwordHash || !(await verifyPassword(args.password, user.passwordHash))) {
      return { success: false, errorMessage: "Invalid administrator password." };
    }

    if (user.totpSecretEncrypted) {
      const plainSecret = await decryptTotpSecret(user.totpSecretEncrypted);
      const valid = await verifyTotpCode(plainSecret, args.code);
      if (!valid) {
        return { success: false, errorMessage: "Invalid 2FA code." };
      }
    }

    await ctx.db.patch(user._id, {
      totpEnabled: false,
      totpSecretEncrypted: undefined,
      totpPendingSecretEncrypted: undefined,
      totpBackupCodesHashed: undefined,
      updatedAt: Date.now(),
    });

    return { success: true };
  },
});



// ═══════════════════════════════════════════════════════════════════════
//                      GET USER SESSION
// ═══════════════════════════════════════════════════════════════════════

export const getUserSession = query({
  args: {
    userId: v.string(),
    sessionToken: v.string(),
  },
  returns: v.union(
    v.object({
      userId: v.string(),
      name: v.string(),
      email: v.string(),
      phone: v.string(),
      role: v.string(),
      address: v.optional(v.string()),
      region: v.optional(v.string()),
      isVerified: v.boolean(),
      emailVerified: v.optional(v.boolean()),
      isActive: v.boolean(),
      avatarUrl: v.optional(v.string()),
      walletAddress: v.optional(v.string()),
      bio: v.optional(v.string()),
      kycStatus: v.optional(v.string()),
      active_mode: v.optional(v.string()),
      is_driver_verified: v.optional(v.boolean()),
      driver_status: v.optional(v.string()),
      verificationStatus: v.optional(v.string()),
      businessName: v.optional(v.string()),
      tinNumber: v.optional(v.string()),
      documentUrl: v.optional(v.string()),
      rejectionReason: v.optional(v.string()),
      verifiedAt: v.optional(v.number()),
    }),
    v.null()
  ),
  handler: async (ctx, args) => {
    try {
      const userId = ctx.db.normalizeId("users", args.userId);
      if (!userId) return null;
      
      const user = await ctx.db.get(userId);
      if (!user) return null;

      // Validate session token (constant-time) and expiry
      if (!user.sessionToken || !safeEqual(user.sessionToken, args.sessionToken)) {
        return null;
      }
      if (!isSessionValid(user)) {
        return null;
      }

      if (!user.isActive) {
        return null;
      }

      const isDriverVerified = Boolean(
        user.is_driver_verified ?? user.isVerifiedDriver ?? (user.role === "driver")
      );
      const activeMode = user.active_mode ?? (user.activeRole === "driver" ? "driver" : "passenger");
      const driverStatus = user.driver_status ?? (user.role === "driver" ? "online" : "offline");

      return {
        userId: user._id as string,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role: user.role,
        address: user.address,
        region: user.region,
        isVerified: user.isVerified,
        emailVerified: !!user.emailVerifiedAt,
        isActive: user.isActive,
        avatarUrl: user.avatarUrl,
        walletAddress: user.walletAddress,
        bio: user.bio,
        kycStatus: user.kycStatus,
        active_mode: activeMode,
        is_driver_verified: isDriverVerified,
        driver_status: driverStatus,
        verificationStatus: user.verificationStatus ?? (user.isVerified ? "verified" : "unverified"),
        businessName: user.businessName,
        tinNumber: user.tinNumber,
        documentUrl: user.documentUrl,
        rejectionReason: user.rejectionReason,
        verifiedAt: user.verifiedAt,
      };
    } catch {
      return null;
    }
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    SEED DEMO / TEST USERS (PRODUCTION ENFORCED)
// ═════════════════════════════════════════════════
//                  EMAIL OWNERSHIP VERIFICATION
// ═════════════════════════════════════════════════

/** Signed-in user asks for a new code for THEIR OWN current email. */
export const resendEmailVerification = mutation({
  args: { sessionToken: v.string() },
  returns: v.object({ success: v.boolean(), alreadyVerified: v.optional(v.boolean()), message: v.string() }),
  handler: async (ctx, args) => {
    const { user } = await requireSelf(ctx, args.sessionToken);
    if (user.emailVerifiedAt) return { success: true, alreadyVerified: true, message: "Your email is already verified." };
    const now = Date.now();
    if (!(await consume(ctx, `email-verify-send:${user._id}`, EMAIL_VERIFY_SEND_POLICY, now))) {
      return { success: false, message: "Too many requests. Please wait 15 minutes and try again." };
    }
    await issueEmailVerification(ctx, user, now);
    return { success: true, message: "A new 6-digit code has been sent to your email." };
  },
});

/**
 * Marks the signed-in user's email as verified when the code mailed to it is entered. The account
 * is always the session's own: a code can never verify (or change) another user's email.
 */
export const verifyEmail = mutation({
  args: { sessionToken: v.string(), code: v.string() },
  returns: v.object({ success: v.boolean(), message: v.string() }),
  handler: async (ctx, args) => {
    const INVALID = { success: false, message: "Invalid or expired verification code. Please request a new one." };
    const { user } = await requireSelf(ctx, args.sessionToken);
    if (user.emailVerifiedAt) return { success: true, message: "Your email is already verified." };
    const code = args.code.trim();
    if (!/^\d{6}$/.test(code)) return { success: false, message: "Please enter the 6-digit verification code." };
    const now = Date.now();

    // Only the most recent challenge counts, and only if it was sent to the address the account has NOW.
    const record = await ctx.db
      .query("email_verifications")
      .withIndex("by_userId", (q) => q.eq("userId", user._id))
      .order("desc")
      .first();
    const email = user.email?.trim().toLowerCase();
    if (!record || record.isUsed || record.expiresAt <= now || !email || record.email !== email) return INVALID;

    const expected = await hashEmailVerificationCode(user._id, email, code);
    if (!safeEqual(expected, record.codeHash)) {
      // Counted and RETURNED (not thrown) so the counter persists; the code is burned at the limit.
      const attempts = (record.attempts ?? 0) + 1;
      await ctx.db.patch(record._id, { attempts, isUsed: attempts >= EMAIL_VERIFY_MAX_ATTEMPTS });
      return attempts >= EMAIL_VERIFY_MAX_ATTEMPTS
        ? { success: false, message: "Too many incorrect codes. Please request a new code." }
        : INVALID;
    }

    await ctx.db.patch(record._id, { isUsed: true });
    await ctx.db.patch(user._id, { emailVerifiedAt: now, updatedAt: now });
    return { success: true, message: "Your email has been verified." };
  },
});

// ═══════════════════════════════════════════════════════════════════════

export const seedDemoUsers = internalMutation({
  args: { initialPassword: v.string() },
  returns: v.object({
    seeded: v.array(v.string()),
    existing: v.array(v.string()),
  }),
  handler: async (ctx, args) => {
    // Only ensure primary production user Alfred Manso Kargbo exists
    const prodAccount = {
      email: "alfred.kargbo@vektolux.com",
      phone: "+232688577868",
      name: "Alfred Manso Kargbo",
      role: "admin" as const,
    };

    const seeded: string[] = [];
    const existing: string[] = [];
    // No hardcoded admin password (it used to be "password123"). Must be supplied by the operator.
    if (!args.initialPassword || args.initialPassword.length < 12) {
      throw new Error("initialPassword must be at least 12 characters.");
    }
    const passwordHash = await hashPassword(args.initialPassword);
    const now = Date.now();

    const existingUser = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", prodAccount.email))
      .first();

    if (existingUser) {
      await ctx.db.patch(existingUser._id, {
        passwordHash,
        role: "admin",
        activeRole: "admin",
        isVerified: true,
        isVerifiedAgent: true,
        isVerifiedMerchant: true,
        isVerifiedDriver: true,
        verificationBadge: "GREEN_TICK",
        verificationStatus: "verified",
        kycStatus: "VERIFIED",
        isActive: true,
        updatedAt: now,
      });
      existing.push(`${prodAccount.email} (synced)`);
    } else {
      // No session token is created here: the administrator signs in normally, which issues a
      // role-bounded (8 hour) session. A standing token with no expiry must never exist.
      await ctx.db.insert("users", {
        email: prodAccount.email,
        phone: prodAccount.phone,
        name: prodAccount.name,
        role: "admin",
        activeRole: "admin",
        passwordHash,
        isVerified: true,
        isVerifiedAgent: true,
        isVerifiedMerchant: true,
        isVerifiedDriver: true,
        verificationBadge: "GREEN_TICK",
        verificationStatus: "verified",
        kycStatus: "VERIFIED",
        isActive: true,
        updatedAt: now,
      });
      seeded.push(`${prodAccount.email} (created)`);
    }

    return { seeded, existing };
  },
});

/**
 * OPERATOR RECOVERY (CLI only — internal, never callable from an app or the dashboard):
 *   npx convex run auth:resetAdminCredentials "{email: '…', newPassword: '…'}"
 * Sets the sign-in email and password of THE administrator account when the owner lost access.
 * Refuses unless there is exactly one admin account, the email is valid and not used by any other
 * account, and the password meets the normal minimum. Signs the admin out everywhere (old sessions
 * stop working). Changes nothing else: role, flags, wallets and every other account stay as they are.
 */
export const resetAdminCredentials = internalMutation({
  args: { email: v.string(), newPassword: v.string() },
  returns: v.object({ success: v.boolean(), adminName: v.string(), email: v.string() }),
  handler: async (ctx, args) => {
    const email = args.email.trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error("Please give a valid email address.");
    if (args.newPassword.length < MIN_PASSWORD_LENGTH) {
      throw new Error(`The password must be at least ${MIN_PASSWORD_LENGTH} characters long.`);
    }
    const admins = [];
    for await (const u of ctx.db.query("users")) {
      if (u.role === "admin") admins.push(u);
      if (admins.length > 1) break;
    }
    if (admins.length !== 1) throw new Error(`Expected exactly one administrator account, found ${admins.length}. Nothing was changed.`);
    const admin = admins[0];
    const taken = await ctx.db.query("users").withIndex("by_email", (q) => q.eq("email", email)).first();
    if (taken && taken._id !== admin._id) throw new Error("This email is already used by another account. Nothing was changed.");

    await ctx.db.patch(admin._id, {
      email,
      passwordHash: await hashPassword(args.newPassword),
      sessionToken: undefined,
      sessionExpiresAt: undefined,
      updatedAt: Date.now(),
    });
    return { success: true, adminName: admin.name, email };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//             PASSWORD RESET (SMS, WHATSAPP, EMAIL)
// ═══════════════════════════════════════════════════════════════════════

export const sendPasswordResetOtp = mutation({
  args: {
    identifier: v.string(), // Phone number or email
    deliveryChannel: v.union(v.literal("sms"), v.literal("whatsapp"), v.literal("email")),
  },
  returns: v.object({
    success: v.boolean(),
    message: v.string(),
    expiresInSeconds: v.number(),
  }),
  handler: async (ctx, args) => {
    // The SAME answer is returned whether or not an account exists (no account enumeration).
    // Only e-mail delivery is implemented: there is no SMS/WhatsApp provider, so we do not
    // claim to have sent one.
    const GENERIC = {
      success: true,
      message:
        "If an account with an email address matches, a 6-digit reset code has been sent to that email. SMS and WhatsApp delivery are not available yet.",
      expiresInSeconds: 600,
    };
    try {
      const rawId = args.identifier.trim();
      if (!rawId) {
        return { success: false, message: "Phone number or email is required", expiresInSeconds: 0 };
      }
      const now = Date.now();

      // Throttle by what the caller typed as well as by account (stops inbox flooding).
      if (!(await consume(ctx, `reset-req:id:${rawId.toLowerCase()}`, RESET_REQUEST_POLICY, now))) {
        return { success: false, message: "Too many reset requests. Please wait 15 minutes and try again.", expiresInSeconds: 0 };
      }

      const user = await findUserByIdentifier(ctx, rawId);
      if (!user || !user.email || user.isActive === false) return GENERIC;
      if (!(await consume(ctx, `reset-req:user:${user._id}`, RESET_REQUEST_POLICY, now))) return GENERIC;

      const normalizedKey = user.email.toLowerCase();
      const existingOtps = await ctx.db
        .query("password_resets")
        .withIndex("by_identifier", (q) => q.eq("identifier", normalizedKey))
        .filter((q) => q.eq(q.field("isUsed"), false))
        .take(20);
      for (const old of existingOtps) await ctx.db.patch(old._id, { isUsed: true });

      const otpCode = secureSixDigitCode();
      await ctx.db.insert("password_resets", {
        identifier: normalizedKey,
        deliveryChannel: "email",
        otpCode: await hashResetCode(normalizedKey, otpCode),
        expiresAt: now + 600 * 1000,
        isUsed: false,
        attempts: 0,
        createdAt: now,
      });

      await ctx.scheduler.runAfter(0, internal.emails.sendOtpEmail, {
        to: normalizedKey,
        otpCode,
        recipientName: user.name ?? "User",
      });
      return GENERIC;
    } catch (err: any) {
      console.error("[sendPasswordResetOtp] error:", err?.message ?? String(err));
      return GENERIC;
    }
  },
});


export const verifyResetOtpAndSetPassword = mutation({
  args: {
    identifier: v.string(),
    otpCode: v.string(),
    newPassword: v.string(),
  },
  returns: v.object({
    success: v.boolean(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    const INVALID = { success: false, message: "Invalid or expired verification code. Please request a new one." };
    try {
      const rawId = args.identifier.trim();
      const code = args.otpCode.trim();
      if (!/^\d{6}$/.test(code)) {
        return { success: false, message: "Please enter a valid 6-digit verification code" };
      }
      if (!args.newPassword || args.newPassword.length < MIN_PASSWORD_LENGTH) {
        return { success: false, message: `New password must be at least ${MIN_PASSWORD_LENGTH} characters long` };
      }
      const now = Date.now();

      const user = await findUserByIdentifier(ctx, rawId);
      if (!user || !user.email) return INVALID;
      const normalizedKey = user.email.toLowerCase();

      // The single most recent active code for this account.
      const record = await ctx.db
        .query("password_resets")
        .withIndex("by_identifier", (q) => q.eq("identifier", normalizedKey))
        .order("desc")
        .first();
      if (!record || record.isUsed || record.expiresAt < now) return INVALID;

      const expected = await hashResetCode(normalizedKey, code);
      if (!safeEqual(expected, record.otpCode)) {
        // Count the wrong guess (returned, not thrown, so it persists). Burn the code at the limit.
        const attempts = (record.attempts ?? 0) + 1;
        await ctx.db.patch(record._id, { attempts, isUsed: attempts >= RESET_CODE_MAX_ATTEMPTS });
        return attempts >= RESET_CODE_MAX_ATTEMPTS
          ? { success: false, message: "Too many incorrect codes. Please request a new code." }
          : INVALID;
      }

      const passwordHash = await hashPassword(args.newPassword);
      // New password => every existing session is invalidated by issuing a fresh one.
      // Receiving and entering the code that was mailed to the account's address proves the owner
      // controls that mailbox.
      await ctx.db.patch(user._id, {
        passwordHash,
        // Role-based lifetime (an administrator gets 8 hours, not 30 days). The reset signs the
        // owner in, so it also counts as the last sign-in.
        ...issueSession(now, user.role === "admin"),
        lastLoginAt: now,
        updatedAt: now,
        ...(user.emailVerifiedAt ? {} : { emailVerifiedAt: now }),
      });
      await ctx.db.patch(record._id, { isUsed: true });
      // A successful reset lifts any login lockout for the account.
      await clearLimit(ctx, `login:user:${user._id}`);

      return { success: true, message: "Password has been successfully updated! You can now sign in." };
    } catch (err: any) {
      console.error("[verifyResetOtpAndSetPassword] error:", err?.message ?? String(err));
      return { success: false, message: "Failed to verify code and reset password." };
    }
  },
});


// ═══════════════════════════════════════════════════════════════════════
//                 DIAGNOSTIC QUERY: USER AUTH STATUS
// ═══════════════════════════════════════════════════════════════════════

// INTERNAL ONLY: returned name/email/phone/role for any identifier (enumeration + PII leak).
export const checkUserAuthStatus = internalQuery({
  args: { identifier: v.string() },
  handler: async (ctx, args) => {
    const user = await findUserByIdentifier(ctx, args.identifier);
    if (!user) return { exists: false };
    return {
      exists: true,
      id: user._id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      role: user.role,
      hasPasswordHash: !!user.passwordHash,
      passwordHashType: user.passwordHash
        ? user.passwordHash.includes(":")
          ? "PBKDF2"
          : "legacy/sha256"
        : "none",
      isVerified: user.isVerified,
      isActive: user.isActive,
    };
  },
});


