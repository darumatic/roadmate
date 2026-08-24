#!/usr/bin/env bash
# Release build of the web app, with the two guards every deploy needs.
# Used by the Web Release pipeline (.github/workflows/web-release.yml) — the
# only path that deploys — and runnable locally for debugging:
#   ./scripts/build_web.sh
set -euo pipefail

# This VPS's tool locations (flutter / dart are not on the default PATH);
# harmless on machines where the directories don't exist (CI, the Mac).
export PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$PATH"

cd "$(dirname "$0")/.."

echo "==> Build web"
flutter build web --no-tree-shake-icons

echo "==> Copy hosted media the web build drops"
# `flutter build web` copies web/ into build/web but silently skips media files
# (verified 27 Jul 2026: every file in web/ came through except the .mp4). One
# of them is load-bearing: the Play Console's foreground-service declaration
# stores https://roadmate.club/fgs-demo.mp4 as the demonstration video, and a
# 404 there during review sinks the submission. So copy them back, and fail the
# build rather than ship one that would break the link.
for media in web/*.mp4; do
  [ -e "$media" ] || continue
  cp "$media" "build/web/$(basename "$media")"
  if [ ! -f "build/web/$(basename "$media")" ]; then
    echo "ERROR: could not stage $media into build/web" >&2
    exit 1
  fi
  echo "    $(basename "$media")"
done

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
# Only actual web plugin implementations appear in the registrant — they
# declare a pluginClass (or default_package fileName) under
# flutter.plugin.platforms.web in their pubspec. Name-matching alone
# false-positived on google_identity_services_web, a plain JS-interop
# package that never registers (broke the v0.1.71 release).
web_plugins="$(python3 - <<'PY'
import json
import pathlib
import re

cfg = json.load(open('.dart_tool/package_config.json'))
for pkg in cfg['packages']:
    name = pkg['name']
    if not name.endswith('_web'):
        continue
    root = pkg['rootUri']
    if root.startswith('file://'):
        root = root[len('file://'):]
    path = pathlib.Path(root)
    if not path.is_absolute():
        path = pathlib.Path('.dart_tool') / path
    try:
        pubspec = (path / 'pubspec.yaml').read_text()
    except OSError:
        continue
    is_web_plugin = re.search(r'^\s+web:\s*$', pubspec, re.M) and (
        'pluginClass:' in pubspec or 'fileName:' in pubspec)
    if is_web_plugin:
        print(name)
PY
)"
missing=0
for pkg in $web_plugins; do
  if ! grep -q "package:${pkg}/" "$registrant"; then
    echo "ERROR: ${pkg} is resolved but not registered in ${registrant}" >&2
    echo "       Stale build cache — run 'flutter clean' and rebuild." >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1

echo "==> Web build ready in build/web"
