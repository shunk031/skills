#!/usr/bin/env bats

readonly CLEANUP_SCRIPT="${BATS_TEST_DIRNAME}/../../skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-tab-cleanup.sh"

function setup() {
    export TEST_REPO_ROOT="${BATS_TEST_TMPDIR}/repos"
    export MAIN_REPO="${TEST_REPO_ROOT}/main"
    export WORKER_WORKTREE="${TEST_REPO_ROOT}/worker"
    export MERGED_WORKTREE="${TEST_REPO_ROOT}/merged"
    export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
    export HERDR_TEST_TABS="${BATS_TEST_TMPDIR}/tabs.json"
    export HERDR_TEST_PANES="${BATS_TEST_TMPDIR}/panes.json"
    export HERDR_TEST_AGENTS="${BATS_TEST_TMPDIR}/agents.json"
    export HERDR_TEST_CLOSES="${BATS_TEST_TMPDIR}/closed-tabs"
    export HERDR_TEST_TAB_CALLS="${BATS_TEST_TMPDIR}/tab-list-calls"
    export HERDR_TEST_AGENT_CALLS="${BATS_TEST_TMPDIR}/agent-list-calls"
    export HERDR_TEST_PANE_READS="${BATS_TEST_TMPDIR}/pane-reads"
    export HERDR_TEST_GH_CALLS="${BATS_TEST_TMPDIR}/gh-calls"
    export HERDR_TEST_FINAL_AGENT_READ="${BATS_TEST_TMPDIR}/final-agent-read"
    export HERDR_ENV=1
    export HERDR_PANE_ID=caller-pane
    export HERDR_TAB_ID=caller-tab
    export HERDR_TAB_CLEANUP_STATE_DIR="${BATS_TEST_TMPDIR}/state/herdr-tab-cleanup"

    mkdir -p "$MAIN_REPO" "$TEST_BIN"
    git -C "$MAIN_REPO" init -q -b main
    git -C "$MAIN_REPO" config user.name "Tab Cleanup Test"
    git -C "$MAIN_REPO" config user.email "tab-cleanup@example.invalid"
    printf 'test\n' > "$MAIN_REPO/README.md"
    git -C "$MAIN_REPO" add README.md
    git -C "$MAIN_REPO" commit -qm "initial commit"
    git -C "$MAIN_REPO" worktree add -q -b meta-worker "$WORKER_WORKTREE" HEAD
    git -C "$MAIN_REPO" worktree add -q -b merged-branch "$MERGED_WORKTREE" HEAD

    cat > "$TEST_BIN/herdr" << 'HERDR'
#!/usr/bin/env bash
set -eu
case "$1 $2" in
    "tab list")
        count="$(cat "$HERDR_TEST_TAB_CALLS")"
        count=$((count + 1))
        printf '%s\n' "$count" > "$HERDR_TEST_TAB_CALLS"
        if [ "$count" -gt 1 ] && [ -n "${HERDR_TEST_TABS_AFTER:-}" ]; then
            cat "$HERDR_TEST_TABS_AFTER"
        else
            cat "$HERDR_TEST_TABS"
        fi
        ;;
    "pane list") cat "$HERDR_TEST_PANES" ;;
    "agent list")
        count="$(cat "$HERDR_TEST_AGENT_CALLS")"
        count=$((count + 1))
        printf '%s\n' "$count" > "$HERDR_TEST_AGENT_CALLS"
        if [ -n "${HERDR_TEST_FINAL_AGENT_LIST_AT:-}" ] && [ "$count" -ge "$HERDR_TEST_FINAL_AGENT_LIST_AT" ]; then
            : > "$HERDR_TEST_FINAL_AGENT_READ"
        fi
        if [ -n "${HERDR_TEST_AGENTS_AFTER_CALL:-}" ] && [ "$count" -ge "$HERDR_TEST_AGENTS_AFTER_CALL" ]; then
            cat "$HERDR_TEST_AGENTS_AFTER"
        else
            cat "$HERDR_TEST_AGENTS"
        fi
        ;;
    "pane read")
        printf '%s\t%s\n' "$3" "$(cat "$HERDR_TEST_AGENT_CALLS")" >> "$HERDR_TEST_PANE_READS"
        if [ -f "$HERDR_TEST_FINAL_AGENT_READ" ] && [ "$3" = "worker-pane" ] && [ "${HERDR_TEST_OCCUPY_AFTER_FINAL_READ:-0}" -eq 1 ]; then
            printf '> echo pending\n'
        else
            case "$3" in
                occupied-pane) printf '> echo pending\n' ;;
                unknown-pane) printf 'terminal capture unavailable\n' ;;
                *) printf '> \n' ;;
            esac
        fi
        ;;
    "tab close") printf '%s\n' "$3" >> "$HERDR_TEST_CLOSES" ;;
    *) exit 64 ;;
