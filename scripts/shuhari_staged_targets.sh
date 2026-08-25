#!/usr/bin/env bash

# @file scripts/shuhari_staged_targets.sh
# @brief Map pre-commit file paths to Shuhari skill targets and run the gate.
# @description
#   pre-commit passes individual changed file paths, but `shuhari check trigger`
#   takes exactly one skill directory, and both commands exit 2 when the eval
#   file they need is absent. This wrapper resolves each path to its skill
#   directory, drops duplicates and deleted skills, skips skills that do not
#   carry the eval file for the requested mode, and then invokes Shuhari with
#   this repository's declared policy values.
#
#   Shuhari owns the evaluation mechanism; this script owns target selection and
#   policy, per the Shuhari development architecture contract.
# @arg $1 mode One of `validate`, `eval`, or `trigger`.
# @arg $@ paths Changed file paths supplied by pre-commit.
# @exitcode 0 Every selected target passed, or nothing was selected.
# @exitcode 1 A Shuhari gate failed.
# @exitcode 2 Invalid usage, or `shuhari` is not installed.
# @example
#   scripts/shuhari_staged_targets.sh eval skills/shunk031-doc-slop-review/SKILL.md

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly SKILLS_ROOT="${REPO_ROOT}/skills"

# Policy values owned by this repository rather than by Shuhari.
readonly TRIALS=3
readonly JOBS=2
readonly TIMEOUT=600

# @description Fail loudly when the gate binary is missing.
# @description A gate that cannot run is a failure, not a pass.
# @exitcode 2 When `shuhari` is not on `PATH`.
function require_shuhari() {
    if ! command -v shuhari > /dev/null 2>&1; then
        printf 'shuhari not found on PATH. Run "make setup" in %s.\n' "${REPO_ROOT}" >&2
        exit 2
    fi
}

# @description Resolve a changed path to its skill directory name.
# @arg $1 path Repository-relative or absolute changed path.
# @stdout The skill directory name, or nothing for paths outside `skills/`.
function skill_name_of() {
    local path="$1"
    local relative="${path#"${REPO_ROOT}/"}"
    relative="${relative#./}"
    case "${relative}" in
    skills/*/*) ;;
    *) return 0 ;;
    esac
    local rest="${relative#skills/}"
    printf '%s\n' "${rest%%/*}"
}

# @description Collect existing skill directories for the supplied paths.
# @description
#   A path may name a deleted file, or a skill deleted outright. Only a
#   directory that still holds `SKILL.md` is a valid Shuhari target; anything
#   else would make Shuhari walk up to the repository root and fail.
# @arg $@ paths Changed file paths.
# @stdout One absolute skill directory per line, deduplicated and sorted.
function collect_targets() {
    local path name
    for path in "$@"; do
        name="$(skill_name_of "${path}")"
        [ -n "${name}" ] || continue
        [ -f "${SKILLS_ROOT}/${name}/SKILL.md" ] || continue
        printf '%s\n' "${SKILLS_ROOT}/${name}"
    done | LC_ALL=C sort -u
}

# @description Keep only targets carrying the eval file a mode requires.
# @description
#   Shuhari treats a missing eval file as invalid input rather than as a skip,
#   so filtering here is what lets a skill ship without evals.
# @arg $1 eval_file File name under the skill's `evals/` directory.
# @arg $@ targets Absolute skill directories.
# @stdout The retained targets, one per line.
function filter_by_eval_file() {
    local eval_file="$1"
    shift
    local target
    for target in "$@"; do
        if [ -f "${target}/evals/${eval_file}" ]; then
            printf '%s\n' "${target}"
        else
            printf 'skip %s: no evals/%s\n' "$(basename -- "${target}")" "${eval_file}" >&2
        fi
    done
}

# @description Read lines from standard input into a named array.
# @description
#   `mapfile` is Bash 4 only, and macOS ships Bash 3.2. This keeps the scripts
#   runnable with the system shell.
# @arg $1 array_name The array to replace with the lines read.
function read_lines_into() {
    local array_name="$1"
    local line
    eval "${array_name}=()"
    while IFS= read -r line; do
        [ -n "${line}" ] || continue
        eval "${array_name}+=(\"\${line}\")"
    done
}

# @description Validate eval and trigger schemas without invoking an agent.
# @arg $@ targets Absolute skill directories.
# @exitcode 1 When a schema is invalid.
function run_validate() {
    local -a eval_targets=()
    local -a trigger_targets=()
    read_lines_into eval_targets < <(filter_by_eval_file evals.json "$@")
    read_lines_into trigger_targets < <(filter_by_eval_file triggers.json "$@")

    if [ "${#eval_targets[@]}" -gt 0 ]; then
        shuhari eval skill --validate-only "${eval_targets[@]}"
    fi

    local target
    for target in "${trigger_targets[@]}"; do
        shuhari check trigger --validate-only "${target}"
    done
}

# @description Evaluate skills with and without their guidance.
# @arg $@ targets Absolute skill directories.
# @exitcode 1 When an evaluation fails.
function run_eval() {
    local -a targets=()
    read_lines_into targets < <(filter_by_eval_file evals.json "$@")
    [ "${#targets[@]}" -gt 0 ] || return 0

    # `shuhari eval skill` accepts several directories and reuses one harness.
    shuhari eval skill \
        --trials "${TRIALS}" --jobs "${JOBS}" --timeout "${TIMEOUT}" \
        "${targets[@]}"
}

# @description Check trigger boundaries one skill at a time.
# @description `shuhari check trigger` accepts exactly one skill directory.
# @arg $@ targets Absolute skill directories.
# @exitcode 1 When any trigger check fails.
function run_trigger() {
    local -a targets=()
    read_lines_into targets < <(filter_by_eval_file triggers.json "$@")

    local target
    local status=0
    for target in "${targets[@]}"; do
        shuhari check trigger "${target}" \
            --trials "${TRIALS}" --jobs "${JOBS}" --timeout "${TIMEOUT}" || status=1
    done
    return "${status}"
}

# @description Dispatch the requested gate over the resolved skill targets.
# @arg $1 mode One of `validate`, `eval`, or `trigger`.
# @arg $@ paths Changed file paths supplied by pre-commit.
function main() {
    local mode="${1:-}"
    shift || true

    case "${mode}" in
    validate | eval | trigger) ;;
    *)
        printf 'Usage: %s {validate|eval|trigger} <path>...\n' "$0" >&2
        exit 2
        ;;
    esac

    require_shuhari

    local -a targets=()
    read_lines_into targets < <(collect_targets "$@")
    if [ "${#targets[@]}" -eq 0 ]; then
        printf 'No skill targets selected.\n'
        exit 0
    fi

    "run_${mode}" "${targets[@]}"
}

main "$@"
