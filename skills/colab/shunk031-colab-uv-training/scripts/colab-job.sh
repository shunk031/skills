#!/usr/bin/env bash

# @file skills/colab/shunk031-colab-uv-training/scripts/colab-job.sh
# @brief Internal job wrapper invoked by colab-gpu-run on a Colab VM.
# @description
#   The launcher uploads this wrapper and invokes it in the same command that
#   allocated the GPU. Do not run it directly. It clears Colab's inherited
#   Python overrides before loading the optional `--env-file`, allowing its
#   explicit values to reach the command. It runs
#   the command under a hard `timeout` and tees its output to
#   `<work>/logs/job.log`. While the job runs, a background loop uploads the
#   log directory and every `--sync-path` to a Hub repository each interval; a
#   failed upload is logged and the job continues. On every exit, success or
#   failure, it writes the exit code into the log directory, uploads everything
#   once more, and asks the runtime to unassign itself through
#   `TBE_RUNTIME_ADDR`, the same call `google.colab.runtime.unassign()` makes.
#
#   Paths land in the repository as `<prefix>/logs/<job>` and
#   `<prefix>/<basename>`, so segments of one run can share a prefix.
#   The token file is read and deleted before the job starts, and the token is
#   passed only to the uploader. An upload that fails before the job starts
#   aborts the run. When the final upload fails, the VM is kept rather than
#   released: the local copies are the only ones left, and the agent's own
#   `colab stop` still bounds cost.
# @option --job NAME Job id; names the local work directory and the default prefix (required).
# @option --hub-repo REPO Hub repository that receives the results, such as `<user>/colab-jobs` (required).
# @option --hub-repo-type TYPE Hub repository type (default: `model`).
# @option --hub-prefix PATH Folder in the repository for this job (default: the job id).
# @option --hub-token-file PATH File holding a Hub token; read and deleted at startup.
# @option --sync-path PATH File or directory uploaded each interval and at exit; repeatable.
# @option --sync-interval DURATION Seconds between uploads, with an optional `s`, `m`, or `h` suffix (default: `15m`).
# @option --ttl DURATION Hard limit passed to `timeout`, such as `11h` (default: `11h`).
# @option --env-file PATH `KEY=VALUE` file exported to the command and deleted before it runs.
# @arg $@ The command to run, after `--`.
# @exitcode 2 When the arguments are invalid or the first upload fails.
# @exitcode * Otherwise the command's exit code; 124 when `timeout` stopped it.
set -Eeuo pipefail

readonly USAGE='usage: colab-job.sh --job NAME --hub-repo REPO [--hub-repo-type TYPE] [--hub-prefix PATH] [--hub-token-file PATH] [--sync-path PATH]... [--sync-interval DURATION] [--ttl DURATION] [--env-file PATH] -- COMMAND [ARGS...]'

job=''
hub_repo=''
hub_repo_type='model'
hub_prefix=''
hub_token_file=''
hf_token=''
sync_interval='15m'
sync_seconds=0
ttl='11h'
env_file=''
sync_paths=()
hf_cmd=()
work_dir=''
log_dir=''
stop_file=''
sync_pid=''

# @description Print a prefixed message to stderr.
# @arg $1 message The message.
function say() {
    printf 'colab-job: %s\n' "$1" >&2
}

# @description Print the usage line and exit with status 2.
function usage_error() {
    printf '%s\n' "${USAGE}" >&2
    exit 2
}

# @description Upload one local file or directory to the Hub repository.
# @arg $1 path The local path.
# @arg $2 path_in_repo The destination inside the repository.
function hub_upload() {
    local token_env=()
    if [ -n "${hf_token}" ]; then
        token_env=("HF_TOKEN=${hf_token}")
    fi

    # Colab's PYTHONPATH and UV_SYSTEM_PYTHON would leak into the uploader's interpreter.
    env -u PYTHONPATH -u UV_SYSTEM_PYTHON ${token_env[@]+"${token_env[@]}"} \
        "${hf_cmd[@]}" upload "${hub_repo}" "$1" "$2" --repo-type "${hub_repo_type}" --private --quiet > /dev/null
}

# @description Upload the log directory and every existing sync path.
# @exitcode 1 When any upload failed.
function upload_all() {
    local failed=0
    local path

    hub_upload "${log_dir}" "${hub_prefix}/logs/${job}" || failed=1
    for path in ${sync_paths[@]+"${sync_paths[@]}"}; do
        [ -e "${path}" ] || continue
        hub_upload "${path}" "${hub_prefix}/$(basename -- "${path}")" || failed=1
    done

    return "${failed}"
}