esac
HERDR
    chmod +x "$TEST_BIN/herdr"

    cat > "$TEST_BIN/gh" << 'GH'
#!/usr/bin/env bash
set -eu
branch="$3"
printf '%s\n' "$branch" >> "$HERDR_TEST_GH_CALLS"
if [ "$branch" = "merged-branch" ]; then
    printf '{"state":"MERGED","headRefName":"merged-branch","mergedAt":"2026-01-01T00:00:00Z"}\n'
else
    printf '{"state":"OPEN","headRefName":"%s","mergedAt":null}\n' "$branch"
fi
GH
    chmod +x "$TEST_BIN/gh"
    export PATH="${TEST_BIN}:${PATH}"
    : > "$HERDR_TEST_CLOSES"
    : > "$HERDR_TEST_PANE_READS"
    : > "$HERDR_TEST_GH_CALLS"
    printf '0\n' > "$HERDR_TEST_TAB_CALLS"
    printf '0\n' > "$HERDR_TEST_AGENT_CALLS"

    python3 - "$HERDR_TEST_TABS" "$HERDR_TEST_PANES" "$HERDR_TEST_AGENTS" "$MAIN_REPO" "$WORKER_WORKTREE" "$MERGED_WORKTREE" << 'PYTHON'
import json
import sys

tabs_path, panes_path, agents_path, main, worker, merged = sys.argv[1:]
definitions = [
    ("caller-tab", "ws-a", "Meta", [("caller-pane", main, "meta", "working")]),
    ("worker-tab", "ws-a", "Worker", [("worker-pane", worker, "meta-worker-1", "done")]),
    ("live-tab", "ws-a", "Live", [("live-pane", worker, "meta-worker-live", "working")]),
    ("user-tab", "ws-a", "Other owner", [("user-pane", worker, "other-worker-1", "done")]),
    ("shell-tab", "ws-a", "1", [("shell-pane", worker, None, None)]),
    ("occupied-tab", "ws-a", "Pending input", [("occupied-pane", worker, "meta-worker-input", "done")]),
    ("unknown-input-tab", "ws-a", "Unknown input", [("unknown-pane", worker, "meta-worker-unknown", "done")]),
    ("primary-tab", "ws-a", "Main checkout", [("primary-pane", main, "meta-worker-primary", "done")]),
    ("hidden-agent-tab", "ws-a", "Hidden agent", [("hidden-worker-pane", worker, "meta-worker-hidden", "done")]),
    ("multi-pane-tab", "ws-a", "Mixed panes", [
        ("mixed-owned-pane", worker, "meta-worker-mixed", "done"),
        ("mixed-shell-pane", worker, None, None),
    ]),
    ("merged-tab", "ws-a", "Merged PR", [("merged-pane", merged, "meta-worker-merged", "done")]),
    ("last-tab", "ws-b", "Last workspace tab", [("last-pane", merged, "meta-worker-last", "done")]),
    ("focused-tab", "ws-a", "Focused", [("focused-pane", worker, "meta-worker-focused", "done")]),
    ("grandchild-tab", "ws-a", "Nested worker", [("grandchild-pane", merged, "meta-radm-task", "done")]),
    ("root-lookalike-tab", "ws-a", "Nested root", [("root-pane", merged, "meta-radm", "done")]),
    ("blocked-review-tab", "ws-a", "⛔ PR #183 user review", [("blocked-review-pane", merged, "meta-worker-review", "done")]),
]
tabs = []
panes = []
agents = []
for tab_id, workspace_id, label, pane_specs in definitions:
    tabs.append({
        "tab_id": tab_id,
        "workspace_id": workspace_id,
        "label": label,
        "focused": tab_id == "focused-tab",
        "pane_count": len(pane_specs),
    })
    for pane_id, cwd, name, status in pane_specs:
        panes.append({
            "pane_id": pane_id,
            "tab_id": tab_id,
            "cwd": cwd,
            "foreground_cwd": cwd,
        })
        if name:
            agents.append({
                "name": name,
                "pane_id": pane_id,
                "tab_id": tab_id,
                "agent_status": status,
            })
