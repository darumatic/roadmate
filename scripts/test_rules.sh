#!/usr/bin/env bash
# Verifies firestore.rules against the Firestore emulator using the official
# @firebase/rules-unit-testing harness (test/rules/rules_test.mjs).
# Requirements: Node, and Java 21+ for the emulator. Not run by `flutter test`,
# but CI runs the same suite (rules-test job in flutter-ci.yml). Run this
# locally whenever firestore.rules changes, before deploying.
set -euo pipefail

export PATH="/opt/flutter/bin:$HOME/.pub-cache/bin:$PATH"
cd "$(dirname "$0")/.."

(cd test/rules && { [ -d node_modules ] || npm install --no-audit --no-fund; })

firebase emulators:exec --only firestore "node test/rules/rules_test.mjs"
