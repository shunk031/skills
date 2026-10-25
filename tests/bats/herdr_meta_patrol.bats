#!/usr/bin/env bats

readonly PATROL_SCRIPT_PATH="./skills/herdr/shunk031-herdr-meta-orchestrate/scripts/herdr-meta-patrol.sh"

function setup() {
    PATROL_STUB_STATE="$BATS_TEST_TMPDIR/patrol-stub"
    mkdir -p "$PATROL_STUB_STATE/bin"
    export PATROL_STUB_STATE HERDR_ENV=1
    cat > "$PATROL_STUB_STATE/bin/herdr" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
machine=''
if [[ "${1:-}" == --machine ]]; then
    machine="$2"
    shift 2
fi
command_name="$1 $2"
shift 2
case "$command_name" in
    "machine list")
        [[ "$machine" == '' && "$1" == --json ]] || exit 2
        printf '%s\n' '[{"label":"remote-down","enabled":true},{"label":"remote-ok","enabled":true},{"label":"disabled","enabled":false}]'
        ;;
    "agent list")
        case "$machine" in
            '')
                printf '%s\n' '{"result":{"agents":[{"name":"blocked","agent_status":"blocked","tokens":{"inbox":null}},{"name":"inbox","agent_status":"idle","tokens":{"inbox":{"text":"private"}}},{"pane_id":"local:p2","agent_status":"idle","tokens":{"inbox":{"text":"private"}}},{"name":"clean","agent_status":"idle","tokens":{"inbox":null}}]}}'
                ;;
            remote-down) exit 1 ;;
            remote-ok)
                printf '%s\n' '{"result":{"agents":[{"name":"remote-inbox","agent_status":"done","tokens":{"inbox":[]}}]}}'
                ;;
            *) exit 2 ;;
        esac
        ;;
    "agent get")
        case "$machine:$1" in
            :meta) printf '%s\n' '{"result":{"agent":{"pane_id":"local:p1"}}}' ;;
            remote-ok:root) printf '%s\n' '{"result":{"agent":{"pane_id":"remote:p1"}}}' ;;
            remote-ok:unreadable) printf '%s\n' '{"result":{"agent":{"pane_id":"unreadable:p1"}}}' ;;
            *) exit 2 ;;
        esac
        ;;
    "pane read")
        [[ "$2" == --source && "$3" == visible && "$4" == --format && "$5" == ansi && "$#" == 5 ]] || exit 3
        case "$machine:$1" in
            :local:p1) printf '❯ earlier text\n\033[36m❯\033[0m\302\240\033[2mSuggested completion without reset\r\n' ;;
            remote-ok:remote:p1) printf '\033[35m›\033[0m typed text \033[2mSuggestion\033[0m\n' ;;
            remote-ok:unreadable:p1) printf 'terminal output without a prompt\n' ;;
            *) exit 2 ;;
        esac
        ;;
    *) exit 2 ;;
esac
EOF
    chmod +x "$PATROL_STUB_STATE/bin/herdr"
    PATH="$PATROL_STUB_STATE/bin:$PATH"
    export PATH
}

@test "[common] patrol reports findings, ignores dim suggestions, and continues after a remote failure" {
    export HERDR_PATROL_ROOTS_JSON='[{"machine":null,"agent":"meta"},{"machine":"remote-down","agent":"orch"},{"machine":"remote-ok","agent":"root"},{"machine":"remote-ok","agent":"unreadable"},{"machine":"disabled","agent":"other"}]'

    run "$PATROL_SCRIPT_PATH"

    [ "$status" -eq 0 ]
    [ "$(jq -se 'length' <<< "$output")" -eq 8 ]
    jq -se 'any(.[]; .kind == "agent_attention" and .machine == "local" and .agent == "blocked" and .agent_status == "blocked" and .inbox_pending == false)' <<< "$output" > /dev/null
    jq -se 'any(.[]; .kind == "agent_attention" and .machine == "local" and .agent == "inbox" and .inbox_pending == true)' <<< "$output" > /dev/null
    jq -se 'any(.[]; .kind == "agent_attention" and .machine == "local" and .agent == null and .pane_id == "local:p2")' <<< "$output" > /dev/null
    jq -se 'any(.[]; .kind == "server_unavailable" and .machine == "remote-down")' <<< "$output" > /dev/null
    jq -se 'any(.[]; .kind == "agent_attention" and .machine == "remote-ok" and .agent == "remote-inbox" and .inbox_pending == true)' <<< "$output" > /dev/null
    jq -se 'any(.[]; .kind == "root_input_occupied" and .machine == "remote-ok" and .agent == "root")' <<< "$output" > /dev/null
    jq -se 'any(.[]; .kind == "root_input_unreadable" and .machine == "remote-ok" and .agent == "unreadable")' <<< "$output" > /dev/null
    jq -se 'any(.[]; .kind == "root_machine_not_enabled" and .machine == "disabled")' <<< "$output" > /dev/null
    ! jq -se 'any(.[]; .kind == "root_input_occupied" and .machine == "local" and .agent == "meta")' <<< "$output" > /dev/null
    ! grep -Eq 'typed text|private|Suggested completion' <<< "$output"
}

@test "[common] patrol rejects malformed root configuration before contacting Herdr" {
    export HERDR_PATROL_ROOTS_JSON='not-json'

    run "$PATROL_SCRIPT_PATH"

    [ "$status" -eq 2 ]
    [[ "$output" == *'"kind":"invalid_configuration"'* ]]
}
