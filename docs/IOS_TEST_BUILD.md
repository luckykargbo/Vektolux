# Vektolux iPhone Test Build

| | |
|---|---|
| App version | 1.0.25 |
| Build number | 26 |
| Bundle ID | `com.vektolux.app` |
| Build type | Release, **unsigned** (built by GitHub Actions on macOS with `flutter build ios --release --no-codesign`) |
| Status | **Test build** for installation on a physical iPhone. Not an App Store / TestFlight build. |

## Install with Sideloadly

1. Download **`Vektolux.ipa`** from this release's *Assets* section.
2. Install **Sideloadly** on your computer (from sideloadly.io) and connect your iPhone with a cable. Tap *Trust* on the iPhone if asked.
3. Open Sideloadly, drag `Vektolux.ipa` into it, select your iPhone, enter your Apple ID, and press **Start**. Sideloadly signs the app with your Apple ID.
4. On the iPhone: *Settings → General → VPN & Device Management* → tap your Apple ID → **Trust**.
   On iOS 16 or later, also turn on *Settings → Privacy & Security → Developer Mode* and restart when asked.
5. Open Vektolux.

With a free Apple ID the app stops opening after 7 days; reinstall it the same way.

## Important for this test

- **Real-money deposits and withdrawals are NOT enabled.** Do not try to pay with real money.
- **Orange Money stays disabled** until Orange provides its webhook documentation.
- Moneroo has been removed from Vektolux.
- This build talks to the live Convex backend (`ideal-poodle-813`). The newest server changes have **not been deployed yet**, so some new actions (for example booking *Confirm completed* / *Report a problem*) can show an error until the backend is deployed. Login, browsing, listings and navigation can be tested normally.
- Sign in with Apple may not work on a free-Apple-ID install: that capability needs a paid Apple Developer account.

Installation through Sideloadly has not been tested by the build pipeline; please report what you see.
