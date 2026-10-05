# Vektolux Admin Dashboard

Local admin web dashboard for Vektolux. It has no database of its own and no hosting: it runs on your
computer and talks to the live Convex backend `https://ideal-poodle-813.convex.cloud` (the only
deployment; there is no fallback).

## Run it

```bash
cd admin-dashboard
npm install
cp .env.example .env.local      # first time only: contains just the public Convex URL
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Signing in

Use the **administrator account's email and password** — they are checked against the live Convex
`users` table (only accounts with the `admin` role get in). Credentials are never stored in this
repository. If the admin password is lost, the operator resets it from the Convex CLI with the
internal `auth:resetAdminCredentials` command (see the root `README.md`, section 8).

## Pages

- **Business Roles** (`/dashboard/roles`): role applications (Real Estate Agent, Owner, Hotel Operator,
  Car Dealer…), filter by status (pending by default); **Approve** (optional note), **Reject** and
  **Suspend** (reason required). Calls `roles:adminListRoleApplications` /
  `roles:adminDecideRoleApplication`; every decision is audited and the applicant is notified.
- **Listing Review**: agent listings waiting for approval (photos, video, details, private
  verification address); approve / reject / remove / archive with a required reason.
- **Users**, **Verifications** (identity documents), **Hotels** (hotel verification),
  **Listings** (take-down with a reason; bulk deletion is disabled), **Listing Agents**.
- **Fees** (fee & commission rules), **Finance** (user funds, escrow, withdrawals, refunds,
  subscription revenue and platform fees reported separately), **Payments**, **Escrow**,
  **Real-Estate Escrow**, **Booking Disputes**, **Refund Recovery**, **API Health**, **Notifications**.
- **Seed** is disabled: sample data is never injected into the live database.

All money-moving and approval actions are enforced on the Convex server (admin session required);
the dashboard only forwards requests.

## Architecture

- Next.js 14 App Router; API routes under `src/app/api/*` call Convex with `ConvexHttpClient`
  (server-side), forwarding the admin session token.
- The admin session is kept in `sessionStorage` (cleared when the browser closes).

## Environment variables (`.env.local`, git-ignored)

| Name | Required | Value |
|---|---|---|
| `NEXT_PUBLIC_CONVEX_URL` | yes | `https://ideal-poodle-813.convex.cloud` |
| `CONVEX_URL` | yes | same |
| `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` | no | Only for the optional push-notification sender (`/api/admin/send-notification`). Firebase is used purely to deliver pushes, never as a backend. Take them from your private backup; never commit them. |

## Security

This dashboard is for **local use only**. Never expose port 3000 to the internet and never deploy it
to a public host without adding proper protection first.
