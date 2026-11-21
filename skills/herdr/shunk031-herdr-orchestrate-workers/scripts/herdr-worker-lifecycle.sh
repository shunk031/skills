#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-worker-lifecycle.sh
# @brief Launch, collect, and audit Herdr workers owned by the calling orchestrator.
# @description
#   Ordinary launches can reuse an explicit root pane; implementation launches create a fresh tab with a size-gate ID.
#   Collect closes only a recorded, explicitly collected worker whose agent is settled.
#   Audit is read-only.
# @option launch NAME --kind KIND (--workspace ID | --new-workspace) --cwd PATH --label TEXT --task TASK [--role implementation --line-budget LINES] [--root-pane PANE] [--env KEY=VALUE ...] -- ARGS Launch and record the worker.
# @option collect NAME Mark one recorded worker collected and close its pane or owned workspace if safe.
# @option audit List unrecorded live agent panes as warnings without closing anything.
# @option --help Show usage.
# @example
#   scripts/herdr-worker-lifecycle.sh launch meta-reader --kind codex --workspace w1 --cwd /repo --label "🚧 Read PR" --task pr-review -- -m gpt-6-luna
#   scripts/herdr-worker-lifecycle.sh collect meta-reader
#   scripts/herdr-worker-lifecycle.sh audit

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
INPUT_STATE_AWK="${SCRIPT_DIR}/herdr-visible-input-state.awk"
COMMAND_NAME="${1:-audit}"
[ "$#" -eq 0 ] || shift

if [ -n "${HERDR_WORKER_LIFECYCLE_STATE_DIR:-}" ]; then
    STATE_DIR="$HERDR_WORKER_LIFECYCLE_STATE_DIR"
elif [ -n "${XDG_STATE_HOME:-}" ]; then
    STATE_DIR="${XDG_STATE_HOME}/herdr-worker-lifecycle"
elif [ -n "${HOME:-}" ]; then
    STATE_DIR="${HOME}/.local/state/herdr-worker-lifecycle"
else
    STATE_DIR=''
fi
RECORDS_FILE=''
LOCK_DIR=''
if [ -n "$STATE_DIR" ]; then
    RECORDS_FILE="${STATE_DIR}/workers.tsv"
    LOCK_DIR="${STATE_DIR}/.workers.lock"
fi

function usage() {
    cat << 'USAGE'
Usage:
  herdr-worker-lifecycle.sh launch <name> --kind <kind> (--workspace <workspace-id> | --new-workspace) --cwd <path> --label <label> --task <task-key> [--role implementation --line-budget <lines>] [--root-pane <pane-id>] [--env KEY=VALUE ...] -- <agent-args...>
  herdr-worker-lifecycle.sh collect <name>
  herdr-worker-lifecycle.sh audit

--new-workspace creates and records an owned workspace; --workspace reuses one without
ownership. Collection closes owned workspaces only when the exact launch record matches
and the collected worker is the sole pane; otherwise it reports why and leaves it open.
audit is read-only and warns about unrecorded live panes. It never closes a pane.
Merged PR worktree cleanup stays separate.
USAGE
}

function fail() {
    printf 'herdr worker lifecycle: %s\n' "$1" >&2
    exit "${2:-1}"
}

if [ "$COMMAND_NAME" = '--help' ] || [ "$COMMAND_NAME" = 'help' ]; then
    usage
    exit 0
fi
case "$COMMAND_NAME" in
launch | collect | audit) ;;
*)
    usage >&2
    fail "unknown command: $COMMAND_NAME" 2
    ;;
esac

if [ "${HERDR_ENV:-}" != '1' ]; then
    fail 'HERDR_ENV=1 is required; this helper targets the local Herdr session'
fi
if [ -z "${HERDR_PANE_ID:-}" ] || [ -z "${HERDR_TAB_ID:-}" ]; then
    fail 'HERDR_PANE_ID and HERDR_TAB_ID are required to identify the caller'
fi
command -v jq > /dev/null 2>&1 || fail 'jq is required'
[ -r "$INPUT_STATE_AWK" ] || fail "visible-input parser is missing: $INPUT_STATE_AWK"
[ -n "$RECORDS_FILE" ] || fail 'XDG_STATE_HOME or HOME is required for worker records'

TABS_JSON=''
PANES_JSON=''
AGENTS_JSON=''
CALLER_NAME=''
CALLER_TERMINAL=''
WORKER_NAME=''
WORKER_KIND=''
WORKER_WORKSPACE=''
WORKER_NEW_WORKSPACE=0
WORKER_CWD=''
WORKER_LABEL=''
WORKER_TAB=''
WORKER_PANE=''
WORKER_TASK=''
WORKER_ROLE=''
WORKER_LINE_BUDGET=''
WORKER_LAUNCH_MODE='tab'
WORKER_ROOT_PANE=''
WORKER_SIZE_GATE_LAUNCH_ID=''
WORKER_ARGS=()
WORKER_ENV=()
WORKER_ENV_COUNT=0
TAB_SAFETY_REASON=''
RECORD_STATE='missing'
LOCK_HELD=0

function load_inventory() {
    TABS_JSON="$(herdr tab list 2> /dev/null)" || return 1
    PANES_JSON="$(herdr pane list 2> /dev/null)" || return 1
    AGENTS_JSON="$(herdr agent list 2> /dev/null)" || return 1
    printf '%s\n' "$TABS_JSON" | jq -e '.result.tabs | type == "array"' > /dev/null 2>&1 || return 1
    printf '%s\n' "$PANES_JSON" | jq -e '.result.panes | type == "array"' > /dev/null 2>&1 || return 1
    printf '%s\n' "$AGENTS_JSON" | jq -e '.result.agents | type == "array"' > /dev/null 2>&1 || return 1
}

# @description Confirm an owned workspace contains exactly the recorded worker pane.
function owned_workspace_has_only_worker_pane() {
    local workspace="$1" tab="$2" pane="$3" terminal="$4" tab_ids pane_count worker_count
    tab_ids="$(printf '%s\n' "$TABS_JSON" | jq -ce --arg ws "$workspace" --argjson panes "$PANES_JSON" 'if all(.result.tabs[]; . as $tab | ($tab | type == "object") and ($tab.workspace_id | type == "string" and length > 0)) and all(.result.tabs[] | select(.workspace_id == $ws); . as $tab | ($tab.pane_count | type == "number" and . >= 0 and floor == .) and ([$panes.result.panes[] | select(.tab_id == $tab.tab_id)] | length == $tab.pane_count)) then [.result.tabs[] | select(.workspace_id == $ws) | .tab_id] else empty end')" || return 1
    printf '%s\n' "$tab_ids" | jq -e 'length > 0 and all(.[]; type == "string" and length > 0) and length == (unique | length)' > /dev/null || return 1
    printf '%s\n' "$PANES_JSON" | jq -e --argjson tabs "$TABS_JSON" '.result.panes | all(.[]; . as $p | ($p | type == "object") and ($p.pane_id | type == "string" and length > 0) and ($p.tab_id | type == "string" and length > 0) and ($p.terminal_id | type == "string" and length > 0) and ([$tabs.result.tabs[] | select(.tab_id == $p.tab_id)] | length == 1))' > /dev/null || return 1
    pane_count="$(jq -nr --argjson panes "$PANES_JSON" --argjson tabs "$tab_ids" '[ $panes.result.panes[] | select(.tab_id as $id | $tabs | index($id)) ] | length')"
    worker_count="$(jq -nr --argjson panes "$PANES_JSON" --argjson tabs "$tab_ids" --arg tab "$tab" --arg pane "$pane" --arg terminal "$terminal" '[ $panes.result.panes[] | select(.tab_id as $id | $tabs | index($id)) | select(.pane_id == $pane and .tab_id == $tab and .terminal_id == $terminal) ] | length')"
    [ "$pane_count" = '1' ] && [ "$worker_count" = '1' ]
}

