// convex/walletCore.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Server-Authoritative Wallet Ledger Core
//
// Balance model (per user, per currency) — `walletBalances`:
//   availableBalance : spendable AND withdrawable funds
//   escrowBalance    : funds protected in an active deal (NOT spendable/withdrawable)
//   pendingBalance   : funds reserved for an in-flight withdrawal (NOT spendable)
//
// Every movement writes an immutable `transactions` row in the SAME Convex
// transaction as the balance change, so the cached balance is always backed by
// an auditable ledger. Nothing here trusts client-supplied amounts or identities:
// callers (public mutations) authenticate first and pass resolved user ids.
//
// Idempotency: each operation accepts an idempotency key / provider reference.
// A replay returns the original result and moves no money.
// ═══════════════════════════════════════════════════════════════════════

import { Id, Doc } from "./_generated/dataModel";
import { internalMutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSelf } from "./lib/auth";

export const DEFAULT_CURRENCY = "SLE";
export const MAX_SINGLE_TRANSFER = 500000;

export const round2 = (n: number): number => Math.round(n * 100) / 100;

/** Validates a money amount: finite, > 0, at most 2 decimal places of precision, optional cap. */
export function assertValidAmount(raw: unknown, max?: number): number {
  const n = Number(raw);
  if (typeof raw === "boolean" || !Number.isFinite(n) || n <= 0) {
    throw new Error("INVALID_AMOUNT: Amount must be a number greater than 0.");
  }
  const amount = round2(n);
  if (amount < 0.01) throw new Error("INVALID_AMOUNT: Amount must be at least 0.01.");
  if (max !== undefined && amount > max) {
    throw new Error(`AMOUNT_EXCEEDS_LIMIT: Maximum allowed is ${max.toFixed(2)}.`);
  }
  return amount;
}

export type EscrowTxExtra = {
  partnerSplitPercent?: number;
  partnerAmount?: number;
  platformFeeAmount?: number;
  agentNumber?: string;
  blockchainTxHash?: string;
};

function newTxCode(): string {
  return "TX-" + crypto.randomUUID();
}

// ─── Wallet primitives ───────────────────────────────────────────────

export async function getOrCreateUserWallet(
  ctx: { db: any },
  userId: Id<"users">,
  currency: string = DEFAULT_CURRENCY
): Promise<Doc<"walletBalances">> {
  const existing = await ctx.db
    .query("walletBalances")
    .withIndex("by_user_currency", (q: any) => q.eq("userId", userId).eq("currency", currency))
    .first();
  if (existing) return existing;

  const id = await ctx.db.insert("walletBalances", {
    userId,
    availableBalance: 0,
    pendingBalance: 0,
    escrowBalance: 0,
    currency,
    updatedAt: Date.now(),
  });
  return (await ctx.db.get(id))!;
}

export async function findByIdempotencyKey(
  ctx: { db: any },
  userId: Id<"users">,
  key: string | undefined
): Promise<Doc<"transactions"> | null> {
  if (!key) return null;
  return await ctx.db
    .query("transactions")
    .withIndex("by_user_idempotency", (q: any) => q.eq("userId", userId).eq("idempotencyKey", key))
    .first();
}

async function postDoubleEntry(
  ctx: { db: any },
  code: string,
  description: string,
  entries: Array<{
    accountType:
      | "CLIENT_AVAILABLE"
      | "CLIENT_ESCROW_LOCKED"
      | "OWNER_AVAILABLE"
      | "PLATFORM_REVENUE_REALIZED"
      | "SUBSCRIPTION_REVENUE"
      | "TELCO_CLEARING_LIABILITY";
    userId?: Id<"users">;
    direction: "DEBIT" | "CREDIT";
    amount: number;
  }>,
  currency: string
) {
  let debit = 0;
  let credit = 0;
  for (const e of entries) {
    if (e.direction === "DEBIT") debit += e.amount;
    else credit += e.amount;
  }
  if (Math.abs(debit - credit) > 0.005) {
    throw new Error("LEDGER_IMBALANCE: debits must equal credits.");
  }
  const now = Date.now();
  const txId = await ctx.db.insert("ledger_transactions", { transactionCode: code, description, createdAt: now });
  for (const e of entries) {
    await ctx.db.insert("ledger_entries", {
      transactionId: txId,
      accountType: e.accountType,
      userId: e.userId,
      direction: e.direction,
      amount: e.amount,
      currency,
      createdAt: now,
    });
  }
}

// ─── Refund-recovery protection ──────────────────────────────────────

/**
 * Amount of a user's AVAILABLE balance reserved for open refund recoveries (reversals where they
 * were the paid recipient and could not repay in full), unless an admin lifted the protection.
 */
export async function protectedRecoveryAmount(ctx: { db: any }, userId: Id<"users">, currency: string): Promise<number> {
  const rows = await ctx.db
    .query("payment_reversals")
    .withIndex("by_recipient_status", (q: any) => q.eq("recipientId", userId).eq("status", "pending_recovery"))
    .collect();
  return round2(
    rows
      .filter((r: Doc<"payment_reversals">) => r.currency === currency && r.withdrawalProtection !== "lifted")
      .reduce((s: number, r: Doc<"payment_reversals">) => s + r.outstandingAmount, 0)
  );
}

/** User-initiated debits may use only funds ABOVE the protected recovery amount. */
async function assertNotRecoveryProtected(ctx: { db: any }, wallet: Doc<"walletBalances">, amount: number, currency: string) {
  const reserved = await protectedRecoveryAmount(ctx, wallet.userId, currency);
  if (reserved <= 0) return;
  const usable = round2(Math.max(0, wallet.availableBalance - reserved));
  if (usable + 0.0001 < amount) {
    throw new Error(
      `RECOVERY_HOLD: ${currency} ${reserved.toFixed(2)} of your balance is reserved for an open refund recovery. You can use up to ${currency} ${usable.toFixed(2)}.`
    );
  }
}

// ─── Deposits (credit ONLY after server-side provider verification) ──

/**
 * Credits a VERIFIED deposit. The caller (webhook handler / verified poll) is
 * responsible for having confirmed the payment with the provider. Idempotent on
 * (provider, providerReference): a replay never credits twice.
 */
