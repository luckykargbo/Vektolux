# Payments audit (repository level) — existing Monime-based system

Scope: what the code in this repository does today. **Nothing here was exercised against the live Monime
account, webhook, or deployment** (this environment has no `.env.local`, no Convex CLI login and no
deployment credentials, so no read-only inspection of the deployment was possible). "Verified" below means
verified by automated tests against a *fake* Monime that the tests themselves implement.

## 1. How money moves (Monime is the aggregator; Orange/Africell/QMoney run THROUGH it)
| Method | Initiation | Provider step | How we learn it was paid | Credit |
|---|---|---|---|---|
| Mobile-money deposit (Orange / Africell / QMoney) via Monime hosted checkout | `payments.initiateMoniMePayment` (alias `createTopUpSession`) | `POST /checkout-sessions` (momo/bank/card options enabled in the payload) | Signed webhook `checkout_session.*` **or** the app's status check; both call `settleMoniMeReference`, which re-reads `GET /checkout-sessions/{id}` | `settleVerifiedDeposit` (wallet core), amount = what Monime reports |
| USSD payment code (fallback when checkout creation is rejected; needs a real phone) | same action | `POST /payment-codes` | webhook `payment_code.*` / status check → `GET /payment-codes/{id}` | same |
| Subscription purchase via Monime | `initiateMoniMePayment` with `subscriptionTierCode` (price quoted by the server) | as above | as above | deposit, then `activateSubscriptionFromDeposit` |
| Escrow funding via Monime (vehicle, real estate, inspection pass, booking) | `initiateMoniMePayment` with an order id (amount quoted by the server) | as above | as above | deposit, then `fundEscrowFromDeposit` (held, not paid out) |
| Wallet-funded escrow / subscription | `createEscrowPayment`, order-specific mutations, `subscriptions.*` | none | n/a | double-entry ledger |
| Mobile-money withdrawal | `withdrawals.requestWithdrawal` (PIN, reservation first) | `POST /payouts` | webhook `payout.*` / poller → `GET /payouts/{id}` bound to OUR withdrawal id + amount | released only on Monime-confirmed completion |
| Bank-transfer escrow deposit | `payments.generateBankEscrowReference` | customer wires to the configured account | **admin** `confirmBankEscrowTransfer` (no bank webhook exists) | admin-confirmed, ledgered |
| Manual merchant claims (QMoney/Afrimoney till) | `submitManualPaymentClaim` | customer pays a till | **admin** approval after checking | admin-approved |
| Bank withdrawal | `requestWithdrawal` (method bank) | none | admin processes and resolves | admin-resolved |
| Direct Orange Money webhook (`/webhooks/orange-money`) | n/a (Orange pushes) | **separate, unconfirmed Orange contract** | HMAC of raw body only; credits only a VERIFIED phone | see §3 |

Card: only through Monime's hosted checkout (`paymentOptions.card.disable=false`). Whether the card/bank
options are actually enabled for the Vektolux Monime space is a Monime-account setting this repo cannot see.

## 2. Orange Money: Monime or Orange?
Orange Money payments initiated by the app go through **Monime** (provider ids m17/m18/m19 are only
hints in checkout metadata). Their webhook is the Monime webhook below. The separate
`/webhooks/orange-money` routes belong to the *direct Orange* option in `.env.example` ("Option A") whose
contract Orange has not supplied (`docs/IOS_TEST_BUILD.md`: "Orange Money stays disabled until Orange
provides its webhook documentation"). The two contracts are different and are kept apart.

## 3. Webhook contracts
- **Monime** (`lib/monimeWebhook.ts`, `http.ts`). Checked against docs.monime.io on the day of this
  review:
  - *Documented:* header `Monime-Signature` ("includes a timestamp"; for origin, integrity, replay);
    a webhook's `verificationMethod` is **HS256** (shared secret, 32–256 chars) **or ES256** (ECDSA,
    PEM P-256 public key); `event.id` is stable across retries; payment-code statuses are
    pending / processing / completed / expired / cancelled; events listed are `payment_code.*` and
    `payout.*` (+ `payout.delayed`), and **`checkout_session.*` are marked "Coming soon"**.
  - *Not documented where reachable:* the header's internal layout, the signed string, encoding and
    tolerance. The "HMAC Verification" guide page did not render, and the official TypeScript SDK
    contains no verification code. The implemented `t=<unix>,v1=<base64>` over `"<t>_"+raw body`, 300 s
    window is therefore an **assumption** inherited from the original code.
  - *Consequences:* (a) the implementation is HS256-only: if Vektolux's Monime webhook is ES256 every
    delivery is rejected (safe, but it never settles); (b) hosted-checkout payments have no documented
    webhook yet, so they settle via status checks — see `checkMyPendingDeposits` and the reconciliation
    switch; (c) money safety does not depend on the signature (the payload is a hint; Monime's API decides).
- **Direct Orange**: unverified contract; accepts only an HMAC of the body; credits only an active account
  whose phone number is verified (nothing sets that yet), otherwise holds. Not the path used by the app.

## 4. Defects found and fixed in this pass (all with tests in `convex/monimeInitiation.test.ts`,
`convex/bankAccountConfig.test.ts`, `convex/cronsDisabled.test.ts`)
1. **Client-chosen currency**: `initiateMoniMePayment` stored the client's `currency` on the pending
   deposit while always creating an SLE checkout. A non-SLE value made a real payment fail with
   `currency_mismatch` *after the customer paid*. Now anything but SLE is refused before anything is
   recorded or sent.
