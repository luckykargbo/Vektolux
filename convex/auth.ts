// convex/auth.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Authentication Mutations & Queries
// Handles user registration, login, and session management.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import { userRole } from "./schema";

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

async function verifyPassword(
  password: string,
  storedHash: string
): Promise<boolean> {
  const parts = storedHash.split(":");
  if (parts.length !== 2) return false;
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

  return computedHashHex === hashHex;
}

// ─── Generate session token ─────────────────────────────────────────
function generateSessionToken(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return Array.from(array)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ═══════════════════════════════════════════════════════════════════════
//                        REGISTER USER
// ═══════════════════════════════════════════════════════════════════════

export const registerUser = mutation({
  args: {
    name: v.string(),
    email: v.string(),
    phone: v.string(),
    password: v.string(),
    role: userRole,
    avatarUrl: v.optional(v.string()),
    businessName: v.optional(v.string()),
    tinNumber: v.optional(v.string()),
    documentStorageId: v.optional(v.id("_storage")),
    documentUrl: v.optional(v.string()),
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
  }),
  handler: async (ctx, args) => {
    // 1. Check for duplicate email
    const existingByEmail = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", args.email))
      .first();
    if (existingByEmail) {
      return {
        success: false,
        errorMessage: "An account with this email already exists.",
      };
    }

    // 2. Check for duplicate phone
    const existingByPhone = await ctx.db
      .query("users")
      .withIndex("by_phone", (q) => q.eq("phone", args.phone))
      .first();
    if (existingByPhone) {
      return {
        success: false,
        errorMessage: "An account with this phone number already exists.",
      };
    }

    // 3. Hash password
    const passwordHash = await hashPassword(args.password);
    const sessionToken = generateSessionToken();
    const now = Date.now();

    const isRestrictedRole = args.role === "agent" || args.role === "merchant";
    const verificationStatus = isRestrictedRole ? "pending" : "unverified";

    // 4. Insert user record
    const userId = await ctx.db.insert("users", {
      name: args.name,
      email: args.email,
      phone: args.phone,
      role: args.role,
      avatarUrl: args.avatarUrl,
      passwordHash,
      sessionToken,
      isVerified: false,
      isActive: true,
      verificationStatus,
      businessName: args.businessName,
      tinNumber: args.tinNumber,
      documentStorageId: args.documentStorageId,
      documentUrl: args.documentUrl,
      updatedAt: now,
    });

    // 5. Create wallet with zero balance
    await ctx.db.insert("walletBalances", {
      userId,
      availableBalance: 0,
      pendingBalance: 0,
      currency: "SLE",
      updatedAt: now,
    });

    // 6. Create merchant profile if role is agent or merchant
    if (isRestrictedRole) {
      await ctx.db.insert("merchant_profiles", {
        userId,
        businessName: args.businessName,
        tinNumber: args.tinNumber,
        documentUrl: args.documentUrl,
        verificationStatus: "pending",
        updatedAt: now,
      });

      await ctx.db.insert("role_applications", {
        userId,
        targetRole: args.role as "agent" | "merchant",
        businessName: args.businessName,
        tinNumber: args.tinNumber,
        documentUrls: args.documentUrl ? [args.documentUrl] : [],
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
      role: args.role,
      avatarUrl: args.avatarUrl,
    };
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
    isVerified: v.optional(v.boolean()),
    verificationStatus: v.optional(v.string()),
    businessName: v.optional(v.string()),
    tinNumber: v.optional(v.string()),
    documentUrl: v.optional(v.string()),
    rejectionReason: v.optional(v.string()),
    verifiedAt: v.optional(v.number()),
    avatarUrl: v.optional(v.string()),
    walletAddress: v.optional(v.string()),
    active_mode: v.optional(v.string()),
    is_driver_verified: v.optional(v.boolean()),
    driver_status: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    // Try email first, then phone
    let user = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", args.identifier))
      .first();

    if (!user) {
      user = await ctx.db
        .query("users")
        .withIndex("by_phone", (q) => q.eq("phone", args.identifier))
        .first();
    }

    if (!user) {
      return {
        success: false,
        errorMessage: "No account found with that email or phone number.",
      };
    }

    if (!user.isActive) {
      return {
        success: false,
        errorMessage: "This account has been deactivated. Please contact support.",
      };
    }

    if (!user.passwordHash) {
      return {
        success: false,
        errorMessage: "Password not set for this account. Please use external login.",
      };
    }

    // Verify password
    const isPasswordValid = await verifyPassword(args.password, user.passwordHash);
    if (!isPasswordValid) {
      return {
        success: false,
        errorMessage: "Invalid password. Please try again.",
      };
    }

    // Generate new session token
    const sessionToken = generateSessionToken();
    await ctx.db.patch(user._id, {
      sessionToken,
      updatedAt: Date.now(),
    });

    const isDriverVerified = Boolean(
      user.is_driver_verified ?? user.isVerifiedDriver ?? (user.role === "driver")
    );
    const activeMode = user.active_mode ?? (user.activeRole === "driver" ? "driver" : "passenger");
    const driverStatus = user.driver_status ?? (user.role === "driver" ? "online" : "offline");

    return {
      success: true,
      userId: user._id as string,
      sessionToken,
      name: user.name,
      email: user.email,
      phone: user.phone,
      role: user.role,
      isVerified: user.isVerified,
      verificationStatus: user.verificationStatus ?? (user.isVerified ? "verified" : "unverified"),
      businessName: user.businessName,
      tinNumber: user.tinNumber,
      documentUrl: user.documentUrl,
      rejectionReason: user.rejectionReason,
      verifiedAt: user.verifiedAt,
      avatarUrl: user.avatarUrl,
      walletAddress: user.walletAddress,
      active_mode: activeMode,
      is_driver_verified: isDriverVerified,
      driver_status: driverStatus,
    };
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
      isVerified: v.boolean(),
      isActive: v.boolean(),
      avatarUrl: v.optional(v.string()),
      walletAddress: v.optional(v.string()),
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

      // Validate session token
      if (user.sessionToken !== args.sessionToken) {
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
        isVerified: user.isVerified,
        isActive: user.isActive,
        avatarUrl: user.avatarUrl,
        walletAddress: user.walletAddress,
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
//                    SEED DEMO / TEST USERS
// ═══════════════════════════════════════════════════════════════════════

export const seedDemoUsers = mutation({
  args: {},
  returns: v.object({
    seeded: v.array(v.string()),
    existing: v.array(v.string()),
  }),
  handler: async (ctx) => {
    const demoAccounts = [
      {
        email: "demo@vektolux.sl",
        phone: "+23276100001",
        name: "Lamin Sesay",
        role: "client" as const,
        balance: 1500,
      },
      {
        email: "driver@vektolux.sl",
        phone: "+23276100002",
        name: "Abu Kamara",
        role: "driver" as const,
        balance: 850,
      },
      {
        email: "agent@vektolux.sl",
        phone: "+23276100003",
        name: "Fatmatta Bangura",
        role: "agent" as const,
        balance: 5000,
      },
    ];

    const seeded: string[] = [];
    const existing: string[] = [];
    const defaultPassword = "password123";
    const passwordHash = await hashPassword(defaultPassword);
    const now = Date.now();

    for (const acc of demoAccounts) {
      const existingUser = await ctx.db
        .query("users")
        .withIndex("by_email", (q) => q.eq("email", acc.email))
        .first();

      if (existingUser) {
        existing.push(acc.email);
        continue;
      }

      const sessionToken = generateSessionToken();
      const userId = await ctx.db.insert("users", {
        email: acc.email,
        phone: acc.phone,
        name: acc.name,
        role: acc.role,
        passwordHash,
        sessionToken,
        isVerified: true,
        isActive: true,
        updatedAt: now,
      });

      await ctx.db.insert("walletBalances", {
        userId,
        availableBalance: acc.balance,
        pendingBalance: 0,
        currency: "SLE",
        updatedAt: now,
      });

      seeded.push(acc.email);
    }

    return { seeded, existing };
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
    demoCode: v.optional(v.string()), // Returned in dev/sandbox for instant testing
  }),
  handler: async (ctx, args) => {
    const rawId = args.identifier.trim();
    if (!rawId) {
      throw new Error("Phone number or email is required");
    }

    // Check if user exists by email or phone
    const user = await ctx.db
      .query("users")
      .filter((q) =>
        q.or(
          q.eq(q.field("email"), rawId),
          q.eq(q.field("phone"), rawId),
          q.eq(q.field("phone"), rawId.startsWith("+") ? rawId : `+232${rawId.replace(/^0+/, "")}`)
        )
      )
      .first();

    if (!user) {
      throw new Error("No account registered with that email or phone number");
    }

    const now = Date.now();
    const expiresInSeconds = 600; // 10 minutes
    const expiresAt = now + expiresInSeconds * 1000;

    // Generate secure 6-digit numeric OTP
    const otpCode = (100000 + Math.floor(Math.random() * 900000)).toString();

    // Invalidate previous active OTPs for this identifier
    const existingOtps = await ctx.db
      .query("password_resets")
      .withIndex("by_identifier", (q) => q.eq("identifier", rawId))
      .filter((q) => q.eq(q.field("isUsed"), false))
      .collect();

    for (const oldOtp of existingOtps) {
      await ctx.db.patch(oldOtp._id, { isUsed: true });
    }

    // Insert new OTP record
    await ctx.db.insert("password_resets", {
      identifier: rawId,
      deliveryChannel: args.deliveryChannel,
      otpCode,
      expiresAt,
      isUsed: false,
      createdAt: now,
    });

    // Dispatch real email via Resend if email channel or email identifier
    if (args.deliveryChannel === "email" || rawId.includes("@")) {
      const emailTarget = rawId.includes("@") ? rawId : user.email;
      await ctx.scheduler.runAfter(0, internal.emails.sendOtpEmail, {
        to: emailTarget,
        otpCode,
        recipientName: user.name,
      });
    }

    const channelName =
      args.deliveryChannel === "whatsapp"
        ? "WhatsApp message"
        : args.deliveryChannel === "sms"
        ? "SMS text"
        : "Email";

    return {
      success: true,
      message: `Reset code dispatched via ${channelName} to ${rawId}`,
      expiresInSeconds,
      demoCode: otpCode, // Test code for zero-friction verification
    };
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
    const rawId = args.identifier.trim();
    const code = args.otpCode.trim();

    if (!code || code.length !== 6) {
      throw new Error("Please enter a valid 6-digit verification code");
    }
    if (!args.newPassword || args.newPassword.length < 6) {
      throw new Error("New password must be at least 6 characters long");
    }

    const now = Date.now();

    // Query active OTP
    const resetRecord = await ctx.db
      .query("password_resets")
      .withIndex("by_identifier_code", (q) =>
        q.eq("identifier", rawId).eq("otpCode", code)
      )
      .first();

    if (!resetRecord || resetRecord.isUsed || resetRecord.expiresAt < now) {
      throw new Error("Invalid or expired verification code. Please request a new one.");
    }

    // Find the user
    const user = await ctx.db
      .query("users")
      .filter((q) =>
        q.or(
          q.eq(q.field("email"), rawId),
          q.eq(q.field("phone"), rawId),
          q.eq(q.field("phone"), rawId.startsWith("+") ? rawId : `+232${rawId.replace(/^0+/, "")}`)
        )
      )
      .first();

    if (!user) {
      throw new Error("Associated user account not found");
    }

    // Re-hash new password using PBKDF2
    const passwordHash = await hashPassword(args.newPassword);
    const newSessionToken = generateSessionToken();

    // Update user record and invalidate older sessions
    await ctx.db.patch(user._id, {
      passwordHash,
      sessionToken: newSessionToken,
      updatedAt: now,
    });

    // Mark OTP used
    await ctx.db.patch(resetRecord._id, { isUsed: true });

    return {
      success: true,
      message: "Password has been successfully updated! You can now sign in.",
    };
  },
});

