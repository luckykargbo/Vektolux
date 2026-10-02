// convex/withdrawals.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Withdrawals (Mobile Money + Bank)
//
// State machine (funds are RESERVED first, and only leave the wallet when the
// payout is CONFIRMED):
//
//   request ──> reserve (available→pending) ──┬─> completed   (confirmed payout)
//                                              ├─> processing  (provider accepted, not yet confirmed)
//                                              ├─> pending     (bank: awaiting admin processing)
//                                              └─> failed / cancelled (reservation released)
//
// • Only AVAILABLE funds can be withdrawn; escrow-protected and already-reserved
//   funds are excluded by construction (see walletCore.reserveWithdrawalFunds).
// • Idempotent: the same idempotencyKey can never create two withdrawals.
// • The client is never told "completed" unless the server state says so.
//
// PROVIDER INTEGRATION POINT: `dispatchMobileMoneyPayout` (Monime /payouts). The
// status strings interpreted there and the confirmation path
// (`applyProviderPayoutResult`, to be called from the provider's payout webhook)
// must be verified against the provider's current API documentation.
// ═══════════════════════════════════════════════════════════════════════

import { action, internalAction, internalMutation, internalQuery, mutation, query } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { requireAdminSession, requireSelf } from "./lib/auth";
import { verifyAndTrackPin } from "./lib/pin";
import { detectSierraLeoneCarrier } from "./lib/paymentErrors";
import { assertValidAmount, confirmWithdrawal, releaseWithdrawal, reserveWithdrawalFunds, DEFAULT_CURRENCY } from "./walletCore";

const MAX_OPEN_WITHDRAWALS = 5;

function getMoniMeConfig() {
  return {
    spaceId: (process.env.MONIME_SPACE_ID || "").trim(),
    accessToken: (process.env.MONIME_ACCESS_TOKEN || process.env.MONIME_API_KEY || "").trim(),
    apiBaseUrl: (process.env.MONIME_API_BASE_URL || "https://api.monime.io/v1").trim(),
  };
}

function maskAccount(acct: string): string {
  const d = acct.replace(/\s/g, "");
  return d.length <= 4 ? "••••" : `••••${d.slice(-3)}`;
}

function normalizeSlPhone(raw: string): string {
  let d = raw.replace(/\D/g, "");
  if (d.startsWith("0")) d = "232" + d.substring(1);
  else if (!d.startsWith("232") && d.length === 8) d = "232" + d;
  return "+" + d;
}

// ─── Step 1: authenticate, authorize (PIN), validate, RESERVE ────────

