#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-meta-orchestrate/scripts/herdr-meta-patrol.sh
# @brief Patrol Herdr agents and handle meta's usage-limit hold.
# @description
#   The default invocation is a read-only patrol for the local server and each
#   enabled saved machine. `--limit-hold` is the external LLM-free patrol's
#   stateful handler for meta usage limits: it sends one user notification per
#   limit episode and guarded instructions to workers waiting on meta's review.
#   HERDR_PATROL_ROOTS_JSON supplies verified root agents as objects with
#   machine: null for local or a saved machine label, and an agent name.
# @stdout One compact JSON object per finding during the default scan; the limit handler is silent.
# @exitcode 2 when prerequisites or the root configuration are invalid.
# @example
#   HERDR_PATROL_ROOTS_JSON='[{"machine":null,"agent":"meta"}]' herdr-meta-patrol.sh
#   herdr-meta-patrol.sh --limit-hold
# @option HERDR_META_PATROL_META Meta agent name (default `meta`).
# @option HERDR_META_PATROL_STATE_DIR Shared patrol and queue state directory.
# @option HERDR_META_PATROL_CALL_TIMEOUT Seconds allowed for one Herdr operation (default 20).
# @option HERDR_META_PATROL_SHARE_PROCESS_GROUP Reuse the enclosing process group for nested handler calls (default 0).
# @option HERDR_META_PATROL_PROMPT_GUARD Guarded Herdr prompt sender path.

set -Eeuo pipefail

if [[ "${HERDR_ENV:-}" != 1 ]]; then
    printf '%s\n' 'patrol requires HERDR_ENV=1' >&2
    exit 2
fi

