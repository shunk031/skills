#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-meta-orchestrate/scripts/herdr-meta-rotate.sh
# @brief Replace the local meta Claude session after a fresh handoff is written.
# @description
#   Start a detached rotation that waits for meta to become idle or done, captures its
#   explicit model option, exits the old session, and starts a fresh session in
#   the same pane. The pane shell supplies the existing environment.
# @arg [--dry-run] HANDOFF_FILE
# @exitcode 2 when the handoff or runtime preconditions are invalid.
# @example
#   herdr-meta-rotate.sh "$HOME/.local/state/meta/open.md"
#   herdr-meta-rotate.sh --dry-run "$HOME/.local/state/meta/open.md"

set -Eeuo pipefail

readonly agent_name=meta
readonly handoff_max_age=600
readonly wait_timeout_ms=600000
readonly start_timeout_ms=300000
readonly process_exit_timeout=60

background_worker=false
dry_run=false
restart_command=''

function usage() {
    printf 'usage: herdr-meta-rotate.sh [--dry-run] HANDOFF_FILE\n' >&2
}

function notify_failure() {
    local message="$1"
    herdr notification show 'Meta rotation failed' --body "$message" --sound request > /dev/null 2>&1 || true
}

function fail() {
    local message="$1"
    if [[ "$background_worker" == true ]]; then
        notify_failure "$message"
    fi
    printf 'herdr-meta-rotate: %s\n' "$message" >&2
    exit 1
}

function notify_unexpected_failure() {
    local message='The detached meta rotation stopped unexpectedly.'
    if [[ -n "$restart_command" ]]; then
        message="${message}

Restart command:
${restart_command}"
    fi
    notify_failure "$message"
}

function fail_restart() {
    local message="$1"
    notify_failure "${message}

Restart command:
${restart_command}"
    printf 'herdr-meta-rotate: %s\n' "$message" >&2
    exit 1
}

function check_handoff() {
    local path="$1"
    local mtime now age

    [[ -f "$path" && -r "$path" ]] || fail "handoff file is missing or unreadable: $path"
    mtime="$(date -r "$path" '+%s')" || fail "cannot read handoff file timestamp: $path"
    now="$(date '+%s')"
    age=$((now - mtime))
    ((age >= 0 && age <= handoff_max_age)) || fail "handoff file must be no more than 10 minutes old: $path"
}

function get_meta_pane() {
    local agent_info current_info pane_id current_pane

    agent_info="$(herdr agent get "$agent_name")" || fail 'cannot find the meta agent'
    pane_id="$(jq -er '.result.agent | select(.agent == "claude") | .pane_id | strings' <<< "$agent_info")" ||
        fail 'the meta agent is not a Claude session'
    current_info="$(herdr pane current --current)" || fail 'cannot identify the caller pane'
    current_pane="$(jq -er '.result.pane.pane_id | strings' <<< "$current_info")" ||
        fail 'cannot identify the caller pane'
    [[ "$current_pane" == "$pane_id" ]] || fail 'run this script from the meta pane'
    printf '%s\n' "$pane_id"
}

