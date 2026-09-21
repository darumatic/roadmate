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

## What the Firestore SDK and the rules really do (emulator probe)

Posting can't be driven through the app (it writes to production, and the app
has no emulator switch), and assumptions about the SDK — pending writes, the
order of acks and snapshots, what a refused batch does to the ones queued
behind it — are exactly what unit-test fakes can't check. They can be checked
locally, against the real JS SDK (the one Flutter web wraps) and the real
rules, without touching production:

1. Scratch dir with `package.json` `{"type":"module"}`, a `node_modules`
   symlink to `test/rules/node_modules` (it already holds `firebase` and
   `@firebase/rules-unit-testing`), and a `probe.mjs`.
2. In it: `initializeTestEnvironment({projectId: 'demo-<name>', firestore:
   {host: '127.0.0.1', port: 8080, rules: readFileSync('<repo>/firestore.rules', 'utf8')}})`.
   `env.authenticatedContext(uid, {firebase: {sign_in_provider: 'anonymous'}}).firestore()`
   is a client under the real rules; `env.withSecurityRulesDisabled(ctx => …)`
   seeds and reads back. Modular API throughout (`writeBatch`, `onSnapshot`,
   `serverTimestamp`, `disableNetwork`/`enableNetwork`).
3. From the repo root: `firebase emulators:exec --only firestore --project
   demo-<name> "node <abs path>/probe.mjs"` (Java 21+). A `demo-` project id
   never reaches a real backend, and the emulator needs no indexes.

`disableNetwork` → write → wait → `enableNetwork` holds a write pending long
enough to observe; issuing two commits back to back without awaiting is a slow
link in miniature (both are with the server before either is answered). Mirror
the Dart logic faithfully and log every attempt. The native Android/iOS SDKs
can't be probed this way. Established so far: a pending `serverTimestamp()`
doc is absent from a Timestamp range-filtered listener until the ack, which
resolves the write's promise ~2 ms *before* the listener's snapshot (#50);
refusals come back in the order the writes went out, a reset queued behind
another post's reset is denied because the window is by then open, and a
re-send joins the SDK's queue at the back — so a post let through while an
earlier one is mid-retry lands first (#57).

Flows worth driving: Home (speedo, blitz banner, closest sites, speaker mute toggle top-right), tap blitz banner → state detail (site cards, vote-row states, back-to-top after two wheel scrolls), bottom nav tabs.
