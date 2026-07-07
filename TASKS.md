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
- [ ] **Repo housekeeping** — the 10 MB design video in `screens/` is committed;
      remove it from Git history.
- [ ] **Refine coordinates** — currently town/locality-level (geocoded via OSM
      Nominatim, verified in-bounds). Improve to exact site positions.
- [ ] **LICENSE** — decide proprietary vs. open-source for `roadmate.club` and add
      a `LICENSE` file (owner decision).
- [ ] add timer to assist with rests
- [ ] Add firebase_analytics/Performance.
