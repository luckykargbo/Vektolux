# Security: what is fixed in the working tree, and what still needs a decision

Fixed in code (with tests): Orange webhook accepts only a body HMAC and credits only verified phones;
eIDV webhook validates every field and never defaults a missing score to a pass; TOTP secrets need
TOTP_ENCRYPTION_KEY; 2FA management needs password + current code; social sign-in for 2FA accounts uses a
single-use challenge (mobile code-entry screen exists); wallet PIN hash is salted PBKDF2 with legacy upgrade
and the PIN pre-check queries are no longer oracles; login throttling no longer locks the dashboard's
shared IP and now covers ordinary accounts per (identifier, address); registration/email-send budgets;
email HTML escaping; OAuth challenge budget per address; escrow bank details come from owner config.

Still open / needs a decision:
1. **Phone ownership flow.** Nothing proves a customer owns their phone, so carrier (Orange) deposits stay
   held. Needs an OTP (SMS/WhatsApp/USSD) provider choice and UX. Until then use the manual path in
   operations-runbook.md.
2. **Orange Money signature scheme.** Needs Orange's written webhook specification.
3. **Distributed password guessing.** Ordinary accounts are throttled per address, not locked account-wide
   (to avoid letting strangers lock customers out). A botnet can still try ~10 guesses/15 min/address.
   Options: CAPTCHA / proof-of-work after N failures, device binding, breached-password check.
4. **Secure token storage on mobile** (needs flutter_secure_storage; see session-storage-migration.md).
5. **PIN strength.** A 4-6 digit PIN is brute-forceable offline from a database copy whatever the hash;
   protect with the server lockout (done) and consider a server-side pepper (env secret) — rotation plan needed.
6. **Google sign-in has no per-attempt nonce** (SDK limitation, documented in `users.ts`).
7. **Peer-to-peer transfers resolve a recipient by phone/email the sender typed**; the sender sees the
   recipient's name before confirming. A squatter could still receive money meant for someone else if the
   sender does not check the name. Consider showing "verified phone" on the recipient.
8. **Old USSD phone-login actions** (`payments.sendUssdOtp/verifyUssdOtp`) are internal and unused; they now
   refuse admin/2FA accounts. Consider deleting them.
