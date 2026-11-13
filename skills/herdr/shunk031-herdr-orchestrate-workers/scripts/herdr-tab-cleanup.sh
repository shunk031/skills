#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-tab-cleanup.sh
# @brief Report or close local Herdr tabs whose ownership and safety are proven.
# @description
#   Requires every pane to match a caller-created dispatch record, a completed
#   worker, and empty visible input. It keeps ⛔ tabs and never removes worktrees
#   or branches; it leaves one tab in each workspace.
# @option --apply Close only named candidates after fresh safety checks.
# @option --results-collected TAB_ID Confirm results and select one tab; repeatable.
# @option --record-worker NAME Record a directly dispatched worker's terminal, tab, and pane.
# @option --help Show usage.
# @example
#   scripts/herdr-tab-cleanup.sh
#   scripts/herdr-tab-cleanup.sh --apply --results-collected <tab-id>
#   scripts/herdr-tab-cleanup.sh --record-worker <worker-name>

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
INPUT_STATE_AWK="${SCRIPT_DIR}/herdr-visible-input-state.awk"
APPLY=0
RESULTS_COLLECTED_TABS=()
RECORD_WORKER=''
CALLER_NAME=''
CALLER_TAB=''
CALLER_TERMINAL=''
CALLER_IDENTITY_OK=0
TABS_JSON=''
PANES_JSON=''
AGENTS_JSON=''
RECORDS_STATE='missing'
RECORDS_FILE=''
RECORDS_DIR=''
RECORD_LOCK=''
RECORD_LOCK_HELD=0
RECHECK_EVIDENCE=''

if [ -n "${HERDR_TAB_CLEANUP_STATE_DIR:-}" ]; then
    RECORDS_DIR="${HERDR_TAB_CLEANUP_STATE_DIR}"
elif [ -n "${XDG_STATE_HOME:-}" ]; then
    RECORDS_DIR="${XDG_STATE_HOME}/herdr-tab-cleanup"
elif [ -n "${HOME:-}" ]; then
    RECORDS_DIR="${HOME}/.local/state/herdr-tab-cleanup"
fi
if [ -n "$RECORDS_DIR" ]; then
    RECORDS_FILE="${RECORDS_DIR}/dispatches.tsv"
    RECORD_LOCK="${RECORDS_DIR}/.dispatches.lock"
fi

function usage() {
    cat << 'USAGE'
Usage: herdr-tab-cleanup.sh [--apply] [--results-collected <tab-id> ...] [--help]

By default, report a close/keep verdict for each local Herdr tab.
--apply requires one or more --results-collected <tab-id> options and closes only
those named tabs after refreshing inventories and repeating safety checks.
--results-collected <tab-id> confirms collection for that worker tab and selects
it for closure when the tab otherwise qualifies; repeat the option per tab.
--record-worker <name> records a worker terminal/tab/pane after this caller dispatches it.
USAGE
}

