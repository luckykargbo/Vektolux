# Vektolux

Sierra Leone marketplace: real estate (agents, owners, viewings, escrow), vehicles (rent / sale, car
dealers), hotels, wallet and Mobile Money payments (Monime).

| Part | Folder | Technology |
|---|---|---|
| Mobile app (iPhone + Android) | `lib/`, `test/`, `android/`, `ios/` | Flutter |
| Backend (the only backend) | `convex/` | Convex (TypeScript) |
| Admin dashboard (local only) | `admin-dashboard/` | Next.js 14 |
| CI: test builds (IPA + APK) | `.github/workflows/build_apps.yml` | GitHub Actions |
| iPhone/Android test-build notes (also the GitHub release text) | `docs/IOS_TEST_BUILD.md` | |

Other folders: `whatsapp-bot/` (separate helper bot, own README), `contracts/` (Hardhat audit-ledger
contract, optional), `supabase/` and `src/` (old, unused files kept for history — **not** a backend).

---

## 1. Authoritative deployment — read this first

**The one and only backend is the Convex deployment `dev:ideal-poodle-813`**
(`https://ideal-poodle-813.convex.cloud`, team `lucky-f11c9`, project `vektolux`).
It is a *dev-type* deployment that is used as production: the app, the admin dashboard and the
payment webhooks all talk to it.

- There is no Firebase backend, no fallback deployment and no second backend. Do not create one.
  (The admin dashboard has an optional Firebase *push-notification sender* only; it stores no data.)
- **`npx convex deploy` is WRONG for this project**: it targets the project's separate, unused "prod"
  deployment. Code reaches `ideal-poodle-813` with `npx convex dev --once` (see §7).
- `npx convex run …` (without `--prod`) runs against `ideal-poodle-813`, i.e. **live data**.
- The root `npm run dev` / `npm run deploy` scripts are deliberately disabled for this reason.

### Current production state (as of 2026-10-05)

- Deployed code: commit `4c3ae01` (everything up to and including the legacy-agent role fix, the
  professional-capability status and the CLI-only admin recovery command).