mode="${1:-scan}"
if [[ "$mode" == scan && $# -ne 0 ]] || [[ "$mode" == --limit-hold && $# -ne 1 ]] ||
    [[ "$mode" != scan && "$mode" != --limit-hold ]]; then
    printf '%s\n' 'usage: herdr-meta-patrol.sh [--limit-hold] (configure scan roots with HERDR_PATROL_ROOTS_JSON)' >&2
    exit 2
fi

meta_name="${HERDR_META_PATROL_META:-meta}"
state_dir="${HERDR_META_PATROL_STATE_DIR:-${HOME:-}/.local/state/herdr-meta-patrol}"
prompt_guard="${HERDR_META_PATROL_PROMPT_GUARD:-${HOME:-}/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh}"
call_timeout="${HERDR_META_PATROL_CALL_TIMEOUT:-20}"
episode_file="${state_dir}/meta-limit-episode.json"

for command in herdr jq awk; do
    command -v "$command" > /dev/null || {
        printf 'patrol: required command is missing: %s\n' "$command" >&2
        exit 2
    }
done

if [[ "$mode" == --limit-hold ]]; then
    for command in perl sed grep head tail tr; do
        command -v "$command" > /dev/null || {
            printf 'patrol: required command is missing: %s\n' "$command" >&2
            exit 2
        }
    done
    if [[ ! "$call_timeout" =~ ^[1-9][0-9]*$ ]]; then
        printf '%s\n' 'patrol: HERDR_META_PATROL_CALL_TIMEOUT must be a positive integer' >&2
        exit 2
    fi
fi

roots_json="${HERDR_PATROL_ROOTS_JSON:-[]}"
if [[ "$mode" == scan ]] && ! jq -e '
    type == "array" and all(.[];
        (.agent | type == "string" and test("^[a-z][a-z0-9_-]{0,31}$")) and
        (.machine | type == "null" or
            (type == "string" and length > 0 and (test("[\t\r\n]") | not)))
    )
' <<< "$roots_json" > /dev/null 2>&1; then
    jq -cn '{kind:"invalid_configuration",setting:"HERDR_PATROL_ROOTS_JSON"}'
    exit 2
fi

function herdr_for_machine() {
    local machine="$1"
    shift
    if [[ -z "$machine" ]]; then
        herdr "$@"
    else
        herdr --machine "$machine" "$@"
    fi
}

# @description Run a command with a timeout, reusing the caller's process group when configured.
# @arg $1 number Seconds before the command is terminated.
# @arg $@ command Command and arguments to run.
function run_with_timeout() {
    local timeout="$1"
    shift
    perl -MPOSIX=setpgid -e '
        my $timeout = shift;
        my @command = @ARGV;
        my $share_process_group = ($ENV{HERDR_META_PATROL_SHARE_PROCESS_GROUP} || "") eq "1";
        my $pid = fork();
        defined($pid) or die "timeout fork: $!\n";
        if ($pid == 0) {
            if (!$share_process_group) {
                setpgid(0, 0) == 0 or die "timeout process group: $!\n";
            }
            exec { $command[0] } @command or die "timeout exec: $!\n";
        }
        setpgid($pid, $pid) if !$share_process_group;
        local $SIG{ALRM} = sub {
            kill "TERM", -$pid if !$share_process_group;
            kill "TERM", $pid;
            sleep 1;
            kill "KILL", -$pid if !$share_process_group;
            kill "KILL", $pid;
            exit 124;
        };
        alarm $timeout;
        waitpid($pid, 0);
        my $status = $?;
        alarm 0;
        die "timeout wait: $!\n" if $status == -1;
        exit($status & 127 ? 128 + ($status & 127) : $status >> 8);
    ' "$timeout" "$@"
}

# @description Run one Herdr operation with an independent timeout.
# @arg $@ command Herdr subcommand and arguments.
function herdr_timed() {
    run_with_timeout "$call_timeout" herdr "$@"
}

function emit_machine_finding() {
    local kind="$1"
    local machine="$2"
    local label="$machine"
    [[ -n "$label" ]] || label=local
    jq -cn --arg kind "$kind" --arg machine "$label" '{kind:$kind,machine:$machine}'
}

function emit_root_finding() {
    local kind="$1"
    local machine="$2"
    local agent="$3"
    local label="$machine"
    [[ -n "$label" ]] || label=local
    jq -cn --arg kind "$kind" --arg machine "$label" --arg agent "$agent" \
        '{kind:$kind,machine:$machine,agent:$agent}'
}

# @description Extract the reset clock token from a limit signal.
# @arg $1 string Limit signal text.
function reset_time_from_signal() {
    local signal match reset reset_pattern
    signal="$1"
    reset_pattern='resets?[[:space:]]+(at[[:space:]]+)?((mon|tue|wed|thu|fri|sat|sun)[a-z]*[[:space:],]+)?([[:alpha:]]{3,9}[[:space:]]+[0-9]{1,2}([[:space:]]+at[[:space:]]+[0-9]{1,2}(:[0-9]{2})?[[:space:]]*([ap]m)?)?|[0-9]{1,2}(:[0-9]{2})?[[:space:]]*([ap]m)?)'
    match="$(LC_ALL=C grep -Eio "$reset_pattern" <<< "$signal" | tail -n 1)" || match=""
    reset="$(sed -E 's/^[Rr]esets?[[:space:]]+([Aa]t[[:space:]]+)?//' <<< "$match" | sed -E 's/[[:space:]]+$//' | tr -d '\r')"
    [[ -n "$reset" ]] || reset='the displayed reset time'
    printf '%s\n' "$reset"
}

# @description Return meta workers whose latest queue record uses the canonical review-ready stage.
#   While waiting for its verdict, a worker keeps that stage and exact HEAD in every STATUS.
# @stdout One meta-prefixed worker name per line.
function ready_for_review_workers() {
    local queue_file="${state_dir}/queue.jsonl"
    [[ -r "$queue_file" ]] || return 0
    jq -Rrs --arg prefix "${meta_name}-" '
        split("\n")
        | map(try fromjson catch null)
        | map(select(type == "object"))
        | sort_by(.seq // 0)
        | reduce .[] as $record ({};
            if (($record.from // "") | startswith($prefix))
            then .[$record.from] = $record
            else .
            end
        )
        | to_entries[]
        | .key as $name
        | select((.value.text // "") | test("^STATUS " + $name + ": [0-9]{2}:[0-9]{2} ready for review head=[0-9a-f]{40}; ETA .+$"))
        | .key
    ' "$queue_file"
}

# @description Save active episode and suppressed-banner state atomically.
# @arg $1 string Reset time displayed by the limit signal.
# @arg $2 boolean Whether the user notification has been sent.
# @arg $3 JSON Array of workers already notified in this episode.
# @arg $4 boolean Whether a limit episode is active.
# @arg $5 JSON Array of reset signals to ignore until they leave the screen.
function write_limit_episode() {
    local reset="$1" notification_sent="$2" workers="$3" active="$4" suppressed_resets="$5" temporary
    temporary="${episode_file}.$$"
    jq -cn --arg reset "$reset" --argjson active "$active" --argjson notification_sent "$notification_sent" \
        --argjson workers "$workers" --argjson suppressed "$suppressed_resets" \
        '{active:$active,reset:$reset,notification_sent:$notification_sent,workers_notified:$workers,suppressed_resets:$suppressed}' > "$temporary" &&
        mv "$temporary" "$episode_file"
}

# @description Detect and handle a local meta usage-limit episode.
function run_meta_limit_hold() {
    local agents_json meta_agent meta_status pane_id inbox_text pane_text pane_read_ok
    local limit_active reset inbox_match inbox_reset banner_line banner_reset candidate_resets observed_resets
    local episode_active episode_reset notification_sent workers_notified suppressed_resets
    local waiters worker worker_agent worker_status message worker_index prompt_count=0
    local -a prompt_pids=() prompt_workers=()
    local api_error_line limit_error_pattern

    if [[ "${HERDR_META_PATROL_LIMIT_LOCKED:-}" != 1 ]]; then
        mkdir -p "$state_dir"
        HERDR_META_PATROL_LIMIT_LOCKED=1 perl -MFcntl=:flock -MErrno=EWOULDBLOCK,EAGAIN -e '
            my $path = shift;
            open my $lock, ">>", $path or die "limit lock: $!\n";
            if (!flock($lock, LOCK_EX | LOCK_NB)) {
                exit 0 if $! == EWOULDBLOCK || $! == EAGAIN;
                die "limit lock: $!\n";
            }
            system @ARGV;
            my $status = $?;
            die "limit handler start: $!\n" if $status == -1;
            exit($status & 127 ? 128 + ($status & 127) : $status >> 8);
        ' "${state_dir}/limit-hold.lock" "$0" --limit-hold
        return $?
    fi

    agents_json="$(herdr_timed agent list 2> /dev/null)" || {
        printf '%s\n' 'patrol: unable to read local agents; limit episode state was kept' >&2
        return 0
    }
    if ! jq -e '.result.agents | type == "array"' <<< "$agents_json" > /dev/null 2>&1; then
        printf '%s\n' 'patrol: local agent list was unreadable; limit episode state was kept' >&2
        return 0
    fi

    meta_agent="$(jq -c --arg name "$meta_name" '[.result.agents[] | select(.name == $name)] | first // empty' <<< "$agents_json")"
    [[ -n "$meta_agent" ]] || return 0

    meta_status="$(jq -r '.agent_status // empty' <<< "$meta_agent")"
    pane_id="$(jq -r '.pane_id // empty' <<< "$meta_agent")"
    inbox_text="$(jq -r '
        .tokens.inbox as $inbox
        | if $inbox == null then ""
          elif ($inbox | type) == "string" then $inbox
          elif ($inbox | type) == "object" then ($inbox.text // $inbox.message // "")
          elif ($inbox | type) == "array" then
              [$inbox[]? | if type == "string" then . elif type == "object" then (.text // .message // empty) else empty end] | join("\n")
          else ""
          end
    ' <<< "$meta_agent")"

    pane_text=""
    pane_read_ok=0
    if [[ -n "$pane_id" ]] && pane_text="$(herdr_timed pane read "$pane_id" --source visible --format text 2> /dev/null)"; then
        pane_read_ok=1
    fi

    inbox_match="$(LC_ALL=C grep -Eio '^![[:space:]]*Limit:[[:space:]]*resets?[[:space:]]+.*' <<< "$inbox_text" | head -n 1)" || inbox_match=""
    inbox_reset=""
    if [[ -n "$inbox_match" ]]; then
        inbox_reset="$(reset_time_from_signal "$inbox_match")"
    fi

    api_error_line='^(■ |[[:space:]]*⎿[[:space:]]+(API Error|Claude usage limit|[0-9]+-hour limit|You.{1,3}ve hit your|Weekly limit|Session limit))'
    limit_error_pattern='Claude usage limit|[0-9]+-hour limit|You.{1,3}ve hit your ([a-z]+ )?limit|Weekly limit|Session limit'
    banner_line=""
    if ((pane_read_ok)); then
        banner_line="$(LC_ALL=C grep -E -- "$api_error_line" <<< "$pane_text" | LC_ALL=C grep -v -- 'Retrying in' | LC_ALL=C grep -iE -- "$limit_error_pattern")" || banner_line=""
    fi
    banner_reset=""
    if [[ -n "$banner_line" ]]; then
        banner_reset="$(reset_time_from_signal "$banner_line")"
    fi
    candidate_resets="$(jq -cn --arg inbox "$inbox_reset" --arg banner "$banner_reset" '[$inbox,$banner] | map(select(length > 0))')"
    observed_resets="$(jq -c 'unique' <<< "$candidate_resets")"
    limit_active=0
    reset=""

    episode_active=false
    episode_reset=""
    notification_sent=false
    workers_notified='[]'
    suppressed_resets='[]'
    if [[ -f "$episode_file" ]] && jq -e '
        type == "object" and
        (.active == null or (.active | type == "boolean")) and
        (.notification_sent | type == "boolean") and
        (.workers_notified | type == "array") and
        (.suppressed_resets == null or (.suppressed_resets | type == "array"))
    ' "$episode_file" > /dev/null 2>&1; then
        episode_active="$(jq -r 'if .active == null then true else .active end' "$episode_file")"
        episode_reset="$(jq -r '.reset // empty' "$episode_file")"
        notification_sent="$(jq -r '.notification_sent' "$episode_file")"
        workers_notified="$(jq -c '.workers_notified' "$episode_file")"
        suppressed_resets="$(jq -c '.suppressed_resets // []' "$episode_file")"
    fi

    if [[ "$meta_status" == working ]]; then
        if [[ "$observed_resets" == "[]" ]]; then
            rm -f "$episode_file"
        else
            write_limit_episode "" false '[]' false "$observed_resets"
        fi
        return 0
    fi

    suppressed_resets="$(jq -cn --argjson previous "$suppressed_resets" --argjson observed "$observed_resets" \
        '[$previous[] as $reset | select(($observed | index($reset)) != null) | $reset] | unique')"

    if [[ -n "$banner_reset" || -n "$inbox_reset" ]]; then
        limit_active=1
        if [[ -n "$banner_reset" ]]; then
            reset="$banner_reset"
        else
            reset="$inbox_reset"
        fi
    fi

    if ((limit_active == 0)); then
        if [[ "$episode_active" != true ]]; then
            if [[ "$suppressed_resets" == "[]" ]]; then
                rm -f "$episode_file"
            else
                write_limit_episode "" false '[]' false "$suppressed_resets"
            fi
        fi
        return 0
    fi

    if [[ "$episode_active" != true ]] &&
        jq -e --arg reset "$reset" 'index($reset) != null' <<< "$suppressed_resets" > /dev/null; then
        write_limit_episode "" false '[]' false "$suppressed_resets"
        return 0
    fi

    if [[ "$episode_active" != true || "$episode_reset" != "$reset" ]]; then
        notification_sent=false
        workers_notified='[]'
        suppressed_resets='[]'
    fi
    mkdir -p "$state_dir"
    write_limit_episode "$reset" "$notification_sent" "$workers_notified" true "$suppressed_resets"

    if [[ "$notification_sent" != true ]]; then
        if herdr_timed notification show 'meta usage limit' --body "Meta is usage-limited until ${reset}. Workers waiting at a ready-for-review HEAD should hold periodic STATUS and use the approved Codex review route."; then
            notification_sent=true
            write_limit_episode "$reset" true "$workers_notified" true "$suppressed_resets"
        else
            printf '%s\n' 'patrol: limit notification failed; it will be retried next cycle' >&2
        fi
    fi

    waiters="$(ready_for_review_workers)" || waiters=""
    while IFS= read -r worker; do
        [[ -n "$worker" ]] || continue
        jq -e --arg worker "$worker" '.workers_notified | index($worker) != null' "$episode_file" > /dev/null && continue
        worker_agent="$(jq -c --arg name "$worker" '[.result.agents[] | select(.name == $name)] | first // empty' <<< "$agents_json")"
        [[ -n "$worker_agent" ]] || continue
        worker_status="$(jq -r '.agent_status // empty' <<< "$worker_agent")"
        [[ "$worker_status" == working || "$worker_status" == idle || "$worker_status" == done ]] || continue
        if [[ ! -x "$prompt_guard" ]]; then
            printf 'patrol: guarded prompt sender is unavailable for %s\n' "$worker" >&2
            continue
        fi
        message="Meta is usage-limited until ${reset}. Please hold periodic STATUS updates while waiting. For this exact ready-for-review HEAD, use the authorized one-shot Codex route in the worker protocol: review it independently, in a fresh read-only context, without further delegation, using the DONE verification checklist. Immediately queue the verdict, exact HEAD, and source as Codex review during meta usage limit. Meta will re-check the exact HEAD when it reads its backlog after recovery, before any merge that needs user approval."
        run_with_timeout "$call_timeout" env HERDR_ENV=1 "$prompt_guard" "$worker" "$message" &
        prompt_pids[$prompt_count]="$!"
        prompt_workers[$prompt_count]="$worker"
        prompt_count=$((prompt_count + 1))
    done <<< "$waiters"

    for ((worker_index = 0; worker_index < prompt_count; worker_index++)); do
        if wait "${prompt_pids[$worker_index]}"; then
            worker="${prompt_workers[$worker_index]}"
            workers_notified="$(jq -c --arg worker "$worker" '.workers_notified = ((.workers_notified + [$worker]) | unique) | .workers_notified' "$episode_file")"
            write_limit_episode "$reset" "$notification_sent" "$workers_notified" true "$suppressed_resets"
        else
            printf 'patrol: limit hold message was not delivered to %s; it will be retried next cycle\n' "${prompt_workers[$worker_index]}" >&2
        fi
    done
}

function visible_input_state() {
    local parser="${HOME:-}/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-visible-input-state.awk"
    if [[ ! -r "$parser" ]]; then
        printf '%s\n' unknown
        return 0
    fi
    LC_ALL=C awk -f "$parser"
}

function check_root_inputs() {
    local machine="$1"
    local roots agent agent_info pane_id snapshot input_state

    if [[ -z "$machine" ]]; then
        roots="$(jq -r '.[] | select(.machine == null) | .agent' <<< "$roots_json")"
    else
        roots="$(jq -r --arg machine "$machine" '.[] | select(.machine == $machine) | .agent' <<< "$roots_json")"
    fi

    while IFS= read -r agent; do
        [[ -n "$agent" ]] || continue
        if ! agent_info="$(herdr_for_machine "$machine" agent get "$agent" 2> /dev/null)" ||
            ! pane_id="$(jq -er '.result.agent.pane_id | strings' <<< "$agent_info" 2> /dev/null)"; then
            emit_root_finding root_check_unavailable "$machine" "$agent"
            continue
        fi
        if ! snapshot="$(herdr_for_machine "$machine" pane read "$pane_id" --source visible --format ansi 2> /dev/null)"; then
            emit_root_finding root_check_unavailable "$machine" "$agent"
            continue
        fi

        input_state="$(visible_input_state <<< "$snapshot")"
        case "$input_state" in
        occupied) emit_root_finding root_input_occupied "$machine" "$agent" ;;
        unknown) emit_root_finding root_input_unreadable "$machine" "$agent" ;;
        esac
    done <<< "$roots"
}

function patrol_machine() {
    local machine="$1"
    local agents_json label

    if ! agents_json="$(herdr_for_machine "$machine" agent list 2> /dev/null)"; then
        emit_machine_finding server_unavailable "$machine"
        return 0
    fi
    if ! jq -e '.result.agents | type == "array"' <<< "$agents_json" > /dev/null 2>&1; then
        emit_machine_finding agent_list_unreadable "$machine"
        return 0
    fi

    label="$machine"
    [[ -n "$label" ]] || label=local
    jq -c --arg machine "$label" '
        .result.agents[] |
        select(.agent_status == "blocked" or .tokens.inbox != null) |
        {
            kind: "agent_attention",
            machine: $machine,
            agent: .name,
            pane_id: .pane_id,
            agent_status: .agent_status,
            inbox_pending: (.tokens.inbox != null)
        }
    ' <<< "$agents_json"

    check_root_inputs "$machine"
}

if [[ "$mode" == --limit-hold ]]; then
    run_meta_limit_hold
    exit $?
fi

machines_json=''
machine_inventory_available=0
if machines_json="$(herdr machine list --json 2> /dev/null)" &&
    jq -e '
        type == "array" and all(.[];
            (.enabled | type == "boolean") and
            (.label | type == "string" and length > 0 and (test("[\t\r\n]") | not))
        )
    ' <<< "$machines_json" > /dev/null 2>&1; then
    machine_inventory_available=1
else
    emit_machine_finding machine_inventory_unavailable ''
fi

patrol_machine ''

if ((machine_inventory_available)); then
    while IFS= read -r machine; do
        patrol_machine "$machine"
    done < <(jq -r '.[] | select(.enabled == true) | .label' <<< "$machines_json")

    while IFS= read -r machine; do
        if ! jq -e --arg machine "$machine" 'any(.[]; .enabled == true and .label == $machine)' \
            <<< "$machines_json" > /dev/null; then
            emit_machine_finding root_machine_not_enabled "$machine"
        fi
    done < <(jq -r '[.[] | .machine | select(type == "string")] | unique[]' <<< "$roots_json")
fi
