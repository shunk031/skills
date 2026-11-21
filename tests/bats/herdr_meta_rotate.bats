#!/usr/bin/env bats

readonly ROTATE_SCRIPT_PATH="./skills/herdr/shunk031-herdr-meta-orchestrate/scripts/herdr-meta-rotate.sh"

function setup() {
    ROTATE_STUB_STATE="$BATS_TEST_TMPDIR/rotate-stub"
    unset INBOX_FEED
    export HOME="$BATS_TEST_TMPDIR/home"
    ROTATE_STUB_EXPECT_FEED_DIR="$HOME/.local/state/inbox/feeds"
    ROTATE_STUB_START_TIMEOUT=0
    ROTATE_STUB_NO_REMOTE=0
    ROTATE_STUB_FAIL_INBOX=0
    ROTATE_STUB_NEW_INPUT_OCCUPIED=0
    ROTATE_STUB_AFTER_START_BLOCKED=0
    mkdir -p "$HOME/.local/state/inbox/task-tree"
    mkdir -p "$ROTATE_STUB_STATE/bin"
    mkdir -p "$HOME/.agents/skills/shunk031-herdr-orchestrate-workers/scripts"
    cp ./skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-visible-input-state.awk \
        "$HOME/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/"
    export ROTATE_STUB_STATE ROTATE_STUB_EXPECT_FEED_DIR ROTATE_STUB_START_TIMEOUT ROTATE_STUB_NO_REMOTE
    export ROTATE_STUB_FAIL_INBOX ROTATE_STUB_NEW_INPUT_OCCUPIED ROTATE_STUB_AFTER_START_BLOCKED
    export HERDR_ENV=1 ROTATE_TEST_ENV=preserved
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
        if [[ -f "$ROTATE_STUB_STATE/started" && "${ROTATE_STUB_EXIT_AFTER_START:-}" == 1 ]]; then
            printf '%s\n' '{"result":{"agent":null}}'
            exit 0
        fi
        if [[ -f "$ROTATE_STUB_STATE/agent_start_failed" && ! -f "$ROTATE_STUB_STATE/started" ]]; then
            printf '%s\n' '{"result":{"agent":null}}'
            exit 0
        fi
        if [[ -f "$ROTATE_STUB_STATE/started" && "$ROTATE_STUB_START_TIMEOUT" == 1 && ! -f "$ROTATE_STUB_STATE/renamed" ]]; then
            printf '%s\n' '{"result":{"agent":null}}'
            exit 0
        fi
        agent_status=idle
        if [[ -f "$ROTATE_STUB_STATE/started" ]]; then
            if [[ "${ROTATE_STUB_AFTER_START_BLOCKED:-}" == 1 ]]; then
                agent_status=blocked
            elif [[ "${ROTATE_STUB_AFTER_START_UNKNOWN:-}" == 1 ]]; then
                agent_status=unknown
            elif [[ "${ROTATE_STUB_UNKNOWN_GETS:-0}" -gt 0 ]]; then
                get_count=0
                if [[ -f "$ROTATE_STUB_STATE/after_start_get_count" ]]; then
                    get_count="$(cat "$ROTATE_STUB_STATE/after_start_get_count")"
                fi
                get_count=$((get_count + 1))
                printf '%s\n' "$get_count" > "$ROTATE_STUB_STATE/after_start_get_count"
                if ((get_count <= ROTATE_STUB_UNKNOWN_GETS)); then
                    agent_status=unknown
                fi
            elif [[ "${ROTATE_STUB_AFTER_START_DONE:-}" == 1 ]]; then
                agent_status=done
            fi
        fi
        if [[ -f "$ROTATE_STUB_STATE/started" && "$agent_status" != unknown ]]; then
            touch "$ROTATE_STUB_STATE/verified"
        fi
        if [[ -f "$ROTATE_STUB_STATE/composer_checked" && "${ROTATE_STUB_WAKE_BEFORE_EXIT:-}" == 1 && ! -f "$ROTATE_STUB_STATE/started" ]]; then
            agent_status=working
        fi
        session_id=old-session
        if [[ -f "$ROTATE_STUB_STATE/started" ]]; then
            session_id=new-session
        fi
        printf '{"result":{"agent":{"agent":"claude","agent_status":"%s","pane_id":"test:p1","agent_session":{"value":"%s"}}}}\n' "$agent_status" "$session_id"
        ;;
    "agent rename")
        [[ "$3" == test:p1 && "$4" == meta ]]
        [[ -f "$ROTATE_STUB_STATE/started" ]]
        touch "$ROTATE_STUB_STATE/renamed"
        printf '%s\n' '{"result":{"renamed":true}}'
        ;;
    "pane read")
        if [[ "$*" == *'--format ansi'* ]]; then
            if [[ -f "$ROTATE_STUB_STATE/started" && "$ROTATE_STUB_NEW_INPUT_OCCUPIED" == 1 ]]; then
                printf '❯ typed text\n'
            elif [[ "${ROTATE_STUB_INPUT:-}" == occupied ]]; then
                printf '❯ typed text\n'
            else
                touch "$ROTATE_STUB_STATE/composer_checked"
                printf '❯ \n'
            fi
        elif [[ -f "$ROTATE_STUB_STATE/started" ]]; then
            if [[ -f "$ROTATE_STUB_STATE/inbox_requested" && "$ROTATE_STUB_FAIL_INBOX" == 1 ]]; then
                exit 1
            fi
            if [[ -f "$ROTATE_STUB_STATE/inbox_requested" ]]; then
                printf 'Remote Control /rc active https://claude.ai/code/session_test\nInbox\nOpened the inbox.\n'
            else
                printf 'Remote Control /rc active https://claude.ai/code/session_test\n'
            fi
        elif [[ -f "$ROTATE_STUB_STATE/exit_entered" && ! -f "$ROTATE_STUB_STATE/exited" && "${ROTATE_STUB_EXIT_DIALOG:-}" == 1 ]]; then
            touch "$ROTATE_STUB_STATE/exit_dialog_seen"
            printf 'Background work is running\n  1. Exit and stop tasks\n'
        elif [[ -f "$ROTATE_STUB_STATE/exit_entered" && ! -f "$ROTATE_STUB_STATE/exited" && "${ROTATE_STUB_CHAT_TEXT:-}" == 1 ]]; then
            printf 'Chat transcript: Background work is running while it describes the dialog.\n'
            touch "$ROTATE_STUB_STATE/exited"
        else
            touch "$ROTATE_STUB_STATE/composer_checked"
            printf '❯ \n'
        fi
        ;;
    "pane current")
        printf '%s\n' '{"result":{"pane":{"pane_id":"test:p1"}}}'
        ;;
    "pane process-info")
        if [[ -f "$ROTATE_STUB_STATE/started" && "${ROTATE_STUB_EXIT_AFTER_START:-}" == 1 ]]; then
            touch "$ROTATE_STUB_STATE/shell_verified"
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":9,"name":"zsh","argv":["zsh"]}]}}}'
        elif [[ -f "$ROTATE_STUB_STATE/started" ]]; then
            if [[ "$ROTATE_STUB_NO_REMOTE" == 1 ]]; then
                printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":44,"name":"claude","argv":["claude","--model","test-model"]}]}}}'
            else
                printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":44,"name":"claude","argv":["claude","--model","test-model","--remote-control","Meta orch."]}]}}}'
            fi
        elif [[ -f "$ROTATE_STUB_STATE/agent_start_failed" || -f "$ROTATE_STUB_STATE/exited" || -f "$ROTATE_STUB_STATE/cleaned" ]]; then
            touch "$ROTATE_STUB_STATE/shell_verified"
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":9,"name":"zsh","argv":["zsh"]}]}}}'
        elif [[ "${ROTATE_STUB_NO_MODEL:-}" == 1 ]]; then
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":42,"name":"claude","argv":["claude"]}]}}}'
        else
            printf '%s\n' '{"result":{"process_info":{"shell_pid":9,"foreground_processes":[{"pid":42,"name":"claude","argv":["claude","--model","test-model"]}]}}}'
        fi
        ;;
    "agent wait")
        if [[ -f "$ROTATE_STUB_STATE/started" ]]; then
            [[ "$*" == *'--until idle --until done --until blocked'* ]]
            if [[ "$ROTATE_STUB_AFTER_START_BLOCKED" == 1 ]]; then
                touch "$ROTATE_STUB_STATE/blocked_handoff_wait"
            fi
        else
            [[ "$*" == *'--until idle --until done'* ]]
        fi
        touch "$ROTATE_STUB_STATE/waited_for_done"
        if [[ -f "$ROTATE_STUB_STATE/started" ]]; then
            cat > "$HOME/.local/state/inbox/task-tree/new-session.json" << 'TASK_TREE'
{"schema":1,"session_id":"new-session","saved_at":"2026-11-21T00:00:00Z","tasks":[{"id":"old-open","title":"Outgoing open task","status":"queued","updated_at":"2026-11-21T00:00:00Z","owner":null,"pr":null,"parent_id":null,"warnings":[]},{"id":"old-child","title":"Outgoing child task","status":"waits-on-other","updated_at":"2026-11-21T00:00:00Z","owner":{"agent":"worker","machine":"local"},"pr":"https://github.com/acme/project/pull/12","parent_id":"old-open","warnings":[]}]}
TASK_TREE
        fi
        ;;
    "pane send-text")
        if [[ "$4" == '/exit' ]]; then
            [[ -d "$ROTATE_STUB_EXPECT_FEED_DIR" ]]
            touch "$ROTATE_STUB_STATE/exit_requested"
            touch "$ROTATE_STUB_STATE/feed_dir_ready_before_exit"
            if [[ "${ROTATE_STUB_TERM_ON_SEND:-}" == 1 ]]; then
                kill -TERM "$PPID"
                sleep 0.1
            fi
        elif [[ "$4" == '/inbox' ]]; then
            touch "$ROTATE_STUB_STATE/inbox_requested"
        else
            exit 2
        fi
        ;;
    "pane run")
        [[ "$3" == test:p1 ]]
        [[ -f "$ROTATE_STUB_STATE/exited" ]]
        [[ -d "$ROTATE_STUB_EXPECT_FEED_DIR" ]]
        [[ "$4" == export\ INBOX_FEED=* ]]
        printf '%s\n' "$4" > "$ROTATE_STUB_STATE/export_command"
        (
            unset INBOX_FEED
            eval "$4"
            printf '%s' "$INBOX_FEED"
        ) > "$ROTATE_STUB_STATE/exported_feed"
        ;;
    "pane send-keys")
        case "$4" in
            1)
                [[ -f "$ROTATE_STUB_STATE/exit_dialog_seen" ]]
                touch "$ROTATE_STUB_STATE/exit_option_selected"
                ;;
            enter)
                if [[ -f "$ROTATE_STUB_STATE/exit_option_selected" ]]; then
                    touch "$ROTATE_STUB_STATE/exited"
                elif [[ -f "$ROTATE_STUB_STATE/inbox_requested" ]]; then
                    touch "$ROTATE_STUB_STATE/inbox_opened"
                elif [[ -f "$ROTATE_STUB_STATE/agent_start_failed" ]]; then
                    touch "$ROTATE_STUB_STATE/cleaned"
                elif [[ "${ROTATE_STUB_EXIT_DIALOG:-}" == 1 || "${ROTATE_STUB_CHAT_TEXT:-}" == 1 ]]; then
                    touch "$ROTATE_STUB_STATE/exit_entered"
                else
                    touch "$ROTATE_STUB_STATE/exited"
                fi
                ;;
            *) exit 2 ;;
        esac
        ;;
    "agent start")
        [[ "$ROTATE_TEST_ENV" == preserved ]]
        [[ -f "$ROTATE_STUB_STATE/exported_feed" ]]
        [[ "$(cat "$ROTATE_STUB_STATE/exported_feed")" == "$ROTATE_STUB_EXPECT_FEED_DIR" ]]
        if [[ "${ROTATE_STUB_NO_MODEL:-}" == 1 ]]; then
            [[ "$*" != *'--model'* ]]
        else
            [[ "$*" == *'--model test-model'* ]]
        fi
        [[ "$*" == *'handoff.md'* ]]
        [[ "$*" == *'herdr-meta-patrol-queue wait'* ]]
        [[ "$*" == *'--remote-control Meta orch.'* ]]
        [[ "$*" == *'Outgoing open task'* ]]
        [[ "$*" == *'Outgoing child task'* ]]
        [[ "$*" == *'Inbox mcp__inbox__tasks tool with operation=add'* ]]
        [[ "$*" == *'Do not write task-tree JSON directly'* ]]
        start_count=0
        if [[ -f "$ROTATE_STUB_STATE/start_count" ]]; then
            start_count="$(cat "$ROTATE_STUB_STATE/start_count")"
        fi
        start_count=$((start_count + 1))
        printf '%s\n' "$start_count" > "$ROTATE_STUB_STATE/start_count"
        printf '%s\n' "$*" > "$ROTATE_STUB_STATE/start_args"
        if ((start_count <= ${ROTATE_STUB_FAIL_START:-0})); then
            touch "$ROTATE_STUB_STATE/agent_start_failed"
            exit 1
        fi
        touch "$ROTATE_STUB_STATE/started"
        if [[ "$ROTATE_STUB_START_TIMEOUT" == 1 ]]; then
            printf '%s\n' '{"code":"timeout","message":"timed out waiting for agent startup"}'
            exit 1
        fi
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
    cat > "$HOME/.local/state/inbox/task-tree/old-session.json" << 'EOF'
{"schema":1,"session_id":"old-session","saved_at":"2026-11-21T00:00:00Z","tasks":[{"id":"old-open","title":"Outgoing open task","status":"queued","updated_at":"2026-11-21T00:00:00Z","owner":null,"pr":null,"parent_id":null,"warnings":[]},{"id":"old-child","title":"Outgoing child task","status":"waits-on-other","updated_at":"2026-11-21T00:00:00Z","owner":{"agent":"worker","machine":"local"},"pr":"https://github.com/acme/project/pull/12","parent_id":"old-open","warnings":[]},{"id":"old-done","title":"Completed old task","status":"done","updated_at":"2026-11-21T00:00:00Z","owner":null,"pr":null,"parent_id":null,"warnings":[]}]}
EOF
}

