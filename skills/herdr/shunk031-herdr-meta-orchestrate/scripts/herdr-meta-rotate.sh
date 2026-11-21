#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-meta-orchestrate/scripts/herdr-meta-rotate.sh
# @brief Replace the local meta Claude session after a fresh handoff is written.
# @description
#   Start a detached rotation that waits for meta to become idle or done, carries its
#   explicit model option, and starts a fresh session in the same pane. After /exit,
#   choose the background-work exit option only when its option line is visible, then
#   confirm that Claude returned to the pane shell. Carry the session task tree through
#   the Inbox tasks tool, start Remote Control with its named CLI flag, and open Inbox.
#   Verify each startup step from the pane before reporting success.
# @option --dry-run Print the planned rotation without changing the pane.
# @arg $1 string Handoff file path.
# @exitcode 1 The handoff is invalid or the rotation fails.
# @exitcode 2 Usage error.
# @example
#   herdr-meta-rotate.sh "$HOME/.local/state/meta/open.md"
#   herdr-meta-rotate.sh --dry-run "$HOME/.local/state/meta/open.md"

set -euo pipefail

readonly agent_name=meta
readonly handoff_max_age=600
readonly wait_timeout_ms=600000
readonly start_timeout_ms=300000
readonly process_exit_timeout=60
readonly startup_command_timeout=60
readonly remote_control_name='Meta orch.'

background_worker=false
dry_run=false
restart_command=''
failure_message=''
failure_notified=false
meta_session_id=''
new_session_id=''
task_snapshot_json='[]'
start_output=''
start_status=0

function usage() {
    printf 'usage: herdr-meta-rotate.sh [--dry-run] HANDOFF_FILE\n' >&2
}

function notify_failure() {
    local message="$1"
    herdr notification show 'Meta rotation failed' --body "$message" --sound request > /dev/null 2>&1 || true
}

function fail() {
    local message="$1"
    failure_message="$message"
    printf 'herdr-meta-rotate: %s\n' "$message" >&2
    exit 1
}

function notify_background_failure() {
    local exit_status="$1"
    local message

    [[ "$background_worker" == true && "$failure_notified" != true && "$exit_status" -ne 0 ]] || return 0
    failure_notified=true
    message="$failure_message"
    [[ -n "$message" ]] || message="The detached meta rotation stopped unexpectedly (exit status ${exit_status})."
    if [[ -n "$restart_command" && "$message" != *'Restart command:'* ]]; then
        message="${message}

Restart command:
${restart_command}"
    fi
    notify_failure "$message"
}

function on_background_exit() {
    local exit_status="$1"

    notify_background_failure "$exit_status"
    trap - EXIT
    exit "$exit_status"
}

function on_background_term() {
    failure_message='The detached meta rotation received SIGTERM.'
    exit 143
}

function fail_restart() {
    local message="$1"
    if [[ -n "$restart_command" ]]; then
        message="${message}

Restart command:
${restart_command}"
    fi
    fail "$message"
}

function check_handoff() {
    local path="$1"
    local mtime now age

    [[ -s "$path" && -r "$path" ]] || fail "handoff file is missing, empty, or unreadable: $path"
    mtime="$(date -r "$path" '+%s')" || fail "cannot read handoff file timestamp: $path"
    now="$(date '+%s')"
    age=$((now - mtime))
    ((age >= 0 && age <= handoff_max_age)) || fail "handoff file must be no more than 10 minutes old: $path"
}

