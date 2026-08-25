#!/usr/bin/env bash

# @file scripts/check_skill_layout.sh
# @brief Enforce the repository's skill layout and naming rules.
# @description
#   Shuhari validates only the skills that carry eval files, and the `skills`
#   CLI reports discovery problems as missing skills rather than as errors. This
#   script covers the gap with offline checks that need no agent:
#
#   1. No `SKILL.md` at the repository root, which would stop CLI discovery and
#      hide every other skill.
#   2. Every skill directory holds a `SKILL.md`.
#   3. Each `SKILL.md` has closed YAML frontmatter with a non-empty `name` and
#      `description`.
#   4. The frontmatter `name` equals the skill directory name.
#   5. `evals/evals.json` and `evals/triggers.json` agree with that name.
#   6. No `SKILL.md` is nested deeper than `skills/<name>/SKILL.md`.
#   7. No Shuhari workspace directory is tracked by git.
# @exitcode 0 When every check passes.
# @exitcode 1 When any check fails.
# @example
#   scripts/check_skill_layout.sh

set -Eeuo pipefail
shopt -s nullglob

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly SKILLS_ROOT="${REPO_ROOT}/skills"

failures=()

# @description Record a failure without aborting the remaining checks.
# @arg $1 message The failure description.
function fail() {
    failures+=("$1")
}

# @description Read a scalar field from a `SKILL.md` YAML frontmatter block.
# @description
#   Only the leading frontmatter block is considered, and only simple
#   `key: value` scalars are supported. Surrounding quotes are stripped.
# @arg $1 file The `SKILL.md` path.
# @arg $2 key The frontmatter key to read.
# @stdout The field value, or nothing when the key is absent.
function frontmatter_field() {
    local file="$1"
    local key="$2"
    awk -v key="${key}" '
        NR == 1 { if ($0 != "---") exit 0; in_block = 1; next }
        in_block && $0 == "---" { exit 0 }
        in_block {
            prefix = key ":"
            if (index($0, prefix) == 1) {
                value = substr($0, length(prefix) + 1)
                sub(/^[ \t]+/, "", value)
                sub(/[ \t]+$/, "", value)
                gsub(/^["'"'"']|["'"'"']$/, "", value)
                print value
                exit 0
            }
        }
    ' "${file}"
}

# @description Read `skill_name` from a Shuhari eval or trigger file.
# @arg $1 file The JSON file path.
# @stdout The `skill_name` value, or nothing when it is absent.
function eval_skill_name() {
    local file="$1"
    sed -n 's/.*"skill_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${file}" | head -n 1
}

# @description Reject a repository-root `SKILL.md`.
# @description
#   The `skills` CLI returns only the root skill when one exists, so this single
#   file would make every skill in `skills/` invisible to installers.
function assert_no_root_skill_file() {
    if [ -f "${REPO_ROOT}/SKILL.md" ]; then
        fail 'SKILL.md exists at the repository root, which hides every skill under skills/'
    fi
}

# @description Reject a `SKILL.md` nested deeper than `skills/<name>/`.
# @description
#   Shuhari workspaces are pruned: they are run artifacts that can contain a
#   copy of the skill under evaluation, which is not a layout violation.
function assert_no_nested_skill_files() {
    local file
    while IFS= read -r file; do
        [ -n "${file}" ] || continue
        fail "SKILL.md nested too deep: ${file#"${REPO_ROOT}/"}"
    done < <(find "${SKILLS_ROOT}" -type d -name '*-workspace' -prune -o -mindepth 3 -name 'SKILL.md' -print 2> /dev/null)
}

# @description Verify frontmatter and eval-file naming for one skill.
# @arg $1 skill_dir The absolute skill directory.
function check_skill() {
    local skill_dir="$1"
    local name
    name="$(basename -- "${skill_dir}")"
    local skill_file="${skill_dir}/SKILL.md"

    if [ ! -f "${skill_file}" ]; then
        fail "skills/${name} has no SKILL.md"
        return 0
    fi

    local declared
    declared="$(frontmatter_field "${skill_file}" name)"
    if [ -z "${declared}" ]; then
        fail "skills/${name}/SKILL.md has no frontmatter name"
    elif [ "${declared}" != "${name}" ]; then
        fail "skills/${name}/SKILL.md declares name ${declared}, which does not match its directory"
    fi

    if [ -z "$(frontmatter_field "${skill_file}" description)" ]; then
        fail "skills/${name}/SKILL.md has no frontmatter description"
    fi

    local eval_file
    for eval_file in evals.json triggers.json; do
        local path="${skill_dir}/evals/${eval_file}"
        [ -f "${path}" ] || continue

        local declared_eval_name
        declared_eval_name="$(eval_skill_name "${path}")"
        if [ "${declared_eval_name}" != "${name}" ]; then
            fail "skills/${name}/evals/${eval_file} declares skill_name ${declared_eval_name:-<missing>}, which does not match its directory"
        fi
    done
}

# @description Reject tracked Shuhari workspace directories.
# @description
#   Workspaces hold verbatim agent transcripts. `.gitignore` covers them, but a
#   forced add would slip past it.
function assert_no_tracked_workspaces() {
    local tracked
    tracked="$(git -C "${REPO_ROOT}" ls-files -- 'skills/*-workspace/*' 2> /dev/null || true)"
    if [ -n "${tracked}" ]; then
        fail 'Shuhari workspace artifacts are tracked by git; they contain agent transcripts'
    fi
}

# @description Run every layout check and report the collected failures.
function main() {
    assert_no_root_skill_file
    assert_no_nested_skill_files
    assert_no_tracked_workspaces

    local skill_dir
    for skill_dir in "${SKILLS_ROOT}"/*/; do
        skill_dir="${skill_dir%/}"
        # Shuhari writes `<skill>-workspace/` beside the skill it evaluated.
        # Those are gitignored run artifacts, not skills, and they are present
        # whenever someone has run a gate locally.
        case "${skill_dir}" in
        *-workspace) continue ;;
        esac
        check_skill "${skill_dir}"
    done

    if [ "${#failures[@]}" -gt 0 ]; then
        printf 'skill layout check failed:\n' >&2
        printf '  %s\n' "${failures[@]}" >&2
        exit 1
    fi

    printf 'check_skill_layout: ok\n'
}

main "$@"
