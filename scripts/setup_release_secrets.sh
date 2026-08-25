#!/usr/bin/env bash
# One-time (re-runnable) upload of the release credentials as GitHub Actions
# secrets on darumatic/roadmate, so the Web Release / Mobile Release
# workflows can deploy. Machine-aware — run it once on each box:
#
#   Linux (the VPS)  -> web + Android secrets, from this machine's files:
#     FIREBASE_SERVICE_ACCOUNT         ~/.config/roadmate/firebase-adminsdk.json
#     NTFY_TOPIC                       ~/.config/roadmate/ntfy_topic (optional)
#     PLAY_SERVICE_ACCOUNT_JSON        ~/.config/roadmate/google-play-service-account.json
#     ANDROID_KEYSTORE_BASE64          the keystore android/key.properties points at
#     ANDROID_STORE_PASSWORD           storePassword from android/key.properties
#     ANDROID_KEY_PASSWORD             keyPassword from android/key.properties
#
#   Darwin (the Mac) -> iOS signing secrets (see specs.md "iOS signing material"):
#     IOS_DIST_P12_BASE64              newest ~/.config/roadmate/apple_distribution*.p12
#     IOS_DIST_P12_PASSWORD            login-keychain item 'roadmate-dist-p12'
#     IOS_PROVISIONING_PROFILE_BASE64  the installed 'RoadMate App Store' profile
#     ASC_KEY_ID                       $ASC_KEY_ID, or derived from a single
#                                      ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8
#     ASC_ISSUER_ID                    $ASC_ISSUER_ID (required env)
#     ASC_PRIVATE_KEY                  the AuthKey_<ID>.p8 contents
#
# Values never touch argv or the terminal — everything is piped straight into
# `gh secret set`. Needs an authenticated `gh`. Re-run whenever a credential
# rotates.
set -euo pipefail

repo="darumatic/roadmate"
cd "$(dirname "$0")/.."

command -v gh >/dev/null || { echo "ERROR: gh (GitHub CLI) is required." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not authenticated (run: gh auth login)." >&2; exit 1; }

set_secret() { # usage: <producer> | set_secret NAME
  gh secret set "$1" --repo "$repo"
  echo "    $1"
}

b64() { base64 < "$1" | tr -d '\n'; }

os="$(uname)"
if [ "$os" = "Linux" ]; then
  echo "==> Linux (VPS): uploading web + Android release secrets"

  fb="$HOME/.config/roadmate/firebase-adminsdk.json"
  [ -f "$fb" ] || { echo "ERROR: $fb not found." >&2; exit 1; }
  set_secret FIREBASE_SERVICE_ACCOUNT < "$fb"

  # Release alerts from CI (web + store). Optional: without it notify.py is a
  # silent no-op, so a missing topic must not fail the setup.
  ntfy="$HOME/.config/roadmate/ntfy_topic"
  if [ -s "$ntfy" ]; then
    tr -d '\n' < "$ntfy" | set_secret NTFY_TOPIC
  else
    echo "    (no $ntfy — release alerts from CI stay off)"
  fi

  play="$HOME/.config/roadmate/google-play-service-account.json"
  [ -f "$play" ] || { echo "ERROR: $play not found." >&2; exit 1; }
  set_secret PLAY_SERVICE_ACCOUNT_JSON < "$play"

  props="android/key.properties"
  [ -f "$props" ] || { echo "ERROR: $props not found (the owner restores it — see CLAUDE.md)." >&2; exit 1; }
  storefile="$(grep -oE '^storeFile=.*' "$props" | cut -d= -f2-)"
  [ -f "$storefile" ] || storefile="android/app/$storefile"
  [ -f "$storefile" ] || { echo "ERROR: keystore named by $props not found." >&2; exit 1; }
  b64 "$storefile" | set_secret ANDROID_KEYSTORE_BASE64
  grep -oE '^storePassword=.*' "$props" | cut -d= -f2- | tr -d '\n' | set_secret ANDROID_STORE_PASSWORD
  grep -oE '^keyPassword=.*' "$props" | cut -d= -f2- | tr -d '\n' | set_secret ANDROID_KEY_PASSWORD

elif [ "$os" = "Darwin" ]; then
  echo "==> Mac: uploading iOS signing secrets"

  p12="$(ls -t "$HOME/.config/roadmate/"apple_distribution*.p12 2>/dev/null | head -1)"
  [ -n "$p12" ] || { echo "ERROR: no apple_distribution*.p12 in ~/.config/roadmate (see specs.md, 'iOS signing material')." >&2; exit 1; }
  echo "    using $p12"
  b64 "$p12" | set_secret IOS_DIST_P12_BASE64
  security find-generic-password -s roadmate-dist-p12 -w >/dev/null \
    || { echo "ERROR: keychain item 'roadmate-dist-p12' not found (see specs.md)." >&2; exit 1; }
  security find-generic-password -s roadmate-dist-p12 -w | tr -d '\n' | set_secret IOS_DIST_P12_PASSWORD

  profile="$(grep -ls "RoadMate App Store" \
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision 2>/dev/null | head -1)"
  [ -n "$profile" ] || { echo "ERROR: the 'RoadMate App Store' profile is not installed (see specs.md)." >&2; exit 1; }
  echo "    using $profile"
  b64 "$profile" | set_secret IOS_PROVISIONING_PROFILE_BASE64

  keydir="$HOME/.appstoreconnect/private_keys"
  if [ -z "${ASC_KEY_ID:-}" ]; then
    ASC_KEY_ID="$(ls "$keydir"/AuthKey_*.p8 2>/dev/null | sed -E 's/.*AuthKey_(.*)\.p8/\1/' | head -1)"
  fi
  [ -n "${ASC_KEY_ID:-}" ] || { echo "ERROR: set ASC_KEY_ID (no AuthKey_*.p8 found in $keydir)." >&2; exit 1; }
  [ -n "${ASC_ISSUER_ID:-}" ] || { echo "ERROR: set ASC_ISSUER_ID (App Store Connect -> Users and Access -> Integrations)." >&2; exit 1; }
  p8="$keydir/AuthKey_${ASC_KEY_ID}.p8"
  [ -f "$p8" ] || { echo "ERROR: $p8 not found." >&2; exit 1; }
  printf '%s' "$ASC_KEY_ID" | set_secret ASC_KEY_ID
  printf '%s' "$ASC_ISSUER_ID" | set_secret ASC_ISSUER_ID
  set_secret ASC_PRIVATE_KEY < "$p8"

else
  echo "ERROR: unsupported OS '$os' — run on the VPS (Linux) or the Mac (Darwin)." >&2
  exit 1
fi

echo "==> Done. Current repo secrets:"
gh secret list --repo "$repo"
