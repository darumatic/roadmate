#!/usr/bin/env bash
# Release cycle for RoadMate. Runs the local steps in order:
#   local tests -> bump patch version -> commit & push
#
#   ./scripts/release.sh                       # cuts a release of the committed tree
#   ./scripts/release.sh "Fix blitz banner"    # bundles staged/working changes under that message
#
# The push IS the release: the Web Release pipeline on GitHub Actions
# (.github/workflows/web-release.yml) runs CodeQL + Flutter CI + Visual
# Verification and, only when all three pass, deploys web + Firestore
# rules/indexes to https://roadmate.club (~15-20 min after the push). The
# terminal never deploys web. Watch the pipeline with scripts/check_ci.sh;
# store builds are a separate manual step (Actions -> Mobile Release).
#
# Any working-tree changes are committed with the given message (or a default
# "Release vX.Y.Z").
set -euo pipefail

# This VPS's tool locations (flutter / dart are not on the default PATH).
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

echo "==> Pushed v${new_version}. The Web Release pipeline deploys from here:"
echo "    https://github.com/darumatic/roadmate/actions/workflows/web-release.yml"
echo "    ./scripts/check_ci.sh   # blocks until the deploy lands (or fails)"
