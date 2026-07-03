#!/usr/bin/env bash
# Poll GitHub Actions until the "Flutter CI" run for a commit SHA finishes.
# Exits 0 if it succeeded, non-zero otherwise. The repo is public, so no auth
# token is needed (uses the REST API via curl + jq).
#
#   ./scripts/check_ci.sh <sha>      # defaults to current HEAD
set -euo pipefail

sha="${1:-$(git rev-parse HEAD)}"
repo="darumatic/roadmate"
api="https://api.github.com/repos/${repo}/actions/runs?head_sha=${sha}"

# ~15 min ceiling (60 * 15s). A freshly pushed run may not appear for a few
# seconds; an empty result is treated as "still queued" and keeps polling.
for i in $(seq 1 60); do
  resp="$(curl -s "$api")"
  status="$(echo "$resp" | jq -r '.workflow_runs[0].status // "queued"')"
  conclusion="$(echo "$resp" | jq -r '.workflow_runs[0].conclusion // ""')"
  url="$(echo "$resp" | jq -r '.workflow_runs[0].html_url // ""')"

  if [ "$status" = "completed" ]; then
    if [ "$conclusion" = "success" ]; then
      echo "CI passed: $url"
      exit 0
    fi
    echo "CI failed ($conclusion): $url" >&2
    exit 1
  fi

  echo "  CI ${status}... (${i}/60)"
  sleep 15
done

echo "Timed out waiting for CI on ${sha}" >&2
exit 1