# @description Upload every interval until the stop file appears.
# @description
#   Sleeping one second at a time lets the wrapper stop the loop between
#   uploads instead of killing it in the middle of a commit.
function sync_loop() {
    local waited=0
    while [ ! -e "${stop_file}" ]; do
        sleep 1
        waited=$((waited + 1))
        [ "${waited}" -ge "${sync_seconds}" ] || continue

        waited=0
        upload_all || say "warning: periodic upload to ${hub_repo} failed; the job continues"
    done
}

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
# @description Stop the sync loop, upload the results a final time, then release the VM.
# @description
#   Runs as the EXIT trap, so it sees the job's exit status in `$?` and exits
#   with that same status.
function finish() {
    local status=$?
    local uploaded=1

    trap - EXIT
    : > "${stop_file}"
    if [ -n "${sync_pid}" ]; then
        wait "${sync_pid}" || true
    fi

    printf '%s\n' "${status}" > "${log_dir}/exit_code"
    say "${job} finished with exit code ${status}"
    if upload_all; then
        say "results uploaded to ${hub_repo}/${hub_prefix}"
    else
        say "final upload to ${hub_repo} failed"
        uploaded=0
    fi

    if [ "${uploaded}" -eq 0 ]; then
        say "not releasing the VM: results exist only under ${work_dir}"
    elif [ -z "${TBE_RUNTIME_ADDR:-}" ]; then
        say 'warning: TBE_RUNTIME_ADDR is unset; release the VM with colab stop'
    else
        say 'releasing the VM'
        curl -fsS -X POST "http://${TBE_RUNTIME_ADDR}/unassign" > /dev/null ||
            say 'warning: self-release failed; release the VM with colab stop'
    fi

    exit "${status}"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
    --job | --hub-repo | --hub-repo-type | --hub-prefix | --hub-token-file | --sync-path | --sync-interval | --ttl | --env-file)
        [ "$#" -ge 2 ] || usage_error
        case "$1" in
        --job) job="$2" ;;
        --hub-repo) hub_repo="$2" ;;
        --hub-repo-type) hub_repo_type="$2" ;;
        --hub-prefix) hub_prefix="$2" ;;
        --hub-token-file) hub_token_file="$2" ;;
        --sync-path) sync_paths+=("$2") ;;
        --sync-interval) sync_interval="$2" ;;
        --ttl) ttl="$2" ;;
        --env-file) env_file="$2" ;;
        esac
        shift 2
        ;;
    --help)
        printf '%s\n' "${USAGE}"
        exit 0
        ;;
    --)
        shift
        break
        ;;
    *) usage_error ;;
    esac
done

[ -n "${job}" ] && [ -n "${hub_repo}" ] && [ "$#" -gt 0 ] || usage_error
case "${job}" in
*/* | .*) usage_error ;;
esac

[[ "${sync_interval}" =~ ^[1-9][0-9]*[smh]?$ ]] || usage_error
case "${sync_interval}" in
*h) sync_seconds=$((${sync_interval%h} * 3600)) ;;
*m) sync_seconds=$((${sync_interval%m} * 60)) ;;
*) sync_seconds="${sync_interval%s}" ;;
esac

hub_prefix="${hub_prefix:-${job}}"
if command -v hf > /dev/null 2>&1; then
    hf_cmd=(hf)
else
    hf_cmd=(uvx --from huggingface_hub hf)
fi

if [ -n "${hub_token_file}" ]; then
    if ! hf_token="$(cat -- "${hub_token_file}")"; then
        say "cannot read ${hub_token_file}"
        exit 2
    fi
    rm -f -- "${hub_token_file}"
fi

work_dir="${COLAB_JOB_WORK_ROOT:-/content/colab-jobs}/${job}"
log_dir="${work_dir}/logs"
stop_file="${work_dir}/.sync-stop"
mkdir -p "${log_dir}"
rm -f -- "${stop_file}"

unset UV_SYSTEM_PYTHON PYTHONPATH MPLBACKEND
if [ -n "${env_file}" ]; then
    set -a
    # shellcheck source=/dev/null
    . "${env_file}"
    set +a
    rm -f -- "${env_file}"
fi

printf 'colab-job: starting %s (limit %s)\n' "${job}" "${ttl}" >> "${log_dir}/job.log"
if ! upload_all; then
    say "cannot upload to ${hub_repo}; check the repository and token before running the job"
    exit 2
fi

trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

sync_loop &
sync_pid=$!

say "starting ${job} (limit ${ttl}); log at ${log_dir}/job.log, syncing every ${sync_interval}"
set +e
timeout --kill-after=120 "${ttl}" "$@" 2>&1 | tee -a "${log_dir}/job.log"
job_status="${PIPESTATUS[0]}"
set -e

exit "${job_status}"
