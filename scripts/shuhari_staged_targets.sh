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
#
#   The execution environment can be adjusted with `SHUHARI_SANDBOX`,
#   `SHUHARI_AGENT_EXECUTABLE`, `SHUHARI_MODE`, `SHUHARI_JOBS`,
#   `SHUHARI_TIMEOUT`, and `SHUHARI_ALLOW_TOOLS`. The sandbox, mode, and
#   executable variables add their corresponding flags; an `unsandboxed`
#   sandbox also adds `--network`, as required by Shuhari. The jobs and timeout
#   variables replace their defaults, while each whitespace-separated allow-tools
#   entry adds one repeated `--allow-tool` flag. Leaving all six unset preserves
#   the existing argv byte for byte.
#
#   Schema validation is exempt from all of these. It never executes an agent,
#   so there is no execution environment for them to describe, and Shuhari reads
#   `SHUHARI_SANDBOX` from the environment on its own: an exported
#   `unsandboxed` would reject a `--validate-only` run that touches no sandbox
#   at all.
#
#   These are environment-shaped overrides only. Trials, evaluated model,
#   judge model, and reasoning efforts define measurement and remain pinned
#   below; they are not overridable.
# @arg $1 mode One of `validate`, `eval`, or `trigger`.
# @arg $@ paths Changed file paths supplied by pre-commit.
# @exitcode 0 Every selected target passed, or nothing was selected.
# @exitcode 1 A Shuhari gate failed.
# @exitcode 2 Invalid usage, or `shuhari` is not installed.
# @example
#   scripts/shuhari_staged_targets.sh eval skills/shunk031-python-uv-workflow/SKILL.md

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly SKILLS_ROOT="${REPO_ROOT}/skills"
readonly RECORDER="${REPO_ROOT}/scripts/record_eval_results.py"

# Keep in step with the `python` pin in mise.toml.
readonly PYTHON_VERSION=3.14.6

# Policy values owned by this repository rather than by Shuhari.
#
# `JOBS` is high because the model endpoint's cost is per-request queueing
# rather than throughput: a single trivial run takes about 90 seconds, three
# concurrent ones take 71, and eight take 116. Running two at a time made an
# evaluation nearly serial and cost roughly an hour per skill for no reason.
readonly TRIALS=3
readonly JOBS="${SHUHARI_JOBS:-8}"
readonly TIMEOUT="${SHUHARI_TIMEOUT:-600}"

# Shuhari defaults the model to whatever the Codex configuration carries, which
# is not a decision this repository should inherit silently. Pin it.
#
# The evaluated model is deliberately the weaker of the ones available. The
# measurement is the difference the skill makes, and a strong model succeeds on
# both arms, which reports a useful skill as useless. A weaker one leaves the
# baseline room to fail, so the difference is visible. Drop to `medium` if
# `high` starts passing both arms on everything.
#
# The 5.6 family cannot use the web-search tool: it answers
# `403 Forbidden: Selected provider is forbidden` and falls back to memory or a
# direct API call, often without saying so. Skills declaring
# `evals/network-required` therefore use the separate network policy below.
readonly MODEL=gpt-5.6-luna
readonly REASONING_EFFORT=high

# Network-required behavior cases use the model that can search successfully.
# Keep this exception scoped to behavior evaluation; trigger checks remain
# offline because they measure whether the skill engages, not its research.
readonly NETWORK_MODEL=gpt-5.5
readonly NETWORK_REASONING_EFFORT=medium

# The judge is a different model on purpose. Left unset, Shuhari points it at
# `--model`, so the same model grades its own output. The harness this
# repository replaced kept the two apart for that reason.
# Grading reads one artifact tree and decides against written assertions, which
# does not need the effort the evaluated work does. Keeping it lower also keeps
# the judge from dominating a run's wall-clock.
readonly JUDGE_MODEL=gpt-5.6-sol
readonly JUDGE_REASONING_EFFORT=medium

# Streams phase events as JSON Lines on stderr. stdout keeps carrying only the
# verdict, so a caller can still parse the result.
readonly PROGRESS_FLAG=--progress

# The evaluated run's model. Both gates take these.
readonly RUN_MODEL_FLAGS=(
    --model "${MODEL}"
    --reasoning-effort "${REASONING_EFFORT}"
)

