#!/usr/bin/env bash
# Google Play release for RoadMate. Runs on the VPS.
#   local checks -> signed AAB -> hand off to Play Console
#
#   ./scripts/release_android.sh
#
# Builds the committed tree at the version in pubspec.yaml. The build number
# after "+" becomes the Android versionCode and must be higher than the last
# bundle uploaded to Play. Run ./scripts/release.sh first to bump the version
# (and release web at the same version), then this script for the AAB.
#
# Signing needs the upload keystore on this machine (both gitignored):
#   android/key.properties   -> keyAlias / keyPassword / storePassword / storeFile
#   the .jks file that key.properties' storeFile points to
#
# After the build, upload the AAB in the Play Console
# (https://play.google.com/console): Production -> Create new release ->
# upload build/app/outputs/bundle/release/app-release.aab -> release notes ->
# roll out. (Automated uploads via the roadmate-play-uploader service account
# can be added once its JSON key is on this machine.)
set -euo pipefail

export PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$PATH"

cd "$(dirname "$0")/.."

version="$(grep -oE '^version: .*' pubspec.yaml | cut -d' ' -f2)"
echo "==> Releasing Android build ${version}"

if [ ! -f android/key.properties ]; then
  echo "ERROR: android/key.properties not found — copy the upload keystore" >&2
  echo "       and key.properties to this machine first (see script header)." >&2
  exit 1
fi
storefile="$(grep -oE '^storeFile=.*' android/key.properties | cut -d= -f2-)"
if [ -z "$storefile" ] || [ ! -f "android/app/$storefile" ] && [ ! -f "$storefile" ]; then
  echo "ERROR: keystore '$storefile' from android/key.properties not found" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "WARNING: working tree is dirty — the AAB will include uncommitted changes." >&2
fi

echo "==> Local checks (analyze + test)"
flutter analyze
flutter test

echo "==> Build signed app bundle"
flutter build appbundle --release
aab="build/app/outputs/bundle/release/app-release.aab"
if [ ! -f "$aab" ]; then
  echo "ERROR: expected bundle not found at ${aab}" >&2
  exit 1
fi

echo "==> Built ${aab} (${version})."
echo "    Upload it in the Play Console: Production -> Create new release (see header)."
