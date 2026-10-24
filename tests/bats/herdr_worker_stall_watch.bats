#!/usr/bin/env bats

readonly WORKER_WATCH_SCRIPT="${BATS_TEST_DIRNAME}/../../skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-worker-stall-watch.sh"

function setup() {
    export HERDR_ENV=1
    export WORKER_STUB_STATE="${BATS_TEST_TMPDIR}/worker-stub"
    STUB_BIN="${BATS_TEST_TMPDIR}/worker-bin"
    mkdir -p "${WORKER_STUB_STATE}" "${STUB_BIN}"

    cat > "${STUB_BIN}/herdr" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state_dir="${WORKER_STUB_STATE:?}"
case "${1:-} ${2:-}" in
    "agent list") cat "${state_dir}/agents.json" ;;
    "pane read")
        [[ "${3:-}" == w1:p1 || "${3:-}" == w2:p2 ]] || exit 2
        printf '%s\n' "${3}" >> "${state_dir}/pane-reads"
        cat "${state_dir}/pane.txt"
        ;;
    *) exit 2 ;;
esac
EOF
    chmod +x "${STUB_BIN}/herdr"
    export PATH="${STUB_BIN}:${PATH}"
}

function write_worker_snapshot() {
    local agent_status="$1"
    printf '{"result":{"agents":[{"name":"worker-one","agent_status":"%s","pane_id":"w1:p1"}]}}\n' \
        "${agent_status}" > "${WORKER_STUB_STATE}/agents.json"
}

function write_two_worker_snapshot() {
    cat > "${WORKER_STUB_STATE}/agents.json" << 'JSON'
{"result":{"agents":[
  {"name":"worker-one","agent_status":"working","pane_id":"w1:p1"},
  {"name":"worker-two","agent_status":"working","pane_id":"w2:p2"}
]}}
JSON
}

@test "[common] worker watcher validates its required prefix and interval arguments" {
    run "${WORKER_WATCH_SCRIPT}" --once

    [ "${status}" -eq 2 ]
    [[ "${output}" == *'Usage: herdr-worker-stall-watch.sh'* ]]

    run "${WORKER_WATCH_SCRIPT}" --agent-prefix worker- --interval-seconds 0 --once

    [ "${status}" -eq 2 ]
    [[ "${output}" == *'Usage: herdr-worker-stall-watch.sh'* ]]
}

@test "[common] worker watcher checks one cycle and excludes the named agent" {
    write_two_worker_snapshot
    printf '%s\n' 'no stall signatures' > "${WORKER_STUB_STATE}/pane.txt"

    run "${WORKER_WATCH_SCRIPT}" --agent-prefix worker- --exclude-agent worker-one --once

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'OK: scanned 1 matching agent(s)'* ]]
    [ "$(<"${WORKER_STUB_STATE}/pane-reads")" = 'w2:p2' ]
}

@test "[common] worker watcher alerts on a gateway retry loop" {
    write_worker_snapshot working
    printf '%s\n' 'Exceeded retry limit' > "${WORKER_STUB_STATE}/pane.txt"

    run "${WORKER_WATCH_SCRIPT}" --agent-prefix worker- --once

    [ "${status}" -eq 3 ]
    [[ "${output}" == *'STALL worker-one w1:p1 gateway reconnect loop'* ]]
}

@test "[common] worker watcher alerts on an unanswered queued question" {
    write_worker_snapshot blocked
    printf '%s\n' '? 1 question' > "${WORKER_STUB_STATE}/pane.txt"

    run "${WORKER_WATCH_SCRIPT}" --agent-prefix worker- --once

    [ "${status}" -eq 3 ]
    [[ "${output}" == *'STALL worker-one w1:p1 unanswered queued question'* ]]
}

@test "[common] worker watcher alerts on an empty restarted working session" {
    write_worker_snapshot working
    printf '%s\n' 'Context 0% used' > "${WORKER_STUB_STATE}/pane.txt"

    run "${WORKER_WATCH_SCRIPT}" --agent-prefix worker- --once

    [ "${status}" -eq 3 ]
    [[ "${output}" == *'STALL worker-one w1:p1 blank restarted session marked working'* ]]
}

@test "[common] zero context does not alert for a blocked worker" {
    write_worker_snapshot blocked
    printf '%s\n' 'Context 0% used' > "${WORKER_STUB_STATE}/pane.txt"

    run "${WORKER_WATCH_SCRIPT}" --agent-prefix worker- --once

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'OK: scanned 1 matching agent(s)'* ]]
    [[ "${output}" != *STALL* ]]
}