@test "dry run reports the model and leaves the pane untouched" {
    run "$ROTATE_SCRIPT_PATH" --dry-run "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *'--model test-model'* ]]
    [[ "$output" == *"--remote-control 'Meta orch.'"* ]]
    ! grep -Eq 'agent wait|send-text|send-keys|pane run|agent start' "$ROTATE_STUB_STATE/calls"
}

@test "stale handoffs are rejected before starting a rotation" {
    perl -e 'utime(time - 601, time - 601, $ARGV[0])' "$ROTATE_STUB_STATE/handoff.md"

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *'no more than 10 minutes old'* ]]
    ! grep -Eq 'agent wait|send-text|send-keys|pane run|agent start' "$ROTATE_STUB_STATE/calls"
}

@test "missing handoffs are rejected before starting a rotation" {
    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/missing.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *'missing, empty, or unreadable'* ]]
    ! grep -Eq 'agent wait|send-text|send-keys|pane run|agent start' "$ROTATE_STUB_STATE/calls"
}

@test "empty handoffs are rejected before starting a rotation" {
    : > "$ROTATE_STUB_STATE/empty.md"

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/empty.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *'missing, empty, or unreadable'* ]]
    ! grep -Eq 'agent wait|send-text|send-keys|pane run|agent start' "$ROTATE_STUB_STATE/calls"
}

