// convex/auth.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Authentication Mutations & Queries
// Handles user registration, login, and session management.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
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
    if (args.role === "agent" || args.role === "merchant") {
      await ctx.db.insert("merchant_profiles", {
        userId,
        businessName: args.businessName,
        tinNumber: args.tinNumber,
        verificationStatus: "pending",
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
        errorMessage: "No account found with this email or phone number.",
      };
    }

    if (!user.isActive) {
      return {
        success: false,
        errorMessage: "This account has been deactivated. Contact support.",
      };
    }

    // Verify password
    const isPasswordValid = await verifyPassword(
      args.password,
      user.passwordHash ?? ""
    );
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

