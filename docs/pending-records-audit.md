# Pending records and cancellation policy — READ-ONLY AUDIT
No record was cancelled, expired, deleted, reconciled or mutated. All jobs remain disabled.

Money-safety rules applied throughout: never cancel a deposit because a webhook is missing or late; never
cancel a withdrawal the provider may already have paid; never release escrow or refund to clear a status;
never erase ledger or audit rows; any future cleanup must be idempotent, audited, tested against late
provider confirmations, and initially disabled.

| # | Record | Created by | Authority for "still pending?" | Existing mechanism | Safe automatic action | Needs provider / admin / customer |
|---|---|---|---|---|---|---|
| 1 | Monime hosted-checkout deposit / payment code (`transactions` top_up `pending`, `MONIME_*`) | `recordPendingMoniMeTransaction` (`initiateMoniMePayment`) | **Monime API** (`GET /checkout-sessions/{id}`, `/payment-codes/{id}`) | webhook (payment_code only); app status checks; `checkMyPendingDeposits`; job `reconcilePendingDeposits` (OFF, 48 h window, 100 rows); `failMoniMeDeposit` when Monime says cancelled/expired | **Fail** only when Monime itself reports `expired`/`cancelled` (already done on every check). Credit only when Monime says `completed`. | A row still `pending` with **no Monime object bound** (`vktlx_…` ref) is *not* provably unpaid: the object may exist at Monime if the bind step failed. Needs provider-side lookup or admin review; do not auto-cancel. |
| 2 | Withdrawals / payouts (`withdrawal_requests` pending/processing) | `withdrawals.reserve` (funds moved available→pending) | **Monime** `GET /payouts/{id}` for mobile money; admin for bank | webhook `payout.*`; `reconcileProcessing` (OFF); `cancelMyWithdrawal` only for **bank** + `pending`; `adminResolveWithdrawal` | none automatic. A `pending` mobile-money request with no provider reference may or may not have reached Monime. | Mobile money: provider confirmation. Bank: admin. Customer may cancel bank requests only. Reserved funds return only via `releaseWithdrawal` (idempotent) after a confirmed failure/cancel. |
| 3 | Bank-transfer deposit claims (`escrow_payment_claims` PENDING_PAYMENT / PENDING_APPROVAL) and bank escrow references | `submitManualPaymentClaim`, `generateBankEscrowReference` | **Admin** checking the bank statement | admin approve/reject; no expiry | none. | Admin review of the statement (no bank webhook exists). A customer reminder/expiry-*notice* is safe; closing a claim is not. |
| 4 | Escrow orders: vehicle `PENDING_PAYMENT`, real-estate contracts `CREATED`, bookings `pending_payment`, inspection passes | `escrow.initiateEscrowOrder`, `realEstateEscrow.*`, `bookings.createBooking` | our own state + wallet/escrow ledger (no money held while pending) | bookings: buyer/vendor `cancelBooking`; **vehicle and real-estate unpaid orders have no cancel and no expiry** (status `CANCELLED` is never set anywhere) | An unpaid order (no held funds, no deposit claim, no Monime pending bound to it) is safe to expire by a documented rule (e.g. 7 days) | Anything with held funds, an open claim or a bound Monime checkout must go through refund/dispute paths, never "expire". Releases/refunds: admin or the documented settlement rules only. |
| 5 | Escrow disputes / refunds / reversals | dispute mutations; `payment_reversals` (`pending_recovery`) | admin decision + ledger | admin resolve; recovery tracking | none | Admin only. |
| 6 | Agent subscription payments / verification applications | Monime checkout (`subscription_checkout`), `role_applications` pending, `verification_requests` | Monime for payment; admin for applications | checkout as row 1; subscription `expireAndRemind` (OFF) | Notices only | Admin decisions; a paid-but-not-activated subscription is credited to the wallet and notified (no money lost). |
| 7 | Listings awaiting moderation (`moderationStatus: pending_review`) | agent submit | admin | queue + approve/reject/withdraw by owner | none (never auto-approve/reject) | Admin. SLA reminders are safe. |
| 8 | Viewing / booking requests (`bookings.status: requested`) | `createBooking` | owner/authorised agent | accept/decline/cancel | Expiring an unanswered, **free** request after N days is safe (no money) | Owner/agent decision otherwise. Paid bookings: row 4. |
| 9 | Account deletion (`deletionScheduledFor`) | `requestAccountDeletion` | the 30-day window + obligation checks | `processDueDeletions` (OFF) | none until enabled and rehearsed | Retention decisions; open obligations defer erasure. |
| 10 | Webhook events / reconciliation records | `monime_webhook_events`, `telco_webhook_logs` | n/a | `purgeOldEvents` (OFF; 30-day retention); `HELD_UNVERIFIED_PHONE` rows kept | purge of *done* event rows is safe | `failed`/held rows are evidence; keep until resolved. |

## Findings that matter
1. **Unpaid vehicle/real-estate escrow orders never leave `PENDING_PAYMENT`/`CREATED`.** Beyond UI noise,
   they are treated as open obligations by account deletion (`ESCROW_OPEN` / `RE_ESCROW_OPEN`), so a user who
   abandoned a checkout can never be erased. A narrowly-scoped "expire unpaid, nothing-held order" rule is
   the main missing lifecycle.
2. **Deposits left `pending` without a Monime object** are ambiguous (see row 1); they need an admin/provider
   look-up, not a timer.
3. Mobile-money withdrawals cannot be cancelled by the customer and rely on the provider outcome; with the
   reconciler off they depend on the webhook (HS256 layout unverified) or an admin.
4. Hosted-checkout deposits have no documented webhook; `checkMyPendingDeposits` (on wallet open) is now the
   user-side path, the reconciler (off) is the system path.
5. Stale pending rows are shown in history as "pending" with no age cue (misleading UI), and
   `checkMyPendingDeposits` ignores deposits older than 48 h.

## Recommended per-category policy (all initially disabled, audited, idempotent)
- **Deposits:** keep fail-on-provider-`expired|cancelled`; add an *age cue* in the UI (e.g. "waiting 3 days —
  contact support"); never auto-cancel by age. Provide an admin "re-check with Monime" action.
- **Withdrawals:** no auto-cancel. Add admin visibility of age + provider reference; allow customer cancel
  only when provably not dispatched (no provider reference and the dispatch call definitively rejected).
- **Bank claims:** reminders at 3 and 7 days; admin closes after contacting the customer.
- **Unpaid escrow orders:** introduce `CANCELLED` transition for orders older than N days with no held
  funds, no claim and no bound provider object; write an audit row; skip anything else.
- **Requests (free):** expire unanswered after N days with a notification.
- **Everything else:** unchanged.

## Tests required before any job is switched on
Expiry only when the authoritative state allows; late provider confirmation after expiry still credits
exactly once (for deposits: never expire by age); duplicate events; retry safety; held-funds orders are
never touched; audit rows written; account-deletion obligation checks treat expired orders as terminal.
