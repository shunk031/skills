#!/usr/bin/env bats

readonly LIFECYCLE_SCRIPT="${BATS_TEST_DIRNAME}/../../skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-worker-lifecycle.sh"

function setup() {
    export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
    export HERDR_TEST_TABS="${BATS_TEST_TMPDIR}/tabs.json"
    export HERDR_TEST_PANES="${BATS_TEST_TMPDIR}/panes.json"
    export HERDR_TEST_AGENTS="${BATS_TEST_TMPDIR}/agents.json"
    export HERDR_TEST_STARTS="${BATS_TEST_TMPDIR}/starts"
    export HERDR_TEST_TAB_CREATES="${BATS_TEST_TMPDIR}/tab-creates"
    export HERDR_TEST_CLOSES="${BATS_TEST_TMPDIR}/closes"
    export HERDR_TEST_CREATE_ARGS="${BATS_TEST_TMPDIR}/create-args"
    export HERDR_TEST_ROOT_STATE=busy
    export HERDR_TEST_START_FAILURE=0
    export HERDR_WORKER_LIFECYCLE_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    export HERDR_ENV=1
    export HERDR_PANE_ID=caller-pane
    export HERDR_TAB_ID=caller-tab

    mkdir -p "$TEST_BIN"
    cat > "$HERDR_TEST_TABS" << 'JSON'
{"result":{"tabs":[{"tab_id":"caller-tab","workspace_id":"workspace-1","label":"Orchestrator","focused":true},{"tab_id":"anchor-tab","workspace_id":"workspace-2","label":"Deliverable","focused":false}]}}
JSON
    cat > "$HERDR_TEST_PANES" << 'JSON'
{"result":{"panes":[{"pane_id":"caller-pane","tab_id":"caller-tab","terminal_id":"terminal-caller"},{"pane_id":"anchor-pane","tab_id":"anchor-tab","terminal_id":"terminal-anchor","foreground_cwd":"/tmp/worktree"}]}}
JSON
    cat > "$HERDR_TEST_AGENTS" << 'JSON'
{"result":{"agents":[{"name":"meta-tabclean","pane_id":"caller-pane","tab_id":"caller-tab","terminal_id":"terminal-caller","agent_status":"working"}]}}
JSON
    : > "$HERDR_TEST_STARTS"
    : > "$HERDR_TEST_TAB_CREATES"
    : > "$HERDR_TEST_CREATE_ARGS"
    : > "$HERDR_TEST_CLOSES"

    cat > "$TEST_BIN/herdr" << 'HERDR'
#!/usr/bin/env bash
set -eu
case "$1 $2" in
    "tab list") cat "$HERDR_TEST_TABS" ;;
    "tab create")
        printf 'create\n' >> "$HERDR_TEST_TAB_CREATES"
        printf '%s\n' "$@" > "$HERDR_TEST_CREATE_ARGS"
        jq '.result.tabs += [{tab_id:"worker-tab",workspace_id:"workspace-2",label:"Worker",focused:false}]' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp"
        mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS"
        jq '.result.panes += [{pane_id:"worker-pane",tab_id:"worker-tab",terminal_id:"terminal-worker"}]' "$HERDR_TEST_PANES" > "${HERDR_TEST_PANES}.tmp"
        mv "${HERDR_TEST_PANES}.tmp" "$HERDR_TEST_PANES"
        printf '{"result":{"tab":{"tab_id":"worker-tab","workspace_id":"workspace-2"},"root_pane":{"pane_id":"worker-pane","tab_id":"worker-tab","terminal_id":"terminal-worker"}}}\n'
        ;;
    "pane list") cat "$HERDR_TEST_PANES" ;;
    "pane process-info")
        if [[ "$HERDR_TEST_ROOT_STATE" == idle ]]; then
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":9,"name":"zsh","argv":["zsh"]}]}}}'
        elif [[ "$HERDR_TEST_ROOT_STATE" == timeout ]]; then
            exit 1
        elif [[ "$HERDR_TEST_ROOT_STATE" == stale ]]; then
            printf '%s\n' '{"result":{"process_info":{"shell_pid":null,"foreground_processes":[{"pid":9,"name":"zsh","argv":["zsh"]}]}}}'
        else
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":9,"name":"zsh","argv":["zsh"]},{"pid":42,"name":"vim","argv":["vim"]}]}}}'
        fi
        ;;
    "agent list") cat "$HERDR_TEST_AGENTS" ;;
    "agent start")
        name="$3"
        pane="$7"
        tab="$(jq -r --arg pane "$pane" '.result.panes[] | select(.pane_id == $pane) | .tab_id' "$HERDR_TEST_PANES")"
        terminal="$(jq -r --arg pane "$pane" '.result.panes[] | select(.pane_id == $pane) | .terminal_id' "$HERDR_TEST_PANES")"
        printf '%s\t%s\n' "$name" "$pane" >> "$HERDR_TEST_STARTS"
        if [[ "${HERDR_TEST_START_FAILURE:-0}" == 1 ]]; then
            exit 124
        fi
        jq --arg name "$name" --arg pane "$pane" --arg tab "$tab" --arg terminal "$terminal" --arg state "${HERDR_TEST_WORKER_STATE:-done}" '.result.agents += [{name:$name,pane_id:$pane,tab_id:$tab,terminal_id:$terminal,agent_status:$state}]' "$HERDR_TEST_AGENTS" > "${HERDR_TEST_AGENTS}.tmp"
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
    [ "$(cat "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "$(printf 'meta-tabclean\tcaller-pane\tterminal-caller\tinspect-pr\tmeta-tabclean-reader\tterminal-worker\tworker-tab\tworker-pane\tstarted\ttab')" ]

    run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_CLOSES")" = "worker-pane" ]
    [[ "$output" == *'owner=meta-tabclean owner-pane=caller-pane task=inspect-pr pane=worker-pane'* ]]
    [ "$(awk -F '\t' '{ print $9 }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "collected" ]
}

