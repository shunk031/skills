#!/usr/bin/env bats

readonly LIFECYCLE_SCRIPT="${BATS_TEST_DIRNAME}/../../skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-worker-lifecycle.sh"

function setup() {
    export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
    export HERDR_TEST_TABS="${BATS_TEST_TMPDIR}/tabs.json"
    export HERDR_TEST_PANES="${BATS_TEST_TMPDIR}/panes.json"
    export HERDR_TEST_AGENTS="${BATS_TEST_TMPDIR}/agents.json"
    export HERDR_TEST_STARTS="${BATS_TEST_TMPDIR}/starts"
    export HERDR_TEST_CLOSES="${BATS_TEST_TMPDIR}/closes"
    export HERDR_WORKER_LIFECYCLE_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    export HERDR_ENV=1
    export HERDR_PANE_ID=caller-pane
    export HERDR_TAB_ID=caller-tab

    mkdir -p "$TEST_BIN"
    cat > "$HERDR_TEST_TABS" << 'JSON'
{"result":{"tabs":[{"tab_id":"caller-tab","workspace_id":"workspace-1","label":"Orchestrator","focused":true},{"tab_id":"anchor-tab","workspace_id":"workspace-2","label":"Deliverable","focused":false}]}}
JSON
    cat > "$HERDR_TEST_PANES" << 'JSON'
{"result":{"panes":[{"pane_id":"caller-pane","tab_id":"caller-tab","terminal_id":"terminal-caller"},{"pane_id":"anchor-pane","tab_id":"anchor-tab","terminal_id":"terminal-anchor"}]}}
JSON
    cat > "$HERDR_TEST_AGENTS" << 'JSON'
{"result":{"agents":[{"name":"meta-tabclean","pane_id":"caller-pane","tab_id":"caller-tab","terminal_id":"terminal-caller","agent_status":"working"}]}}
JSON
    : > "$HERDR_TEST_STARTS"
    : > "$HERDR_TEST_CLOSES"

    cat > "$TEST_BIN/herdr" << 'HERDR'
#!/usr/bin/env bash
set -eu
case "$1 $2" in
    "tab list") cat "$HERDR_TEST_TABS" ;;
    "tab create")
        jq '.result.tabs += [{tab_id:"worker-tab",workspace_id:"workspace-2",label:"Worker",focused:false}]' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp"
        mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS"
        jq '.result.panes += [{pane_id:"worker-pane",tab_id:"worker-tab",terminal_id:"terminal-worker"}]' "$HERDR_TEST_PANES" > "${HERDR_TEST_PANES}.tmp"
        mv "${HERDR_TEST_PANES}.tmp" "$HERDR_TEST_PANES"
        printf '{"result":{"tab":{"tab_id":"worker-tab","workspace_id":"workspace-2"},"root_pane":{"pane_id":"worker-pane","tab_id":"worker-tab","terminal_id":"terminal-worker"}}}\n'
        ;;
    "pane list") cat "$HERDR_TEST_PANES" ;;
    "agent list") cat "$HERDR_TEST_AGENTS" ;;
    "agent start")
        name="$3"
        pane="$7"
        printf '%s\t%s\n' "$name" "$pane" >> "$HERDR_TEST_STARTS"
        jq --arg name "$name" --arg pane "$pane" --arg state "${HERDR_TEST_WORKER_STATE:-done}" '.result.agents += [{name:$name,pane_id:$pane,tab_id:"worker-tab",terminal_id:"terminal-worker",agent_status:$state}]' "$HERDR_TEST_AGENTS" > "${HERDR_TEST_AGENTS}.tmp"
        mv "${HERDR_TEST_AGENTS}.tmp" "$HERDR_TEST_AGENTS"
        ;;
    "pane read") printf '> \n' ;;
    "pane close") printf '%s\n' "$3" >> "$HERDR_TEST_CLOSES" ;;
    *) exit 64 ;;
esac
HERDR
    chmod +x "$TEST_BIN/herdr"
    export PATH="${TEST_BIN}:${PATH}"
}

function add_worker_agent() {
    local state="$1"
    jq --arg state "$state" '.result.agents += [{name:"meta-tabclean-reader",pane_id:"worker-pane",tab_id:"worker-tab",terminal_id:"terminal-worker",agent_status:$state}]' "$HERDR_TEST_AGENTS" > "${HERDR_TEST_AGENTS}.tmp"
    mv "${HERDR_TEST_AGENTS}.tmp" "$HERDR_TEST_AGENTS"
}

function add_worker_slot() {
    jq '.result.tabs += [{tab_id:"worker-tab",workspace_id:"workspace-2",label:"Worker",focused:false}]' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp"
    mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS"
    jq '.result.panes += [{pane_id:"worker-pane",tab_id:"worker-tab",terminal_id:"terminal-worker"}]' "$HERDR_TEST_PANES" > "${HERDR_TEST_PANES}.tmp"
    mv "${HERDR_TEST_PANES}.tmp" "$HERDR_TEST_PANES"
}

