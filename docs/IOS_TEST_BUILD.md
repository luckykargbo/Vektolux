# Vektolux Test Build (iPhone & Android)

| | |
|---|---|
| App version | 1.0.28 |
| Build number | 29 |
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

## Install on Android

1. Download **`Vektolux.apk`** from this release's *Assets* section on the Android phone.
2. Open it and allow installing from this source when Android asks (*Install unknown apps*).
3. This is a **test APK signed with a test key**, not a Google Play build. If a different Vektolux build is already installed and Android refuses to update it, uninstall that one first.

## Important for this test

- **Real-money deposits and withdrawals are NOT enabled.** Do not try to pay with real money.
- **Orange Money stays disabled** until Orange provides its webhook documentation.
- Moneroo has been removed from Vektolux.
- This build talks to the live Convex backend (`ideal-poodle-813`). The newest server changes have **not been deployed yet**, so some new actions (for example booking *Confirm completed* / *Report a problem*) can show an error until the backend is deployed. Login, browsing, listings and navigation can be tested normally.
- **New in this build: every screen fits every phone.** All app screens were checked at small Android (320/360pt), iPhone SE, iPhone 15, Pixel and Pro Max sizes with normal and large text, and every layout overflow was fixed. Very large phone font settings are capped at 115% so screens keep their layout. Screens no longer show invented details (for example "Verified Auto Dealer", "Inspected", or made-up mileage and colour on vehicles).
- Also included from the previous build: **the Real Estate Agent workspace** (Home, Listings, Messages, Notifications and Profile tabs; add and manage listings, buyer inquiries, earnings & payouts, followers). It opens only for accounts the server reports as approved Real Estate Agents, and it needs the newest server changes, which are not deployed yet. Until then every account sees the normal app, exactly as before.
- Still included from the previous build: the Home and Explore layout fixes and light mode, so text is readable when the phone is in Dark Mode.
- Sign in with Apple may not work on a free-Apple-ID install: that capability needs a paid Apple Developer account.

Installation through Sideloadly has not been tested by the build pipeline; please report what you see.
