# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

**RoadMate AU** — a community-powered Flutter app (iOS + Android + web from one codebase) for Australian heavy-vehicle drivers to share **live status** of NHVR (National Heavy Vehicle Regulator) inspection/compliance sites. Tagline: "Know before you roll." Dark-mode UI styled like a modern iOS directory app.

The design source of truth is the **screenshots + screen-recording in `screens/`** (richer than the original brief). **`specs.md` is the as-built record — read it first** for the full feature status, the **Key decisions & rationale**, and the deployment/domain details. The original prototype was React Native/Expo on Replit — there is no reusable code; this is a Flutter rebuild from the design.

Core surface: Home (stats bar Open/Blitz/Closed + Browse-by-State grid + Recently Active + "BLITZ DETECTED" banner), state detail (site list with OPEN/BLITZ/CLOSE voting, Report activity, star to Favourite, type chips, direction tags), Nearby (geolocation), Favourites, Add Site.

## Stack & architecture

- **Flutter** (Material 3, dark theme in `lib/theme/app_theme.dart`).
- **Riverpod 3** for state (`flutter_riverpod`) — note 3.x API; `ConsumerWidget.build(context, ref)`, `Notifier`/`NotifierProvider`, non-generic `Ref`.
- **go_router** with `StatefulShellRoute.indexedStack` for the Home/Nearby/Favourites bottom-nav shell; state detail (`/state/:code`) and `/add` are top-level routes. See `lib/router.dart`.
- **Firebase** — project `roadmate-b1551`. (web **LIVE at **https://roadmate.club**.

**Repository abstraction (important):** all data access goes through `SiteRepository` (`lib/services/site_repository.dart`). Production uses **`FirestoreSiteRepository`**; `LocalSeedSiteRepository` (bundled asset) remains for offline/dev/tests. `lib/services/providers.dart` → `siteRepositoryProvider` is the single swap point. For unit tests, override that provider with a fake/local repo (see `test/site_card_test.dart`).

**Firestore model:** `sites/{id}`, `sites/{id}/reports/{id}`, `users/{uid}/favourites/{id}`, `usernames/{key}` (road-name uniqueness claims — key is the lowercased name; see specs.md), `announcements/current`. Security rules in `firestore.rules` are **deployed & hardened** (test mode closed): votes are validated (exactly one counter +1; no field tampering); Add Site creates **pending** sites (`approved: false`) hidden until manually approved in the console (`watchSites` filters `approved == true`). The strict create rule means a wiped DB can't be re-seeded from the client (admin op). `SeedService` (`lib/services/seed_service.dart`) seeds the 24 sites once and backfills coordinates; both idempotent no-ops once populated.

**Posting is proximity-gated, not account-gated (0.1.57+):** activity reports and status votes are open to anonymous users but only within **3 km** of the site — `checkReportProximity` (`lib/services/report_proximity.dart`) is the rule, with `reportRadiusKm` compile-time locked to `proximityRadiusKm` (the app must never *ask* "what's the status?" at a distance it would refuse an answer from). `FirestoreSiteRepository.vote/report` is the single enforcement point (throws `TooFarException` / `LocationRequiredException`; `SiteRepository.vote/report` take the whole `Site` so the gate can measure against its coordinates), the device fix comes from `LocationSource.currentPosition()` (one-shot; runs the OS permission ask, so "turn on location" is prompted at the moment of posting — still never a second `getPositionStream`), and every UI path turns a refusal into an explanatory snack. **Admins are exempt (0.1.58+, `enforceReportProximity`)** — only moderators may report remotely — with the `userRoles/{uid}` read paid only after a refusal, so ordinary posts cost no extra read. An **un-geocoded site is always reportable** and skips the position lookup. Browsing, Nearby, favourites and Add Site stay account-free and ungated. The gate is client-side only (rules can't verify GPS): shipped 0.1.55/0.1.56 mobile builds keep their old sign-in gate, pre-0.1.55 builds post from anywhere — both write shapes must stay accepted. The 0.1.55 `isRegistered()` rules hardening was **never deployed and is now permanently shelved** — deploying it would break anonymous posting.

**Admin broadcast (`announcements/current`, admin-written):** one doc, one document listener per client, banded across the top of every screen by `AnnouncementGate` (mounted beside `UpdateGate` in `app.dart`). Published from the admin **Notice** tab. In-app only — there is no push channel — and invisible to pre-0.1.55 builds. Keep it a single doc: a query here would break the read budget. **Rich notices (0.1.68+):** optional additive `messageHtml` (≤480; safe HTML subset parsed by `lib/services/notice_markup.dart` — b/i/u/br, http(s) links, `<font color>`; never rendered by an HTML package) and `color` (`#RRGGBB` background). `message` stays required (≤280) as the plain-text fallback 0.1.55–0.1.67 mobile builds render verbatim — the admin form derives it via `plainTextOfNotice`, so never write markup into `message`.

**Bans (`bans/{uid}`, admin-written):** an active ban makes the rules refuse **every write** from that uid (votes, reports, new sites, adding a favourite, profile sync) while leaving all reads open. Two deliberate carve-outs that must survive any edit: **removing** a favourite and **deleting your own account** stay allowed (App Store 5.1.1(v)). A ban with **no `until` field is permanent**, and a malformed one is treated the same — `isBanned()` fails **closed**. Write it as `exists()` **then** `get()` (mirroring `isAdmin()`): binding the `get()` and null-checking it raises "Null value error" for every user *without* a ban and denies all ordinary writes — the `an unbanned user is unaffected` check in `test/rules/rules_test.mjs` exists to catch exactly that regression.

**Hand-edits in `firebase_options.dart`** (a `flutterfire configure` re-run reverts them — restore both): the web block's `authDomain` is `roadmate.club` (first-party sign-in redirects; guarded by `test/firebase_options_test.dart`), and the `ios` block is hand-written from `ios/Runner/GoogleService-Info.plist` (FlutterFire's CLI can't edit the Xcode project on this machine — system Ruby 2.6 lacks the `xcodeproj` gem; runtime init uses explicit options so the plist build-phase ref isn't required). Building iOS needs `sudo xcodebuild -license accept` first, then `brew link cocoapods` + `pod install`.

**Pure, unit-tested logic** lives Flutter/Firebase-free for fast tests: `services/status_logic.dart` (live status from reports), `services/site_stats.dart` (counts/grouping/search/recently-active/blitz), `services/geo.dart` (haversine/nearest), and `parseNhvrNationalData` in `site_repository.dart`.

**Firestore read budget (keep it):** the app deliberately opens few listeners — `watchSites` (one query) and `watchAllRecentReports` (**one** `collectionGroup('reports')` query bounded by the 10h freshness window, feeding every site card via `recentReportsProvider`). Never reintroduce per-site reports listeners, and never `invalidate` a healthy live stream on pull-to-refresh (`refreshSiteData` restarts errored streams only) — both patterns re-bill whole result sets and once blew ~200 reads/user/session.

**One GPS stream (keep it):** `TripController` owns the only position stream and fans it out — speedometer, trip logging, over-limit beep, and the site-approach prompt (`ProximityController.onPosition`). Never open a second `getPositionStream` for a new feature; on a phone in a truck cradle that doubles the radio duty cycle. The stream is background-capable (Android location foreground service, iOS background location mode — see `tripLocationSettings`), so approach alerts still fire with the app off screen; off screen they become a system notification (`ProximityNotifier`) instead of the in-app card, and the pending prompt is kept so the card is waiting on return.

**Disaster recovery:** the live Firestore database is the only copy of every community report, and the hardened `firestore.rules` deliberately prevent client-side re-seeding — so a wipe is unrecoverable without a snapshot. `scripts/backup_firestore.py` (stdlib-only, Admin SA at `~/.config/roadmate/firebase-adminsdk.json`) walks every collection recursively and writes a gzipped JSON snapshot to `~/backups`, preserving raw REST `fields` so timestamps/geopoints/int64s round trip exactly. **Cron on the VPS runs it nightly at 03:00** — incremental Mon–Sat, full on Sunday — with 30-day retention. Restore is `--restore <snapshot>`, a **dry run unless `--confirm`**, and only ever upserts (it never deletes). Logic is unit-tested in `scripts/backup_firestore_test.py`, run as part of `flutter test` via `test/backup_firestore_test.dart`.

Incremental runs carry the append-only `reports` (~80% of the database) forward from the previous snapshot instead of re-reading them — ~260 reads versus ~1,100 — and every run cross-checks its totals against server `count()` aggregations, automatically re-reading in full on any mismatch. An admin *editing* an old report leaves the count unchanged, which is exactly what the weekly full backup covers.

## Hard constraints

- **Commit attribution: only the user.** Do NOT add `Co-Authored-By: Claude` (or any Claude/Anthropic attribution) to commits — overrides the default Claude Code trailer (per `specs.md`).
- **Every feature ships with a unit test** (per `specs.md`).
- **App Store metadata must never mention Google Play, the Play Store, or Android** (guideline 2.3.10 — it got 0.1.38 rejected). This covers everything in App Store Connect: `store/apple_whats_new.txt`, the description, promotional text and keywords. `scripts/asc_submit.py` enforces this and refuses to submit on a match (`FORBIDDEN_IN_METADATA`): the What's New text is checked from the file **before any writes**, and the fields the script never writes (`UNWRITTEN_LOCALIZATION_FIELDS` — description, promotional text, keywords) are **read back from ASC** and checked while the version is still editable. `test/asc_submit_test.dart` runs that guard under `flutter test` and also fails if `store/apple_whats_new.txt` itself trips 2.3.10, so a bad edit surfaces locally rather than an hour into a release. The in-app share message (`InfoScreen.shareText`) is user content and deliberately keeps all three store links; that is allowed. Keep `store/google_play_release_notes.txt` and `store/apple_whats_new.txt` as separate files — never write one from the other.
- **Never break retrocompatibility with released mobile clients.** Shipped Android/iOS builds talk to the same live Firestore and, unlike web, cannot be hot-updated — users may sit on old versions for months. So: Firestore schema changes must be additive (never rename/remove/repurpose fields old clients read or write), `firestore.rules` must keep accepting every read/write shape shipped mobile versions produce, and behaviour changes should live in client-side logic (like the 10h status/activity freshness windows) rather than server-side enforcement wherever possible. If a breaking server-side change is ever unavoidable, flag it explicitly to the owner — it requires coordinated store releases and acceptance that old apps misbehave until updated.
- Data lives in `sites/nhvr_national_inspection_sites.json` (authoritative, 24 sites). **Coordinates are geocoded (town-level, approximate)** via OSM Nominatim — verify exact positions before production.
- TASKS.md is for the user to control what is next. Don't write this file but you can use it as a reference.
- **Every change follows the full release cycle (the owner has standing authorization to deploy to prod):**
  1. **Local tests** — `flutter test` + `flutter analyze` (both must be clean). When fixing a bug or adding a feature, **add/update unit tests** for it first.
  2. **Commit & push** to `master` (commit attribution: only the user — see above).
  3. **Deploy to prod** — publish web + Firestore rules/indexes. **Do not wait for, or post-check, GitHub CI** — its jobs run the same suites already run locally (flutter analyze/test, and test/rules via `scripts/test_rules.sh`), so polling it adds nothing (`scripts/check_ci.sh <sha>` exists only for the rare manual investigation; no `gh`/token required).
  - `scripts/release.sh` runs all three in order (and bumps the patch version — see the version tooling); prefer it over doing the steps by hand.

## Commands

Deploy runs on a Linux VPS. `flutter` lives at `/opt/flutter/bin` and `firebase`/`flutterfire` at `~/.pub-cache/bin` — **neither is on the default PATH**, so scripts export `PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$PATH"`. Firebase is authenticated (`firebase login`, headless via `--no-localhost`); `.firebaserc` sets the default project so `--project` is optional.

```bash
./scripts/release.sh [msg]         # FULL CYCLE: test+analyze -> bump -> commit+push -> deploy
./scripts/check_ci.sh [sha]        # poll GitHub Flutter CI for a commit until green (0=pass; manual use only, not part of the release cycle)
dart run tool/bump_version.dart    # bump patch in pubspec.yaml + regen lib/version.dart (used by release.sh)

flutter run -d chrome              # run the web app
flutter test                       # all unit tests
flutter test test/<file>_test.dart # a single test file
flutter analyze                    # static analysis (keep clean)
dart format .                      # format
flutter build web --no-tree-shake-icons  # web release build
firebase deploy --only hosting,firestore:rules,firestore:indexes   # publish web + rules + indexes (LIVE)
```

**Versioning:** `pubspec.yaml` `version:` is the source of truth; `lib/version.dart` (`appVersion`) is a **generated** display constant baked into the build and shown at the bottom of the Info tab. Each release bumps the patch (`1.0.0 → 1.0.1`) via `tool/bump_version.dart`; the bump logic is unit-tested in `lib/services/version_logic.dart`.

## Environment notes

- **Web & Android** build/run today. **iOS is blocked** until full **Xcode** (App Store) + **CocoaPods** are installed — only the user can do this. `flutterfire configure` currently registers android+web only (iOS step needs the Ruby `xcodeproj` gem from Xcode). Re-run it after Xcode to add iOS.
- When re-verifying the web build in a browser, **bust the service-worker cache** (unregister SW + `caches.delete`, or load a `?cachebust` URL) or you'll see a stale build.
- Flutter web uses CanvasKit; emoji/icon fonts load async (brief tofu on first paint is expected, not a bug).
- Sites are publicly readable, so you can inspect Firestore data via the REST API with the web apiKey: `GET https://firestore.googleapis.com/v1/projects/roadmate-b1551/databases/(default)/documents/sites?key=<apiKey>`.


## Release Information
- Google Play Service Account: roadmate-play-uploader@roadmate-play-release-501004.iam.gserviceaccount.com

## iOS release & App Store review

**Process:** `scripts/release.sh` covers only web (+ version bump, commit, push). Store builds are separate, manual scripts run on the Mac:
- `scripts/release_ios.sh` — analyze/test → `flutter build ios --config-only` (a prior `flutter build web` resets the generated Swift package to iOS 13, breaking Firebase plugins; this regenerates it) → signing preflight (distribution identity + `RoadMate App Store` profile — see **iOS signing material** in `specs.md`, incl. the .p12 backup and how to mint replacements via the ASC API) → `flutter build ipa --export-options-plist=ios/ExportOptions.plist` (**manual** export signing; the automatic default needs an Apple ID signed into Xcode.app, which this CLI-only Mac lacks) → upload via `xcrun altool` when `ASC_KEY_ID`/`ASC_ISSUER_ID` are set (key file `AuthKey_<ID>.p8` in `~/.appstoreconnect/private_keys/`), else hands the IPA to Transporter.
- After the altool upload, **`scripts/asc_submit.py` finishes the ASC release automatically** (stdlib-only, ES256 JWT via openssl): waits for build processing (~1h; polls every 2 min), sets "What's New" from `store/apple_whats_new.txt` (**update that file before releasing** — the script refuses text mentioning Google Play/Android per guideline 2.3.10), renames the editable version, attaches the build, and creates-or-reuses a review submission and submits it. `--dry-run` for read-only checks. Manual-upload (Transporter app) path leaves the ASC steps manual.
- `scripts/release_android.sh` builds the AAB and **uploads + rolls it out to Play production automatically** via `scripts/play_upload.py` (stdlib-only; auth with the roadmate-play-uploader service-account JSON at `~/.config/roadmate/google-play-service-account.json`; release notes read from `store/google_play_release_notes.txt` — update that file before releasing). Falls back to a manual Play Console upload when the key file is absent.

**App Store review constraints (from the 0.1.38 rejection, Jul 2026):**
- **Guideline 3.1.1** — the native iOS app must never expose external donation/payment links (Buy Me a Coffee). This is gated by `showDonationLink()` in `lib/services/min_version.dart`: it hides the Info tab's "Support the app" row and redirects `/info/support` → `/info` (see `lib/router.dart`). Android and web keep donations. Keep both gates when touching the Info tab or router.
- **Guideline 2.3.10** — App Store **metadata** (especially the "What's New" text) must never mention Google Play or other stores. The in-app share message (`InfoScreen.shareText`) is user content and deliberately keeps all three links — that is allowed; only the ASC metadata must stay clean.

