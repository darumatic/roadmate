#!/usr/bin/env bash
# The GitHub security settings of this repository, as code.
#
#   ./scripts/github_security.sh            # --check: report drift, change nothing
#   ./scripts/github_security.sh --apply    # set everything, then check
#
# Exit 0 = everything as expected · 1 = drift · 2 = could not run.
#
# Why this exists: these settings live in GitHub, not in the repo, and NOTHING
# re-applies them — no organization security configuration is attached to this
# repository. For months the docs said CodeQL was kept on org-side while the
# API had it "not-configured" with no analysis ever uploaded. A setting nobody
# can see drifts silently; this makes the intended state readable, checkable
# and reproducible (a transferred or re-created repo is one --apply away).
#
# Needs `gh` signed in as a repository admin (token scope: repo) and `jq`.
#
# Deliberately NOT here — do not "fix" these:
#  * Non-provider patterns, validity checks, AI secret detection, custom
#    patterns, delegated bypass: part of the paid GitHub Secret Protection
#    product. The org is on the Free plan, where a public repo gets secret
#    scanning + push protection only — the API answers 200 to those toggles
#    and silently leaves them disabled.
#  * CodeQL languages java-kotlin and swift: CodeQL has to BUILD them, its
#    autobuild cannot build a Flutter project's android/ and ios/ folders, and a
#    failed scan blocks every release at the pipeline's CodeQL gate (the
#    unattended issue auto-fixer's too). They are four files of boilerplate.
#    Dart is not a CodeQL language at all.
#  * A pull-request requirement on master: releases ARE direct pushes
#    (scripts/release.sh, the auto-fixer). The ruleset below only blocks
#    force-pushes and deletion, which nothing in the tooling does.
#  * The Actions "require SHA pinning" policy: the pins are enforced by
#    test/release_pipeline_test.dart instead, because the policy's effect on
#    GitHub's own dynamic workflows (CodeQL default setup) is not worth
#    finding out on a release.
set -euo pipefail

REPO="${GITHUB_SECURITY_REPO:-darumatic/roadmate}"
API="repos/${REPO}"
RULESET_NAME="Protect master: no force-push, no deletion"
CODEQL_LANGUAGES=(actions javascript-typescript python)
CODEQL_FORBIDDEN=(java-kotlin swift)

mode="--check"
case "${1:-}" in
  ""|--check) ;;
  --apply) mode="--apply" ;;
  *) echo "usage: $0 [--check|--apply]" >&2; exit 2 ;;
esac

for tool in gh jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "could not run: $tool is not installed" >&2
    exit 2
  fi
done

# Reads an endpoint, or gives up: a setting that cannot be read is NOT a
# setting that is fine, so an API failure never counts as "ok".
get() {
  local out
  if ! out="$(gh api "$1" 2>&1)"; then
    echo "could not run: gh api $1 failed: ${out}" >&2
    exit 2
  fi
  printf '%s' "$out"
}

drift=0
expect() {  # expect <label> <actual> <wanted>
  if [ "$2" = "$3" ]; then
    echo "  ok     $1 = $2"
  else
    echo "  DRIFT  $1 = ${2:-<unset>} (want $3)"
    drift=1
  fi
}

