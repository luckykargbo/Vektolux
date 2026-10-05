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
import { issueSession } from "./lib/session";
import { restoreLegacyAgentRole } from "./lib/legacyRoles";

const MIN_PASSWORD_LENGTH = 8;
// Login: 5 wrong attempts within 15 min locks that account/identifier for 15 min.
const LOGIN_POLICY = { max: 5, windowMs: 15 * 60 * 1000, lockMs: 15 * 60 * 1000 };
// Reset requests: at most 3 codes per 15 min per account (stops inbox flooding).
const RESET_REQUEST_POLICY = { max: 3, windowMs: 15 * 60 * 1000 };
// Reset code guesses: a code is burned after 5 wrong guesses.
const RESET_CODE_MAX_ATTEMPTS = 5;

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Reset codes are stored hashed (bound to the identifier), never in plain text. */
async function hashResetCode(identifier: string, code: string): Promise<string> {
  return "h1:" + (await sha256Hex(`vektolux-reset:${identifier}:${code}`));
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

// ─── Generate session token ─────────────────────────────────────────
function generateSessionToken(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return Array.from(array)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
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

      // 1. Check for duplicate email (case-insensitive)
      const existingByEmail = await findUserByIdentifier(ctx, normalizedEmail);
      if (existingByEmail) {
        return {
          success: false,
          errorMessage: "An account with this email already exists.",
        };
      }

      // 2. Check for duplicate phone
      const existingByPhone = await findUserByIdentifier(ctx, normalizedPhone);
      if (existingByPhone) {
        return {
          success: false,
          errorMessage: "An account with this phone number already exists.",
        };
      }

      if (!args.password || args.password.length < MIN_PASSWORD_LENGTH) {
        return { success: false, errorMessage: `Password must be at least ${MIN_PASSWORD_LENGTH} characters long.` };
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

      return {
        success: true,
        userId: userId as string,
        sessionToken,
        name: args.name,
        email: args.email,
        phone: args.phone,
        role: canonicalRole,
        avatarUrl: args.avatarUrl,
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
    address: v.optional(v.string()),
    region: v.optional(v.string()),
    isVerified: v.optional(v.boolean()),
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

      const idLock = await lockRemainingMs(ctx, idKey, now);
      if (idLock > 0) {
        return { success: false, errorMessage: `Too many failed attempts. Please try again in ${minutes(idLock)} minute(s) or reset your password.` };
      }

      const user = await findUserByIdentifier(ctx, sanitizedId);
      const userKey = user ? `login:user:${user._id}` : undefined;
      if (userKey) {
        const userLock = await lockRemainingMs(ctx, userKey, now);
        if (userLock > 0) {
          return { success: false, errorMessage: `Too many failed attempts. Please try again in ${minutes(userLock)} minute(s) or reset your password.` };
        }
      }

      // One generic answer for "no such account", "no password set" and "wrong password", so the
      // response never reveals which emails/phones are registered. Every failure is counted.
      const ok = !!user && !!user.passwordHash && (await verifyPassword(args.password, user.passwordHash));
      if (!ok || !user) {
        await recordFailure(ctx, idKey, LOGIN_POLICY, now);
        if (userKey) await recordFailure(ctx, userKey, LOGIN_POLICY, now);
        return { success: false, errorMessage: GENERIC };
      }

      // Correct password: only now is it safe to say the account is deactivated.
      if (!user.isActive) {
        return { success: false, errorMessage: "This account has been deactivated. Please contact support." };
      }

      await clearLimit(ctx, idKey);
      await clearLimit(ctx, userKey!);

      // An agent approved by the OLD admin flow (which never changed users.role) gets the role the
      // admin granted, from the stored approval evidence only (lib/legacyRoles.ts). Idempotent.
      const legacy = await restoreLegacyAgentRole(ctx, user, { now });
      const role = legacy.restored ? ("agent" as const) : user.role;

      const { sessionToken, sessionExpiresAt } = issueSession(now);
      // Transparently upgrade legacy (SHA-256 / plaintext) password records to salted PBKDF2.
      const upgradedHash = user.passwordHash!.includes(":") ? undefined : await hashPassword(args.password);
      await ctx.db.patch(user._id, {
        sessionToken,
        sessionExpiresAt,
        lastLoginAt: now,
        updatedAt: now,
        ...(upgradedHash ? { passwordHash: upgradedHash } : {}),
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
      if (typeof user.sessionExpiresAt === "number" && user.sessionExpiresAt <= Date.now()) {
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
      const sessionToken = generateSessionToken();
      await ctx.db.insert("users", {
        email: prodAccount.email,
        phone: prodAccount.phone,
        name: prodAccount.name,
        role: "admin",
        activeRole: "admin",
        passwordHash,
        sessionToken,
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
      await ctx.db.patch(user._id, { passwordHash, ...issueSession(now), updatedAt: now });
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


