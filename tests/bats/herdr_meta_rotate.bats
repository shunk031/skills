#!/usr/bin/env bats

readonly ROTATE_SCRIPT_PATH="./skills/herdr/shunk031-herdr-meta-orchestrate/scripts/herdr-meta-rotate.sh"

function setup() {
    ROTATE_STUB_STATE="$BATS_TEST_TMPDIR/rotate-stub"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$ROTATE_STUB_STATE/bin"
    mkdir -p "$HOME/.agents/skills/shunk031-herdr-orchestrate-workers/scripts"
    cp ./skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-visible-input-state.awk \
        "$HOME/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/"
    export ROTATE_STUB_STATE HERDR_ENV=1 ROTATE_TEST_ENV=preserved
    cat > "$ROTATE_STUB_STATE/bin/herdr" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$ROTATE_STUB_STATE/calls"
case "$1 $2" in
    "agent get")
        if [[ -f "$ROTATE_STUB_STATE/started" ]]; then
            touch "$ROTATE_STUB_STATE/verified"
            printf '%s\n' '{"result":{"agent":{"agent":"claude","agent_status":"idle","pane_id":"test:p1"}}}'
        else
            printf '%s\n' '{"result":{"agent":{"agent":"claude","agent_status":"idle","pane_id":"test:p1"}}}'
        fi
        ;;
    "pane read")
        if [[ "${ROTATE_STUB_INPUT:-}" == occupied ]]; then
            printf '❯ typed text\n'
        else
            printf '❯ \n'
        fi
        ;;
    "pane current")
        printf '%s\n' '{"result":{"pane":{"pane_id":"test:p1"}}}'
        ;;
    "pane process-info")
        if [[ -f "$ROTATE_STUB_STATE/agent_start_failed" && ! -f "$ROTATE_STUB_STATE/cleaned" ]]; then
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":43,"name":"claude","argv":["claude"]}]}}}'
        elif [[ -f "$ROTATE_STUB_STATE/exited" ]]; then
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":9,"name":"zsh","argv":["zsh"]}]}}}'
        else
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":42,"name":"claude","argv":["claude","--model","test-model"]}]}}}'
        fi
        ;;
    "agent wait")
        ;;
    "pane send-text")
        [[ "$4" == '/exit' ]]
        ;;
    "pane send-keys")
        [[ "$4" == enter ]]
        if [[ -f "$ROTATE_STUB_STATE/agent_start_failed" ]]; then
            touch "$ROTATE_STUB_STATE/cleaned"
        else
            touch "$ROTATE_STUB_STATE/exited"
        fi
        ;;
    "agent start")
        [[ "$ROTATE_TEST_ENV" == preserved ]]
        [[ "$*" == *'--model test-model'* ]]
        [[ "$*" == *'handoff.md'* ]]
        [[ "$*" == *'standing-permissions.md'* ]]
        [[ "$*" == *'open-items.md'* ]]
        [[ "$*" == *'herdr-meta-patrol-queue wait'* ]]
        if [[ "${ROTATE_STUB_FAIL_START:-}" == 1 ]]; then
            touch "$ROTATE_STUB_STATE/agent_start_failed"
            exit 1
        fi
        touch "$ROTATE_STUB_STATE/started"
        ;;
    "notification show")
        touch "$ROTATE_STUB_STATE/notified"
        ;;
    *) exit 2 ;;
esac
EOF
    chmod +x "$ROTATE_STUB_STATE/bin/herdr"
    PATH="$ROTATE_STUB_STATE/bin:$PATH"
    export PATH
    : > "$ROTATE_STUB_STATE/calls"
    printf 'fresh handoff\n' > "$ROTATE_STUB_STATE/handoff.md"
}

@test "dry run reports the model and leaves the pane untouched" {
    run "$ROTATE_SCRIPT_PATH" --dry-run "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *'--model test-model'* ]]
    ! grep -Eq 'agent wait|send-text|send-keys|agent start' "$ROTATE_STUB_STATE/calls"
}

@test "stale handoffs are rejected before starting a rotation" {
    perl -e 'utime(time - 601, time - 601, $ARGV[0])' "$ROTATE_STUB_STATE/handoff.md"

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *'no more than 10 minutes old'* ]]
    ! grep -Eq 'agent wait|send-text|send-keys|agent start' "$ROTATE_STUB_STATE/calls"
}

@test "missing handoffs are rejected before starting a rotation" {
    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/missing.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *'missing or unreadable'* ]]
    ! grep -Eq 'agent wait|send-text|send-keys|agent start' "$ROTATE_STUB_STATE/calls"
}

@test "rotation is detached and restarts meta with the captured model and handoff prompt" {
    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *'started in the background'* ]]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/verified" ]] && break
        sleep 0.1
    done
    if [[ ! -f "$ROTATE_STUB_STATE/verified" ]]; then
        cat "$ROTATE_STUB_STATE/calls"
        false
    fi
    grep -q 'agent wait meta --until idle' "$ROTATE_STUB_STATE/calls"
    grep -q 'pane send-text test:p1 /exit' "$ROTATE_STUB_STATE/calls"
    grep -q 'pane send-keys test:p1 enter' "$ROTATE_STUB_STATE/calls"
    grep -q 'agent start meta --kind claude --pane test:p1' "$ROTATE_STUB_STATE/calls"
}

@test "failed startup shows a notification and returns the pane to its shell" {
    export ROTATE_STUB_FAIL_START=1

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/notified" ]] && break
        sleep 0.1
    done
    [ -f "$ROTATE_STUB_STATE/notified" ]
    if [[ ! -f "$ROTATE_STUB_STATE/cleaned" ]]; then
        cat "$ROTATE_STUB_STATE/calls"
        false
    fi
}

@test "occupied composer input aborts before exiting meta" {
    export ROTATE_STUB_INPUT=occupied

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/notified" ]] && break
        sleep 0.1
    done
    [ -f "$ROTATE_STUB_STATE/notified" ]
    ! grep -Eq 'send-text|send-keys|agent start' "$ROTATE_STUB_STATE/calls"
}
