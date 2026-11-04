#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-merge-handoff-check.sh
# @brief Check whether a reviewed pull request is ready for merge handoff.
# @description
#   Requires an open, ready, clean pull request whose head matches the accepted
#   review, with every required check successful.
# @arg $1 pr_url GitHub pull request URL.
# @arg $2 reviewed_head_sha Exact head SHA accepted by independent review.
# @stdout One-line result describing whether the pull request passes the gate.
# @exitcode 0 The pull request is ready for merge handoff.
# @exitcode 1 The pull request does not pass the gate or could not be checked.
# @exitcode 2 The invocation is invalid.

set -Eeuo pipefail

# @arg $1 reason One-line reason that the merge gate failed.
function fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

if [[ $# -ne 2 || -z "$1" || -z "$2" ]]; then
    printf '%s\n' 'Usage: herdr-merge-handoff-check.sh <pr-url> <reviewed-head-sha>' >&2
    exit 2
fi

pr_url="$1"
reviewed_head_sha="$2"

command -v gh > /dev/null 2>&1 || fail 'gh is required'
command -v jq > /dev/null 2>&1 || fail 'jq is required'

if ! pr_json="$(gh pr view "$pr_url" --json state,isDraft,headRefOid,mergeable,mergeStateStatus 2> /dev/null)"; then
    fail 'could not read pull request metadata'
fi

if ! jq -e '
    type == "object" and
    (.state | type == "string") and
    (.isDraft | type == "boolean") and
    (.headRefOid | type == "string") and
    (.mergeable | type == "string") and
    (.mergeStateStatus | type == "string")
' > /dev/null 2>&1 <<< "$pr_json"; then
    fail 'pull request metadata is incomplete'
fi

pr_state="$(jq -r '.state' <<< "$pr_json")"
is_draft="$(jq -r '.isDraft' <<< "$pr_json")"
head_sha="$(jq -r '.headRefOid' <<< "$pr_json")"
mergeable="$(jq -r '.mergeable' <<< "$pr_json")"
merge_state="$(jq -r '.mergeStateStatus' <<< "$pr_json")"

[[ "$pr_state" == 'OPEN' ]] || fail 'pull request is not OPEN'
[[ "$is_draft" == 'false' ]] || fail 'pull request is a draft'
[[ "$head_sha" == "$reviewed_head_sha" ]] || fail 'pull request head does not match the reviewed SHA'
[[ "$mergeable" == 'MERGEABLE' ]] || fail 'pull request is not mergeable'
[[ "$merge_state" == 'CLEAN' ]] || fail 'pull request merge state is not CLEAN'

checks_exit=0
if checks_json="$(gh pr checks "$pr_url" --required --json name,state 2> /dev/null)"; then
    checks_exit=0
else
    checks_exit=$?
fi

if ! jq -e '
    type == "array" and
    all(.[]; (.name | type == "string") and (.state | type == "string"))
' > /dev/null 2>&1 <<< "$checks_json"; then
    fail 'could not read required check statuses'
fi

if ! jq -e 'all(.[]; .state == "SUCCESS")' > /dev/null 2>&1 <<< "$checks_json"; then
    fail 'one or more required checks are not SUCCESS'
fi

[[ "$checks_exit" -eq 0 ]] || fail 'gh did not report successful required checks'

printf '%s\n' 'PASS: pull request is ready for merge handoff.'
