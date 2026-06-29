# RoadMate AU — Spec & As-Built Record

> Originally a brief MVP requirements doc. Updated 2026-06-29 to reflect what was
> actually built. The original functional/UI requirements are preserved at the
> bottom for reference.

## What it is

**RoadMate AU** — "Know before you roll." A community-powered app for Australian
heavy-vehicle drivers to see and share the **live status** of NHVR inspection /
compliance sites (weighbridges, checking stations, HV safety stations, inspection
sites). Dark, iOS-directory-style UI.

Single **Flutter** codebase targeting **iOS, Android, and web**. Backend is
**Firebase** (project `roadmate-b1551`).

## Key decisions & rationale

- **Flutter** — one codebase ships iOS + Android + web simultaneously. Trade-off
  accepted: Flutter web is CanvasKit-rendered (weaker SEO, async font load → brief
  emoji "tofu" on first paint). The original non-coder prototype was Expo/React
  Native on Replit; **no code was reusable** — this is a rebuild from the design.
- **Firebase over Cloudflare** — the owner initially leaned Cloudflare, but Firebase
  won for: first-class Flutter SDK (FlutterFire), built-in **anonymous auth**,
  realtime Firestore, and Hosting — fastest path, and small traffic fits the free
  tier. (Cloudflare would have meant hand-building auth + a REST API.)
- **Anonymous auth, no login wall** — lowest friction for "report quickly" usage;
  votes/saves/submissions are keyed by the anonymous uid.
- **Build the richer product** — implemented the community live-status app from the
  **screenshots/screen-recording** (voting, Nearby, Saved, BLITZ banner), not the
  thinner written brief; replaced "mock JSON" with the **real NHVR dataset** in
  Firestore.
- **`SiteRepository` abstraction** — one interface, a Firestore impl and a bundled-
  seed impl. Lets the app run offline/in-dev and keeps unit tests Firebase-free; the
  Firestore swap is a single line in `providers.dart`.
- **Status model** — displayed status = the most recent report within a 6 h window
  (pure, unit-tested in `status_logic.dart`).
- **Security posture** — anonymous **but validated** writes (a vote must bump exactly
  one counter by +1, fields locked); community **Add Site → pending** (moderated).
- **Coordinates** — absent from source NHVR data, **geocoded via OSM Nominatim**
  (town-level, approximate).
- **iOS uses Swift Package Manager** for Firebase (not CocoaPods). The `ios` block in
  `firebase_options.dart` is **hand-written from `GoogleService-Info.plist`** to
  bypass the FlutterFire CLI's broken `xcodeproj`-gem step on system Ruby 2.6; since
  init passes explicit options, the bundled plist isn't strictly required.
- **Riverpod 3** (manual providers, no codegen) + **go_router** (`StatefulShellRoute`).

## Architecture (as built)

- **Flutter** + Material 3 dark theme · **Riverpod 3** state · **go_router** nav.
- **Firebase**: Cloud Firestore (data), Firebase Auth **Anonymous** (device-based
  identity — no login wall), Firebase Hosting (web — **deployed live**).
- All data access goes through the **`SiteRepository`** interface
  (`lib/services/`). Production uses `FirestoreSiteRepository`; a
  `LocalSeedSiteRepository` (bundled asset) remains for offline/dev/tests. Swap
  point: `siteRepositoryProvider` in `lib/services/providers.dart`.
- Pure, unit-tested logic kept Firebase-free: `status_logic.dart`,
  `site_stats.dart`, `geo.dart` (haversine), seed parsing.
- **30 unit/widget tests**; `flutter analyze` clean.

### Firestore data model
- `sites/{siteId}`: name, type, state, suburb, address, lat, lng, direction,
  note, currentStatus, openVotes/blitzVotes/closedVotes, lastReportAt, approved,
  createdBy.
- `sites/{siteId}/reports/{reportId}`: status vote and/or activityNote, uid,
  createdAt.
- `users/{uid}/favourites/{siteId}`: a user's favourite sites (private to their uid).

### Security rules (`firestore.rules` — DEPLOYED & HARDENED)
Anonymous users may: read sites/reports; cast **validated** status votes (a vote
must bump exactly one counter by +1, counters can't decrease, currentStatus must
be a valid value, no other fields change); post activity reports (uid/createdAt
validated); submit new sites **as pending** (`approved == false`, `createdBy` =
own uid); manage their own favourites list. Deletes disabled. **Test mode closed; all
four write paths verified live under these rules.**