- **Background jobs are PAUSED**: `BACKGROUND_JOBS_ENABLED = false` in `convex/crons.ts`
  (owner's decision for the first deploy). Not running: withdrawal reconciliation, Monime deposit
  reconciliation, subscription expiry/reminders, booking escrow auto-release, webhook-log purge.
  Turning them on = set it to `true` and deploy — **owner's decision only**.
- `LEGACY_SUBSCRIPTION_POLICY_LAUNCH_TIMESTAMP` stays `null` until the owner has reviewed the legacy
  agents.
- Real-money deposits/withdrawals have not been tested. Do not test with real money.
- Latest test build: **1.0.31 (32)** — GitHub release `vektolux-ios-test-1.0.31-32`.

---

## 2. Tools to install on a new computer

| Tool | Version | Used for |
|---|---|---|
| Git | any recent | |
| Flutter (stable) | 3.22 or newer required by `pubspec.yaml`; developed on **3.47.2** (Dart 3.13.2); CI uses the latest stable | the app |
| Node.js + npm | **Node 20 or newer** (developed on Node 24.19, npm 11.17) | Convex CLI, tests, admin dashboard |
| Convex CLI | comes with `npm install` (`npx convex`, developed on 1.45) — no global install needed | backend |
| Java JDK 17 + Android SDK (Android Studio) | JDK 17 (same as CI) | local Android builds only |
| macOS + Xcode | not needed | iOS is built by GitHub Actions (see §9) |

---

## 3. First-time setup

```bash
git clone https://github.com/luckykargbo/Vektolux.git
cd Vektolux

flutter pub get                       # Flutter packages
npm install                           # Convex CLI + backend test tools (root package.json)
cd admin-dashboard && npm install && cd ..
```

### Connect the Convex CLI (needed for deploys, `convex run`, data inspection — not for tests)

```bash
npx convex login                      # log in with the Convex account that owns team lucky-f11c9
```

Then create `.env.local` in the repository root (git-ignored) containing **only these three lines**:

```
CONVEX_DEPLOYMENT=dev:ideal-poodle-813
CONVEX_URL=https://ideal-poodle-813.convex.cloud
CONVEX_SITE_URL=https://ideal-poodle-813.convex.site
```

Verify before doing anything else: `npx convex env list` must work and show the variable names
listed in §4. If the CLI asks to "create a new project" or "configure a new deployment", **stop** —
it is not pointing at `ideal-poodle-813`.

### Admin dashboard configuration

```bash
cp admin-dashboard/.env.example admin-dashboard/.env.local
```

It contains only the public Convex URL. Firebase push variables are optional (see
`admin-dashboard/README.md`).

### Android release signing (optional, local builds only)

`android/key.properties` and the keystore `android/app/vektolux-release.jks` are **secrets and are
never committed**. Copy both from your private backup onto the new computer at those paths. Without
them a local release APK is signed with the debug key (fine for testing; CI test APKs are signed
that way too). **Losing the keystore means future Play Store updates cannot be signed with the same
key — keep a safe backup of it.**

---

## 4. Secrets and environment variables

Secrets live **in the Convex dashboard**, never in the repository:
`https://dashboard.convex.dev/t/lucky-f11c9/vektolux/ideal-poodle-813/settings/environment-variables`
They are already set on the deployment; a new computer needs nothing locally for the backend.
`.env.example` lists every name the backend reads (names only, no values).

Currently set on `ideal-poodle-813` (names only): `MONIME_SPACE_ID`, `MONIME_ACCESS_TOKEN`,
`MONIME_API_BASE_URL`, `MONIME_WEBHOOK_SECRET`, `RESEND_API_KEY`, plus two leftovers from the removed
Moneroo integration (`MONEROO_SECRET_KEY`, `WEBHOOK_SECRET_HASH`) that no code reads any more.

Never commit: `.env`, `.env.local`, `android/key.properties`, `*.jks`, `*.p12`, `*.p8`, `*.pem`,
provisioning profiles, Apple keys, Monime/webhook/OAuth secrets. `.gitignore` already blocks them.

---

## 5. Run the app

```bash
flutter run                           # on a connected Android phone / emulator
```

The app always talks to `ideal-poodle-813` (`lib/core/constants/` / Convex client config) — any
account you create while testing is a **real** account on the live backend.

## 6. Run the admin dashboard (local only, no hosting)

```bash
cd admin-dashboard
npm run dev                           # http://localhost:3000
```

Sign in with the administrator account's email and password (stored on the live backend, never in
this repository). Pages include Business Roles (approve / reject / suspend role applications), Listing
Review, Users, Verifications, Hotels, Fees, Finance, Escrow, Booking Disputes, Refund Recovery and
Listing Agents. Details: `admin-dashboard/README.md`. It is not deployed anywhere — do not expose port
3000 to the internet.

## 7. Tests (all safe, nothing touches the live backend)

```bash
npx tsc --noEmit -p convex/tsconfig.json      # backend typecheck
npx vitest run                                # backend tests (convex-test, in-memory)
flutter analyze lib test                      # app static analysis
flutter test --concurrency=1                  # app tests incl. responsive layout harness
cd admin-dashboard && npx tsc --noEmit        # dashboard typecheck
```

Run vitest and the Flutter tests one after the other, not at the same time (on a small PC they
exhaust process spawning). Expected on 2026-10-05: 388 backend tests, 565 Flutter tests, all passing.

---

## 8. Commands: safe vs. needs the owner's explicit approval

**Safe (local only):** everything in §5–§7, `flutter build apk`, `npx convex codegen`,
`npx convex env list`, read-only `npx convex data <table>`, `npx convex logs`.

**Changes production — only with the owner's explicit approval, each time:**

