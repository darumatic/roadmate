#!/usr/bin/env bash
# Apple (App Store) release for RoadMate. Runs on the Mac (the VPS only does web).
#   local checks -> iOS config regen -> signed IPA -> upload to App Store Connect
#
#   ./scripts/release_ios.sh
#
# Builds the committed tree at the version in pubspec.yaml (the build number
# after "+" must be higher than the last build uploaded to App Store Connect).
#
# Upload: if App Store Connect API key env vars are set (ASC_KEY_ID and
# ASC_ISSUER_ID, with AuthKey_<ASC_KEY_ID>.p8 in ~/.appstoreconnect/private_keys/)
# the IPA is uploaded from the CLI via altool; otherwise it is handed to the
# Transporter app for a manual upload.
#
# After the upload, finish in App Store Connect (https://appstoreconnect.apple.com):
# wait for the build to finish processing, attach it to the app version,
# fill in release notes, and submit for review.
set -euo pipefail

cd "$(dirname "$0")/.."

version="$(grep -oE '^version: .*' pubspec.yaml | cut -d' ' -f2)"
echo "==> Releasing iOS build ${version}"

if [ -n "$(git status --porcelain)" ]; then
  echo "WARNING: working tree is dirty — the IPA will include uncommitted changes." >&2
fi

echo "==> Local checks (analyze + test)"
flutter analyze
flutter test

# A 'flutter build web' resets the generated Swift package back to iOS 13,
# which breaks the Firebase plugins (they need 15). Regenerate the iOS config
# before every store build.
echo "==> Regenerate iOS build config"
flutter build ios --config-only

echo "==> Build signed IPA"
flutter build ipa
ipa="build/ios/ipa/roadmate.ipa"
if [ ! -f "$ipa" ]; then
  echo "ERROR: expected IPA not found at ${ipa}" >&2
  exit 1
fi

echo "==> Upload to App Store Connect"
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
  xcrun altool --upload-app --type ios -f "$ipa" \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "==> Uploaded ${version}. Finish the release in App Store Connect (see header)."
else
  echo "    No ASC_KEY_ID/ASC_ISSUER_ID set — opening the IPA in Transporter."
  open -a Transporter "$ipa"
  echo "==> Deliver ${ipa} in Transporter, then finish in App Store Connect (see header)."
fi
