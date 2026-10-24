#!/usr/bin/env bats

readonly RUN_FAILURE_WATCH_SCRIPT="${BATS_TEST_DIRNAME}/../../skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-run-failure-watch.sh"

function setup() {
    export RUNNER_STATE_DIR="${BATS_TEST_TMPDIR}/runner-state"
    mkdir -p "${RUNNER_STATE_DIR}"
    unset WATCH_IGNORE || true
}

function write_failed_state() {
    local path="$1"
    local name="$2"
    local age_seconds="${3:-0}"
    python3 - "${path}" "${name}" "${age_seconds}" << 'PYTHON'
import json
import sys
from datetime import datetime, timedelta, timezone

path, name, age_seconds = sys.argv[1:]
finished = datetime.now(timezone.utc) - timedelta(seconds=int(age_seconds))
with open(path, "w", encoding="utf-8") as state:
    json.dump(
        {"jobs": {name: {"status": "failed", "finished_at_utc": finished.isoformat(), "exit_code": 17}}},
        state,
    )
PYTHON
}

function age_file_by_hours() {
    local path="$1"
    local hours="$2"
    python3 - "${path}" "${hours}" << 'PYTHON'
import os
import sys
import time

path, hours = sys.argv[1:]
mtime = time.time() - int(hours) * 60 * 60
os.utime(path, (mtime, mtime))
PYTHON
}

function write_completed_state() {
    printf '%s\n' '{"jobs":{"complete":{"status":"completed"}}}' > "$1"
}

function write_running_state() {
    local path="$1"
    local name="$2"
    local pid="$3"
    printf '{"jobs":{"%s":{"status":"running","pid":%s}}}\n' "$name" "$pid" > "${path}"
}

@test "[common] runner watcher validates its source and polling arguments" {
    run "${RUN_FAILURE_WATCH_SCRIPT}" --once

    [ "${status}" -eq 2 ]
    [[ "${output}" == *'provide at least one --state-glob'* ]]

    run "${RUN_FAILURE_WATCH_SCRIPT}" \
        --remote-state-glob '/remote/state/*.json' \
        --once

    [ "${status}" -eq 2 ]
    [[ "${output}" == *'--remote-state-glob requires --remote-host'* ]]

    run "${RUN_FAILURE_WATCH_SCRIPT}" \
        --state-glob "${RUNNER_STATE_DIR}/*.json" \
        --interval-seconds 0 \
        --once

    [ "${status}" -eq 2 ]
    [[ "${output}" == *'--interval-seconds must be a positive integer'* ]]
}

@test "[common] runner watcher alerts on a recent failed job" {
    write_failed_state "${RUNNER_STATE_DIR}/recent.json" fresh-job

    run "${RUN_FAILURE_WATCH_SCRIPT}" --state-glob "${RUNNER_STATE_DIR}/recent.json" --once

    [ "${status}" -eq 3 ]
    [[ "${output}" == *'ALERT LOCAL fresh-job status=failed exit=17'* ]]
}

@test "[common] runner watcher ignores failures older than three hours" {
    write_failed_state "${RUNNER_STATE_DIR}/old-job.json" old-job 14400

    run "${RUN_FAILURE_WATCH_SCRIPT}" --state-glob "${RUNNER_STATE_DIR}/old-job.json" --once

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'OK: checked 1 local and 0 remote recent state file(s)'* ]]
    [[ "${output}" != *ALERT* ]]
}

@test "[common] runner watcher filters state files older than twelve hours" {
    write_failed_state "${RUNNER_STATE_DIR}/stale-failure.json" stale-file-job
    age_file_by_hours "${RUNNER_STATE_DIR}/stale-failure.json" 13
    write_completed_state "${RUNNER_STATE_DIR}/recent.json"

    run "${RUN_FAILURE_WATCH_SCRIPT}" --state-glob "${RUNNER_STATE_DIR}/*.json" --once

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'OK: checked 1 local and 0 remote recent state file(s)'* ]]
    [[ "${output}" != *stale-file-job* ]]
}

@test "[common] runner watcher honors WATCH_IGNORE" {
    write_failed_state "${RUNNER_STATE_DIR}/ignored.json" ignored-job
    export WATCH_IGNORE=ignored-job

    run "${RUN_FAILURE_WATCH_SCRIPT}" --state-glob "${RUNNER_STATE_DIR}/ignored.json" --once

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'OK: checked 1 local and 0 remote recent state file(s)'* ]]
    [[ "${output}" != *ignored-job* ]]
}

@test "[common] runner watcher alerts when a running job PID is gone" {
    write_running_state "${RUNNER_STATE_DIR}/running.json" missing-process 99999999

    run "${RUN_FAILURE_WATCH_SCRIPT}" --state-glob "${RUNNER_STATE_DIR}/running.json" --once

    [ "${status}" -eq 3 ]
    [[ "${output}" == *'ALERT LOCAL missing-process marked running but PID 99999999 is gone'* ]]
}

@test "[common] runner watcher preflight rejects an empty configured remote source" {
    local stub_bin="${BATS_TEST_TMPDIR}/runner-bin"
    mkdir -p "${stub_bin}"
    cat > "${stub_bin}/ssh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${stub_bin}/ssh"
    export PATH="${stub_bin}:${PATH}"
    write_completed_state "${RUNNER_STATE_DIR}/local.json"

    run "${RUN_FAILURE_WATCH_SCRIPT}" \
        --state-glob "${RUNNER_STATE_DIR}/local.json" \
        --remote-host test-host \
        --remote-state-glob '/remote/state/*.json' \
        --once

    [ "${status}" -eq 1 ]
    [[ "${output}" == *'no recent remote state files matched the configured globs'* ]]
    [[ "${output}" != *'OK:'* ]]
}