export async function settleVerifiedDeposit(
  ctx: { db: any },
  p: {
    userId: Id<"users">;
    amount: number; // gross paid
    netAmount?: number; // credited to wallet (after provider/platform fee)
    feeAmount?: number;
    currency?: string;
    provider: string;
    providerReference: string;
    description?: string;
  }
): Promise<{ duplicate: boolean; transactionDocId: Id<"transactions">; availableBalance: number }> {
  const currency = p.currency ?? DEFAULT_CURRENCY;
  const gross = assertValidAmount(p.amount);
  const fee = p.feeAmount !== undefined ? round2(p.feeAmount) : 0;
  const net = p.netAmount !== undefined ? round2(p.netAmount) : round2(gross - fee);
  if (net <= 0 || net > gross) throw new Error("INVALID_AMOUNT: Net credit out of range.");
  if (!p.providerReference) throw new Error("A provider reference is required to settle a deposit.");

  const wallet = await getOrCreateUserWallet(ctx, p.userId, currency);

  const existing = await ctx.db
    .query("transactions")
    .withIndex("by_gateway_ref", (q: any) => q.eq("gatewayProvider", p.provider).eq("gatewayReference", p.providerReference))
    .first();

  if (existing) {
    if (existing.userId !== p.userId) {
      throw new Error("Payment reference belongs to a different account.");
    }
    if (existing.status === "completed") {
      return { duplicate: true, transactionDocId: existing._id, availableBalance: wallet.availableBalance };
    }
  }

  const now = Date.now();
  const newAvailable = round2(wallet.availableBalance + net);
  await ctx.db.patch(wallet._id, { availableBalance: newAvailable, updatedAt: now });

  let txDocId: Id<"transactions">;
  if (existing) {
    await ctx.db.patch(existing._id, {
      status: "completed",
      amount: gross,
      netAmount: net,
      feeAmount: fee,
      failureReason: undefined,
      updatedAt: now,
    });
    txDocId = existing._id;
  } else {
    txDocId = await ctx.db.insert("transactions", {
      transactionId: newTxCode(),
      walletId: wallet._id,
      userId: p.userId,
      type: "top_up",
      amount: gross,
      netAmount: net,
      feeAmount: fee,
      currency,
      gatewayProvider: p.provider,
      gatewayReference: p.providerReference,
      status: "completed",
      description: p.description ?? `Wallet deposit via ${p.provider}`,
      createdAt: now,
      updatedAt: now,
    });
  }

  await postDoubleEntry(
    ctx,
    `DEP-${p.provider}-${p.providerReference}`,
    `Verified deposit via ${p.provider}`,
    [
      { accountType: "TELCO_CLEARING_LIABILITY", direction: "DEBIT", amount: gross },
      { accountType: "CLIENT_AVAILABLE", userId: p.userId, direction: "CREDIT", amount: net },
      ...(fee > 0
        ? [{ accountType: "PLATFORM_REVENUE_REALIZED" as const, direction: "CREDIT" as const, amount: fee }]
        : []),
    ],
    currency
  );

  return { duplicate: false, transactionDocId: txDocId, availableBalance: newAvailable };
}

/** Marks a pending deposit failed. Never changes any balance. */
export async function failPendingDeposit(
  ctx: { db: any },
  p: { userId: Id<"users">; provider: string; providerReference: string; reason: string }
): Promise<boolean> {
  const existing = await ctx.db
    .query("transactions")
    .withIndex("by_gateway_ref", (q: any) => q.eq("gatewayProvider", p.provider).eq("gatewayReference", p.providerReference))
    .first();
  if (!existing || existing.userId !== p.userId || existing.status !== "pending") return false;
  await ctx.db.patch(existing._id, { status: "failed", failureReason: p.reason, updatedAt: Date.now() });
  return true;
}

// ─── Wallet-to-wallet transfer (P2P and QR) ──────────────────────────

export async function transferFunds(
  ctx: { db: any },
  p: {
    senderId: Id<"users">;
    recipientId: Id<"users">;
    amount: number;
    currency?: string;
    idempotencyKey?: string;
    note?: string;
    referenceType?: string; // e.g. "p2p_transfer" | "qr_payment"
    referenceId?: string;
  }
): Promise<{
  duplicate: boolean;
  transactionId: string;
  amount: number;
  senderBalanceAfter: number;
  recipientBalanceAfter: number;
  timestamp: number;
}> {
  const currency = p.currency ?? DEFAULT_CURRENCY;
  const amount = assertValidAmount(p.amount, MAX_SINGLE_TRANSFER);
  if (p.senderId === p.recipientId) {
    throw new Error("INVALID_TRANSFER: You cannot transfer funds to yourself.");
  }

  // Idempotent replay: return the original outcome, move nothing.
  const prior = await findByIdempotencyKey(ctx, p.senderId, p.idempotencyKey);
  if (prior) {
    const w = await getOrCreateUserWallet(ctx, p.senderId, currency);
    const rw = await getOrCreateUserWallet(ctx, p.recipientId, currency);
    return {
      duplicate: true,
      transactionId: prior.transactionId ?? (prior._id as string),
      amount: prior.amount,
      senderBalanceAfter: w.availableBalance,
      recipientBalanceAfter: rw.availableBalance,
      timestamp: prior.createdAt ?? prior._creationTime,
    };
  }

  const sender = await ctx.db.get(p.senderId);
  const recipient = await ctx.db.get(p.recipientId);
  if (!sender || sender.isActive === false) throw new Error("SENDER_INACTIVE: Your account is not active.");
  if (!recipient || recipient.isActive === false) throw new Error("RECIPIENT_INACTIVE: Recipient account is not active.");

  const senderWallet = await getOrCreateUserWallet(ctx, p.senderId, currency);
  // Only AVAILABLE funds can be sent: escrow-protected and withdrawal-reserved funds are excluded.
  if (senderWallet.availableBalance < amount) {
    throw new Error(
      `INSUFFICIENT_FUNDS: Available balance (${currency} ${senderWallet.availableBalance.toFixed(2)}) is less than ${currency} ${amount.toFixed(2)}.`
    );
  }
  await assertNotRecoveryProtected(ctx, senderWallet, amount, currency);
  const recipientWallet = await getOrCreateUserWallet(ctx, p.recipientId, currency);

  const now = Date.now();
  const txCode = newTxCode();
  const senderAfter = round2(senderWallet.availableBalance - amount);
  const recipientAfter = round2(recipientWallet.availableBalance + amount);

  await ctx.db.patch(senderWallet._id, { availableBalance: senderAfter, updatedAt: now });
  await ctx.db.patch(recipientWallet._id, { availableBalance: recipientAfter, updatedAt: now });

  const refType = p.referenceType ?? "p2p_transfer";
  await ctx.db.insert("transactions", {
    transactionId: txCode,
    walletId: senderWallet._id,
    userId: p.senderId,
    counterpartyId: p.recipientId,
    counterpartyName: recipient.name,
    counterpartyPhone: recipient.phone,
    type: "p2p_transfer",
    amount,
    feeAmount: 0,
    netAmount: -amount,
    currency,
    status: "completed",
    referenceType: refType,
    referenceId: p.referenceId ?? txCode,
    gatewayProvider: "INTERNAL_WALLET",
    gatewayReference: txCode,
    idempotencyKey: p.idempotencyKey,
    description: p.note ? `Sent to ${recipient.name} — ${p.note}` : `Sent to ${recipient.name}`,
    createdAt: now,
    updatedAt: now,
  });
  await ctx.db.insert("transactions", {
    transactionId: txCode,
    walletId: recipientWallet._id,
    userId: p.recipientId,
    counterpartyId: p.senderId,
    counterpartyName: sender.name,
    counterpartyPhone: sender.phone,
    type: "p2p_transfer",
    amount,
    feeAmount: 0,
    netAmount: amount,
    currency,
    status: "completed",
    referenceType: refType,
    referenceId: p.referenceId ?? txCode,
    gatewayProvider: "INTERNAL_WALLET",
    gatewayReference: txCode,
    description: p.note ? `Received from ${sender.name} — ${p.note}` : `Received from ${sender.name}`,
    createdAt: now,
    updatedAt: now,
  });

  await postDoubleEntry(ctx, txCode, `Transfer ${sender.name} -> ${recipient.name}`, [
    { accountType: "CLIENT_AVAILABLE", userId: p.senderId, direction: "DEBIT", amount },
    { accountType: "CLIENT_AVAILABLE", userId: p.recipientId, direction: "CREDIT", amount },
  ], currency);

  return {
    duplicate: false,
    transactionId: txCode,
    amount,
    senderBalanceAfter: senderAfter,
    recipientBalanceAfter: recipientAfter,
    timestamp: now,
  };
}