@test "rotation waits for done and accepts a completed session after restart" {
    export ROTATE_STUB_AFTER_START_DONE=1

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    [[ "$output" == *'started in the background'* ]]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/inbox_opened" ]] && break
        sleep 0.1
    done
    if [[ ! -f "$ROTATE_STUB_STATE/inbox_opened" ]]; then
        cat "$ROTATE_STUB_STATE/calls"
        false
    fi
    [ -f "$ROTATE_STUB_STATE/waited_for_done" ]
    grep -q 'agent wait meta --until idle --until done' "$ROTATE_STUB_STATE/calls"
    grep -q 'pane send-text test:p1 /exit' "$ROTATE_STUB_STATE/calls"
    grep -q 'pane send-keys test:p1 enter' "$ROTATE_STUB_STATE/calls"
    [ -f "$ROTATE_STUB_STATE/feed_dir_ready_before_exit" ]
    [ "$(cat "$ROTATE_STUB_STATE/exported_feed")" = "$ROTATE_STUB_EXPECT_FEED_DIR" ]
    [ "$(cat "$ROTATE_STUB_STATE/export_command")" = "export INBOX_FEED=$ROTATE_STUB_EXPECT_FEED_DIR" ]
    grep -Fq -- '--remote-control Meta orch.' "$ROTATE_STUB_STATE/start_args"
    grep -Fq 'Outgoing open task' "$ROTATE_STUB_STATE/start_args"
    grep -Fq 'Outgoing child task' "$ROTATE_STUB_STATE/start_args"
    grep -Fq 'mcp__inbox__tasks tool with operation=add' "$ROTATE_STUB_STATE/start_args"
    grep -Fq 'Do not write task-tree JSON directly' "$ROTATE_STUB_STATE/start_args"
    grep -Fq '"owner":{"agent":"worker","machine":"local"}' "$ROTATE_STUB_STATE/start_args"
    grep -Fq '"parent_id":"old-open"' "$ROTATE_STUB_STATE/start_args"
    grep -Fq 'https://github.com/acme/project/pull/12' "$ROTATE_STUB_STATE/start_args"
    ! grep -Fq 'Completed old task' "$ROTATE_STUB_STATE/start_args"
    [ -f "$HOME/.local/state/inbox/task-tree/new-session.json" ]
    export_line="$(grep -n '^pane run test:p1 export INBOX_FEED=' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    start_line="$(grep -n '^agent start meta ' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    [ "$export_line" -lt "$start_line" ]
    grep -q 'agent start meta --kind claude --pane test:p1' "$ROTATE_STUB_STATE/calls"
}

@test "the exit dialog selects option 1 before starting the handoff session" {
    export ROTATE_STUB_EXIT_DIALOG=1

    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    [ -f "$ROTATE_STUB_STATE/exit_option_selected" ]
    [ -f "$ROTATE_STUB_STATE/exited" ]
    [ -f "$ROTATE_STUB_STATE/shell_verified" ]
    [ -f "$ROTATE_STUB_STATE/verified" ]
    exit_request_line="$(grep -n 'pane send-text test:p1 /exit' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    dialog_read_line="$(awk -v after="$exit_request_line" 'NR > after && /^pane read test:p1 --source visible --format text/ { print NR; exit }' "$ROTATE_STUB_STATE/calls")"
    option_line="$(grep -n 'pane send-keys test:p1 1' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    enter_line="$(awk -v after="$option_line" 'NR > after && /^pane send-keys test:p1 enter/ { print NR; exit }' "$ROTATE_STUB_STATE/calls")"
    start_line="$(grep -n '^agent start meta ' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    [ "$exit_request_line" -lt "$dialog_read_line" ]
    [ "$dialog_read_line" -lt "$option_line" ]
    [ "$option_line" -lt "$enter_line" ]
    [ "$enter_line" -lt "$start_line" ]
    grep -Fq "Read the handoff file at $ROTATE_STUB_STATE/handoff.md first and follow its references." "$ROTATE_STUB_STATE/calls"
}

@test "chat text containing the dialog heading does not select an exit option" {
    export ROTATE_STUB_CHAT_TEXT=1

    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    [ -f "$ROTATE_STUB_STATE/exited" ]
    [ -f "$ROTATE_STUB_STATE/verified" ]
    ! grep -q 'pane send-keys test:p1 1' "$ROTATE_STUB_STATE/calls"
    grep -q 'pane read test:p1 --source visible --format text' "$ROTATE_STUB_STATE/calls"
}

@test "no exit dialog follows the normal shell-return path" {
    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    [ -f "$ROTATE_STUB_STATE/exited" ]
    [ -f "$ROTATE_STUB_STATE/shell_verified" ]
    [ -f "$ROTATE_STUB_STATE/verified" ]
    ! grep -q 'pane send-keys test:p1 1' "$ROTATE_STUB_STATE/calls"
    [ "$(grep -c 'pane send-keys test:p1 enter' "$ROTATE_STUB_STATE/calls")" -eq 2 ]
}

@test "the replacement starts named Remote Control and opens Inbox once after an empty-input check" {
    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    [ -f "$ROTATE_STUB_STATE/inbox_opened" ]
    grep -Fq -- '--remote-control Meta orch.' "$ROTATE_STUB_STATE/start_args"
    [ "$(grep -c 'pane send-text test:p1 /inbox' "$ROTATE_STUB_STATE/calls")" -eq 1 ]
    start_line="$(grep -n '^agent start meta ' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    remote_read_line="$(awk -v start="$start_line" 'NR > start && /^pane read test:p1 --source visible --format text/ { print NR; exit }' "$ROTATE_STUB_STATE/calls")"
    input_check_line="$(grep -n 'pane read test:p1 --source visible --format ansi' "$ROTATE_STUB_STATE/calls" | tail -1 | cut -d: -f1)"
    inbox_send_line="$(grep -n 'pane send-text test:p1 /inbox' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    inbox_verify_line="$(awk -v start="$inbox_send_line" 'NR > start && /^pane read test:p1 --source visible --format text/ { print NR; exit }' "$ROTATE_STUB_STATE/calls")"
    [ -n "$remote_read_line" ]
    [ "$remote_read_line" -lt "$input_check_line" ]
    [ "$input_check_line" -lt "$inbox_send_line" ]
    [ "$inbox_send_line" -lt "$inbox_verify_line" ]
}

@test "a timed-out start renames the verified Claude process and does not start twice" {
    export ROTATE_STUB_START_TIMEOUT=1

    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    [ -f "$ROTATE_STUB_STATE/renamed" ]
    [ -f "$ROTATE_STUB_STATE/inbox_opened" ]
    [ "$(cat "$ROTATE_STUB_STATE/start_count")" -eq 1 ]
    start_line="$(grep -n '^agent start meta ' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    rename_line="$(grep -n '^agent rename test:p1 meta' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    get_after_rename_line="$(awk -v start="$rename_line" 'NR > start && /^agent get meta/ { print NR; exit }' "$ROTATE_STUB_STATE/calls")"
    inbox_line="$(grep -n 'pane send-text test:p1 /inbox' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    [ "$start_line" -lt "$rename_line" ]
    [ "$rename_line" -lt "$get_after_rename_line" ]
    [ "$get_after_rename_line" -lt "$inbox_line" ]
}

@test "rotation fails without verified Remote Control and does not try Inbox" {
    export ROTATE_STUB_NO_REMOTE=1

    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *'did not verify Remote Control active'* ]]
    [ "$(cat "$ROTATE_STUB_STATE/start_count")" -eq 1 ]
    ! grep -q 'pane send-text test:p1 /inbox' "$ROTATE_STUB_STATE/calls"
}

