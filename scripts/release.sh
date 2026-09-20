#!/usr/bin/env bash
# Release cycle for RoadMate. Runs the local steps in order:
#   local tests -> bump the version (patch by default) -> commit & push
#
#   ./scripts/release.sh                       # cuts a release of the committed tree
#   ./scripts/release.sh "Fix blitz banner"    # bundles staged/working changes under that message
#   ./scripts/release.sh --minor "..."         # 1.0.27 -> 1.1.0 (--major: -> 2.0.0); default is a patch
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

# Which part of x.y.z this release bumps. Patch unless asked: the unattended
# issue auto-fixer calls this script with a message only, and must never be
# able to move the minor or major version by accident.
bump="patch"
case "${1:-}" in
  --minor) bump="minor"; shift ;;
  --major) bump="major"; shift ;;
  --*) echo "usage: $0 [--minor|--major] [message]" >&2; exit 64 ;;
esac

msg="${1:-}"

# The issue auto-fixer pushes to master on its own (scripts/fix_issues.py), so
# this workspace goes stale without anyone touching it. Rebase FIRST: bumping
# the version on a stale base produces a duplicate version and a push that is
# rejected only after the whole suite has run (seen twice on 2026-08-25).
echo "==> Sync with origin/master"
git fetch origin
if [ -n "$(git status --porcelain)" ]; then
  # Uncommitted work: rebase it across on a stash so the bump lands on top of
  # whatever the bot released while we were working.
  git stash push -u -m "release.sh autostash" >/dev/null
  trap 'git stash pop >/dev/null 2>&1 || true' EXIT
  git rebase origin/master
  git stash pop >/dev/null
  trap - EXIT
else
  git rebase origin/master
fi

echo "==> Local checks (analyze + test)"
flutter analyze
flutter test

echo "==> Bump ${bump} version"
dart run tool/bump_version.dart "$bump"
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
