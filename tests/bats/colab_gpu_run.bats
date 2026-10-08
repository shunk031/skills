#!/usr/bin/env bats

readonly LAUNCHER="${BATS_TEST_DIRNAME}/../../skills/colab/shunk031-colab-uv-training/scripts/colab-gpu-run"

function setup() {
    STUB_BIN="${BATS_TEST_TMPDIR}/bin"
    export COLAB_LOG="${BATS_TEST_TMPDIR}/colab.log"
    export COLAB_DRIVER_CAPTURE="${BATS_TEST_TMPDIR}/driver.py"
    export COLAB_STATUS_FILE="${BATS_TEST_TMPDIR}/status"
    export COLAB_STOP_LOG="${BATS_TEST_TMPDIR}/stops.log"
    export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
    export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
    mkdir -p "${STUB_BIN}" "${XDG_STATE_HOME}" "${TMPDIR}"
    : > "${COLAB_STATUS_FILE}"

    cat > "${STUB_BIN}/colab" << 'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "${COLAB_LOG}"
if [ "$1" = version ]; then
    printf 'Version: 0.7.4\n'
    exit 0
fi
if [ "$1" = --config ]; then
    config="$2"
    shift 2
else
    exit 90
fi
command="$1"
shift
case "${command}" in
version)
    printf 'Version: 0.7.4\n'
    ;;
new)
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --session) session="$2"; shift 2 ;;
        *) shift ;;
        esac
    done
    if [ "${COLAB_EXPECT_TOKEN_PREALLOC:-0}" = 1 ]; then
        token_preallocated=0
        for token_copy in "${TMPDIR:-/tmp}"/colab-gpu-run.*/hf-token; do
            if [ -f "${token_copy}" ]; then
                token_preallocated=1
                break
            fi
        done
        [ "${token_preallocated}" -eq 1 ] || exit 93
    fi
    mkdir -p "$(dirname "${config}")"
    if [ "${COLAB_SIMULATE_STATE_WRITE_FAILURE:-0}" = 1 ]; then
        PYTHONPATH= COLAB_GPU_HANDOFF_FILE= COLAB_GPU_HANDOFF_SESSION= python3 - "${COLAB_GPU_HANDOFF_FILE}" "${COLAB_GPU_HANDOFF_SESSION}" <<'PY'
import json
import sys

name = sys.argv[2]
session = {
    "name": name,
    "token": "runtime-token",
    "url": "https://runtime.example",
    "endpoint": f"endpoint-{name}",
    "variant": "GPU",
    "accelerator": "A100",
    "machine_shape": "STANDARD",
}
with open(sys.argv[1], "w", encoding="utf-8") as handoff:
    json.dump({"name": name, "session": session}, handoff)
PY
    else
        printf '{"%s":{"name":"%s","endpoint":"endpoint-%s"}}\n' "${session}" "${session}" "${session}" > "${config}"
    fi
    if [ "${COLAB_KILL_WATCHDOG_ON_NEW:-0}" = 1 ]; then
        for pid_file in "${XDG_STATE_HOME}"/colab-gpu-run/*/watchdog.pid; do
            [ -f "${pid_file}" ] || continue
            kill "$(cat "${pid_file}")" 2> /dev/null || true
        done
    fi
    if [ "${COLAB_FAIL_NEW_AFTER_ASSIGN:-0}" = 1 ]; then
        exit 37
    fi
    ;;
status)
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -s) session="$2"; shift 2 ;;
        *) shift ;;
        esac
    done
    if [ "$(cat "${COLAB_STATUS_FILE}")" = gone ]; then
        printf "[colab] Session '%s' not found.\n" "${session}"
    else
        printf '[%s] endpoint-%s | Hardware: A100 | Shape: Standard | Variant: GPU | Status: IDLE\n' "${session}" "${session}"
    fi
    ;;
upload)
    ;;
exec)
    driver=''
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -f) driver="$2"; shift 2 ;;
        *) shift ;;
        esac
    done
    cp "${driver}" "${COLAB_DRIVER_CAPTURE}"
    ;;
stop)
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -s) session="$2"; shift 2 ;;
        *) shift ;;
        esac
    done
    printf '%s\n' "${session}" >> "${COLAB_STOP_LOG}"
    printf 'gone\n' > "${COLAB_STATUS_FILE}"
    ;;
*)
    exit 92
    ;;
esac
EOF
    chmod +x "${STUB_BIN}/colab"
    export PATH="${STUB_BIN}:${PATH}"
}

function teardown() {
    local pid_file
    local pid
    for pid_file in "${XDG_STATE_HOME}"/colab-gpu-run/*/watchdog.pid; do
        [ -f "${pid_file}" ] || continue
        pid="$(cat "${pid_file}")"
        kill "${pid}" 2> /dev/null || true
    done
}

