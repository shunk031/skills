#!/usr/bin/env bats

# `results.json` is what the documentation site reads to say what a skill
# measurably changes. It is derived from a Shuhari run, and the run's workspace
# is gitignored, so it can only be written on the machine that ran the gate.
#
# Leaving that to a person meant forgetting it. Two gates were run the day the
# recorder was written and one `results.json` exists, because the second run
# happened in a worktree that was merged without recording. These tests cover
# the recorder itself and its wiring into the gate.

readonly RECORDER="./scripts/record_eval_results.py"
readonly WRAPPER="./scripts/shuhari_staged_targets.sh"

# @description Build a skill directory with a completed run beside it.
# @arg $1 name The skill name.
# @arg $2 iteration The iteration directory to create.
# @arg $3 with_rate The with-skill pass rate to record.
function make_run() {
    local name="$1" iteration="$2" with_rate="$3"
    local skill="${BATS_TEST_TMPDIR}/skills/${name}"
    local run="${BATS_TEST_TMPDIR}/skills/${name}-workspace/${iteration}"

    mkdir -p "${skill}/evals" "${run}"
    printf -- '---\nname: %s\ndescription: d\n---\n' "${name}" > "${skill}/SKILL.md"
    printf '{"skill_name":"%s","evals":[]}\n' "${name}" > "${skill}/evals/evals.json"

    cat > "${run}/manifest.json" << EOF
{"created_at":"2026-01-02T03:04:05Z","config":{"model":"m","reasoning_effort":"high","trials":3,"network":false},"agent_identity":{"agent":"codex"}}
EOF
    cat > "${run}/benchmark.json" << EOF
{"run_summary":{"with_skill":{"pass_rate":{"mean":${with_rate}},"tokens":{"mean":1},"time_seconds":{"mean":1}},
"without_skill":{"pass_rate":{"mean":0.25},"tokens":{"mean":1},"time_seconds":{"mean":1}}},
"assertion_analysis":[{"case_id":"c","assertion":"a","with_pass_rate":1,"without_pass_rate":0,"category":"x"}]}
EOF
}

@test "[common] the recorder writes the numbers a run produced" {
    make_run demo iteration-1 0.75

    run uv run --python 3.14.6 --no-project -- python "${RECORDER}" "${BATS_TEST_TMPDIR}/skills/demo"
    [ "${status}" -eq 0 ]

    local results="${BATS_TEST_TMPDIR}/skills/demo/evals/results.json"
    [ -f "${results}" ]
    run grep -F '"with_skill": 0.75' "${results}"
    [ "${status}" -eq 0 ]
}

@test "[common] an interrupted run does not shadow the last real one" {
    # A run killed before grading leaves a directory with no benchmark. Taking
    # the newest directory outright would publish nothing and lose the numbers
    # that exist.
    make_run demo iteration-1 0.75
    mkdir -p "${BATS_TEST_TMPDIR}/skills/demo-workspace/iteration-2"

    run uv run --python 3.14.6 --no-project -- python "${RECORDER}" "${BATS_TEST_TMPDIR}/skills/demo"
    [ "${status}" -eq 0 ]

    run grep -F '"with_skill": 0.75' "${BATS_TEST_TMPDIR}/skills/demo/evals/results.json"
    [ "${status}" -eq 0 ]
}

@test "[common] a skill with no completed run records nothing" {
    mkdir -p "${BATS_TEST_TMPDIR}/skills/demo/evals"
    printf -- '---\nname: demo\ndescription: d\n---\n' > "${BATS_TEST_TMPDIR}/skills/demo/SKILL.md"

    run uv run --python 3.14.6 --no-project -- python "${RECORDER}" "${BATS_TEST_TMPDIR}/skills/demo"
    [ "${status}" -eq 0 ]
    [ ! -f "${BATS_TEST_TMPDIR}/skills/demo/evals/results.json" ]
}

@test "[common] the gate records after a passing evaluation" {
    # The wiring, not the recorder: the wrapper must invoke it, or every gate
    # run leaves the site's numbers one run behind for as long as nobody
    # remembers to run it by hand.
    run grep -F 'record_eval_results.py' "${WRAPPER}"
    [ "${status}" -eq 0 ]
}