# The id of an ACTIVE ruleset on the default branch that blocks both deletion
# and force-pushes, or nothing. Matched by what it does, not by its name.
protecting_ruleset() {
  local id detail
  for id in $(get "${API}/rulesets" | jq -r '.[] | select(.enforcement == "active" and .target == "branch") | .id'); do
    detail="$(get "${API}/rulesets/${id}")"
    if echo "$detail" | jq -e '
        (.conditions.ref_name.include // [] | any(. == "~DEFAULT_BRANCH" or . == "refs/heads/master"))
        and ([.rules[].type] | (index("deletion") != null and index("non_fast_forward") != null))
      ' >/dev/null; then
      echo "$id"
      return
    fi
  done
}

apply() {
  echo "==> Applying the security settings to ${REPO}"
  gh api -X PATCH "$API" --input - >/dev/null <<'JSON'
{ "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" } } }
JSON
  gh api -X PUT "${API}/vulnerability-alerts" >/dev/null
  gh api -X PUT "${API}/automated-security-fixes" >/dev/null
  gh api -X PUT "${API}/private-vulnerability-reporting" >/dev/null
  gh api -X PUT "${API}/actions/permissions/workflow" \
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false >/dev/null
  gh api -X PUT "${API}/actions/permissions/fork-pr-contributor-approval" \
    -f approval_policy=all_external_contributors >/dev/null

  local args=(-f state=configured -f query_suite=extended)
  local lang
  for lang in "${CODEQL_LANGUAGES[@]}"; do args+=(-f "languages[]=${lang}"); done
  gh api -X PATCH "${API}/code-scanning/default-setup" "${args[@]}" >/dev/null

  if [ -z "$(protecting_ruleset)" ]; then
    gh api -X POST "${API}/rulesets" --input - >/dev/null <<JSON
{ "name": "${RULESET_NAME}", "target": "branch", "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" } ] }
JSON
  fi
}

check() {
  echo "==> GitHub security settings of ${REPO}"
  local repo setup workflow languages lang

  repo="$(get "$API")"
  expect "secret scanning" \
    "$(echo "$repo" | jq -r '.security_and_analysis.secret_scanning.status // ""')" enabled
  expect "secret scanning push protection" \
    "$(echo "$repo" | jq -r '.security_and_analysis.secret_scanning_push_protection.status // ""')" enabled
  expect "Dependabot security updates" \
    "$(echo "$repo" | jq -r '.security_and_analysis.dependabot_security_updates.status // ""')" enabled

  # 204 when on, 404 when off — so this one is asked without get()'s give-up.
  if gh api "${API}/vulnerability-alerts" >/dev/null 2>&1; then
    expect "Dependabot alerts" enabled enabled
  else
    expect "Dependabot alerts" disabled enabled
  fi

  expect "private vulnerability reporting" \
    "$(get "${API}/private-vulnerability-reporting" | jq -r '.enabled')" true

  setup="$(get "${API}/code-scanning/default-setup")"
  expect "CodeQL default setup" "$(echo "$setup" | jq -r '.state')" configured
  expect "CodeQL query suite" "$(echo "$setup" | jq -r '.query_suite')" extended
  languages="$(echo "$setup" | jq -r '.languages | join(" ")')"
  for lang in "${CODEQL_LANGUAGES[@]}"; do
    expect "CodeQL analyses ${lang}" \
      "$(case " $languages " in *" $lang "*) echo yes ;; *) echo no ;; esac)" yes
  done
  for lang in "${CODEQL_FORBIDDEN[@]}"; do
    # Must stay off: it cannot be built here, and a failed scan blocks releases.
    expect "CodeQL analyses ${lang}" \
      "$(case " $languages " in *" $lang "*) echo yes ;; *) echo no ;; esac)" no
  done

  workflow="$(get "${API}/actions/permissions/workflow")"
  expect "default workflow token" \
    "$(echo "$workflow" | jq -r '.default_workflow_permissions')" read
  expect "Actions may approve pull requests" \
    "$(echo "$workflow" | jq -r '.can_approve_pull_request_reviews')" false
  expect "fork pull requests need approval from" \
    "$(get "${API}/actions/permissions/fork-pr-contributor-approval" | jq -r '.approval_policy')" \
    all_external_contributors

  if [ -n "$(protecting_ruleset)" ]; then
    expect "master blocks force-push and deletion" yes yes
  else
    expect "master blocks force-push and deletion" no yes
  fi
}

if [ "$mode" = "--apply" ]; then apply; fi
check

if [ "$drift" -ne 0 ]; then
  echo "DRIFT: re-apply with $0 --apply (needs repository admin)" >&2
  exit 1
fi
echo "All security settings are as expected."