2. **Invented phone number**: with no phone, `23276000000` was sent to Monime (metadata and as the
   `authorizedPhoneNumber` of the USSD fallback — possibly a real person's number). Now no number is
   invented and the fallback is skipped without a phone.
3. **Client-chosen `returnUrl`**: passed straight to Monime as `successUrl`. Now only the app's own
   `vektolux://…` scheme is accepted.
4. **Unbounded checkout creation**: each call is an outbound Monime request. Now 10 per account per 10 min.
5. **Bank-transfer destination**: previously a number hard-coded in source that nobody had confirmed.
   Now it comes from deployment env **or the admin-managed `bank_transfer` payment setting** (so an owner
   who already entered it in the dashboard needs to do nothing); the old seed's placeholder numbers are
   ignored; and an owner who wants to keep the previous account can adopt it once with
   `internal.payments.setEscrowBankAccount({confirm:true, bankName, accountName, accountNumber})` (owner supplies the confirmed details; none are stored in source).
   Until one of these exists the app says bank transfer is "not available yet" — that is why it may look
   unavailable after this change.
6. **Job switches**: one flag controlled everything. They are now separate groups, all `false`
   (`JOB_SWITCHES`), with a test that no cron is registered.

7. **`processed` treated as paid** (follow-up review): a payment code counted as paid at `completed` OR
   `processed`; Monime documents no `processed` status (and `processing` means in flight). Paid is now
   `completed` only.
8. **No settlement path for a closed app**: with `checkout_session.*` webhooks "coming soon" and the
   poller off, a hosted-checkout payment made after the app closed stayed pending until someone checked.
   Added `payments.checkMyPendingDeposits` (caller's own deposits only, ≤5, 6/min, each re-verified with
   Monime). **The app must call it when the wallet/history opens** — the function and its session-token
   registration exist; the screen wiring is not done yet.

9. **Seeded placeholder rows still public**: if the old seed ever ran in production, an *enabled*
   `bank_transfer` row with the made-up number `0012345678` is served by `getActivePaymentMethods` and
   accepted by claim submission. Such a row is now hidden and refused. The seed's merchant code `001`
   (QMoney/Afrimoney rows) is NOT filtered because it might be a real code: **the owner should check
   those two rows in the dashboard** (Payments) and either confirm or disable them.

## 4b. What `setEscrowBankAccount` does (it has NOT been run)
Internal mutation, callable only by the owner from the Convex dashboard/CLI, and only with
`{confirm: true, bankName, accountName, accountNumber}`. **No account details are stored in the
repository**: the owner passes them in (the account older builds hard-coded is visible in the git history
of `convex/payments.ts`, to be compared with the bank's records first). It writes ONE row in
`payment_settings` (`providerId: "bank_transfer"`) with `isEnabled: true`; it refuses placeholders and
malformed numbers, refuses to overwrite a row that already has a real number, writes nothing else and
returns only the last 4 digits. Effects once run: the bank-details query and `generateBankEscrowReference`
give customers that account, and the admin payment-methods list shows the row.
**Confirm first:** the bank confirms number and name, it is a Vektolux-controlled escrow account, and
compliance agrees customers should wire there. Or simply enter the details in the dashboard (Payments →
bank transfer) — no code needed. No read-only look at the live `payment_settings` was possible.

## 5. Automation and reconciliation (all OFF — owner decision)
| Group (`convex/crons.ts` `JOB_SWITCHES`) | Jobs | What it can do |
|---|---|---|
| `RECONCILIATION_JOBS_ENABLED` | poll pending Monime deposits; poll processing payouts | **Reads** Monime and applies only outcomes Monime confirms for our own records. Never starts a payment or payout. The natural first switch to turn on: it is the safety net for a missed or rejected webhook. |
| `HOUSEKEEPING_JOBS_ENABLED` | purge webhook-event rows >30 days | housekeeping |
| `SUBSCRIPTION_JOBS_ENABLED` | expire + reminders | notifications / status |
| `ESCROW_RELEASE_JOBS_ENABLED` | release booking escrow 24 h after end | **moves money to vendors** |
| `DELETION_JOBS_ENABLED` | erase accounts after 30 days | **irreversible** |
Without any job: webhook (if its signature scheme is right) + user/admin status checks settle everything.

## 6. Not verified (needs the real account / a real small payment)
- The Monime webhook signature scheme above, and the exact header casing.
- That the Vektolux Monime space has momo, bank and card options enabled, and the status strings
  (`completed`, `processed`, `expired`, `cancelled`, `failed`, `delayed`) for checkout sessions,
  payment codes and payouts match Monime's current API.
- Payout request/response shapes in `withdrawals.ts` (the file itself notes this).
- Whether the previously displayed bank account is correct (decision: adopt or set another).
- Production data: existing pending deposits, webhook-event rows, env var *names* present.

## 7. How to confirm safely (owner actions, no code changes)
1. In the Convex dashboard, check env **names** exist: `MONIME_SPACE_ID`, `MONIME_ACCESS_TOKEN`,
   `MONIME_WEBHOOK_SECRET` (values stay hidden).
2. Make ONE small real deposit from a test account; watch Logs for `[MoniMe Webhook] … -> settled`
   (good) or `rejected: mismatch|header_format|timestamp` (scheme mismatch → send me the header
   *format* only, never the secret).
3. Then consider turning on `RECONCILIATION_JOBS_ENABLED` on a rehearsal deployment first.