@test "preflight rejects an invalid Bash job before allocating a session" {
    local job="${BATS_TEST_TMPDIR}/broken.sh"
    printf 'if then\n' > "${job}"

    run "${LAUNCHER}" --gpu A100 --job fit --hub-repo user/jobs --job-script "${job}"

    [ "${status}" -eq 2 ]
    [ ! -s "${COLAB_LOG}" ]
}

@test "preflight rejects a missing token file before allocating a session" {
    local job="${BATS_TEST_TMPDIR}/job.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${job}"

    run "${LAUNCHER}" --gpu A100 --job fit --hub-repo user/jobs --job-script "${job}" --hub-token-file "${BATS_TEST_TMPDIR}/missing-token"

    [ "${status}" -eq 2 ]
    [ ! -s "${COLAB_LOG}" ]
}

@test "preflight rejects a local input reference before allocating a session" {
    local job="${BATS_TEST_TMPDIR}/job.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${job}"

    run "${LAUNCHER}" --gpu A100 --job fit --hub-repo user/jobs --job-script "${job}" --hub-input data=./data/train.csv

    [ "${status}" -eq 2 ]
    [ ! -s "${COLAB_LOG}" ]
}

@test "a successful launch watches the session, uploads serially, and starts colab-job.sh" {
    local job="${BATS_TEST_TMPDIR}/job.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${job}"

    run "${LAUNCHER}" --gpu A100 --job fit --hub-repo user/jobs --job-script "${job}" --hub-input train=hf://user/data/train --wall-timeout 43200 --colab-config "${BATS_TEST_TMPDIR}/sessions.json"

    [ "${status}" -eq 0 ]
    [ "$(grep -c ' new --session ' "${COLAB_LOG}")" -eq 1 ]
    [ "$(grep -c ' upload -s ' "${COLAB_LOG}")" -eq 2 ]
    [ "$(grep -c ' exec -s ' "${COLAB_LOG}")" -eq 1 ]
    local new_line
    local wrapper_upload_line
    local job_upload_line
    local exec_line
    new_line="$(grep -n ' new --session ' "${COLAB_LOG}" | cut -d: -f1)"
    wrapper_upload_line="$(grep -n ' upload -s .* /content/colab-job.sh$' "${COLAB_LOG}" | cut -d: -f1)"
    job_upload_line="$(grep -n ' upload -s .* /content/colab-user-job.sh$' "${COLAB_LOG}" | cut -d: -f1)"
    exec_line="$(grep -n ' exec -s ' "${COLAB_LOG}" | cut -d: -f1)"
    [ "${new_line}" -lt "${wrapper_upload_line}" ]
    [ "${wrapper_upload_line}" -lt "${job_upload_line}" ]
    [ "${job_upload_line}" -lt "${exec_line}" ]
    [[ "$(cat "${COLAB_DRIVER_CAPTURE}")" == *'/content/colab-job.sh'* ]]
    [[ "$(cat "${COLAB_DRIVER_CAPTURE}")" == *'--hub-input'* ]]
    [ -n "$(find "${XDG_STATE_HOME}/colab-gpu-run" -type f -name ready -print)" ]
}

