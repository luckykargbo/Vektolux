# Privacy policy & Terms: what is needed (not legal advice, not approved text)

The in-app Privacy Policy / Terms screens previously showed marketing-style statements that the code does
not support ("zero telemetry", "encrypted locally in SQLite"). They now say the documents are being
finalised. **Nothing in this repository is a reviewed legal document.** Counsel must write and approve
the final text; this list is only the topics the *code actually does* so the text can be accurate.

## Facts about the system the policy must reflect (from the code)
- Data collected at sign-up: name, email, phone, password (hashed), optional avatar; Google/Apple sign-in
  identity (subject id, verified email).
- Seller / professional verification: business name, TIN, ID document and selfie, licence documents.
- Location data on listings (exact coordinates are stored; public views show only a town-level location).
- Wallet and payments: balances, transactions, mobile-money phone numbers, bank/withdrawal destinations,
  escrow and dispute records, provider references.
- Messages between buyers and sellers/agents.
- Technical: session tokens, rate-limit counters (IP address), audit logs of administrator actions.
- Processors: Convex (hosting/database), Resend (email), Monime (payments), the SMS/identity providers in
  use. Confirm the real list before publishing.
- Retention/erasure: see `docs/account-deletion-decisions.md` (30-day window; financial and KYC records
  retained; owner/legal decision on periods).
- Account deletion is available in the app (Account > security), with the conditions listed there.

## Topics a policy and terms normally cover (to be written by counsel)
Controller identity and contact; lawful basis; purposes; recipients/processors and cross-border transfers;
retention periods; user rights and how to exercise them; children; security measures; breach notification;
cookies/analytics (the dashboard and app: none presently — confirm); changes to the policy.
Terms: eligibility, accounts and security, listings and moderation, fees and commissions (the 85/15 and
fee-rule schedule), escrow and dispute procedure, refunds, prohibited conduct, liability, governing law,
termination.

## App-store requirements to prepare
Apple: privacy policy URL, App Privacy "nutrition label", account deletion in-app (present), Sign in with
Apple (present). Google Play: Data safety form, privacy policy URL, account deletion URL/process.
