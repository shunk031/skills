#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh
# @brief Send an agent prompt only after its visible input line is empty.
# @description
#   Read the target pane's visible ANSI input line before sending. Ignore all
#   text from the dim suggestion marker to the line end, retry a busy or unclear
#   line five times, then report the unsent prompt.
# @arg $1 Target agent name or pane ID.
# @arg $2 Prompt text, passed as one argument.
# @example
#   herdr-agent-prompt-if-input-empty.sh orch "$report"

set -Eeuo pipefail

if [[ "${HERDR_ENV:-}" != 1 ]]; then
    printf '%s\n' 'prompt sender requires HERDR_ENV=1' >&2
    exit 2
fi

(($# == 2)) || {
    printf '%s\n' 'usage: herdr-agent-prompt-if-input-empty.sh TARGET MESSAGE' >&2
    exit 2
}

command -v herdr jq awk sleep > /dev/null || {
    printf '%s\n' 'prompt sender requires herdr, jq, awk, and sleep' >&2
    exit 127
}

target="$1"
message="$2"
attempt=0
max_retries=5

function visible_input_state() {
    local snapshot
    snapshot="$1"
    printf '%s\n' "$snapshot" | LC_ALL=C awk '
        {
            line = $0
            sub(/\033\[2m.*/, "", line)
            gsub(/\033\[[0-?]*[ -\/]*[@-~]/, "", line)
            if (match(line, /^[[:space:]]*(❯|›)/)) {
                found = 1
                rest = substr(line, RSTART + RLENGTH)
                occupied = rest ~ /[^[:space:]]/
            }
        }

        END {
            if (!found) print "unknown"
            else if (occupied) print "occupied"
            else print "empty"
        }
    '
}

while ((attempt <= max_retries)); do
    if agent_info="$(herdr agent get "$target" 2> /dev/null)" &&
        pane_id="$(jq -er '.result.agent.pane_id | strings' <<< "$agent_info" 2> /dev/null)" &&
        snapshot="$(herdr pane read "$pane_id" --source visible --format ansi 2> /dev/null)"; then
        input_state="$(visible_input_state "$snapshot")"
    else
        input_state=unknown
    fi

    if [[ "$input_state" == empty ]]; then
        herdr agent prompt "$target" "$message"
        exit $?
    fi

    if ((attempt == max_retries)); then
        printf 'undelivered to %s: target input was %s after %d retries; message was not sent:\n%s\n' \
            "$target" "$input_state" "$max_retries" "$message" >&2
        exit 75
    fi

    printf 'target %s input is %s; retry %d/%d in 30 seconds\n' \
        "$target" "$input_state" "$((attempt + 1))" "$max_retries" >&2
    sleep 30
    attempt=$((attempt + 1))
done
