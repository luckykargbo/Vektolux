# Real Estate Agent: seven-day onboarding, badge and posting eligibility — AUDIT ONLY
> **OUTSTANDING REQUIREMENT — DO NOT LOSE.** The seven-day agent onboarding, badge and posting-eligibility
> policy is a required production-readiness item. It is **not implemented**; this document is the audit and the
> recommended rule. Implement only after the owner approves the definition in section 4.

Status: **NOT IMPLEMENTED.** Read-only findings from the code at this checkpoint, plus a recommendation.

## 1. What exists today
- **There is no seven-day period anywhere in the code** (no trial, onboarding window or deadline for a new
  agent; a search for seven/7-day/trial/onboarding finds only analytics windows).
- The only time-boxed policy is the **legacy-agent grace**: 14 days from a fixed
  `LEGACY_SUBSCRIPTION_POLICY_LAUNCH_TIMESTAMP` (`convex/lib/permissions.ts`), for agents approved *before*
  the policy launched. The constant is `null`, so **today nobody receives any grace** (fail safe).
- A new agent today: registers as a client → a `role_applications` row (`pending`) is created
  (`auth.registerUser` / `users.applyRoleUpgrade`) → an administrator approves it
  (`roles.adminDecideRoleApplication` sets `role`, `roleApprovedAt`, `roleApprovedBy`) → to post they need
  an **active, unexpired paid agent subscription** (`postingPermission`). No subscription ⇒ cannot post.
- **Badge** = `professionalBadge()` (permissions.ts): computed on read from role-approved + active agent
  subscription, never stored, never client-settable. It expires with the subscription.
- A second, older pipeline exists: `agentVerification.*` (`verification_requests`, documents, status
  `approved_pending_payment` → "Agent can now activate verified subscription badge") and
  `businessVerification.*`. Its `activateVerifiedBadge` internal mutation (stores `agent_profiles.isVerified`,
  `users.isVerified/isVerifiedSeller`) **has no caller**; subscription payment never advances that request.
  So there are two overlapping notions of "verified agent" (document KYC vs paid computed badge).
- Pricing is server-side: `subscription_plans` (`basePrice`, `discountPercent`, `promoStart/End`,
  `billingInterval` monthly/quarterly/annual) → `effectivePrice()`; checkout amounts come from
  `getCheckoutQuote`, never from the client. Admin plan editing: `adminUpsertPlan`.

## 2. Answers to the audit questions
| Question | Finding |
|---|---|
| What starts the 7 days? | Nothing does; the concept does not exist. Candidate timestamps already stored server-side: `users._creationTime`, `role_applications._creationTime`, `users.roleApprovedAt` (admin-set). |
| Protected from reset? | N/A today. `roleApprovedAt` is written only by an admin mutation; clients cannot edit it. Caveat: re-approval after suspension **overwrites** `roleApprovedAt` (so a naive "approval + 7 days" would be renewable by suspend/re-approve). |
| What is paid? | One product only: the recurring **agent subscription** (`vendor_subscriptions`). There is no separate one-off "verification badge fee"; the badge is a by-product of an active subscription. The older pipeline's copy ("activate verified subscription badge") blurs the two. |
| Can an agent post before paying? | **No** (server-enforced in `postingPermission` and every listing creator, incl. `requireVerifiedSeller`), except an eligible legacy agent inside the fixed 14-day grace (currently nobody). Admin can grant a complimentary subscription (`adminGrantSubscription`, audited). |
| Is the badge client-forgeable? | No. Computed server-side; `getProfessionalBadge` is a read. |
| Are prices/discounts/grace server-side? | Yes (effectivePrice, quote, legacy grace from constants). |
| Does it affect other roles? | The subscription rule applies to agents and hotel operators only; owners, dealers and clients are not subject to it (`postingPermission`). The legacy grace is agent-only. |
| Can admins see eligibility/deadline/payment/verification/reason? | **Partly.** `roles.adminListRoleApplications` shows identity status; `subscriptions.adminListSubscriptions` shows subscription status/expiry; nothing shows a per-agent "why blocked" or a deadline. `getMyProfessionalStatus` gives the *user* those fields; admins have no equivalent view. |

## 3. Gaps against the intended behaviour
1. No onboarding window exists; implementing "7 days then paid" is a new rule, not a fix.
2. Re-approval overwrites `roleApprovedAt` (renewable clock) — needs a write-once first-approval stamp.
3. Two verification pipelines + dead `activateVerifiedBadge` ⇒ ambiguity over what "verified" means and
   whether KYC verification is required before a badge.
4. Badge fee vs subscription fee are not distinguished in product or data.
5. Admins lack an eligibility/deadline/blocked-reason view.
6. Legacy grace is unconfigured (`null`); existing agents currently need a paid subscription immediately
   — a deliberate fail-safe, but a launch decision is pending (`legacyAgentPolicyReport` exists).

## 4. Recommended single definition (needs owner approval before any code)
- **Start event: first admin approval of the Real Estate Agent role.** Registration grants nothing and an
  application can sit in review; the user should not lose days to admin latency.
- **Store once, server-side:** `agentOnboardingStartedAt` set only if undefined at approval (never reset by
  re-approval, suspension, profile edits, logout or new sessions). Deadline = start + 7 days, computed on
  read like the legacy grace (no per-user "extend" field).
- **During the window:** allow posting without a subscription **only if** the account is role-approved
  (and, if the owner wants it, identity-verified). **After:** the paid subscription requirement applies,
  server-enforced in `postingPermission`.
- **Badge:** issued only while `role approved AND (identity/KYC verified if required) AND active paid
  subscription`. Never because 7 days elapsed or because a payment alone was made.
- **Existing agents:** handled only by the legacy-grace constant (owner sets the launch timestamp);
  never given the 7-day window retroactively unless explicitly decided.
- **Admin view:** per agent — approved at, onboarding deadline, subscription status/expiry, KYC status,
  `postingPermission` verdict + reason.

## 5. Files that would change
`convex/schema.ts` (one optional field), `convex/roles.ts` (stamp at approval), `convex/lib/permissions.ts`
(`postingPermission`, `professionalBadge`), `convex/subscriptions.ts` (`getMyProfessionalStatus`, an admin
status query), `convex/agentVerification.ts` (retire or wire `activateVerifiedBadge`), dashboard
Roles/Users pages, Flutter `professional_subscription_screen.dart` and agent workspace messaging.

## 6. Tests needed
Window start = first approval only; suspend→re-approve does not extend; edits/logout/new sessions do not
move it; posting allowed inside, refused after (server, every listing creator); other roles unaffected;
badge absent without payment, absent without required KYC, absent after expiry; legacy agents unchanged;
admin view shows deadline and reason; discount/promo applied server-side at checkout.