function get_meta_pane() {
    local agent_info current_info pane_id current_pane session_id

    agent_info="$(herdr agent get "$agent_name")" || return 1
    pane_id="$(jq -er '.result.agent | select(.agent == "claude") | .pane_id | strings' <<< "$agent_info")" ||
        return 1
    session_id="$(jq -er '.result.agent.agent_session.value | strings | select(length > 0)' <<< "$agent_info")" ||
        return 1
    current_info="$(herdr pane current --current)" || return 1
    current_pane="$(jq -er '.result.pane.pane_id | strings' <<< "$current_info")" ||
        return 1
    [[ "$current_pane" == "$pane_id" ]] || return 1
    meta_pane_id="$pane_id"
    meta_session_id="$session_id"
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

# @description Read and serialize the outgoing session's open Inbox task tree without modifying its export.
# @arg $1 string Outgoing Claude session ID.
function load_open_task_snapshot() {
    local session_id="$1"
    local task_tree_file="$HOME/.local/state/inbox/task-tree/$session_id.json"

    [[ -r "$task_tree_file" ]] || return 1
    task_snapshot_json="$(jq -ce --arg session_id "$session_id" '
        if .schema == 1 and .session_id == $session_id and (.tasks | type == "array") then
            [.tasks[]
                | select(.status != "done" and .status != "dropped")
                | {id, title, status, parent_id, owner, pr}] as $open |
            [$open[]
                | .parent_id as $parent
                | .parent_id = (if $parent != null and any($open[]; .id == $parent) then $parent else null end)]
        else
            error("invalid Inbox task-tree export")
        end
    ' "$task_tree_file")" || return 1
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

# @description Detect the background-work exit option in the bottom 24 visible pane lines.
# @arg $1 string Pane identifier.
function exit_dialog_is_visible() {
    local pane_id="$1"
    local snapshot

    snapshot="$(herdr pane read "$pane_id" --source visible --format text)" || return 2
    LC_ALL=C awk '
        { lines[NR] = $0 }
        END {
            first_line = NR - 23
            if (first_line < 1) first_line = 1
            for (line = first_line; line <= NR; line++) {
                if (index(lines[line], "1. Exit and stop tasks") > 0) exit 0
            }
            exit 1
        }
    ' <<< "$snapshot"
}

# @description Wait for Claude to return to its pane shell after /exit, answering the visible background-work dialog if needed.
# @arg $1 string Pane identifier.
# @arg $2 int Original Claude process ID.
function wait_for_exit() {
    local pane_id="$1"
    local pid="$2"
    local attempt dialog_status
    local dialog_answered=false

    for ((attempt = 0; attempt < process_exit_timeout; attempt++)); do
        if ! claude_pid_is_present "$pane_id" "$pid" && pane_at_shell "$pane_id"; then
            return 0
        fi
        if [[ "$dialog_answered" != true ]]; then
            if exit_dialog_is_visible "$pane_id"; then
                herdr pane send-keys "$pane_id" 1 || return 1
                herdr pane send-keys "$pane_id" enter || return 1
                dialog_answered=true
            else
                dialog_status=$?
                ((dialog_status == 1)) || return 1
            fi
        fi
        sleep 1
    done
    return 1
}

# @description Send one Claude slash command only after the target composer is confirmed empty.
# @arg $1 string Pane identifier.
# @arg $2 string Slash command.
function send_slash_command_once() {
    local pane_id="$1"
    local command="$2"

    check_input_empty "$pane_id" || return 1
    herdr pane send-text "$pane_id" "$command" || return 1
    herdr pane send-keys "$pane_id" enter || return 1
}

# @description Verify Remote Control is active in the pane and started with the configured session name.
# @arg $1 string Pane identifier.
function verify_remote_control() {
    local pane_id="$1"
    local process_info snapshot attempt

    for ((attempt = 0; attempt < startup_command_timeout; attempt++)); do
        process_info="$(herdr pane process-info --pane "$pane_id")" || return 1
        if jq -e --arg name "$remote_control_name" '
            any(.result.process_info.foreground_processes[];
                .name == "claude" and
                (.argv | index("--remote-control") as $i | $i != null and .[$i + 1] == $name))
        ' <<< "$process_info" > /dev/null; then
            snapshot="$(herdr pane read "$pane_id" --source visible --format text)" || return 1
            if [[ "$snapshot" == *'/rc active'* && "$snapshot" == *'claude.ai/code/session_'* ]]; then
                return 0
            fi
        else
            return 1
        fi
        sleep 1
    done
    return 1
}

# @description Verify the Inbox plugin reported success and its titled pane is visible.
# @arg $1 string Pane identifier.
function verify_inbox_open() {
    local pane_id="$1"
    local snapshot attempt

    for ((attempt = 0; attempt < startup_command_timeout; attempt++)); do
        snapshot="$(herdr pane read "$pane_id" --source visible --format text)" || return 1
        if [[ "$snapshot" == *'Opened the inbox.'* && "$snapshot" == *'Inbox'* ]]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# @description Check that every outgoing open task title appears in the replacement session's Inbox export.
# @arg $1 string Replacement Claude session ID.
function verify_task_tree_carried() {
    local session_id="$1"
    local task_tree_file="$HOME/.local/state/inbox/task-tree/$session_id.json"
    local remaining_attempts

    [[ "$(jq -r 'length' <<< "$task_snapshot_json")" -gt 0 ]] || return 0
    for ((remaining_attempts = 0; remaining_attempts < startup_command_timeout; remaining_attempts++)); do
        if [[ -r "$task_tree_file" ]] &&
            jq -e --arg session_id "$session_id" --argjson expected "$task_snapshot_json" '
                if .schema != 1 or .session_id != $session_id or (.tasks | type != "array") then
                    false
                else
                    [.tasks[] | select(.status != "done" and .status != "dropped")
                        | {id, title, status, parent_id, owner, pr}] as $actual |
                    all($expected[]; . as $task | any($actual[]; . == $task))
                end
            ' "$task_tree_file" > /dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

function meta_claude_is_running() {
    local process_info

    process_info="$(herdr pane process-info --pane "$meta_pane_id")" || return 2
    jq -e 'any(.result.process_info.foreground_processes[]; .name == "claude")' \
        <<< "$process_info" > /dev/null
}

function get_meta_pane_after_start() {
    local agent_info pane_id state attempt process_status

    for ((attempt = 0; attempt < 5; attempt++)); do
        if ! agent_info="$(herdr agent get "$agent_name")"; then
            if meta_claude_is_running; then
                return 2
            else
                process_status=$?
                ((process_status == 1)) || return 2
                return 1
            fi
        fi
        if ! pane_id="$(jq -er '.result.agent | select(.agent == "claude") | .pane_id | strings' <<< "$agent_info")"; then
            if meta_claude_is_running; then
                return 2
            else
                process_status=$?
                ((process_status == 1)) || return 2
                return 1
            fi
        fi
        [[ "$pane_id" == "$meta_pane_id" ]] || return 2
        new_session_id="$(jq -er '.result.agent.agent_session.value | strings | select(length > 0)' <<< "$agent_info")" ||
            return 2
        state="$(jq -er '.result.agent.agent_status | strings' <<< "$agent_info")" || return 2
        case "$state" in
        idle | working | done | blocked) return 0 ;;
        unknown) sleep 1 ;;
        *) return 2 ;;
        esac
    done
    return 2
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

    if herdr pane send-text "$pane_id" '/exit' > /dev/null 2>&1 &&
        herdr pane send-keys "$pane_id" enter > /dev/null 2>&1; then
        if wait_for_exit "$pane_id" "$claude_pid"; then
            return 0
        fi
    fi

    herdr pane send-keys "$pane_id" ctrl+c > /dev/null 2>&1 || true
    if herdr pane send-text "$pane_id" '/exit' > /dev/null 2>&1 &&
        herdr pane send-keys "$pane_id" enter > /dev/null 2>&1; then
        wait_for_exit "$pane_id" "$claude_pid"
    else
        return 1
    fi
}

function build_restart_command() {
    local model_arg quoted_arg

    printf -v restart_command 'herdr agent start %q --kind claude --pane %q --timeout %q --' \
        "$agent_name" "$meta_pane_id" "$start_timeout_ms"
    while IFS= read -r model_arg; do
        printf -v quoted_arg '%q' "$model_arg"
        restart_command="${restart_command} ${quoted_arg}"
    done < <(jq -r '.[]' <<< "$model_args_json")
    printf -v quoted_arg '%q' '--remote-control'
    restart_command="$restart_command $quoted_arg"
    printf -v quoted_arg '%q' "$remote_control_name"
    restart_command="$restart_command $quoted_arg"
    printf -v quoted_arg '%q' "$initial_prompt"
    restart_command="${restart_command} ${quoted_arg}"
}

function start_meta_session() {
    start_output=''
    start_status=0
    start_output="$(herdr agent start "$agent_name" --kind claude --pane "$meta_pane_id" --timeout "$start_timeout_ms" -- \
        ${model_args[@]+"${model_args[@]}"} --remote-control "$remote_control_name" "$initial_prompt" 2>&1)" ||
        start_status=$?
}

# @description Recover Herdr's timeout result only after the replacement Claude process is verified in the original pane.
# @arg $1 string Pane identifier.
function recover_timed_out_start() {
    local pane_id="$1"
    local process_info process_is_new renamed_info

    process_info="$(herdr pane process-info --pane "$pane_id")" || return 2
    process_is_new="$(jq -er --argjson shell_pid "$pane_shell_pid" --argjson old_pid "$claude_pid" '
        .result.process_info as $process |
        [$process.foreground_processes[] | select(.name == "claude")] as $claudes |
        ($process.shell_pid == $shell_pid and ($claudes | length) == 1 and $claudes[0].pid != $old_pid)
    ' <<< "$process_info")" || return 2
    [[ "$process_is_new" == true ]] || return 1

    herdr agent rename "$pane_id" "$agent_name" || return 2
    renamed_info="$(herdr agent get "$agent_name")" || return 2
    jq -e --arg pane_id "$pane_id" '
        .result.agent.agent == "claude" and .result.agent.pane_id == $pane_id
    ' <<< "$renamed_info" > /dev/null || return 2
    new_session_id="$(jq -er '.result.agent.agent_session.value | strings | select(length > 0)' <<< "$renamed_info")" ||
        return 2
}

function start_and_verify_meta() {
    local verification_status recovery_status

    start_meta_session
    if ((start_status != 0)); then
        if [[ "$(jq -r '.code // empty' <<< "$start_output" 2> /dev/null || true)" == timeout ]]; then
            if recover_timed_out_start "$meta_pane_id"; then
                :
            else
                recovery_status=$?
                ((recovery_status == 1)) && return 1
                return 2
            fi
        else
            return 1
        fi
    fi
    if get_meta_pane_after_start; then
        return 0
    else
        verification_status=$?
    fi
    if ((verification_status == 2)); then
        return 2
    fi
    return 1
}

if [[ "${1:-}" == --background-worker ]]; then
    background_worker=true
    shift
fi
if [[ "$background_worker" == true ]]; then
    trap 'on_background_exit "$?"' EXIT
    trap 'on_background_term' TERM
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
get_meta_pane || fail 'cannot identify the caller meta Claude pane'
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
    printf "Would start Remote Control with --remote-control '%s' and open Inbox once after checking for an empty input line.\n" \
        "$remote_control_name"
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
current_meta_session="$(jq -er '.result.agent.agent_session.value | strings' <<< "$agent_info")" ||
    fail 'cannot verify the outgoing meta session identity'
[[ "$current_meta_session" == "$meta_session_id" ]] || fail 'meta changed sessions while the rotation was waiting'
check_handoff "$handoff_file"
capture_model_args "$meta_pane_id" || fail 'cannot record the current Claude model option'
check_input_empty "$meta_pane_id" || fail 'meta has text in its input line; the pane was left unchanged'
load_open_task_snapshot "$meta_session_id" ||
    fail 'cannot read the outgoing Inbox task-tree export; the pane was left unchanged'
printf -v initial_prompt \
    'Read the handoff file at %s first and follow its references. Re-arm the background herdr-meta-patrol-queue wait command. Restore each task in the outgoing Inbox task snapshot below through the Inbox mcp__inbox__tasks tool with operation=add. Use each snapshot id as task_id; preserve title, status, parent_id, pr, and owner_agent/owner_machine where present. Add parents before children. The exported owner object maps to owner_agent and owner_machine. Do not write task-tree JSON directly. If the Inbox task tool is unavailable or a task is not saved, report the handoff incomplete. Verify every restored task before continuing as the meta orchestrator. Outgoing open-task snapshot: %s' \
    "$handoff_file" "$task_snapshot_json"
build_restart_command
agent_info="$(herdr agent get "$agent_name")" || fail 'cannot confirm meta is idle before exiting'
meta_state="$(jq -er '.result.agent.agent_status | strings' <<< "$agent_info")" ||
    fail 'cannot confirm meta is idle before exiting'
case "$meta_state" in
idle | done) ;;
*) fail "meta became active before /exit (state: $meta_state); the pane was left unchanged" ;;
esac