// ─── Withdrawals: reserve -> (confirm | release) ─────────────────────

/**
 * Reserves funds for a withdrawal: available -> pending. The money has NOT left the
 * wallet yet; it cannot be spent, transferred or withdrawn again while reserved.
 */
export async function reserveWithdrawalFunds(
  ctx: { db: any },
  p: {
    userId: Id<"users">;
    amount: number;
    currency?: string;
    provider: string;
    destination: string;
    idempotencyKey: string;
  }
): Promise<{ duplicate: boolean; transactionDocId: Id<"transactions">; walletId: Id<"walletBalances">; amount: number }> {
  const currency = p.currency ?? DEFAULT_CURRENCY;
  const amount = assertValidAmount(p.amount);

  const prior = await findByIdempotencyKey(ctx, p.userId, p.idempotencyKey);
  if (prior) {
    return { duplicate: true, transactionDocId: prior._id, walletId: prior.walletId, amount: prior.amount };
  }

  const wallet = await getOrCreateUserWallet(ctx, p.userId, currency);
  // `availableBalance` already EXCLUDES escrow-protected funds, so escrow can never be withdrawn.
  if (wallet.availableBalance < amount) {
    throw new Error(
      `INSUFFICIENT_FUNDS: Withdrawable balance is ${currency} ${wallet.availableBalance.toFixed(2)}. Funds in escrow or already reserved cannot be withdrawn.`
    );
  }
  await assertNotRecoveryProtected(ctx, wallet, amount, currency);

  const now = Date.now();
  await ctx.db.patch(wallet._id, {
    availableBalance: round2(wallet.availableBalance - amount),
    pendingBalance: round2(wallet.pendingBalance + amount),
    updatedAt: now,
  });
  const txDocId = await ctx.db.insert("transactions", {
    transactionId: newTxCode(),
    walletId: wallet._id,
    userId: p.userId,
    type: "withdrawal",
    amount,
    netAmount: -amount,
    feeAmount: 0,
    currency,
    gatewayProvider: p.provider,
    agentNumber: p.destination,
    status: "pending",
    idempotencyKey: p.idempotencyKey,
    description: `Withdrawal of ${currency} ${amount.toFixed(2)} to ${p.provider}`,
    createdAt: now,
    updatedAt: now,
  });
  return { duplicate: false, transactionDocId: txDocId, walletId: wallet._id, amount };
}

/** Payout CONFIRMED by the provider/admin: the reserved funds leave the wallet. Idempotent. */
export async function confirmWithdrawal(
  ctx: { db: any },
  txDocId: Id<"transactions">,
  providerReference?: string
): Promise<{ changed: boolean }> {
  const tx = await ctx.db.get(txDocId);
  if (!tx || tx.type !== "withdrawal") throw new Error("Withdrawal transaction not found.");
  if (tx.status === "completed") return { changed: false };
  if (tx.status !== "pending") throw new Error(`Cannot complete a withdrawal in status '${tx.status}'.`);

  const wallet = await ctx.db.get(tx.walletId);
  const now = Date.now();
  await ctx.db.patch(wallet._id, {
    pendingBalance: Math.max(0, round2(wallet.pendingBalance - tx.amount)),
    updatedAt: now,
  });
  await ctx.db.patch(tx._id, {
    status: "completed",
    gatewayReference: providerReference ?? tx.gatewayReference,
    updatedAt: now,
  });
  await postDoubleEntry(ctx, `WDR-${tx.transactionId}`, "Confirmed withdrawal payout", [
    { accountType: "CLIENT_AVAILABLE", userId: tx.userId, direction: "DEBIT", amount: tx.amount },
    { accountType: "TELCO_CLEARING_LIABILITY", direction: "CREDIT", amount: tx.amount },
  ], tx.currency);
  return { changed: true };
}

/** Payout failed/cancelled: the reservation is released back to available. Idempotent. */
export async function releaseWithdrawal(
  ctx: { db: any },
  txDocId: Id<"transactions">,
  reason: string
): Promise<{ changed: boolean }> {
  const tx = await ctx.db.get(txDocId);
  if (!tx || tx.type !== "withdrawal") throw new Error("Withdrawal transaction not found.");
  if (tx.status === "failed") return { changed: false };
  if (tx.status !== "pending") throw new Error(`Cannot fail a withdrawal in status '${tx.status}'.`);

  const wallet = await ctx.db.get(tx.walletId);
  const now = Date.now();
  await ctx.db.patch(wallet._id, {
    availableBalance: round2(wallet.availableBalance + tx.amount),
    pendingBalance: Math.max(0, round2(wallet.pendingBalance - tx.amount)),
    updatedAt: now,
  });
  await ctx.db.patch(tx._id, { status: "failed", failureReason: reason, updatedAt: now });
  return { changed: true };
}

