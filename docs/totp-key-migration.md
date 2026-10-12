# TOTP encryption key: compatibility and recovery plan

Status: written for the owner. Nothing here has been run against any deployment.

## Background

Earlier code (`convex/lib/totp.ts`, commit `4fa5c9d`, 2026-10-11) encrypted admin 2FA secrets with
`TOTP_ENCRYPTION_KEY`, and **silently fell back to a constant committed to the repository** when the
variable was unset. The fix removes that fallback: with no valid key, 2FA enrolment, verification
and 2FA login all fail closed (the key must be a unique secret of at least 32 characters).

## Could the live deployment already hold secrets encrypted with the fallback?

Evidence available from the repository only (no deployment access was used):

| Evidence | Finding |
|---|---|
| `git log` for `convex/lib/totp.ts` | Introduced in `4fa5c9d` on 2026-10-11, only on `prod-readiness`; not in `main` (`f2d0adf`). |
| `main:convex/schema.ts` | Contains **no** `totp*` fields. Nothing deployed from `main` can store a TOTP secret. |
| `README.md` §3 "Current production state" | Deployed code is `4c3ae01` (as of 2026-10-05), which **predates** the TOTP commit. |
| `README.md` §4 | Lists the env var names set on `ideal-poodle-813`; `TOTP_ENCRYPTION_KEY` is not among them. |
| TOTP mutations (`setupTotp` / `enableTotp` / `disableTotp`) | Have **no callers** in the app, the dashboard or the bot, so no UI enrols 2FA even if the code were deployed. |

Conclusion: **very likely no TOTP secrets exist anywhere**, because the code that writes them has
never been part of the deployed release. This cannot be *proven* from the repository: the README is
dated 2026-10-05 and a deploy since then (`npx convex dev --once` from this branch) would not be
visible in git.

## Owner checks before deploying (all read-only, run by the owner)

1. `npx convex env list` (names only) — confirm whether `TOTP_ENCRYPTION_KEY` exists. Do **not** print values.
2. In the Convex dashboard data view, filter `users` for `totpEnabled == true` or a present
   `totpSecretEncrypted`. If the table has no such fields/values, there is nothing to migrate.

## Decision table

| `TOTP_ENCRYPTION_KEY` set? | Any user with `totpSecretEncrypted`? | Action |
|---|---|---|
| any | **No** | Nothing to migrate. Set a fresh key (`openssl rand -base64 48`) before enabling 2FA enrolment. |
| **Yes** (unique, >= 32 chars) | Yes | Secrets were encrypted with that key: they keep working. Do not change the key. |
| **No** | Yes | Those secrets were encrypted with the **public** fallback key and must be treated as exposed. Follow the recovery below. |

## Recovery when secrets were encrypted with the public fallback

No automatic migration is shipped on purpose: re-encrypting would need the old public key in code
again, and the secrets themselves are compromised anyway (anyone with read access to the table or a
backup could decrypt them).

1. Set a new `TOTP_ENCRYPTION_KEY` on the approved deployment (`npx convex env set`, owner only).
2. For each affected admin, in the Convex dashboard clear `totpEnabled`, `totpSecretEncrypted`,
   `totpPendingSecretEncrypted`, `totpBackupCodesHashed`, `totpPendingBackupCodesHashed`
   (owner-approved data edit; the CLI-only operator recovery command is documented in README, "Admin account recovery (operator only)").
3. The admin signs in with password only, then re-enrols through `setupTotp` -> `enableTotp`,
   which now requires the password and stores only server-generated backup-code hashes.
4. Rotate the affected admins' passwords and invalidate their sessions (set `sessionToken` empty).

Until step 2 is done, an affected admin cannot complete 2FA login (fail closed). The password reset
and CLI recovery paths remain available, so no admin is locked out permanently.

## What not to do

- Do not set `TOTP_ENCRYPTION_KEY` to the old fallback string: it is rejected by design.
- Do not rotate the key after admins have enrolled without re-enrolling them.
