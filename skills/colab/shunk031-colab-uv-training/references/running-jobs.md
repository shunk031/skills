# Running long jobs

Use this reference when launching or monitoring a job. Reuse the repository's job command and approved storage inside `scripts/colab-gpu-run` when they meet the task's needs. The bundled `colab-job.sh` wrapper writes logs and selected outputs to a private Hugging Face Hub repository.

## Prepare durable storage

Use an approved private Hub repository and a unique prefix such as `<project>/<run-id>`. Give each segment a distinct `--job` name so its logs land at `<prefix>/logs/<job>`. Each `--sync-path` lands at `<prefix>/<basename>`; choose distinct basenames and include every required checkpoint and result directory.

Stage datasets and other large inputs in approved durable storage before allocating a GPU. Declare every input that the job downloads with `--hub-input NAME=URI`; the launcher validates the name and passes the declaration to the Bash job script. The job script must download the data inside the VM. The launcher uploads only the job script, which is capped at 1 MiB, and an optional token file, which is capped at 16 KiB.

Use a fine-grained token scoped to the output repository and write it to a local file with mode `0600`. Pass it with `--hub-token-file`. The launcher verifies the mode and uploads two restricted copies serially: `/content/hf-token` for the wrapper and `/content/hf-job-token` for private input downloads. The wrapper reads and deletes its copy before the job starts; the remote driver removes the input copy when the job finishes. The original local token file is left in place. Do not pass token values in command text or `colab exec --env`.

Before spending GPU time, verify that the output repository is private and writable. The wrapper passes `--private` to uploads; that flag does not replace checking an existing repository's visibility.

## Launch a GPU job

Start every GPU job with `scripts/colab-gpu-run`. Do not allocate with `colab new --gpu`, `colab run --gpu`, or start work with a direct `colab exec`. The launcher checks the local job script with `bash -n`, validates local files and named inputs, starts the watchdog, allocates a unique named GPU session, uploads control files one at a time, and invokes `colab-job.sh` in the same command. Large data must be staged in durable storage and downloaded by the job script.

This example runs a ten-hour training segment. The job script downloads `train` from the named durable URI, runs the repository's training command, and writes results under `/content/out` for periodic upload.

```bash
scripts/colab-gpu-run \
    --gpu A100 \
    --job fit-seg1 \
    --hub-repo '<user>/colab-jobs' \
    --hub-prefix <project>/<run-id> \
    --job-script /abs/path/run-fit.sh \
    --hub-input 'train=hf://<user>/<dataset>/train.csv' \
    --hub-token-file /abs/path/hf-token \
    --sync-path /content/out/ckpt \
    --sync-path /content/out/results \
    --ttl 10h
```

The launcher requires Colab CLI 0.7.4, Bash, and Python 3. It defaults to a 180-second idle limit and a 43,200-second wall-clock limit; set `--idle-timeout` or `--wall-timeout` to choose different positive values in seconds. The job `--ttl` must not exceed the wall-clock limit. CPU-only sessions do not use this launcher or watchdog.

The watchdog runs detached on the local machine and logs to the path printed by the launcher under `${XDG_STATE_HOME:-~/.local/state}/colab-gpu-run/`. For Colab CLI 0.7.4, the launcher records the assigned endpoint before the CLI's own state write and the watchdog can recover from a failed local write using a private state file. Before stopping, it verifies the exact session name and endpoint in `colab status -s <name>`; at the wall limit, it may stop after a status error only when the local endpoint is unchanged and any endpoint in the error output matches. It retries other timed-out status checks without issuing a stop. Keep the local machine awake while the runtime is allocated; a machine shutdown or sleep can pause the watchdog.

In Colab CLI 0.7.4, status is `BUSY (<running command>)` while the local client records a running cell and `IDLE` otherwise. If a client disconnects after a timeout, the watchdog may treat the cell as idle and stop it after the idle limit. Sync checkpoints and results during the job so an interrupted run can resume from durable storage.

## Monitor and finish

Use the session name printed by the launcher with `colab status -s <name>` to inspect the state. Do not send a second `exec` into the busy kernel. Download requested results from the Hub after the job finishes; `colab download` is appropriate only for recovering files that remain on the VM.

The wrapper is invoked only by the launcher. It uploads logs and existing sync paths before the command, then runs the job under `timeout`, tees its output, syncs every 15 minutes by default, writes `logs/<job>/exit_code`, uploads again, and requests self-release via `TBE_RUNTIME_ADDR`. The watchdog remains active until the session disappears.

Verify the expected artifacts in durable storage, not just the wrapper's return code. If periodic or final upload fails, the wrapper retains the runtime so its local files can be recovered, but the watchdog will still stop an idle session after its configured limit. Recover any required files immediately with `colab download`, then verify the endpoint is no longer assigned with `colab sessions`. A watchdog stop at the wall-clock limit is unconditional, including while the job is busy.