# The grader's model. `shuhari eval skill` grades and compares two arms and
# takes these; `shuhari check trigger` runs one arm and judges it by whether the
# skill engaged, so it has no judge and rejects the flags outright.
readonly EVAL_MODEL_FLAGS=(
    "${RUN_MODEL_FLAGS[@]}"
    --judge-model "${JUDGE_MODEL}"
    --judge-reasoning-effort "${JUDGE_REASONING_EFFORT}"
)

# Network-required runs preserve the isolated sandbox while allowing egress.
readonly NETWORK_EVAL_MODEL_FLAGS=(
    --model "${NETWORK_MODEL}"
    --reasoning-effort "${NETWORK_REASONING_EFFORT}"
    --judge-model "${JUDGE_MODEL}"
    --judge-reasoning-effort "${JUDGE_REASONING_EFFORT}"
    --network
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

# @description Validate the optional Shuhari evaluation mode override.
# @exitcode 2 When `SHUHARI_MODE` is set to an unsupported value.
function validate_shuhari_mode() {
    if [ "${SHUHARI_MODE+x}" = x ]; then
        case "${SHUHARI_MODE}" in
        agentic | completion) ;;
        *)
            printf "Invalid SHUHARI_MODE '%s'; expected agentic or completion.\n" \
                "${SHUHARI_MODE}" >&2
            exit 2
            ;;
        esac
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
# @description
#   Both invocations are stripped of the execution-environment variables
#   Shuhari reads directly. Validation parses files; it starts no agent and
#   enters no sandbox, so an exported `SHUHARI_SANDBOX=unsandboxed` would fail
#   the gate over an execution environment this run never establishes.
# @arg $@ targets Absolute skill directories.
# @exitcode 1 When a schema is invalid.
function run_validate() {
    local -a eval_targets=()
    local -a trigger_targets=()
    read_lines_into eval_targets < <(filter_by_eval_file evals.json "$@")
    read_lines_into trigger_targets < <(filter_by_eval_file triggers.json "$@")

    local -a offline=(
        env -u SHUHARI_SANDBOX -u SHUHARI_I_UNDERSTAND_NO_CREDENTIAL_BOUNDARY
    )

    if [ "${#eval_targets[@]}" -gt 0 ]; then
        "${offline[@]}" shuhari eval skill --validate-only "${eval_targets[@]}"
    fi

    # Bash 3.2 treats expanding an empty array as an unbound variable under
    # `set -u`, so every array expansion here is guarded by a count check.
    [ "${#trigger_targets[@]}" -gt 0 ] || return 0

    local target
    for target in "${trigger_targets[@]}"; do
        "${offline[@]}" shuhari check trigger --validate-only "${target}"
    done
}

# @description Report whether a skill declares the network evaluation policy.
# @description
#   Runs are offline by default. A skill whose subject is the live network — one
#   that tells the agent to consult current documentation, for example — cannot
#   be measured offline: it correctly refuses to proceed, produces nothing, and
#   loses to a baseline that simply guesses. Such a skill declares the need with
#   an `evals/network-required` marker.
#
#   The marker selects `gpt-5.5` with medium reasoning and network egress while
#   preserving Shuhari's default isolated sandbox. Ordinary behavior cases and
#   every trigger check retain the default offline policy.
# @arg $1 target Absolute skill directory.
# @exitcode 0 When the skill declares that its cases need network egress.
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
#   with `#` comments ignored. `SHUHARI_ALLOW_TOOLS` appends its
#   whitespace-separated entries to the same flags.
# @arg $1 target Absolute skill directory.
# @stdout Alternating `--allow-tool <name>` arguments, one pair per line.
function declared_tool_flags() {
    local manifest="$1/evals/tools-required"
    if [ -f "${manifest}" ]; then
        local line
        while IFS= read -r line || [ -n "${line}" ]; do
            line="${line%%#*}"
            line="$(printf '%s' "${line}" | tr -d '[:space:]')"
            [ -n "${line}" ] || continue
            printf -- '--allow-tool\n%s\n' "${line}"
        done < "${manifest}"
    fi

    local tool
    while IFS= read -r tool || [ -n "${tool}" ]; do
        [ -n "${tool}" ] || continue
        printf -- '--allow-tool\n%s\n' "${tool}"
    done < <(printf '%s\n' "${SHUHARI_ALLOW_TOOLS:-}" | tr -s '[:space:]' '\012')
}