@test "rotation fails when the new session input is occupied without sending Inbox" {
    export ROTATE_STUB_NEW_INPUT_OCCUPIED=1

    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *'new meta input was not empty'* ]]
    ! grep -q 'pane send-text test:p1 /inbox' "$ROTATE_STUB_STATE/calls"
}

@test "rotation reports an Inbox pane verification failure without retrying the command" {
    export ROTATE_STUB_FAIL_INBOX=1

    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *'did not verify the Inbox pane'* ]]
    [ "$(grep -c 'pane send-text test:p1 /inbox' "$ROTATE_STUB_STATE/calls")" -eq 1 ]
}

@test "an override with spaces, quotes, and dollars survives shell quoting" {
    export INBOX_FEED="$ROTATE_STUB_STATE/feeds with 'quotes' and \$dollars"
    export ROTATE_STUB_EXPECT_FEED_DIR="$INBOX_FEED"

    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    [ -f "$ROTATE_STUB_STATE/verified" ]
    [ "$(cat "$ROTATE_STUB_STATE/exported_feed")" = "$INBOX_FEED" ]
    printf -v expected_export 'export INBOX_FEED=%q' "$INBOX_FEED"
    [ "$(cat "$ROTATE_STUB_STATE/export_command")" = "$expected_export" ]
    export_line="$(grep -n '^pane run test:p1 export INBOX_FEED=' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    start_line="$(grep -n '^agent start meta ' "$ROTATE_STUB_STATE/calls" | cut -d: -f1)"
    [ "$export_line" -lt "$start_line" ]
}

