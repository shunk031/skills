#!/usr/bin/env bats

readonly PROMPT_HELPER_PATH="./skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh"

function setup() {
    STUB_STATE="$BATS_TEST_TMPDIR/prompt-stub"
    mkdir -p "$STUB_STATE/bin"
    export PROMPT_STUB_STATE="$STUB_STATE"
    export HERDR_ENV=1
    : > "$STUB_STATE/reads"
    : > "$STUB_STATE/sleeps"
    cat > "$STUB_STATE/bin/herdr" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state_dir="$PROMPT_STUB_STATE"
command_name="$1 $2"
shift 2
case "$command_name" in
    "agent get")
        printf '%s\n' '{"result":{"agent":{"pane_id":"w1:p1"}}}'
        ;;
    "pane read")
        [[ "$1" == w1:p1 && "$2" == --source && "$3" == visible && "$4" == --format && "$5" == ansi && "$#" == 5 ]] || exit 1
        read_count="$(wc -l < "$state_dir/reads" | tr -d '[:space:]')"
        read_count=$((read_count + 1))
        printf '%s\n' read >> "$state_dir/reads"
        if [[ -f "$state_dir/snapshot_$read_count" ]]; then
            cat "$state_dir/snapshot_$read_count"
        else
            cat "$state_dir/snapshot"
        fi
        ;;
    "agent prompt")
        printf '%s\n' "$1" > "$state_dir/prompt_target"
        printf '%s' "$2" > "$state_dir/prompt_message"
        ;;
    *)
        exit 2
        ;;
esac
EOF
    cat > "$STUB_STATE/bin/sleep" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$PROMPT_STUB_STATE/sleeps"
EOF
    chmod +x "$STUB_STATE/bin/herdr" "$STUB_STATE/bin/sleep"
    PATH="$STUB_STATE/bin:$PATH"
    export PATH
}

@test "[common] dimmed Codex and Claude prompt suggestions count as empty" {
    printf '› \033[2mAsk Codex to do anything\033[0m\n' > "$STUB_STATE/snapshot"
    run "$PROMPT_HELPER_PATH" codex "report"
    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_STATE/prompt_target")" = codex ]
    [ "$(cat "$STUB_STATE/prompt_message")" = report ]

    rm -f "$STUB_STATE/prompt_target" "$STUB_STATE/prompt_message"
    printf '❯ \033[2mDraft suggestion\033[0m\n' > "$STUB_STATE/snapshot"
    run "$PROMPT_HELPER_PATH" claude "relay"
    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_STATE/prompt_target")" = claude ]
    [ "$(cat "$STUB_STATE/prompt_message")" = relay ]
}

@test "[common] nested ANSI Codex placeholder with trailing CR counts as empty" {
    printf '\033[0m\033[1m\033[48;2;30;30;30m›\033[0m\033[48;2;30;30;30m \033[0m\033[2m\033[48;2;30;30;30mAsk Codex to do anything\033[0m\033[48;2;30;30;30m    \033[0m\r\n' > "$STUB_STATE/snapshot"

    run "$PROMPT_HELPER_PATH" codex "report"

    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_STATE/prompt_target")" = codex ]
    [ "$(cat "$STUB_STATE/prompt_message")" = report ]
}

@test "[common] real text after a dim placeholder keeps the input occupied" {
    printf '› \033[1;2mDraft suggestion\033[22m\033[48;2;30;30;30mtyped text\033[0m\r\n' > "$STUB_STATE/snapshot"

    run "$PROMPT_HELPER_PATH" codex "report"

    [ "$status" -eq 75 ]
    [ "$(wc -l < "$STUB_STATE/reads" | tr -d '[:space:]')" = 6 ]
    [ "$(wc -l < "$STUB_STATE/sleeps" | tr -d '[:space:]')" = 5 ]
    [ ! -f "$STUB_STATE/prompt_target" ]
    [[ "$output" == *"input was occupied"* ]]
    [[ "$output" == *"report"* ]]
}

@test "[common] the last matching prompt glyph line determines occupancy" {
    printf '❯ typed earlier\n› \033[2mDraft suggestion\033[0m\n' > "$STUB_STATE/snapshot"

    run "$PROMPT_HELPER_PATH" worker "report"

    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_STATE/prompt_target")" = worker ]
    [ "$(cat "$STUB_STATE/prompt_message")" = report ]
}

@test "[common] Claude prompt NBSP before a dim placeholder counts as empty" {
    printf '❯\302\240\033[2mDraft suggestion\033[0m\n' > "$STUB_STATE/snapshot"

    run "$PROMPT_HELPER_PATH" claude "relay"

    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_STATE/prompt_target")" = claude ]
    [ "$(cat "$STUB_STATE/prompt_message")" = relay ]
}

@test "[common] waits for the input to clear before sending" {
    printf '❯ user text\n' > "$STUB_STATE/snapshot_1"
    printf '› \033[2mAsk Codex to do anything\033[0m\n' > "$STUB_STATE/snapshot_2"

    run "$PROMPT_HELPER_PATH" worker "message"

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$STUB_STATE/reads" | tr -d '[:space:]')" = 2 ]
    [ "$(wc -l < "$STUB_STATE/sleeps" | tr -d '[:space:]')" = 1 ]
    [ "$(cat "$STUB_STATE/prompt_message")" = message ]
}

@test "[common] ignores suggestions after the dim marker but still blocks typed text" {
    printf '❯ earlier text\n› \033[2mSuggested completion without reset\n' > "$STUB_STATE/snapshot"

    run "$PROMPT_HELPER_PATH" worker "message"

    [ "$status" -eq 0 ]
    [ "$(cat "$STUB_STATE/prompt_message")" = message ]

    rm -f "$STUB_STATE/prompt_target" "$STUB_STATE/prompt_message"
    : > "$STUB_STATE/reads"
    : > "$STUB_STATE/sleeps"
    printf '❯ typed text \033[2mSuggested completion without reset\n' > "$STUB_STATE/snapshot"

    run "$PROMPT_HELPER_PATH" worker "message"

    [ "$status" -eq 75 ]
    [[ "$output" == *"target input was occupied"* ]]
    [ ! -f "$STUB_STATE/prompt_target" ]
}

@test "[common] reports the full message without sending after the retry budget" {
    printf '❯ user text\n' > "$STUB_STATE/snapshot"

    run "$PROMPT_HELPER_PATH" worker "undelivered report"

    [ "$status" -eq 75 ]
    [ "$(wc -l < "$STUB_STATE/reads" | tr -d '[:space:]')" = 6 ]
    [ "$(wc -l < "$STUB_STATE/sleeps" | tr -d '[:space:]')" = 5 ]
    [ ! -f "$STUB_STATE/prompt_target" ]
    [[ "$output" == *"undelivered to worker"* ]]
    [[ "$output" == *"undelivered report"* ]]
}
