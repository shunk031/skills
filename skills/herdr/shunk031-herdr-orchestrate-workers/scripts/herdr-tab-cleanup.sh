#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-tab-cleanup.sh
# @brief Report or close local Herdr tabs whose ownership and safety are proven.
# @description
#   Requires every pane to belong to a completed caller-owned worker with empty
#   visible input. It never closes a primary checkout or removes worktrees and
#   branches, and it leaves one tab in each workspace.
# @option --apply Close candidates after a fresh safety check.
# @option --results-collected Attest that eligible worker results were collected.
# @option --help Show usage.
# @example
#   scripts/herdr-tab-cleanup.sh
#   scripts/herdr-tab-cleanup.sh --apply --results-collected

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
INPUT_STATE_AWK="${SCRIPT_DIR}/herdr-visible-input-state.awk"
APPLY=0
RESULTS_COLLECTED=0

function usage() {
    cat << 'USAGE'
Usage: herdr-tab-cleanup.sh [--apply] [--results-collected] [--help]

By default, report a close/keep verdict for each local Herdr tab.
--apply closes candidates after a fresh safety check.
--results-collected attests that results from eligible completed worker tabs
were collected and no further messages will be sent.
USAGE
}

function fail() {
    printf 'herdr tab cleanup: %s\n' "$1" >&2
    exit "${2:-1}"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
    --apply) APPLY=1 ;;
    --results-collected) RESULTS_COLLECTED=1 ;;
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
CALLER_NAME=''
CALLER_TAB=''
CALLER_IDENTITY_OK=0

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
    local matches
    matches="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg pane "$HERDR_PANE_ID" '[.result.agents[] | select(.pane_id == $pane)] | length')"
    CALLER_IDENTITY_OK=0
    CALLER_NAME=''
    CALLER_TAB=''
    [ "$matches" = "1" ] || return 1
    CALLER_NAME="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg pane "$HERDR_PANE_ID" '[.result.agents[] | select(.pane_id == $pane)][0].name // empty')"
    CALLER_TAB="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg pane "$HERDR_PANE_ID" '[.result.agents[] | select(.pane_id == $pane)][0].tab_id // empty')"
    [ -n "$CALLER_NAME" ] && [ "$CALLER_TAB" = "$HERDR_TAB_ID" ] || return 1
    CALLER_IDENTITY_OK=1
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
    local pane_id cwd foreground_cwd check_path root git_dir common_dir canonical_git canonical_common
    local agent_matches agent_json agent_name agent_status input_text input_state
    local candidate_root candidate_branch merged_evidence

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

    pane_rows="$(printf '%s\n' "$PANES_JSON" | jq -r --arg tab "$tab_id" '[.result.panes[] | select(.tab_id == $tab)] | .[] | [.pane_id, (.cwd // ""), (.foreground_cwd // "")] | @tsv')"
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
    while IFS="$(printf '\t')" read -r pane_id cwd foreground_cwd; do
        if [ -z "$pane_id" ]; then
            [ -z "$cwd" ] && [ -z "$foreground_cwd" ] && continue
            printf 'keep\tpane inventory contains an unnamed pane\n'
            return 0
        fi
        agent_matches="$(printf '%s\n' "$AGENTS_JSON" | jq -r --arg pane "$pane_id" '[.result.agents[] | select(.pane_id == $pane)] | length')"
        [ "$agent_matches" = "1" ] || {
            printf 'keep\tpane %s has no unique named agent; owner is unknown\n' "$pane_id"
            return 0
        }
        agent_json="$(printf '%s\n' "$AGENTS_JSON" | jq -c --arg pane "$pane_id" '[.result.agents[] | select(.pane_id == $pane)][0]')"
        agent_name="$(printf '%s\n' "$agent_json" | jq -r '.name // empty')"
        agent_status="$(printf '%s\n' "$agent_json" | jq -r '.agent_status // .status // empty')"
        [ -n "$agent_name" ] || {
            printf 'keep\tpane %s agent identity is unknown\n' "$pane_id"
            return 0
        }
        case "$agent_name" in
        "${CALLER_NAME}"-*) ;;
        *)
            printf 'keep\tpane %s agent %s is not named by caller %s\n' "$pane_id" "$agent_name" "$CALLER_NAME"
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
        printf 'close\tall panes are caller-owned completed workers with empty inputs; %s\n' "$merged_evidence"
    elif [ "$RESULTS_COLLECTED" -eq 1 ]; then
        printf 'close\tall panes are caller-owned completed workers with empty inputs; result collection is attested\n'
    else
        printf 'keep\tcompleted owned worker has no proven merged PR and results were not attested as collected\n'
    fi
}

# @description Count the currently listed tabs in a workspace.
# @arg $1 workspace_id Herdr workspace ID.
function workspace_tab_count() {
    printf '%s\n' "$TABS_JSON" | jq -r --arg workspace "$1" '[.result.tabs[] | select(.workspace_id == $workspace)] | length'
}

load_inventory || fail "could not read valid local Herdr tab, pane, and agent inventories"
identify_caller || true

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
        classification="$(classify_tab "$tab_id")"
        IFS="$(printf '\t')" read -r current_verdict current_evidence << EOF
$classification
EOF
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
