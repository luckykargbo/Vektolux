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
    businessName: v.optional(v.string()),
    tinNumber: v.optional(v.string()),
  },
  returns: v.object({
    userId: v.string(),
    sessionToken: v.string(),
    name: v.string(),
    email: v.string(),
    phone: v.string(),
    role: v.string(),
  }),
  handler: async (ctx, args) => {
    // 1. Check for duplicate email
    const existingByEmail = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", args.email))
      .first();
    if (existingByEmail) {
      throw new Error("An account with this email already exists.");
    }

    // 2. Check for duplicate phone
    const existingByPhone = await ctx.db
      .query("users")
      .withIndex("by_phone", (q) => q.eq("phone", args.phone))
      .first();
    if (existingByPhone) {
      throw new Error("An account with this phone number already exists.");
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
      userId: userId as string,
      sessionToken,
      name: args.name,
      email: args.email,
      phone: args.phone,
      role: args.role,
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
    userId: v.string(),
    sessionToken: v.string(),
    name: v.string(),
    email: v.string(),
    phone: v.string(),
    role: v.string(),
    isVerified: v.boolean(),
    avatarUrl: v.optional(v.string()),
    walletAddress: v.optional(v.string()),
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
      throw new Error("No account found with this email or phone number.");
    }

    if (!user.isActive) {
      throw new Error("This account has been deactivated. Contact support.");
    }

    // Verify password
    const isPasswordValid = await verifyPassword(
      args.password,
      user.passwordHash ?? ""
    );
    if (!isPasswordValid) {
      throw new Error("Invalid password. Please try again.");
    }

    // Generate new session token
    const sessionToken = generateSessionToken();
    await ctx.db.patch(user._id, {
      sessionToken,
      updatedAt: Date.now(),
    });

    return {
      userId: user._id as string,
      sessionToken,
      name: user.name,
      email: user.email,
      phone: user.phone,
      role: user.role,
      isVerified: user.isVerified,
      avatarUrl: user.avatarUrl,
      walletAddress: user.walletAddress,
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
      };
    } catch {
      return null;
    }
  },
});