// ─── Escrow: hold -> (release | refund) ──────────────────────────────

/** Moves `amount` from the user's AVAILABLE funds into ESCROW protection. */
export async function holdFunds(
  ctx: { db: any },
  p: {
    userId: Id<"users">;
    amount: number;
    currency?: string;
    referenceType: string;
    referenceId: string;
    idempotencyKey: string;
    description?: string;
    counterpartyId?: Id<"users">;
    extra?: EscrowTxExtra;
  }
): Promise<{ duplicate: boolean; availableBalance: number; escrowBalance: number; transactionDocId?: Id<"transactions"> }> {
  const currency = p.currency ?? DEFAULT_CURRENCY;
  const amount = assertValidAmount(p.amount);
  const wallet = await getOrCreateUserWallet(ctx, p.userId, currency);

  const prior = await findByIdempotencyKey(ctx, p.userId, p.idempotencyKey);
  if (prior) {
    return { duplicate: true, availableBalance: wallet.availableBalance, escrowBalance: wallet.escrowBalance ?? 0 };
  }
  if (wallet.availableBalance < amount) {
    throw new Error(
      `INSUFFICIENT_FUNDS: Available balance (${currency} ${wallet.availableBalance.toFixed(2)}) is less than ${currency} ${amount.toFixed(2)}.`
    );
  }
  await assertNotRecoveryProtected(ctx, wallet, amount, currency);

  const now = Date.now();
  const available = round2(wallet.availableBalance - amount);
  const escrow = round2((wallet.escrowBalance ?? 0) + amount);
  await ctx.db.patch(wallet._id, { availableBalance: available, escrowBalance: escrow, updatedAt: now });
  const txDocId = await ctx.db.insert("transactions", {
    transactionId: newTxCode(),
    walletId: wallet._id,
    userId: p.userId,
    counterpartyId: p.counterpartyId,
    type: "escrow_lock",
    amount,
    netAmount: -amount,
    currency,
    referenceType: p.referenceType,
    referenceId: p.referenceId,
    escrowStatus: "locked",
    status: "completed",
    idempotencyKey: p.idempotencyKey,
    description: p.description ?? `Funds held in escrow (${p.referenceType})`,
    ...(p.extra ?? {}),
    createdAt: now,
    updatedAt: now,
  });
  await postDoubleEntry(ctx, `ESC-LOCK-${p.idempotencyKey}`, "Escrow hold", [
    { accountType: "CLIENT_AVAILABLE", userId: p.userId, direction: "DEBIT", amount },
    { accountType: "CLIENT_ESCROW_LOCKED", userId: p.userId, direction: "CREDIT", amount },
  ], currency);
  return { duplicate: false, availableBalance: available, escrowBalance: escrow, transactionDocId: txDocId };
}

/**
 * A VERIFIED external payment (mobile money / bank / card) funds escrow DIRECTLY: the buyer
 * does not need to top up their wallet first. The caller (webhook / verified poll / admin)
 * must already have confirmed the payment with the provider. Idempotent on
 * (provider, providerReference): a replayed webhook never funds escrow twice.
 */
export async function fundEscrowFromExternalPayment(
  ctx: { db: any },
  p: {
    userId: Id<"users">;
    amount: number;
    currency?: string;
    provider: string;
    providerReference: string;
    referenceType: string;
    referenceId: string;
    counterpartyId?: Id<"users">;
    extra?: EscrowTxExtra;
  }
): Promise<{ duplicate: boolean; escrowBalance: number; transactionDocId: Id<"transactions"> }> {
  const currency = p.currency ?? DEFAULT_CURRENCY;
  const amount = assertValidAmount(p.amount);
  if (!p.providerReference) throw new Error("A provider reference is required to fund escrow.");
  const wallet = await getOrCreateUserWallet(ctx, p.userId, currency);

  const existing = await ctx.db
    .query("transactions")
    .withIndex("by_gateway_ref", (q: any) => q.eq("gatewayProvider", p.provider).eq("gatewayReference", p.providerReference))
    .first();
  if (existing) {
    return { duplicate: true, escrowBalance: wallet.escrowBalance ?? 0, transactionDocId: existing._id };
  }

  const now = Date.now();
  const escrow = round2((wallet.escrowBalance ?? 0) + amount);
  await ctx.db.patch(wallet._id, { escrowBalance: escrow, updatedAt: now });
  const txDocId = await ctx.db.insert("transactions", {
    transactionId: newTxCode(),
    walletId: wallet._id,
    userId: p.userId,
    counterpartyId: p.counterpartyId,
    type: "escrow_lock",
    amount,
    netAmount: amount,
    currency,
    referenceType: p.referenceType,
    referenceId: p.referenceId,
    gatewayProvider: p.provider,
    gatewayReference: p.providerReference,
    escrowStatus: "locked",
    status: "completed",
    description: `Direct ${p.provider} payment held in escrow (${p.referenceType})`,
    ...(p.extra ?? {}),
    createdAt: now,
    updatedAt: now,
  });
  await postDoubleEntry(ctx, `ESC-EXT-${p.provider}-${p.providerReference}`, "External payment funds escrow", [
    { accountType: "TELCO_CLEARING_LIABILITY", direction: "DEBIT", amount },
    { accountType: "CLIENT_ESCROW_LOCKED", userId: p.userId, direction: "CREDIT", amount },
  ], currency);
  return { duplicate: false, escrowBalance: escrow, transactionDocId: txDocId };
}

