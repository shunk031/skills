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
    export HERDR_ENV=1
    export HERDR_PANE_ID=caller-pane
    export HERDR_TAB_ID=caller-tab

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
        count="$(cat "$HERDR_TEST_TAB_CALLS")"
        if [ "$count" -gt 1 ] && [ -n "${HERDR_TEST_AGENTS_AFTER:-}" ]; then
            cat "$HERDR_TEST_AGENTS_AFTER"
        else
            cat "$HERDR_TEST_AGENTS"
        fi
        ;;
    "pane read")
        case "$3" in
            occupied-pane) printf '> echo pending\n' ;;
            unknown-pane) printf 'terminal capture unavailable\n' ;;
            *) printf '> \n' ;;
        esac
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
if [ "$branch" = "merged-branch" ]; then
    printf '{"state":"MERGED","headRefName":"merged-branch","mergedAt":"2026-01-01T00:00:00Z"}\n'
else
    printf '{"state":"OPEN","headRefName":"%s","mergedAt":null}\n' "$branch"
fi
GH
    chmod +x "$TEST_BIN/gh"
    export PATH="${TEST_BIN}:${PATH}"
    : > "$HERDR_TEST_CLOSES"
    printf '0\n' > "$HERDR_TEST_TAB_CALLS"

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
    ("hidden-agent-tab", "ws-a", "Hidden agent", [("hidden-worker-pane", worker, "meta-worker-hidden-done", "done")]),
    ("multi-pane-tab", "ws-a", "Mixed panes", [
        ("mixed-owned-pane", worker, "meta-worker-mixed", "done"),
        ("mixed-shell-pane", worker, None, None),
    ]),
    ("merged-tab", "ws-a", "Merged PR", [("merged-pane", merged, "meta-worker-merged", "done")]),
    ("last-tab", "ws-b", "Last workspace tab", [("last-pane", merged, "meta-worker-last", "done")]),
    ("focused-tab", "ws-a", "Focused", [("focused-pane", worker, "meta-worker-focused", "done")]),
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
}

@test "default mode reports verdicts and does not change tabs" {
    run "$CLEANUP_SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" == *'tab=caller-tab label="Meta" verdict=keep evidence=caller own tab'* ]]
    [[ "$output" == *'tab=worker-tab label="Worker" verdict=keep evidence=completed owned worker has no proven merged PR'* ]]
    [[ "$output" == *'tab=live-tab label="Live" verdict=keep evidence=pane live-pane agent meta-worker-live is working'* ]]
    [[ "$output" == *'tab=user-tab label="Other owner" verdict=keep evidence=pane user-pane agent other-worker-1 is not named by caller meta'* ]]
    [[ "$output" == *'tab=shell-tab label="1" verdict=keep evidence=pane shell-pane has no unique named agent'* ]]
    [[ "$output" == *'tab=occupied-tab label="Pending input" verdict=keep evidence=pane occupied-pane visible input is occupied'* ]]
    [[ "$output" == *'tab=unknown-input-tab label="Unknown input" verdict=keep evidence=pane unknown-pane visible input is unknown'* ]]
    [[ "$output" == *'tab=primary-tab label="Main checkout" verdict=keep evidence=pane primary-pane is in a primary checkout'* ]]
    [[ "$output" == *'tab=hidden-agent-tab label="Hidden agent" verdict=keep evidence=agent inventory has extra agents not represented by panes'* ]]
    [[ "$output" == *'tab=multi-pane-tab label="Mixed panes" verdict=keep evidence=pane mixed-shell-pane has no unique named agent'* ]]
    [[ "$output" == *'tab=merged-tab label="Merged PR" verdict=close evidence=all panes are caller-owned completed workers with empty inputs; pull request for branch merged-branch is merged'* ]]
    [[ "$output" == *'tab=last-tab label="Last workspace tab" verdict=keep evidence=workspace must retain one tab'* ]]
    [[ "$output" == *'tab=focused-tab label="Focused" verdict=keep evidence=tab is focused'* ]]
    [ ! -s "$HERDR_TEST_CLOSES" ]
}

@test "apply closes only completed owned tabs with collected results or a merged PR" {
    run "$CLEANUP_SCRIPT" --apply --results-collected

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_CLOSES")" = "$(printf 'worker-tab\nmerged-tab')" ]
    [[ "$output" == *'apply=closed tab=worker-tab'* ]]
    [[ "$output" == *'apply=closed tab=merged-tab'* ]]
    [[ "$output" != *'apply=closed tab=caller-tab'* ]]
    [ -d "$WORKER_WORKTREE" ]
    [ -d "$MERGED_WORKTREE" ]
}

@test "apply closes a merged tab without a collection attestation and retains the last workspace tab" {
    run "$CLEANUP_SCRIPT" --apply

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_CLOSES")" = "merged-tab" ]
    [[ "$output" == *'tab=worker-tab label="Worker" verdict=keep'* ]]
    [[ "$output" == *'tab=last-tab label="Last workspace tab" verdict=keep evidence=workspace must retain one tab'* ]]
}

@test "apply refreshes agent lifecycle state immediately before closing" {
    export HERDR_TEST_AGENTS_AFTER="${BATS_TEST_TMPDIR}/agents-after.json"
    python3 - "$HERDR_TEST_AGENTS" "$HERDR_TEST_AGENTS_AFTER" << 'PYTHON'
import json
import sys

source, destination = sys.argv[1:]
with open(source, encoding="utf-8") as input_file:
    inventory = json.load(input_file)
for agent in inventory["result"]["agents"]:
    if agent["name"].startswith("meta-worker-"):
        agent["agent_status"] = "working"
with open(destination, "w", encoding="utf-8") as output:
    json.dump(inventory, output)
PYTHON

    run "$CLEANUP_SCRIPT" --apply --results-collected

    [ "$status" -eq 0 ]
    [ ! -s "$HERDR_TEST_CLOSES" ]
    [[ "$output" == *'apply=skipped tab=worker-tab evidence=pane worker-pane agent meta-worker-1 is working'* ]]
}
