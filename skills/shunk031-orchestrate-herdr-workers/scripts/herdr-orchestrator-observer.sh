#!/usr/bin/env bash

# @file skills/shunk031-orchestrate-herdr-workers/scripts/herdr-orchestrator-observer.sh
# @brief Observe fixed worker identities and coalesce bounded orchestrator nudges.
# @description
#   Scope is supplied as immutable worker, pane, and tab identities. Each sample
#   reads live Herdr state; alert and rearm memory stays in this process.
#
#   Per-worker memory is kept in newline-delimited `key<TAB>value` strings
#   rather than associative arrays. macOS ships Bash 3.2, which has no
#   `declare -A`, and this script runs on the machine an agent is working on.
#   Worker names, pane ids, and tab ids are validated against character classes
#   that exclude tabs and newlines, so they are safe as keys.

set -Eeuo pipefail

if [[ "${HERDR_ENV:-}" != 1 ]]; then
    printf '%s\n' 'observer requires HERDR_ENV=1' >&2
    exit 2
fi

ORCHESTRATOR=''
INTERVAL_SECONDS=60
STALE_SAMPLES=3
declare -a WORKER_SPECS=()
previous_fingerprint=''
previous_stable=''
previous_alerted=''

if (($# == 0)); then
    printf '%s\n' 'usage: herdr-orchestrator-observer.sh --orchestrator NAME --worker NAME|PANE|TAB [--worker ...] [--interval-seconds N] [--stale-samples N]' >&2
    exit 2
fi

while (($# > 0)); do
    case "$1" in
    --orchestrator)
        (($# >= 2)) || exit 2
        ORCHESTRATOR="$2"
        shift 2
        ;;
    --worker)
        (($# >= 2)) || exit 2
        WORKER_SPECS+=("$2")
        shift 2
        ;;
    --interval-seconds)
        (($# >= 2)) || exit 2
        INTERVAL_SECONDS="$2"
        shift 2
        ;;
    --stale-samples)
        (($# >= 2)) || exit 2
        STALE_SAMPLES="$2"
        shift 2
        ;;
    --help)
        printf '%s\n' 'usage: herdr-orchestrator-observer.sh --orchestrator NAME --worker NAME|PANE|TAB [--worker ...] [--interval-seconds N] [--stale-samples N]'
        exit 0
        ;;
    *)
        exit 2
        ;;
    esac
done

[[ "${ORCHESTRATOR}" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || exit 2
[[ "${INTERVAL_SECONDS}" =~ ^[1-9][0-9]*$ && "${STALE_SAMPLES}" =~ ^[1-9][0-9]*$ ]] || exit 2
((${#WORKER_SPECS[@]} == 0)) && exit 0

seen_names=''
seen_panes=''
seen_tabs=''
for spec in "${WORKER_SPECS[@]}"; do
    IFS='|' read -r name pane tab extra <<< "${spec}"
    [[ -n "${name}" && -n "${pane}" && -n "${tab}" && -z "${extra}" ]] || exit 2
    [[ "${name}" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || exit 2
    [[ "${pane}" =~ ^[A-Za-z0-9_-]+:[A-Za-z0-9_-]+$ && "${tab}" =~ ^[A-Za-z0-9_-]+:[A-Za-z0-9_-]+$ ]] || exit 2
    [[ "${name}" != "${ORCHESTRATOR}" ]] || exit 2
    printf '%s\n' "${seen_names}" | grep -Fxq -- "${name}" && exit 2
    printf '%s\n' "${seen_panes}" | grep -Fxq -- "${pane}" && exit 2
    printf '%s\n' "${seen_tabs}" | grep -Fxq -- "${tab}" && exit 2
    seen_names="${seen_names}${name}"$'\n'
    seen_panes="${seen_panes}${pane}"$'\n'
    seen_tabs="${seen_tabs}${tab}"$'\n'
done

for command in herdr jq shasum awk sleep; do
    command -v "${command}" > /dev/null || {
        printf 'observer: required command is missing: %s\n' "${command}" >&2
        exit 127
    }
done

function hash_text() {
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
}

#
# @description Read one value out of a `key<TAB>value` map.
# @arg $1 map string Newline-delimited `key<TAB>value` pairs.
# @arg $2 key string The key to look up.
# @stdout The value, or nothing when the key is absent.
#
function map_get() {
    printf '%s\n' "$1" | awk -F'\t' -v key="$2" 'NF && $1 == key { print $2; exit }'
}

#
# @description Print a `key<TAB>value` map with one key set to a new value.
# @description
#   The caller reassigns: `map="$(map_set "${map}" k v)"`. Setting an existing
#   key replaces it rather than appending, so a key never appears twice.
# @arg $1 map string Newline-delimited `key<TAB>value` pairs.
# @arg $2 key string The key to set.
# @arg $3 value string The value to store.
# @stdout The resulting map.
#
function map_set() {
    printf '%s\n' "$1" | awk -F'\t' -v key="$2" 'NF && $1 != key'
    printf '%s\t%s\n' "$2" "$3"
}

function observe_once() {
    local agents spec name pane tab row status revision state_seq tab_json label transcript transcript_sha
    local normalized_status fingerprint previous stable alerted complete open_pr_wait
    local matched_workers=0
    local nudge
    local -a report_lines=() pending_names=()
    local next_fingerprint='' next_stable='' next_alerted=''

    agents="$(herdr agent list 2> /dev/null)" || {
        printf '%s\n' 'observer: herdr agent list failed; sample rejected' >&2
        return 1
    }
    jq -e '.result.agents | type == "array"' <<< "${agents}" > /dev/null || {
        printf '%s\n' 'observer: malformed herdr agent list; sample rejected' >&2
        return 1
    }

    for spec in "${WORKER_SPECS[@]}"; do
        IFS='|' read -r name pane tab <<< "${spec}"
        if ! row="$(jq -er --arg name "${name}" --arg pane "${pane}" --arg tab "${tab}" '
			[.result.agents[]? | select(.name == $name and .pane_id == $pane and .tab_id == $tab)]
			| if length == 1 and (.[0].agent_status | type) == "string" and
				(.[0].revision | type) == "number" and (.[0].state_change_seq | type) == "number"
			  then .[0] | [.agent_status, .revision, .state_change_seq] | @tsv
			  else error("worker identity missing or malformed") end' <<< "${agents}")"; then
            printf 'observer: live identity read failed for %s; worker skipped\n' "${name}" >&2
            continue
        fi
        IFS=$'\t' read -r status revision state_seq <<< "${row}"
        [[ "${status}" =~ ^(working|idle|done|blocked|unknown)$ && "${revision}" =~ ^[0-9]+$ && "${state_seq}" =~ ^[0-9]+$ ]] || {
            printf 'observer: malformed live state for %s; worker skipped\n' "${name}" >&2
            continue
        }
        matched_workers=$((matched_workers + 1))

        if ! tab_json="$(herdr tab get "${tab}" 2> /dev/null)" || ! label="$(jq -er '.result.tab.label | strings' <<< "${tab_json}")"; then
            printf 'observer: tab read failed for %s; worker skipped\n' "${name}" >&2
            continue
        fi
        if ! transcript="$(herdr agent read "${name}" --source recent-unwrapped --lines 80 2> /dev/null)" || [[ -z "${transcript}" ]]; then
            printf 'observer: transcript read failed for %s; worker skipped\n' "${name}" >&2
            continue
        fi
        transcript_sha="$(hash_text "${transcript}")"

        normalized_status="${status}"
        [[ "${normalized_status}" == "done" ]] && normalized_status=idle
        fingerprint="$(hash_text "${name}|${pane}|${tab}|${normalized_status}|${revision}|${state_seq}|${label}|${transcript_sha}")"
        previous="$(map_get "${previous_fingerprint}" "${name}")"
        if [[ -n "${previous}" && "${fingerprint}" == "${previous}" ]]; then
            stable=$(($(map_get "${previous_stable}" "${name}") + 1))
            alerted="$(map_get "${previous_alerted}" "${name}")"
            alerted="${alerted:-0}"
        else
            stable=1
            alerted=0
        fi
        next_fingerprint="$(map_set "${next_fingerprint}" "${name}" "${fingerprint}")"
        next_stable="$(map_set "${next_stable}" "${name}" "${stable}")"
        next_alerted="$(map_set "${next_alerted}" "${name}" "${alerted}")"

        complete=0
        open_pr_wait=0
        case "${label}" in
        '✅ '*) complete=1 ;;
        '⛔ review and merge PR '*) open_pr_wait=1 ;;
        esac
        if [[ "${normalized_status}" == idle && "${complete}" == 1 && "${alerted}" != 1 ]]; then
            report_lines+=("- worker=${name} pane=${pane} tab=${tab} status=idle reason=completed resource needs bounded worktree and PR reconciliation (state_change_seq=${state_seq} revision=${revision} transcript_sha=${transcript_sha})")
            pending_names+=("${name}")
        elif ((stable >= STALE_SAMPLES)) && [[ "${open_pr_wait}" != 1 && "${alerted}" != 1 ]]; then
            if [[ "${normalized_status}" == working ]]; then
                report_lines+=("- worker=${name} pane=${pane} tab=${tab} status=working reason=no lifecycle/revision/transcript movement for ${stable} samples; this may be a quiet long command, reconcile why it looks stale before prompting or killing (state_change_seq=${state_seq} revision=${revision} transcript_sha=${transcript_sha})")
            else
                report_lines+=("- worker=${name} pane=${pane} tab=${tab} status=${normalized_status} reason=no lifecycle/revision/transcript movement for ${stable} samples; reconcile a missing report or handoff (state_change_seq=${state_seq} revision=${revision} transcript_sha=${transcript_sha})")
            fi
            pending_names+=("${name}")
        fi
    done

    ((matched_workers > 0)) || {
        printf '%s\n' 'observer: no scoped workers remain; stopping' >&2
        return 3
    }
    if ((${#report_lines[@]} > 0)); then
        nudge="$(
            printf 'OBSERVER %s: bounded reconciliation required\n' "${ORCHESTRATOR}"
            printf '%s\n' "${report_lines[@]}"
            printf '%s\n' 'Reconcile Herdr state/transcript and relevant worktree/PR/CI truth; this observer is read-only and the report is not terminal.'
        )"
        if herdr agent prompt "${ORCHESTRATOR}" "${nudge}" > /dev/null 2>&1; then
            for name in "${pending_names[@]}"; do
                next_alerted="$(map_set "${next_alerted}" "${name}" 1)"
            done
        else
            printf '%s\n' 'observer: orchestrator nudge failed; episode remains armed' >&2
        fi
    fi

    # The old code cleared each map and copied every key back from its `next_`
    # counterpart, which is what assignment does.
    previous_fingerprint="${next_fingerprint}"
    previous_stable="${next_stable}"
    previous_alerted="${next_alerted}"
}

trap 'exit 0' INT TERM
while :; do
    if observe_once; then
        :
    else
        status=$?
        ((status == 3)) && exit 0
    fi
    sleep "${INTERVAL_SECONDS}" &
    wait "$!" || true
done
