// convex/crons.ts
import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// ⚠ ALL JOBS ARE PAUSED (owner's decision, 2026-10-05, first deploy).
// These jobs act on live money / subscription / personal data by themselves, so each group has its OWN
// switch and every switch is false. To enable a group: set that constant to true, rehearse on a
// non-production deployment first, then deploy. Nothing depends on them running: privileges follow the
// real expiry dates at every check, deposits and payouts are settled by the signed Monime webhook
// (always re-verified against Monime's API) and by the user-triggered status checks.
//
// Recommended order for the owner (least to most consequential):
//   1. RECONCILIATION_JOBS_ENABLED  — only READS Monime and applies outcomes Monime itself confirms
//      (deposits that were paid but whose webhook was missed; payouts that completed/failed). It never
//      starts a payment or a payout. This is the safety net for lost webhooks.
//   2. HOUSEKEEPING_JOBS_ENABLED    — purges old webhook-event rows.
//   3. SUBSCRIPTION_JOBS_ENABLED    — records expiries and sends reminders.
//   4. ESCROW_RELEASE_JOBS_ENABLED  — RELEASES held booking escrow to vendors 24h after the booking.
//   5. DELETION_JOBS_ENABLED        — erases/anonymises accounts after the 30-day window.
export const JOB_SWITCHES = {
  RECONCILIATION_JOBS_ENABLED: false,
  HOUSEKEEPING_JOBS_ENABLED: false,
  SUBSCRIPTION_JOBS_ENABLED: false,
  ESCROW_RELEASE_JOBS_ENABLED: false,
  DELETION_JOBS_ENABLED: false,
  // Expires UNPAID escrow orders/contracts (14 days, never bank-transfer) and passes past their own
  // deadline. Writes status only; never touches wallets or the ledger. Run the admin dry-run first.
  ESCROW_ORDER_EXPIRY_JOBS_ENABLED: false,
} as const;

if (JOB_SWITCHES.RECONCILIATION_JOBS_ENABLED) {
  // Completion of Mobile Money withdrawals must not depend on webhook delivery: every 5 minutes,
  // ask the provider about any withdrawal still "processing" and apply its confirmed outcome.
  crons.interval(
    "reconcile processing withdrawals",
    { minutes: 5 },
    internal.withdrawals.reconcileProcessing,
    {}
  );

  // Same for deposits: credit any MoniMe payment that was paid but whose webhook we missed.
  crons.interval(
    "reconcile pending moniMe deposits",
    { minutes: 5 },
    internal.payments.reconcilePendingDeposits,
    {}
  );
}

if (JOB_SWITCHES.SUBSCRIPTION_JOBS_ENABLED) {
  // Subscriptions: record expiries and send renewal reminders (privileges already follow the real
  // expiry date at every check, so nothing depends on this job running on time).
  crons.interval("expire subscriptions and send reminders", { hours: 1 }, internal.subscriptions.expireAndRemind, {});
}

if (JOB_SWITCHES.ESCROW_RELEASE_JOBS_ENABLED) {
  // Marketplace bookings: release escrow 24h after the booking ends unless it was disputed.
  crons.interval("release due booking escrows", { minutes: 15 }, internal.bookings.releaseDueBookings, {});
}

if (JOB_SWITCHES.ESCROW_ORDER_EXPIRY_JOBS_ENABLED) {
  crons.interval("expire unpaid escrow orders", { hours: 6 }, internal.escrowExpiry.expireUnpaidOrders, {});
}

if (JOB_SWITCHES.DELETION_JOBS_ENABLED) {
  // Account deletion: erase/anonymise accounts whose 30-day window elapsed (retention-aware; see
  // accountDeletion.ts and docs/account-deletion-decisions.md).
  crons.interval("complete scheduled account deletions", { hours: 6 }, internal.accountDeletion.processDueDeletions, {});
}

if (JOB_SWITCHES.HOUSEKEEPING_JOBS_ENABLED) {
  // Webhook event ledger housekeeping.
  crons.interval("purge old monime webhook events", { hours: 24 }, internal.monimeWebhooks.purgeOldEvents, {});
}

export default crons;