@test "launch reuses an idle root shell and collect closes its last workspace pane" {
    export HERDR_TEST_ROOT_STATE=idle

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tanchor-pane')" ]
    [ "$(awk -F '\t' '{ print NF ":" $9 ":" $10 }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "10:started:root" ]

    run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_CLOSES")" = "anchor-pane" ]
    [ "$(awk -F '\t' '{ print $9 ":" $10 }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "collected:root" ]
}

@test "launch falls back to a new tab when the root shell has another foreground process" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
    [ "$(awk -F '\t' '{ print NF ":" $9 ":" $10 }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "10:started:tab" ]
}

@test "launch falls back when the target root pane already has an agent" {
    export HERDR_TEST_ROOT_STATE=idle
    jq '.result.agents += [{name:"other-worker",pane_id:"anchor-pane",tab_id:"anchor-tab",terminal_id:"terminal-anchor",agent_status:"working"}]' "$HERDR_TEST_AGENTS" > "${HERDR_TEST_AGENTS}.tmp"
    mv "${HERDR_TEST_AGENTS}.tmp" "$HERDR_TEST_AGENTS"

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
}

@test "launch falls back when the root shell is in a different working directory" {
    export HERDR_TEST_ROOT_STATE=idle
    jq '.result.panes[1].foreground_cwd = "/tmp/other-worktree"' "$HERDR_TEST_PANES" > "${HERDR_TEST_PANES}.tmp"
    mv "${HERDR_TEST_PANES}.tmp" "$HERDR_TEST_PANES"

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
}

@test "launch falls back when the root shell working directory is unknown" {
    export HERDR_TEST_ROOT_STATE=idle
    jq 'del(.result.panes[1].foreground_cwd)' "$HERDR_TEST_PANES" > "${HERDR_TEST_PANES}.tmp"
    mv "${HERDR_TEST_PANES}.tmp" "$HERDR_TEST_PANES"

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
}

@test "launch falls back when root process information cannot be read" {
    export HERDR_TEST_ROOT_STATE=timeout

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
}

@test "launch falls back when root process information is incomplete" {
    export HERDR_TEST_ROOT_STATE=stale

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
}

@test "launch timeout leaves the root pane unrecorded without opening another tab" {
    export HERDR_TEST_ROOT_STATE=idle
    export HERDR_TEST_START_FAILURE=1

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'launched worker is not uniquely present in the live agent inventory'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -e "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv" ]
}

@test "launch creates a tab to apply worker-specific environment variables" {
    export HERDR_TEST_ROOT_STATE=idle

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --env WORKER_MODE=isolated -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    grep -Fqx -- "--env" "$HERDR_TEST_CREATE_ARGS"
    grep -Fqx -- "WORKER_MODE=isolated" "$HERDR_TEST_CREATE_ARGS"
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
}

@test "launch falls back when the target workspace has another tab" {
    export HERDR_TEST_ROOT_STATE=idle
    jq '.result.tabs += [{tab_id:"extra-tab",workspace_id:"workspace-2",label:"Extra",focused:false}]' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp"
    mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS"

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
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
