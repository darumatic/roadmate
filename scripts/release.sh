#!/usr/bin/env bash
# Full release cycle for RoadMate. Runs the mandatory steps in order:
#   local tests -> bump patch version -> commit & push -> deploy to prod
#
#   ./scripts/release.sh                       # cuts a release of the committed tree
#   ./scripts/release.sh "Fix blitz banner"    # bundles staged/working changes under that message
#
# Any working-tree changes are committed with the given message (or a default
# "Release vX.Y.Z"). GitHub CI runs the same analyze+test suite on the pushed
# commit, but the deploy does not wait for it (use scripts/check_ci.sh to poll
# a run manually).
set -euo pipefail

# This VPS's tool locations (flutter / firebase are not on the default PATH).
export PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$PATH"

# Deploy with the service-account key when it is on this machine, so the
# firebase CLI never depends on a (expirable) personal login token.
if [ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] \
    && [ -f "$HOME/.config/roadmate/firebase-adminsdk.json" ]; then
  export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/roadmate/firebase-adminsdk.json"
fi

cd "$(dirname "$0")/.."

msg="${1:-}"

echo "==> Local checks (analyze + test)"
flutter analyze
flutter test

echo "==> Bump patch version"
dart run tool/bump_version.dart
new_version="$(grep -oE "[0-9]+\.[0-9]+\.[0-9]+" lib/version.dart | head -1)"
if [ -z "$msg" ]; then
  msg="Release v${new_version}"
fi
echo "    ${msg}"

echo "==> Commit & push"
git add -A
git commit -m "$msg"
git push

echo "==> Build web"
flutter build web --no-tree-shake-icons

echo "==> Verify web plugin registrant"
# Guard against a stale generated registrant (bit us in v1.0.9-v1.0.18: the
# cached web_plugin_registrant.dart predated shared_preferences being added,
# so SharedPreferences silently threw MissingPluginException on web and trips
# never saved). Every *_web plugin package resolved in package_config.json
# must be imported by the registrant compiled into the build.
registrant="$(ls -t .dart_tool/flutter_build/*/web_plugin_registrant.dart 2>/dev/null | head -1)"
if [ -z "$registrant" ]; then
  echo "ERROR: no web_plugin_registrant.dart found after build" >&2
  exit 1
fi
missing=0
for pkg in $(grep -oE '"name": *"[a-z0-9_]+_web"' .dart_tool/package_config.json | grep -oE '[a-z0-9_]+_web'); do
  if ! grep -q "package:${pkg}/" "$registrant"; then
    echo "ERROR: ${pkg} is resolved but not registered in ${registrant}" >&2
    echo "       Stale build cache — run 'flutter clean' and rebuild." >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1

echo "==> Deploy to prod"
firebase deploy --only hosting,firestore:rules,firestore:indexes

echo "==> Released v${new_version} -> https://roadmate.club"
