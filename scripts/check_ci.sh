#!/usr/bin/env bash
# Poll the Web Release pipeline (the deploy path) for a commit until it
# finishes. Exits 0 when the release landed, non-zero otherwise. The repo is
# public, so no auth token is *needed* (REST API via curl + jq) — but one is
# used when it is at hand, because of GitHub's rate limit (see below).
#
#   ./scripts/check_ci.sh <sha>      # defaults to current HEAD
#
# Output contract (scripts/fix_issues.py's classify_check_ci parses it): exit 0
# = deployed; "Timed out ..." = never saw the run finish; anything else = red.
set -euo pipefail

# The API's head_sha filter only matches the full 40-char sha — a short sha
# silently matches no runs and the loop polls "queued" until it times out.
sha="$(git rev-parse "${1:-HEAD}")"
repo="darumatic/roadmate"
api="https://api.github.com/repos/${repo}/actions/workflows/web-release.yml/runs?head_sha=${sha}"

# GitHub allows an anonymous caller 60 requests an HOUR (per IP), a signed-in
# one 5,000. A green run takes ~15-20 min, so the old fixed 15 s cadence spent
# the whole anonymous allowance in 15 minutes — right as the release finished
# — and every request after that came back 403. So: borrow a token when one
# exists (the environment's, else gh's own) and keep the fast cadence;
# otherwise poll once a minute, which the allowance can sustain.
token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$token" ] && command -v gh >/dev/null 2>&1; then
  token="$(gh auth token 2>/dev/null || true)"
fi
if [ -n "$token" ]; then interval=15; else interval=60; fi

# ~40 min ceiling whatever the cadence: the pipeline compiles the web app
# twice (the visual-verification gate, then the deploy build).
polls=$((2400 / interval))

fetch() {  # prints the response body, then the HTTP status on its own line
  if [ -n "$token" ]; then
    curl -s -w '\n%{http_code}' -H "Authorization: Bearer ${token}" "$api"
  else
    curl -s -w '\n%{http_code}' "$api"
  fi
}

i=0
while [ "$i" -lt "$polls" ]; do
  i=$((i + 1))
  out="$(fetch || true)"
  code="${out##*$'\n'}"
  resp="${out%$'\n'*}"

  if [ "$code" != "200" ]; then
    # An API error is NOT "still queued". The old `// "queued"` fallback read
    # a rate-limit 403 as a missing run, so a FAILED release kept reporting
    # "queued" until the 40-minute ceiling. Say what GitHub said, and keep
    # trying — a rate limit lifts, a blip passes.
    message="$(echo "$resp" | jq -r '.message // empty' 2>/dev/null || true)"
    echo "  WARNING: GitHub API answered ${code:-nothing}${message:+: $message} (${i}/${polls})" >&2
    if [ "$code" = "401" ] && [ -n "$token" ]; then
      echo "  WARNING: the token was refused — continuing unauthenticated, once a minute" >&2
      token=""
      # Same ~40 min ceiling at the slower cadence: re-count what is left.
      polls=$((i + (polls - i) * interval / 60))
      interval=60
    fi
    sleep "$interval"
    continue
  fi

  # A freshly pushed run may not exist for a few seconds: no run yet really
  # is "still queued".
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

  echo "  Web Release ${status}... (${i}/${polls})"
  sleep "$interval"
done

echo "Timed out waiting for the Web Release run on ${sha}" >&2
exit 1
