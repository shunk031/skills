#!/usr/bin/env bats

# The layout check resolves `skills/` from its own location, so setup copies it
# into a disposable repository holding synthetic skills. That keeps these tests
# independent of whichever skills the real tree currently ships, and lets a
# rejected name exist at all: one committed to `skills/` would fail the very
# gate this file covers.

setup() {
    FIXTURE_ROOT="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${FIXTURE_ROOT}/scripts"
    cp "${BATS_TEST_DIRNAME}/../../scripts/check_skill_layout.sh" \
        "${FIXTURE_ROOT}/scripts/check_skill_layout.sh"
    CHECKER="${FIXTURE_ROOT}/scripts/check_skill_layout.sh"
    mkdir -p "${FIXTURE_ROOT}/skills"
}

# @description Create a minimal well-formed skill directory.
# @arg $1 name The skill directory name, also written as the frontmatter name.
function make_skill() {
    local name="$1"
    local skill_dir="${FIXTURE_ROOT}/skills/${name}"

    mkdir -p "${skill_dir}"
    printf -- '---\nname: %s\ndescription: d\n---\n' "${name}" > "${skill_dir}/SKILL.md"
}

@test "[common] an allowed domain passes" {
    make_skill shunk031-herdr-orchestrate-workers
    make_skill shunk031-shellscript-shdoc-docs

    run "${CHECKER}"
    [ "${status}" -eq 0 ]
}

@test "[common] a domain outside the allowlist is rejected" {
    make_skill shunk031-orchestrate-things

    run "${CHECKER}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *'uses domain orchestrate'* ]]
}

@test "[common] a domain with no topic after it is rejected" {
    make_skill shunk031-github

    run "${CHECKER}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *'is not named shunk031-<domain>-<topic>'* ]]
}

@test "[common] the document-level writing skill is the only one-part exception" {
    make_skill shunk031-writing

    run "${CHECKER}"
    [ "${status}" -eq 0 ]

    make_skill shunk031-editing

    run "${CHECKER}"
    [ "${status}" -eq 1 ]
    [[ "${output}" == *'skills/shunk031-editing is not named shunk031-<domain>-<topic>'* ]]
}

@test "[common] a skill without the owner prefix is out of scope" {
    make_skill vendor-orchestrate-things

    run "${CHECKER}"
    [ "${status}" -eq 0 ]
}

@test "[common] every allowed domain is accepted" {
    make_skill shunk031-codex-a
    make_skill shunk031-github-a
    make_skill shunk031-herdr-a
    make_skill shunk031-manage-a
    make_skill shunk031-python-a
    make_skill shunk031-research-a
    make_skill shunk031-shellscript-a

    run "${CHECKER}"
    [ "${status}" -eq 0 ]
}

@test "[common] the allowlist matches the domains the tree actually uses" {
    # The check is only as good as its list. A rename wave that adds a domain
    # without widening the allowlist fails here rather than in pre-commit.
    local skill_dir name
    for skill_dir in "${BATS_TEST_DIRNAME}"/../../skills/*/; do
        name="$(basename -- "${skill_dir%/}")"
        case "${name}" in
        *-workspace) continue ;;
        esac
        make_skill "${name}"
    done

    run "${CHECKER}"
    [ "${status}" -eq 0 ]
}
