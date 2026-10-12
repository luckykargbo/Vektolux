# Account deletion: behaviour, retained data, and decisions needed

Code: `convex/accountDeletion.ts` (`internal.accountDeletion.processDueDeletions`). It is **not scheduled**:
its cron entry lives inside the disabled `BACKGROUND_JOBS_ENABLED` block of `convex/crons.ts`.
The 30-day request window is created by `users.requestAccountDeletion`; signing in cancels it.

## When an account is erased
Only if all of these hold at run time (otherwise it is *deferred* and re-checked next run, never partially
erased): not an admin, no live session, and none of these open obligations —
wallet funds / escrow balance · in-flight withdrawals · unsettled vehicle escrow or its disputes · open or
paid-but-unsettled bookings · real-estate escrow contracts not finished, locked/disputed caution deposits,
open real-estate disputes, unfinished inspection passes · property-booking payments in flight · hotel stays
not closed (as guest or operator) · refund-recovery cases · pending payment claims / intents · a running
(or dunning) professional subscription · pending/active listing-agent authorizations.

## What is erased / anonymised
Sign-in methods, push tokens, sessions, email-verification and password-reset codes, saved listings,
follows, single-user notifications; the `users` row is anonymised in place (same `_id`); listings are
unpublished and lose their private contact phone; open QR payment requests are cancelled; agent and hotel
profile contact fields are blanked. An audit row (`account_deletion_events`, no personal data) is written.

## Deliberately retained (nothing deletes these)
Wallet balances, transactions, ledger entries, escrow orders, real-estate contracts / milestones / caution
deposits, bookings, withdrawal records, payment reversals, disputes, admin audit logs; KYC / identity
checks and documents, role applications, merchant/agent TIN and business registration fields;
contact requests and messages (the counterparty's record); files in storage.

## Decisions required from the owner / counsel (not invented here)
1. **Retention period** for financial records, KYC and identity documents, and dispute evidence in Sierra
   Leone (and any app-store / GDPR-style obligations that apply to your users).
2. **KYC files in storage** — keep for the retention period, then purge? Who triggers it?
3. **Messages** the deleted user sent: keep for counterparties, redact the body, or delete after N days.
4. **Public content** (listing photos/descriptions) — currently only unpublished, not erased.
5. **Subscriptions** — keep deferring until expiry (current), or allow erasure with forfeiture.
6. **Admin accounts** — never auto-erased (current); define a manual procedure.
7. Whether to notify the user before/after erasure (email/SMS) and what the in-app text should promise.

## Before enabling
Deploy schema additions to a rehearsal deployment, run `processDueDeletions` there with seeded accounts,
review `account_deletion_events`, and only then consider adding it to the enabled cron set.
