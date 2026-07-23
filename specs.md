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
- **Read-cost design (2026-07)** — 61 users generated ~12k Firestore reads, so the
  free tier was at risk. Root cause: every visible site card opened its own
  `reports` listener (≤20 docs, re-billed per session), pull-to-refresh tore down
  live listeners (full re-read for zero new data), and the admin feed did one site
  `get()` per report. As built now: **one shared `collectionGroup('reports')`
  listener** with `createdAt ≥ now − 10h` feeds every card (time-bounded — a busy
  day can never push a site's reports out of view — with a `limit(500)` guard
  against runaway spam only; newest win); the exact 10h filter stays client-side
  (`reportsWithinWindow`); pull-to-refresh restarts a stream **only after an
  error** (`shouldRestartOnRefresh` — a healthy snapshot listener is never stale);
  the admin feed resolves site names from one cached sites fetch. Rules: the
  collection-group `reports` read was widened from admin-only to public — per-doc
  reads were already public, so nothing new is exposed.

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
own uid); manage their own favourites list. Deletes are disabled for regular
users; **admins may delete sites** (and reports) — see admin site removal below.
**Test mode closed; all four write paths verified live under these rules.**

**Rate limiting (issue #15 redux): LIVE, global per user.** 5 actions (votes +
activity reports combined, across all sites) per 5-minute window, enforced by
a ledger doc at `users/{uid}/limits/actions` (`count`, `windowStart`,
`lastActionAt`) that new clients stamp in the same atomic batch as every
vote/report. The 2026-07-07 rollback happened because the client chose the
window-reset-vs-increment branch with the device clock; the redesign is
**clock-free**: rules judge both shapes purely with `request.time` (increment:
count+1 ≤ 5 inside the window and `windowStart` untouched; reset: a fresh
count-1 window, allowed on create or once the old window expired) and the
client simply tries increment then retries once with reset — two consecutive
denials mean genuinely rate-limited (`RateLimitedException` → "Easy there"
snackbar). **Retrocompat phase 1:** vote/report rules do NOT require the
stamp, so released mobile builds (plain 2-op batches) keep working
unthrottled; a deliberate abuser can mimic that legacy shape until phase 2
flips the rules to require
`getAfter(/users/$(uid)/limits/actions).lastActionAt == request.time` once the
min-version gate has pushed adoption. Legacy `sites/{id}/limits/{uid}` docs
stay frozen (admin read/delete only). Covered by `test/rules/rules_test.mjs`
(run locally via `scripts/test_rules.sh`, and in CI by the `rules-test` job),
pure unit tests (`test/rate_limit_test.dart`), and a device-gated emulator
suite (`test/firebase/firestore_repository_emulator_test.dart`).

**Forced-update gate:** `config/app.minVersion` (Firestore, world-readable,
console-edited only) is watched live; builds below it render a blocking
"Update required" screen (store link / web refresh) — `lib/services/
min_version.dart`, `widgets/force_update_screen.dart`, gated in `app.dart`.
Fails open on missing/malformed config. Limitation: only builds shipping the
gate obey it; older builds are retired by the phase-2 strict rules above.
(iOS App Store URL is a placeholder until the app is listed.)

