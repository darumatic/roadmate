#!/usr/bin/env bash
# Verifies firestore.rules against the Firestore emulator using the official
# @firebase/rules-unit-testing harness (test/rules/rules_test.mjs).
# Requirements: Node, and Java 21+ for the emulator (a Homebrew keg-only JDK
# is picked up automatically — see below). Not run by `flutter test`, but CI
# runs the same suite (rules-test job in flutter-ci.yml). Run this locally
# whenever firestore.rules changes, before deploying.
set -euo pipefail

export PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$PATH"
cd "$(dirname "$0")/.."

# firebase-tools refuses to start the emulator on Java < 21. On the Mac that
# bites even with a modern JDK installed: Homebrew keeps `openjdk` keg-only
# (never on PATH) and the older openjdk@11/@17 kegs look identical from here.
# So: if the java on PATH is missing or too old, adopt the newest candidate
# keg that qualifies. No candidate exists on the Linux VPS or in CI, where the
# system java is already current — this whole block is then a no-op.
java_major() {  # "openjdk version "26.0.2"" -> 26; "1.8.0_292" -> 8
  local v
  v="$("$1" -version 2>&1 | head -1 | grep -oE '"[0-9]+(\.[0-9]+)?' | tr -d '"')"
  case "$v" in
    1.*) echo "${v#1.}" ;;
    "")  echo 0 ;;
    *)   echo "${v%%.*}" ;;
  esac
}

if ! command -v java >/dev/null || [ "$(java_major java)" -lt 21 ]; then
  for candidate in /opt/homebrew/opt/openjdk/bin/java \
                   /usr/local/opt/openjdk/bin/java \
                   /opt/homebrew/opt/openjdk@2*/bin/java \
                   /usr/local/opt/openjdk@2*/bin/java; do
    [ -x "$candidate" ] || continue
    [ "$(java_major "$candidate")" -ge 21 ] || continue
    export PATH="$(dirname "$candidate"):$PATH"
    echo "==> Using Java $(java_major java) from $(dirname "$candidate")"
    break
  done
fi

if ! command -v java >/dev/null || [ "$(java_major java)" -lt 21 ]; then
  found="$(java -version 2>&1 | head -1 || true)"
  echo "ERROR: the Firestore emulator needs Java 21+ (found: ${found:-no java on PATH})" >&2
  echo "       macOS: brew install openjdk    Linux: install a JDK 21+ package" >&2
  exit 1
fi

(cd test/rules && { [ -d node_modules ] || npm install --no-audit --no-fund; })

firebase emulators:exec --only firestore "node test/rules/rules_test.mjs"