function add_worker_record() {
    local owner="$1"
    local state="$2"
    mkdir -p "$HERDR_WORKER_LIFECYCLE_STATE_DIR"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$owner" caller-pane terminal-caller inspect-pr meta-tabclean-reader terminal-worker worker-tab worker-pane "$state" \
        > "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv"
}

@test "launch records owner and task and collect closes only its settled pane" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
    [ "$(cat "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "$(printf 'meta-tabclean\tcaller-pane\tterminal-caller\tinspect-pr\tmeta-tabclean-reader\tterminal-worker\tworker-tab\tworker-pane\tstarted')" ]

    run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_CLOSES")" = "worker-pane" ]
    [[ "$output" == *'owner=meta-tabclean owner-pane=caller-pane task=inspect-pr pane=worker-pane'* ]]
    [ "$(awk -F '\t' '{ print $9 }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "collected" ]
}

@test "collect never closes an agent not launched by this caller pane" {
    add_worker_slot
    add_worker_agent done
    add_worker_record other-orchestrator started

    run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader

    [ "$status" -ne 0 ]
    [[ "$output" == *'does not have one exact launch record for this caller pane and task'* ]]
    [ ! -s "$HERDR_TEST_CLOSES" ]
}

@test "collect leaves working or blocked agents open" {
    add_worker_slot
    add_worker_record meta-tabclean started
    add_worker_agent working
    jq '.result.agents |= map(if .name == "meta-tabclean-reader" then .agent_status = "blocked" else . end)' "$HERDR_TEST_AGENTS" > "${HERDR_TEST_AGENTS}.tmp"
    mv "${HERDR_TEST_AGENTS}.tmp" "$HERDR_TEST_AGENTS"

    run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader

    [ "$status" -ne 0 ]
    [[ "$output" == *'only done or idle workers can be collected'* ]]
    [ ! -s "$HERDR_TEST_CLOSES" ]
}

@test "audit warns for unrecorded panes without changing them" {
    add_worker_slot
    add_worker_agent working
    jq '.result.tabs += [{tab_id:"shell-tab",workspace_id:"workspace-1",label:"1",focused:false}]' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp"
    mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS"
    jq '.result.panes += [{pane_id:"shell-pane",tab_id:"shell-tab",terminal_id:"terminal-shell"}]' "$HERDR_TEST_PANES" > "${HERDR_TEST_PANES}.tmp"
    mv "${HERDR_TEST_PANES}.tmp" "$HERDR_TEST_PANES"

    run "$LIFECYCLE_SCRIPT" audit

    [ "$status" -eq 0 ]
    [[ "$output" == *'warning unrecorded-live-agent name=meta-tabclean-reader state=working pane=worker-pane tab=worker-tab'* ]]
    [[ "$output" == *'warning unrecorded-live-pane-without-agent pane=shell-pane tab=shell-tab'* ]]
    [[ "$output" == *'warning unrecorded-live-pane-without-agent pane=anchor-pane tab=anchor-tab'* ]]
    [[ "$output" == *'audit warnings=3 mode=read-only'* ]]
    [ ! -s "$HERDR_TEST_CLOSES" ]
}

@test "audit warns when a settled recorded worker was never explicitly collected" {
    add_worker_slot
    jq '.result.tabs |= map(select(.tab_id != "anchor-tab"))' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp"
    mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS"
    jq '.result.panes |= map(select(.pane_id != "anchor-pane"))' "$HERDR_TEST_PANES" > "${HERDR_TEST_PANES}.tmp"
    mv "${HERDR_TEST_PANES}.tmp" "$HERDR_TEST_PANES"
    add_worker_agent done
    add_worker_record meta-tabclean started

    run "$LIFECYCLE_SCRIPT" audit

    [ "$status" -eq 0 ]
    [[ "$output" == *'warning settled-worker-not-collected name=meta-tabclean-reader state=done task=inspect-pr pane=worker-pane tab=worker-tab'* ]]
    [[ "$output" == *'audit warnings=1 mode=read-only'* ]]
    [ ! -s "$HERDR_TEST_CLOSES" ]
}

@test "collect leaves a focused tab open" {
    add_worker_slot
    add_worker_agent done
    add_worker_record meta-tabclean started
    jq '.result.tabs |= map(if .tab_id == "worker-tab" then .focused = true else . end)' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp"
    mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS"

    run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader

    [ "$status" -ne 0 ]
    [[ "$output" == *'worker tab is focused or its focus state is unknown'* ]]
    [ ! -s "$HERDR_TEST_CLOSES" ]
}

@test "collect leaves a protected tab open" {
    add_worker_slot
    add_worker_agent done
    add_worker_record meta-tabclean started
    jq '.result.tabs |= map(if .tab_id == "worker-tab" then .label = "⛔ protected" else . end)' "$HERDR_TEST_TABS" > "$HERDR_TEST_TABS.tmp"
    mv "$HERDR_TEST_TABS.tmp" "$HERDR_TEST_TABS"

    run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader

    [ "$status" -ne 0 ]
    [[ "$output" == *'worker tab label starts with ⛔'* ]]
    [ ! -s "$HERDR_TEST_CLOSES" ]
}
