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
- **Anonymous auth, no login wall to *use* the app** — lowest friction for "report
  quickly" usage; saves/submissions/trips are keyed by the anonymous uid. **Since
  0.1.55 posting is the exception:** activity reports and status votes require a
  linked Google/Apple account, because an anonymous identity is free and unlimited
  (a banned spammer just reinstalls). Signing in *links* the provider onto the
  existing anonymous uid, so nobody loses favourites, trips or report history.
  Browsing, search, Nearby, favourites and Add Site stay account-free.
- **Build the richer product** — implemented the community live-status app from the
  **screenshots/screen-recording** (voting, Nearby, Saved, BLITZ banner), not the
  thinner written brief; replaced "mock JSON" with the **real NHVR dataset** in
  Firestore.
- **`SiteRepository` abstraction** — one interface, a Firestore impl and a bundled-
  seed impl. Lets the app run offline/in-dev and keeps unit tests Firebase-free; the
  Firestore swap is a single line in `providers.dart`.
- **Status model** — displayed status = the most recent report within a 6 h window
  (pure, unit-tested in `status_logic.dart`).
- **Security posture** — **validated** writes (a vote must bump exactly
  one counter by +1, fields locked); community **Add Site → pending** (moderated);
  posting reports/votes needs a real account (see above).
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
- **Trip time is wall-clock time (2026-07, from a 0.1.47 iOS report)** — the Trip
  Logger's ELAPSED readout was derived from GPS *sample* time (last fix − first
  fix) and only repainted when a fix arrived. Recorded indoors, where no fix ever
  landed, it sat frozen on "0m 0s" for the whole trip. Now the running card ticks
  once a second off `clock.now() − tripStartedAt`, and `stopAndSave` stores that
  same wall-clock duration (and averages the distance over it) so the saved tile
  agrees with what the driver watched. Time is read through `package:clock` so
  the ticker is testable without waiting in real time. Related: the status line
  no longer shows a green "GPS active" merely because the stream was subscribed —
  `GpsSignal` (`lib/services/gps_signal.dart`) distinguishes *waiting for a first
  fix* (amber) and *stream errored* (red), so a still speedometer explains itself
  instead of looking broken.