@test "an INBOX_FEED directory creation failure leaves meta untouched" {
    printf 'not a directory\n' > "$ROTATE_STUB_STATE/not-a-directory"
    export INBOX_FEED="$ROTATE_STUB_STATE/not-a-directory/feeds"
    export ROTATE_STUB_EXPECT_FEED_DIR="$INBOX_FEED"

    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *'cannot create INBOX_FEED directory'* ]]
    ! grep -Eq '^(pane send-text|pane send-keys|pane run|agent start) ' "$ROTATE_STUB_STATE/calls"
}

@test "the root-orchestrator handoff launch path does not receive INBOX_FEED" {
    ! grep -R -q 'INBOX_FEED' ./skills/herdr/shunk031-herdr-orchestrator-handoff
}

@test "a blocked new session reports incomplete handoff without retrying or opening Inbox" {
    export ROTATE_STUB_AFTER_START_BLOCKED=1

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/notified" ]] && break
        sleep 0.1
    done
    [ -f "$ROTATE_STUB_STATE/notified" ]
    [ -f "$ROTATE_STUB_STATE/blocked_handoff_wait" ]
    [ "$(cat "$ROTATE_STUB_STATE/start_count")" -eq 1 ]
    [ "$(grep -c 'pane send-text test:p1 /exit' "$ROTATE_STUB_STATE/calls")" -eq 1 ]
    [ "$(grep -c 'pane send-keys test:p1 enter' "$ROTATE_STUB_STATE/calls")" -eq 1 ]
    grep -q 'blocked at a permission prompt' "$ROTATE_STUB_STATE/notification"
    ! grep -q 'pane send-text test:p1 /inbox' "$ROTATE_STUB_STATE/calls"
}

