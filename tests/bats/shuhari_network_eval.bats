#!/usr/bin/env bats

# The wrapper resolves every target against the repository root derived from
# its own location, so setup copies it into a disposable repository populated
# with synthetic skills. That keeps these tests valid no matter which real
# skills currently carry evals/evals.json.

# @description Create a synthetic eval-bearing skill inside the fixture repository.
# @description
#   The wrapper only tests that `evals/evals.json` exists, and the Shuhari
#   stub never reads it, so a minimal file is enough.
# @arg $1 fixture_root Fixture repository root.
# @arg $2 name Skill directory name.
# @stdout The absolute path of the created skill's `SKILL.md`.
function make_fixture_skill() {
    local fixture_root="$1"
    local name="$2"
    local skill_dir="${fixture_root}/skills/${name}"
    mkdir -p "${skill_dir}/evals"
    printf '# %s\n' "${name}" > "${skill_dir}/SKILL.md"
    printf '{"skill_name": "%s", "evals": []}\n' "${name}" > "${skill_dir}/evals/evals.json"
    printf '%s\n' "${skill_dir}/SKILL.md"
}

# @description Build the fixture repository and install fake mise, Shuhari, and uv commands that record evaluation policy without making model calls.
function setup() {
    local fake_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${fake_bin}"
    export SHUHARI_POLICY_LOG="${BATS_TEST_TMPDIR}/policy"

    local fixture_root="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${fixture_root}/scripts"
    cp "${BATS_TEST_DIRNAME}/../../scripts/shuhari_staged_targets.sh" \
        "${fixture_root}/scripts/shuhari_staged_targets.sh"
    WRAPPER="${fixture_root}/scripts/shuhari_staged_targets.sh"

    NETWORK_TARGET="$(make_fixture_skill "${fixture_root}" network-required-fixture)"
    touch "${NETWORK_TARGET%/SKILL.md}/evals/network-required"
    OFFLINE_TARGET="$(make_fixture_skill "${fixture_root}" offline-fixture)"

    cat > "${fake_bin}/mise" << EOF
#!/usr/bin/env bash
if [ "\$1" = "which" ] && [ "\$2" = "shuhari" ]; then
    printf '%s\n' "${fake_bin}/shuhari"
    exit 0
fi
exit 1
EOF

    cat > "${fake_bin}/shuhari" << 'EOF'
#!/usr/bin/env bash
model=''
reasoning_effort=''
judge_model=''
judge_reasoning_effort=''
network=false
sandbox=default
while [ "$#" -gt 0 ]; do
    case "$1" in
    --model)
        shift
        model="$1"
        ;;
    --reasoning-effort)
        shift
        reasoning_effort="$1"
        ;;
    --judge-model)
        shift
        judge_model="$1"
        ;;
    --judge-reasoning-effort)
        shift
        judge_reasoning_effort="$1"
        ;;
    --network | --network=true)
        network=true
        ;;
    --sandbox)
        shift
        sandbox="$1"
        ;;
    esac
    shift
done
printf 'model=%s\nreasoning_effort=%s\njudge_model=%s\njudge_reasoning_effort=%s\nnetwork=%s\nsandbox=%s\n' \
    "${model}" "${reasoning_effort}" "${judge_model}" \
    "${judge_reasoning_effort}" "${network}" "${sandbox}" > "${SHUHARI_POLICY_LOG}"
EOF

    cat > "${fake_bin}/uv" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF

    chmod +x "${fake_bin}/mise" "${fake_bin}/shuhari" "${fake_bin}/uv"
    PATH="${fake_bin}:${PATH}"
    export PATH
}

@test "[common] network-required evaluations use gpt-5.5 medium with network" {
    run "${WRAPPER}" eval ignored "${NETWORK_TARGET}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "" ]
    grep -Fx 'model=gpt-5.5' "${SHUHARI_POLICY_LOG}"
    grep -Fx 'reasoning_effort=medium' "${SHUHARI_POLICY_LOG}"
    grep -Fx 'judge_model=gpt-5.6-sol' "${SHUHARI_POLICY_LOG}"
    grep -Fx 'judge_reasoning_effort=medium' "${SHUHARI_POLICY_LOG}"
    grep -Fx 'network=true' "${SHUHARI_POLICY_LOG}"
    grep -Fx 'sandbox=default' "${SHUHARI_POLICY_LOG}"
}

@test "[common] ordinary evaluations keep the default offline model policy" {
    run "${WRAPPER}" eval ignored "${OFFLINE_TARGET}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "" ]
    grep -Fx 'model=gpt-5.6-luna' "${SHUHARI_POLICY_LOG}"
    grep -Fx 'reasoning_effort=high' "${SHUHARI_POLICY_LOG}"
    grep -Fx 'judge_model=gpt-5.6-sol' "${SHUHARI_POLICY_LOG}"
    grep -Fx 'judge_reasoning_effort=medium' "${SHUHARI_POLICY_LOG}"
    grep -Fx 'network=false' "${SHUHARI_POLICY_LOG}"
    grep -Fx 'sandbox=default' "${SHUHARI_POLICY_LOG}"
}
