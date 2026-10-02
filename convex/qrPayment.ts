// convex/qrPayment.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — QR Payments (Receive / Scan / Pay)
//
// Security model:
//  • The QR encodes ONLY an opaque, unguessable token:  vektolux://pay?r=<token>
//    No user id, phone, name, balance, amount or secret is inside the code.
//  • Everything (recipient, fixed amount, expiry, single-use, status) is resolved
//    SERVER-SIDE from the token. A scanned amount/recipient is never trusted.
//  • Scanning is READ-ONLY (`resolveQR`). Money only moves in `payQR`, after the
//    sender explicitly confirms and authorizes with their PIN.
//  • `payQR` is idempotent (per-sender idempotency key) and single-use QRs can
//    only ever be paid once, even under concurrent scans.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSelf } from "./lib/auth";
import { verifyAndTrackPin } from "./lib/pin";
import { assertValidAmount, findByIdempotencyKey, transferFunds, DEFAULT_CURRENCY, MAX_SINGLE_TRANSFER } from "./walletCore";

const TOKEN_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"; // no ambiguous chars
const TOKEN_LENGTH = 32;
const MAX_ACTIVE_QR_PER_USER = 50;
const MAX_NOTE_LENGTH = 140;

function generateToken(): string {
  const bytes = new Uint8Array(TOKEN_LENGTH);
  crypto.getRandomValues(bytes);
  let out = "";
  for (let i = 0; i < TOKEN_LENGTH; i++) out += TOKEN_ALPHABET[bytes[i] % TOKEN_ALPHABET.length];
  return out;
}

/** Extracts the token from `vektolux://pay?r=<token>` (or a bare token). Never reads other params. */
export function parseQrToken(payload: string): string | null {
  const raw = (payload ?? "").trim();
  if (!raw || raw.length > 512) return null;
  let candidate = raw;
  if (raw.startsWith("vektolux://")) {
    const m = raw.match(/[?&]r=([^&#]+)/);
    if (!m) return null;
    candidate = decodeURIComponent(m[1]);
  }
  return /^[a-z0-9]{16,64}$/.test(candidate) ? candidate : null;
}

function cleanNote(note: string | undefined): string | undefined {
  const t = note?.trim();
  if (!t) return undefined;
  return t.slice(0, MAX_NOTE_LENGTH);
}

// ─── RECEIVE: create a QR payment request ────────────────────────────

export const createReceiveQR = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    amount: v.optional(v.number()), // omit = payer chooses the amount
    note: v.optional(v.string()),
    singleUse: v.optional(v.boolean()),
    ttlMinutes: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { userId, user } = await requireSelf(ctx, args.sessionToken);
    if (!user.isActive) throw new Error("Your account is not active.");

    const hasFixed = args.amount !== undefined && args.amount !== null;
    const amount = hasFixed ? assertValidAmount(args.amount, MAX_SINGLE_TRANSFER) : undefined;

    // Fixed-amount requests default to single-use with a 24h life; open ones are reusable.
    const singleUse = args.singleUse ?? hasFixed;
    let ttl = args.ttlMinutes ?? (hasFixed ? 24 * 60 : undefined);
    if (ttl !== undefined) {
      if (!Number.isFinite(ttl) || ttl < 1 || ttl > 60 * 24 * 30) throw new Error("Invalid expiry.");
    }

    const active = await ctx.db
      .query("qr_payment_requests")
      .withIndex("by_receiver", (q) => q.eq("receiverId", userId))
      .order("desc")
      .take(MAX_ACTIVE_QR_PER_USER + 1);
    if (active.filter((r) => r.status === "active").length >= MAX_ACTIVE_QR_PER_USER) {
      throw new Error("Too many active payment requests. Cancel some before creating new ones.");
    }

    const now = Date.now();
    const token = generateToken();
    const expiresAt = ttl !== undefined ? now + ttl * 60000 : undefined;
    await ctx.db.insert("qr_payment_requests", {
      token,
      receiverId: userId,
      currency: DEFAULT_CURRENCY,
      amount,
      note: cleanNote(args.note),
      singleUse,
      status: "active",
      expiresAt,
      createdAt: now,
      updatedAt: now,
    });

    return {
      token,
      qrPayload: `vektolux://pay?r=${token}`,
      amount: amount ?? null,
      note: cleanNote(args.note) ?? null,
      singleUse,
      expiresAt: expiresAt ?? null,
      currency: DEFAULT_CURRENCY,
    };
  },
});

