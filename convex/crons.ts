// convex/crons.ts
import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

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

export default crons;
