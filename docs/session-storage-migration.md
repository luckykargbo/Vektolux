# Mobile session-token storage: current state and migration design

## Current state (verified in source)
`lib/features/auth/data/repositories/auth_repository_impl.dart` persists the Convex session token
(`vkt_session_token`), user id and a user JSON blob in **SharedPreferences** (plain XML on Android,
NSUserDefaults on iOS). `flutter_secure_storage` is **not** a dependency, and it is not present in the
local pub cache, so it could not be added and verified in this environment.

## Done now (no new dependency)
- `android:allowBackup="false"` / `fullBackupContent="false"`: the token can no longer be copied into
  Auto Backup / device-to-device transfer and restored on another device. (Server sessions are already
  bounded: 30 days users, 8 hours admins; logout revokes server-side.)

## Not done: move the token into platform secure storage
Needs `flutter_secure_storage` (Keychain on iOS, Keystore-backed EncryptedSharedPreferences on Android)
or equivalent, which must be added with network access, then built on real Android/iOS toolchains.

Proposed design (backward compatible, no forced logout):
1. Add a `SessionTokenStore` interface with `read()/write()/clear()`; implement it with secure storage.
2. On app start: read from secure storage; if absent and SharedPreferences has `vkt_session_token`,
   **copy** it to secure storage, verify the copy reads back, then delete the SharedPreferences keys.
   If the secure-storage write fails, keep using SharedPreferences (never log the user out).
3. Keep the user JSON (non-secret profile cache) in SharedPreferences; move only the token.
4. `logout()` clears both stores; server-side revocation is already performed by `auth:logout`.
5. iOS: set Keychain accessibility `first_unlock_this_device` (no iCloud Keychain sync of the token);
   remember Keychain survives uninstall, so clear it on first launch after a fresh install if desired.
6. Tests: migration with/without legacy value, secure-store failure fallback, logout clears both,
   no token ever written to SharedPreferences after migration.

## Decision needed
Whether the app may require re-login if secure storage is unavailable on a device (recommended: no, fall
back to the current behaviour and rely on the short server-side expiry).