@test "handoff keeps a post-assignment session watched when local state writing fails" {
    local job="${BATS_TEST_TMPDIR}/job.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${job}"
    export COLAB_FAIL_NEW_AFTER_ASSIGN=1
    export COLAB_SIMULATE_STATE_WRITE_FAILURE=1

    run "${LAUNCHER}" --gpu A100 --job fit --hub-repo user/jobs --job-script "${job}" --colab-config "${BATS_TEST_TMPDIR}/sessions.json"

    [ "${status}" -eq 37 ]
    [ "$(grep -c ' new --session ' "${COLAB_LOG}")" -eq 1 ]
    [ "$(grep -c ' upload -s ' "${COLAB_LOG}")" -eq 0 ]
    [ "$(grep -c ' exec -s ' "${COLAB_LOG}")" -eq 0 ]
    [ -n "$(find "${XDG_STATE_HOME}/colab-gpu-run" -type f -name ready -print)" ]
    [ -n "$(find "${XDG_STATE_HOME}/colab-gpu-run" -type f -name recovery.json -print)" ]
}

@test "if the watchdog dies after allocation the launcher stops only its verified session" {
    local job="${BATS_TEST_TMPDIR}/job.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${job}"
    export COLAB_KILL_WATCHDOG_ON_NEW=1

    run "${LAUNCHER}" --gpu A100 --job fit --hub-repo user/jobs --job-script "${job}" --colab-config "${BATS_TEST_TMPDIR}/sessions.json"

    [ "${status}" -eq 2 ]
    [ "$(wc -l < "${COLAB_STOP_LOG}" | tr -d '[:space:]')" -eq 1 ]
    [ "$(grep -c ' upload -s ' "${COLAB_LOG}")" -eq 0 ]
    [ "$(grep -c ' exec -s ' "${COLAB_LOG}")" -eq 0 ]
    [ "$(cat "${COLAB_STATUS_FILE}")" = gone ]
}

@test "the launcher can stop the handed-off session if its watchdog dies before state is saved" {
    local job="${BATS_TEST_TMPDIR}/job.sh"
    local expected_session
    printf '#!/usr/bin/env bash\nexit 0\n' > "${job}"
    export COLAB_KILL_WATCHDOG_ON_NEW=1
    export COLAB_SIMULATE_STATE_WRITE_FAILURE=1
    export COLAB_FAIL_NEW_AFTER_ASSIGN=1

    run "${LAUNCHER}" --gpu A100 --job fit --hub-repo user/jobs --job-script "${job}" --colab-config "${BATS_TEST_TMPDIR}/sessions.json"

    [ "${status}" -eq 37 ]
    [ "$(wc -l < "${COLAB_STOP_LOG}" | tr -d '[:space:]')" -eq 1 ]
    expected_session="$(sed -n 's/.*--session \(cgr-[[:xdigit:]]*\).*/\1/p' "${COLAB_LOG}" | head -n 1)"
    [ "$(cat "${COLAB_STOP_LOG}")" = "${expected_session}" ]
    [ "$(grep -c ' upload -s ' "${COLAB_LOG}")" -eq 0 ]
    [ "$(cat "${COLAB_STATUS_FILE}")" = gone ]
}

@test "a restricted token is uploaded for the wrapper and job and removed remotely" {
    local job="${BATS_TEST_TMPDIR}/job.sh"
    local token="${BATS_TEST_TMPDIR}/hf-token"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${job}"
    printf 'hf_secret\n' > "${token}"
    chmod 600 "${token}"
    export COLAB_EXPECT_TOKEN_PREALLOC=1

    run "${LAUNCHER}" --gpu A100 --job fit --hub-repo user/jobs --job-script "${job}" --hub-token-file "${token}" --colab-config "${BATS_TEST_TMPDIR}/sessions.json"

    [ "${status}" -eq 0 ]
    [ "$(grep -c ' upload -s ' "${COLAB_LOG}")" -eq 4 ]
    [[ "$(cat "${COLAB_DRIVER_CAPTURE}")" == *"/content/hf-job-token"* ]]
    [[ "$(cat "${COLAB_DRIVER_CAPTURE}")" != *'hf_secret'* ]]
    [ -f "${token}" ]
}