@test "a briefly unknown new session is accepted when Herdr sees it" {
    export ROTATE_STUB_UNKNOWN_GETS=2

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/after_start_get_count" && -f "$ROTATE_STUB_STATE/inbox_opened" ]] && break
        sleep 0.1
    done
    [ "$(cat "$ROTATE_STUB_STATE/after_start_get_count")" -ge 3 ]
    [ "$(cat "$ROTATE_STUB_STATE/start_count")" -eq 1 ]
    [ ! -f "$ROTATE_STUB_STATE/notified" ]
}

@test "a ready session that remains unknown is left running and not retried" {
    export ROTATE_STUB_AFTER_START_UNKNOWN=1

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 100; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/notified" ]] && break
        sleep 0.1
    done
    [ -f "$ROTATE_STUB_STATE/notified" ]
    [ "$(cat "$ROTATE_STUB_STATE/start_count")" -eq 1 ]
    [ "$(grep -c 'pane send-text test:p1 /exit' "$ROTATE_STUB_STATE/calls")" -eq 1 ]
    [ "$(grep -c 'pane send-keys test:p1 enter' "$ROTATE_STUB_STATE/calls")" -eq 1 ]
    ctrl_c_count="$(grep -c 'pane send-keys test:p1 ctrl+c' "$ROTATE_STUB_STATE/calls" || true)"
    [ "$ctrl_c_count" -eq 0 ]
    grep -q 'Restart command:' "$ROTATE_STUB_STATE/notification"
    [ "$(grep -c '^notification show ' "$ROTATE_STUB_STATE/calls")" -eq 1 ]
}