export const reserve = internalMutation({
  args: {
    sessionToken: v.optional(v.string()),
    userId: v.optional(v.string()),
    amount: v.number(),
    method: v.union(v.literal("mobile_money"), v.literal("bank")),
    providerCode: v.string(),
    destinationAccount: v.string(),
    destinationName: v.optional(v.string()),
    bankName: v.optional(v.string()),
    pin: v.string(),
    idempotencyKey: v.string(),
    currency: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId, user } = await requireSelf(ctx, args.sessionToken, args.userId);
    const currency = args.currency ?? DEFAULT_CURRENCY;
    const key = args.idempotencyKey.trim();
    if (key.length < 16 || key.length > 100) throw new Error("A valid idempotency key is required.");

    // Replay: return the existing request untouched.
    const existing = await ctx.db
      .query("withdrawal_requests")
      .withIndex("by_user_idempotency", (q) => q.eq("userId", userId).eq("idempotencyKey", key))
      .first();
    if (existing) {
      return { ok: true as const, duplicate: true, requestId: existing._id, status: existing.status, method: existing.method };
    }

    const amount = assertValidAmount(args.amount);

    // Destination validation (server-side; never trust the client's shape)
    let destination = args.destinationAccount.trim();
    let providerCode = args.providerCode.trim().toLowerCase();
    if (args.method === "mobile_money") {
      const phone = normalizeSlPhone(destination);
      if (!/^\+232\d{8}$/.test(phone)) throw new Error("INVALID_DESTINATION: Enter a valid Sierra Leone mobile number.");
      destination = phone;
      const carrier = detectSierraLeoneCarrier(phone);
      providerCode = carrier === "africell" || providerCode.includes("africell") || providerCode.includes("afrimoney") ? "africell" : "orange";
    } else {
      if (!/^\d{6,30}$/.test(destination.replace(/[\s-]/g, ""))) throw new Error("INVALID_DESTINATION: Enter a valid bank account number.");
      destination = destination.replace(/[\s-]/g, "");
      if (!args.bankName?.trim()) throw new Error("INVALID_DESTINATION: Bank name is required.");
      if (!args.destinationName || args.destinationName.trim().length < 2) throw new Error("INVALID_DESTINATION: Account holder name is required.");
    }

    // Bound the number of concurrent open withdrawals.
    const open = await ctx.db
      .query("withdrawal_requests")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .take(25);
    if (open.filter((r) => r.status === "pending" || r.status === "processing").length >= MAX_OPEN_WITHDRAWALS) {
      throw new Error("TOO_MANY_PENDING: Please wait for your pending withdrawals to complete.");
    }

    // PIN authorization. A failure is RETURNED so the lockout counter commits.
    const pinCheck = await verifyAndTrackPin(ctx, user, args.pin);
    if (!pinCheck.ok) return { ok: false as const, errorCode: pinCheck.code, message: pinCheck.message };

    const reservation = await reserveWithdrawalFunds(ctx, {
      userId,
      amount,
      currency,
      provider: providerCode,
      destination,
      idempotencyKey: key,
    });

    const now = Date.now();
    const requestId = await ctx.db.insert("withdrawal_requests", {
      userId,
      walletId: reservation.walletId,
      transactionDocId: reservation.transactionDocId,
      amount,
      currency,
      method: args.method,
      providerCode: args.method === "bank" ? (args.bankName ?? providerCode).trim() : providerCode,
      destinationAccount: destination,
      destinationName: args.destinationName?.trim(),
      bankName: args.bankName?.trim(),
      status: "pending",
      idempotencyKey: key,
      createdAt: now,
      updatedAt: now,
    });
    return { ok: true as const, duplicate: false, requestId, status: "pending" as const, method: args.method };
  },
});

// ─── Outcome application (shared by dispatch, webhook, and admin) ────

async function applyOutcome(
  ctx: { db: any },
  req: Doc<"withdrawal_requests">,
  outcome: "completed" | "failed" | "processing" | "cancelled",
  opts: { providerReference?: string; reason?: string; adminId?: Id<"users"> }
) {
  // Terminal states are final and idempotent.
  if (req.status === "completed" || req.status === "failed" || req.status === "cancelled") {
    return { status: req.status, changed: false };
  }
  const now = Date.now();
  if (outcome === "processing") {
    await ctx.db.patch(req._id, { status: "processing", providerReference: opts.providerReference ?? req.providerReference, updatedAt: now });
    return { status: "processing" as const, changed: true };
  }
  if (outcome === "completed") {
    await confirmWithdrawal(ctx, req.transactionDocId, opts.providerReference);
    await ctx.db.patch(req._id, {
      status: "completed",
      providerReference: opts.providerReference ?? req.providerReference,
      resolvedByAdminId: opts.adminId,
      completedAt: now,
      updatedAt: now,
    });
    return { status: "completed" as const, changed: true };
  }
  // failed | cancelled → release the reservation
  await releaseWithdrawal(ctx, req.transactionDocId, opts.reason ?? "Withdrawal failed");
  await ctx.db.patch(req._id, {
    status: outcome,
    failureReason: opts.reason,
    resolvedByAdminId: opts.adminId,
    updatedAt: now,
  });
  return { status: outcome, changed: true };
}

export const recordOutcome = internalMutation({
  args: {
    requestId: v.id("withdrawal_requests"),
    outcome: v.union(v.literal("completed"), v.literal("failed"), v.literal("processing")),
    providerReference: v.optional(v.string()),
    reason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const req = await ctx.db.get(args.requestId);
    if (!req) throw new Error("Withdrawal request not found.");
    return applyOutcome(ctx, req, args.outcome, { providerReference: args.providerReference, reason: args.reason });
  },
});

