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
#
# `JOBS` is high because the model endpoint's cost is per-request queueing
# rather than throughput: a single trivial run takes about 90 seconds, three
# concurrent ones take 71, and eight take 116. Running two at a time made an
# evaluation nearly serial and cost roughly an hour per skill for no reason.
readonly TRIALS=3
readonly JOBS=8
readonly TIMEOUT=600

# Shuhari defaults the model to whatever the Codex configuration carries, which
# is not a decision this repository should inherit silently. Pin it.
#
# The evaluated model is deliberately the weaker of the ones available. The
# measurement is the difference the skill makes, and a strong model succeeds on
# both arms, which reports a useful skill as useless. A weaker one leaves the
# baseline room to fail, so the difference is visible. Drop to `medium` if
# `high` starts passing both arms on everything.
readonly MODEL=gpt-5.6-luna
readonly REASONING_EFFORT=high

# The judge is a different model on purpose. Left unset, Shuhari points it at
# `--model`, so the same model grades its own output. The harness this
# repository replaced kept the two apart for that reason.
# Grading reads one artifact tree and decides against written assertions, which
# does not need the effort the evaluated work does. Keeping it lower also keeps
# the judge from dominating a run's wall-clock.
readonly JUDGE_MODEL=gpt-5.6-sol
readonly JUDGE_REASONING_EFFORT=medium

readonly MODEL_FLAGS=(
    --model "${MODEL}"
    --reasoning-effort "${REASONING_EFFORT}"
    --judge-model "${JUDGE_MODEL}"
    --judge-reasoning-effort "${JUDGE_REASONING_EFFORT}"
)

# @description Put the pinned `shuhari` on `PATH`, or fail loudly.
# @description
#   Git and pre-commit run hooks with a reduced environment, so mise's shims are
#   often inactive even though the pinned tool is installed. Resolving it through
#   mise keeps the hooks working whether or not the caller had mise activated,
#   and keeps them on the pinned build rather than whatever else is on `PATH`.
#
#   A gate that cannot run is a failure, not a pass, so a genuinely missing
#   binary exits non-zero instead of quietly skipping.
# @exitcode 2 When `shuhari` cannot be located.
function require_shuhari() {
    local resolved
    if command -v mise > /dev/null 2>&1; then
        resolved="$(cd -- "${REPO_ROOT}" && mise which shuhari 2> /dev/null || true)"
        if [ -n "${resolved}" ] && [ -x "${resolved}" ]; then
            PATH="$(dirname -- "${resolved}"):${PATH}"
            export PATH
            return 0
        fi
    fi

    if command -v shuhari > /dev/null 2>&1; then
        return 0
    fi

    printf 'shuhari not found. Run "make setup" in %s.\n' "${REPO_ROOT}" >&2
    exit 2
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

    # Bash 3.2 treats expanding an empty array as an unbound variable under
    # `set -u`, so every array expansion here is guarded by a count check.
    [ "${#trigger_targets[@]}" -gt 0 ] || return 0

    local target
    for target in "${trigger_targets[@]}"; do
        shuhari check trigger --validate-only "${target}"
    done
}

# @description Report whether a skill declares that its cases need network egress.
# @description
#   Runs are offline by default. A skill whose subject is the live network — one
#   that tells the agent to consult current documentation, for example — cannot
#   be measured offline: it correctly refuses to proceed, produces nothing, and
#   loses to a baseline that simply guesses. Such a skill declares the need with
#   an `evals/network-required` marker.
# @arg $1 target Absolute skill directory.
# @exitcode 0 When the skill declares that it needs network egress.
# @exitcode 1 When it does not.
function needs_network() {
    [ -f "$1/evals/network-required" ]
}

# @description Print the `--allow-tool` flags a skill declares.
# @description
#   Evaluated agents see a fixed system PATH, so a skill whose subject is a tool
#   installed elsewhere measures the sandbox rather than the skill: the agent
#   reports the tool as unavailable and loses to a baseline that improvises. A
#   skill declares what it needs in `evals/tools-required`, one name per line,
#   with `#` comments ignored.
# @arg $1 target Absolute skill directory.
# @stdout Alternating `--allow-tool <name>` arguments, one pair per line.
function declared_tool_flags() {
    local manifest="$1/evals/tools-required"
    [ -f "${manifest}" ] || return 0

    local line
    while IFS= read -r line || [ -n "${line}" ]; do
        line="${line%%#*}"
        line="$(printf '%s' "${line}" | tr -d '[:space:]')"
        [ -n "${line}" ] || continue
        printf -- '--allow-tool\n%s\n' "${line}"
    done < "${manifest}"
}

# @description Evaluate skills with and without their guidance.
# @description
#   `shuhari eval skill` takes network access as a whole-run flag, so skills that
#   need it are evaluated in a separate invocation from those that do not.
# @arg $@ targets Absolute skill directories.
# @exitcode 1 When an evaluation fails.
function run_eval() {
    local -a targets=()
    read_lines_into targets < <(filter_by_eval_file evals.json "$@")
    [ "${#targets[@]}" -gt 0 ] || return 0

    local -a offline=()
    local -a online=()
    local target
    for target in "${targets[@]}"; do
        if needs_network "${target}"; then
            online+=("${target}")
        else
            offline+=("${target}")
        fi
    done

    local status=0
    local -a group_flags=()
    local group
    for group in offline online; do
        local -a members=()
        if [ "${group}" = "offline" ]; then
            members=(${offline[@]+"${offline[@]}"})
            group_flags=()
        else
            members=(${online[@]+"${online[@]}"})
            group_flags=(--network=true)
        fi
        [ "${#members[@]}" -gt 0 ] || continue

        local member
        for member in "${members[@]}"; do
            # Tool declarations are per-run flags, so a skill that declares any
            # is evaluated on its own rather than batched with the others.
            local -a tool_flags=()
            read_lines_into tool_flags < <(declared_tool_flags "${member}")
            shuhari eval skill ${group_flags[@]+"${group_flags[@]}"} ${tool_flags[@]+"${tool_flags[@]}"} \
                "${MODEL_FLAGS[@]}" \
                --trials "${TRIALS}" --jobs "${JOBS}" --timeout "${TIMEOUT}" \
                "${member}" || status=1
        done
    done
    return "${status}"
}

# @description Check trigger boundaries one skill at a time.
# @description `shuhari check trigger` accepts exactly one skill directory.
# @arg $@ targets Absolute skill directories.
# @exitcode 1 When any trigger check fails.
function run_trigger() {
    local -a targets=()
    read_lines_into targets < <(filter_by_eval_file triggers.json "$@")
    [ "${#targets[@]}" -gt 0 ] || return 0

    local target
    local status=0
    for target in "${targets[@]}"; do
        local -a tool_flags=()
        read_lines_into tool_flags < <(declared_tool_flags "${target}")
        shuhari check trigger "${target}" ${tool_flags[@]+"${tool_flags[@]}"} \
            "${MODEL_FLAGS[@]}" \
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
