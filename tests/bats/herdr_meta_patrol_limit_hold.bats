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

function write_ready_review_status() {
    jq -cn '{seq:1,t:1,kind:"message",from:"meta-review",text:"STATUS meta-review: 21:00 ready for review head=0123456789abcdef0123456789abcdef01234567; ETA 21:30"}' \
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
    write_agents idle null done
    write_ready_review_status
    printf '%s\n' "⎿ You've hit your weekly limit · resets 9pm" > "${FAKE_PANE}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]
    grep -Fq 'until 9pm' "${NOTIFICATION_LOG}"
    grep -Fq 'hold periodic STATUS' "${PROMPT_LOG}"
    grep -Fq 'exact HEAD' "${PROMPT_LOG}"
    grep -Fq 'Codex review during meta usage limit' "${PROMPT_LOG}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]

    write_agents done null done
    printf '%s\n' 'Meta finished its turn' > "${FAKE_PANE}"
    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ -e "${HERDR_META_PATROL_STATE_DIR}/meta-limit-episode.json" ]

    write_agents working null done
    printf '%s\n' "⎿ You've hit your weekly limit · resets 9pm" > "${FAKE_PANE}"
    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ "$(jq -r '.active' "${HERDR_META_PATROL_STATE_DIR}/meta-limit-episode.json")" = false ]
    jq -e '.suppressed_resets | index("9pm") != null' "${HERDR_META_PATROL_STATE_DIR}/meta-limit-episode.json" > /dev/null
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]

    write_agents idle null done
    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]

    printf '%s\n' 'Meta resumed; the old banner has left the pane' > "${FAKE_PANE}"
    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ ! -e "${HERDR_META_PATROL_STATE_DIR}/meta-limit-episode.json" ]

    printf '%s\n' "⎿ You've hit your weekly limit · resets 9pm" > "${FAKE_PANE}"
    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 2 ]

    write_agents idle null done
    printf '%s\n' "⎿ You've hit your weekly limit · resets Mon 12:00am" > "${FAKE_PANE}"
    run bash "${PATROL_SCRIPT_PATH}" --limit-hold
    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 3 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 3 ]
    grep -Fq 'until Mon 12:00am' "${NOTIFICATION_LOG}"
}

@test "meta inbox limit token is detected when the pane has no limit banner" {
    write_agents idle '"! Limit: resets 10pm"' done
    write_ready_review_status
    printf '%s\n' 'Waiting for the reset' > "${FAKE_PANE}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold

    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]
    grep -Fq 'until 10pm' "${NOTIFICATION_LOG}"
}

@test "the latest banner reset wins over a different inbox reset for the whole episode" {
    write_agents idle '"! Limit: resets 10pm"' done
    write_ready_review_status
    printf '%s\n' "⎿ You've hit your weekly limit · resets 9pm" > "${FAKE_PANE}"

    for _ in 1 2 3 4; do
        run bash "${PATROL_SCRIPT_PATH}" --limit-hold
        [ "${status}" -eq 0 ]
    done

    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]
    grep -Fq 'until 9pm' "${NOTIFICATION_LOG}"
    grep -Fq 'Codex review during meta usage limit' "${PROMPT_LOG}"
}

@test "the last matching banner line supplies the reset for a changed episode" {
    write_agents idle null done
    write_ready_review_status
    printf '%s\n' "⎿ You've hit your weekly limit · resets 9pm" > "${FAKE_PANE}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold

    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]

    {
        printf '%s\n' "⎿ You've hit your weekly limit · resets 9pm"
        printf '%s\n' "⎿ You've hit your weekly limit · resets 10pm"
    } > "${FAKE_PANE}"
    run bash "${PATROL_SCRIPT_PATH}" --limit-hold

    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 2 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 2 ]
    grep -Fq 'until 10pm' "${NOTIFICATION_LOG}"
}