/**
 * Provider payout webhook / verified status poll entry point. Looks the request up by the
 * provider's reference and applies the confirmed outcome (idempotent).
 * INTEGRATION POINT: call from the provider's payout webhook handler once its payload
 * format is confirmed against the provider's documentation.
 */
export const applyProviderPayoutResult = internalMutation({
  args: {
    requestId: v.id("withdrawal_requests"),
    outcome: v.union(v.literal("completed"), v.literal("failed")),
    providerReference: v.optional(v.string()),
    reason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const req = await ctx.db.get(args.requestId);
    if (!req) throw new Error("Withdrawal request not found.");
    return applyOutcome(ctx, req, args.outcome, { providerReference: args.providerReference, reason: args.reason });
  },
});

// ─── Step 2 (mobile money): dispatch to the provider, record the TRUE outcome ──

// Monime documents exactly four payout statuses: pending | processing | completed | failed.
// (https://docs.monime.io payout object). Anything else is treated as NOT confirmed.
const OK_STATES = new Set(["completed"]);
const FAILED_STATES = new Set(["failed"]);

export const requestWithdrawal = action({
  args: {
    sessionToken: v.optional(v.string()),
    userId: v.optional(v.string()),
    amount: v.number(),
    method: v.optional(v.union(v.literal("mobile_money"), v.literal("bank"))),
    destinationProviderCode: v.string(),
    destinationAccountNumber: v.string(),
    destinationName: v.optional(v.string()),
    bankName: v.optional(v.string()),
    pin: v.string(),
    currency: v.optional(v.string()),
    idempotencyKey: v.string(),
  },
  handler: async (ctx, args): Promise<any> => {
    const method = args.method ?? "mobile_money";
    const res: any = await ctx.runMutation(internal.withdrawals.reserve, {
      sessionToken: args.sessionToken,
      userId: args.userId,
      amount: args.amount,
      method,
      providerCode: args.destinationProviderCode,
      destinationAccount: args.destinationAccountNumber,
      destinationName: args.destinationName,
      bankName: args.bankName,
      pin: args.pin,
      idempotencyKey: args.idempotencyKey,
      currency: args.currency,
    });

    if (!res.ok) return { success: false, errorCode: res.errorCode, message: res.message };
    if (res.duplicate) {
      return { success: true, duplicate: true, status: res.status, withdrawalId: res.requestId, message: "This withdrawal was already submitted." };
    }

    // Bank transfers are processed/confirmed by an administrator (manual verification).
    if (method === "bank") {
      return {
        success: true,
        status: "pending",
        withdrawalId: res.requestId,
        message: "Withdrawal request submitted. Funds are reserved and will be sent to your bank account once processed.",
      };
    }

    const dispatch = await dispatchMobileMoneyPayout(ctx, res.requestId);
    return {
      success: true,
      withdrawalId: res.requestId,
      status: dispatch.status,
      message: dispatch.message,
    };
  },
});

