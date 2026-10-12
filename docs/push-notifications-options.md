# Push notifications without Firebase: options (decision needed)

## Current state (verified)
- The mobile app has **no push client**: `lib/core/services/notification_service.dart` only shows local
  notifications and in-app items, and nothing in the app registers a device token
  (`user_fcm_tokens` is never written by the app).
- The admin dashboard used `firebase-admin` (FCM) to "send" push; with no tokens and no FCM client in the
  app, that could never reach a device. The send route/UI now only create **in-app** announcements and
  say so; `src/lib/firebase-admin.ts` is removed.
- `firebase-admin` is still listed in `admin-dashboard/package.json` because the lockfile cannot be
  regenerated offline: run `npm uninstall firebase-admin` in `admin-dashboard/` (needs network) and commit
  the updated `package-lock.json`.

## Constraint
Project rule: Flutter + Convex, **no Firebase**. On Android, a push that reaches a closed app normally
means FCM (Google Play services); on iOS it means APNs. "No Firebase" therefore has a real cost on Android.

## Options (none chosen here; no provider is selected on your behalf)
| Option | Android closed-app delivery | iOS | Cost / ops | Notes |
|---|---|---|---|---|
| A. In-app only (current) | No | No | none | Honest and shippable; users see announcements when they open the app. |
| B. APNs direct (iOS) + FCM HTTP v1 *without the Firebase SDK* (Android) | Yes | Yes | Google Cloud project for FCM credentials; no Firebase SDK in the app | Still uses Google's FCM service, only not the "Firebase" client SDK. Needs your decision whether that satisfies the rule. |
| C. Third-party push service (OneSignal, Pusher Beams, Expo, etc.) | Yes | Yes | Paid tiers; data leaves your stack | Most of them wrap FCM/APNs; adds a vendor and privacy review. |
| D. Self-hosted UnifiedPush / ntfy | Android users who install a distributor | No (iOS) | You run a server | Poor fit for a mass-market Sierra Leone audience. |
| E. SMS / WhatsApp for critical alerts (payments, escrow) | n/a | n/a | per-message cost | Complements A for the few alerts that must not be missed. |

## Recommendation
Ship **A** now. For payment/escrow alerts that must reach people, add **E** (you already have SMS/WhatsApp
touchpoints). Decide on **B or C** only after the owner confirms whether FCM-without-SDK is acceptable.

## If B or C is chosen later (work list)
Add a device-token registration mutation (authenticated, per device, revoked on logout and on account
deletion — `accountDeletion.ts` already deletes `user_fcm_tokens`), a server-side sender behind a Convex
action with per-user rate limits, notification preferences, and tests that never call the live provider.
