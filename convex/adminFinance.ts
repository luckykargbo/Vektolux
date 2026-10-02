// convex/adminFinance.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Admin financial overview (real data only, admin session required).
//
// Money categories are reported SEPARATELY and never merged:
//   user available funds · funds held in escrow · pending (unsettled) balances · deposits awaiting
//   provider confirmation · withdrawals in flight / completed / failed · refunds ·
//   subscription revenue (ledger) · platform fees / commission (ledger)
// User funds are liabilities the platform holds for users; they are NOT platform revenue.
// Every figure is computed from stored records at query time — nothing is estimated.
// ═══════════════════════════════════════════════════════════════════════

import { query } from "./_generated/server";
import { v } from "convex/values";
import { requireAdmin } from "./lib/auth";

const SCAN_LIMIT = 10_000;
const round2 = (n: number) => Math.round(n * 100) / 100;

type Bucket = { amount: number; count: number };
const add = (m: Record<string, Bucket>, currency: string, amount: number) => {
  const b = (m[currency] ??= { amount: 0, count: 0 });
  b.amount = round2(b.amount + amount);
  b.count += 1;
};

export const getFinancialOverview = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await requireAdmin(ctx, { sessionToken: args.sessionToken });
    const truncated: string[] = [];

    // ── user wallets (liabilities to users) ──────────────────────────
    const wallets = await ctx.db.query("walletBalances").take(SCAN_LIMIT + 1);
    if (wallets.length > SCAN_LIMIT) truncated.push("walletBalances");
    const userFunds: Record<string, { available: number; escrow: number; pending: number; wallets: number }> = {};
    for (const w of wallets.slice(0, SCAN_LIMIT)) {
      const c = (userFunds[w.currency] ??= { available: 0, escrow: 0, pending: 0, wallets: 0 });
      c.available = round2(c.available + (w.availableBalance ?? 0));
      c.escrow = round2(c.escrow + (w.escrowBalance ?? 0));
      c.pending = round2(c.pending + (w.pendingBalance ?? 0));
      c.wallets += 1;
    }

    // ── ledger revenue accounts (credits minus debits) ───────────────
    const ledgerNet = async (accountType: "SUBSCRIPTION_REVENUE" | "PLATFORM_REVENUE_REALIZED") => {
      const rows = await ctx.db
        .query("ledger_entries")
        .withIndex("by_account", (q) => q.eq("accountType", accountType))
        .take(SCAN_LIMIT + 1);
      if (rows.length > SCAN_LIMIT) truncated.push(accountType);
      const out: Record<string, Bucket> = {};
      for (const e of rows.slice(0, SCAN_LIMIT)) add(out, e.currency, e.direction === "CREDIT" ? e.amount : -e.amount);
      return out;
    };
    const subscriptionRevenue = await ledgerNet("SUBSCRIPTION_REVENUE");
    const platformFees = await ledgerNet("PLATFORM_REVENUE_REALIZED");

    // ── withdrawals ──────────────────────────────────────────────────
    const withdrawals: Record<string, Record<string, Bucket>> = {};
    for (const status of ["pending", "processing", "completed", "failed", "cancelled"] as const) {
      const rows = await ctx.db
        .query("withdrawal_requests")
        .withIndex("by_status", (q) => q.eq("status", status))
        .take(SCAN_LIMIT + 1);
      if (rows.length > SCAN_LIMIT) truncated.push(`withdrawals:${status}`);
      const m: Record<string, Bucket> = {};
      for (const r of rows.slice(0, SCAN_LIMIT)) add(m, r.currency ?? "SLE", r.amount);
      withdrawals[status] = m;
    }

    // ── deposits awaiting provider confirmation ─────────────────────
    const pendingTx = await ctx.db
      .query("transactions")
      .withIndex("by_status", (q) => q.eq("status", "pending"))
      .take(SCAN_LIMIT + 1);
    if (pendingTx.length > SCAN_LIMIT) truncated.push("transactions:pending");
    const depositsAwaiting: Record<string, Bucket> = {};
    for (const t of pendingTx.slice(0, SCAN_LIMIT)) if (t.type === "top_up") add(depositsAwaiting, t.currency, t.amount);

    // ── completed deposits and refunds ───────────────────────────────
    const completedTx = await ctx.db
      .query("transactions")
      .withIndex("by_status", (q) => q.eq("status", "completed"))
      .order("desc")
      .take(SCAN_LIMIT + 1);
    if (completedTx.length > SCAN_LIMIT) truncated.push("transactions:completed");
    const depositsSettled: Record<string, Bucket> = {};
    const refunds: Record<string, Bucket> = {};
    for (const t of completedTx.slice(0, SCAN_LIMIT)) {
      if (t.type === "top_up") add(depositsSettled, t.currency, t.netAmount ?? t.amount);
      else if (t.type === "refund") add(refunds, t.currency, Math.abs(t.amount));
    }

    // ── subscriptions ────────────────────────────────────────────────
    const now = Date.now();
    const activeSubs = await ctx.db
      .query("vendor_subscriptions")
      .withIndex("by_status_and_expiryDate", (q) => q.eq("status", "active").gt("expiryDate", now))
      .take(SCAN_LIMIT);

    return {
      generatedAt: now,
      userFunds,
      depositsAwaitingConfirmation: depositsAwaiting,
      depositsSettled,
      withdrawals,
      refunds,
      subscriptionRevenue,
      platformFees,
      activeSubscriptions: activeSubs.length,
      // Non-empty means a category had more rows than one query scans; figures are then partial.
      truncated,
    };
  },
});