async function dispatchMobileMoneyPayout(
  ctx: any,
  requestId: Id<"withdrawal_requests">
): Promise<{ status: "completed" | "processing" | "failed"; message: string }> {
  const req: Doc<"withdrawal_requests"> | null = await ctx.runQuery(internal.withdrawals.getRequestInternal, { requestId });
  if (!req) throw new Error("Withdrawal request not found.");

  const { spaceId, accessToken, apiBaseUrl } = getMoniMeConfig();
  if (!spaceId || !accessToken) {
    // Provider not configured: do not pretend. Release the reservation immediately.
    await ctx.runMutation(internal.withdrawals.recordOutcome, {
      requestId,
      outcome: "failed",
      reason: "Mobile money payouts are not configured yet.",
    });
    return { status: "failed", message: "Mobile money payouts are not available yet. Your funds were not debited." };
  }

  const payload = {
    amount: { currency: req.currency, value: Math.round(req.amount * 100) },
    destination: {
      type: "momo",
      providerId: req.providerCode === "africell" ? "m18" : "m17",
      phoneNumber: req.destinationAccount,
    },
    metadata: { withdrawalId: requestId as string, purpose: "wallet_withdrawal" },
  };

  let httpStatus = 0;
  let body: any = {};
  try {
    const response = await fetch(`${apiBaseUrl}/payouts`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
        "Monime-Space-Id": spaceId,
        "Idempotency-Key": `payout_${requestId}`,
      },
      body: JSON.stringify(payload),
    });
    httpStatus = response.status;
    body = await response.json().catch(() => ({}));
  } catch (err: any) {
    // UNKNOWN outcome (network/timeout): the provider may have accepted it. Never release
    // funds on an ambiguous result — keep reserved and let reconciliation confirm.
    await ctx.runMutation(internal.withdrawals.recordOutcome, { requestId, outcome: "processing" });
    return { status: "processing", message: "Your withdrawal is being processed. We will confirm shortly." };
  }

  const providerRef: string | undefined = body?.result?.id ?? body?.id;
  const state = String(body?.result?.status ?? body?.status ?? "").toLowerCase();

  // Definitive rejection: a 4xx means the provider did not accept the payout.
  if (httpStatus >= 400 && httpStatus < 500) {
    const reason = body?.error?.message ?? body?.messages?.[0]?.message ?? body?.message ?? `Payout rejected (HTTP ${httpStatus}).`;
    await ctx.runMutation(internal.withdrawals.recordOutcome, { requestId, outcome: "failed", reason });
    return { status: "failed", message: `Withdrawal could not be processed: ${reason} Your funds were not debited.` };
  }
  // 5xx / anything else non-2xx: ambiguous → keep reserved.
  if (httpStatus < 200 || httpStatus >= 300) {
    await ctx.runMutation(internal.withdrawals.recordOutcome, { requestId, outcome: "processing", providerReference: providerRef });
    return { status: "processing", message: "Your withdrawal is being processed. We will confirm shortly." };
  }

  if (FAILED_STATES.has(state)) {
    const detail = body?.result?.failureDetail;
    await ctx.runMutation(internal.withdrawals.recordOutcome, {
      requestId,
      outcome: "failed",
      reason: detail?.message ?? detail?.code ?? `Provider status: ${state}`,
    });
    return { status: "failed", message: "The payout was declined by the provider. Your funds were not debited." };
  }
  if (OK_STATES.has(state)) {
    await ctx.runMutation(internal.withdrawals.recordOutcome, { requestId, outcome: "completed", providerReference: providerRef });
    return { status: "completed", message: "Withdrawal completed." };
  }
  // Accepted but not yet confirmed.
  await ctx.runMutation(internal.withdrawals.recordOutcome, { requestId, outcome: "processing", providerReference: providerRef });
  return { status: "processing", message: "Withdrawal submitted and is being processed. We will confirm once the payout completes." };
}

export const getRequestInternal = internalQuery({
  args: { requestId: v.id("withdrawal_requests") },
  handler: async (ctx, args) => ctx.db.get(args.requestId),
});

// ─── The authenticated user's own withdrawals ────────────────────────

export const getMyWithdrawals = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const rows = await ctx.db
      .query("withdrawal_requests")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .take(30);
    return rows.map((r) => ({
      id: r._id as string,
      amount: r.amount,
      currency: r.currency,
      method: r.method,
      provider: r.providerCode,
      destination: maskAccount(r.destinationAccount),
      status: r.status,
      failureReason: r.failureReason ?? null,
      createdAt: r.createdAt,
      completedAt: r.completedAt ?? null,
    }));
  },
});

/** The user may cancel only a bank withdrawal that has not been processed yet. */
export const cancelMyWithdrawal = mutation({
  args: { sessionToken: v.optional(v.string()), withdrawalId: v.id("withdrawal_requests") },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const req = await ctx.db.get(args.withdrawalId);
    if (!req || req.userId !== userId) throw new Error("Withdrawal not found.");
    if (req.status !== "pending" || req.method !== "bank") {
      throw new Error("This withdrawal can no longer be cancelled.");
    }
    return applyOutcome(ctx, req, "cancelled", { reason: "Cancelled by user" });
  },
});

