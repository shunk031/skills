#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-meta-orchestrate/scripts/herdr-meta-patrol.sh
# @brief Report agent attention and occupied root input lines across enabled Herdr servers.
# @description
#   Read-only patrol for the local server and each enabled saved machine.
#   HERDR_PATROL_ROOTS_JSON supplies verified root agents as objects with
#   machine: null for local or a saved machine label, and an agent name.
# @stdout One compact JSON object per finding. No output means no findings.
# @exitcode 2 when prerequisites or the root configuration are invalid.
# @example
#   HERDR_PATROL_ROOTS_JSON='[{"machine":null,"agent":"meta"}]' herdr-meta-patrol.sh

set -Eeuo pipefail

if [[ "${HERDR_ENV:-}" != 1 ]]; then
    printf '%s\n' 'patrol requires HERDR_ENV=1' >&2
    exit 2
fi

if (($# != 0)); then
    printf '%s\n' 'usage: herdr-meta-patrol.sh (configure roots with HERDR_PATROL_ROOTS_JSON)' >&2
    exit 2
fi

for command in herdr jq awk; do
    command -v "$command" > /dev/null || {
        printf 'patrol: required command is missing: %s\n' "$command" >&2
        exit 2
    }
done

roots_json="${HERDR_PATROL_ROOTS_JSON:-[]}"
if ! jq -e '
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
