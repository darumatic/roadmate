#!/usr/bin/env bash
# Poll the Web Release pipeline (the deploy path) for a commit until it
# finishes. Exits 0 when the release landed, non-zero otherwise. The repo is
# public, so no auth token is needed (uses the REST API via curl + jq).
#
#   ./scripts/check_ci.sh <sha>      # defaults to current HEAD
set -euo pipefail

# The API's head_sha filter only matches the full 40-char sha — a short sha
# silently matches no runs and the loop polls "queued" until it times out.
sha="$(git rev-parse "${1:-HEAD}")"
repo="darumatic/roadmate"
api="https://api.github.com/repos/${repo}/actions/workflows/web-release.yml/runs?head_sha=${sha}"

# ~40 min ceiling (160 * 15s): the pipeline compiles the web app twice (the
# visual-verification gate, then the deploy build), so a green run takes
# ~15-20 min. A freshly pushed run may not appear for a few seconds; an empty
# result is treated as "still queued" and keeps polling.
for i in $(seq 1 160); do
  resp="$(curl -s "$api")"
  status="$(echo "$resp" | jq -r '.workflow_runs[0].status // "queued"')"
  conclusion="$(echo "$resp" | jq -r '.workflow_runs[0].conclusion // ""')"
  url="$(echo "$resp" | jq -r '.workflow_runs[0].html_url // ""')"

  if [ "$status" = "completed" ]; then
    if [ "$conclusion" = "success" ]; then
      echo "Web release landed: $url"
      exit 0
    fi
    echo "Web release failed ($conclusion): $url" >&2
    exit 1
  fi

  echo "  Web Release ${status}... (${i}/160)"
  sleep 15
done

echo "Timed out waiting for the Web Release run on ${sha}" >&2
exit 1