# @description Identify the caller from the inherited Herdr pane and terminal IDs.
function identify_caller() {
    local agent_json pane_json agent_count pane_count
    agent_count="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg pane "$HERDR_PANE_ID" --arg tab "$HERDR_TAB_ID" '[.result.agents[] | select(.pane_id == $pane and .tab_id == $tab)] | length')"
    pane_count="$(printf '%s\n' "$PANES_JSON" | jq -r --arg pane "$HERDR_PANE_ID" --arg tab "$HERDR_TAB_ID" '[.result.panes[] | select(.pane_id == $pane and .tab_id == $tab)] | length')"
    [ "$agent_count" = '1' ] && [ "$pane_count" = '1' ] || return 1
    agent_json="$(printf '%s\n' "$AGENTS_JSON" | jq -c --arg pane "$HERDR_PANE_ID" --arg tab "$HERDR_TAB_ID" '[.result.agents[] | select(.pane_id == $pane and .tab_id == $tab)][0]')"
    pane_json="$(printf '%s\n' "$PANES_JSON" | jq -c --arg pane "$HERDR_PANE_ID" --arg tab "$HERDR_TAB_ID" '[.result.panes[] | select(.pane_id == $pane and .tab_id == $tab)][0]')"
    CALLER_NAME="$(printf '%s\n' "$agent_json" | jq -r '.name // empty')"
    CALLER_TERMINAL="$(printf '%s\n' "$agent_json" | jq -r '.terminal_id // empty')"
    [ -n "$CALLER_NAME" ] && [ -n "$CALLER_TERMINAL" ] && [ "$CALLER_TERMINAL" = "$(printf '%s\n' "$pane_json" | jq -r '.terminal_id // empty')" ]
}

# @description Apply the tab safety checks shared by explicit root launches and collection.
function check_collectable_tab() {
    local tab_json="$1" tab_label focused
    TAB_SAFETY_REASON=''
    tab_label="$(printf '%s\n' "$tab_json" | jq -r '.label // ""')"
    case "$tab_label" in
    ⛔*)
        TAB_SAFETY_REASON='label starts with ⛔'
        return 1
        ;;
    esac
    focused="$(printf '%s\n' "$tab_json" | jq -r 'if .focused == true then "true" elif .focused == false then "false" else "unknown" end')"
    if [ "$focused" != 'false' ]; then
        TAB_SAFETY_REASON='is focused or its focus state is unknown'
        return 1
    fi
}

# @description Validate the private worker registry before using it.
function inspect_records() {
    if [ -z "$RECORDS_FILE" ] || [ -L "$RECORDS_FILE" ] || [ ! -e "$RECORDS_FILE" ]; then
        RECORD_STATE='missing'
        return 0
    fi
    if [ ! -f "$RECORDS_FILE" ] || [ ! -r "$RECORDS_FILE" ]; then
        RECORD_STATE='invalid'
        return 0
    fi
    if awk -F '\t' '(NF != 9 && NF != 10) || $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" || $6 == "" || $7 == "" || $8 == "" || ($9 != "started" && $9 != "collected") || (NF == 10 && $10 != "tab" && $10 != "root" && $10 !~ /^owned:[^[:space:]]+$/) { bad = 1 } END { exit bad ? 1 : 0 }' "$RECORDS_FILE"; then
        RECORD_STATE='valid'
    else
        RECORD_STATE='invalid'
    fi
}