@test "Claude limit banners cover supported usage-limit line variants" {
    local banner expected=1
    write_ready_review_status
    write_agents idle null done
    for banner in \
        "⎿ You've hit your limit · resets 9pm" \
        "⎿ You’ve hit your limit · resets 9pm" \
        "⎿ Claude usage limit reached · resets 9pm" \
        "⎿ 5-hour limit reached · resets 9pm" \
        "⎿ Weekly limit reached · resets 9pm" \
        "⎿ Session limit reached · resets 9pm"; do
        write_agents idle null done
        printf '%s\n' "$banner" > "${FAKE_PANE}"
        run bash "${PATROL_SCRIPT_PATH}" --limit-hold
        [ "${status}" -eq 0 ]
        [ "$(line_count "${NOTIFICATION_LOG}")" -eq "${expected}" ]
        expected=$((expected + 1))

        printf '%s\n' 'Meta resumed work' > "${FAKE_PANE}"
        write_agents working null done
        run bash "${PATROL_SCRIPT_PATH}" --limit-hold
        [ "${status}" -eq 0 ]
        [ ! -e "${HERDR_META_PATROL_STATE_DIR}/meta-limit-episode.json" ]
    done
    [ "$(line_count "${PROMPT_LOG}")" -eq 6 ]
}

@test "quoted usage-limit text in meta's pane does not start a limit episode" {
    write_agents idle null done
    write_ready_review_status
    printf '%s\n' 'Meta summarized: ⎿ Weekly limit reached · resets 9pm' > "${FAKE_PANE}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold

    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 0 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 0 ]
    [ ! -e "${HERDR_META_PATROL_STATE_DIR}/meta-limit-episode.json" ]
}

@test "periodic STATUS keeps a waiting worker eligible for its review notice" {
    write_agents idle null done
    {
        jq -cn '{seq:1,t:1,kind:"message",from:"meta-review",text:"STATUS meta-review: 21:00 ready for review head=0123456789abcdef0123456789abcdef01234567; ETA 21:30"}'
        jq -cn '{seq:2,t:2,kind:"message",from:"meta-review",text:"STATUS meta-review: 21:01 ready for review head=0123456789abcdef0123456789abcdef01234567; ETA 21:45"}'
    } > "${HERDR_META_PATROL_STATE_DIR}/queue.jsonl"
    printf '%s\n' "⎿ You've hit your weekly limit · resets 9pm" > "${FAKE_PANE}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold

    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]
}

@test "the sender's latest DONE record removes it from the review waiters" {
    write_agents idle null done
    {
        jq -cn '{seq:1,t:1,kind:"message",from:"meta-review",text:"STATUS meta-review: 21:00 ready for review head=0123456789abcdef0123456789abcdef01234567; ETA 21:30"}'
        jq -cn '{seq:2,t:2,kind:"message",from:"meta-review",text:"DONE meta-review: Codex review verdict accepted for head 0123456789abcdef0123456789abcdef01234567"}'
    } > "${HERDR_META_PATROL_STATE_DIR}/queue.jsonl"
    printf '%s\n' "⎿ You've hit your weekly limit · resets 9pm" > "${FAKE_PANE}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold

    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 0 ]
}

@test "a changed reset starts a new episode when patrol missed recovery" {
    write_agents idle null done
    write_ready_review_status
    printf '%s\n' "⎿ You've hit your weekly limit · resets 9pm" > "${FAKE_PANE}"

    run bash "${PATROL_SCRIPT_PATH}" --limit-hold

    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 1 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 1 ]

    printf '%s\n' "⎿ You've hit your weekly limit · resets 10pm" > "${FAKE_PANE}"
    run bash "${PATROL_SCRIPT_PATH}" --limit-hold

    [ "${status}" -eq 0 ]
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 2 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 2 ]
    grep -Fq 'until 10pm' "${NOTIFICATION_LOG}"
}

@test "reset times accept full weekday names and month-day dates" {
    local reset
    write_ready_review_status
    for reset in "Tuesday 9pm" "Wednesday 9pm" "Thursday 9pm" "Saturday 9pm" "Nov 20"; do
        write_agents idle null done
        printf '%s\n' "⎿ Weekly limit reached · resets ${reset}" > "${FAKE_PANE}"

        run bash "${PATROL_SCRIPT_PATH}" --limit-hold

        [ "${status}" -eq 0 ]
        grep -Fq "until ${reset}" "${NOTIFICATION_LOG}"

        write_agents working null done
        run bash "${PATROL_SCRIPT_PATH}" --limit-hold
        [ "${status}" -eq 0 ]
        [ "$(jq -r '.active' "${HERDR_META_PATROL_STATE_DIR}/meta-limit-episode.json")" = false ]
        jq -e --arg reset "${reset}" '.suppressed_resets | index($reset) != null' "${HERDR_META_PATROL_STATE_DIR}/meta-limit-episode.json" > /dev/null
    done
    [ "$(line_count "${NOTIFICATION_LOG}")" -eq 5 ]
    [ "$(line_count "${PROMPT_LOG}")" -eq 5 ]
}
