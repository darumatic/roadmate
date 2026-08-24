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
# Upload: if the roadmate-play-uploader service-account key exists at
# ~/.config/roadmate/google-play-service-account.json the AAB is uploaded and
# rolled out to the production track automatically via scripts/play_upload.py
# (release notes from store/google_play_release_notes.txt — update that file
# first). Without the key it falls back to a manual Play Console upload:
# Production -> Create new release -> upload the AAB -> notes -> roll out.
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

# A CI dry run (Mobile Release workflow) proves the build + signing without
# consuming a Play upload.
if [ "${RELEASE_DRY_RUN:-}" = "1" ]; then
  echo "==> RELEASE_DRY_RUN=1 — skipping the Play upload."
  exit 0
fi

sa_key="$HOME/.config/roadmate/google-play-service-account.json"
if [ -f "$sa_key" ]; then
  echo "==> Upload to Google Play (production)"
  python3 scripts/play_upload.py --self-test
  version_name="${version%%+*}"
  build_no="${version##*+}"
  python3 scripts/play_upload.py --aab "$aab" --name "${version_name} (${build_no})"
else
  echo "    No service-account key at ${sa_key} — upload the AAB in the"
  echo "    Play Console: Production -> Create new release (see header)."
fi
