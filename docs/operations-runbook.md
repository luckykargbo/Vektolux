# Operations runbook (repository-level; nothing here has been run against a live system)

## 1. Money-in webhooks: what happens and how to recover
| Source | Route(s) | Accepted proof | Credits a wallet when |
|---|---|---|---|
| Orange Money | `/webhooks/orange-money`, `/api/webhooks/orange-money`, `/payments/orange-money/webhook` | HMAC-SHA256 of the raw body in `x-orange-signature` keyed with `ORANGE_MONEY_WEBHOOK_SECRET`. The secret itself is **not** accepted. **The provider's real signing scheme is unconfirmed**: if Orange's differs, every delivery is rejected (fail closed). | status is success, currency SLE, **and the paying phone is a VERIFIED phone of an active account** (`users.phoneVerifiedAt/Number`). Otherwise the delivery is held. |
| Monime | `/webhooks/monime`, `/api/webhooks/monime` | provider signature (see `convex/lib/monimeWebhook.ts`) | matches a pending checkout the app created for an authenticated user |
| eIDV | `/api/v1/verifications/webhook` | HMAC-SHA256 body, `x-signature`, `EIDV_WEBHOOK_SECRET` | n/a (identity result; strict field validation, fail closed) |

### Held / orphaned carrier deposits
Rows in `telco_webhook_logs` with `status` `HELD_UNVERIFIED_PHONE` or `ORPHANED_USER` and
`isProcessed=false` were **not** credited. To resolve one: confirm the payer out-of-band, record phone
ownership with `internal.users.markPhoneVerified({userId, phone, method})` (owner-run, e.g. from the
Convex dashboard), then have the provider redeliver (or re-run `internal.payments.processIncomingCarrierDeposit`
with the stored fields). The ledger key is the carrier transaction id, so it credits at most once.
Nothing in the app calls `markPhoneVerified`; a customer-facing phone-ownership flow (OTP) is a product
decision (see docs/security-open-items.md).

### Duplicates / replays
Every credit path is keyed on the provider transaction id (`transactions.by_transaction_id`,
`by_gateway_ref`, `telco_webhook_logs.by_ext_id`). A replay returns `ALREADY_PROCESSED`.

## 2. Switching money paths off safely
- Background reconcilers/auto-release: `convex/crons.ts` `BACKGROUND_JOBS_ENABLED = false` (leave false
  until the owner enables jobs one at a time on a rehearsal deployment).
- To stop an inbound provider: unset its webhook secret on the deployment (`ORANGE_MONEY_WEBHOOK_SECRET`,
  Monime webhook secret): every delivery is then rejected with 401. Re-enable by setting it again.
- To stop bank transfers: leave/unset `ESCROW_BANK_*` — the app shows "not available yet".
- Manual payment methods start disabled; administrators enable them in the dashboard.

## 3. Environment separation (not yet done; owner decision)
README documents one deployment (`dev:ideal-poodle-813`) holding live data. Target: separate `dev`,
`staging` (rehearsal, seeded copy), `prod`. Steps for the owner: create the prod deployment in the Convex
dashboard; set its env vars (names in `.env.example`); set repo variable `CONVEX_URL` to the approved
deployment for release builds (CI refuses to build without it); never run `convex dev` against prod.
Schema changes: deploy to staging first; additions in this branch are optional fields/indexes/tables only.

## 4. Monitoring / crash reporting (not implemented; provider choice needed)
No error tracking exists in the app, dashboard or Convex. Options that avoid Firebase: Sentry
(Flutter, Next.js and a Convex log drain), or Convex's own log streaming to a log service. Minimum
alerting wanted: webhook 4xx/5xx rate, `HELD_UNVERIFIED_PHONE` count, failed payouts, login lockouts,
`account_deletion_events`. Do not add a vendor SDK without the owner's choice and a privacy review.

## 5. Release checklist (repo-level facts)
- Android `targetSdk` is **34** (`android/app/build.gradle.kts`). Google Play's current minimum for
  new submissions must be checked on the day of release; raising it also enables edge-to-edge enforcement
  (API 35) and other behaviour changes that need on-device testing. Not changed blindly here.
- `minifyEnabled` is off; enabling R8 needs a full regression pass.
- CI release jobs require repository variable `CONVEX_URL` and signing secrets
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`;
  without them they fail by design. iOS App Store/TestFlight signing is not configured in CI (the
  workflow builds an unsigned test IPA only).
- The version shown in the app and checked in CI comes from `pubspec.yaml` (`version: x.y.z+build`).
