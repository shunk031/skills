#!/usr/bin/env bats

# Behaviour tests for the observer script this skill ships. The script used to
# live in shunk031/dotfiles, and its test stayed behind when the skill moved,
# leaving the script untested. It is tested here, next to what it belongs to.

readonly OBSERVER_SCRIPT_PATH="./skills/shunk031-herdr-orchestrate-workers/scripts/herdr-orchestrator-observer.sh"

function setup() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}/.local/bin"
    OBSERVER_PID=''
}

function teardown() {
    # The observer runs in the background, so a failing assertion would
    # otherwise leave it polling after the test that started it has ended.
    if [[ -n "${OBSERVER_PID}" ]] && kill -0 "${OBSERVER_PID}" 2> /dev/null; then
        kill "${OBSERVER_PID}" 2> /dev/null || true
        wait "${OBSERVER_PID}" 2> /dev/null || true
    fi
    PATH=$(getconf PATH)
    export PATH
}

@test "[common] observer coalesces scoped lifecycle truth and stops cleanly" {
    HERDR_OBSERVER_STUB_STATE="${BATS_TEST_TMPDIR}/observer-state"
    export HERDR_OBSERVER_STUB_STATE
    mkdir -p "${HERDR_OBSERVER_STUB_STATE}"
    mkdir -p "${BATS_TEST_TMPDIR}/observer-bin"
    cat > "${BATS_TEST_TMPDIR}/observer-bin/herdr" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state_dir="${HERDR_OBSERVER_STUB_STATE:?}"
command_name="${1:-} ${2:-}"
shift 2 || true
case "${command_name}" in
    "agent list")
        printf '%s\n' sample >> "${state_dir}/samples"
        if [[ "$(<"${state_dir}/agents_mode")" == malformed ]]; then
            printf '%s\n' malformed-json
        else
            cat "${state_dir}/agents.json"
        fi
        ;;
    "agent read")
        target="${1:?}"
        [[ "${target}" != unreadable ]] || exit 1
        if [[ "${target}" == moving ]]; then
            printf 'moving %s\n' "$(date +%s%N)"
        else
            cat "${state_dir}/transcript_${target}"
        fi
        ;;
    "agent prompt")
        target="${1:?}"
        report="${2:?}"
        [[ "${target}" == orch264 ]] || exit 1
        one_line="${report//$'\n'/ }"
        printf '%s\n' "${one_line}" >> "${state_dir}/prompts"
        ;;
    "tab get")
        case "${1:?}" in
            w1:t1) printf '%s\n' '{"result":{"tab":{"label":"🚧 stale task"}}}' ;;
            w2:t1) printf '%s\n' '{"result":{"tab":{"label":"🚧 moving task"}}}' ;;
            w3:t1) printf '%s\n' '{"result":{"tab":{"label":"✅ clean audit"}}}' ;;
            w4:t1) printf '%s\n' '{"result":{"tab":{"label":"⛔ review and merge PR 264"}}}' ;;
            w5:t1) printf '%s\n' '{"result":{"tab":{"label":"🚧 unreadable task"}}}' ;;
            w6:t1) printf '%s\n' '{"result":{"tab":{"label":"🚧 foreign task"}}}' ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 2 ;;
