#!/usr/bin/env bats

readonly PATROL_SCRIPT_PATH="./skills/herdr/shunk031-herdr-meta-orchestrate/scripts/herdr-meta-patrol.sh"

function setup() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    export HERDR_ENV=1
    export HERDR_META_PATROL_META=meta
    export HERDR_META_PATROL_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    export HERDR_META_PATROL_PROMPT_GUARD="${BATS_TEST_TMPDIR}/prompt-guard"
    export FAKE_AGENTS="${BATS_TEST_TMPDIR}/agents.json"
    export FAKE_PANE="${BATS_TEST_TMPDIR}/pane.txt"
    export NOTIFICATION_LOG="${BATS_TEST_TMPDIR}/notifications.log"
    export PROMPT_LOG="${BATS_TEST_TMPDIR}/prompts.log"
    mkdir -p "${BATS_TEST_TMPDIR}/bin" "${HERDR_META_PATROL_STATE_DIR}"
    PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    export PATH

    cat > "${BATS_TEST_TMPDIR}/bin/herdr" << 'STUB'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$1 $2" in
    "agent list") cat "${FAKE_AGENTS}" ;;
    "pane read")
        [[ "$3" == p-meta && "$4" == --source && "$5" == visible && "$6" == --format && "$7" == text ]] || exit 2
        cat "${FAKE_PANE}"
        ;;
    "notification show") printf '%s\n' "$*" >> "${NOTIFICATION_LOG}" ;;
    *) exit 2 ;;
esac
STUB
    cat > "${HERDR_META_PATROL_PROMPT_GUARD}" << 'STUB'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\t%s\n' "$1" "$2" >> "${PROMPT_LOG}"
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/herdr" "${HERDR_META_PATROL_PROMPT_GUARD}"
    printf '%s\n' 'Working normally' > "${FAKE_PANE}"
    write_agents idle null idle
}

function write_agents() {
    local meta_status="$1" inbox_json="$2" worker_status="$3"
    jq -n --arg meta_status "${meta_status}" --argjson inbox "${inbox_json}" --arg worker_status "${worker_status}" \
        '{result:{agents:[
            {name:"meta",pane_id:"p-meta",agent_status:$meta_status,tokens:{inbox:$inbox}},
            {name:"meta-review",pane_id:"p-review",agent_status:$worker_status,tokens:{inbox:null}},
            {name:"other-review",pane_id:"p-other",agent_status:$worker_status,tokens:{inbox:null}}
        ]}}' > "${FAKE_AGENTS}"
}

function write_waiting_review_status() {
    jq -cn '{seq:1,t:1,kind:"message",from:"meta-review",text:"STATUS meta-review: 21:00 waiting for meta review; ETA after reset"}' \
        > "${HERDR_META_PATROL_STATE_DIR}/queue.jsonl"
}

function line_count() {
    [[ -f "$1" ]] || {
        printf '0'
        return
    }
    wc -l < "$1" | tr -d '[:space:]'
}

@test "limit banner notifies once, prompts the waiting worker once, and rearms after meta works" {
    write_agents idle null idle
    write_waiting_review_status
    printf '%s\n' "You've hit your weekly limit · resets 9pm" > "${FAKE_PANE}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]
    grep -Fq 'until 9pm' "${NOTIFICATION_LOG}"
    grep -Fq 'hold periodic STATUS' "${PROMPT_LOG}"
    grep -Fq 'exact HEAD' "${PROMPT_LOG}"
    grep -Fq 'Codex during meta' "${PROMPT_LOG}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]

    write_agents working null idle
    printf '%s\n' 'Meta resumed work' > "${FAKE_PANE}"
    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ ! -e "${HERDR_META_PATROL_STATE_DIR}/meta-limit-episode.json" ]

    write_agents idle null idle
    printf '%s\n' "You've hit your weekly limit · resets Mon 12:00am" > "${FAKE_PANE}"
    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 2 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 2 ]
    grep -Fq 'until Mon 12:00am' "${NOTIFICATION_LOG}"
}

@test "meta inbox limit token is detected when the pane has no limit banner" {
    write_agents idle '"! Limit: resets 10pm"' idle
    write_waiting_review_status
    printf '%s\n' 'Waiting for the reset' > "${FAKE_PANE}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold

    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]
    grep -Fq 'until 10pm' "${NOTIFICATION_LOG}"
}

@test "only a worker's latest STATUS can mark it as waiting for meta review" {
    write_agents idle null idle
    {
        jq -cn '{seq:1,t:1,kind:"message",from:"meta-review",text:"STATUS meta-review: 21:00 waiting for meta review"}'
        jq -cn '{seq:2,t:2,kind:"message",from:"meta-review",text:"STATUS meta-review: 21:01 waiting for root review"}'
    } > "${HERDR_META_PATROL_STATE_DIR}/queue.jsonl"
    printf '%s\n' "You've hit your weekly limit · resets 9pm" > "${FAKE_PANE}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold

    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 0 ]
}