export const cancelReceiveQR = mutation({
  args: { sessionToken: v.optional(v.string()), token: v.string() },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const qr = await ctx.db.query("qr_payment_requests").withIndex("by_token", (q) => q.eq("token", args.token)).first();
    if (!qr || qr.receiverId !== userId) throw new Error("Payment request not found.");
    if (qr.status === "active") await ctx.db.patch(qr._id, { status: "cancelled", updatedAt: Date.now() });
    return { success: true };
  },
});

/** Receiver polls this to show "Payment Received". Owner-only. */
export const getMyQRStatus = query({
  args: { sessionToken: v.optional(v.string()), token: v.string() },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const qr = await ctx.db.query("qr_payment_requests").withIndex("by_token", (q) => q.eq("token", args.token)).first();
    if (!qr || qr.receiverId !== userId) throw new Error("Payment request not found.");

    let payer: { name: string } | null = null;
    let paidAmount: number | null = null;
    if (qr.paidByUserId) {
      const p = await ctx.db.get(qr.paidByUserId);
      if (p) payer = { name: p.name };
    }
    if (qr.paidTransactionId) {
      const tx = await ctx.db
        .query("transactions")
        .withIndex("by_transaction_id", (q) => q.eq("transactionId", qr.paidTransactionId!))
        .filter((q) => q.eq(q.field("userId"), userId))
        .first();
      if (tx) paidAmount = tx.amount;
    }
    return {
      status: qr.status,
      amount: qr.amount ?? null,
      paidAmount,
      payerName: payer?.name ?? null,
      transactionId: qr.paidTransactionId ?? null,
      currency: qr.currency,
    };
  },
});

// ─── SCAN: read-only resolution (never moves money) ──────────────────

export const resolveQR = query({
  args: { sessionToken: v.optional(v.string()), payload: v.string() },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const token = parseQrToken(args.payload);
    if (!token) return { valid: false as const, reason: "INVALID_CODE", message: "This is not a valid Vektolux payment code." };

    const qr = await ctx.db.query("qr_payment_requests").withIndex("by_token", (q) => q.eq("token", token)).first();
    if (!qr) return { valid: false as const, reason: "NOT_FOUND", message: "Payment request not found." };

    const receiver = await ctx.db.get(qr.receiverId);
    if (!receiver || receiver.isActive === false) {
      return { valid: false as const, reason: "RECEIVER_INACTIVE", message: "This recipient cannot receive payments." };
    }
    if (qr.receiverId === userId) {
      return { valid: false as const, reason: "OWN_CODE", message: "You cannot pay your own payment code." };
    }
    if (qr.status === "paid") return { valid: false as const, reason: "ALREADY_PAID", message: "This payment request was already paid." };
    if (qr.status === "cancelled") return { valid: false as const, reason: "CANCELLED", message: "This payment request was cancelled." };
    if (qr.expiresAt !== undefined && qr.expiresAt < Date.now()) {
      return { valid: false as const, reason: "EXPIRED", message: "This payment request has expired." };
    }

    return {
      valid: true as const,
      recipientName: receiver.name,
      recipientIsVerified: receiver.isVerified === true,
      fixedAmount: qr.amount ?? null, // server-side truth; the payer cannot change it
      note: qr.note ?? null,
      currency: qr.currency,
      expiresAt: qr.expiresAt ?? null,
    };
  },
});

