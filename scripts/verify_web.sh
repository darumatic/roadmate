#!/usr/bin/env bash
# Deterministic web verification: compiles the app and drives it in real
# headless Chrome via the integration_test suite (integration_test/app_test.dart),
# writing screenshots to build/integration_screenshots/.
#
# Used by .github/workflows/nightly-visual.yml and runnable on the VPS:
#   ./scripts/verify_web.sh
#
# Chromedriver/Chrome resolution:
#   - CI (ubuntu-latest) exports CHROMEWEBDRIVER with a chromedriver matched to
#     the preinstalled Chrome — used as-is.
#   - Elsewhere (this VPS has no system Chrome) a matched Chrome-for-Testing +
#     chromedriver pair is installed once via @puppeteer/browsers into
#     ~/.cache/roadmate-verify and reused.
set -euo pipefail

# This VPS's tool locations (flutter / dart are not on the default PATH).
export PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$PATH"

cd "$(dirname "$0")/.."

CACHE="${VERIFY_BROWSER_CACHE:-$HOME/.cache/roadmate-verify}"
DRIVER_PORT=4444

if [ -n "${CHROMEWEBDRIVER:-}" ] && [ -x "$CHROMEWEBDRIVER/chromedriver" ]; then
  DRIVER="$CHROMEWEBDRIVER/chromedriver"
else
  mkdir -p "$CACHE/bin"
  DRIVER="$(find "$CACHE" -type f -name chromedriver 2>/dev/null | head -1)"
  CHROME="$(find "$CACHE" -type f -name chrome -path '*chrome-linux64*' 2>/dev/null | head -1)"
  if [ -z "$DRIVER" ] || [ -z "$CHROME" ]; then
    echo "==> Installing Chrome-for-Testing + chromedriver into $CACHE"
    (cd "$CACHE" && npx --yes @puppeteer/browsers install chrome@stable \
                 && npx --yes @puppeteer/browsers install chromedriver@stable)
    DRIVER="$(find "$CACHE" -type f -name chromedriver | head -1)"
    CHROME="$(find "$CACHE" -type f -name chrome -path '*chrome-linux64*' | head -1)"
  fi
  # chromedriver discovers the browser as google-chrome on PATH.
  ln -sf "$CHROME" "$CACHE/bin/google-chrome"
  export PATH="$CACHE/bin:$PATH"
  export CHROME_EXECUTABLE="$CHROME"
fi

echo "==> chromedriver: $DRIVER"
"$DRIVER" --port=$DRIVER_PORT &
DRIVER_PID=$!
trap 'kill $DRIVER_PID 2>/dev/null || true' EXIT
sleep 2

rm -rf build/integration_screenshots

# Chrome refuses to run sandboxed as root (the VPS case); harmless elsewhere.
echo "==> flutter drive (web-server + headless Chrome)"
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart \
  -d web-server \
  --browser-name=chrome \
  --driver-port=$DRIVER_PORT \
  --web-browser-flag=--no-sandbox \
  --no-pub

echo "==> Screenshots:"
ls -l build/integration_screenshots/
