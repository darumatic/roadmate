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

**Firestore model:** `sites/{id}`, `sites/{id}/reports/{id}`, `users/{uid}/favourites/{id}`. Security rules in `firestore.rules` are **deployed & hardened** (test mode closed): votes are validated (exactly one counter +1; no field tampering); Add Site creates **pending** sites (`approved: false`) hidden until manually approved in the console (`watchSites` filters `approved == true`). The strict create rule means a wiped DB can't be re-seeded from the client (admin op). `SeedService` (`lib/services/seed_service.dart`) seeds the 24 sites once and backfills coordinates; both idempotent no-ops once populated.

**iOS:** `firebase_options.dart` `ios` block is hand-written from `ios/Runner/GoogleService-Info.plist` (FlutterFire's CLI can't edit the Xcode project on this machine — system Ruby 2.6 lacks the `xcodeproj` gem; runtime init uses explicit options so the plist build-phase ref isn't required). Building iOS needs `sudo xcodebuild -license accept` first, then `brew link cocoapods` + `pod install`.

**Pure, unit-tested logic** lives Flutter/Firebase-free for fast tests: `services/status_logic.dart` (live status from reports), `services/site_stats.dart` (counts/grouping/search/recently-active/blitz), `services/geo.dart` (haversine/nearest), and `parseNhvrNationalData` in `site_repository.dart`.

## Hard constraints

- **Commit attribution: only the user.** Do NOT add `Co-Authored-By: Claude` (or any Claude/Anthropic attribution) to commits — overrides the default Claude Code trailer (per `specs.md`).
- **Every feature ships with a unit test** (per `specs.md`).
- Data lives in `sites/nhvr_national_inspection_sites.json` (authoritative, 24 sites). **Coordinates are geocoded (town-level, approximate)** via OSM Nominatim — verify exact positions before production.
- TASKS.md is for the user to control what is next. Don't write this file but you can use it as a reference.
- After each substantial change, commit and push the changes to git.

## Commands

`flutter` is installed via Homebrew at `/opt/homebrew/bin` (Flutter 3.44.x).

`firebase`/`flutterfire` are installed; `flutterfire` is at `~/.pub-cache/bin` (not on default PATH — call with full path or add it).

```bash
flutter run -d chrome              # run the web app
flutter test                       # all unit tests (30)
flutter test test/<file>_test.dart # a single test file
flutter analyze                    # static analysis (keep clean)
dart format .                      # format
flutter build web --no-tree-shake-icons  # web release build
firebase deploy --only firestore:rules --project roadmate-b1551   # deploy rules
firebase deploy --only hosting --project roadmate-b1551           # publish web (NOT yet done — get owner OK)
```

## Environment notes

- **Web & Android** build/run today. **iOS is blocked** until full **Xcode** (App Store) + **CocoaPods** are installed — only the user can do this. `flutterfire configure` currently registers android+web only (iOS step needs the Ruby `xcodeproj` gem from Xcode). Re-run it after Xcode to add iOS.
- When re-verifying the web build in a browser, **bust the service-worker cache** (unregister SW + `caches.delete`, or load a `?cachebust` URL) or you'll see a stale build.
- Flutter web uses CanvasKit; emoji/icon fonts load async (brief tofu on first paint is expected, not a bug).
- Sites are publicly readable, so you can inspect Firestore data via the REST API with the web apiKey: `GET https://firestore.googleapis.com/v1/projects/roadmate-b1551/databases/(default)/documents/sites?key=<apiKey>`.


## Release Information
- Google Play Service Account: roadmate-play-uploader@roadmate-play-release-501004.iam.gserviceaccount.com

