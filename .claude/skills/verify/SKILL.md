---
name: verify
description: Build, launch and drive the RoadMate web app headlessly to verify a change end-to-end (screenshots via puppeteer + chrome-headless-shell).
---

# Verify RoadMate changes (headless web)

## First choice: the deterministic suite

`./scripts/verify_web.sh` compiles the app and drives it in real headless
Chrome via `integration_test/app_test.dart` (semantic finders, seed data, no
Firebase), writing PNGs to `build/integration_screenshots/` — run it, check
exit code 0, and read the PNGs. The same script runs as the Visual
Verification gate of every Web Release
(`.github/workflows/visual-verification.yml`). When a change touches a screen the
suite covers (Home, Info hub, Share, state detail), extend the suite's
assertions/screenshots instead of hand-driving. First run installs a matched
Chrome-for-Testing + chromedriver pair into `~/.cache/roadmate-verify` (~1 min).

## Ad-hoc / live-site driving (Puppeteer)

For flows the suite doesn't cover, live Firestore data, or the deployed site
(https://roadmate.club), the interactive recipe:

1. **Build**: `export PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$PATH" && flutter build web --no-tree-shake-icons` (~3 min).
2. **Browser**: in a scratch dir, `npm i puppeteer-core @puppeteer/browsers && npx @puppeteer/browsers install chrome-headless-shell@stable` (~1 min; pin the executable path it prints).
3. **Serve**: `cd build/web && python3 -m http.server 8787 &` — the app talks to live Firestore (public reads), so real site/report data renders.
4. **Drive**: puppeteer-core with `--no-sandbox`, viewport `390x844 @2x`. Grant + set geolocation (`overridePermissions(origin, ['geolocation'])`, `setGeolocation`) so the speedometer shows "GPS active" and Closest Sites populate. Flutter web is CanvasKit — no DOM text; drive by mouse coordinates read off screenshots (screenshot px = 2× CSS px) and verify by reading the PNGs.
5. Allow ~9 s after `goto` for first paint (fonts/CanvasKit load async).

Gotchas:
- Console will show `wakelock toggle failed: NotAllowedError` — headless artifact, not a bug.
- Avoid tapping vote/report buttons: they write to the production database.
- `?cachebust=N` on the URL avoids the service-worker serving a stale build.

Flows worth driving: Home (speedo, blitz banner, closest sites, speaker mute toggle top-right), tap blitz banner → state detail (site cards, vote-row states, back-to-top after two wheel scrolls), bottom nav tabs.
