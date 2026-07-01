# RoadMate AU — Pending Tasks

Backlog toward a real launch. The build itself is complete and live
(https://roadmate.club); see `specs.md` for the as-built record and
decisions. Nothing below is blocking — these are next steps.

## Next
- [ ] Review the fallback page in case Firebase does not work. 
- [ ] Is Firebase in testing mode?
- [ ] "Report activity" should not be abused. Investigate abuse prevention.
- [ ] Plan backup and roll-backs. We need to make sure the database is being backup at least two weeks before.
- [ ] `www.roadmate.club` should redirect to roadmate.club.
- [ ] Add a Darumatic logo and page. Something like consulting provided / etc.
- [ ] **Repo housekeeping** — the 10 MB design video in `screens/` is committed;
      remove it from Git history.
- [ ] Add donations page.
- [ ] ci unit tests. Add instructions to add tests where it makes sense and keep adding tests for new functionality.

## Backlog
- [ ] Reorganise state based on the user location?
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
- [ ] **FCM push notifications** for blitz alerts. At 50km.
- [ ] **Analytics** (Firebase Analytics already wired via the web config).
- [ ] **LICENSE** — decide proprietary vs. open-source for `roadmate.club` and add
      a `LICENSE` file (owner decision).

- [ ] add timer to assist with rests
- [ ] page with important links
- [ ]