**Moderation:** community-submitted sites are created pending and stay hidden
(`watchSites` filters `approved == true`) until approved. Approval is **manual
for MVP** — flip `approved` to `true` in the Firebase console. An in-app admin
screen is a follow-up. (Re-seeding a wiped DB is blocked by the strict create
rule — it's an admin op.)

Still owed before scale: per-user rate-limiting and an admin/moderation UI.

## Data source

Authoritative NHVR site list: `sites/nhvr_national_inspection_sites.json`
(24 real sites — NSW 13, QLD 3, VIC 3, SA 2, TAS 3; WA & NT are non-participating
jurisdictions). Seeded into Firestore on first run.

**Coordinates** were not in the source data; they were **geocoded (town/locality
level) via OpenStreetMap Nominatim** and merged into the dataset + Firestore.
They are approximate — verify exact site positions before production.

## Feature status

| Feature | Status |
|---|---|
| Home: stats bar (Open/Blitz/Closed, tappable) | ✅ Done |
| Browse by State (cards, counts, blitz badge) | ✅ Done |
| State detail: site list + search | ✅ Done |
| Site card: type chip, direction tag, GVM/notes, status badge | ✅ Done |
| Community status voting (OPEN/BLITZ/CLOSE) → Firestore, live | ✅ Done & verified |
| Report activity (free-text) | ✅ Done |
| "BLITZ DETECTED" banner | ✅ Done & verified |
| Recently Active list | ✅ Done |
| Favourites (star) — synced per anon uid | ✅ Done & verified |
| Add Site (submission form) → pending moderation | ✅ Done & verified |
| Nearby (distance-ranked) | ⚙️ Built + unit-tested; **coords geocoded & verified in-bounds**. End-to-end pending real-device geolocation permission (not grantable in automated browser) |
| iOS build | ✅ **Done & verified** — builds via Swift Package Manager (Firebase), runs on the iOS 26.5 Simulator; Firebase anon auth + Firestore reads live. Deployment target 15.0; location permission in `Info.plist`. Real-device signing still needed for App Store. |
| Web public deploy (Firebase Hosting) | ✅ **LIVE — https://roadmate-b1551.web.app** |

## Deployment & domain

- **Live web app:** https://roadmate-b1551.web.app (Firebase Hosting). Deploy with
  `firebase deploy --only hosting --project roadmate-b1551` (build `flutter build web`
  first; config in `firebase.json`).
- **Custom domain:** `roadmate.club` (registrar **Namecheap**, default BasicDNS).
  Connected via the modern Firebase single-A-record method:
  - `A` · host `@` · `199.36.158.100`  (Firebase Hosting IP)
  - `TXT` · host `@` · `hosting-site=roadmate-b1551`  (Firebase site verification)
  - `www` (optional): `CNAME` · host `www` · `roadmate-b1551.web.app` — and add
    `www.roadmate.club` as a custom domain in the console so SSL is issued.
  - Firebase auto-provisions the Let's Encrypt cert after verification (~15 min–few h).
- **Rules deploy:** `firebase deploy --only firestore:rules --project roadmate-b1551`.

## Hard constraints (still in force)
- **Commits attributed to the owner only** — no `Co-Authored-By: Claude` trailer.
- **Every feature ships with a unit test.**

## Known follow-ups (remaining)
1. **Rate-limiting & moderation UI** — rules block counter tampering, but a user can
   still spam +1 votes; Add Site submissions are pending-only with **manual** console
   approval (no in-app admin screen yet). Needs Cloud Functions for rate-limiting and
   an approval flow.
2. **Coordinates** — geocoded at town/locality level (verified in-bounds); refine to
   exact site positions and test **Nearby** end-to-end on a real device (geolocation
   permission can't be granted in the automated browser).
3. **iOS release** — runs on the Simulator; still needs Apple Developer signing,
   bundle-id provisioning, and App Store setup for distribution.
4. **Optional later:** FCM push for blitz alerts; an admin/moderation console.

---

## Original MVP requirements (preserved)

Build a modern mobile-first web app (dark mode UI) that lists all NHVR (National
Heavy Vehicle Regulator) sites across Australia.

Core: Home with "NHVR Sites" title, subtitle, search bar; states as clickable
cards (VIC, NSW, QLD, SA, WA, NT, TAS); each state opens a list of sites showing
name, address, type (Inspection / Weighbridge / Compliance) and a status
indicator. UI: dark theme, rounded cards, minimalist icons/emojis, status badges.
Extras: Add Site, Favourites, Reports, bottom navigation. Stack: Flutter, mock
JSON data, commits attributing the owner only, generated unit tests.

> Note: the as-built app follows the richer **screenshots/screen-recording**
> (community live-status voting, Nearby, Saved) rather than the simpler text
> above, and replaced "mock JSON only" with Firestore backed by the real NHVR
> dataset — per decisions agreed during the build.
