# Vektolux Test Build (iPhone & Android)

| | |
|---|---|
| App version | 1.0.30 |
| Build number | 31 |
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
- **New in this build (1.0.30): listing review, saved properties, viewing requests, Agent & Car Dealer.**
  - **Listings are reviewed before they go live:** an agent's new listing is *Pending review* until a Vektolux administrator approves it. My Listings shows every status (Active, Pending review, Rejected, Removed, Draft, Unpublished, Archived) with the administrator's reason. The admin dashboard has a new *Listing Review* page (photos, video, details; approve / reject / remove / archive with a required reason) and a *Business Roles* page.
  - **Hearts are saved to your account** (they survive logging out and other phones). *Account → Saved Properties* lists them. Agents see real view, save, inquiry and viewing-request counts.
  - **A free site visit is a request:** the client sends *Request a Viewing*; the agent (or the owner) **accepts or declines with a reason**; the client sees the answer under *Account → My Viewings*. Property owners get *Account → Viewing Requests*.
  - **Real Estate Agent & Car Dealer:** an agent whose separate Car Dealer application is approved keeps the agent workspace and gets an *Auto* section (Add Vehicle, My Vehicles).
  - The fake "Saved addresses" were removed from Account.
  - **All of this needs the newest server changes, which are NOT deployed yet.** Until then these new actions show "available after the next Vektolux server update" or an error.
- Previous build: the complete Real Estate Agent workspace.
  - **Dashboard:** real counts (total, active and unpublished listings, unread client messages, followers, active deals, earnings) and the next viewing. Quick actions: Add Property, My Listings, Messages, Viewings, Notifications. No car posting in the agent workspace.
  - **Add Property with photos AND video:** add several photos (first one is the cover; hold and drag to reorder) and up to 3 short videos (60 s / 50 MB each). Every file uploads to Vektolux storage with a real progress bar; a failed upload shows **Retry** and is never attached. The public location (town/district) and the private verification address + contact phone are separate fields; the private ones are never published.
  - **Messages:** real conversations with clients (each one shows the property: "Interested in: …"), with reply, read status and closing a conversation. Clients can now message a seller from any property page, and find their conversations under *Account → Messages*.
  - **Viewing requests**, **notifications** in tabs (Messages, Viewings, Listings, Deals, Account, Admin), **profile** with bio, followers/following, public profile, earnings & payouts, support and settings.
  - The workspace opens only for accounts the server reports as approved Real Estate Agents. **It needs the newest server changes, which are not deployed yet** (agent status, messaging, property videos). Until the backend is deployed every account sees the normal app, and messaging shows "available after the next Vektolux server update".
- Still included: every screen fits small and large phones (text capped at 115%), the Home and Explore fixes and light mode.
- Sign in with Apple may not work on a free-Apple-ID install: that capability needs a paid Apple Developer account.

Installation through Sideloadly has not been tested by the build pipeline; please report what you see.
