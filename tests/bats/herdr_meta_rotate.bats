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
    ln -s /bin/bash "$ROTATE_STUB_STATE/bin/bash"
    cat > "$ROTATE_STUB_STATE/bin/date" << 'EOF'
#!/usr/bin/env bash
if [[ "${ROTATE_STUB_FAIL_CLOCK:-}" == 1 && "${1:-}" != -r ]]; then
    exit 1
fi
exec /bin/date "$@"
EOF
    chmod +x "$ROTATE_STUB_STATE/bin/date"
    cat > "$ROTATE_STUB_STATE/bin/herdr" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$ROTATE_STUB_STATE/calls"
case "$1 $2" in
    "agent get")
        agent_status=idle
        if [[ -f "$ROTATE_STUB_STATE/started" ]]; then
            touch "$ROTATE_STUB_STATE/verified"
            if [[ "${ROTATE_STUB_AFTER_START_DONE:-}" == 1 ]]; then
                agent_status=done
            fi
        fi
        if [[ -f "$ROTATE_STUB_STATE/composer_checked" && "${ROTATE_STUB_WAKE_BEFORE_EXIT:-}" == 1 && ! -f "$ROTATE_STUB_STATE/started" ]]; then
            agent_status=working
        fi
        printf '{"result":{"agent":{"agent":"claude","agent_status":"%s","pane_id":"test:p1"}}}\n' "$agent_status"
        ;;
    "pane read")
        if [[ "${ROTATE_STUB_INPUT:-}" == occupied ]]; then
            printf '❯ typed text\n'
        else
            touch "$ROTATE_STUB_STATE/composer_checked"
            printf '❯ \n'
        fi
        ;;
    "pane current")
        printf '%s\n' '{"result":{"pane":{"pane_id":"test:p1"}}}'
        ;;
    "pane process-info")
        if [[ -f "$ROTATE_STUB_STATE/agent_start_failed" && ! -f "$ROTATE_STUB_STATE/cleaned" ]]; then
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":43,"name":"claude","argv":["claude"]}]}}}'
        elif [[ -f "$ROTATE_STUB_STATE/exited" || -f "$ROTATE_STUB_STATE/cleaned" ]]; then
            touch "$ROTATE_STUB_STATE/shell_verified"
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":9,"name":"zsh","argv":["zsh"]}]}}}'
        elif [[ "${ROTATE_STUB_NO_MODEL:-}" == 1 ]]; then
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":42,"name":"claude","argv":["claude"]}]}}}'
        else
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":42,"name":"claude","argv":["claude","--model","test-model"]}]}}}'
        fi
        ;;
    "agent wait")
        [[ "$*" == *'--until idle --until done'* ]]
        touch "$ROTATE_STUB_STATE/waited_for_done"
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
        if [[ "${ROTATE_STUB_NO_MODEL:-}" == 1 ]]; then
            [[ "$*" != *'--model'* ]]
        else
            [[ "$*" == *'--model test-model'* ]]
        fi
        [[ "$*" == *'handoff.md'* ]]
        [[ "$*" == *'herdr-meta-patrol-queue wait'* ]]
        [[ "$*" != *'standing-permissions.md'* ]]
        [[ "$*" != *'open-items.md'* ]]
        start_count=0
        if [[ -f "$ROTATE_STUB_STATE/start_count" ]]; then
            start_count="$(cat "$ROTATE_STUB_STATE/start_count")"
        fi
        start_count=$((start_count + 1))
        printf '%s\n' "$start_count" > "$ROTATE_STUB_STATE/start_count"
        if ((start_count <= ${ROTATE_STUB_FAIL_START:-0})); then
            touch "$ROTATE_STUB_STATE/agent_start_failed"
            exit 1
        fi
        touch "$ROTATE_STUB_STATE/started"
        ;;
    "notification show")
        printf '%s\n' "$*" >> "$ROTATE_STUB_STATE/notification"
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

@test "rotation waits for done and accepts a completed session after restart" {
    export ROTATE_STUB_AFTER_START_DONE=1

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
    [ -f "$ROTATE_STUB_STATE/waited_for_done" ]
    grep -q 'agent wait meta --until idle --until done' "$ROTATE_STUB_STATE/calls"
    grep -q 'pane send-text test:p1 /exit' "$ROTATE_STUB_STATE/calls"
    grep -q 'pane send-keys test:p1 enter' "$ROTATE_STUB_STATE/calls"
    grep -q 'agent start meta --kind claude --pane test:p1' "$ROTATE_STUB_STATE/calls"
}

@test "a missing model option restarts successfully without an empty-array error" {
    export ROTATE_STUB_NO_MODEL=1

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/verified" ]] && break
        sleep 0.1
    done
    [ -f "$ROTATE_STUB_STATE/verified" ]
    ! grep -q -- '--model' "$ROTATE_STUB_STATE/calls"
}

@test "a transient startup failure is retried once and verified" {
    export ROTATE_STUB_FAIL_START=1

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/verified" ]] && break
        sleep 0.1
    done
    [ -f "$ROTATE_STUB_STATE/verified" ]
    [ "$(cat "$ROTATE_STUB_STATE/start_count")" -eq 2 ]
    [ ! -f "$ROTATE_STUB_STATE/notified" ]
}

@test "persistent startup failure retries once, notifies with the command, and returns to shell" {
    export ROTATE_STUB_FAIL_START=2

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/notified" ]] && break
        sleep 0.1
    done
    [ -f "$ROTATE_STUB_STATE/notified" ]
    [ "$(cat "$ROTATE_STUB_STATE/start_count")" -eq 2 ]
    [ -f "$ROTATE_STUB_STATE/shell_verified" ]
    grep -q 'Restart command:' "$ROTATE_STUB_STATE/notification"
    grep -q -- '--model test-model' "$ROTATE_STUB_STATE/notification"
    grep -q 'handoff.md' "$ROTATE_STUB_STATE/notification"
    grep -q 'herdr-meta-patrol-queue' "$ROTATE_STUB_STATE/notification"
    if [[ ! -f "$ROTATE_STUB_STATE/cleaned" ]]; then
        cat "$ROTATE_STUB_STATE/calls"
        false
    fi
}

@test "the detached worker notifies on an unexpected error" {
    export ROTATE_STUB_FAIL_CLOCK=1

    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 1 ]
    [ -f "$ROTATE_STUB_STATE/notified" ]
}

@test "a patrol wake before exit aborts when meta is working" {
    export ROTATE_STUB_WAKE_BEFORE_EXIT=1

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/notified" ]] && break
        sleep 0.1
    done
    [ -f "$ROTATE_STUB_STATE/notified" ]
    ! grep -Eq 'pane send-text|pane send-keys|agent start' "$ROTATE_STUB_STATE/calls"
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