agents.append({
    "name": "meta-worker-hidden-live",
    "pane_id": "unlisted-live-pane",
    "tab_id": "hidden-agent-tab",
    "agent_status": "working",
})
for path, value in [
    (tabs_path, {"result": {"tabs": tabs}}),
    (panes_path, {"result": {"panes": panes}}),
    (agents_path, {"result": {"agents": agents}}),
]:
    with open(path, "w", encoding="utf-8") as output:
        json.dump(value, output)
PYTHON

    for worker_name in \
        meta-worker-1 meta-worker-live meta-worker-input meta-worker-unknown \
        meta-worker-primary meta-worker-hidden meta-worker-mixed meta-worker-merged \
        meta-worker-last meta-worker-focused meta-worker-review; do
        "$CLEANUP_SCRIPT" --record-worker "$worker_name" > /dev/null
    done
    printf '0\n' > "$HERDR_TEST_TAB_CALLS"
    printf '0\n' > "$HERDR_TEST_AGENT_CALLS"
}

@test "default mode reports tab verdicts and does not change tabs" {
    run "$CLEANUP_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" == *'tab=caller-tab label="Meta" verdict=keep evidence=caller own tab'* ]]
    [[ "$output" == *'tab=worker-tab label="Worker" verdict=keep evidence=no matching merged PR; results for this tab were not confirmed'* ]]
    [[ "$output" == *'tab=live-tab label="Live" verdict=keep evidence=pane live-pane agent meta-worker-live is working'* ]]
    [[ "$output" == *'tab=user-tab label="Other owner" verdict=keep evidence=pane user-pane was not recorded as created by this caller at dispatch'* ]]
    [[ "$output" == *'tab=shell-tab label="1" verdict=keep evidence=pane shell-pane has no unique named agent'* ]]
    [[ "$output" == *'tab=occupied-tab label="Pending input" verdict=keep evidence=pane occupied-pane visible input is occupied'* ]]
    [[ "$output" == *'tab=unknown-input-tab label="Unknown input" verdict=keep evidence=pane unknown-pane visible input is unknown'* ]]
    [[ "$output" == *'tab=primary-tab label="Main checkout" verdict=keep evidence=pane primary-pane is in a primary checkout'* ]]
    [[ "$output" == *'tab=hidden-agent-tab label="Hidden agent" verdict=keep evidence=agent inventory has extra agents not represented by panes'* ]]
    [[ "$output" == *'tab=multi-pane-tab label="Mixed panes" verdict=keep evidence=pane mixed-shell-pane has no unique named agent'* ]]
    [[ "$output" == *'tab=merged-tab label="Merged PR" verdict=close evidence=all panes match caller dispatch records'* ]]
    [[ "$output" == *'tab=last-tab label="Last workspace tab" verdict=keep evidence=workspace must retain one tab'* ]]
    [[ "$output" == *'tab=focused-tab label="Focused" verdict=keep evidence=tab is focused'* ]]
    [[ "$output" == *'tab=grandchild-tab label="Nested worker" verdict=keep evidence=pane grandchild-pane was not recorded as created by this caller at dispatch'* ]]
    [[ "$output" == *'tab=root-lookalike-tab label="Nested root" verdict=keep evidence=pane root-pane was not recorded as created by this caller at dispatch'* ]]
    [[ "$output" == *'tab=blocked-review-tab label="⛔ PR #183 user review" verdict=keep evidence=tab label starts with ⛔'* ]]
    [ ! -s "$HERDR_TEST_CLOSES" ]
}