- **Releases ship from GitHub, never the terminal (2026-08-24)** — a push to
  master IS the web release: the **Web Release** pipeline runs three parallel
  gates — CodeQL, Flutter CI, Visual Verification (ex "Nightly Visual
  Verification"; per-push now, so its cron + skip gate died) — and only a fully
  green chain deploys hosting + rules + indexes. Store builds moved to a
  **manual `workflow_dispatch`** (Mobile Release) whose preflight refuses any
  commit without a green Web Release: mobile follows a positive web release.
  CodeQL stays on GitHub's **default setup** (the org's security configuration
  keeps it on, and an advanced-setup workflow's SARIF uploads conflict with
  it), so the pipeline binds it in by polling for the commit's
  `dynamic/github-code-scanning/*` workflow run rather than `needs:` (NOT by
  check-run app: default setup's check runs report under plain
  `github-actions`, which is indistinguishable from our own jobs).
  A dispatch button was chosen over an auto-queued environment approval so
  ordinary pushes leave no pending-deployment nag — releases stay web-only by
  default. Details under **Deployment & domain → Release pipeline**.

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
  createdAt; activity reports from 0.1.59 also carry `reporterLevel` (the
  author's participation-ladder index, denormalized at write time so report
  rows show a level icon with zero extra reads — optional, old clients' docs
  simply don't have it).
- `users/{uid}/favourites/{siteId}`: a user's favourite sites (private to their uid).
- `users/{uid}/stats/participation`: the raw participation counters
  (`votes`, `reports`, `sitesAdded`, + server-stamped `updatedAt`), bumped by
  exactly one in the same batch as every vote/report/site submission.
  `sitesAdded` (0.1.60) is credited at **submission** time — deliberately not
  at approval, which can also happen straight in the Firebase console where
  no client code runs — and feeds the Trailblazer badge only (no points);
  the rules read it with `get()` defaults so 0.1.59 docs/writes without the
  key keep passing. Points (`votes*5 + reports*10`), the 6-rung level ladder
  (Rookie → Outback Legend) and all badges are **computed client-side**
  (`lib/services/participation_logic.dart`) — no stored points, so rules
  never validate arithmetic and rebalancing is a client release.
  Anti-cheat is deliberately soft (owner-only, +1-per-write, banned users
  refused); a scripted +1 earns no faster than scripted real votes, which the
  ledger caps. Anonymous users lose their points if the app is reinstalled
  (anon uid lost); signing in preserves them.
- `usernames/{key}` (0.1.61, road names): the uniqueness claim for a public
  road name — the doc id is the lowercased name (so "Dusty Nomad" and "DUSTY
  NOMAD" collide), holding `{uid, username (display casing), createdAt}`.
  Claiming is create-if-free: a second create of the same key arrives as an
  update and dies on the rules' owner check — that *is* the uniqueness
  guarantee. The display-cased name is denormalized onto
  `users/{uid}.username` in the same transaction
  (`lib/services/username_store.dart`); renames delete the old claim in that
  transaction, and account deletion best-effort-releases the claim *outside*
  the deletion batch (a broken claim must never block App Store 5.1.1(v)).
- `users/{uid}`: profile sync (email/displayName/photoUrl/isAnonymous/
  lastSeenAt) — now also `username` (optional, 3–30 chars). Anonymous users
  write this doc too since 0.1.61 (their road name is its only content).
- `announcements/current`: the one admin broadcast every client bands across the
  top of the app (see **Admin broadcast** below).

### Security rules (`firestore.rules` — DEPLOYED & HARDENED)
Signed-in users (anonymous or federated) may: read sites/reports; cast
**validated** status votes (a vote must bump exactly one counter by +1, counters
can't decrease, currentStatus must be a valid value, no other fields change);
post activity reports (uid/createdAt validated); submit new sites **as pending**
(`approved == false`, `createdBy` = own uid); manage their own favourites list.
Deletes are disabled for regular users; **admins may delete sites** (and reports)
— see admin site removal below. **Test mode closed; all four write paths verified
live under these rules.**

**Proximity-gated posting (trust control): client-side, from 0.1.57.** Posting
is **account-free again** — the 0.1.55 sign-in gate lasted one release. The
owner's call (2026-08-03): reports are trusted because they come from someone
who can see the site, so the gate is **distance, not identity**: votes and
activity reports are accepted only within **3 km** of the site — deliberately
the same `proximityRadiusKm` at which the approach prompt starts asking
"what's the status?", so the app never asks for an answer it would then
refuse (`reportRadiusKm` in `lib/services/report_proximity.dart` is
compile-time locked to it, and a unit test pins the equality).
`checkReportProximity` (pure, Flutter/Firebase-free) is the rule;
`FirestoreSiteRepository.vote/report` is the single enforcement point —
`SiteRepository.vote/report` now take the whole `Site` so the gate can measure
against its coordinates — and throws `TooFarException` or
`LocationRequiredException`, which every UI path turns into an explanatory
snack. **Admins are exempt (0.1.58): only moderators may post remotely** —
correcting a stale status can't wait for a site visit, and their named
accounts stay on the audit trail. The exemption is `enforceReportProximity`
(pure, unit-tested), and the `userRoles/{uid}` read that feeds `isAdmin` is
paid **only after a refusal** (the `_activeBan` discipline), so an ordinary
post near a site costs no extra read and an admin's remote one costs exactly
one; no rules change (a user may already read their own `userRoles` doc). The device fix comes from `LocationSource.currentPosition()` (one-shot,
15 s-bounded `quickFix` lookup that first runs the permission ask — so "turn on
location" is prompted by the OS at the moment of posting; the trip stream stays
the app's only `getPositionStream`). Deliberate carve-outs: an **un-geocoded
site is always reportable** (nothing to measure against — the position lookup
is skipped entirely so nobody is asked for location the check can't use), and
the approach prompt/notification answers pass by construction (GPS put the
truck in range). Browsing, Nearby, favourites and Add Site remain account-free
and ungated as before. The check is **client-side only** — rules cannot verify
a GPS fix — which also means shipped 0.1.55/0.1.56 mobile builds simply keep
their old client-side sign-in gate until updated, and pre-0.1.55 builds keep
posting from anywhere; both write shapes stay accepted. The sign-in machinery
this replaced (`report_eligibility.dart`, `sign_in_required_sheet.dart`,
`mayPostReports`) is **deleted**, and the never-deployed `isRegistered()`
rules hardening (with its minVersion-then-rules phased rollout, recorded in
git history at 0.1.55) is **permanently shelved** — do not deploy it, or
anonymous posting breaks again. Covered by `test/report_proximity_test.dart`,
the proximity-gate group in `test/site_card_test.dart`, and the anonymous
voting tests in `test/proximity_prompt_test.dart`.

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
stay frozen (admin read/delete only). **Admins are exempt from the cap** —
their ledger accepts any stamp (`|| isAdmin()`, last in the `||` chain so an
ordinary in-window action never pays for the `userRoles` lookup), so
moderating a blitz can be a burst of votes/reports. The exemption is
server-side only, which means it also reaches already-shipped mobile builds.
Covered by `test/rules/rules_test.mjs`
(run locally via `scripts/test_rules.sh`, and in CI by the `rules-test` job),
pure unit tests (`test/rate_limit_test.dart`), and a device-gated emulator
suite (`test/firebase/firestore_repository_emulator_test.dart`).

**Bans (spam control): LIVE, admin-issued, server-enforced.** An admin bans a
uid by writing `bans/{uid}` — **1 day** (`until` timestamp) or **forever** (no
`until` field at all). While the ban is active the rules refuse **every write**
from that uid: votes, activity reports, new sites, adding a favourite, even the
profile sync. Reads are untouched — a banned spammer keeps the map, the
speedo and their trips, they just can't post. Two carve-outs are deliberate:
**removing** a favourite and **deleting your own account** stay allowed, so
nobody is trapped with content they can't clear and App Store 5.1.1(v) keeps
working. A missing/malformed `until` reads as permanent — a half-written ban
must **fail closed**. Enforcement is one `get()` per write (never `exists()` +
`get()`, which would bill two) and only on write paths, so the listener read
budget is untouched; `isAdmin()` is evaluated first wherever it appears, so a
moderator's own writes never pay for the lookup. **Retrocompat:** nothing
changes for unbanned users, so already-shipped mobile builds are unaffected;
a banned old client simply sees its generic "Could not submit" error, while
new clients read `bans/{uid}` on the denial path (one read, failure only) and
show the real reason — "Your account is suspended until 30 Jul 2026, 2:15 pm"
(`BannedException`, `lib/services/ban_logic.dart`). Admin UI: a **Ban this
user** action on every report card in the Reports/Activity tabs (needs the
report's uid) and a **Bans** tab listing every ban — active or lapsed, since a
served 1-day ban is the evidence for handing out a permanent one — each with a
one-tap **Lift ban**. Covered by `test/ban_logic_test.dart`,
`test/admin_bans_test.dart` and the ban section of `test/rules/rules_test.mjs`.

**Bulk report purge (spam cleanup): LIVE on web only, from 0.1.56.** A ban stops
the *next* report but leaves everything already posted sitting on the map, so
**Remove this user's reports** on any report card wipes every report and status
vote that uid posted in the last **10 hours** (`purgeWindow`, deliberately equal
to `statusFreshWindow` — older reports are already invisible to drivers and are
kept as history). Confirmed by a dialog; irreversible. **Web only** by
`showBulkReportPurge(isWeb:)` (`lib/services/report_purge.dart`, surfaced via
`isWebProvider`): it is the most destructive tool in the admin surface and web
is the build that can be rolled back in minutes, whereas a shipped Android/iOS
binary sits on phones for months. Banning and single-report removal stay on
every platform. Implementation: `AdminRepository.deleteRecentReportsByUser`
runs **one uid-filtered `collectionGroup('reports')` query** (so a purge costs
one read per report actually removed, not a scan of every recent report in the
country — needs the new `reports` COLLECTION_GROUP index on `uid`+`createdAt`),
groups the hits by site, and per site rewrites the denormalised
`openVotes`/`blitzVotes`/`closedVotes`/`currentStatus`/`lastReportAt` from the
survivors. Tallies are written as **absolute values, never decrements**, so a
retry after a partial failure still lands on the right numbers; deletes are
chunked below the 500-op batch limit with the recount riding in the final batch,
so counters can never drop before the reports they count. The recount is shared
with the existing single-report `deleteReport` (`talliesFrom`). **No rules
change was needed** — `allow delete: if isAdmin()` on
`sites/{id}/reports/{id}` and the world-readable collection-group match already
covered it, so shipped mobile clients are untouched. Covered by
`test/report_purge_test.dart`, `test/admin_purge_reports_test.dart` and three
new checks in `test/rules/rules_test.mjs` (the uid-filtered query, the
batch purge + recount, and a non-admin being refused a report delete — the
admin report-delete path had no rules coverage before).

**Forced-update gate:** `config/app.minVersion` (Firestore, world-readable,
console-edited only) is watched live; builds below it render a blocking
"Update required" screen (store link / web refresh) — `lib/services/
min_version.dart`, `widgets/force_update_screen.dart`, gated in `app.dart`.
Fails open on missing/malformed config. Limitation: only builds shipping the
gate obey it (**0.1.32+**); older builds are retired by the phase-2 strict rules
above. **`config/app` does not exist yet** — verified 2026-07-30 against the REST
API (404) — so the gate has never fired for anyone. (It was to be armed as step
2 of the 0.1.55 signed-in-posting rollout, which the 0.1.57 proximity gate
above made moot.)
(iOS App Store URL is a placeholder until the app is listed.)

**Admin broadcast (`announcements/current`): LIVE as of 0.1.55.** One
world-readable, admin-written document carrying `message` (≤280 chars, matching
`kAnnouncementMaxLength`), `severity` (`info`/`warning`), server-stamped
`publishedAt`/`publishedBy` and an optional `expiresAt`; validated by
`isValidAnnouncement()` on the same discipline as `isValidBan()`. Every client
holds **one document listener** (`announcementProvider` — the cheapest read shape
there is, deliberately not a query) and `AnnouncementGate` bands the message
across the top of every screen from the `MaterialApp.router` builder, beside
`UpdateGate`. Dismissal is per-device (`SharedPreferences`, keyed on
`publishedAt`), so editing a notice re-shows it to people who had closed the old
one; clearing is an admin delete. Published from the admin **Notice** tab
(`NoticeTab`, `admin_repository.publishAnnouncement/clearAnnouncement`).
Pure logic + expiry in `lib/services/announcement.dart`; covered by
`test/announcement_test.dart`, `test/announcement_banner_test.dart`,
`test/admin_broadcast_test.dart` and the announcement checks in
`test/rules/rules_test.mjs`. **Reach:** in-app only — there is no push channel
(`flutter_local_notifications` is device-local, for the approach prompt; no
`firebase_messaging`), so a notice is seen next time someone opens the app, and
builds older than 0.1.55 have no listener and never show one at all. Fully
additive, so those old builds are otherwise unaffected.

**Rich notices (0.1.70+): links, formatting and colour.** Two additive optional
fields on the same doc: `messageHtml` (≤480 chars, `kAnnouncementHtmlMaxLength`
— the extra room pays for tags) and `color` (`#RRGGBB` background override;
foreground auto-picks black/white by luminance, `prefersDarkForeground`).
`messageHtml` accepts a **safe HTML subset only** — `<b>/<strong>`, `<i>/<em>`,
`<u>`, `<br>`, `<a href="https://…">` (http/https only; `javascript:`/`mailto:`
etc. are refused) and `<font color="#RRGGBB">`; entities `&amp; &lt; &gt;
&quot; &#39; &apos; &nbsp;`. Parsing lives Flutter-free in
`lib/services/notice_markup.dart` (hand-rolled scanner → flat `NoticeSpan`s;
unknown tags stripped, their text kept), rendered by `AnnouncementBanner` as
tappable spans (`url_launcher`, external browser; tests inject `onOpenLink`).
The admin form is one field that takes markup directly, with preset swatches +
custom hex and a live draft preview; on publish it always writes the plain-text
rendering to `message` (via `plainTextOfNotice`) so the two fields tell the same
story, and a notice with no markup writes the exact pre-rich shape.
**Retrocompat:** `message` stays required (≤280) — 0.1.55–0.1.67 mobile builds
render it verbatim, with no formatting, links or colour; they must never be
shown raw tags. Parser + colour logic in `test/notice_markup_test.dart`.

**Rate notices (0.1.74+): the store-rating CTA.** A third additive optional
field on the same doc: `cta` — a string with `'rate'` as its only value so far
(`kAnnouncementCtaRate`; a string, not a bool, so later CTAs stay additive like
severity levels, and an unknown value renders as a plain notice). A rate notice
grows a specialised **"Rate RoadMate"** button in the banner that opens the
platform's own store: Google Play on Android, the App Store **rating sheet** on
iOS (`?action=write-review`) — `rateUrlFor` in `lib/services/min_version.dart`
beside the store URLs it reuses. On platforms with nothing to rate (**web**,
desktop) `rateUrlFor` is null and `AnnouncementGate` hides a rate notice
**entirely** — web users receive nothing, by design. The admin Notice tab has an
"Ask users to rate the app" toggle that seeds an empty message box with the
plea ("Enjoy the app? Would you mind rating us?") without overwriting typed
text; both previews pass a stand-in URL so the button stays visible while
composing on web. **Retrocompat:** mobile builds 0.1.55–0.1.73 show just the
`message` text, without the button, and pre-0.1.55 builds nothing — the button
reaches users only from builds that ship it (the owner's iOS 0.1.73 was cut
just before this landed, so on mobile the button starts at 0.1.74). Covered across
`test/store_links_test.dart`, `test/announcement_test.dart`,
`test/announcement_banner_test.dart`, `test/admin_broadcast_test.dart` and the
`cta` checks in `test/rules/rules_test.mjs`.

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
| Vote/report rate limiting (issue #15) | ✅ **Done (redux)** — global 5 actions/5 min per user via a clock-free rules ledger (`users/{uid}/limits/actions`, retry-based branch selection); admins exempt entirely, and old mobile builds exempt until the phase-2 strict flip; forced-update gate shipped alongside (see rules note above) |
| Admin adds sites pre-approved (issue #16) | ✅ Done — Add Site is role-aware (banner + "Publish site"); `addSite(approved: true)` allowed by rules for admins only |
| Web update banner ("new version — Refresh") | ✅ Done — polls `/version.json` (5 min + on tab refocus) vs baked `appVersion`; Refresh clears SW + caches then reloads (`lib/services/update_checker.dart`, `widgets/update_banner.dart`); no-op on native |
| Alert beep audible over music (issue #18) | ✅ Done — `alertAudioContext()` in `alert_player.dart`: Android alarm stream + transient duck; iOS `playback` category (ignores silent switch) + `duckOthers`; web unaffected |
| Beep fires the moment the driver hits limit+1 km/h (issue #19) | ✅ Done — `shouldAlert`/`isOverLimit` use `>=` (was strict `>`, leaving a dead zone at exactly +1) |
| "Unknown" status when the last report is >10h old (issue #21) | ✅ Done — `SiteStatus.unknown` (grey); `effectiveStatus`/`withEffectiveStatus` in `status_logic.dart` applied in `sitesProvider`; vote buttons come from `SiteStatus.votable` so Unknown is display-only and all three buttons render greyed |
| Speaker toggle mutes the over-limit alarm (issue #22) | ✅ Done — icon top-right of Home; `soundEnabledProvider`, persisted via `TripHistoryStore.saveSoundEnabled`; muting doesn't consume the rising edge, so unmuting mid-breach beeps on the next reading |
| Back-to-top arrow on long lists (issue #25) | ✅ Done — `widgets/back_to_top.dart` overlays a small FAB after 400px of scroll on Home and state detail |
| Bottom-nav oversized padding on iOS (issue #26) | ✅ Done — the shell's `MediaQuery.removePadding` (context outside the Scaffold) re-introduced the notch top inset into the nav bar's internal SafeArea; now strips top+bottom (`ShellBottomBar`), bar lays out at the bare 80pt M3 height |
| Camera Times (Info → top row) | ✅ Done — expected point-to-point travel times between average-speed camera points, from `assets/camera_times.csv` (bundled, build-time data). Pure logic in `lib/services/camera_times.dart` (parse → routes → corridors, slugs, duration formatting; unit-tested). UI: `/info/cameras` lists 8 corridors (city pair + highway variant, forward totals); `/info/cameras/:slug` shows the leg-by-leg times with a direction toggle ("To Melbourne"/"To Sydney"), slow-zone notes and a full-run total. CSV "Segment" column rendered as "From → To". Tap-to-select consecutive legs sums a partial run (`LegRange`/`nextLegSelection`); "Time me" (partial or full run) starts a global session (`cameraTimerProvider`, survives tab changes) counting down to when passing the end camera is legal, with a session average piggybacked on the Home speedometer's GPS odometer (no second GPS stream; hidden when GPS off/reset). The panel also renders under the Home speedometer while a session runs (same widget). Every leg card has its own Time me play button; sessions carry the `upcoming` leg queue so the panel offers "Next · <leg>" + "Start next" to roll to the following camera stretch (fresh clock/baseline) as the driver passes each camera |
| Site-approach prompt (Waze-style) | ✅ Done — `services/proximity_alert.dart` (pure `ProximityTracker`) raises a prompt when a site is within **3 km**, the driver is doing **>20 km/h**, and the distance is **shrinking since the previous fix** (that closing test *is* the direction check for the ordinary site — no compass maths, no reliance on the often-missing direction tag), at most **once per site per 2 h**. Fed from the existing speedometer GPS stream (`TripController._onPosition` → `ProximityController.onPosition`) — never a second listener. On screen: a card floating over the router (`ProximityGate` in `app.dart`) showing the live status + OPEN/BLITZ/CLOSED. **The card has no timer** — it stays (counting the distance down as you close in) until the driver answers it, dismisses it, or the site goes behind them (tracked per *pass* through the radius: `hasPassed` fires once they pull `proximityPassedMarginKm` back from their closest point, or leave the 3 km radius). A **dismissal** is "not now", so the site gets one **second-chance prompt inside 100 m** (`proximityNearRadiusKm`, no speed or cooldown gate — braking for the gate is exactly when the answer is best); an **answer** ends the conversation for that pass. Off screen: a system notification with the same three vote actions (`services/proximity_notifier.dart`); the pending prompt is kept so the card is waiting when the app is reopened. Toggle: `near_me` icon on Home, persisted like the sound switch. **Direction-aware opposite pairs (0.1.67):** the one place compass maths *does* enter. Two opposite-direction sites within `proximityPairRadiusKm` (2 km) are one location — the two carriageways of the same road (Mt White, Marulan and Daroobalgie N/S share a pin). A travel heading derived inside the tracker from consecutive fixes (course over ground ≥ 10 m of movement — this *is* the device's GPS heading, but pure, testable and web-capable, unlike platform `Position.heading` with its -1/0/NaN invalid markers) picks the member the driver is actually rolling toward (bearing within 90° of the tag): that one prompts exactly as before, and the opposite one is **deferred** — it asks **once**, only inside the 100 m near radius, and only after the matching member is *done* (answered or passed): "you've dealt with your side — what does the other side look like?". Two dismissals of your own side is "leave me alone", not done. Unknown heading, lone directional sites (their tag may be stale; no twin to carry the question) and pairs further apart than 2 km keep the old behaviour exactly |
| Background site alerts | ✅ Done (Android verified locally; **iOS needs on-device verification on the Mac**) — Android runs a location-typed **foreground service** (`AndroidSettings.foregroundNotificationConfig`, wake lock on) which is what grants background location *without* `ACCESS_BACKGROUND_LOCATION` and its Play review; the ongoing "RoadMate is watching the road" notification is the visible trade. iOS uses `AppleSettings(allowBackgroundLocationUpdates, showBackgroundLocationIndicator, pauseLocationUpdatesAutomatically: false, automotiveNavigation)` + `UIBackgroundModes: location` in `Info.plist`. Manifest/plist keys are guarded by `android_manifest_test.dart` / `ios_info_plist_test.dart` |
| GPS coordinates on Add Site + admin site editor (name + pin) | ✅ Done — `widgets/coordinate_fields.dart` (shared by both) offers "Use my current location" plus editable lat/lng. **Optional by design**, but validated: half a pair or an out-of-range value is rejected rather than silently dropped (`parseCoordinate`/`coordinateFieldError`/`coordinatePairError` in `geo.dart`). Admins get an `edit_location_alt` action on every site card — amber when the site has no pin — opening `EditSiteDialog` (`widgets/edit_site_dialog.dart`; 0.1.64 grew it from coordinates-only to the name; 0.1.66 made it the **full site editor**: name/suburb/address (validated non-empty, trimmed), type/state/direction dropdowns, and a clearable note — every describing field, deliberately excluding derived data (status, vote tallies, lastReportAt — owned by report moderation) and moderation fields (approved/createdBy — own approve/reject flow)), writing through `AdminRepository.updateSiteDetails`/`siteEditData` (pure, unit-tested write shape: enum wire strings, nulls for cleared optionals — exactly what shipped clients read; existing shape-free admin-update rule, no rules change) |
| Road names (unique public usernames signing all posts) | ✅ Done (0.1.61, **web-first**) — every vote, activity report and site submission is signed with a unique, human-readable "road name" ("Dusty Roadtrain"). Generator mixes one-or-two adjectives + a road/travel noun (`lib/services/username_logic.dart`, pure & unit-tested); the picker pre-fills a roll, offers a dice reroll, and accepts free typing (validated 3–30 chars, letters/digits/space/`-`/`_`). Uniqueness via `usernames/{lowercased}` claim docs (create-if-free rules; lost races surface as "already taken"). Anonymous users with no name get a dismissible overlay card at load (`UsernameGate` in `app.dart`, same overlay pattern as the proximity card) and a **mandatory** dialog at post time (`ensureSignatureName` — declining abandons the post); signed-in users sign with their provider displayName unless they pick a road name (never prompted at load). The proximity approach card is the one deliberate exception: it sits above the Navigator and a driver answering at speed must not be blocked, so its votes are signed only when a name already exists. Votes carry `reporterName` now too (additive rules change; legacy 4-field votes keep passing), sites carry `createdByName` beside `createdBy`, and the report dialog's old free-text "Name (optional)" box is replaced by "Posting as <name>". User tab shows/changes the name (`RoadNameRow`). Mobile builds keep working unsigned until their next store release |
| Participation points, levels & badges (virtual rewards) | ✅ Done (0.1.59, **web-first** — mobile earns/shows levels only after its next store release; old builds keep working, they just don't participate) — counters in `users/{uid}/stats/participation` written in the same atomic batch as each vote/report; level icon + title + progress in the User tab's account panel (`ParticipationSummary`); Achievements page (`/user/achievements`) with the badge grid; level icon beside reporter names on report rows via the denormalized `reporterLevel`. 0.1.60 adds the Trailblazer badge — earned by submitting a site (`sitesAdded` counter, no approval needed and no points). Deferred to phase 2: *points* for approved Add-Site submissions (console approvals would skip the credit), historical backfill, level-up snack |
| Open a site in the maps app (the whole address row is the tap target — bare directions icon leading the address text, replacing the decorative pin) | ✅ Done — `mapsUri` in `lib/services/map_links.dart` (pure, platform-injected like `storeLinksFor`): Android gets the `geo:` scheme (native maps app / chooser), iOS gets Apple Maps (`maps.apple.com?ll=&q=`), web and desktop get the universal Google Maps search URL in a new tab (`LaunchMode.externalApplication`). Un-geocoded sites fall back to a maps **text search of the address**, so every card keeps the affordance. Launch failure → snack |
| Google sign-in popup-blocked fallback | ✅ Done — a blocked popup falls back to `signInWithRedirect`/`linkWithRedirect`; the return leg completes at startup (`AuthController.completeRedirectSignIn`), incl. the link-conflict case; `ensureSignedIn` waits for the restored session first. Web `authDomain` = `roadmate.club` (first-party redirects — Safari/incognito safe; the OAuth redirect URI was added in Google Cloud 2026-07-07). **Installed PWAs skip the popup entirely** and use redirect from the start (`display_mode_web.dart` detects standalone display) — a PWA "popup" is an opener-less custom tab where the Firebase handler hangs blank (Firefox shortcut-app bug, diagnosed from screen recording 2026-07-08) |
| Android Google sign-in via the native account sheet | ✅ Done (0.1.71) — Android uses **Credential Manager** (`google_sign_in` 7.x, `AuthController.useGoogleCredentialSheet`) instead of `signInWithProvider`: the Custom-Tab flow delivered its result behind a tab it never closed, stranding users on a blank page (diagnosed frame-by-frame from the owner's 0.1.70 recording), and forced a full email/password/2FA round trip. The sheet signs in over the app with the device's Google accounts — no browser. `GoogleCredentialSource` (`lib/services/google_credential.dart`) mints the Firebase credential (`serverClientId` pinned to the web OAuth client, guarded by `test/google_credential_test.dart`); linking/conflict fallback mirrors the provider flow; account-deletion reauth uses the sheet too; a dismissed sheet throws `SignInCancelledException`, which the panel treats as a silent no-op (deletion shows "Account not deleted…"). Requires the SHA-1/SHA-256 fingerprints registered in Firebase 2026-08-15 (Play App Signing + upload + VPS debug — that registration also fixed the `invalid-cert-hash` failure that blocked all 0.1.70 Android sign-ins). minSdk was already 24 (Flutter default), matching `google_sign_in_android`'s floor. iOS keeps `signInWithProvider` (ASWebAuthenticationSession auto-closes); web keeps popup/redirect. Pre-0.1.71 Android builds keep the Custom-Tab flow — quirky but working now the SHAs exist |

## Deployment & domain

- **Live web app:** https://roadmate-b1551.web.app (Firebase Hosting; config in
  `firebase.json`). **Deploys run only from the Web Release pipeline** (see
  below) — never from a terminal.
- **Custom domain:** `roadmate.club` (registrar **Namecheap**, default BasicDNS).
  Connected via the modern Firebase single-A-record method:
  - `A` · host `@` · `199.36.158.100`  (Firebase Hosting IP)
  - `TXT` · host `@` · `hosting-site=roadmate-b1551`  (Firebase site verification)
  - `www` (optional): `CNAME` · host `www` · `roadmate-b1551.web.app` — and add
    `www.roadmate.club` as a custom domain in the console so SSL is issued.
  - Firebase auto-provisions the Let's Encrypt cert after verification (~15 min–few h).
- **Rules & indexes deploy:** ride every web release — the pipeline's deploy
  step publishes `hosting,firestore:rules,firestore:indexes` together.

### Release pipeline (GitHub Actions, 2026-08-24)

Pushing `master` triggers **Web Release** (`.github/workflows/web-release.yml`):
three parallel gates — the **CodeQL gate** (waits for GitHub's default-setup
scan: the `dynamic/github-code-scanning/*` workflow run for the commit — it
has no workflow file in this repo and its run names vary, e.g. "Code Quality:
Push on master"), **Flutter CI**
(`flutter-ci.yml`, reusable: analyze + tests + Firestore-rules suite; still
runs standalone on PRs) and **Visual Verification** (`visual-verification.yml`,
reusable: `scripts/verify_web.sh` in headless Chrome) — then a deploy job
(`needs:` all three) builds via `scripts/build_web.sh` (the media copy-back and
registrant guard preserved from the old release.sh) and runs `firebase deploy
--only hosting,firestore:rules,firestore:indexes` as the service account. A
green push is live in ~15–20 min; `scripts/check_ci.sh [sha]` blocks on it.
`scripts/release.sh` is now only the local half: tests → patch bump →
commit+push.

**Mobile Release** (`mobile-release.yml`) is the manual store step: Actions →
Run workflow (platform `both`/`android`/`ios`; `dry_run` builds everything but
uploads nothing; `commit` releases a chosen master commit — paste the sha of
the green pipeline run to ship, empty = latest, the GitLab-style "release this
pipeline"). Preflight resolves that sha, requires it to be **on master** and to
have its own successful Web Release, and refuses non-master refs. Android runs on ubuntu (keystore + Play SA
materialized from secrets → `release_android.sh`); iOS runs on a hosted macOS
runner (temp keychain from the .p12 secret, the provisioning profile, the ASC
API key → `release_ios.sh`, which uploads via altool and finishes with
`asc_submit.py`). Both scripts honour `RELEASE_DRY_RUN=1` (stop after the
signed artifact).

**Actions secrets** (uploaded by `scripts/setup_release_secrets.sh` — machine-
aware: run on the VPS for the web/Android half, on the Mac for iOS):
`FIREBASE_SERVICE_ACCOUNT`, `PLAY_SERVICE_ACCOUNT_JSON`,
`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`;
iOS: `IOS_DIST_P12_BASE64`, `IOS_DIST_P12_PASSWORD`,
`IOS_PROVISIONING_PROFILE_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_PRIVATE_KEY`. Re-run the script after rotating anything. Pipeline
invariants are unit-guarded by `test/release_pipeline_test.dart`.

**Release permissions (2026-08-25):** the darumatic org's base permission is
**read**, so only the two org owners (`deccico`, `fortuneFelix`) can push to
master (which auto-deploys web), dispatch Mobile Release, or reach the Actions
secrets. On this repo **write = release power** — a push deploys, and a branch
workflow can read repo secrets — so keep roadmate collaborators at read/triage
and take contributions as fork PRs (the Flutter CI `pull_request` gate covers
them; fork PRs get no secrets and cannot dispatch workflows). Per-repo grants
stack on top of the base: giving someone write on another darumatic repo does
not touch this one.

### Google Play publishing

`scripts/release_android.sh` → `scripts/play_upload.py` (stdlib-only; SA JSON at `~/.config/roadmate/google-play-service-account.json`) uploads the AAB and commits a completed release to the production track. Learnings from the 0.1.72 release (2026-08-16):

- **An API commit is not a live release.** Play still reviews the change set after the commit, and the console's Publishing overview can show "Not yet sent for review" even though auto-send (`changesNotSentForReview=false`) is the API default. The tracks API reporting the release as `status: "completed"` describes the committed configuration only — it is never proof users can see the build.
- **A stuck "Not yet sent for review" pile can sometimes be flushed via the API**: open a fresh edit, re-PUT the production track unchanged, then `:commit?changesNotSentForReview=false` (worked on 0.1.72). The Publishing-overview **"Send for review" button has no API** — if the flush doesn't take, it's an owner click in the console, usually because a new required declaration is attached (the page says which).
- `play_upload.py` prints "Committed …" (not "Released") and warns about this state since 0.1.72.
- Play **re-signs** uploads with the App Signing cert (SHA-1 `79:3E:54:9D:B9:F7:06:75:A8:3E:06:B9:49:86:FD:F2:87:F1:4F:34`) — that cert, not the upload key, is what installed apps present to Firebase/Google APIs. Both are registered as Firebase SHA fingerprints since 2026-08-15 (the missing registration was the root cause of the `invalid-cert-hash` sign-in failures).

### iOS signing material

Apple team **76UL6RCLTT** (DARUMATIC PTY LTD). `hello@darumatic.com` is the Account
Holder and `adrian@darumatic.com` an Admin — **two logins into the same team**, not
two teams, so the ASC API sees one shared set of certificates.

Two pieces must be present on the release Mac, and both went missing before the
0.1.51 release (28 Jul 2026): the team's only **Apple Distribution** certificate had
been revoked, which cascaded and deleted every provisioning profile with it. The
archive still built (automatic *development* signing) and the failure only appeared
at the export step. `scripts/release_ios.sh` now preflights both:

- **Identity** — `Apple Distribution: DARUMATIC PTY LTD (76UL6RCLTT)` in the login
  keychain (`security find-identity -v -p codesigning`). A **.p12 backup** of the
  current one lives at `~/.config/roadmate/apple_distribution_20260728.p12`; its
  passphrase is in the login keychain, **not in this repo** —
  `security find-generic-password -s roadmate-dist-p12 -w`. A private key is *never*
  re-downloadable from Apple, so losing it means minting a new certificate. Restore with
  `security import <p12> -k ~/Library/Keychains/login.keychain-db -P "$(security find-generic-password -s roadmate-dist-p12 -w)" -T /usr/bin/codesign`.
  (The p12 and the keychain item live on the same Mac, so keep an off-machine copy of
  both if that Mac is the only one that can release.)
- **Profile** — `RoadMate App Store` (App Store type, bundle `com.darumatic.roadmate`)
  in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. **Keep the name
  stable** — `ios/ExportOptions.plist` matches it by name.

Signing is **manual end to end** (2026-08-24): the Runner target's Release
configuration pins `CODE_SIGN_STYLE = Manual`, the `Apple Distribution` identity and
the `RoadMate App Store` profile for the *archive*, and `ios/ExportOptions.plist`
does the same for the export — both guarded by `test/ios_export_options_test.dart`.
Until then the archive used Xcode's *automatic* signing, which wants an Apple ID
signed into Xcode.app: on the Mac it quietly leaned on leftover *development*
signing material (which is why the revocation above only surfaced at the export
step), and on a hosted GitHub runner — which has no such leftovers — it failed
outright with "No Accounts" / "No profiles for 'com.darumatic.roadmate'" (the first
Mobile Release iOS dry run). Manual Release signing needs exactly the two
preflighted pieces above, on any machine. The Mobile Release workflow installs the
profile into both the Xcode 16+ location above and the legacy
`~/Library/MobileDevice/Provisioning Profiles` so any runner Xcode resolves it.

To mint replacements headlessly (the ASC API key is Admin, so no Xcode sign-in or
2FA is needed): `openssl genrsa` + `openssl req` for a CSR → `POST /v1/certificates`
with `certificateType: DISTRIBUTION` → import → `POST /v1/profiles` with
`profileType: IOS_APP_STORE`, related to the bundle id and the new certificate.
Apple allows 2 distribution certificates per team; minting only revokes something if
both slots are already full.

**Export signing is manual on purpose.** `flutter build ipa` defaults to *automatic*
export, which asks the Apple ID signed into Xcode.app for a distribution certificate —
this Mac has no Xcode account (`No Accounts`), so the release script passes
`--export-options-plist=ios/ExportOptions.plist`. Guarded by
`test/ios_export_options_test.dart`.

**Still unresolved:** *why* the certificate was revoked. It was valid to 2027-07-08 and
had signed 0.1.49 days earlier. `leandropervieux@hotmail.com` was ruled out — his
`provisioningAllowed` was already `false`, so he never had portal access (he was
nonetheless reduced to `CUSTOMER_SUPPORT` on 28 Jul 2026 at the owner's request). That
leaves the two portal-capable logins, `hello@darumatic.com` and `adrian@darumatic.com`;
neither has been checked. 0.1.51 shipped on a **replacement** certificate — the cause is
worked around, not found.

**Also unguarded:** the *archive* step still uses automatic **development** signing, so
it depends on `Apple Development: Felix Schmitz (7GHG36Y542)` (expires 2027-07-08) — the
only development identity on this Mac. The preflight checks the distribution identity
and profile, not that one; when it expires the archive will fail with no Xcode account
to renew it.

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
   permission can't be granted in the automated browser). Admins can now correct a
   pin in-app (site card → edit-location), and drivers can capture one when adding
   a site, so refinement no longer needs an ops script.
5. **Background approach alerts on iOS** — code and `Info.plist` are in place but
   unverifiable here (iOS builds only on the Mac). Needs a real-device run: confirm
   fixes keep arriving with the app backgrounded, the blue indicator appears, and
   the notification's vote actions bring the app forward and cast the vote. App
   Review will also want the background-location purpose string to match observed
   behaviour.
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
