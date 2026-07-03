#!/usr/bin/env bash
# Full release cycle for RoadMate. Runs the mandatory steps in order:
#   local tests -> bump patch version -> commit & push -> GitHub CI check -> deploy to prod
#
#   ./scripts/release.sh                       # cuts a release of the committed tree
#   ./scripts/release.sh "Fix blitz banner"    # bundles staged/working changes under that message
#
# Any working-tree changes are committed with the given message (or a default
# "Release vX.Y.Z"). Deploy only happens after GitHub CI goes green.
set -euo pipefail

# This VPS's tool locations (flutter / firebase are not on the default PATH).
export PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$PATH"

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
sha="$(git rev-parse HEAD)"

echo "==> GitHub CI check (${sha})"
./scripts/check_ci.sh "$sha"

echo "==> Build web"
flutter build web --no-tree-shake-icons

echo "==> Deploy to prod"
firebase deploy --only hosting,firestore:rules,firestore:indexes

echo "==> Released v${new_version} -> https://roadmate.club"