# @description Print flags for execution-environment overrides.
# @stdout Alternating environment flag names and values, with `--network` for
#   an `unsandboxed` sandbox and `--mode <value>` when requested.
# @arg $1 network_already_allowed Whether the command already includes
#   `--network`.
function declared_environment_flags() {
    local network_already_allowed="${1:-false}"
    if [ -n "${SHUHARI_SANDBOX:-}" ]; then
        printf -- '--sandbox\n%s\n' "${SHUHARI_SANDBOX}"
        if [ "${SHUHARI_SANDBOX}" = unsandboxed ] &&
            [ "${network_already_allowed}" != true ]; then
            printf '%s\n' '--network'
        fi
    fi

    if [ "${SHUHARI_MODE+x}" = x ]; then
        printf -- '--mode\n%s\n' "${SHUHARI_MODE}"
    fi

    if [ -n "${SHUHARI_AGENT_EXECUTABLE:-}" ]; then
        printf -- '--agent-executable\n%s\n' "${SHUHARI_AGENT_EXECUTABLE}"
    fi
}

# @description Lift a finished run's numbers into the skill's `results.json`.
# @description
#   The documentation site reads that file to say what a skill measurably
#   changes. It can only be written where the run happened, because the
#   workspace it reads is gitignored, so leaving it to a person means it does
#   not happen: two gates were run the day the recorder was written and one
#   `results.json` exists.
#
#   A failure here does not fail the gate. The evaluation is the gate; recording
#   is bookkeeping, and losing a number is not worth rejecting a passing run.
# @arg $1 target Absolute skill directory.
function record_results() {
    uv run --python "${PYTHON_VERSION}" --no-project -- python "${RECORDER}" "$1" || {
        printf 'warning: could not record results for %s\n' "$(basename -- "$1")" >&2
    }
}

# @description Evaluate skills with and without their guidance.
# @description
#   Skills declaring `evals/network-required` use the dedicated network model
#   policy. Other skills retain the default offline model policy.
# @arg $@ targets Absolute skill directories.
# @exitcode 1 When an evaluation fails.
function run_eval() {
    local -a targets=()
    read_lines_into targets < <(filter_by_eval_file evals.json "$@")
    [ "${#targets[@]}" -gt 0 ] || return 0

    local status=0
    local target
    for target in "${targets[@]}"; do
        local -a eval_model_flags=("${EVAL_MODEL_FLAGS[@]}")
        local network_already_allowed=false
        if needs_network "${target}"; then
            eval_model_flags=("${NETWORK_EVAL_MODEL_FLAGS[@]}")
            network_already_allowed=true
        fi

        local -a environment_flags=()
        read_lines_into environment_flags < \
            <(declared_environment_flags "${network_already_allowed}")

        # Tool declarations are per-run flags, so a skill that declares any is
        # evaluated on its own rather than batched with the others.
        local -a tool_flags=()
        read_lines_into tool_flags < <(declared_tool_flags "${target}")
        if shuhari eval skill ${tool_flags[@]+"${tool_flags[@]}"} \
            ${environment_flags[@]+"${environment_flags[@]}"} \
            "${PROGRESS_FLAG}" "${eval_model_flags[@]}" \
            --trials "${TRIALS}" --jobs "${JOBS}" --timeout "${TIMEOUT}" \
            "${target}"; then
            record_results "${target}"
        else
            status=1
            # A failed run still produced numbers, and they are the ones worth
            # publishing: the site should show what the skill currently does,
            # not the last time it passed.
            record_results "${target}"
        fi
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

    local -a environment_flags=()
    read_lines_into environment_flags < <(declared_environment_flags false)

    local target
    local status=0
    for target in "${targets[@]}"; do
        local -a tool_flags=()
        read_lines_into tool_flags < <(declared_tool_flags "${target}")
        shuhari check trigger "${target}" ${tool_flags[@]+"${tool_flags[@]}"} \
            ${environment_flags[@]+"${environment_flags[@]}"} \
            "${PROGRESS_FLAG}" "${RUN_MODEL_FLAGS[@]}" \
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

    validate_shuhari_mode
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
