#!/usr/bin/env bats

# Behaviour tests for the Colab job wrapper. `timeout`, `hf`, and `curl` are
# stubbed: the stub `timeout` drops its options and runs the command, the stub
# `hf` copies uploads into a local directory standing in for the Hub repository
# and records the token it saw, and the stub `curl` records its arguments
# instead of unassigning anything.

readonly JOB_SCRIPT="${BATS_TEST_DIRNAME}/../../skills/colab/shunk031-colab-uv-training/scripts/colab-job.sh"

function setup() {
    STUB_BIN="${BATS_TEST_TMPDIR}/bin"
    export HUB="${BATS_TEST_TMPDIR}/hub"
    export HF_LOG="${BATS_TEST_TMPDIR}/hf.log"
    export HF_FAIL="${BATS_TEST_TMPDIR}/hf-fail"
    export CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
    export COLAB_JOB_WORK_ROOT="${BATS_TEST_TMPDIR}/work"
    export TBE_RUNTIME_ADDR='runtime.test:8080'
    mkdir -p "${STUB_BIN}" "${HUB}"

    cat > "${STUB_BIN}/timeout" << 'EOF'
#!/usr/bin/env bash
while [ "${1#-}" != "$1" ]; do shift; done
shift
exec "$@"
EOF
    cat > "${STUB_BIN}/hf" << 'EOF'
#!/usr/bin/env bash
[ "$1" = upload ] || exit 9
printf '%s %s token=%s\n' "$3" "$4" "${HF_TOKEN:-}" >> "${HF_LOG}"
[ ! -e "${HF_FAIL}" ] || exit 1
if [ -d "$3" ]; then
    mkdir -p "${HUB}/$4"
    cp -R "$3/." "${HUB}/$4/"
else
    mkdir -p "$(dirname "${HUB}/$4")"
    cp "$3" "${HUB}/$4"
fi
EOF
    cat > "${STUB_BIN}/curl" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CURL_LOG}"
EOF
    chmod +x "${STUB_BIN}/timeout" "${STUB_BIN}/hf" "${STUB_BIN}/curl"
    export PATH="${STUB_BIN}:${PATH}"
}

@test "[common] a successful job uploads logs, sync paths, and exit code, then releases the VM" {
    mkdir -p "${BATS_TEST_TMPDIR}/out/ckpt"
    printf 'weights\n' > "${BATS_TEST_TMPDIR}/out/ckpt/last.ckpt"

    run "${JOB_SCRIPT}" --job fit --hub-repo user/colab-jobs --hub-prefix proj/fit \
        --sync-path "${BATS_TEST_TMPDIR}/out/ckpt" -- echo trained
    [ "${status}" -eq 0 ]
    [[ "${output}" == *trained* ]]
    [ "$(cat "${HUB}/proj/fit/logs/fit/exit_code")" = 0 ]
    grep -q trained "${HUB}/proj/fit/logs/fit/job.log"
    [ -f "${HUB}/proj/fit/ckpt/last.ckpt" ]
    [ "$(cat "${CURL_LOG}")" = '-fsS -X POST http://runtime.test:8080/unassign' ]
}

@test "[common] a failing job keeps its exit code and still releases the VM" {
    run "${JOB_SCRIPT}" --job fit --hub-repo user/colab-jobs -- sh -c 'echo boom; exit 3'
    [ "${status}" -eq 3 ]
    [ "$(cat "${HUB}/fit/logs/fit/exit_code")" = 3 ]
    grep -q boom "${HUB}/fit/logs/fit/job.log"
    [ -s "${CURL_LOG}" ]
}

@test "[common] the sync loop uploads while the job runs" {
    run "${JOB_SCRIPT}" --job fit --hub-repo user/colab-jobs --sync-interval 1 -- sleep 3
    [ "${status}" -eq 0 ]
    # One upload before the job, at least one from the loop, and the final one.
    [ "$(grep -c '/logs fit/logs/fit' "${HF_LOG}")" -ge 3 ]
}

@test "[common] --no-release keeps the VM assigned" {
    run "${JOB_SCRIPT}" --job fit --hub-repo user/colab-jobs --no-release -- true
    [ "${status}" -eq 0 ]
    [ ! -e "${CURL_LOG}" ]
    [[ "${output}" == *'self-release disabled'* ]]
}

@test "[common] a missing TBE_RUNTIME_ADDR warns instead of releasing" {
    unset TBE_RUNTIME_ADDR
    run "${JOB_SCRIPT}" --job fit --hub-repo user/colab-jobs -- true
    [ "${status}" -eq 0 ]
    [ ! -e "${CURL_LOG}" ]
    [[ "${output}" == *'TBE_RUNTIME_ADDR is unset'* ]]
}

@test "[common] a failed final upload keeps the VM so the results are not lost" {
    run "${JOB_SCRIPT}" --job fit --hub-repo user/colab-jobs -- touch "${HF_FAIL}"
    [ "${status}" -eq 0 ]
    [ ! -e "${CURL_LOG}" ]
    [[ "${output}" == *'not releasing the VM'* ]]
}

@test "[common] a failed first upload aborts before the job runs" {
    touch "${HF_FAIL}"
    run "${JOB_SCRIPT}" --job fit --hub-repo user/colab-jobs -- touch "${BATS_TEST_TMPDIR}/ran"
    [ "${status}" -eq 2 ]
    [ ! -e "${BATS_TEST_TMPDIR}/ran" ]
    [ ! -e "${CURL_LOG}" ]
}

@test "[common] the token reaches only the uploader and its file is deleted" {
    local token_file="${BATS_TEST_TMPDIR}/hf-token"
    printf 'hf_secret\n' > "${token_file}"

    run "${JOB_SCRIPT}" --job fit --hub-repo user/colab-jobs --hub-token-file "${token_file}" -- \
        sh -c "test -z \"\${HF_TOKEN:-}\" && test ! -e '${token_file}' && echo token-hidden"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *token-hidden* ]]
    [[ "${output}" != *hf_secret* ]]
    [ "$(grep -c 'token=hf_secret$' "${HF_LOG}")" -eq "$(wc -l < "${HF_LOG}")" ]
}

@test "[common] the env file reaches the command and is deleted before it runs" {
    local env_file="${BATS_TEST_TMPDIR}/job.env"
    printf 'WANDB_API_KEY=secret-value\n' > "${env_file}"

    run "${JOB_SCRIPT}" --job fit --hub-repo user/colab-jobs --env-file "${env_file}" -- \
        sh -c "test -n \"\${WANDB_API_KEY}\" && test ! -e '${env_file}' && echo env-ok"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *env-ok* ]]
    [[ "${output}" != *secret-value* ]]
}

@test "[common] invalid arguments are usage errors" {
    run "${JOB_SCRIPT}" --job fit --hub-repo user/colab-jobs
    [ "${status}" -eq 2 ]

    run "${JOB_SCRIPT}" --job fit -- true
    [ "${status}" -eq 2 ]

    run "${JOB_SCRIPT}" --job ../escape --hub-repo user/colab-jobs -- true
    [ "${status}" -eq 2 ]

    run "${JOB_SCRIPT}" --job fit --hub-repo user/colab-jobs --sync-interval 0 -- true
    [ "${status}" -eq 2 ]
    [ ! -e "${HF_LOG}" ]
}