/** Releases escrowed funds from the buyer to the recipient (net of any platform fee). */
export async function releaseHeldFunds(
  ctx: { db: any },
  p: {
    buyerId: Id<"users">;
    recipientId: Id<"users">;
    amount: number;
    platformFee?: number;
    currency?: string;
    referenceType: string;
    referenceId: string;
    idempotencyKey: string;
  }
): Promise<{ duplicate: boolean; recipientAvailable: number; buyerEscrow: number }> {
  const currency = p.currency ?? DEFAULT_CURRENCY;
  const amount = assertValidAmount(p.amount);
  const fee = round2(p.platformFee ?? 0);
  if (fee < 0 || fee > amount) throw new Error("INVALID_AMOUNT: Invalid platform fee.");

  const buyerWallet = await getOrCreateUserWallet(ctx, p.buyerId, currency);
  const recipientWallet = await getOrCreateUserWallet(ctx, p.recipientId, currency);

  const prior = await findByIdempotencyKey(ctx, p.buyerId, p.idempotencyKey);
  if (prior) {
    return { duplicate: true, recipientAvailable: recipientWallet.availableBalance, buyerEscrow: buyerWallet.escrowBalance ?? 0 };
  }
  if ((buyerWallet.escrowBalance ?? 0) < amount) {
    throw new Error("ESCROW_INSUFFICIENT: Not enough escrowed funds to release this amount.");
  }

  const now = Date.now();
  const net = round2(amount - fee);
  const buyerEscrow = round2((buyerWallet.escrowBalance ?? 0) - amount);
  const recipientAvailable = round2(recipientWallet.availableBalance + net);
  await ctx.db.patch(buyerWallet._id, { escrowBalance: buyerEscrow, updatedAt: now });
  await ctx.db.patch(recipientWallet._id, { availableBalance: recipientAvailable, updatedAt: now });

  const code = newTxCode();
  await ctx.db.insert("transactions", {
    transactionId: code,
    walletId: buyerWallet._id,
    userId: p.buyerId,
    counterpartyId: p.recipientId,
    type: "escrow_release",
    amount,
    netAmount: -amount,
    feeAmount: fee,
    platformFeeAmount: fee,
    currency,
    referenceType: p.referenceType,
    referenceId: p.referenceId,
    escrowStatus: "released",
    status: "completed",
    idempotencyKey: p.idempotencyKey,
    description: `Escrow released (${p.referenceType})`,
    createdAt: now,
    updatedAt: now,
  });
  await ctx.db.insert("transactions", {
    transactionId: code,
    walletId: recipientWallet._id,
    userId: p.recipientId,
    counterpartyId: p.buyerId,
    type: "payout",
    amount,
    netAmount: net,
    feeAmount: fee,
    platformFeeAmount: fee,
    currency,
    referenceType: p.referenceType,
    referenceId: p.referenceId,
    status: "completed",
    description: `Escrow payout received (${p.referenceType})`,
    createdAt: now,
    updatedAt: now,
  });
  await postDoubleEntry(ctx, `ESC-REL-${p.idempotencyKey}`, "Escrow release", [
    { accountType: "CLIENT_ESCROW_LOCKED", userId: p.buyerId, direction: "DEBIT", amount },
    { accountType: "OWNER_AVAILABLE", userId: p.recipientId, direction: "CREDIT", amount: net },
    ...(fee > 0
      ? [{ accountType: "PLATFORM_REVENUE_REALIZED" as const, direction: "CREDIT" as const, amount: fee }]
      : []),
  ], currency);
  return { duplicate: false, recipientAvailable, buyerEscrow };
}

/** Refunds escrowed funds back to the buyer's AVAILABLE balance. */
export async function refundHeldFunds(
  ctx: { db: any },
  p: {
    userId: Id<"users">;
    amount: number;
    currency?: string;
    referenceType: string;
    referenceId: string;
    idempotencyKey: string;
  }
): Promise<{ duplicate: boolean; availableBalance: number; escrowBalance: number }> {
  const currency = p.currency ?? DEFAULT_CURRENCY;
  const amount = assertValidAmount(p.amount);
  const wallet = await getOrCreateUserWallet(ctx, p.userId, currency);

  const prior = await findByIdempotencyKey(ctx, p.userId, p.idempotencyKey);
  if (prior) {
    return { duplicate: true, availableBalance: wallet.availableBalance, escrowBalance: wallet.escrowBalance ?? 0 };
  }
  if ((wallet.escrowBalance ?? 0) < amount) {
    throw new Error("ESCROW_INSUFFICIENT: Not enough escrowed funds to refund this amount.");
  }

  const now = Date.now();
  const escrow = round2((wallet.escrowBalance ?? 0) - amount);
  const available = round2(wallet.availableBalance + amount);
  await ctx.db.patch(wallet._id, { availableBalance: available, escrowBalance: escrow, updatedAt: now });
  await ctx.db.insert("transactions", {
    transactionId: newTxCode(),
    walletId: wallet._id,
    userId: p.userId,
    type: "refund",
    amount,
    netAmount: amount,
    currency,
    referenceType: p.referenceType,
    referenceId: p.referenceId,
    escrowStatus: "refunded",
    status: "completed",
    idempotencyKey: p.idempotencyKey,
    description: `Escrow refunded (${p.referenceType})`,
    createdAt: now,
    updatedAt: now,
  });
  await postDoubleEntry(ctx, `ESC-REF-${p.idempotencyKey}`, "Escrow refund", [
    { accountType: "CLIENT_ESCROW_LOCKED", userId: p.userId, direction: "DEBIT", amount },
    { accountType: "CLIENT_AVAILABLE", userId: p.userId, direction: "CREDIT", amount },
  ], currency);
  return { duplicate: false, availableBalance: available, escrowBalance: escrow };
}

// ─── Reversals: refunds AFTER a payout ──────────────────────────────
//
// A settled escrow release is never edited or deleted. A refund after payout is a NEW reversal:
//   • the platform's fee from that release is reversed out of platform revenue;
//   • the recipient's net payout is taken back from their AVAILABLE balance — never more than they
//     have (no negative balances);
//   • the buyer is credited exactly what was really recovered (no fake refund);
//   • any shortfall stays OPEN as a recovery case ("pending_recovery") for an admin, who can retry
//     later, have the platform cover it, or write it off — each step its own transaction, its own
//     ledger transaction and its own event.

export type ReversalStatus = "completed" | "pending_recovery" | "recovered" | "platform_covered" | "written_off";

