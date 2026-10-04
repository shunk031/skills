# Resuming and recovering jobs

Read the relevant section for a resumed run, a failed connection or upload, or an authorized cleanup. Recovery stays within the current job's cost and storage scope unless the user expands it.

## Resume from a durable checkpoint

Use the repository's checkpoint writer and resume command. Store checkpoints in a synced directory and choose a save interval that limits lost work if the VM disappears. For Lightning, `ModelCheckpoint` supports `save_last=True` and `train_time_interval`; configure its output directory to match a `--sync-path`.

For a Hub-backed Lightning run, download the selected checkpoint before starting the next segment. Run this as an uploaded shell script so the token stays out of IPython command expansion and CLI history. Use the CLI's interpreter or `uvx --from huggingface_hub hf` if `hf` is unavailable.

If a previous wrapper has already run, follow [Hub operations after the wrapper](running-jobs.md#hub-operations-after-the-wrapper) to upload and preflight a fresh restricted token file before this download.

```bash
set -euo pipefail
HF_TOKEN="$(cat /content/hf-token)" hf download <user>/colab-jobs --include '<project>/<run-id>/ckpt/last.ckpt' --local-dir /content/hub
mkdir -p /content/out/ckpt
cp /content/hub/<project>/<run-id>/ckpt/last.ckpt /content/out/ckpt/last.ckpt
test -s /content/out/ckpt/last.ckpt
```

Then pass the explicit path to the project command after clearing the Colab overrides with `unset UV_SYSTEM_PYTHON PYTHONPATH MPLBACKEND`, for example `fit --ckpt_path /content/out/ckpt/last.ckpt`. Confirm from the training log that the checkpoint loaded. Lightning's `ckpt_path="last"` can start fresh when no checkpoint exists, so do not use that fallback to satisfy a request to resume. If download or validation fails, resolve it before allocating more training time. Delete the token file after the download; upload a separate restricted token file when starting the next wrapper run.

Use a new job name for each segment and the same run prefix when continuing the same run. Download the results the user requested locally; leave large checkpoints at the approved destination unless local copies are part of the request.

## Client timeout or stalled launch

A failed `colab exec` can leave its cell running. Inspect `colab status -s <name>`, the job log, and any exit-code file through the contents API. If work is progressing, monitor it. The absence of a log alone does not prove the cell was never submitted.

Stop a stuck local client by its recorded PID before opening another client. Relaunch only after establishing that the earlier command did not start or has stopped; otherwise report the uncertain state and preserve the VM while resolving it. A retry uses a distinct job name once the previous attempt is known to have ended, so an old log or exit-code file cannot be mistaken for the new attempt.

## Failed upload or release

When the wrapper retains the VM after a final upload failure, recover all required sync paths and logs by repairing the upload or downloading them. Verify that recovery succeeded before `colab stop`. The wrapper deletes its token file at startup, so use [Hub operations after the wrapper](running-jobs.md#hub-operations-after-the-wrapper) to upload and preflight a fresh restricted token file for any retry.

If storage remains unavailable, report the endpoint, remaining results, and ongoing allocation. Do not let a scheduled or manually invoked sweep erase the only copy. A hard cost cap may conflict with retention; use the user's existing loss-versus-cost decision or ask for that decision rather than silently choosing.

Once results are safe, retry release for this task and verify the endpoint is gone. `colab sessions` can prune stale local records after self-release. A local record disappearing is not evidence that an unknown assigned endpoint belongs to this task.

## Account-wide cleanup and leases

`scripts/colab-sweep --dry-run` inventories assignments without writing sweep state or releasing VMs. The mutating command is account-wide: it stops expired leases and unassigns endpoints absent from the local CLI records after a grace period. Such an endpoint may belong to a notebook or another machine. Its absence locally and its age do not prove it is safe to stop.

Use targeted `colab stop -s <name>` for normal task teardown. Use the mutating sweeper only when account-wide cleanup is authorized and every proposed target is covered. If the dry-run includes unrelated or uncertain runtimes, do not run it; resolve ownership or use targeted cleanup. An authorized review of the dry-run need not be requested again unless the targets or scope change.

The sweeper's operational details matter only when using it:

- It reads `~/.config/colab-cli/sessions.json` and every `~/.config/colab-cli/states/*.json`. A custom `colab --config` outside that directory is invisible to it. Malformed JSON aborts the sweep.
- Unrecorded assignments become eligible after `--grace`, default `30m` or `COLAB_SWEEP_GRACE`. First-seen times and action logs live under `$XDG_STATE_HOME/colab-sweep`, default `~/.local/state/colab-sweep`. Dry-runs do not start that clock.
- `scripts/colab-sweep lease <name> <duration>` records an expiry. A later mutating sweep stops matching sessions even if results have not been recovered. Lease names are shared across the state files, so use a unique name and create a lease only when release at expiry is authorized. A lease is not a timer.
- Stale or unrecorded sessions lose their leases; the script leaves CLI records to `colab sessions` to prune. API or state failures require investigation before another mutation.
- If `colab_cli` is not importable, the helper re-executes under the mise pipx installation's interpreter. For another install method, invoke it with the CLI's interpreter.

Nothing schedules the sweeper. Neither a lease nor the wrapper guarantees cleanup after every crash or failed upload; verify allocation explicitly.

## Storage alternatives and deletion

Keep an existing approved artifact store instead of migrating solely for this skill. Google Drive mounting in the observed CLI workflow requires browser consent for each fresh session, so it needs an attended authentication step. Arrange that step when the user chose Drive; it is not an unattended substitute for an already authenticated store.

Deleting a run folder or rewriting Hub history requires authorization for that destructive operation. `HfApi.delete_folder` removes the run's files; `super_squash_history` affects the whole repository history, including other runs. Check current storage policy and the scope of data retained before proposing either operation. Successful retrieval alone is not permission to delete artifacts.
