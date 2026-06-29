# RoadMate AU — Pending Tasks

Backlog toward a real launch. The build itself is complete and live
(https://roadmate-b1551.web.app); see `specs.md` for the as-built record and
decisions. Nothing below is blocking — these are next steps.

## In progress
- [ ] **Custom domain `roadmate.club`** — DNS records are live and propagated
      (`A @ 199.36.158.100`, `TXT @ hosting-site=roadmate-b1551`). Click **Verify**
      in Firebase Console → Hosting and let the SSL cert provision (~15 min–few h).
  - [ ] Optional: add `www.roadmate.club` (CNAME `www → roadmate-b1551.web.app`,
        and add it as a custom domain in the console so SSL is issued).

## Pre-launch hardening
- [ ] **Rate-limiting** — rules block counter *tampering*, but a user can still
      spam +1 votes. Add Cloud Functions (or App Check) to throttle votes/reports.
- [ ] **Moderation UI** — Add Site submissions are created `approved: false` and
      currently approved **manually** in the Firebase console. Build an in-app
      admin/approval screen (or a lightweight review flow).

## Coordinates & Nearby
- [ ] **Refine coordinates** — currently town/locality-level (geocoded via OSM
      Nominatim, verified in-bounds). Improve to exact site positions.
- [ ] **Test Nearby end-to-end** on a real device (geolocation permission can't be
      granted in the automated browser).

## Release
- [ ] **iOS App Store** — runs on the Simulator; needs Apple Developer signing,
      provisioning profiles, app icons, and a store listing.
- [ ] **Android release** — build/sign (keystore) + Play Store listing.

## Optional / later
- [ ] **FCM push notifications** for blitz alerts.
- [ ] **Analytics** (Firebase Analytics already wired via the web config).
- [ ] **Repo housekeeping** — the 10 MB design video in `screens/` is committed;
      consider Git LFS or removing it from history if repo size matters.

## Documentation & decisions
- [ ] **LICENSE** — decide proprietary vs. open-source for `roadmate.club` and add
      a `LICENSE` file (owner decision).
- [ ] **In-app data disclaimer** — the README has a disclaimer; also surface a short
      user-facing one in the app (e.g. on Home or a Profile/About screen):
      "community-reported, may be inaccurate, not official NHVR data."
- [ ] **Secrets policy (when server-side work starts)** — committed Firebase client
      config is public/non-secret, but future Cloud Functions service-account keys
      must never be committed; document the chosen secret store at that time.

## Done (this build)
- [x] Flutter app (iOS/Android/web), Firebase (Firestore + anonymous auth)
- [x] Home, Browse-by-State, state detail, voting, Report, BLITZ banner,
      Recently Active, Saved, Add Site, Nearby
- [x] 24 real NHVR sites seeded; coordinates geocoded
- [x] Hardened Firestore security rules (validated votes; pending-site moderation)
- [x] Web deployed live to Firebase Hosting
- [x] iOS built & verified on the Simulator
- [x] 30 unit/widget tests; `flutter analyze` clean
