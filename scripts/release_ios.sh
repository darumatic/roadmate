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
# the IPA is uploaded from the CLI via altool, and then scripts/asc_submit.py
# finishes the release in App Store Connect automatically: waits for build
# processing (can take ~1h), sets "What's New" from store/apple_whats_new.txt
# (update that file first), attaches the build and submits for review.
# Without the env vars the IPA is handed to the Transporter app and the ASC
# steps stay manual.
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

# Signing preflight. Both of these have gone missing once (the team's only
# Apple Distribution certificate was revoked, which cascaded and took every
# provisioning profile with it), and the failure only surfaced after a full
# archive build. Fail fast with the fix instead.
echo "==> Signing preflight"
if ! security find-identity -v -p codesigning | grep -q "Apple Distribution: DARUMATIC PTY LTD"; then
  echo "ERROR: no 'Apple Distribution: DARUMATIC PTY LTD' identity in the keychain." >&2
  echo "       Import the .p12 backup, or mint a new certificate — see specs.md" >&2
  echo "       ('iOS signing material')." >&2
  exit 1
fi
if ! grep -qls "RoadMate App Store" \
     "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision; then
  echo "ERROR: the 'RoadMate App Store' provisioning profile is not installed." >&2
  echo "       See specs.md ('iOS signing material') to recreate and install it." >&2
  exit 1
fi

# Manual export options — the automatic export needs an Apple ID signed into
# Xcode.app, which this CLI-only release path does not have. See the comments
# in ios/ExportOptions.plist.
echo "==> Build signed IPA"
flutter build ipa --export-options-plist=ios/ExportOptions.plist
ipa="build/ios/ipa/roadmate.ipa"
if [ ! -f "$ipa" ]; then
  echo "ERROR: expected IPA not found at ${ipa}" >&2
  exit 1
fi

# A CI dry run (Mobile Release workflow) proves the archive + signing without
# an App Store upload or review submission.
if [ "${RELEASE_DRY_RUN:-}" = "1" ]; then
  echo "==> RELEASE_DRY_RUN=1 — skipping the App Store upload."
  exit 0
fi

echo "==> Upload to App Store Connect"
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
  xcrun altool --upload-app --type ios -f "$ipa" \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "==> Uploaded ${version}. Finishing the release in App Store Connect…"
  python3 scripts/asc_submit.py --self-test
  version_name="${version%%+*}"
  build_no="${version##*+}"
  python3 scripts/asc_submit.py --version "$version_name" --build "$build_no"
else
  echo "    No ASC_KEY_ID/ASC_ISSUER_ID set — opening the IPA in Transporter."
  open -a Transporter "$ipa"
  echo "==> Deliver ${ipa} in Transporter, then finish in App Store Connect (see header)."
fi