@test "dispatch registration records exact worker, tab, and pane and is idempotent" {
    [ "$(awk -F '\t' '$1 == "meta" && $2 == "meta-worker-1" && $3 == "worker-tab" && $4 == "worker-pane" { n++ } END { print n + 0 }' "$HERDR_TAB_CLEANUP_STATE_DIR/dispatches.tsv")" -eq 1 ]

    run "$CLEANUP_SCRIPT" --record-worker meta-worker-1

    [ "$status" -eq 0 ]
    [[ "$output" == *'recorded caller=meta worker=meta-worker-1 tab=worker-tab pane=worker-pane'* ]]
    [ "$(awk -F '\t' '$1 == "meta" && $2 == "meta-worker-1" && $3 == "worker-tab" && $4 == "worker-pane" { n++ } END { print n + 0 }' "$HERDR_TAB_CLEANUP_STATE_DIR/dispatches.tsv")" -eq 1 ]
}

@test "apply closes only the named tabs and never removes their worktrees" {
    run "$CLEANUP_SCRIPT" --apply \
        --results-collected worker-tab \
        --results-collected merged-tab

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_CLOSES")" = "$(printf 'worker-tab\nmerged-tab')" ]
    [[ "$output" == *'apply=closed tab=worker-tab'* ]]
    [[ "$output" == *'apply=closed tab=merged-tab'* ]]
    [[ "$output" != *'apply=closed tab=grandchild-tab'* ]]
    [ -d "$WORKER_WORKTREE" ]
    [ -d "$MERGED_WORKTREE" ]
}

@test "apply requires explicit tab IDs and leaves other newly completed tabs alone" {
    run "$CLEANUP_SCRIPT" --apply

    [ "$status" -eq 2 ]
    [ ! -s "$HERDR_TEST_CLOSES" ]

    run "$CLEANUP_SCRIPT" --apply --results-collected merged-tab

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_CLOSES")" = "merged-tab" ]
    [[ "$output" == *'tab=worker-tab label="Worker" verdict=keep'* ]]
    [[ "$output" == *'apply=closed tab=merged-tab'* ]]
    [[ "$output" != *'apply=closed tab=worker-tab'* ]]
}

@test "apply rereads agent lifecycle after pull-request lookup" {
    export HERDR_TEST_AGENTS_AFTER_CALL=3
    export HERDR_TEST_AGENTS_AFTER="${BATS_TEST_TMPDIR}/agents-after.json"
    python3 - "$HERDR_TEST_AGENTS" "$HERDR_TEST_AGENTS_AFTER" << 'PYTHON'
import json
import sys

source, destination = sys.argv[1:]
with open(source, encoding="utf-8") as input_file:
    inventory = json.load(input_file)
for agent in inventory["result"]["agents"]:
    if agent["name"] == "meta-worker-1":
        agent["agent_status"] = "working"
with open(destination, "w", encoding="utf-8") as output:
    json.dump(inventory, output)
PYTHON

    run "$CLEANUP_SCRIPT" --apply --results-collected worker-tab

    [ "$status" -eq 0 ]
    [ ! -s "$HERDR_TEST_CLOSES" ]
    [[ "$output" == *'apply=skipped tab=worker-tab evidence=pane worker-pane agent is working, not done or exited'* ]]
}

@test "apply rereads visible input after pull-request lookup" {
    export HERDR_TEST_FINAL_AGENT_LIST_AT=3
    export HERDR_TEST_OCCUPY_AFTER_FINAL_READ=1

    run "$CLEANUP_SCRIPT" --apply --results-collected worker-tab

    [ "$status" -eq 0 ]
    [ ! -s "$HERDR_TEST_CLOSES" ]
    [[ "$output" == *'apply=skipped tab=worker-tab evidence=pane worker-pane visible input is occupied'* ]]
    [ "$(awk -F '\t' '$1 == "worker-pane" && $2 == "3" { n++ } END { print n + 0 }' "$HERDR_TEST_PANE_READS")" -eq 1 ]
}