// ─── Admin processing (bank transfers / manual confirmation) ─────────

export const adminListWithdrawals = query({
  args: {
    sessionToken: v.optional(v.string()),
    status: v.optional(
      v.union(v.literal("pending"), v.literal("processing"), v.literal("completed"), v.literal("failed"), v.literal("cancelled"))
    ),
  },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const rows = args.status
      ? await ctx.db.query("withdrawal_requests").withIndex("by_status", (q) => q.eq("status", args.status!)).order("desc").take(100)
      : await ctx.db.query("withdrawal_requests").order("desc").take(100);
    return await Promise.all(
      rows.map(async (r) => {
        const u = await ctx.db.get(r.userId);
        return {
          id: r._id as string,
          userName: u?.name ?? "Unknown",
          amount: r.amount,
          currency: r.currency,
          method: r.method,
          provider: r.providerCode,
          // Full destination is exposed only to an authenticated administrator for processing.
          destinationAccount: r.destinationAccount,
          destinationName: r.destinationName ?? null,
          bankName: r.bankName ?? null,
          status: r.status,
          providerReference: r.providerReference ?? null,
          createdAt: r.createdAt,
        };
      })
    );
  },
});

export const adminResolveWithdrawal = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    withdrawalId: v.id("withdrawal_requests"),
    outcome: v.union(v.literal("completed"), v.literal("failed")),
    providerReference: v.optional(v.string()),
    reason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    const req = await ctx.db.get(args.withdrawalId);
    if (!req) throw new Error("Withdrawal not found.");
    if (args.outcome === "completed" && !args.providerReference?.trim()) {
      throw new Error("A payout/bank reference is required to mark a withdrawal completed.");
    }
    const result = await applyOutcome(ctx, req, args.outcome, {
      providerReference: args.providerReference?.trim(),
      reason: args.reason,
      adminId,
    });
    if (result.changed) {
      await ctx.db.insert("audit_logs", {
        adminUserId: adminId,
        action: args.outcome === "completed" ? "WITHDRAWAL_COMPLETED" : "WITHDRAWAL_FAILED",
        targetTransactionId: req._id as string,
        snapshot: JSON.stringify({
          userId: req.userId,
          amount: req.amount,
          currency: req.currency,
          method: req.method,
          providerReference: args.providerReference ?? null,
          reason: args.reason ?? null,
        }),
        timestamp: Date.now(),
      });
    }
    return result;
  },
});

// ═══════════════════════════════════════════════════════════════════════
// PROVIDER-VERIFIED RECONCILIATION (webhook + background poller)
//
// A payout webhook is only a HINT that something changed. We never act on the payload: we ask
// Monime's API (GET /v1/payouts/{id}) and act on ITS answer, after binding the payout to OUR
// withdrawal (same payout id, same metadata.withdrawalId, same amount and currency).
// A forged webhook therefore cannot complete or fail any withdrawal.
// ═══════════════════════════════════════════════════════════════════════

export const findRequestForPayout = internalQuery({
  args: { payoutId: v.string(), hintWithdrawalId: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const byRef = await ctx.db
      .query("withdrawal_requests")
      .withIndex("by_providerReference", (q) => q.eq("providerReference", args.payoutId))
      .first();
    if (byRef) return byRef;
    if (args.hintWithdrawalId) {
      const id = ctx.db.normalizeId("withdrawal_requests", args.hintWithdrawalId);
      if (id) return await ctx.db.get(id);
    }
    return null;
  },
});

export const listProcessingWithReference = internalQuery({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db
      .query("withdrawal_requests")
      .withIndex("by_status", (q) => q.eq("status", "processing"))
      .take(50);
    return rows.filter((r) => !!r.providerReference).map((r) => ({ id: r._id, providerReference: r.providerReference! }));
  },
});