| Command | Effect |
|---|---|
| `npx convex dev --once` | **Deploys** the local `convex/` code to `ideal-poodle-813`. Also regenerates `convex/_generated` (commit that). |
| `npx convex dev` (no `--once`) | Deploys on **every file save** — avoid. |
| `npx convex run <function> …` | Runs a function against live data. |
| `npx convex env set/remove …` | Changes live secrets. |
| `npx convex import …` | Overwrites live data. |
| Setting `BACKGROUND_JOBS_ENABLED = true` + deploy | Starts the money/subscription jobs. |
| Pushing to `main` without `[skip ci]` | Starts a CI build + updates the GitHub release (not a backend deploy). |

**Never:** `npx convex deploy` (wrong deployment), `npx convex run --prod`, creating new Convex
projects/deployments, `auth:seedDemoUsers` (would create a second admin — the admin's login email is
no longer the one it looks for) or `seedData:seedDiscoveryData` (inserts sample listings into live
data).

### Admin account recovery (operator only)

If the admin password is lost, from a computer logged in to the Convex CLI:

```bash
npx convex run auth:resetAdminCredentials "{email: 'admin-email@example.com', newPassword: 'at-least-8-chars'}"
```

It changes only the single admin account's email/password and signs it out everywhere. It is an
internal function: it cannot be called from the app or the dashboard.

---

## 9. Migrations / one-off backfills

All are internal functions (CLI only). They were handled at the 2026-10-05 deploy; **none needs to
run again** unless the owner decides otherwise.

| Function | Purpose | Status | Rerun? |
|---|---|---|---|
| `legacyRoleMigration:backfillLegacyAgentRoles` | Gives the `agent` role back to accounts approved as agents by the old admin flow (requires the legacy flag **and** an approved agent application; KYC-only flags are skipped). Pass `{dryRun: true}` first. | Ran 2026-10-05: 0 changes. Login also does this per user. | Safe, idempotent; changes user roles only. |
| `listingStats:backfillListingCounters` | Recounts listing inquiry / viewing-request counters from existing records. | Ran 2026-10-05: 0 listings. | Safe, idempotent (recount, not increment). |
| `bookings:backfillBookingSettlement` | Marks bookings paid before settlement tracking as "held" so they can be released. Moves no money. | Not needed: production has 0 bookings. | Safe, idempotent. |

New schema fields added since are all optional, so no data migration is required.

---

## 10. Builds

**Android (local):** `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`.

**iPhone + Android test builds (CI):** every push to `main` (unless the commit message contains
`[skip ci]`) runs `.github/workflows/build_apps.yml`: an unsigned IPA on macOS and an APK on Linux,
published to the GitHub release named in the workflow, with `docs/IOS_TEST_BUILD.md` as the release
text. Install the IPA with Sideloadly (instructions in that file). For a new build number update
together: `version:` in `pubspec.yaml`, the `test "$VER"` / `test "$BLD"` checks and both
`tag_name` / `name` entries in the workflow, and `docs/IOS_TEST_BUILD.md`.

No Apple signing credentials are used or stored; a TestFlight/App Store build would need a paid
Apple Developer account set up by the owner.

---

## 11. Architecture notes

- Money moves only through `convex/walletCore.ts`; amounts and fees are computed by the server
  (`convex/lib/fees.ts`, `feeRules.ts`); payment webhooks are hints that are re-verified with the
  provider; every user debit/credit is idempotent.
- Roles: a business role (agent, owner, hotel operator, car dealer, admin) is granted only by an
  administrator approving a role application (`roles.ts`). Car Dealer can be held *alongside* the
  agent role (`vehicleDealerApprovedAt`). A subscription gates posting, not identity.
- The app routes professionals by the server's `subscriptions:getMyProfessionalStatus`
  (`capabilities`), never by the role stored on the phone.
- Agent listings are reviewed by an admin before going live (`listingModeration.ts`).
- Convex coding rules for this repo: `convex/_generated/ai/guidelines.md` (read before editing
  `convex/`).