function fail() {
    printf 'herdr tab cleanup: %s\n' "$1" >&2
    exit "${2:-1}"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
    --apply) APPLY=1 ;;
    --results-collected)
        [ "$#" -ge 2 ] && [ -n "$2" ] || fail "--results-collected requires a tab ID" 2
        RESULTS_COLLECTED_TABS[${#RESULTS_COLLECTED_TABS[@]}]="$2"
        shift
        ;;
    --record-worker)
        [ "$#" -ge 2 ] && [ -n "$2" ] || fail "--record-worker requires a worker name" 2
        [ -z "$RECORD_WORKER" ] || fail "--record-worker may be specified only once" 2
        RECORD_WORKER="$2"
        shift
        ;;
    --help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        fail "unknown option: $1" 2
        ;;
    esac
    shift
done

if [ -n "$RECORD_WORKER" ]; then
    [ "$APPLY" -eq 0 ] && [ "${#RESULTS_COLLECTED_TABS[@]}" -eq 0 ] || fail "--record-worker cannot be combined with cleanup options" 2
elif [ "$APPLY" -eq 1 ] && [ "${#RESULTS_COLLECTED_TABS[@]}" -eq 0 ]; then
    fail "--apply requires one or more --results-collected <tab-id> options" 2
fi

if [ "${HERDR_ENV:-}" != "1" ]; then
    fail "HERDR_ENV=1 is required; this helper targets the local Herdr server"
fi
if [ -z "${HERDR_PANE_ID:-}" ] || [ -z "${HERDR_TAB_ID:-}" ]; then
    fail "HERDR_PANE_ID and HERDR_TAB_ID are required to prove the caller identity"
fi
command -v jq > /dev/null 2>&1 || fail "jq is required"
[ -r "$INPUT_STATE_AWK" ] || fail "visible-input parser is missing: $INPUT_STATE_AWK"

TABS_JSON=''
PANES_JSON=''
AGENTS_JSON=''
# @description Read the local tab, pane, and agent inventories.
function load_inventory() {
    TABS_JSON="$(herdr tab list 2> /dev/null)" || return 1
    PANES_JSON="$(herdr pane list 2> /dev/null)" || return 1
    AGENTS_JSON="$(herdr agent list 2> /dev/null)" || return 1
    printf '%s\n' "$TABS_JSON" | jq -e '.result.tabs | type == "array"' > /dev/null 2>&1 || return 1
    printf '%s\n' "$PANES_JSON" | jq -e '.result.panes | type == "array"' > /dev/null 2>&1 || return 1
    printf '%s\n' "$AGENTS_JSON" | jq -e '.result.agents | type == "array"' > /dev/null 2>&1 || return 1
}

# @description Identify the caller from its Herdr pane.
function identify_caller() {
    local matches agent_json pane_matches pane_json agent_terminal pane_terminal
    CALLER_IDENTITY_OK=0
    CALLER_NAME=''
    CALLER_TAB=''
    CALLER_TERMINAL=''
    matches="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg pane "$HERDR_PANE_ID" --arg tab "$HERDR_TAB_ID" '[.result.agents[] | select(.pane_id == $pane and .tab_id == $tab)] | length')"
    [ "$matches" = "1" ] || return 1
    agent_json="$(printf '%s\n' "$AGENTS_JSON" | jq -c --arg pane "$HERDR_PANE_ID" --arg tab "$HERDR_TAB_ID" '[.result.agents[] | select(.pane_id == $pane and .tab_id == $tab)][0]')"
    CALLER_NAME="$(printf '%s\n' "$agent_json" | jq -r '.name // empty')"
    CALLER_TAB="$(printf '%s\n' "$agent_json" | jq -r '.tab_id // empty')"
    CALLER_TERMINAL="$(printf '%s\n' "$agent_json" | jq -r '.terminal_id // empty')"
    pane_matches="$(printf '%s\n' "$PANES_JSON" | jq -r --arg pane "$HERDR_PANE_ID" --arg tab "$HERDR_TAB_ID" '[.result.panes[] | select(.pane_id == $pane and .tab_id == $tab)] | length')"
    [ "$pane_matches" = "1" ] || return 1
    pane_json="$(printf '%s\n' "$PANES_JSON" | jq -c --arg pane "$HERDR_PANE_ID" --arg tab "$HERDR_TAB_ID" '[.result.panes[] | select(.pane_id == $pane and .tab_id == $tab)][0]')"
    pane_terminal="$(printf '%s\n' "$pane_json" | jq -r '.terminal_id // empty')"
    [ -n "$CALLER_NAME" ] && [ "$CALLER_TAB" = "$HERDR_TAB_ID" ] && [ -n "$CALLER_TERMINAL" ] && [ "$CALLER_TERMINAL" = "$pane_terminal" ] || return 1
    CALLER_IDENTITY_OK=1
}

# @description Validate the caller's opt-in dispatch record file, if present.
function inspect_dispatch_records() {
    if [ -z "$RECORDS_FILE" ] || [ -L "$RECORDS_FILE" ] || [ ! -e "$RECORDS_FILE" ]; then
        RECORDS_STATE='missing'
        return 0
    fi
    if [ ! -f "$RECORDS_FILE" ] || [ ! -r "$RECORDS_FILE" ]; then
        RECORDS_STATE='invalid'
        return 0
    fi
    if awk -F '\t' 'NF != 6 || $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" || $6 == "" { bad = 1 } END { exit bad ? 1 : 0 }' "$RECORDS_FILE"; then
        RECORDS_STATE='valid'
    else
        RECORDS_STATE='invalid'
    fi
}

# @description Count exact caller/worker/terminal/tab/pane dispatch records.
# @arg $1 caller Caller agent name.
# @arg $2 caller_terminal Caller terminal ID.
# @arg $3 worker Dispatched worker name.
# @arg $4 worker_terminal Worker terminal ID.
# @arg $5 tab_id Herdr tab ID.
# @arg $6 pane_id Herdr pane ID.
function dispatch_record_count() {
    [ "$RECORDS_STATE" = 'valid' ] || {
        printf '0\n'
        return 0
    }
    awk -F '\t' -v caller="$1" -v caller_terminal="$2" -v worker="$3" -v worker_terminal="$4" -v tab="$5" -v pane="$6" \
        '$1 == caller && $2 == caller_terminal && $3 == worker && $4 == worker_terminal && $5 == tab && $6 == pane { count++ } END { print count + 0 }' \
        "$RECORDS_FILE"
}

# @description Tell whether a tab ID was explicitly named for this cleanup run.
# @arg $1 tab_id Herdr tab ID.
function tab_was_selected() {
    local selected
    [ "${#RESULTS_COLLECTED_TABS[@]}" -gt 0 ] || return 1
    for selected in "${RESULTS_COLLECTED_TABS[@]}"; do
        [ "$selected" = "$1" ] && return 0
    done
    return 1
}

# @description Release the dispatch-record writer lock.
function release_dispatch_lock() {
    if [ "$RECORD_LOCK_HELD" -eq 1 ]; then
        rmdir "$RECORD_LOCK" 2> /dev/null || true
        RECORD_LOCK_HELD=0
    fi
}

# @description Acquire a bounded lock before appending a dispatch record.
function acquire_dispatch_lock() {
    local attempt
    [ -n "$RECORDS_DIR" ] && [ -n "$RECORDS_FILE" ] || return 1
    case "$RECORDS_DIR" in
    /*) ;;
    *) return 1 ;;
    esac
    [ ! -L "$RECORDS_DIR" ] || return 1
    mkdir -p "$RECORDS_DIR" 2> /dev/null || return 1
    [ ! -L "$RECORDS_DIR" ] || return 1
    chmod 700 "$RECORDS_DIR" 2> /dev/null || return 1
    attempt=0
    while [ "$attempt" -lt 10 ]; do
        if mkdir "$RECORD_LOCK" 2> /dev/null; then
            RECORD_LOCK_HELD=1
            trap 'release_dispatch_lock' EXIT
            trap 'exit 130' INT
            trap 'exit 143' TERM
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
}

# @description Record the caller and worker terminal IDs with a directly dispatched worker's tab and pane.
# @stdout A confirmation with caller, worker, terminal, tab, and pane identities.
function record_worker_dispatch() {
    local worker_matches worker_json worker_pane worker_tab worker_terminal worker_pane_matches worker_pane_json worker_pane_terminal tab_matches existing conflicting
    [ "$CALLER_IDENTITY_OK" -eq 1 ] || fail "caller identity could not be proven"
    [ -n "$RECORDS_FILE" ] || fail "XDG_STATE_HOME or HOME is required for dispatch records"
    worker_matches="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg name "$RECORD_WORKER" '[.result.agents[] | select(.name == $name)] | length')"
    [ "$worker_matches" = '1' ] || fail "worker must match exactly one live Herdr agent"
    worker_json="$(printf '%s\n' "$AGENTS_JSON" | jq -c --arg name "$RECORD_WORKER" '[.result.agents[] | select(.name == $name)][0]')"
    worker_pane="$(printf '%s\n' "$worker_json" | jq -r '.pane_id // empty')"
    worker_tab="$(printf '%s\n' "$worker_json" | jq -r '.tab_id // empty')"
    worker_terminal="$(printf '%s\n' "$worker_json" | jq -r '.terminal_id // empty')"
    [ -n "$worker_pane" ] && [ -n "$worker_tab" ] && [ -n "$worker_terminal" ] || fail "worker pane, tab, or terminal ID is unknown"
    [ "$worker_tab" != "$CALLER_TAB" ] && [ "$worker_tab" != "$HERDR_TAB_ID" ] || fail "cannot record the caller's own tab"
    worker_pane_matches="$(printf '%s\n' "$PANES_JSON" | jq -r --arg pane "$worker_pane" --arg tab "$worker_tab" '[.result.panes[] | select(.pane_id == $pane and .tab_id == $tab)] | length')"
    [ "$worker_pane_matches" = '1' ] || fail "worker pane does not uniquely match the live pane inventory"
    worker_pane_json="$(printf '%s\n' "$PANES_JSON" | jq -c --arg pane "$worker_pane" --arg tab "$worker_tab" '[.result.panes[] | select(.pane_id == $pane and .tab_id == $tab)][0]')"
    worker_pane_terminal="$(printf '%s\n' "$worker_pane_json" | jq -r '.terminal_id // empty')"
    [ "$worker_terminal" = "$worker_pane_terminal" ] || fail "worker agent and pane terminal IDs do not match"
    tab_matches="$(printf '%s\n' "$TABS_JSON" | jq -r --arg tab "$worker_tab" '[.result.tabs[] | select(.tab_id == $tab)] | length')"
    [ "$tab_matches" = '1' ] || fail "worker tab does not uniquely match the live tab inventory"

    acquire_dispatch_lock || fail "could not acquire the dispatch-record lock"
    if [ -L "$RECORDS_FILE" ] || { [ -e "$RECORDS_FILE" ] && [ ! -f "$RECORDS_FILE" ]; }; then
        fail "dispatch-record path is not a regular file"
    fi
    if [ -e "$RECORDS_FILE" ]; then
        [ -r "$RECORDS_FILE" ] || fail "dispatch-record file is unreadable"
        awk -F '\t' 'NF != 6 || $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" || $6 == "" { bad = 1 } END { exit bad ? 1 : 0 }' "$RECORDS_FILE" || fail "dispatch-record file is malformed"
        existing="$(awk -F '\t' -v caller="$CALLER_NAME" -v caller_terminal="$CALLER_TERMINAL" -v worker="$RECORD_WORKER" -v worker_terminal="$worker_terminal" -v tab="$worker_tab" -v pane="$worker_pane" \
            '$1 == caller && $2 == caller_terminal && $3 == worker && $4 == worker_terminal && $5 == tab && $6 == pane { count++ } END { print count + 0 }' "$RECORDS_FILE")"
        conflicting="$(awk -F '\t' -v caller="$CALLER_NAME" -v caller_terminal="$CALLER_TERMINAL" -v worker="$RECORD_WORKER" -v worker_terminal="$worker_terminal" -v tab="$worker_tab" -v pane="$worker_pane" \
            '$4 == worker_terminal && $5 == tab && $6 == pane && !($1 == caller && $2 == caller_terminal && $3 == worker) { count++ } END { print count + 0 }' "$RECORDS_FILE")"
    else
        existing=0
        conflicting=0
    fi
    [ "$conflicting" -eq 0 ] || fail "worker tab/pane already has a different dispatch owner"
    [ "$existing" -le 1 ] || fail "dispatch record is duplicated"
    if [ "$existing" -eq 0 ]; then
        (umask 077 && : >> "$RECORDS_FILE") || fail "cannot create dispatch-record file"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$CALLER_NAME" "$CALLER_TERMINAL" "$RECORD_WORKER" "$worker_terminal" "$worker_tab" "$worker_pane" >> "$RECORDS_FILE" || fail "cannot append dispatch record"
    fi
    chmod 600 "$RECORDS_FILE" 2> /dev/null || fail "cannot secure dispatch-record file"
    release_dispatch_lock
    trap - EXIT INT TERM
    printf 'recorded caller=%s caller-terminal=%s worker=%s worker-terminal=%s tab=%s pane=%s\n' "$CALLER_NAME" "$CALLER_TERMINAL" "$RECORD_WORKER" "$worker_terminal" "$worker_tab" "$worker_pane"
}

# @description Resolve a Git metadata path to an absolute path.
# @arg $1 path Worktree path used for Git discovery.
# @arg $2 git_path Git metadata path returned by Git.
function canonical_git_path() {
    local path="$1"
    local git_path="$2"
    case "$git_path" in
    /*) ;;
    *) git_path="${path}/${git_path}" ;;
    esac
    (cd "$git_path" 2> /dev/null && pwd -P)
}

# @description Return evidence when a branch has a merged pull request.
# @arg $1 root Worktree root.
# @arg $2 branch Local branch name.
function merged_pr_evidence() {
    local root="$1"
    local branch="$2"
    local pr_json state head merged_at
    [ -n "$branch" ] && command -v gh > /dev/null 2>&1 || return 1
    pr_json="$(cd "$root" && gh pr view "$branch" --json state,headRefName,mergedAt 2> /dev/null)" || return 1
    printf '%s\n' "$pr_json" | jq -e 'type == "object"' > /dev/null 2>&1 || return 1
    state="$(printf '%s\n' "$pr_json" | jq -r '.state // empty')"
    head="$(printf '%s\n' "$pr_json" | jq -r '.headRefName // empty')"
    merged_at="$(printf '%s\n' "$pr_json" | jq -r '.mergedAt // empty')"
    [ "$state" = "MERGED" ] && [ "$head" = "$branch" ] && [ -n "$merged_at" ] || return 1
    printf 'pull request for branch %s is merged\n' "$branch"
}

# @description Classify one tab from the current inventory and live pane state.
# @arg $1 tab_id Herdr tab ID.
# @stdout One tab-separated verdict and evidence string.
function classify_tab() {
    local tab_id="$1"
    local tab_json workspace_id focused declared_count pane_rows pane_count
    local pane_id pane_terminal cwd foreground_cwd check_path root git_dir common_dir canonical_git canonical_common
    local agent_matches agent_json agent_name agent_terminal agent_status input_text input_state
    local candidate_root candidate_branch merged_evidence tab_match_count unique_pane_count tab_agent_count record_count

    if [ "$CALLER_IDENTITY_OK" -ne 1 ]; then
        printf 'keep\tcaller identity could not be proven\n'
        return 0
    fi
    tab_match_count="$(printf '%s\n' "$TABS_JSON" | jq -r --arg tab "$tab_id" '[.result.tabs[] | select(.tab_id == $tab)] | length')"
    [ "$tab_match_count" = "1" ] || {
        printf 'keep\ttab identity is missing or duplicated\n'
        return 0
    }
    tab_json="$(printf '%s\n' "$TABS_JSON" | jq -c --arg tab "$tab_id" '[.result.tabs[] | select(.tab_id == $tab)][0] // empty')"
    [ -n "$tab_json" ] || {
        printf 'keep\ttab is missing from the current inventory\n'
        return 0
    }

    if printf '%s\n' "$tab_json" | jq -e '(.label | type == "string") and (.label | startswith("⛔"))' > /dev/null 2>&1; then
        printf 'keep\ttab label starts with ⛔\n'
        return 0
    fi

    workspace_id="$(printf '%s\n' "$tab_json" | jq -r '.workspace_id // empty')"
    focused="$(printf '%s\n' "$tab_json" | jq -r 'if .focused == true then "true" elif .focused == false then "false" else "unknown" end')"
    declared_count="$(printf '%s\n' "$tab_json" | jq -r 'if (.pane_count | type) == "number" then .pane_count else "unknown" end')"
    if [ "$tab_id" = "$HERDR_TAB_ID" ] || [ "$tab_id" = "$CALLER_TAB" ]; then
        printf 'keep\tcaller own tab\n'
        return 0
    fi
    [ "$focused" != "unknown" ] || {
        printf 'keep\tfocused state is unknown\n'
        return 0
    }
    [ "$focused" != "true" ] || {
        printf 'keep\ttab is focused\n'
        return 0
    }
    [ -n "$workspace_id" ] || {
        printf 'keep\tworkspace ownership is unknown\n'
        return 0
    }

    pane_rows="$(printf '%s\n' "$PANES_JSON" | jq -r --arg tab "$tab_id" '[.result.panes[] | select(.tab_id == $tab)] | .[] | [.pane_id, (.terminal_id // ""), (.cwd // ""), (.foreground_cwd // "")] | @tsv')"
    pane_count="$(printf '%s\n' "$PANES_JSON" | jq -r --arg tab "$tab_id" '[.result.panes[] | select(.tab_id == $tab)] | length')"
    unique_pane_count="$(printf '%s\n' "$PANES_JSON" | jq -r --arg tab "$tab_id" '[.result.panes[] | select(.tab_id == $tab) | .pane_id | select(type == "string" and length > 0)] | unique | length')"
    tab_agent_count="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg tab "$tab_id" '[.result.agents[] | select(.tab_id == $tab)] | length')"
    case "$declared_count" in
    '' | unknown)
        printf 'keep\ttab pane count is unknown\n'
        return 0
        ;;
    esac
    if [ "$pane_count" -eq 0 ] || [ "$pane_count" != "$declared_count" ]; then
        printf 'keep\tpane inventory is empty or inconsistent\n'
        return 0
    fi
    if [ "$unique_pane_count" != "$pane_count" ]; then
        printf 'keep\tpane inventory contains duplicate or unnamed panes\n'
        return 0
    fi
    if [ "$tab_agent_count" -gt "$pane_count" ]; then
        printf 'keep\tagent inventory has extra agents not represented by panes\n'
        return 0
    fi

    candidate_root=''
    candidate_branch=''
    while IFS="$(printf '\t')" read -r pane_id pane_terminal cwd foreground_cwd; do
        if [ -z "$pane_id" ]; then
            [ -z "$cwd" ] && [ -z "$foreground_cwd" ] && continue
            printf 'keep\tpane inventory contains an unnamed pane\n'
            return 0
        fi
        agent_matches="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg pane "$pane_id" --arg tab "$tab_id" '[.result.agents[] | select(.pane_id == $pane and .tab_id == $tab)] | length')"
        [ "$agent_matches" = "1" ] || {
            printf 'keep\tpane %s has no unique named agent; owner is unknown\n' "$pane_id"
            return 0
        }
        agent_json="$(printf '%s\n' "$AGENTS_JSON" | jq -c --arg pane "$pane_id" --arg tab "$tab_id" '[.result.agents[] | select(.pane_id == $pane and .tab_id == $tab)][0]')"
        agent_name="$(printf '%s\n' "$agent_json" | jq -r '.name // empty')"
        agent_terminal="$(printf '%s\n' "$agent_json" | jq -r '.terminal_id // empty')"
        agent_status="$(printf '%s\n' "$agent_json" | jq -r '.agent_status // empty')"
        [ -n "$agent_name" ] && [ -n "$pane_terminal" ] && [ "$agent_terminal" = "$pane_terminal" ] || {
            printf 'keep\tpane %s agent or terminal identity is unknown or inconsistent\n' "$pane_id"
            return 0
        }
        case "$RECORDS_STATE" in
        valid)
            record_count="$(dispatch_record_count "$CALLER_NAME" "$CALLER_TERMINAL" "$agent_name" "$agent_terminal" "$tab_id" "$pane_id")"
            [ "$record_count" = '1' ] || {
                printf 'keep\tpane %s was not recorded as created by this caller at dispatch\n' "$pane_id"
                return 0
            }
            ;;
        missing)
            printf 'keep\tcaller dispatch record is missing\n'
            return 0
            ;;
        *)
            printf 'keep\tcaller dispatch record is unreadable or malformed\n'
            return 0
            ;;
        esac
        [ "$(printf '%s\n' "$agent_json" | jq -r '.tab_id // empty')" = "$tab_id" ] || {
            printf 'keep\tpane %s agent is attached to a different tab\n' "$pane_id"
            return 0
        }
        case "$agent_status" in
        done | exited) ;;
        *)
            printf 'keep\tpane %s agent %s is %s, not done or exited\n' "$pane_id" "$agent_name" "${agent_status:-unknown}"
            return 0
            ;;
        esac

        input_text="$(herdr pane read "$pane_id" --source visible --format ansi 2> /dev/null)" || {
            printf 'keep\tpane %s visible input could not be read\n' "$pane_id"
            return 0
        }
        input_state="$(printf '%s\n' "$input_text" | LC_ALL=C awk -f "$INPUT_STATE_AWK")"
        [ "$input_state" = "empty" ] || {
            printf 'keep\tpane %s visible input is %s\n' "$pane_id" "$input_state"
            return 0
        }

        [ -n "$foreground_cwd" ] || foreground_cwd="$cwd"
        [ -n "$cwd" ] && [ -n "$foreground_cwd" ] || {
            printf 'keep\tpane %s worktree path is unknown\n' "$pane_id"
            return 0
        }
        for check_path in "$cwd" "$foreground_cwd"; do
            [ -d "$check_path" ] || {
                printf 'keep\tpane %s worktree path is missing\n' "$pane_id"
                return 0
            }
            root="$(git -C "$check_path" rev-parse --show-toplevel 2> /dev/null)" || {
                printf 'keep\tpane %s is not in a provable Git worktree\n' "$pane_id"
                return 0
            }
            git_dir="$(git -C "$check_path" rev-parse --git-dir 2> /dev/null)" || {
                printf 'keep\tpane %s Git directory is unknown\n' "$pane_id"
                return 0
            }
            common_dir="$(git -C "$check_path" rev-parse --git-common-dir 2> /dev/null)" || {
                printf 'keep\tpane %s common Git directory is unknown\n' "$pane_id"
                return 0
            }
            canonical_git="$(canonical_git_path "$check_path" "$git_dir")" || {
                printf 'keep\tpane %s Git directory cannot be resolved\n' "$pane_id"
                return 0
            }
            canonical_common="$(canonical_git_path "$check_path" "$common_dir")" || {
                printf 'keep\tpane %s common Git directory cannot be resolved\n' "$pane_id"
                return 0
            }
            [ "$canonical_git" != "$canonical_common" ] || {
                printf 'keep\tpane %s is in a primary checkout\n' "$pane_id"
                return 0
            }
            if [ -z "$candidate_root" ]; then
                candidate_root="$root"
                candidate_branch="$(git -C "$check_path" branch --show-current 2> /dev/null)"
            elif [ "$candidate_root" != "$root" ]; then
                printf 'keep\ttab panes use different worktrees\n'
                return 0
            fi
        done
    done << EOF
$pane_rows
EOF

    [ -n "$candidate_root" ] || {
        printf 'keep\tworktree could not be proven\n'
        return 0
    }
    merged_evidence="$(merged_pr_evidence "$candidate_root" "$candidate_branch" 2> /dev/null)" || merged_evidence=''
    if [ -n "$merged_evidence" ]; then
        printf 'close\tall panes match caller dispatch records, workers are done or exited, and visible inputs appear empty; %s\n' "$merged_evidence"
    elif tab_was_selected "$tab_id"; then
        printf 'close\tall panes match caller dispatch records, workers are done or exited, visible inputs appear empty, and results for this tab were confirmed\n'
    else
        printf 'keep\tno matching merged PR; results for this tab were not confirmed\n'
    fi
}

# @description Count the currently listed tabs in a workspace.
# @arg $1 workspace_id Herdr workspace ID.
function workspace_tab_count() {
    printf '%s\n' "$TABS_JSON" | jq -r --arg workspace "$1" '[.result.tabs[] | select(.workspace_id == $workspace)] | length'
}

# @description Re-read lifecycle and visible input after pull-request lookup.
# @arg $1 tab_id Herdr tab ID.
function recheck_after_pr() {
    local tab_id="$1" tab_json tab_matches workspace_id focused declared_count pane_rows pane_count unique_pane_count tab_agent_count
    local pane_id pane_terminal pane_cwd foreground_cwd check_path root git_dir common_dir canonical_git canonical_common candidate_root
    local agent_matches agent_json agent_name agent_terminal agent_status record_count input_text input_state
    RECHECK_EVIDENCE=''

    TABS_JSON="$(herdr tab list 2> /dev/null)" || {
        RECHECK_EVIDENCE='tab inventory refresh failed after pull-request lookup'
        return 1
    }
    PANES_JSON="$(herdr pane list 2> /dev/null)" || {
        RECHECK_EVIDENCE='pane inventory refresh failed after pull-request lookup'
        return 1
    }
    AGENTS_JSON="$(herdr agent list 2> /dev/null)" || {
        RECHECK_EVIDENCE='agent lifecycle refresh failed after pull-request lookup'
        return 1
    }
    printf '%s\n' "$TABS_JSON" | jq -e '.result.tabs | type == "array"' > /dev/null 2>&1 || {
        RECHECK_EVIDENCE='tab inventory is invalid after pull-request lookup'
        return 1
    }
    printf '%s\n' "$PANES_JSON" | jq -e '.result.panes | type == "array"' > /dev/null 2>&1 || {
        RECHECK_EVIDENCE='pane inventory is invalid after pull-request lookup'
        return 1
    }
    printf '%s\n' "$AGENTS_JSON" | jq -e '.result.agents | type == "array"' > /dev/null 2>&1 || {
        RECHECK_EVIDENCE='agent inventory is invalid after pull-request lookup'
        return 1
    }
    identify_caller || {
        RECHECK_EVIDENCE='caller identity could not be rechecked'
        return 1
    }
    inspect_dispatch_records
    [ "$RECORDS_STATE" = 'valid' ] || {
        RECHECK_EVIDENCE='caller dispatch record is unreadable or malformed'
        return 1
    }
    tab_matches="$(printf '%s\n' "$TABS_JSON" | jq -r --arg tab "$tab_id" '[.result.tabs[] | select(.tab_id == $tab)] | length')"
    [ "$tab_matches" = '1' ] || {
        RECHECK_EVIDENCE='tab identity is missing or duplicated after pull-request lookup'
        return 1
    }
    tab_json="$(printf '%s\n' "$TABS_JSON" | jq -c --arg tab "$tab_id" '[.result.tabs[] | select(.tab_id == $tab)][0]')"
    if printf '%s\n' "$tab_json" | jq -e '(.label | type == "string") and (.label | startswith("⛔"))' > /dev/null 2>&1; then
        RECHECK_EVIDENCE='tab label starts with ⛔'
        return 1
    fi
    workspace_id="$(printf '%s\n' "$tab_json" | jq -r '.workspace_id // empty')"
    focused="$(printf '%s\n' "$tab_json" | jq -r 'if .focused == true then "true" elif .focused == false then "false" else "unknown" end')"
    declared_count="$(printf '%s\n' "$tab_json" | jq -r 'if (.pane_count | type) == "number" then .pane_count else "unknown" end')"
    [ "$tab_id" != "$HERDR_TAB_ID" ] && [ "$tab_id" != "$CALLER_TAB" ] || {
        RECHECK_EVIDENCE='caller tab is protected'
        return 1
    }
    [ "$focused" = 'false' ] || {
        RECHECK_EVIDENCE='tab is focused or its focus state is unknown'
        return 1
    }
    [ -n "$workspace_id" ] || {
        RECHECK_EVIDENCE='workspace ownership is unknown'
        return 1
    }
    pane_rows="$(printf '%s\n' "$PANES_JSON" | jq -r --arg tab "$tab_id" '[.result.panes[] | select(.tab_id == $tab)] | .[] | [.pane_id, (.terminal_id // ""), (.cwd // ""), (.foreground_cwd // "")] | @tsv')"
    pane_count="$(printf '%s\n' "$PANES_JSON" | jq -r --arg tab "$tab_id" '[.result.panes[] | select(.tab_id == $tab)] | length')"
    unique_pane_count="$(printf '%s\n' "$PANES_JSON" | jq -r --arg tab "$tab_id" '[.result.panes[] | select(.tab_id == $tab) | .pane_id | select(type == "string" and length > 0)] | unique | length')"
    tab_agent_count="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg tab "$tab_id" '[.result.agents[] | select(.tab_id == $tab)] | length')"
    [ "$declared_count" != 'unknown' ] && [ "$pane_count" -gt 0 ] && [ "$pane_count" = "$declared_count" ] && [ "$pane_count" = "$unique_pane_count" ] || {
        RECHECK_EVIDENCE='pane inventory is empty, unknown, or inconsistent'
        return 1
    }
    [ "$tab_agent_count" -le "$pane_count" ] || {
        RECHECK_EVIDENCE='agent inventory has extra agents not represented by panes'
        return 1
    }

    candidate_root=''
    while IFS="$(printf '\t')" read -r pane_id pane_terminal pane_cwd foreground_cwd; do
        [ -n "$pane_id" ] || {
            RECHECK_EVIDENCE='pane inventory contains an unnamed pane'
            return 1
        }
        agent_matches="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg pane "$pane_id" --arg tab "$tab_id" '[.result.agents[] | select(.pane_id == $pane and .tab_id == $tab)] | length')"
        [ "$agent_matches" = '1' ] || {
            RECHECK_EVIDENCE="pane ${pane_id} has no unique live agent"
            return 1
        }
        agent_json="$(printf '%s\n' "$AGENTS_JSON" | jq -c --arg pane "$pane_id" --arg tab "$tab_id" '[.result.agents[] | select(.pane_id == $pane and .tab_id == $tab)][0]')"
        agent_name="$(printf '%s\n' "$agent_json" | jq -r '.name // empty')"
        agent_terminal="$(printf '%s\n' "$agent_json" | jq -r '.terminal_id // empty')"
        agent_status="$(printf '%s\n' "$agent_json" | jq -r '.agent_status // empty')"
        record_count="$(dispatch_record_count "$CALLER_NAME" "$CALLER_TERMINAL" "$agent_name" "$agent_terminal" "$tab_id" "$pane_id")"
        [ -n "$agent_name" ] && [ -n "$pane_terminal" ] && [ "$agent_terminal" = "$pane_terminal" ] && [ "$record_count" = '1' ] || {
            RECHECK_EVIDENCE="pane ${pane_id} no longer matches a caller dispatch record"
            return 1
        }
        [ "$(printf '%s\n' "$agent_json" | jq -r '.tab_id // empty')" = "$tab_id" ] || {
            RECHECK_EVIDENCE="pane ${pane_id} agent moved to another tab"
            return 1
        }
        case "$agent_status" in
        done | exited) ;;
        *)
            RECHECK_EVIDENCE="pane ${pane_id} agent is ${agent_status:-unknown}, not done or exited"
            return 1
            ;;
        esac
        [ -n "$foreground_cwd" ] || foreground_cwd="$pane_cwd"
        [ -n "$pane_cwd" ] && [ -n "$foreground_cwd" ] || {
            RECHECK_EVIDENCE="pane ${pane_id} worktree path is unknown"
            return 1
        }
        for check_path in "$pane_cwd" "$foreground_cwd"; do
            [ -d "$check_path" ] || {
                RECHECK_EVIDENCE="pane ${pane_id} worktree path is missing"
                return 1
            }
            root="$(git -C "$check_path" rev-parse --show-toplevel 2> /dev/null)" || {
                RECHECK_EVIDENCE="pane ${pane_id} is not in a provable Git worktree"
                return 1
            }
            git_dir="$(git -C "$check_path" rev-parse --git-dir 2> /dev/null)" || {
                RECHECK_EVIDENCE="pane ${pane_id} Git directory is unknown"
                return 1
            }
            common_dir="$(git -C "$check_path" rev-parse --git-common-dir 2> /dev/null)" || {
                RECHECK_EVIDENCE="pane ${pane_id} common Git directory is unknown"
                return 1
            }
            canonical_git="$(canonical_git_path "$check_path" "$git_dir")" || {
                RECHECK_EVIDENCE="pane ${pane_id} Git directory cannot be resolved"
                return 1
            }
            canonical_common="$(canonical_git_path "$check_path" "$common_dir")" || {
                RECHECK_EVIDENCE="pane ${pane_id} common Git directory cannot be resolved"
                return 1
            }
            [ "$canonical_git" != "$canonical_common" ] || {
                RECHECK_EVIDENCE="pane ${pane_id} is in a primary checkout"
                return 1
            }
            if [ -z "$candidate_root" ]; then
                candidate_root="$root"
            elif [ "$candidate_root" != "$root" ]; then
                RECHECK_EVIDENCE='tab panes now use different worktrees'
                return 1
            fi
        done
        input_text="$(herdr pane read "$pane_id" --source visible --format ansi 2> /dev/null)" || {
            RECHECK_EVIDENCE="pane ${pane_id} visible input could not be reread"
            return 1
        }
        input_state="$(printf '%s\n' "$input_text" | LC_ALL=C awk -f "$INPUT_STATE_AWK")"
        [ "$input_state" = 'empty' ] || {
            RECHECK_EVIDENCE="pane ${pane_id} visible input is ${input_state}"
            return 1
        }
    done << EOF
$pane_rows
EOF
    return 0
}

load_inventory || fail "could not read valid local Herdr tab, pane, and agent inventories"
identify_caller || true
inspect_dispatch_records
if [ -n "$RECORD_WORKER" ]; then
    record_worker_dispatch
    exit 0
fi

if [ "${#RESULTS_COLLECTED_TABS[@]}" -gt 0 ]; then
    for selected_tab in "${RESULTS_COLLECTED_TABS[@]}"; do
        selected_count="$(printf '%s\n' "$TABS_JSON" | jq -r --arg tab "$selected_tab" '[.result.tabs[] | select(.tab_id == $tab)] | length')"
        [ "$selected_count" = '1' ] || fail "selected tab ID is missing or duplicated: ${selected_tab}" 2
    done
fi

TAB_IDS=()
TAB_WORKSPACES=()
TAB_LABELS=()
TAB_VERDICTS=()
TAB_EVIDENCE=()
tab_index=0

while IFS= read -r tab_id; do
    [ -n "$tab_id" ] || continue
    tab_json="$(printf '%s\n' "$TABS_JSON" | jq -c --arg tab "$tab_id" '[.result.tabs[] | select(.tab_id == $tab)][0]')"
    TAB_IDS[tab_index]="$tab_id"
    TAB_WORKSPACES[tab_index]="$(printf '%s\n' "$tab_json" | jq -r '.workspace_id // empty')"
    TAB_LABELS[tab_index]="$(printf '%s\n' "$tab_json" | jq -r '(.label // "") | @json')"
    classification="$(classify_tab "$tab_id")"
    IFS="$(printf '\t')" read -r tab_verdict tab_evidence << EOF
$classification
EOF
    if [ "$APPLY" -eq 1 ] && [ "$tab_verdict" = 'close' ] && ! tab_was_selected "$tab_id"; then
        tab_verdict='keep'
        tab_evidence='tab was not explicitly named with --results-collected'
    fi
    TAB_VERDICTS[tab_index]="$tab_verdict"
    TAB_EVIDENCE[tab_index]="$tab_evidence"
    tab_index=$((tab_index + 1))
done << EOF
$(printf '%s\n' "$TABS_JSON" | jq -r '.result.tabs[] | .tab_id')
EOF

# Reserve one tab in each workspace and report the same plan used by apply mode.
i=0
while [ "$i" -lt "$tab_index" ]; do
    if [ "${TAB_VERDICTS[i]}" = "close" ]; then
        workspace="${TAB_WORKSPACES[i]}"
        workspace_count="$(workspace_tab_count "$workspace")"
        earlier_closes=0
        j=0
        while [ "$j" -lt "$i" ]; do
            if [ "${TAB_WORKSPACES[j]}" = "$workspace" ] && [ "${TAB_VERDICTS[j]}" = "close" ]; then
                earlier_closes=$((earlier_closes + 1))
            fi
            j=$((j + 1))
        done
        if [ $((workspace_count - earlier_closes)) -le 1 ]; then
            TAB_VERDICTS[i]="keep"
            TAB_EVIDENCE[i]="workspace must retain one tab"
        fi
    fi
    printf 'tab=%s label=%s verdict=%s evidence=%s\n' \
        "${TAB_IDS[i]}" "${TAB_LABELS[i]}" "${TAB_VERDICTS[i]}" "${TAB_EVIDENCE[i]}"
    i=$((i + 1))
done

[ "$APPLY" -eq 1 ] || exit 0

i=0
while [ "$i" -lt "$tab_index" ]; do
    if [ "${TAB_VERDICTS[i]}" = "close" ]; then
        tab_id="${TAB_IDS[i]}"
        load_inventory || fail "inventory refresh failed before closing tab ${tab_id}"
        identify_caller || true
        inspect_dispatch_records
        classification="$(classify_tab "$tab_id")"
        IFS="$(printf '\t')" read -r current_verdict current_evidence << EOF
$classification
EOF
        if [ "$current_verdict" = 'close' ] && tab_was_selected "$tab_id"; then
            if ! recheck_after_pr "$tab_id"; then
                current_verdict='keep'
                current_evidence="$RECHECK_EVIDENCE"
            fi
        elif [ "$current_verdict" = 'close' ]; then
            current_verdict='keep'
            current_evidence='tab was not explicitly named with --results-collected'
        fi
        current_count="$(printf '%s\n' "$TABS_JSON" | jq -r --arg tab "$tab_id" '[.result.tabs[] | select(.tab_id == $tab)] | length')"
        current_workspace="$(printf '%s\n' "$TABS_JSON" | jq -r --arg tab "$tab_id" '[.result.tabs[] | select(.tab_id == $tab)][0].workspace_id // empty')"
        if [ "$current_verdict" != "close" ]; then
            printf 'apply=skipped tab=%s evidence=%s\n' "$tab_id" "$current_evidence"
        elif [ "$current_count" != "1" ] || [ -z "$current_workspace" ]; then
            printf 'apply=skipped tab=%s evidence=tab or workspace is missing\n' "$tab_id"
        elif [ "$(workspace_tab_count "$current_workspace")" -le 1 ]; then
            printf 'apply=skipped tab=%s evidence=workspace must retain one tab\n' "$tab_id"
        elif herdr tab close "$tab_id" > /dev/null 2>&1; then
            printf 'apply=closed tab=%s evidence=%s\n' "$tab_id" "$current_evidence"
        else
            printf 'apply=failed tab=%s evidence=Herdr tab close failed\n' "$tab_id" >&2
            exit 1
        fi
    fi
    i=$((i + 1))
done
