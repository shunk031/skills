#!/usr/bin/env bats

readonly MERGE_HANDOFF_CHECK_SCRIPT="$BATS_TEST_DIRNAME/../../skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-merge-handoff-check.sh"
readonly PR_URL="https://github.com/shunk031/skills/pull/999"
readonly REVIEWED_HEAD_SHA="0123456789abcdef0123456789abcdef01234567"

function setup() {
    export GH_STUB_DIR="$BATS_TEST_TMPDIR/gh-bin"
    export GH_CALLS_FILE="$BATS_TEST_TMPDIR/gh-calls"
    export GH_PR_JSON="$BATS_TEST_TMPDIR/pr.json"
    export GH_CHECKS_JSON="$BATS_TEST_TMPDIR/checks.json"
    export GH_CHECKS_EXIT=0
    export PR_URL
    mkdir -p "$GH_STUB_DIR"
    : > "$GH_CALLS_FILE"

    cat > "$GH_STUB_DIR/gh" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$GH_CALLS_FILE"
case "$1 $2" in
    "pr view")
        [[ "$3" == "$PR_URL" ]] || exit 2
        [[ "$4 $5" == '--json state,isDraft,headRefOid,mergeable,mergeStateStatus' ]] || exit 2
        cat "$GH_PR_JSON"
        ;;
    "pr checks")
        [[ "$3" == "$PR_URL" ]] || exit 2
        [[ "$4 $5 $6" == '--required --json name,state' ]] || exit 2
        cat "$GH_CHECKS_JSON"
        exit "$GH_CHECKS_EXIT"
        ;;
    *)
        exit 2
        ;;
esac
EOF
    chmod +x "$GH_STUB_DIR/gh"
    export PATH="$GH_STUB_DIR:$PATH"

    write_pr_metadata OPEN false "$REVIEWED_HEAD_SHA" MERGEABLE CLEAN
    write_required_checks SUCCESS
}

function write_pr_metadata() {
    printf '{"state":"%s","isDraft":%s,"headRefOid":"%s","mergeable":"%s","mergeStateStatus":"%s"}\n' \
        "$1" "$2" "$3" "$4" "$5" > "$GH_PR_JSON"
}

function write_required_checks() {
    printf '[{"name":"required-check","state":"%s"}]\n' "$1" > "$GH_CHECKS_JSON"
}

@test "usage requires a PR URL and reviewed head SHA" {
    run "$MERGE_HANDOFF_CHECK_SCRIPT"

    [ "$status" -eq 2 ]
    [[ "$output" == *'Usage: herdr-merge-handoff-check.sh <pr-url> <reviewed-head-sha>'* ]]
}

@test "draft pull requests fail before checking CI" {
    write_pr_metadata OPEN true "$REVIEWED_HEAD_SHA" MERGEABLE CLEAN

    run "$MERGE_HANDOFF_CHECK_SCRIPT" "$PR_URL" "$REVIEWED_HEAD_SHA"

    [ "$status" -eq 1 ]
    [[ "$output" == *'FAIL: pull request is a draft'* ]]
    [[ "$(< "$GH_CALLS_FILE")" == *'pr view'* ]]
    [[ "$(< "$GH_CALLS_FILE")" != *'pr checks'* ]]
}

@test "a pull request head that differs from the reviewed SHA fails" {
    write_pr_metadata OPEN false "89abcdef0123456789abcdef0123456789abcdef" MERGEABLE CLEAN

    run "$MERGE_HANDOFF_CHECK_SCRIPT" "$PR_URL" "$REVIEWED_HEAD_SHA"

    [ "$status" -eq 1 ]
    [[ "$output" == *'FAIL: pull request head does not match the reviewed SHA'* ]]
    [[ "$(< "$GH_CALLS_FILE")" != *'pr checks'* ]]
}

@test "closed pull requests fail" {
    write_pr_metadata CLOSED false "$REVIEWED_HEAD_SHA" MERGEABLE CLEAN

    run "$MERGE_HANDOFF_CHECK_SCRIPT" "$PR_URL" "$REVIEWED_HEAD_SHA"

    [ "$status" -eq 1 ]
    [[ "$output" == *'FAIL: pull request is not OPEN'* ]]
}

@test "conflicting pull requests fail" {
    write_pr_metadata OPEN false "$REVIEWED_HEAD_SHA" CONFLICTING DIRTY

    run "$MERGE_HANDOFF_CHECK_SCRIPT" "$PR_URL" "$REVIEWED_HEAD_SHA"

    [ "$status" -eq 1 ]
    [[ "$output" == *'FAIL: pull request is not mergeable'* ]]
}

@test "a pull request with a non-clean merge state fails" {
    write_pr_metadata OPEN false "$REVIEWED_HEAD_SHA" MERGEABLE DIRTY

    run "$MERGE_HANDOFF_CHECK_SCRIPT" "$PR_URL" "$REVIEWED_HEAD_SHA"

    [ "$status" -eq 1 ]
    [[ "$output" == *'FAIL: pull request merge state is not CLEAN'* ]]
}

@test "a failing required check prevents merge handoff" {
    write_required_checks FAILURE
    export GH_CHECKS_EXIT=1

    run "$MERGE_HANDOFF_CHECK_SCRIPT" "$PR_URL" "$REVIEWED_HEAD_SHA"

    [ "$status" -eq 1 ]
    [[ "$output" == *'FAIL: one or more required checks are not SUCCESS'* ]]
    [[ "$(< "$GH_CALLS_FILE")" == *'pr checks'* ]]
}

@test "a clean reviewed pull request with successful required checks passes" {
    run "$MERGE_HANDOFF_CHECK_SCRIPT" "$PR_URL" "$REVIEWED_HEAD_SHA"

    [ "$status" -eq 0 ]
    [[ "$output" == 'PASS: pull request is ready for merge handoff.' ]]
    [[ "$(< "$GH_CALLS_FILE")" == *'--required --json name,state'* ]]
}
