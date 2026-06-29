# RoadMate AU

**Know before you roll.** A community-powered app for Australian heavy-vehicle
drivers to see and share the **live status** of NHVR (National Heavy Vehicle
Regulator) inspection / compliance sites — weighbridges, checking stations, HV
safety stations and inspection sites.

🌐 **Live:** https://roadmate-b1551.web.app — custom domain **roadmate.club**

> ⚠️ **Data disclaimer.** Site information is **community-reported and
> provisional**. Locations are approximate (geocoded at town level), statuses are
> crowd-sourced and may be wrong or out of date, and this is **not official NHVR
> data**. Always follow on-road signage and official directions.

## Stack

One **Flutter** codebase → **iOS, Android, web**. Backend is **Firebase**
(Cloud Firestore, anonymous Auth, Hosting). State: **Riverpod 3**; routing:
**go_router**. Firebase project: `roadmate-b1551`.

See [`specs.md`](specs.md) for the full as-built record and **key decisions**, and
[`CLAUDE.md`](CLAUDE.md) for architecture/agent guidance. Backlog in
[`tasks.md`](tasks.md).

## Quickstart

```bash
flutter pub get
flutter run -d chrome          # web (also: an iOS sim id, or an Android emulator)
flutter test                   # 30 unit/widget tests
flutter analyze                # static analysis (keep clean)
dart format lib test
```

Firebase config is generated in `lib/firebase_options.dart`. The committed
`firebase_options.dart`, `GoogleService-Info.plist` and `google-services.json` are
**public client config, not secrets** — safe to commit. (Any future server-side
service-account keys must **not** be committed.)

### Project layout
```
lib/
  models/      enums, Site, SiteReport
  services/    SiteRepository (Firestore + local seed), auth, seed,
               status_logic / site_stats / geo (pure, unit-tested)
  features/    home, state_detail, nearby, saved, add_site
  widgets/     shared UI (site card, state card, stats bar, blitz banner, ...)
sites/         nhvr_national_inspection_sites.json  (authoritative data, 24 sites)
firestore.rules
```

## Data

The authoritative site list is `sites/nhvr_national_inspection_sites.json`
(24 sites — NSW 13, QLD 3, VIC 3, SA 2, TAS 3; WA & NT are non-participating
jurisdictions). It is **seeded into Firestore automatically on first run** when the
`sites` collection is empty (`SeedService`), and coordinates are backfilled.
Coordinates were geocoded (town level) via OpenStreetMap Nominatim.

To change the dataset: edit the JSON. On an **empty** DB it re-seeds automatically;
on a populated DB, seeding is a no-op — updating existing docs is an admin task
(the hardened create rule blocks client-side `approved: true` writes).

## Operations / runbook

### Deploy
```bash
flutter build web --no-tree-shake-icons
firebase deploy --only hosting --project roadmate-b1551          # web
firebase deploy --only firestore:rules --project roadmate-b1551  # security rules
```
`flutterfire` lives at `~/.pub-cache/bin` (not on PATH by default).

### Approve a community-submitted site (moderation)
New sites from **Add Site** are stored with `approved: false` and stay hidden
(`watchSites` filters `approved == true`). To publish one:
1. Firebase Console → **Firestore Database** → `sites` collection.
2. Open the pending doc (it has `approved: false`, `createdBy: <uid>`).
3. Set **`approved`** → `true`. It appears in the app immediately.

(An in-app admin screen + rate-limiting are tracked in `tasks.md`.)

### Inspect Firestore data quickly
Sites are publicly readable, so you can read them via REST with the web apiKey:
```
GET https://firestore.googleapis.com/v1/projects/roadmate-b1551/databases/(default)/documents/sites?key=<apiKey>
```

### iOS
Building iOS needs the Xcode license accepted (`sudo xcodebuild -license accept`).
Firebase is integrated via **Swift Package Manager** (not CocoaPods). Runs on the
iOS Simulator today; App Store distribution still needs signing/provisioning.

## Contributing

Commits in this repo are **attributed to the owner only** — do not add
`Co-Authored-By` trailers.