# @description Acquire the lock used to update worker ownership and collection records.
function acquire_lock() {
    local attempt
    case "$STATE_DIR" in
    /*) ;;
    *) return 1 ;;
    esac
    [ ! -L "$STATE_DIR" ] || return 1
    mkdir -p "$STATE_DIR" 2> /dev/null || return 1
    [ ! -L "$STATE_DIR" ] || return 1
    chmod 700 "$STATE_DIR" 2> /dev/null || return 1
    attempt=0
    while [ "$attempt" -lt 10 ]; do
        if mkdir "$LOCK_DIR" 2> /dev/null; then
            LOCK_HELD=1
            trap 'release_lock' EXIT
            trap 'exit 130' INT
            trap 'exit 143' TERM
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
}

# @description Release the worker-record lock.
function release_lock() {
    if [ "$LOCK_HELD" -eq 1 ]; then
        rmdir "$LOCK_DIR" 2> /dev/null || true
        LOCK_HELD=0
    fi
}

# @description Validate task keys stored as one field in the worker registry.
# @arg $1 task_key One-line task identifier.
function valid_task_key() {
    case "$1" in
    '' | *[!A-Za-z0-9._-]* | [!A-Za-z0-9]*) return 1 ;;
    *) return 0 ;;
    esac
}

# @description Verify that an implementation launch targets an open Herdr workspace for a linked Git worktree.
function validate_implementation_worktree() {
    local worker_cwd repo_root git_dir common_dir git_worktrees herdr_worktrees
    local advice
    advice='herdr worktree create --cwd <repo> --branch <topic> --base origin/<default> --no-focus, or herdr worktree open for an existing worktree'
    [ "$WORKER_NEW_WORKSPACE" -eq 0 ] || fail "implementation launches cannot use --new-workspace; use $advice"
    [ -n "$WORKER_WORKSPACE" ] || fail "implementation launches require a Herdr worktree workspace; use $advice"
    repo_root="$(git -C "$WORKER_CWD" rev-parse --show-toplevel 2> /dev/null)" || fail "could not verify implementation --cwd as a linked Git worktree; use $advice"
    repo_root="$(cd "$repo_root" 2> /dev/null && pwd -P)" || fail "could not resolve implementation worktree path; use $advice"
    git_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-dir 2> /dev/null)" || fail "could not inspect implementation Git directory; use $advice"
    common_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir 2> /dev/null)" || fail "could not inspect implementation Git common directory; use $advice"
    git_dir="$(cd "$git_dir" 2> /dev/null && pwd -P)" || fail "could not resolve implementation Git directory; use $advice"
    common_dir="$(cd "$common_dir" 2> /dev/null && pwd -P)" || fail "could not resolve implementation Git common directory; use $advice"
    [ "$git_dir" != "$common_dir" ] || fail "implementation --cwd is the main working tree; use $advice"
    worker_cwd="$(cd "$WORKER_CWD" 2> /dev/null && pwd -P)" || fail "could not resolve implementation --cwd; use $advice"
    [ "$worker_cwd" = "$repo_root" ] || fail "implementation --cwd must be the linked Git worktree root; use $advice"
    git_worktrees="$(git -C "$repo_root" worktree list --porcelain 2> /dev/null)" || fail "could not verify implementation Git worktree membership; use $advice"
    if ! printf '%s\n' "$git_worktrees" | awk -v expected="$repo_root" '
        function finish_stanza() {
            if (!in_stanza) return
            if (!have_path || !have_head) malformed = 1
            if (path == expected) {
                matches++
                if (prunable) matching_prunable = 1
            }
            in_stanza = 0
            path = ""
            have_path = have_head = have_branch = have_bare = have_detached = have_locked = prunable = 0
        }
        $0 == "" {
            finish_stanza()
            next
        }
        substr($0, 1, 9) == "worktree " {
            finish_stanza()
            in_stanza = 1
            path = substr($0, 10)
            if (path == "") malformed = 1
            have_path = 1
            next
        }
        {
            if (!in_stanza) {
                malformed = 1
                next
            }
            if (substr($0, 1, 5) == "HEAD ") {
                value = substr($0, 6)
                if (have_head || value == "" || value ~ /[[:space:]]/) malformed = 1
                have_head = 1
                next
            }
            if (substr($0, 1, 7) == "branch ") {
                value = substr($0, 8)
                if (have_branch || value == "" || value ~ /[[:space:]]/) malformed = 1
                have_branch = 1
                next
            }
            if ($0 == "bare") {
                if (have_bare) malformed = 1
                have_bare = 1
                next
            }
            if ($0 == "detached") {
                if (have_detached) malformed = 1
                have_detached = 1
                next
            }
            if ($0 == "locked" || substr($0, 1, 7) == "locked ") {
                if (have_locked || ($0 != "locked" && substr($0, 8) == "")) malformed = 1
                have_locked = 1
                next
            }
            if ($0 == "prunable" || substr($0, 1, 9) == "prunable ") {
                if (prunable || ($0 != "prunable" && substr($0, 10) == "")) malformed = 1
                prunable = 1
                next
            }
            malformed = 1
        }
        END {
            finish_stanza()
            exit malformed || matches != 1 || matching_prunable
        }
    '; then
        fail "implementation --cwd is not a uniquely verified current linked Git worktree; use $advice"
    fi
    herdr_worktrees="$(herdr worktree list --cwd "$repo_root" --json 2> /dev/null)" || fail "could not verify the Herdr worktree workspace; use $advice"
    printf '%s\n' "$herdr_worktrees" | jq -e '.result.type == "worktree_list" and (.result.worktrees | type == "array")' > /dev/null 2>&1 || fail "Herdr returned an invalid worktree list; use $advice"
    if ! printf '%s\n' "$herdr_worktrees" | jq -e --arg path "$repo_root" --arg workspace "$WORKER_WORKSPACE" '[.result.worktrees[] | select(.path == $path and .is_linked_worktree == true and .is_prunable == false and .open_workspace_id == $workspace)] | length == 1' > /dev/null 2>&1; then
        fail "--workspace is not the open Herdr worktree workspace for $repo_root; use $advice"
    fi
}

# @description Persist the exact caller and worker identities after a successful launch.
function record_launch() {
    local matches worker_json worker_terminal worker_tab existing conflicting
    [ "$RECORD_STATE" = 'missing' ] || [ "$RECORD_STATE" = 'valid' ] || fail 'worker registry is malformed or unreadable'
    matches="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg name "$WORKER_NAME" '[.result.agents[] | select(.name == $name)] | length')"
    [ "$matches" = '1' ] || fail 'launched worker is not uniquely present in the live agent inventory'
    worker_json="$(printf '%s\n' "$AGENTS_JSON" | jq -c --arg name "$WORKER_NAME" '[.result.agents[] | select(.name == $name)][0]')"
    worker_terminal="$(printf '%s\n' "$worker_json" | jq -r '.terminal_id // empty')"
    worker_tab="$(printf '%s\n' "$worker_json" | jq -r '.tab_id // empty')"
    [ "$(printf '%s\n' "$worker_json" | jq -r '.pane_id // empty')" = "$WORKER_PANE" ] || fail 'launched worker is not in the requested pane'
    [ "$worker_tab" = "$WORKER_TAB" ] || fail 'launched worker is not in the requested worker tab'
    [ -n "$worker_terminal" ] && [ -n "$worker_tab" ] || fail 'worker terminal or tab identity is unknown'
    [ "$WORKER_PANE" != "$HERDR_PANE_ID" ] && [ "$worker_tab" != "$HERDR_TAB_ID" ] || fail 'worker cannot use the caller pane or tab'
    acquire_lock || fail 'could not acquire the worker-record lock'
    inspect_records
    [ "$RECORD_STATE" = 'missing' ] || [ "$RECORD_STATE" = 'valid' ] || fail 'worker registry is malformed or unreadable'
    existing=0
    conflicting=0
    if [ -e "$RECORDS_FILE" ]; then
        existing="$(awk -F '\t' -v owner="$CALLER_NAME" -v owner_pane="$HERDR_PANE_ID" -v owner_terminal="$CALLER_TERMINAL" -v task="$WORKER_TASK" -v worker="$WORKER_NAME" -v terminal="$worker_terminal" -v tab="$worker_tab" -v pane="$WORKER_PANE" '$1 == owner && $2 == owner_pane && $3 == owner_terminal && $4 == task && $5 == worker && $6 == terminal && $7 == tab && $8 == pane { count++ } END { print count + 0 }' "$RECORDS_FILE")"
        conflicting="$(awk -F '\t' -v terminal="$worker_terminal" -v tab="$worker_tab" -v pane="$WORKER_PANE" -v owner="$CALLER_NAME" -v owner_pane="$HERDR_PANE_ID" -v owner_terminal="$CALLER_TERMINAL" -v task="$WORKER_TASK" -v worker="$WORKER_NAME" '$6 == terminal && $7 == tab && $8 == pane && !($1 == owner && $2 == owner_pane && $3 == owner_terminal && $4 == task && $5 == worker) { count++ } END { print count + 0 }' "$RECORDS_FILE")"
    fi
    [ "$conflicting" -eq 0 ] || fail 'worker pane is already registered to another owner or task'
    [ "$existing" -le 1 ] || fail 'worker launch record is duplicated'
    if [ "$existing" -eq 0 ]; then
        (umask 077 && : >> "$RECORDS_FILE") || fail 'cannot create worker registry'
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tstarted\t%s\n' "$CALLER_NAME" "$HERDR_PANE_ID" "$CALLER_TERMINAL" "$WORKER_TASK" "$WORKER_NAME" "$worker_terminal" "$worker_tab" "$WORKER_PANE" "$WORKER_LAUNCH_MODE" >> "$RECORDS_FILE" || fail 'cannot append worker registry'
    fi
    chmod 600 "$RECORDS_FILE" 2> /dev/null || fail 'cannot secure worker registry'
    release_lock
    trap - EXIT INT TERM
    printf 'recorded owner=%s owner-pane=%s task=%s worker=%s tab=%s pane=%s\n' "$CALLER_NAME" "$HERDR_PANE_ID" "$WORKER_TASK" "$WORKER_NAME" "$worker_tab" "$WORKER_PANE"
}

# @description Parse the launch form and start a worker through this recorder.
function launch_worker() {
    local start_status tab_create_json created_tab created_pane created_terminal caller_tab caller_workspace before_tabs before_panes env_assignment root_pane_json root_tab_json size_gate_result
    local -a tab_create_args
    tab_create_args=()
    [ "$#" -ge 1 ] || fail 'launch requires a worker name' 2
    WORKER_NAME="$1"
    shift
    printf '%s\n' "$WORKER_NAME" | grep -Eq '^[a-z][a-z0-9_-]{0,31}$' || fail 'worker name is invalid' 2
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --kind)
            [ "$#" -ge 2 ] || fail '--kind requires a value' 2
            WORKER_KIND="$2"
            shift 2
            ;;
        --workspace)
            [ "$#" -ge 2 ] || fail '--workspace requires a value' 2
            WORKER_WORKSPACE="$2"
            shift 2
            ;;
        --new-workspace)
            WORKER_NEW_WORKSPACE=1
            shift
            ;;
        --cwd)
            [ "$#" -ge 2 ] || fail '--cwd requires a value' 2
            WORKER_CWD="$2"
            shift 2
            ;;
        --label)
            [ "$#" -ge 2 ] || fail '--label requires a value' 2
            WORKER_LABEL="$2"
            shift 2
            ;;
        --task)
            [ "$#" -ge 2 ] || fail '--task requires a value' 2
            WORKER_TASK="$2"
            shift 2
            ;;
        --role)
            [ "$#" -ge 2 ] || fail '--role requires a value' 2
            WORKER_ROLE="$2"
            shift 2
            ;;
        --line-budget)
            [ "$#" -ge 2 ] || fail '--line-budget requires a value' 2
            WORKER_LINE_BUDGET="$2"
            shift 2
            ;;
        --root-pane)
            [ "$#" -ge 2 ] && [ -n "$2" ] || fail '--root-pane requires a pane ID' 2
            WORKER_ROOT_PANE="$2"
            shift 2
            ;;
        --env)
            [ "$#" -ge 2 ] || fail '--env requires KEY=VALUE' 2
            WORKER_ENV["$WORKER_ENV_COUNT"]="$2"
            WORKER_ENV_COUNT=$((WORKER_ENV_COUNT + 1))
            shift 2
            ;;
        --)
            shift
            WORKER_ARGS=("$@")
            break
            ;;
        *) fail "unknown launch option: $1" 2 ;;
        esac
    done
    [ -n "$WORKER_KIND" ] && [ -n "$WORKER_CWD" ] && [ -n "$WORKER_LABEL" ] && [ -n "$WORKER_TASK" ] || fail 'launch requires --kind, --cwd, --label, and --task' 2
    if [ "$WORKER_NEW_WORKSPACE" -eq 1 ]; then
        [ -z "$WORKER_WORKSPACE" ] && [ -z "$WORKER_ROOT_PANE" ] || fail '--new-workspace cannot be combined with --workspace or --root-pane' 2
    else
        [ -n "$WORKER_WORKSPACE" ] || fail 'launch requires --workspace or --new-workspace' 2
    fi
    if [ "$WORKER_ROLE" = 'implementation' ]; then
        [ -n "$WORKER_LINE_BUDGET" ] || fail 'implementation launches require --line-budget' 2
        if [ "$WORKER_ENV_COUNT" -gt 0 ]; then
            for env_assignment in "${WORKER_ENV[@]}"; do
                case "$env_assignment" in
                HERDR_WORKER_SIZE_GATE_LAUNCH_ID=*) fail 'the size-gate launch ID is managed by the lifecycle helper' 2 ;;
                esac
            done
        fi
        validate_implementation_worktree
    elif [ -n "$WORKER_LINE_BUDGET" ]; then
        fail '--line-budget requires --role implementation' 2
    fi
    case "$WORKER_LABEL" in ⛔*) fail 'worker tab label cannot start with ⛔' 2 ;; esac
    valid_task_key "$WORKER_TASK" || fail 'task key must use letters, digits, dot, underscore, or hyphen' 2
    [ "$#" -gt 0 ] || fail 'launch requires agent arguments after --' 2
    load_inventory || fail 'could not read local Herdr inventories'
    identify_caller || fail 'caller identity could not be proven'
    caller_tab="$(printf '%s\n' "$TABS_JSON" | jq -c --arg tab "$HERDR_TAB_ID" '[.result.tabs[] | select(.tab_id == $tab)][0]')"
    caller_workspace="$(printf '%s\n' "$caller_tab" | jq -r '.workspace_id // empty')"
    [ -n "$caller_workspace" ] || fail 'caller workspace could not be identified'
    if [ "$WORKER_NEW_WORKSPACE" -eq 0 ]; then
        [ "$WORKER_WORKSPACE" != "$caller_workspace" ] || fail 'worker tab cannot be created in the caller workspace'
        [ "$(printf '%s\n' "$TABS_JSON" | jq -r --arg workspace "$WORKER_WORKSPACE" '[.result.tabs[] | select(.workspace_id == $workspace)] | length')" -gt 0 ] || fail 'target workspace is not present in the local tab inventory'
    fi
    inspect_records
    [ "$RECORD_STATE" = 'missing' ] || [ "$RECORD_STATE" = 'valid' ] || fail 'worker registry is malformed or unreadable'
    [ "$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg name "$WORKER_NAME" '[.result.agents[] | select(.name == $name)] | length')" = '0' ] || fail 'worker name is already present in the local agent inventory'
    if [ "$WORKER_ROLE" = 'implementation' ]; then
        if size_gate_result="$(python3 "$SCRIPT_DIR/herdr-worker-size-gate.py" preflight --repo "$WORKER_CWD" --line-budget "$WORKER_LINE_BUDGET" --worker-name "$WORKER_NAME" --task-key "$WORKER_TASK" 2>&1)"; then
            :
        else
            fail "size-gate preflight failed; worker was not launched: $size_gate_result"
        fi
        WORKER_SIZE_GATE_LAUNCH_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')" || fail 'could not create a size-gate launch ID'
    fi
    WORKER_LAUNCH_MODE='tab'
    if [ "$WORKER_NEW_WORKSPACE" -eq 1 ]; then
        tab_create_args=(--cwd "$WORKER_CWD" --label "$WORKER_LABEL" --no-focus)
        if [ "$WORKER_ENV_COUNT" -gt 0 ]; then for env_assignment in "${WORKER_ENV[@]}"; do tab_create_args+=(--env "$env_assignment"); done; fi
        if [ "$WORKER_ROLE" = 'implementation' ]; then tab_create_args+=(--env "HERDR_WORKER_SIZE_GATE_LAUNCH_ID=$WORKER_SIZE_GATE_LAUNCH_ID"); fi
        workspace_create_json="$(herdr workspace create "${tab_create_args[@]}")" || fail 'Herdr could not create the owned worker workspace'
        WORKER_WORKSPACE="$(printf '%s\n' "$workspace_create_json" | jq -r '.result.workspace.workspace_id // empty')"
        WORKER_TAB="$(printf '%s\n' "$workspace_create_json" | jq -r '.result.tab.tab_id // empty')"
        WORKER_PANE="$(printf '%s\n' "$workspace_create_json" | jq -r '.result.root_pane.pane_id // empty')"
        created_terminal="$(printf '%s\n' "$workspace_create_json" | jq -r '.result.root_pane.terminal_id // empty')"
        [ -n "$WORKER_WORKSPACE" ] && [ -n "$WORKER_TAB" ] && [ -n "$WORKER_PANE" ] && [ -n "$created_terminal" ] || fail 'workspace creation response did not include exact IDs; workspace left open'
        WORKER_LAUNCH_MODE="owned:$WORKER_WORKSPACE"
        load_inventory || fail 'could not verify the new workspace; workspace left open'
        identify_caller || fail 'caller identity could not be reproven after workspace creation; workspace left open'
    elif [ -n "$WORKER_ROOT_PANE" ] && [ "$WORKER_ROLE" != 'implementation' ]; then
        [ "$WORKER_ENV_COUNT" -eq 0 ] || fail '--root-pane cannot be combined with --env'
        [ "$(printf '%s\n' "$PANES_JSON" | jq -r --arg pane "$WORKER_ROOT_PANE" '[.result.panes[] | select(.pane_id == $pane)] | length')" = '1' ] || fail 'requested root pane is missing or ambiguous'
        root_pane_json="$(printf '%s\n' "$PANES_JSON" | jq -c --arg pane "$WORKER_ROOT_PANE" '[.result.panes[] | select(.pane_id == $pane)][0]')"
        WORKER_TAB="$(printf '%s\n' "$root_pane_json" | jq -r '.tab_id // empty')"
        created_terminal="$(printf '%s\n' "$root_pane_json" | jq -r '.terminal_id // empty')"
        [ -n "$WORKER_TAB" ] && [ -n "$created_terminal" ] || fail 'requested root pane has incomplete identity data'
        [ "$(printf '%s\n' "$TABS_JSON" | jq -r --arg tab "$WORKER_TAB" --arg workspace "$WORKER_WORKSPACE" '[.result.tabs[] | select(.tab_id == $tab and .workspace_id == $workspace)] | length')" = '1' ] || fail 'requested root pane is not in the given workspace'
        root_tab_json="$(printf '%s\n' "$TABS_JSON" | jq -c --arg tab "$WORKER_TAB" --arg workspace "$WORKER_WORKSPACE" '[.result.tabs[] | select(.tab_id == $tab and .workspace_id == $workspace)][0]')"
        check_collectable_tab "$root_tab_json" || fail "requested root pane tab $TAB_SAFETY_REASON"
        if ! printf '%s\n' "$AGENTS_JSON" | jq -e --arg pane "$WORKER_ROOT_PANE" 'all(.result.agents[]; type == "object" and (.pane_id | type == "string" and length > 0)) and ([.result.agents[] | select(.pane_id == $pane)] | length == 0)' > /dev/null 2>&1; then
            fail 'requested root pane has an agent or agent inventory is incomplete'
        fi
        WORKER_PANE="$WORKER_ROOT_PANE"
        WORKER_LAUNCH_MODE='root'
    else
        before_tabs="$TABS_JSON"
        before_panes="$PANES_JSON"
        tab_create_args=(--workspace "$WORKER_WORKSPACE" --cwd "$WORKER_CWD" --label "$WORKER_LABEL" --no-focus)
        if [ "$WORKER_ENV_COUNT" -gt 0 ]; then
            for env_assignment in "${WORKER_ENV[@]}"; do
                tab_create_args+=(--env "$env_assignment")
            done
        fi
        if [ "$WORKER_ROLE" = 'implementation' ]; then
            tab_create_args+=(--env "HERDR_WORKER_SIZE_GATE_LAUNCH_ID=$WORKER_SIZE_GATE_LAUNCH_ID")
        fi
        tab_create_json="$(herdr tab create "${tab_create_args[@]}")" || fail 'Herdr could not create the worker tab'
        created_tab="$(printf '%s\n' "$tab_create_json" | jq -r '.result.tab.tab_id // empty')"
        created_pane="$(printf '%s\n' "$tab_create_json" | jq -r '.result.root_pane.pane_id // empty')"
        created_terminal="$(printf '%s\n' "$tab_create_json" | jq -r '.result.root_pane.terminal_id // empty')"
        [ -n "$created_tab" ] && [ -n "$created_pane" ] && [ -n "$created_terminal" ] || fail 'worker tab creation response did not include exact tab and pane identities'
        [ "$(printf '%s\n' "$before_tabs" | jq -r --arg tab "$created_tab" '[.result.tabs[] | select(.tab_id == $tab)] | length')" = '0' ] || fail 'tab creation returned a tab that already existed'
        [ "$(printf '%s\n' "$before_panes" | jq -r --arg pane "$created_pane" '[.result.panes[] | select(.pane_id == $pane)] | length')" = '0' ] || fail 'tab creation returned a pane that already existed'
        WORKER_TAB="$created_tab"
        WORKER_PANE="$created_pane"
        load_inventory || fail 'could not verify the newly created worker tab'
        identify_caller || fail 'caller identity could not be reproven after tab creation'
    fi
    [ "$(printf '%s\n' "$TABS_JSON" | jq -r --arg tab "$WORKER_TAB" --arg workspace "$WORKER_WORKSPACE" '[.result.tabs[] | select(.tab_id == $tab and .workspace_id == $workspace)] | length')" = '1' ] || fail 'worker tab is missing or in another workspace'
    if [ "$WORKER_LAUNCH_MODE" != 'root' ]; then
        [ "$(printf '%s\n' "$TABS_JSON" | jq -r --arg tab "$WORKER_TAB" '[.result.tabs[] | select(.tab_id == $tab and .focused == false)] | length')" = '1' ] || fail 'new worker tab is focused or its focus state is unknown'
    fi
    [ "$(printf '%s\n' "$PANES_JSON" | jq -r --arg pane "$WORKER_PANE" --arg tab "$WORKER_TAB" --arg terminal "$created_terminal" '[.result.panes[] | select(.pane_id == $pane and .tab_id == $tab and .terminal_id == $terminal)] | length')" = '1' ] || fail 'worker pane does not match its recorded tab and terminal identities'
    if [ "$WORKER_ROLE" = 'implementation' ]; then
        if size_gate_result="$(python3 "$SCRIPT_DIR/herdr-worker-size-gate.py" prepare --repo "$WORKER_CWD" --line-budget "$WORKER_LINE_BUDGET" --worker-name "$WORKER_NAME" --task-key "$WORKER_TASK" --launch-id "$WORKER_SIZE_GATE_LAUNCH_ID" --owner-name "$CALLER_NAME" --owner-pane "$HERDR_PANE_ID" --owner-terminal "$CALLER_TERMINAL" --worker-pane "$WORKER_PANE" --worker-tab "$WORKER_TAB" --worker-terminal "$created_terminal" 2>&1)"; then
            :
        else
            fail "size-gate prepare failed; worker was not launched: $size_gate_result"
        fi
    fi
    herdr agent start "$WORKER_NAME" --kind "$WORKER_KIND" --pane "$WORKER_PANE" -- "${WORKER_ARGS[@]}"
    start_status=$?
    if [ "$start_status" -ne 0 ]; then
        if [ "$WORKER_ROLE" = 'implementation' ]; then
            fail "herdr agent start returned status $start_status; the pending size-gate record remains, run audit for an unrecorded-pane warning" "$start_status"
        fi
        fail "herdr agent start returned status $start_status; no launch record was written, run audit for an unrecorded-pane warning" "$start_status"
    fi
    if ! load_inventory; then
        fail 'worker start returned but the resulting Herdr inventory could not be read; run audit for an unrecorded-pane warning'
    fi
    identify_caller || fail 'caller identity could not be reproven after worker launch'
    if [ "$WORKER_ROLE" = 'implementation' ]; then
        if size_gate_result="$(python3 "$SCRIPT_DIR/herdr-worker-size-gate.py" finish --launch-id "$WORKER_SIZE_GATE_LAUNCH_ID" --worker-pane "$WORKER_PANE" --worker-tab "$WORKER_TAB" --worker-terminal "$created_terminal" 2>&1)"; then
            :
        else
            fail "size-gate finish failed; run audit and inspect the pending size-gate record: $size_gate_result"
        fi
    fi
    inspect_records
    record_launch
}

# @description Count exact live worker-pane records for a worker identity.
# @arg $1 name Worker agent name.
# @arg $2 terminal Worker terminal ID.
# @arg $3 tab Worker tab ID.
# @arg $4 pane Worker pane ID.
function worker_record_state() {
    if [ "$RECORD_STATE" != 'valid' ]; then
        printf 'missing\n'
        return 0
    fi
    awk -F '\t' -v worker="$1" -v terminal="$2" -v tab="$3" -v pane="$4" '(NF == 9 || NF == 10) && $5 == worker && $6 == terminal && $7 == tab && $8 == pane { count++; state = $9; task = $4 } END { if (count == 1) print state "\t" task; else if (count > 1) print "duplicate\t"; else print "missing\t" }' "$RECORDS_FILE"
}

# @description Mark a caller-owned settled worker collected and close only its pane.
function collect_worker() {
    local worker_json worker_terminal worker_tab worker_pane worker_state launch_mode recorded_workspace='' records tab_json pane_json workspace_id pane_count workspace_tab_count input_text input_state matches task_key tmp_file
    [ "$#" -eq 1 ] || fail 'collect requires exactly one worker name' 2
    WORKER_NAME="$1"
    load_inventory || fail 'could not read local Herdr inventories'
    identify_caller || fail 'caller identity could not be proven'
    inspect_records
    [ "$RECORD_STATE" = 'valid' ] || fail 'worker registry is missing or malformed'
    matches="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg name "$WORKER_NAME" '[.result.agents[] | select(.name == $name)] | length')"
    [ "$matches" = '1' ] || fail 'worker must match exactly one live Herdr agent'
    worker_json="$(printf '%s\n' "$AGENTS_JSON" | jq -c --arg name "$WORKER_NAME" '[.result.agents[] | select(.name == $name)][0]')"
    worker_terminal="$(printf '%s\n' "$worker_json" | jq -r '.terminal_id // empty')"
    worker_tab="$(printf '%s\n' "$worker_json" | jq -r '.tab_id // empty')"
    worker_pane="$(printf '%s\n' "$worker_json" | jq -r '.pane_id // empty')"
    worker_state="$(printf '%s\n' "$worker_json" | jq -r '.agent_status // "unknown"')"
    [ -n "$worker_terminal" ] && [ -n "$worker_tab" ] && [ -n "$worker_pane" ] || fail 'worker pane identity is unknown'
    [ "$worker_pane" != "$HERDR_PANE_ID" ] && [ "$worker_tab" != "$HERDR_TAB_ID" ] || fail 'cannot collect the caller pane or tab'
    records="$(awk -F '\t' -v owner="$CALLER_NAME" -v owner_pane="$HERDR_PANE_ID" -v owner_terminal="$CALLER_TERMINAL" -v worker="$WORKER_NAME" -v terminal="$worker_terminal" -v tab="$worker_tab" -v pane="$worker_pane" '(NF == 9 || NF == 10) && $5 == worker && $6 == terminal && $7 == tab && $8 == pane { identity_count++; if ($1 == owner && $2 == owner_pane && $3 == owner_terminal && ($9 == "started" || $9 == "collected")) owner_count++ } END { print (identity_count == 1 && owner_count == 1) + 0 }' "$RECORDS_FILE")"
    [ "$records" = '1' ] || fail 'worker does not have one exact launch record for this caller pane and task'
    task_key="$(awk -F '\t' -v owner="$CALLER_NAME" -v owner_pane="$HERDR_PANE_ID" -v owner_terminal="$CALLER_TERMINAL" -v worker="$WORKER_NAME" -v terminal="$worker_terminal" -v tab="$worker_tab" -v pane="$worker_pane" '(NF == 9 || NF == 10) && $1 == owner && $2 == owner_pane && $3 == owner_terminal && $5 == worker && $6 == terminal && $7 == tab && $8 == pane { print $4; exit }' "$RECORDS_FILE")"
    launch_mode="$(awk -F '\t' -v owner="$CALLER_NAME" -v owner_pane="$HERDR_PANE_ID" -v owner_terminal="$CALLER_TERMINAL" -v worker="$WORKER_NAME" -v terminal="$worker_terminal" -v tab="$worker_tab" -v pane="$worker_pane" '(NF == 9 || NF == 10) && $1 == owner && $2 == owner_pane && $3 == owner_terminal && $5 == worker && $6 == terminal && $7 == tab && $8 == pane { count++; mode = (NF == 10 ? $10 : "tab") } END { if (count == 1) print mode }' "$RECORDS_FILE")"
    if [[ "$launch_mode" == owned:* ]]; then
        recorded_workspace="${launch_mode#owned:}"
        launch_mode=owned
    fi
    case "$worker_state" in
    done | idle) ;;
    *) fail "worker is $worker_state; only done or idle workers can be collected" ;;
    esac
    tab_json="$(printf '%s\n' "$TABS_JSON" | jq -c --arg tab "$worker_tab" '[.result.tabs[] | select(.tab_id == $tab)][0]')"
    [ -n "$tab_json" ] && [ "$tab_json" != 'null' ] || fail 'worker tab is missing'
    check_collectable_tab "$tab_json" || fail "worker tab $TAB_SAFETY_REASON"
    workspace_id="$(printf '%s\n' "$tab_json" | jq -r '.workspace_id // empty')"
    [ -n "$workspace_id" ] || fail 'worker workspace is unknown'
    pane_json="$(printf '%s\n' "$PANES_JSON" | jq -c --arg pane "$worker_pane" --arg tab "$worker_tab" '[.result.panes[] | select(.pane_id == $pane and .tab_id == $tab)][0]')"
    [ -n "$pane_json" ] && [ "$pane_json" != 'null' ] || fail 'worker pane is missing from the pane inventory'
    pane_count="$(printf '%s\n' "$PANES_JSON" | jq -r --arg tab "$worker_tab" '[.result.panes[] | select(.tab_id == $tab)] | length')"
    workspace_tab_count="$(printf '%s\n' "$TABS_JSON" | jq -r --arg ws "$workspace_id" '[.result.tabs[] | select(.workspace_id == $ws)] | length')"
    if [ "$launch_mode" = 'owned' ]; then
        [ "$recorded_workspace" = "$workspace_id" ] || fail 'owned workspace ID does not match its launch record; leaving it open'
        owned_workspace_has_only_worker_pane "$workspace_id" "$worker_tab" "$worker_pane" "$worker_terminal" || fail 'owned workspace has another or unknown pane; leaving it open'
    elif [ "$pane_count" -eq 1 ] && [ "$workspace_tab_count" -le 1 ]; then
        fail 'closing this worker pane would close the workspace'
    fi
    input_text="$(herdr pane read "$worker_pane" --source visible --format ansi 2> /dev/null)" || fail 'worker visible input could not be read'
    input_state="$(printf '%s\n' "$input_text" | LC_ALL=C awk -f "$INPUT_STATE_AWK")"
    [ "$input_state" = 'empty' ] || fail "worker visible input is $input_state"

    acquire_lock || fail 'could not acquire the worker-record lock'
    inspect_records
    [ "$RECORD_STATE" = 'valid' ] || fail 'worker registry changed or became malformed'
    records="$(awk -F '\t' -v owner="$CALLER_NAME" -v owner_pane="$HERDR_PANE_ID" -v owner_terminal="$CALLER_TERMINAL" -v worker="$WORKER_NAME" -v terminal="$worker_terminal" -v tab="$worker_tab" -v pane="$worker_pane" -v mode="$launch_mode" -v ws="$recorded_workspace" '(NF == 9 || NF == 10) && $5 == worker && $6 == terminal && $7 == tab && $8 == pane { identity_count++; if ($1 == owner && $2 == owner_pane && $3 == owner_terminal && ((mode == "owned" && NF == 10 && $10 == "owned:" ws) || (mode == "root" && NF == 10 && $10 == "root") || (mode == "tab" && (NF == 9 || (NF == 10 && $10 == "tab"))))) owner_count++ } END { print (identity_count == 1 && owner_count == 1) + 0 }' "$RECORDS_FILE")"
    [ "$records" = '1' ] || fail 'worker launch record changed before collection'
    tmp_file="${RECORDS_FILE}.$$.tmp"
    (umask 077 && : > "$tmp_file") || fail 'cannot prepare worker registry update'
    awk -F '\t' -v OFS='\t' -v owner="$CALLER_NAME" -v owner_pane="$HERDR_PANE_ID" -v owner_terminal="$CALLER_TERMINAL" -v worker="$WORKER_NAME" -v terminal="$worker_terminal" -v tab="$worker_tab" -v pane="$worker_pane" '{ if ((NF == 9 || NF == 10) && $1 == owner && $2 == owner_pane && $3 == owner_terminal && $5 == worker && $6 == terminal && $7 == tab && $8 == pane) $9 = "collected"; print }' "$RECORDS_FILE" > "$tmp_file" || fail 'cannot mark worker collected'
    chmod 600 "$tmp_file" 2> /dev/null || fail 'cannot secure worker registry update'
    mv -f "$tmp_file" "$RECORDS_FILE" || fail 'cannot save collected worker record'
    # Refresh while holding the registry lock so concurrent helper invocations cannot close twice.
    load_inventory || fail 'inventory refresh failed after collection was recorded'
    identify_caller || fail 'caller identity could not be rechecked before collection'
    worker_json="$(printf '%s\n' "$AGENTS_JSON" | jq -c --arg name "$WORKER_NAME" '[.result.agents[] | select(.name == $name)][0]')"
    [ "$worker_json" != 'null' ] || fail 'collected worker is no longer live; its record remains for audit'
    [ "$(printf '%s\n' "$worker_json" | jq -r '.pane_id // empty')" = "$worker_pane" ] && [ "$(printf '%s\n' "$worker_json" | jq -r '.terminal_id // empty')" = "$worker_terminal" ] && [ "$(printf '%s\n' "$worker_json" | jq -r '.tab_id // empty')" = "$worker_tab" ] || fail 'worker identity changed after collection was recorded'
    worker_state="$(printf '%s\n' "$worker_json" | jq -r '.agent_status // "unknown"')"
    case "$worker_state" in done | idle) ;; *) fail "worker became $worker_state; its collected record remains open" ;; esac
    tab_json="$(printf '%s\n' "$TABS_JSON" | jq -c --arg tab "$worker_tab" '[.result.tabs[] | select(.tab_id == $tab)][0]')"
    [ -n "$tab_json" ] && [ "$tab_json" != 'null' ] || fail 'worker tab disappeared after collection was recorded'
    check_collectable_tab "$tab_json" || fail "worker tab $TAB_SAFETY_REASON after collection was recorded"
    workspace_id="$(printf '%s\n' "$tab_json" | jq -r '.workspace_id // empty')"
    [ -n "$workspace_id" ] || fail 'worker workspace became unknown'
    pane_json="$(printf '%s\n' "$PANES_JSON" | jq -c --arg pane "$worker_pane" --arg tab "$worker_tab" --arg terminal "$worker_terminal" '[.result.panes[] | select(.pane_id == $pane and .tab_id == $tab and .terminal_id == $terminal)][0]')"
    [ -n "$pane_json" ] && [ "$pane_json" != 'null' ] || fail 'worker pane identity changed after collection was recorded'
    pane_count="$(printf '%s\n' "$PANES_JSON" | jq -r --arg tab "$worker_tab" '[.result.panes[] | select(.tab_id == $tab)] | length')"
    workspace_tab_count="$(printf '%s\n' "$TABS_JSON" | jq -r --arg ws "$workspace_id" '[.result.tabs[] | select(.workspace_id == $ws)] | length')"
    if [ "$launch_mode" = 'owned' ]; then
        [ "$recorded_workspace" = "$workspace_id" ] || fail 'owned workspace ID changed after collection; leaving it open'
        owned_workspace_has_only_worker_pane "$workspace_id" "$worker_tab" "$worker_pane" "$worker_terminal" || fail 'owned workspace has another or unknown pane; leaving it open'
    elif [ "$pane_count" -eq 1 ] && [ "$workspace_tab_count" -le 1 ]; then
        fail 'worker pane became the last pane in the last workspace tab'
    fi
    input_text="$(herdr pane read "$worker_pane" --source visible --format ansi 2> /dev/null)" || fail 'worker visible input could not be reread before close'
    input_state="$(printf '%s\n' "$input_text" | LC_ALL=C awk -f "$INPUT_STATE_AWK")"
    [ "$input_state" = 'empty' ] || fail "worker visible input became $input_state; its collected record remains open"
    if [ "$launch_mode" = 'owned' ]; then
        herdr workspace close "$recorded_workspace" || fail 'Herdr could not close the owned workspace; it remains open for audit'
    else
        herdr pane close "$worker_pane" || fail 'Herdr could not close the collected worker pane; its record remains for audit'
    fi
    release_lock
    trap - EXIT INT TERM
    printf 'closed worker=%s owner=%s owner-pane=%s task=%s pane=%s workspace=%s\n' "$WORKER_NAME" "$CALLER_NAME" "$HERDR_PANE_ID" "$task_key" "$worker_pane" "$recorded_workspace"
}

# @description Print warnings for live named agent panes without an exact launch record.
function audit_workers() {
    local rows pane tab terminal name state agent_count registration registration_state registration_task warnings
    load_inventory || fail 'could not read local Herdr inventories'
    identify_caller || fail 'caller identity could not be proven'
    inspect_records
    [ "$RECORD_STATE" != 'invalid' ] || fail 'worker registry is malformed or unreadable'
    rows="$(printf '%s\n' "$PANES_JSON" | jq -r --argjson agents "$AGENTS_JSON" '.result.panes[] as $pane | [$pane.pane_id // "", $pane.tab_id // "", $pane.terminal_id // "", ([ $agents.result.agents[] | select(.pane_id == $pane.pane_id and .tab_id == $pane.tab_id and .terminal_id == $pane.terminal_id) ] | length), ([ $agents.result.agents[] | select(.pane_id == $pane.pane_id and .tab_id == $pane.tab_id and .terminal_id == $pane.terminal_id) ][0].name // ""), ([ $agents.result.agents[] | select(.pane_id == $pane.pane_id and .tab_id == $pane.tab_id and .terminal_id == $pane.terminal_id) ][0].agent_status // "unknown")] | @tsv')"
    warnings=0
    while IFS="$(printf '\t')" read -r pane tab terminal agent_count name state; do
        [ -n "$pane" ] || continue
        [ "$pane" = "$HERDR_PANE_ID" ] && continue
        if [ "$agent_count" = '1' ]; then
            registration="$(worker_record_state "$name" "$terminal" "$tab" "$pane")"
            registration_state="${registration%%"$(printf '\t')"*}"
            registration_task="${registration#*"$(printf '\t')"}"
            case "$registration_state" in
            missing)
                printf 'warning unrecorded-live-agent name=%s state=%s pane=%s tab=%s\n' "$name" "$state" "$pane" "$tab"
                warnings=$((warnings + 1))
                ;;
            duplicate)
                printf 'warning duplicate-worker-record name=%s pane=%s tab=%s\n' "$name" "$pane" "$tab"
                warnings=$((warnings + 1))
                ;;
            started)
                case "$state" in done | idle)
                    printf 'warning settled-worker-not-collected name=%s state=%s task=%s pane=%s tab=%s\n' "$name" "$state" "$registration_task" "$pane" "$tab"
                    warnings=$((warnings + 1))
                    ;;
                esac
                ;;
            collected)
                printf 'warning collected-worker-pane-still-open name=%s state=%s task=%s pane=%s tab=%s\n' "$name" "$state" "$registration_task" "$pane" "$tab"
                warnings=$((warnings + 1))
                ;;
            esac
        elif [ "$agent_count" = '0' ]; then
            printf 'warning unrecorded-live-pane-without-agent pane=%s tab=%s\n' "$pane" "$tab"
            warnings=$((warnings + 1))
        else
            printf 'warning ambiguous-agent-pane pane=%s tab=%s matches=%s\n' "$pane" "$tab" "$agent_count"
            warnings=$((warnings + 1))
        fi
    done << EOF
$rows
EOF
    rows="$(printf '%s\n' "$AGENTS_JSON" | jq -r '.result.agents[] | [.name // "", .pane_id // "", .tab_id // "", .terminal_id // "", .agent_status // "unknown"] | @tsv')"
    while IFS="$(printf '\t')" read -r name pane tab terminal state; do
        [ -n "$pane" ] || continue
        [ "$pane" = "$HERDR_PANE_ID" ] && continue
        [ "$(printf '%s\n' "$PANES_JSON" | jq -r --arg pane "$pane" --arg tab "$tab" --arg terminal "$terminal" '[.result.panes[] | select(.pane_id == $pane and .tab_id == $tab and .terminal_id == $terminal)] | length')" = '0' ] || continue
        printf 'warning agent-without-live-pane name=%s state=%s pane=%s tab=%s\n' "$name" "$state" "$pane" "$tab"
        warnings=$((warnings + 1))
    done << EOF
$rows
EOF
    printf 'audit warnings=%s mode=read-only\n' "$warnings"
}

if [ "$COMMAND_NAME" = 'launch' ]; then
    launch_worker "$@"
elif [ "$COMMAND_NAME" = 'collect' ]; then
    collect_worker "$@"
else
    [ "$#" -eq 0 ] || fail 'audit takes no arguments' 2
    audit_workers
fi
