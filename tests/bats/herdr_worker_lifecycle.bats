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
    export HERDR_TEST_LINKED_WORKTREE="${BATS_TEST_TMPDIR}/implementation-linked-worktree"
    export HERDR_TEST_WORKTREES="${BATS_TEST_TMPDIR}/worktrees.json"
    export HERDR_TEST_WORKTREE_LIST_FAILURE=0
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
    printf '{"id":"cli:worktree:list","result":{"type":"worktree_list","worktrees":[]}}\n' > "$HERDR_TEST_WORKTREES"

    cat > "$TEST_BIN/herdr" << 'HERDR'
#!/usr/bin/env bash
set -eu
case "$1 $2" in
    "worktree list")
        if [[ "${HERDR_TEST_WORKTREE_LIST_FAILURE:-0}" != 0 ]]; then exit "$HERDR_TEST_WORKTREE_LIST_FAILURE"; fi
        cat "$HERDR_TEST_WORKTREES"
        ;;
    "tab list") cat "$HERDR_TEST_TABS" ;;
    "workspace create")
        jq '.result.tabs += [{tab_id:"owned-tab",workspace_id:"owned-workspace",label:"Worker",focused:false,pane_count:1}]' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp" && mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS"
        jq '.result.panes += [{pane_id:"owned-pane",tab_id:"owned-tab",terminal_id:"terminal-owned"}]' "$HERDR_TEST_PANES" > "${HERDR_TEST_PANES}.tmp" && mv "${HERDR_TEST_PANES}.tmp" "$HERDR_TEST_PANES"
        printf '{"result":{"workspace":{"workspace_id":"owned-workspace"},"tab":{"tab_id":"owned-tab"},"root_pane":{"pane_id":"owned-pane","tab_id":"owned-tab","terminal_id":"terminal-owned"}}}\n'
        ;;
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
    "workspace close") printf 'workspace:%s\n' "$3" >> "$HERDR_TEST_CLOSES" ;;
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
    git -C "$HERDR_TEST_WORKTREE" worktree add -q -b implementation-topic "$HERDR_TEST_LINKED_WORKTREE" main
    configure_herdr_worktree "$HERDR_TEST_LINKED_WORKTREE" workspace-2
}

function configure_herdr_worktree() {
    local path="$1"
    local workspace="$2"
    path="$(cd "$path" && pwd -P)"
    jq -n --arg path "$path" --arg workspace "$workspace" '{id:"cli:worktree:list",result:{type:"worktree_list",worktrees:[{path:$path,is_linked_worktree:true,is_prunable:false,open_workspace_id:$workspace}]}}' > "$HERDR_TEST_WORKTREES"
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

@test "new-workspace launch records ownership and collection closes only its exact sole pane" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --new-workspace --cwd /tmp/worktree --label Worker --task inspect-pr -- -m gpt-6-luna && [ "$status" -eq 0 ] && [ "$(awk -F '\t' '{ print $10 }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "owned:owned-workspace" ] && run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader && [ "$status" -eq 0 ] && [ "$(cat "$HERDR_TEST_CLOSES")" = "workspace:owned-workspace" ]
}

@test "collect leaves mismatched and duplicate owned workspace records open" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --new-workspace --cwd /tmp/worktree --label Worker --task inspect-pr -- -m gpt-6-luna && [ "$status" -eq 0 ] && awk -F '\t' -v OFS='\t' '{$10="owned:other-workspace"; print}' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv" > "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv.tmp" && mv "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv.tmp" "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv" && run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader && [ "$status" -ne 0 ] && [[ "$output" == *'owned workspace ID does not match its launch record; leaving it open'* ]] && awk -F '\t' -v OFS='\t' 'NR == 1 { $10="owned:owned-workspace"; print; $1="other-owner"; $2="other-pane"; $3="other-terminal"; print }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv" > "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv.tmp" && mv "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv.tmp" "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv" && run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader && [ "$status" -ne 0 ] && [[ "$output" == *'worker does not have one exact launch record'* ]] && [ ! -s "$HERDR_TEST_CLOSES" ]
}