async function postReversalMovement(
  ctx: { db: any },
  rev: Doc<"payment_reversals">,
  step: string,
  p: { fromRecipient: number; fromPlatform: number; description: string }
): Promise<{ transactionCode: string; ledgerCode: string } | null> {
  const fromRecipient = round2(p.fromRecipient);
  const fromPlatform = round2(p.fromPlatform);
  const credit = round2(fromRecipient + fromPlatform);
  if (!(credit > 0)) return null;
  const now = Date.now();
  const buyerWallet = await getOrCreateUserWallet(ctx, rev.buyerId, rev.currency);
  const recipientWallet = await getOrCreateUserWallet(ctx, rev.recipientId, rev.currency);
  if (fromRecipient > 0) {
    if (recipientWallet.availableBalance + 0.0001 < fromRecipient) throw new Error("RECOVERY_INSUFFICIENT: The recipient's available balance is too low.");
    await ctx.db.patch(recipientWallet._id, { availableBalance: round2(recipientWallet.availableBalance - fromRecipient), updatedAt: now });
  }
  const buyerAfter = await ctx.db.get(buyerWallet._id);
  await ctx.db.patch(buyerWallet._id, { availableBalance: round2(buyerAfter.availableBalance + credit), updatedAt: now });

  const code = newTxCode();
  const key = `rev:${rev._id}:${step}`;
  await ctx.db.insert("transactions", {
    transactionId: code,
    walletId: buyerWallet._id,
    userId: rev.buyerId,
    counterpartyId: rev.recipientId,
    type: "refund",
    amount: credit,
    netAmount: credit,
    currency: rev.currency,
    referenceType: "payment_reversal",
    referenceId: rev._id as string,
    status: "completed",
    idempotencyKey: key,
    description: p.description,
    createdAt: now,
    updatedAt: now,
  });
  if (fromRecipient > 0) {
    await ctx.db.insert("transactions", {
      transactionId: code,
      walletId: recipientWallet._id,
      userId: rev.recipientId,
      counterpartyId: rev.buyerId,
      type: "refund",
      amount: fromRecipient,
      netAmount: -fromRecipient,
      currency: rev.currency,
      referenceType: "payment_reversal",
      referenceId: rev._id as string,
      status: "completed",
      idempotencyKey: key,
      description: `Payout returned for a refund (${rev.referenceType})`,
      createdAt: now,
      updatedAt: now,
    });
  }
  const ledgerCode = `REV-${rev._id}-${step}`;
  await postDoubleEntry(ctx, ledgerCode, p.description, [
    ...(fromRecipient > 0 ? [{ accountType: "OWNER_AVAILABLE" as const, userId: rev.recipientId, direction: "DEBIT" as const, amount: fromRecipient }] : []),
    ...(fromPlatform > 0 ? [{ accountType: "PLATFORM_REVENUE_REALIZED" as const, direction: "DEBIT" as const, amount: fromPlatform }] : []),
    { accountType: "CLIENT_AVAILABLE", userId: rev.buyerId, direction: "CREDIT", amount: credit },
  ], rev.currency);
  return { transactionCode: code, ledgerCode };
}

async function reversalEvent(
  ctx: { db: any },
  reversalId: Id<"payment_reversals">,
  action: "REVERSED" | "RECOVERED" | "PLATFORM_COVERED" | "WRITTEN_OFF",
  actorId: Id<"users">,
  amount: number,
  refs: { transactionCode: string; ledgerCode: string } | null,
  note?: string
) {
  await ctx.db.insert("payment_reversal_events", {
    reversalId,
    action,
    amount: round2(amount),
    transactionCode: refs?.transactionCode,
    ledgerCode: refs?.ledgerCode,
    actorId,
    note: note ? note.slice(0, 500) : undefined,
    at: Date.now(),
  });
}

/**
 * Reverses ONE completed escrow release (the buyer-side "escrow_release" row). One reversal per
 * release; a repeat returns the existing reversal and moves nothing.
 */
export async function reverseSettledRelease(
  ctx: { db: any },
  p: { releaseTransactionId: Id<"transactions">; reason: string; actorId: Id<"users"> }
): Promise<{ duplicate: boolean; reversalId: Id<"payment_reversals">; refundedToBuyer: number; outstanding: number; status: ReversalStatus }> {
  const rel: Doc<"transactions"> | null = await ctx.db.get(p.releaseTransactionId);
  if (!rel || rel.type !== "escrow_release" || rel.status !== "completed" || !rel.counterpartyId) {
    throw new Error("Only a completed escrow release can be reversed.");
  }
  const existing = await ctx.db
    .query("payment_reversals")
    .withIndex("by_release", (q: any) => q.eq("releaseTransactionId", rel._id))
    .first();
  if (existing) {
    return { duplicate: true, reversalId: existing._id, refundedToBuyer: existing.refundedToBuyer, outstanding: existing.outstandingAmount, status: existing.status };
  }
  const amount = round2(rel.amount);
  const fee = round2(rel.platformFeeAmount ?? rel.feeAmount ?? 0);
  if (!(amount > 0) || fee < 0 || fee > amount) throw new Error("This release has an invalid amount.");
  const net = round2(amount - fee);
  const recipientWallet = await getOrCreateUserWallet(ctx, rel.counterpartyId, rel.currency);
  const recovered = round2(Math.min(net, Math.max(0, recipientWallet.availableBalance)));
  const outstanding = round2(net - recovered);
  const status: ReversalStatus = outstanding > 0 ? "pending_recovery" : "completed";
  const now = Date.now();
  const reversalId = await ctx.db.insert("payment_reversals", {
    releaseTransactionId: rel._id,
    buyerId: rel.userId,
    recipientId: rel.counterpartyId,
    currency: rel.currency,
    referenceType: rel.referenceType ?? "escrow",
    referenceId: rel.referenceId ?? (rel._id as string),
    originalAmount: amount,
    platformFeeReversed: fee,
    recipientNetOwed: net,
    recoveredFromRecipient: recovered,
    platformCoveredAmount: 0,
    writtenOffAmount: 0,
    refundedToBuyer: round2(fee + recovered),
    outstandingAmount: outstanding,
    status,
    withdrawalProtection: outstanding > 0 ? "active" : undefined,
    reason: p.reason.slice(0, 500),
    createdBy: p.actorId,
    createdAt: now,
    updatedAt: now,
  });
  const rev = (await ctx.db.get(reversalId))!;
  const refs = await postReversalMovement(ctx, rev, "1", {
    fromRecipient: recovered,
    fromPlatform: fee,
    description: `Refund after payout (${rev.referenceType})`,
  });
  await reversalEvent(ctx, reversalId, "REVERSED", p.actorId, fee + recovered, refs, p.reason);
  return { duplicate: false, reversalId, refundedToBuyer: round2(fee + recovered), outstanding, status };
}

