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
    export HERDR_TEST_WORKTREE="${BATS_TEST_TMPDIR}/implementation-worktree"
    export HERDR_TEST_START_FAILURE=0
    export HERDR_WORKER_LIFECYCLE_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    export HOME="${BATS_TEST_TMPDIR}/home"
    export HERDR_ENV=1
    export HERDR_PANE_ID=caller-pane
    export HERDR_TAB_ID=caller-tab

    mkdir -p "$TEST_BIN" "$HOME"
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
    "agent list") cat "$HERDR_TEST_AGENTS" ;;
    "agent start")
        name="$3"
        pane="$7"
        tab="$(jq -r --arg pane "$pane" '.result.panes[] | select(.pane_id == $pane) | .tab_id' "$HERDR_TEST_PANES")"
        terminal="$(jq -r --arg pane "$pane" '.result.panes[] | select(.pane_id == $pane) | .terminal_id' "$HERDR_TEST_PANES")"
        printf '%s\t%s\n' "$name" "$pane" >> "$HERDR_TEST_STARTS"
        jq --arg name "$name" --arg pane "$pane" --arg tab "$tab" --arg terminal "$terminal" --arg state "${HERDR_TEST_WORKER_STATE:-done}" '.result.agents += [{name:$name,pane_id:$pane,tab_id:$tab,terminal_id:$terminal,agent_status:$state}]' "$HERDR_TEST_AGENTS" > "${HERDR_TEST_AGENTS}.tmp"
        mv "${HERDR_TEST_AGENTS}.tmp" "$HERDR_TEST_AGENTS"
        if [[ "${HERDR_TEST_START_FAILURE:-0}" != 0 ]]; then
            exit "$HERDR_TEST_START_FAILURE"
        fi
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

function create_size_gate_repo() {
    mkdir -p "$HERDR_TEST_WORKTREE"
    git -C "$HERDR_TEST_WORKTREE" init -q
    git -C "$HERDR_TEST_WORKTREE" checkout -qb main
    git -C "$HERDR_TEST_WORKTREE" config user.name "Lifecycle Test"
    git -C "$HERDR_TEST_WORKTREE" config user.email "lifecycle-test@example.invalid"
    printf 'baseline\n' > "$HERDR_TEST_WORKTREE/README.md"
    git -C "$HERDR_TEST_WORKTREE" add README.md
    git -C "$HERDR_TEST_WORKTREE" commit -qm baseline
    git init --bare -q "${HERDR_TEST_WORKTREE}.remote"
    git -C "$HERDR_TEST_WORKTREE" remote add origin "${HERDR_TEST_WORKTREE}.remote"
    git -C "$HERDR_TEST_WORKTREE" push -q origin main
    git --git-dir="${HERDR_TEST_WORKTREE}.remote" symbolic-ref HEAD refs/heads/main
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

@test "launch uses an explicit root pane and collect closes its last workspace pane" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --root-pane anchor-pane -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tanchor-pane')" ]
    [ "$(awk -F '\t' '{ print NF ":" $9 ":" $10 }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "10:started:root" ]

    run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_CLOSES")" = "anchor-pane" ]
    [ "$(awk -F '\t' '{ print $9 ":" $10 }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "collected:root" ]
}

@test "launch errors when an explicitly selected root pane is in a focused tab" {
    jq '.result.tabs[1].focused = true' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp"
    mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS"

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --root-pane anchor-pane -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'requested root pane tab is focused or its focus state is unknown'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]
}

@test "launch errors when an explicitly selected root pane has a protected tab label" {
    jq '.result.tabs[1].label = "⛔ Keep"' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp"
    mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS"

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --root-pane anchor-pane -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'requested root pane tab label starts with ⛔'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]
}

@test "launch errors when the requested root pane has an agent" {
    jq '.result.agents += [{name:"other-worker",pane_id:"anchor-pane",tab_id:"anchor-tab",terminal_id:"terminal-anchor",agent_status:"working"}]' "$HERDR_TEST_AGENTS" > "${HERDR_TEST_AGENTS}.tmp"
    mv "${HERDR_TEST_AGENTS}.tmp" "$HERDR_TEST_AGENTS"

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --root-pane anchor-pane -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'requested root pane has an agent'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]
}

@test "launch errors when the requested root pane is missing or outside the workspace" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --root-pane "" -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'--root-pane requires a pane ID'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --root-pane missing-pane -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'requested root pane is missing or ambiguous'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --root-pane caller-pane -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'requested root pane is not in the given workspace'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]
}

@test "launch errors when a requested root pane is combined with env options" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --root-pane anchor-pane --env WORKER_MODE=isolated -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'--root-pane cannot be combined with --env'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]
}

@test "launch timeout leaves an explicitly selected root pane unrecorded" {
    export HERDR_TEST_START_FAILURE=124

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --root-pane anchor-pane -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'no launch record was written'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -e "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv" ]
    [ "$(jq -r '[.result.agents[] | select(.name == "meta-tabclean-reader")] | length' "$HERDR_TEST_AGENTS")" = "1" ]
}

@test "launch creates a tab to apply worker-specific environment variables" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --env WORKER_MODE=isolated -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    grep -Fqx -- "--env" "$HERDR_TEST_CREATE_ARGS"
    grep -Fqx -- "WORKER_MODE=isolated" "$HERDR_TEST_CREATE_ARGS"
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
}

@test "implementation launch requires a budget and bypasses root-pane reuse with its gate environment" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$HERDR_TEST_WORKTREE" --label "Worker" --task size-test --role implementation --root-pane anchor-pane -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'implementation launches require --line-budget'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]

    create_size_gate_repo
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$HERDR_TEST_WORKTREE" --label "Worker" --task size-test --role implementation --line-budget 400 --root-pane anchor-pane -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    grep -Fqx -- "--env" "$HERDR_TEST_CREATE_ARGS"
    launch_id="$(sed -n 's/^HERDR_WORKER_SIZE_GATE_LAUNCH_ID=//p' "$HERDR_TEST_CREATE_ARGS")"
    [[ "$launch_id" =~ ^[a-f0-9-]{36}$ ]]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
    [ "$(awk -F '\t' '{ print $9 ":" $10 }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "started:tab" ]
    gate_record="$(find "$HOME/.local/state/herdr-worker-lifecycle/size-gates" -name '*.json' -print -quit)"
    [ -n "$gate_record" ]
    jq -e --arg launch_id "$launch_id" '.launch_id == $launch_id and .status == "started" and .worker.pane == "worker-pane" and .worker.tab == "worker-tab" and .worker.terminal == "terminal-worker"' "$gate_record" > /dev/null
}

@test "implementation launch timeout leaves a pending size-gate record" {
    create_size_gate_repo
    export HERDR_TEST_START_FAILURE=124

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$HERDR_TEST_WORKTREE" --label "Worker" --task size-test --role implementation --line-budget 400 -- -m gpt-6-luna

    [ "$status" -eq 124 ]
    [[ "$output" == *'pending size-gate record remains'* ]]
    [ ! -e "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv" ]
    gate_record="$(find "$HOME/.local/state/herdr-worker-lifecycle/size-gates" -name '*.json' -print -quit)"
    [ -n "$gate_record" ]
    jq -e '.status == "pending" and .worker.pane == "worker-pane" and .worker.tab == "worker-tab" and .worker.terminal == "terminal-worker"' "$gate_record" > /dev/null
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