// ─── PAY: explicit, confirmed, idempotent ────────────────────────────

export const payQR = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    payload: v.string(),
    amount: v.optional(v.number()), // required only when the QR has no fixed amount
    pin: v.string(),
    idempotencyKey: v.string(), // client-generated UUID per payment attempt
    note: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: senderId, user: sender } = await requireSelf(ctx, args.sessionToken);

    const key = args.idempotencyKey.trim();
    if (key.length < 16 || key.length > 100) throw new Error("A valid idempotency key is required.");

    // Replay of an already-processed payment: return the original receipt, move nothing.
    const prior = await findByIdempotencyKey(ctx, senderId, key);
    if (prior) {
      const rcpt = prior.counterpartyId ? await ctx.db.get(prior.counterpartyId) : null;
      return {
        success: true as const,
        duplicate: true,
        transactionId: prior.transactionId ?? (prior._id as string),
        amount: prior.amount,
        currency: prior.currency,
        recipientName: rcpt?.name ?? prior.counterpartyName ?? "Recipient",
        timestamp: prior.createdAt ?? prior._creationTime,
      };
    }

    const token = parseQrToken(args.payload);
    if (!token) throw new Error("INVALID_CODE: This is not a valid Vektolux payment code.");
    const qr = await ctx.db.query("qr_payment_requests").withIndex("by_token", (q) => q.eq("token", token)).first();
    if (!qr) throw new Error("NOT_FOUND: Payment request not found.");
    if (qr.status !== "active") throw new Error(`UNAVAILABLE: This payment request is ${qr.status}.`);
    if (qr.expiresAt !== undefined && qr.expiresAt < Date.now()) throw new Error("EXPIRED: This payment request has expired.");
    if (qr.receiverId === senderId) throw new Error("INVALID_TRANSFER: You cannot pay yourself.");

    const receiver = await ctx.db.get(qr.receiverId);
    if (!receiver || receiver.isActive === false) throw new Error("RECEIVER_INACTIVE: This recipient cannot receive payments.");

    // The amount is decided by the SERVER: a fixed QR amount always wins.
    let amount: number;
    if (qr.amount !== undefined) {
      if (args.amount !== undefined && Math.abs(args.amount - qr.amount) > 0.001) {
        throw new Error("AMOUNT_MISMATCH: This payment request has a fixed amount.");
      }
      amount = qr.amount;
    } else {
      amount = assertValidAmount(args.amount, MAX_SINGLE_TRANSFER);
    }

    // Authorize with PIN. Failures are RETURNED (not thrown) so the attempt counter commits.
    const pinCheck = await verifyAndTrackPin(ctx, sender, args.pin);
    if (!pinCheck.ok) {
      return { success: false as const, errorCode: pinCheck.code, message: pinCheck.message };
    }

    const result = await transferFunds(ctx, {
      senderId,
      recipientId: qr.receiverId,
      amount,
      currency: qr.currency,
      idempotencyKey: key,
      note: cleanNote(args.note) ?? qr.note,
      referenceType: "qr_payment",
      referenceId: qr._id as string,
    });

    const now = Date.now();
    if (qr.singleUse) {
      await ctx.db.patch(qr._id, {
        status: "paid",
        paidTransactionId: result.transactionId,
        paidByUserId: senderId,
        updatedAt: now,
      });
    }

    await ctx.db.insert("user_notifications", {
      userId: qr.receiverId as string,
      targetType: "single_user",
      title: "Payment Received",
      body: `You received ${qr.currency} ${amount.toFixed(2)} from ${sender.name}.`,
      read: false,
      createdAt: now,
    });

    return {
      success: true as const,
      duplicate: false,
      transactionId: result.transactionId,
      amount,
      currency: qr.currency,
      recipientName: receiver.name,
      timestamp: result.timestamp,
    };
  },
});
