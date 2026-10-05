// convex/crons.ts
import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// ⚠ PAUSED FOR THE FIRST DEPLOY (owner's decision, 2026-10-05).
// The live backend jumps from the late-September code to this release in one deploy. These jobs act
// on live money / subscription data on their own (real Monime API calls, wallet credits, withdrawal
// outcomes and refunds, escrow releases, subscription expiries, ledger purges), so they stay OFF until
// the owner has checked the deployed release. To switch them on: set this to true and deploy again.
// Nothing else depends on them running: privileges already follow the real expiry dates at every check,
// and users can still trigger their own deposit / withdrawal status checks.
const BACKGROUND_JOBS_ENABLED = false;

if (BACKGROUND_JOBS_ENABLED) {
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

  // Subscriptions: record expiries and send renewal reminders (privileges already follow the real
  // expiry date at every check, so nothing depends on this job running on time).
  crons.interval("expire subscriptions and send reminders", { hours: 1 }, internal.subscriptions.expireAndRemind, {});

  // Marketplace bookings: release escrow 24h after the booking ends unless it was disputed.
  crons.interval("release due booking escrows", { minutes: 15 }, internal.bookings.releaseDueBookings, {});

  // Webhook event ledger housekeeping.
  crons.interval("purge old monime webhook events", { hours: 24 }, internal.monimeWebhooks.purgeOldEvents, {});
}

export default crons;