**Moderation:** community-submitted sites are created pending and stay hidden
(`watchSites` filters `approved == true`) until approved. Approval is **manual
for MVP** — flip `approved` to `true` in the Firebase console. An in-app admin
screen is a follow-up. (Re-seeding a wiped DB is blocked by the strict create
rule — it's an admin op.)

Still owed before scale: an admin/moderation UI, and phase 2 of rate limiting
(strict ledger stamping + App Check) once mobile adoption allows.

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
| Admin site removal (X on site card + warning popup; deletes site + its reports, issue #13) | ✅ Done — `AdminRepository.deleteSite`, rules allow `delete` for admins only |
| Screen stays awake while app is foregrounded, web + native (issue #14) | ✅ Done — `KeepAwakeScope`/`KeepAwake` (`lib/services/keep_awake.dart`); re-acquires on resume; replaced the trip-only wakelock |
| Vote/report rate limiting (issue #15) | ✅ **Done (redux)** — global 5 actions/5 min per user via a clock-free rules ledger (`users/{uid}/limits/actions`, retry-based branch selection); old mobile builds exempt until the phase-2 strict flip; forced-update gate shipped alongside (see rules note above) |
| Admin adds sites pre-approved (issue #16) | ✅ Done — Add Site is role-aware (banner + "Publish site"); `addSite(approved: true)` allowed by rules for admins only |
| Web update banner ("new version — Refresh") | ✅ Done — polls `/version.json` (5 min + on tab refocus) vs baked `appVersion`; Refresh clears SW + caches then reloads (`lib/services/update_checker.dart`, `widgets/update_banner.dart`); no-op on native |
| Alert beep audible over music (issue #18) | ✅ Done — `alertAudioContext()` in `alert_player.dart`: Android alarm stream + transient duck; iOS `playback` category (ignores silent switch) + `duckOthers`; web unaffected |
| Beep fires the moment the driver hits limit+1 km/h (issue #19) | ✅ Done — `shouldAlert`/`isOverLimit` use `>=` (was strict `>`, leaving a dead zone at exactly +1) |
| "Unknown" status when the last report is >10h old (issue #21) | ✅ Done — `SiteStatus.unknown` (grey); `effectiveStatus`/`withEffectiveStatus` in `status_logic.dart` applied in `sitesProvider`; vote buttons come from `SiteStatus.votable` so Unknown is display-only and all three buttons render greyed |
| Speaker toggle mutes the over-limit alarm (issue #22) | ✅ Done — icon top-right of Home; `soundEnabledProvider`, persisted via `TripHistoryStore.saveSoundEnabled`; muting doesn't consume the rising edge, so unmuting mid-breach beeps on the next reading |
| Back-to-top arrow on long lists (issue #25) | ✅ Done — `widgets/back_to_top.dart` overlays a small FAB after 400px of scroll on Home and state detail |
| Bottom-nav oversized padding on iOS (issue #26) | ✅ Done — the shell's `MediaQuery.removePadding` (context outside the Scaffold) re-introduced the notch top inset into the nav bar's internal SafeArea; now strips top+bottom (`ShellBottomBar`), bar lays out at the bare 80pt M3 height |
| Camera Times (Info → top row) | ✅ Done — expected point-to-point travel times between average-speed camera points, from `assets/camera_times.csv` (bundled, build-time data). Pure logic in `lib/services/camera_times.dart` (parse → routes → corridors, slugs, duration formatting; unit-tested). UI: `/info/cameras` lists 8 corridors (city pair + highway variant, forward totals); `/info/cameras/:slug` shows the leg-by-leg times with a direction toggle ("To Melbourne"/"To Sydney"), slow-zone notes and a full-run total. CSV "Segment" column rendered as "From → To". Tap-to-select consecutive legs sums a partial run (`LegRange`/`nextLegSelection`); "Time me" (partial or full run) starts a global session (`cameraTimerProvider`, survives tab changes) counting down to when passing the end camera is legal, with a session average piggybacked on the Home speedometer's GPS odometer (no second GPS stream; hidden when GPS off/reset) |
| Google sign-in popup-blocked fallback | ✅ Done — a blocked popup falls back to `signInWithRedirect`/`linkWithRedirect`; the return leg completes at startup (`AuthController.completeRedirectSignIn`), incl. the link-conflict case; `ensureSignedIn` waits for the restored session first. Web `authDomain` = `roadmate.club` (first-party redirects — Safari/incognito safe; the OAuth redirect URI was added in Google Cloud 2026-07-07). **Installed PWAs skip the popup entirely** and use redirect from the start (`display_mode_web.dart` detects standalone display) — a PWA "popup" is an opener-less custom tab where the Firebase handler hangs blank (Firefox shortcut-app bug, diagnosed from screen recording 2026-07-08) |

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