/** Recovery case: take what the recipient now has available (up to the outstanding amount). */
export async function retryReversalRecovery(
  ctx: { db: any },
  p: { reversalId: Id<"payment_reversals">; actorId: Id<"users">; note?: string }
): Promise<{ recovered: number; outstanding: number; status: ReversalStatus }> {
  const rev: Doc<"payment_reversals"> | null = await ctx.db.get(p.reversalId);
  if (!rev) throw new Error("Reversal not found.");
  if (rev.status !== "pending_recovery") throw new Error(`This reversal is ${rev.status}; nothing to recover.`);
  const w = await getOrCreateUserWallet(ctx, rev.recipientId, rev.currency);
  const take = round2(Math.min(rev.outstandingAmount, Math.max(0, w.availableBalance)));
  if (!(take > 0)) return { recovered: 0, outstanding: rev.outstandingAmount, status: rev.status };
  const step = `r${Date.now()}`;
  const refs = await postReversalMovement(ctx, rev, step, { fromRecipient: take, fromPlatform: 0, description: `Refund recovery (${rev.referenceType})` });
  const outstanding = round2(rev.outstandingAmount - take);
  const status: ReversalStatus = outstanding > 0 ? "pending_recovery" : "recovered";
  await ctx.db.patch(rev._id, {
    recoveredFromRecipient: round2(rev.recoveredFromRecipient + take),
    refundedToBuyer: round2(rev.refundedToBuyer + take),
    outstandingAmount: outstanding,
    status,
    updatedAt: Date.now(),
  });
  await reversalEvent(ctx, rev._id, "RECOVERED", p.actorId, take, refs, p.note);
  return { recovered: take, outstanding, status };
}

/**
 * Closes an open recovery case: "platform_covered" credits the buyer the outstanding amount from
 * platform revenue; "written_off" closes it WITHOUT crediting the buyer further. Both are recorded.
 */
export async function closeReversalRecovery(
  ctx: { db: any },
  p: { reversalId: Id<"payment_reversals">; resolution: "platform_covered" | "written_off"; actorId: Id<"users">; note: string }
): Promise<{ status: ReversalStatus; amount: number }> {
  const rev: Doc<"payment_reversals"> | null = await ctx.db.get(p.reversalId);
  if (!rev) throw new Error("Reversal not found.");
  if (rev.status !== "pending_recovery") throw new Error(`This reversal is ${rev.status}; it is not open.`);
  const amount = rev.outstandingAmount;
  const now = Date.now();
  if (p.resolution === "platform_covered") {
    const refs = await postReversalMovement(ctx, rev, "cover", { fromRecipient: 0, fromPlatform: amount, description: `Refund covered by the platform (${rev.referenceType})` });
    await ctx.db.patch(rev._id, {
      platformCoveredAmount: amount,
      refundedToBuyer: round2(rev.refundedToBuyer + amount),
      outstandingAmount: 0,
      status: "platform_covered",
      closedBy: p.actorId,
      closedAt: now,
      closeNote: p.note.slice(0, 500),
      updatedAt: now,
    });
    await reversalEvent(ctx, rev._id, "PLATFORM_COVERED", p.actorId, amount, refs, p.note);
    return { status: "platform_covered", amount };
  }
  await ctx.db.patch(rev._id, {
    writtenOffAmount: amount,
    outstandingAmount: 0,
    status: "written_off",
    closedBy: p.actorId,
    closedAt: now,
    closeNote: p.note.slice(0, 500),
    updatedAt: now,
  });
  await reversalEvent(ctx, rev._id, "WRITTEN_OFF", p.actorId, amount, null, p.note);
  return { status: "written_off", amount };
}

// ─── Platform charges (subscriptions) ───────────────────────────────

/**
 * Charges the user's AVAILABLE balance for a platform service (e.g. a professional subscription).
 * The money is booked as SUBSCRIPTION_REVENUE on the ledger — platform revenue, clearly separate
 * from user funds and escrow. Idempotent per (user, idempotencyKey).
 */
export async function chargeSubscription(
  ctx: { db: any },
  p: { userId: Id<"users">; amount: number; currency?: string; idempotencyKey: string; description: string; tierCode: string }
): Promise<{ duplicate: boolean; transactionCode: string; availableBalance: number }> {
  const currency = p.currency ?? DEFAULT_CURRENCY;
  const amount = assertValidAmount(p.amount);
  const prior = await findByIdempotencyKey(ctx, p.userId, p.idempotencyKey);
  const wallet = await getOrCreateUserWallet(ctx, p.userId, currency);
  if (prior) {
    return { duplicate: true, transactionCode: prior.transactionId ?? (prior._id as string), availableBalance: wallet.availableBalance };
  }
  if (wallet.availableBalance < amount) {
    throw new Error(
      `INSUFFICIENT_FUNDS: Available balance (${currency} ${wallet.availableBalance.toFixed(2)}) is less than ${currency} ${amount.toFixed(2)}.`
    );
  }
  await assertNotRecoveryProtected(ctx, wallet, amount, currency);
  const now = Date.now();
  const code = newTxCode();
  const available = round2(wallet.availableBalance - amount);
  await ctx.db.patch(wallet._id, { availableBalance: available, updatedAt: now });
  await ctx.db.insert("transactions", {
    transactionId: code,
    walletId: wallet._id,
    userId: p.userId,
    type: "payment",
    amount,
    netAmount: -amount,
    currency,
    referenceType: "subscription",
    referenceId: p.tierCode,
    gatewayProvider: "INTERNAL_WALLET",
    gatewayReference: code,
    status: "completed",
    idempotencyKey: p.idempotencyKey,
    description: p.description,
    createdAt: now,
    updatedAt: now,
  });
  await postDoubleEntry(ctx, code, p.description, [
    { accountType: "CLIENT_AVAILABLE", userId: p.userId, direction: "DEBIT", amount },
    { accountType: "SUBSCRIPTION_REVENUE", direction: "CREDIT", amount },
  ], currency);
  return { duplicate: false, transactionCode: code, availableBalance: available };
}

// ─── User-facing history for the escrow modules' double-entry postings ─

/**
 * The vehicle / real-estate escrow modules move money with their own double-entry postings.
 * This turns each posting's per-user entries into rows in the user's transaction HISTORY
 * (funding, release, payout, refund) so every user sees the real movements of their money.
 * It records history only; balances are changed by the calling module.
 */
