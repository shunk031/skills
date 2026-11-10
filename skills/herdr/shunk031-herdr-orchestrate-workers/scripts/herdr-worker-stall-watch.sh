#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-worker-stall-watch.sh
# @brief Alert when a matching Herdr worker pane shows a known stall signature.
# @description
#   Polls workers selected by an agent-name prefix and exits after the first
#   alert. Run with --once for a foreground health check before backgrounding.
# @option --agent-prefix PREFIX Required agent-name prefix to watch.
# @option --exclude-agent NAME Agent to skip, such as the orchestrator.
# @option --interval-seconds N Poll interval in seconds (default: 900).
# @option --once Check one cycle and exit.
# @option --help Show usage.

set -Eeuo pipefail

AGENT_PREFIX=''
EXCLUDED_AGENT=''
INTERVAL_SECONDS=900
CHECK_ONCE=0

# @description Print usage and exit with a caller-provided status.
# @arg $1 status Exit status to return.
function usage() {
    local status="$1"
    cat << 'USAGE'
Usage: herdr-worker-stall-watch.sh --agent-prefix PREFIX [options]

Options:
  --agent-prefix PREFIX   Required agent-name prefix to watch.
  --exclude-agent NAME     Ignore one agent, such as the orchestrator.
  --interval-seconds N     Poll interval in seconds (default: 900).
  --once                   Check one cycle and exit.
  --help                   Show this help.
USAGE
    exit "$status"
}

while (($# > 0)); do
    case "$1" in
    --agent-prefix)
        (($# >= 2)) || usage 2
        AGENT_PREFIX="$2"
        shift 2
        ;;
    --exclude-agent)
        (($# >= 2)) || usage 2
        EXCLUDED_AGENT="$2"
        shift 2
        ;;
    --interval-seconds)
        (($# >= 2)) || usage 2
        INTERVAL_SECONDS="$2"
        shift 2
        ;;
    --once)
        CHECK_ONCE=1
        shift
        ;;
    --help)
        usage 0
        ;;
    *)
        usage 2
        ;;
    esac
done

[[ -n "${AGENT_PREFIX}" && "${AGENT_PREFIX}" != *$'\n'* && "${AGENT_PREFIX}" != *$'\t'* ]] || usage 2
[[ "${EXCLUDED_AGENT}" != *$'\n'* && "${EXCLUDED_AGENT}" != *$'\t'* ]] || usage 2
[[ "${INTERVAL_SECONDS}" =~ ^[1-9][0-9]*$ ]] || usage 2
[[ "${HERDR_ENV:-}" == 1 ]] || {
    printf '%s\n' 'worker stall watcher requires HERDR_ENV=1' >&2
    exit 2
}

for command in herdr jq tail date sleep; do
    command -v "${command}" > /dev/null || {
        printf 'worker stall watcher: required command is missing: %s\n' "${command}" >&2
        exit 127
    }
done

# @description Read one Herdr snapshot and alert on its first matching stall.
# @stdout Prints one STALL line on an alert, or an OK line in --once mode.
# @exitcode 0 A scan completed without an alert.
# @exitcode 1 Herdr returned an invalid or unreadable worker snapshot.
# @exitcode 3 A stall signature was found.
function observe_once() {
    local agents name status pane pane_tail matched=0

    agents="$(herdr agent list 2> /dev/null)" || {
        printf '%s\n' 'worker stall watcher: herdr agent list failed' >&2
        return 1
    }
    if ! jq -e '.result.agents | type == "array"' <<< "${agents}" > /dev/null; then
        printf '%s\n' 'worker stall watcher: malformed herdr agent list' >&2
        return 1
    fi

    while IFS=$'\t' read -r name status pane; do
        [[ -n "${name}" ]] || continue
        [[ -z "${EXCLUDED_AGENT}" || "${name}" != "${EXCLUDED_AGENT}" ]] || continue
        case "${status}" in
        working | blocked | idle) ;;
        *) continue ;;
        esac
        [[ -n "${pane}" ]] || {
            printf 'worker stall watcher: missing pane id for %s\n' "${name}" >&2
            return 1
        }
        matched=$((matched + 1))

        if ! pane_tail="$(herdr pane read "${pane}" 2> /dev/null | tail -n 25)"; then
            printf 'worker stall watcher: pane read failed for %s\n' "${name}" >&2
            return 1
        fi
        if [[ "${pane_tail}" == *'Exceeded retry limit'* ]]; then
            printf '%s\n' "$(date)" "STALL ${name} ${pane} gateway reconnect loop"
            return 3
        elif [[ "${pane_tail}" == *'? 1 question'* ]]; then
            printf '%s\n' "$(date)" "STALL ${name} ${pane} unanswered queued question"
            return 3
        elif [[ "${status}" == working && "${pane_tail}" == *'Context 0% used'* ]]; then
            printf '%s\n' "$(date)" "STALL ${name} ${pane} blank restarted session marked working"
            return 3
        fi
    done < <(
        jq -r --arg prefix "${AGENT_PREFIX}" \
            '.result.agents[] | select((.name // "") | startswith($prefix)) | [.name // "", .agent_status // "", .pane_id // ""] | @tsv' \
            <<< "${agents}"
    )

    if ((matched == 0 && CHECK_ONCE == 1)); then
        printf 'worker stall watcher: no active agents match prefix %s\n' "${AGENT_PREFIX}" >&2
        return 1
    fi
    if ((CHECK_ONCE == 1)); then
        printf 'OK: scanned %s matching agent(s); no stall signatures found.\n' "${matched}"
    fi
    return 0
}

while :; do
    if observe_once; then
        ((CHECK_ONCE == 0)) || exit 0
    else
        status=$?
        if ((status == 3)); then
            ((CHECK_ONCE == 1)) && exit 3
            exit 0
        fi
        exit "${status}"
    fi
    sleep "${INTERVAL_SECONDS}"
done
