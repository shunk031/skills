#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh
# @brief Send an agent prompt only after its visible input line is empty.
# @description
#   Read the target pane's visible ANSI input line before sending. Ignore plain
#   dim placeholder and suggestion spans, retry a busy or unclear line five
#   times, then report the unsent prompt.
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
        function apply_sgr(params, count, codes, i, code, mode) {
            if (params == "") {
                dim = 0
                return
            }

            count = split(params, codes, ";")
            for (i = 1; i <= count; i++) {
                code = codes[i]
                if (code ~ /^(38|48|58):/) continue
                if (code == "" || code == "0" || code == "22") dim = 0
                else if (code == "2") dim = 1
                else if (code == "38" || code == "48" || code == "58") {
                    mode = codes[i + 1]
                    if (mode == "2") i += 4
                    else if (mode == "5") i += 2
                }
            }
        }

        {
            line = $0
            sub(/\r$/, "", line)
            plain = ""
            dim_mask = ""
            dim = 0
            for (i = 1; i <= length(line);) {
                if (substr(line, i, 1) == "\033" && substr(line, i + 1, 1) == "[") {
                    j = i + 2
                    while (j <= length(line) && substr(line, j, 1) !~ /[@-~]/) j++
                    if (j <= length(line)) {
                        if (substr(line, j, 1) == "m") {
                            apply_sgr(substr(line, i + 2, j - i - 2))
                        }
                        i = j + 1
                        continue
                    }
                }

                char = substr(line, i, 1)
                plain = plain char
                dim_mask = dim_mask (dim ? "1" : "0")
                i++
            }

            if (match(plain, /^[[:space:]]*(❯|›)/)) {
                found = 1
                for (i = RSTART + RLENGTH; i <= length(plain); i++) {
                    char = substr(plain, i, 1)
                    if (substr(dim_mask, i, 1) == "0" && char ~ /[^[:space:]]/) {
                        occupied = 1
                        break
                    }
                }
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
