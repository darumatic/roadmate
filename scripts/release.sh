#!/usr/bin/env bash
# Release RoadMate: bump the patch version, rebuild web, deploy to Firebase, and
# commit + push the version bump. One command per release.
#
#   ./scripts/release.sh
set -euo pipefail

# This VPS's tool locations (flutter / flutterfire are not on the default PATH).
export PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$PATH"

cd "$(dirname "$0")/.."

echo "==> Bumping version"
dart run tool/bump_version.dart
new_version="$(grep -oE "appVersion = '[^']+'" lib/version.dart | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")"
echo "    now v${new_version}"

echo "==> Building web"
flutter build web --no-tree-shake-icons

echo "==> Deploying to Firebase"
firebase deploy --only hosting,firestore:rules,firestore:indexes

echo "==> Committing version bump"
git add pubspec.yaml lib/version.dart
git commit -m "Release v${new_version}"
git push

echo "==> Released v${new_version}"