esac
EOF
    chmod +x "${BATS_TEST_TMPDIR}/observer-bin/herdr"
    cat > "${HERDR_OBSERVER_STUB_STATE}/agents.json" << 'EOF'
{"result":{"agents":[
  {"name":"stale","agent_status":"working","revision":1,"state_change_seq":1,"pane_id":"w1:p1","tab_id":"w1:t1"},
  {"name":"moving","agent_status":"working","revision":1,"state_change_seq":1,"pane_id":"w2:p1","tab_id":"w2:t1"},
  {"name":"complete","agent_status":"done","revision":1,"state_change_seq":1,"pane_id":"w3:p1","tab_id":"w3:t1"},
  {"name":"pr-wait","agent_status":"done","revision":1,"state_change_seq":1,"pane_id":"w4:p1","tab_id":"w4:t1"},
  {"name":"unreadable","agent_status":"working","revision":1,"state_change_seq":1,"pane_id":"w5:p1","tab_id":"w5:t1"},
  {"name":"foreign","agent_status":"working","revision":1,"state_change_seq":1,"pane_id":"w6:p1","tab_id":"w6:t1"}
]},"type":"agent_list"}
EOF
    printf '%s\n' 'stale transcript' > "${HERDR_OBSERVER_STUB_STATE}/transcript_stale"
    printf '%s\n' 'completed transcript' > "${HERDR_OBSERVER_STUB_STATE}/transcript_complete"
    printf '%s\n' 'open PR transcript' > "${HERDR_OBSERVER_STUB_STATE}/transcript_pr-wait"
    printf '%s\n' 'foreign transcript' > "${HERDR_OBSERVER_STUB_STATE}/transcript_foreign"
    printf '%s\n' malformed > "${HERDR_OBSERVER_STUB_STATE}/agents_mode"
    export HERDR_ENV=1
    PATH="${BATS_TEST_TMPDIR}/observer-bin:${PATH}"
    export PATH
    : > "${HERDR_OBSERVER_STUB_STATE}/prompts"
    : > "${HERDR_OBSERVER_STUB_STATE}/samples"

    launch_log="${BATS_TEST_TMPDIR}/observer.log"
    "${OBSERVER_SCRIPT_PATH}" --orchestrator orch264 --worker "stale|w1:p1|w1:t1" --worker "moving|w2:p1|w2:t1" --worker "complete|w3:p1|w3:t1" --worker "pr-wait|w4:p1|w4:t1" --worker "missing|w9:p1|w9:t1" --worker "unreadable|w5:p1|w5:t1" --interval-seconds 1 --stale-samples 2 > "${launch_log}" 2>&1 &
    OBSERVER_PID=$!
    kill -0 "${OBSERVER_PID}"

    for _ in {1..50}; do
        grep -Fq 'observer: malformed herdr agent list; sample rejected' "${launch_log}" && break
        sleep 0.1
    done
    grep -Fq 'observer: malformed herdr agent list; sample rejected' "${launch_log}"
    [ ! -s "${HERDR_OBSERVER_STUB_STATE}/prompts" ]
    printf '%s\n' valid > "${HERDR_OBSERVER_STUB_STATE}/agents_mode"

    for _ in {1..50}; do
        [ "$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/prompts")" -ge 1 ] && break
        sleep 0.1
    done
    [ "$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/prompts")" -ge 1 ]
    grep -F 'OBSERVER orch264: bounded reconciliation required' "${HERDR_OBSERVER_STUB_STATE}/prompts"
    grep -F 'worker=complete ' "${HERDR_OBSERVER_STUB_STATE}/prompts"
    ! grep -Fq 'worker=moving ' "${HERDR_OBSERVER_STUB_STATE}/prompts"

    for _ in {1..50}; do
        [ "$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/prompts")" -eq 2 ] && break
        sleep 0.1
    done
    [ "$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/prompts")" -eq 2 ]
    grep -F 'worker=stale ' "${HERDR_OBSERVER_STUB_STATE}/prompts"
    ! grep -Fq 'worker=foreign ' "${HERDR_OBSERVER_STUB_STATE}/prompts"
    ! grep -Fq 'pr-wait' "${HERDR_OBSERVER_STUB_STATE}/prompts"
    ! grep -Fq 'unreadable' "${HERDR_OBSERVER_STUB_STATE}/prompts"
    sample_count="$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/samples")"
    printf '%s\n' 'stale transcript moved' > "${HERDR_OBSERVER_STUB_STATE}/transcript_stale"

    for _ in {1..50}; do
        [ "$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/samples")" -gt "${sample_count}" ] && break
        sleep 0.1
    done
    [ "$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/samples")" -gt "${sample_count}" ]
    [ "$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/prompts")" -eq 2 ]

    sample_count="$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/samples")"
    for _ in {1..50}; do
        if [ "$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/samples")" -gt "${sample_count}" ] && [ "$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/prompts")" -eq 3 ]; then
            break
        fi
        sleep 0.1
    done
    [ "$(wc -l < "${HERDR_OBSERVER_STUB_STATE}/prompts")" -eq 3 ]
    printf '%s\n' '{"result":{"agents":[]},"type":"agent_list"}' > "${HERDR_OBSERVER_STUB_STATE}/agents.json"

    for _ in {1..50}; do
        ! kill -0 "${OBSERVER_PID}" 2> /dev/null && break
        sleep 0.1
    done
    ! kill -0 "${OBSERVER_PID}"
    OBSERVER_PID=''
}