@test "collect leaves an owned workspace open for incomplete pane inventory or another pane" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --new-workspace --cwd /tmp/worktree --label Worker --task inspect-pr -- -m gpt-6-luna && [ "$status" -eq 0 ] && jq '.result.tabs |= map(if .tab_id == "owned-tab" then .pane_count = 2 else . end)' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp" && mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS" && run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader && [ "$status" -ne 0 ] && [[ "$output" == *'owned workspace has another or unknown pane; leaving it open'* ]] && [ ! -s "$HERDR_TEST_CLOSES" ] && jq '.result.tabs |= map(if .tab_id == "owned-tab" then .pane_count = 1 else . end)' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp" && mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS" && jq '.result.panes += [{pane_id:"sibling-pane",tab_id:"owned-tab",terminal_id:"terminal-sibling"}]' "$HERDR_TEST_PANES" > "${HERDR_TEST_PANES}.tmp" && mv "${HERDR_TEST_PANES}.tmp" "$HERDR_TEST_PANES" && jq '.result.tabs |= map(if .tab_id == "owned-tab" then .pane_count = 2 else . end)' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp" && mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS" && run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader && [ "$status" -ne 0 ] && [[ "$output" == *'owned workspace has another or unknown pane; leaving it open'* ]] && [ ! -s "$HERDR_TEST_CLOSES" ]
}
@test "collect leaves an owned workspace open when a tab has no workspace ID" { run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --new-workspace --cwd /tmp/worktree --label Worker --task inspect-pr -- -m gpt-6-luna && [ "$status" -eq 0 ] && jq '.result.tabs += [{tab_id:"unknown-tab",label:"Unknown",focused:false}]' "$HERDR_TEST_TABS" > "${HERDR_TEST_TABS}.tmp" && mv "${HERDR_TEST_TABS}.tmp" "$HERDR_TEST_TABS" && jq '.result.panes += [{pane_id:"unknown-pane",tab_id:"unknown-tab",terminal_id:"terminal-unknown"}]' "$HERDR_TEST_PANES" > "${HERDR_TEST_PANES}.tmp" && mv "${HERDR_TEST_PANES}.tmp" "$HERDR_TEST_PANES" && run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader && [ "$status" -ne 0 ] && [[ "$output" == *'owned workspace has another or unknown pane; leaving it open'* ]] && [ ! -s "$HERDR_TEST_CLOSES" ]; }
@test "collect keeps an unowned root-pane workspace open when it is the last pane" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd /tmp/worktree --label "Worker" --task inspect-pr --root-pane anchor-pane -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tanchor-pane')" ]
    [ "$(awk -F '\t' '{ print NF ":" $9 ":" $10 }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "10:started:root" ]

    run "$LIFECYCLE_SCRIPT" collect meta-tabclean-reader

    [ "$status" -ne 0 ] && [[ "$output" == *'closing this worker pane would close the workspace'* ]] && [ ! -s "$HERDR_TEST_CLOSES" ]
    [ "$(awk -F '\t' '{ print $9 ":" $10 }' "$HERDR_WORKER_LIFECYCLE_STATE_DIR/workers.tsv")" = "started:root" ]
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
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$HERDR_TEST_LINKED_WORKTREE" --label "Worker" --task size-test --role implementation --line-budget 400 --root-pane anchor-pane -- -m gpt-6-luna

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

@test "implementation launch refuses the main checkout before creating a tab" {
    create_size_gate_repo
    mkdir -p "$HERDR_TEST_WORKTREE/nested"

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$HERDR_TEST_WORKTREE" --label Worker --task size-test --role implementation --line-budget 400 -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'implementation --cwd is the main working tree'* ]]
    [[ "$output" == *'herdr worktree create --cwd <repo>'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$HERDR_TEST_WORKTREE/nested" --label Worker --task size-test --role implementation --line-budget 400 -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'implementation --cwd is the main working tree'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]
}

@test "implementation launch refuses a workspace that is not the matching Herdr worktree workspace" {
    create_size_gate_repo
    configure_herdr_worktree "$HERDR_TEST_LINKED_WORKTREE" worktree-workspace

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$HERDR_TEST_LINKED_WORKTREE" --label Worker --task size-test --role implementation --line-budget 400 -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'--workspace is not the open Herdr worktree workspace'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]
}

@test "implementation launch refuses new workspaces before creating a tab" {
    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --new-workspace --cwd /tmp/worktree --label Worker --task size-test --role implementation --line-budget 400 -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'implementation launches cannot use --new-workspace'* ]]
    [[ "$output" == *'herdr worktree create --cwd <repo>'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]
}

@test "implementation launch refuses a failed Herdr worktree lookup" {
    create_size_gate_repo
    export HERDR_TEST_WORKTREE_LIST_FAILURE=1

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$HERDR_TEST_LINKED_WORKTREE" --label Worker --task size-test --role implementation --line-budget 400 -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'could not verify the Herdr worktree workspace'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]
}

@test "implementation launch refuses a failed Git worktree lookup" {
    mkdir -p "$BATS_TEST_TMPDIR/plain-folder"

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$BATS_TEST_TMPDIR/plain-folder" --label Worker --task size-test --role implementation --line-budget 400 -- -m gpt-6-luna

    [ "$status" -ne 0 ]
    [[ "$output" == *'could not verify implementation --cwd as a linked Git worktree'* ]]
    [[ "$output" == *'herdr worktree create --cwd <repo>'* ]]
    [ ! -s "$HERDR_TEST_TAB_CREATES" ]
    [ ! -s "$HERDR_TEST_STARTS" ]
}

@test "implementation launch accepts the matching linked worktree workspace" {
    create_size_gate_repo

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$HERDR_TEST_LINKED_WORKTREE" --label Worker --task size-test --role implementation --line-budget 400 -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
}

@test "non-implementation launch still accepts a plain folder" {
    mkdir -p "$BATS_TEST_TMPDIR/report-folder"

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$BATS_TEST_TMPDIR/report-folder" --label Worker --task inspect-pr -- -m gpt-6-luna

    [ "$status" -eq 0 ]
    [ "$(cat "$HERDR_TEST_TAB_CREATES")" = "create" ]
    [ "$(cat "$HERDR_TEST_STARTS")" = "$(printf 'meta-tabclean-reader\tworker-pane')" ]
}

@test "implementation launch timeout leaves a pending size-gate record" {
    create_size_gate_repo
    export HERDR_TEST_START_FAILURE=124

    run "$LIFECYCLE_SCRIPT" launch meta-tabclean-reader --kind codex --workspace workspace-2 --cwd "$HERDR_TEST_LINKED_WORKTREE" --label "Worker" --task size-test --role implementation --line-budget 400 -- -m gpt-6-luna

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