function capture_model_args() {
    local pane_id="$1"
    local process_info claude_process

    process_info="$(herdr pane process-info --pane "$pane_id")" || return 1
    pane_shell_pid="$(jq -er '.result.process_info.shell_pid | numbers' <<< "$process_info")" || return 1
    claude_process="$(jq -ce '
        [.result.process_info.foreground_processes[] | select(.name == "claude")]
        | if length == 1 then .[0] else error("expected one Claude process") end
    ' <<< "$process_info")" || return 1
    claude_pid="$(jq -er '.pid | numbers' <<< "$claude_process")" || return 1
    model_args_json="$(jq -ce '
        .argv as $argv |
        [range(0; ($argv | length)) as $i |
            if $argv[$i] == "--model" then
                if $i + 1 < ($argv | length) then ["--model", $argv[$i + 1]]
                else error("--model has no value") end
            elif ($argv[$i] | startswith("--model=")) then [$argv[$i]]
            else empty end
        ] as $matches |
        if ($matches | length) <= 1 then ($matches[0] // [])
        else error("multiple --model options") end
    ' <<< "$claude_process")" || return 1
    model_args=()
    while IFS= read -r model_arg; do
        model_args[${#model_args[@]}]="$model_arg"
    done < <(jq -r '.[]' <<< "$model_args_json")
}

function claude_pid_is_present() {
    local pane_id="$1"
    local pid="$2"
    local process_info

    process_info="$(herdr pane process-info --pane "$pane_id")" || return 2
    jq -e --argjson pid "$pid" \
        'any(.result.process_info.foreground_processes[]; .name == "claude" and .pid == $pid)' \
        <<< "$process_info" > /dev/null
}

function check_input_empty() {
    local pane_id="$1"
    local parser="${HOME}/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-visible-input-state.awk"
    local snapshot input_state

    [[ -r "$parser" ]] || return 1
    snapshot="$(herdr pane read "$pane_id" --source visible --format ansi)" || return 1
    input_state="$(LC_ALL=C awk -f "$parser" <<< "$snapshot")" || return 1
    [[ "$input_state" == empty ]]
}

function pane_at_shell() {
    local pane_id="$1"
    local process_info

    process_info="$(herdr pane process-info --pane "$pane_id")" || return 1
    jq -e --argjson shell_pid "$pane_shell_pid" '
        .result.process_info as $process_info |
        $process_info.shell_pid == $shell_pid and
            all($process_info.foreground_processes[]; .name != "claude")
    ' <<< "$process_info" > /dev/null
}

function wait_for_shell() {
    local pane_id="$1"
    local pid="$2"
    local attempt

    for ((attempt = 0; attempt < process_exit_timeout; attempt++)); do
        if ! claude_pid_is_present "$pane_id" "$pid" && pane_at_shell "$pane_id"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

function get_meta_pane_after_start() {
    local agent_info pane_id state

    agent_info="$(herdr agent get "$agent_name")" || return 1
    pane_id="$(jq -er '.result.agent | select(.agent == "claude") | .pane_id | strings' <<< "$agent_info")" ||
        return 1
    [[ "$pane_id" == "$meta_pane_id" ]] || return 1
    state="$(jq -er '.result.agent.agent_status | strings' <<< "$agent_info")" || return 1
    [[ "$state" == idle || "$state" == working || "$state" == "done" ]]
}

function return_failed_start_to_shell() {
    local pane_id="$1"
    local process_info has_claude

    process_info="$(herdr pane process-info --pane "$pane_id")" || return 1
    has_claude="$(jq -r 'any(.result.process_info.foreground_processes[]; .name == "claude")' <<< "$process_info")"
    if [[ "$has_claude" != true ]]; then
        pane_at_shell "$pane_id"
        return
    fi

    herdr pane send-text "$pane_id" '/exit' > /dev/null 2>&1 || true
    herdr pane send-keys "$pane_id" enter > /dev/null 2>&1 || true
    if wait_for_shell "$pane_id" "$claude_pid"; then
        return 0
    fi

    herdr pane send-keys "$pane_id" ctrl+c > /dev/null 2>&1 || true
    herdr pane send-text "$pane_id" '/exit' > /dev/null 2>&1 || true
    herdr pane send-keys "$pane_id" enter > /dev/null 2>&1 || true
    wait_for_shell "$pane_id" "$claude_pid"
}

function build_restart_command() {
    local model_arg quoted_arg

    printf -v restart_command 'herdr agent start %q --kind claude --pane %q --timeout %q --' \
        "$agent_name" "$meta_pane_id" "$start_timeout_ms"
    while IFS= read -r model_arg; do
        printf -v quoted_arg '%q' "$model_arg"
        restart_command="${restart_command} ${quoted_arg}"
    done < <(jq -r '.[]' <<< "$model_args_json")
    printf -v quoted_arg '%q' "$initial_prompt"
    restart_command="${restart_command} ${quoted_arg}"
}

function start_meta_session() {
    herdr agent start "$agent_name" --kind claude --pane "$meta_pane_id" --timeout "$start_timeout_ms" -- \
        ${model_args[@]+"${model_args[@]}"} "$initial_prompt"
}

function start_and_verify_meta() {
    if ! start_meta_session; then
        return 1
    fi
    get_meta_pane_after_start
}

if [[ "${1:-}" == --background-worker ]]; then
    background_worker=true
    shift
fi
if [[ "$background_worker" == true ]]; then
    trap 'notify_unexpected_failure' ERR
fi
if [[ "${1:-}" == --dry-run ]]; then
    dry_run=true
    shift
fi
if (($# != 1)); then
    usage
    exit 2
fi

handoff_file="$1"
case "$handoff_file" in
/*) ;;
*) handoff_file="$PWD/$handoff_file" ;;
esac

if [[ "${HERDR_ENV:-}" != 1 ]]; then
    fail 'HERDR_ENV=1 is required'
fi
for command in herdr jq date nohup sleep awk; do
    command -v "$command" > /dev/null || fail "required command is missing: $command"
done
check_handoff "$handoff_file"
meta_pane_id="$(get_meta_pane)"
model_args=()
claude_pid=''
pane_shell_pid=''
model_args_json='[]'
capture_model_args "$meta_pane_id" || fail 'cannot record the current Claude model option'

if [[ "$dry_run" == true ]]; then
    if ((${#model_args[@]} == 0)); then
        printf 'Would rotate meta in %s with no explicit --model option; the same pane shell environment will be reused.\n' "$meta_pane_id"
    else
        printf 'Would rotate meta in %s with %s; the same pane shell environment will be reused.\n' \
            "$meta_pane_id" "${model_args[*]}"
    fi
    exit 0
fi

if [[ "$background_worker" != true ]]; then
    script_path="$0"
    case "$script_path" in
    /*) ;;
    *) script_path="$PWD/${script_path#./}" ;;
    esac
    nohup "$script_path" --background-worker "$handoff_file" < /dev/null > /dev/null 2>&1 &
    printf 'Meta rotation started in the background (PID %s).\n' "$!"
    exit 0
fi

herdr agent wait "$agent_name" --until idle --until 'done' --timeout "$wait_timeout_ms" ||
    fail 'meta did not become idle or done'
agent_info="$(herdr agent get "$agent_name")" || fail 'meta exited before the rotation started'
current_meta_pane="$(jq -er '.result.agent | select(.agent == "claude") | .pane_id | strings' <<< "$agent_info")" ||
    fail 'meta is no longer a Claude session'
[[ "$current_meta_pane" == "$meta_pane_id" ]] || fail 'meta moved to another pane while waiting'
check_handoff "$handoff_file"
capture_model_args "$meta_pane_id" || fail 'cannot record the current Claude model option'
check_input_empty "$meta_pane_id" || fail 'meta has text in its input line; the pane was left unchanged'
agent_info="$(herdr agent get "$agent_name")" || fail 'cannot confirm meta is idle before exiting'
meta_state="$(jq -er '.result.agent.agent_status | strings' <<< "$agent_info")" ||
    fail 'cannot confirm meta is idle before exiting'
case "$meta_state" in
idle | done) ;;
*) fail "meta became active before /exit (state: $meta_state); the pane was left unchanged" ;;
esac

herdr pane send-text "$meta_pane_id" '/exit' || fail 'could not send /exit to meta'
herdr pane send-keys "$meta_pane_id" enter || fail 'could not submit /exit to meta'
wait_for_shell "$meta_pane_id" "$claude_pid" || fail 'the old Claude process did not return the pane to its shell'

printf -v initial_prompt \
    'Read the handoff file at %s first and follow its references. Re-arm the background herdr-meta-patrol-queue wait command, then continue as the meta orchestrator.' \
    "$handoff_file"
build_restart_command

if ! start_and_verify_meta; then
    return_failed_start_to_shell "$meta_pane_id" || true
    if ! start_and_verify_meta; then
        if return_failed_start_to_shell "$meta_pane_id"; then
            fail_restart 'the new Claude session failed after one retry; the pane is back at its shell'
        fi
        fail_restart 'the new Claude session failed after one retry and did not return to the shell'
    fi
fi