type ReconcileResult = { result: string; status?: string };

async function reconcileWithProvider(
  ctx: any,
  req: Doc<"withdrawal_requests">,
  payoutId: string
): Promise<ReconcileResult> {
  if (req.status === "completed" || req.status === "failed" || req.status === "cancelled") {
    return { result: "already_final", status: req.status };
  }
  if (req.method !== "mobile_money") return { result: "not_a_provider_payout" };

  const { spaceId, accessToken, apiBaseUrl } = getMoniMeConfig();
  if (!spaceId || !accessToken) return { result: "provider_not_configured" };

  let payout: any;
  try {
    const r = await fetch(`${apiBaseUrl}/payouts/${encodeURIComponent(payoutId)}`, {
      headers: { Authorization: `Bearer ${accessToken}`, "Monime-Space-Id": spaceId },
    });
    if (!r.ok) return { result: `provider_http_${r.status}` };
    payout = (await r.json().catch(() => ({})))?.result;
  } catch {
    return { result: "provider_unreachable" }; // ambiguous: change nothing
  }
  if (!payout || payout.id !== payoutId) return { result: "provider_bad_response" };

  // Bind the provider's payout to OUR withdrawal. Any mismatch is ignored (never completes/fails).
  const metaId = payout.metadata?.withdrawalId;
  if (metaId !== (req._id as string)) return { result: "binding_mismatch" };
  if (req.providerReference && req.providerReference !== payoutId) return { result: "binding_mismatch" };
  const expectedMinor = Math.round(req.amount * 100);
  if (payout.amount?.value !== expectedMinor || payout.amount?.currency !== req.currency) {
    return { result: "amount_mismatch" };
  }

  const status = String(payout.status ?? "").toLowerCase();
  if (status === "completed") {
    const r: any = await ctx.runMutation(internal.withdrawals.applyProviderPayoutResult, {
      requestId: req._id, outcome: "completed", providerReference: payoutId,
    });
    return { result: "applied", status: r.status };
  }
  if (status === "failed") {
    const detail = payout.failureDetail;
    const r: any = await ctx.runMutation(internal.withdrawals.applyProviderPayoutResult, {
      requestId: req._id, outcome: "failed", providerReference: payoutId,
      reason: detail?.message ?? detail?.code ?? "Payout failed at provider",
    });
    return { result: "applied", status: r.status };
  }
  // pending | processing | (payout.delayed): not final. Remember the payout id so the poller can follow it.
  if (!req.providerReference) {
    await ctx.runMutation(internal.withdrawals.recordOutcome, {
      requestId: req._id, outcome: "processing", providerReference: payoutId,
    });
  }
  return { result: "not_final", status };
}

/** Called by the webhook receiver with the (untrusted) payout id from the payload. */
export const reconcilePayout = internalAction({
  args: { payoutId: v.string(), hintWithdrawalId: v.optional(v.string()) },
  handler: async (ctx, args): Promise<ReconcileResult> => {
    if (!/^pyt-[A-Za-z0-9_-]{4,80}$/.test(args.payoutId)) return { result: "ignored_bad_id" };
    const req: Doc<"withdrawal_requests"> | null = await ctx.runQuery(internal.withdrawals.findRequestForPayout, args);
    if (!req) return { result: "ignored_unknown_payout" };
    return await reconcileWithProvider(ctx, req, args.payoutId);
  },
});

/** Safety net so completion never depends on webhook delivery: polled by a cron. */
export const reconcileProcessing = internalAction({
  args: {},
  handler: async (ctx): Promise<{ checked: number }> => {
    const rows: Array<{ id: Id<"withdrawal_requests">; providerReference: string }> = await ctx.runQuery(
      internal.withdrawals.listProcessingWithReference,
      {}
    );
    for (const row of rows) {
      const req: Doc<"withdrawal_requests"> | null = await ctx.runQuery(internal.withdrawals.getRequestInternal, { requestId: row.id });
      if (req) await reconcileWithProvider(ctx, req, row.providerReference);
    }
    return { checked: rows.length };
  },
});
