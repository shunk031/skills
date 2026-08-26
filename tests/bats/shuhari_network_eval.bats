#!/usr/bin/env bats

readonly WRAPPER="./scripts/shuhari_staged_targets.sh"
readonly NETWORK_TARGET="skills/shunk031-research-before-implementation/SKILL.md"
readonly OFFLINE_TARGET="skills/shunk031-cgd-dev-identity/SKILL.md"

# @description Install fake mise, Shuhari, and uv commands that record evaluation policy without making model calls.
function setup() {
    local fake_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${fake_bin}"
    export SHUHARI_POLICY_LOG="${BATS_TEST_TMPDIR}/policy"

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
