#!/usr/bin/env bash

# @file skills/colab/shunk031-colab-uv-training/scripts/colab-job.sh
# @brief Run one long GPU job on a Colab VM, persist its results, then release the VM.
# @description
#   Upload this script to the Colab VM and run it from a busy kernel cell. It
#   runs the command under a hard `timeout`, tees its output to a log, and on
#   every exit, success or failure, copies the declared artifacts and the log to
#   a persistent directory, writes the exit code beside them, and asks the
#   runtime to unassign itself through `TBE_RUNTIME_ADDR`, the same call
#   `google.colab.runtime.unassign()` makes.
#
#   When any copy fails, the VM is kept rather than released: the local copies
#   are the only ones left, and the agent's own `colab stop` still bounds cost.
#   A persistent directory under `/content/drive` is refused unless Drive is
#   mounted, because `mkdir -p` would otherwise create a local directory that
#   vanishes with the VM.
# @option --job NAME Job name; names the work and persistent directories (required).
# @option --ttl DURATION Hard limit passed to `timeout`, such as `11h` (default: `11h`).
# @option --persist-dir DIR Where artifacts, log, and exit code are copied (default: `/content/drive/MyDrive/colab-jobs/<job>`).
# @option --artifact PATH File or directory copied to the persistent directory on exit; repeatable.
# @option --env-file PATH `KEY=VALUE` file exported to the command and deleted before it runs.
# @option --no-release Keep the VM assigned after the job, for inspection.
# @arg $@ The command to run, after `--`.
# @exitcode 2 When the arguments are invalid or the persistent directory is unusable.
# @exitcode * Otherwise the command's exit code; 124 when `timeout` stopped it.
# @example
#   bash /content/colab-job.sh --job fit-seg1 --ttl 10h --artifact /content/repo/lightning_logs \
#       --env-file /content/job.env -- uv run --package my-model python train.py fit --ckpt_path last

set -Eeuo pipefail

readonly USAGE='usage: colab-job.sh --job NAME [--ttl DURATION] [--persist-dir DIR] [--artifact PATH]... [--env-file PATH] [--no-release] -- COMMAND [ARGS...]'

job=''
ttl='11h'
persist_dir=''
env_file=''
release=1
artifacts=()
work_dir=''
log_file=''

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

# @description Copy artifacts, log, and exit code to the persistent directory, then release the VM.
# @description
#   Runs as the EXIT trap, so it sees the job's exit status in `$?` and exits
#   with that same status.
function finish() {
    local status=$?
    local persisted=1
    local artifact

    trap - EXIT
    printf '%s\n' "${status}" > "${work_dir}/exit_code"

    # `${artifacts[@]+...}` keeps Bash 3.2's `set -u` from rejecting an empty array.
    for artifact in ${artifacts[@]+"${artifacts[@]}"} "${log_file}" "${work_dir}/exit_code"; do
        if [ ! -e "${artifact}" ]; then
            say "artifact ${artifact} does not exist; skipped"
            continue
        fi

        if ! cp -R "${artifact}" "${persist_dir}/"; then
            say "failed to copy ${artifact} to ${persist_dir}"
            persisted=0
        fi
    done

    say "${job} finished with exit code ${status}; persisted to ${persist_dir}"

    if [ "${release}" -eq 0 ]; then
        say 'self-release disabled; the VM stays assigned until colab stop'
    elif [ "${persisted}" -eq 0 ]; then
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
    --job | --ttl | --persist-dir | --artifact | --env-file)
        [ "$#" -ge 2 ] || usage_error
        case "$1" in
        --job) job="$2" ;;
        --ttl) ttl="$2" ;;
        --persist-dir) persist_dir="$2" ;;
        --artifact) artifacts+=("$2") ;;
        --env-file) env_file="$2" ;;
        esac
        shift 2
        ;;
    --no-release)
        release=0
        shift
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

[ -n "${job}" ] && [ "$#" -gt 0 ] || usage_error
case "${job}" in
*/* | .*) usage_error ;;
esac

persist_dir="${persist_dir:-/content/drive/MyDrive/colab-jobs/${job}}"
case "${persist_dir}" in
/content/drive/*)
    if [ ! -d /content/drive/MyDrive ]; then
        say "Google Drive is not mounted; run colab drivemount first or pass --persist-dir"
        exit 2
    fi
    ;;
esac

if ! mkdir -p "${persist_dir}"; then
    say "cannot create ${persist_dir}"
    exit 2
fi

work_dir="${COLAB_JOB_WORK_ROOT:-/content/colab-jobs}/${job}"
mkdir -p "${work_dir}"
log_file="${work_dir}/job.log"

if [ -n "${env_file}" ]; then
    set -a
    # shellcheck source=/dev/null
    . "${env_file}"
    set +a
    rm -f "${env_file}"
fi

trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

say "starting ${job} (limit ${ttl}); log at ${log_file}"
set +e
timeout --kill-after=120 "${ttl}" "$@" 2>&1 | tee -a "${log_file}"
job_status="${PIPESTATUS[0]}"
set -e

exit "${job_status}"
