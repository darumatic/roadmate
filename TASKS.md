# RoadMate AU — Pending Tasks

Backlog toward a real launch. The build itself is complete and live
(https://roadmate.club); see `specs.md` for the as-built record and
decisions. Nothing below is blocking — these are next steps.

## To review
- [ ] Answer in a document "codex-output.md": Money limits for Firebase. What happens if we consume more than the free tier plan? I want to fail gracefully and stop serving the app.
- [ ] Answer in a document "codex-output.md": What happens with the data from "Report activity"?
- [ ] Answer in a document "codex-output.md": plan backup / roll-backs. What happens with the database state if we need to roll-back to last week's version for example?
- [ ] Answer in a document "codex-output.md": Firebase database is in "testing" what does this mean?
- [ ] **Repo housekeeping** — the 10 MB design video in `screens/` is committed;
      remove it from Git history.
- [ ] Answer in a document "codex-output.md": **Secrets policy (when server-side work starts)** — committed Firebase client config is public/non-secret, but future Cloud Functions service-account keys must never be committed; document the chosen secret store at that time.


## In progress
  - [ ] Optional: add `www.roadmate.club` (CNAME `www → roadmate-b1551.web.app`,
        and add it as a custom domain in the console so SSL is issued).

## Next
- [ ] Also we can add a timer of how long ago each weightbridge being reported
- [x] We can change SAVED to FAVOURITE and should saved for different users
- [x] Initial loading is slow. We need some loading icon.
- [x] Add sites needs to go.
- [ ] Money limits for Firebase. What happens if we consume more than the free tier plan? I want to fail gracefully and stop serving the app.
- [ ] Add donations page.
- [ ] Add about page mentioning Leandro.
- [ ] ci unit tests
- [ ] add support option. (email reports. What email?)

## BAcklog
- [ ] Reorganise state based on the location?
- [ ] Favourites at the beginning?
- [ ] **Rate-limiting** — rules block counter *tampering*, but a user can still
      spam +1 votes. Add Cloud Functions (or App Check) to throttle votes/reports.
- [ ] **Refine coordinates** — currently town/locality-level (geocoded via OSM
      Nominatim, verified in-bounds). Improve to exact site positions.
- [ ] **Test Nearby end-to-end** on a real device (geolocation permission can't be
      granted in the automated browser).
- [ ] **iOS App Store** — runs on the Simulator; needs Apple Developer signing,
      provisioning profiles, app icons, and a store listing.
- [ ] **Android release** — build/sign (keystore) + Play Store listing.
- [ ] **FCM push notifications** for blitz alerts.
- [ ] **Analytics** (Firebase Analytics already wired via the web config).
- [ ] **LICENSE** — decide proprietary vs. open-source for `roadmate.club` and add
      a `LICENSE` file (owner decision).
- [ ] **In-app data disclaimer** — the README has a disclaimer; also surface a short
      user-facing one in the app (e.g. on Home or a Profile/About screen):
      "community-reported, may be inaccurate, not official NHVR data."

