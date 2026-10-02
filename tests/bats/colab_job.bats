#!/usr/bin/env bats

# Behaviour tests for the Colab job wrapper. `timeout` and `curl` are stubbed:
# the stub `timeout` drops its options and runs the command, and the stub
# `curl` records its arguments instead of unassigning anything.

readonly JOB_SCRIPT="${BATS_TEST_DIRNAME}/../../skills/colab/shunk031-colab-uv-training/scripts/colab-job.sh"

function setup() {
    STUB_BIN="${BATS_TEST_TMPDIR}/bin"
    PERSIST="${BATS_TEST_TMPDIR}/persist"
    CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
    export CURL_LOG
    export COLAB_JOB_WORK_ROOT="${BATS_TEST_TMPDIR}/work"
    export TBE_RUNTIME_ADDR='runtime.test:8080'
    mkdir -p "${STUB_BIN}"

    cat > "${STUB_BIN}/timeout" << 'EOF'
#!/usr/bin/env bash
while [ "${1#-}" != "$1" ]; do shift; done
shift
exec "$@"
EOF
    cat > "${STUB_BIN}/curl" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CURL_LOG}"
EOF
    chmod +x "${STUB_BIN}/timeout" "${STUB_BIN}/curl"
    export PATH="${STUB_BIN}:${PATH}"
}

@test "[common] a successful job persists its log, artifacts, and exit code, then releases the VM" {
    mkdir -p "${BATS_TEST_TMPDIR}/ckpt"
    printf 'weights\n' > "${BATS_TEST_TMPDIR}/ckpt/last.ckpt"

    run "${JOB_SCRIPT}" --job fit --persist-dir "${PERSIST}" --artifact "${BATS_TEST_TMPDIR}/ckpt" -- echo trained
    [ "${status}" -eq 0 ]
    [[ "${output}" == *trained* ]]
    [ "$(cat "${PERSIST}/exit_code")" = 0 ]
    grep -q trained "${PERSIST}/job.log"
    [ -f "${PERSIST}/ckpt/last.ckpt" ]
    [ "$(cat "${CURL_LOG}")" = '-fsS -X POST http://runtime.test:8080/unassign' ]
}

@test "[common] a failing job keeps its exit code and still releases the VM" {
    run "${JOB_SCRIPT}" --job fit --persist-dir "${PERSIST}" -- sh -c 'echo boom; exit 3'
    [ "${status}" -eq 3 ]
    [ "$(cat "${PERSIST}/exit_code")" = 3 ]
    grep -q boom "${PERSIST}/job.log"
    [ -s "${CURL_LOG}" ]
}

@test "[common] --no-release keeps the VM assigned" {
    run "${JOB_SCRIPT}" --job fit --persist-dir "${PERSIST}" --no-release -- true
    [ "${status}" -eq 0 ]
    [ ! -e "${CURL_LOG}" ]
    [[ "${output}" == *'self-release disabled'* ]]
}

@test "[common] a missing TBE_RUNTIME_ADDR warns instead of releasing" {
    unset TBE_RUNTIME_ADDR
    run "${JOB_SCRIPT}" --job fit --persist-dir "${PERSIST}" -- true
    [ "${status}" -eq 0 ]
    [ ! -e "${CURL_LOG}" ]
    [[ "${output}" == *'TBE_RUNTIME_ADDR is unset'* ]]
}

@test "[common] a failed copy keeps the VM so the results are not lost" {
    mkdir -p "${PERSIST}"
    run "${JOB_SCRIPT}" --job fit --persist-dir "${PERSIST}" -- sh -c "chmod 500 '${PERSIST}'"
    chmod 700 "${PERSIST}"
    [ "${status}" -eq 0 ]
    [ ! -e "${CURL_LOG}" ]
    [[ "${output}" == *'not releasing the VM'* ]]
}

@test "[common] the env file reaches the command and is deleted before it runs" {
    local env_file="${BATS_TEST_TMPDIR}/job.env"
    printf 'HF_TOKEN=secret-value\n' > "${env_file}"

    run "${JOB_SCRIPT}" --job fit --persist-dir "${PERSIST}" --env-file "${env_file}" -- sh -c "test -n \"\${HF_TOKEN}\" && test ! -e '${env_file}' && echo env-ok"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *env-ok* ]]
    [[ "${output}" != *secret-value* ]]
}

@test "[common] a Drive path is refused while Drive is not mounted" {
    [ ! -d /content/drive/MyDrive ] || skip 'Google Drive is mounted on this host'

    run "${JOB_SCRIPT}" --job fit -- true
    [ "${status}" -eq 2 ]
    [[ "${output}" == *'Google Drive is not mounted'* ]]
    [ ! -e "${COLAB_JOB_WORK_ROOT}" ]
}

@test "[common] a missing command or job name is a usage error" {
    run "${JOB_SCRIPT}" --job fit --persist-dir "${PERSIST}"
    [ "${status}" -eq 2 ]

    run "${JOB_SCRIPT}" --persist-dir "${PERSIST}" -- true
    [ "${status}" -eq 2 ]

    run "${JOB_SCRIPT}" --job ../escape --persist-dir "${PERSIST}" -- true
    [ "${status}" -eq 2 ]
}