@test "a missing model option restarts successfully without an empty-array error" {
    export ROTATE_STUB_NO_MODEL=1

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/inbox_opened" ]] && break
        sleep 0.1
    done
    [ -f "$ROTATE_STUB_STATE/inbox_opened" ]
    ! grep -q -- '--model' "$ROTATE_STUB_STATE/calls"
}

@test "a transient startup failure is retried once and verified" {
    export ROTATE_STUB_FAIL_START=1

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/inbox_opened" ]] && break
        sleep 0.1
    done
    [ -f "$ROTATE_STUB_STATE/inbox_opened" ]
    [ "$(cat "$ROTATE_STUB_STATE/start_count")" -eq 2 ]
    [ ! -f "$ROTATE_STUB_STATE/notified" ]
}

@test "a ready start that exits to shell is retried and reports shell recovery" {
    export ROTATE_STUB_EXIT_AFTER_START=1

    run "$ROTATE_SCRIPT_PATH" "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 0 ]
    for ((attempt = 0; attempt < 50; attempt++)); do
        [[ -f "$ROTATE_STUB_STATE/notified" ]] && break
        sleep 0.1
    done
    [ -f "$ROTATE_STUB_STATE/notified" ]
    [ "$(cat "$ROTATE_STUB_STATE/start_count")" -eq 2 ]
    [ -f "$ROTATE_STUB_STATE/shell_verified" ]
    grep -q 'the new Claude session failed after one retry; the pane is back at its shell' "$ROTATE_STUB_STATE/notification"
    grep -q 'Restart command:' "$ROTATE_STUB_STATE/notification"
    untouched_alert_count="$(grep -c 'the new session was left untouched' "$ROTATE_STUB_STATE/notification" || true)"
    [ "$untouched_alert_count" -eq 0 ]
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
}

@test "the detached worker notifies on an unexpected error" {
    export ROTATE_STUB_FAIL_CLOCK=1

    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 1 ]
    [ -f "$ROTATE_STUB_STATE/notified" ]
    [ "$(grep -c '^notification show ' "$ROTATE_STUB_STATE/calls")" -eq 1 ]
}

@test "the detached worker notifies once when it receives SIGTERM" {
    export ROTATE_STUB_TERM_ON_SEND=1

    run "$ROTATE_SCRIPT_PATH" --background-worker "$ROTATE_STUB_STATE/handoff.md"

    [ "$status" -eq 143 ]
    [ -f "$ROTATE_STUB_STATE/notified" ]
    grep -q 'Restart command:' "$ROTATE_STUB_STATE/notification"
    [ "$(grep -c '^notification show ' "$ROTATE_STUB_STATE/calls")" -eq 1 ]
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
    ! grep -Eq '^(pane send-text|pane send-keys|pane run|agent start) ' "$ROTATE_STUB_STATE/calls"
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
    ! grep -Eq 'send-text|send-keys|pane run|agent start' "$ROTATE_STUB_STATE/calls"
}