export async function recordHistoryFromLedgerEntries(
  ctx: { db: any },
  p: {
    code: string;
    description: string;
    currency?: string;
    entries: Array<{ accountType: string; userId?: Id<"users">; direction: "DEBIT" | "CREDIT"; amount: number }>;
  }
): Promise<void> {
  const currency = p.currency ?? DEFAULT_CURRENCY;
  const now = Date.now();
  for (const e of p.entries) {
    if (!e.userId || !(e.amount > 0)) continue;

    let type: "escrow_lock" | "escrow_release" | "payout" | "refund" | null = null;
    let net = e.amount;
    if (e.accountType === "CLIENT_ESCROW_LOCKED" && e.direction === "CREDIT") {
      type = "escrow_lock";
      // Wallet-funded (available -> escrow) leaves the spendable balance; externally-funded does not.
      const fromWallet = p.entries.some(
        (x) => x.userId === e.userId && x.accountType === "CLIENT_AVAILABLE" && x.direction === "DEBIT"
      );
      net = fromWallet ? -e.amount : e.amount;
    } else if (e.accountType === "CLIENT_ESCROW_LOCKED" && e.direction === "DEBIT") {
      type = "escrow_release";
      net = -e.amount;
    } else if (e.accountType === "OWNER_AVAILABLE" && e.direction === "CREDIT") {
      type = "payout";
    } else if (e.accountType === "CLIENT_AVAILABLE" && e.direction === "CREDIT") {
      type = "refund";
    }
    if (!type) continue;

    const wallet = await getOrCreateUserWallet(ctx, e.userId, currency);
    await ctx.db.insert("transactions", {
      transactionId: `${p.code}:${type}:${e.userId}`,
      walletId: wallet._id,
      userId: e.userId,
      type,
      amount: e.amount,
      netAmount: net,
      currency,
      referenceType: "escrow_deal",
      referenceId: p.code,
      escrowStatus: type === "escrow_lock" ? "locked" : type === "escrow_release" ? "released" : type === "refund" ? "refunded" : undefined,
      status: "completed",
      description: p.description,
      createdAt: now,
      updatedAt: now,
    });
  }
}

// ─── Internal entry points (webhooks / reconciliation / tests). NOT client-callable. ──

export const creditVerifiedDeposit = internalMutation({
  args: {
    userId: v.id("users"),
    amount: v.number(),
    netAmount: v.optional(v.number()),
    feeAmount: v.optional(v.number()),
    currency: v.optional(v.string()),
    provider: v.string(),
    providerReference: v.string(),
    description: v.optional(v.string()),
  },
  handler: async (ctx, args) => settleVerifiedDeposit(ctx, args),
});

export const markDepositFailed = internalMutation({
  args: {
    userId: v.id("users"),
    provider: v.string(),
    providerReference: v.string(),
    reason: v.string(),
  },
  handler: async (ctx, args) => failPendingDeposit(ctx, args),
});

export const holdFundsInEscrow = internalMutation({
  args: {
    userId: v.id("users"),
    amount: v.number(),
    currency: v.optional(v.string()),
    referenceType: v.string(),
    referenceId: v.string(),
    idempotencyKey: v.string(),
  },
  handler: async (ctx, args) => holdFunds(ctx, args),
});

export const releaseEscrowToRecipient = internalMutation({
  args: {
    buyerId: v.id("users"),
    recipientId: v.id("users"),
    amount: v.number(),
    platformFee: v.optional(v.number()),
    currency: v.optional(v.string()),
    referenceType: v.string(),
    referenceId: v.string(),
    idempotencyKey: v.string(),
  },
  handler: async (ctx, args) => releaseHeldFunds(ctx, args),
});

export const refundEscrowToBuyer = internalMutation({
  args: {
    userId: v.id("users"),
    amount: v.number(),
    currency: v.optional(v.string()),
    referenceType: v.string(),
    referenceId: v.string(),
    idempotencyKey: v.string(),
  },
  handler: async (ctx, args) => refundHeldFunds(ctx, args),
});

// ─── Earnings (sum of REAL completed payouts credited to the caller) ─

export const getEarningsSummary = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const rows = await ctx.db
      .query("transactions")
      .withIndex("by_user_type", (q: any) => q.eq("userId", userId).eq("type", "payout"))
      .order("desc")
      .take(500);
    let total = 0;
    let count = 0;
    for (const r of rows) {
      if (r.status !== "completed") continue;
      // Legacy withdrawals were also stored as "payout" rows (with the destination in agentNumber):
      // those are money OUT, not earnings.
      if (r.agentNumber) continue;
      const credit = r.netAmount ?? r.amount;
      if (credit > 0) {
        total += credit;
        count += 1;
      }
    }
    return { totalEarned: round2(total), currency: DEFAULT_CURRENCY, count, truncated: rows.length === 500 };
  },
});

// ─── Transaction history (the authenticated user's own records only) ─

export const getUserTransactions = query({
  args: {
    userId: v.optional(v.string()),
    limit: v.optional(v.number()),
    sessionToken: v.optional(v.string()),
    typeFilter: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    transactions: v.array(
      v.object({
        id: v.string(),
        transactionId: v.string(),
        type: v.string(),
        amount: v.number(),
        currency: v.string(),
        status: v.string(),
        description: v.optional(v.string()),
        counterpartyName: v.optional(v.string()),
        counterpartyPhone: v.optional(v.string()),
        feeAmount: v.optional(v.number()),
        netAmount: v.optional(v.number()),
        gatewayProvider: v.optional(v.string()),
        gatewayReference: v.optional(v.string()),
        referenceType: v.optional(v.string()),
        failureReason: v.optional(v.string()),
        createdAt: v.number(),
      })
    ),
  }),
  handler: async (ctx, args) => {
    // Identity is derived from the session only; a claimed userId must match it.
    const { userId: targetUserId } = await requireSelf(ctx, args.sessionToken, args.userId);
    const limit = Math.min(Math.max(args.limit ?? 50, 1), 100);

    const records =
      args.typeFilter && args.typeFilter !== "all"
        ? await ctx.db
            .query("transactions")
            .withIndex("by_user_type", (q: any) =>
              q.eq("userId", targetUserId).eq("type", args.typeFilter as any)
            )
            .order("desc")
            .take(limit)
        : await ctx.db
            .query("transactions")
            .withIndex("by_user", (q: any) => q.eq("userId", targetUserId))
            .order("desc")
            .take(limit);

    return {
      success: true,
      transactions: records.map((r: any) => ({
        id: r._id as string,
        transactionId: r.transactionId ?? (r._id as string),
        type: r.type,
        amount: r.amount,
        currency: r.currency,
        status: r.status,
        description: r.description,
        counterpartyName: r.counterpartyName,
        counterpartyPhone: r.counterpartyPhone,
        feeAmount: r.feeAmount,
        netAmount: r.netAmount,
        gatewayProvider: r.gatewayProvider,
        gatewayReference: r.gatewayReference,
        referenceType: r.referenceType,
        failureReason: r.failureReason,
        createdAt: r.createdAt ?? r._creationTime,
      })),
    };
  },
});