feed_dir="${INBOX_FEED:-$HOME/.local/state/inbox/feeds}"
mkdir -p "$feed_dir" || fail "cannot create INBOX_FEED directory: $feed_dir"

herdr pane send-text "$meta_pane_id" '/exit' || fail 'could not send /exit to meta'
herdr pane send-keys "$meta_pane_id" enter || fail 'could not submit /exit to meta'
wait_for_exit "$meta_pane_id" "$claude_pid" || fail 'the old Claude process did not return the pane to its shell'

printf -v export_command 'export INBOX_FEED=%q' "$feed_dir"
herdr pane run "$meta_pane_id" "$export_command" || fail 'could not export INBOX_FEED in the meta pane shell'
wait_for_shell "$meta_pane_id" "$claude_pid" || fail 'the meta pane did not return to its shell after exporting INBOX_FEED'

start_result=0
start_and_verify_meta || start_result=$?
if ((start_result == 2)); then
    fail_restart 'Herdr started Claude but could not verify its state; the new session was left untouched'
elif ((start_result != 0)); then
    return_failed_start_to_shell "$meta_pane_id" || true
    start_result=0
    start_and_verify_meta || start_result=$?
    if ((start_result == 2)); then
        fail_restart 'Herdr started Claude but could not verify its state after one retry; the new session was left untouched'
    elif ((start_result != 0)); then
        if return_failed_start_to_shell "$meta_pane_id"; then
            fail_restart 'the new Claude session failed after one retry; the pane is back at its shell'
        fi
        fail_restart 'the new Claude session failed after one retry and did not return to the shell'
    fi
fi

restart_command=''
verify_remote_control "$meta_pane_id" ||
    fail 'the new meta session did not verify Remote Control active under the launch name Meta orch.'
herdr agent wait "$agent_name" --until idle --until 'done' --timeout "$wait_timeout_ms" ||
    fail 'the new meta session did not complete its handoff and task-tree restoration'
verify_task_tree_carried "$new_session_id" ||
    fail 'the new meta session did not restore every outgoing open Inbox task'
send_slash_command_once "$meta_pane_id" '/inbox' ||
    fail 'the new meta input was not empty or /inbox could not be submitted; no retry was attempted'
verify_inbox_open "$meta_pane_id" ||
    fail 'the new meta session did not verify the Inbox pane after the single /inbox command'
