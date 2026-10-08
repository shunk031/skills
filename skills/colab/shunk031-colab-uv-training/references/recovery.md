# Resuming and recovering jobs

Read the relevant section for a resumed run, a failed connection or upload, or an authorized cleanup. Recovery stays within the current job's cost and storage scope unless the user expands it.

## Resume from a durable checkpoint

Use the repository's checkpoint writer and resume command. Store checkpoints in a synced directory and choose a save interval that limits lost work if the VM disappears. For Lightning, `ModelCheckpoint` supports `save_last=True` and `train_time_interval`; configure its output directory to match a `--sync-path`.

For a Hub-backed Lightning run, download the selected checkpoint inside the next job script before starting the training command. The launcher passes the declared `--hub-input` references to that script and makes the restricted token available at `/content/hf-job-token` when one was provided.

```bash
HF_TOKEN="$(cat /content/hf-job-token)" hf download <user>/colab-jobs --include '<project>/<run-id>/ckpt/last.ckpt' --local-dir /content/hub
mkdir -p /content/out/ckpt
cp /content/hub/<project>/<run-id>/ckpt/last.ckpt /content/out/ckpt/last.ckpt
test -s /content/out/ckpt/last.ckpt
```

Then pass the explicit path to the training command in the same job script, for example `fit --ckpt_path /content/out/ckpt/last.ckpt`. Start that script through `scripts/colab-gpu-run` with a new job name, the checkpoint declared as `--hub-input`, and a synced output path. Confirm from the training log that the checkpoint loaded. Lightning's `ckpt_path="last"` can start fresh when no checkpoint exists, so do not use that fallback to satisfy a request to resume. If download or validation fails, resolve it before allocating more training time. The launcher removes its remote input-token copy when the job finishes.

Use a new job name for each segment and the same run prefix when continuing the same run. Download the results the user requested locally; leave large checkpoints at the approved destination unless local copies are part of the request.

## Client timeout or stalled launch

A stalled launcher may leave its cell running. Inspect `colab status -s <name>`, the job log, and any exit-code file through the contents API. The detached watchdog keeps monitoring while the launcher client is stalled. If status reports `BUSY`, monitor the job and do not submit duplicate work. If status reports `IDLE`, the watchdog will stop the session after its configured idle limit.

Stop a stuck local client by its recorded PID before opening another client. Do not resume GPU work with a direct `colab exec`; prepare the retry script and inputs, then use `scripts/colab-gpu-run` after the previous attempt has ended. A retry uses a distinct job name so an old log or exit-code file cannot be mistaken for the new attempt.

## Failed upload or release

When the wrapper retains the VM after a final upload failure, recover all required sync paths and logs with `colab download` before the watchdog's idle limit expires. Verify that recovery succeeded before `colab stop`. To retry a Hub operation on a GPU, put it in a job script and start it through `scripts/colab-gpu-run` with a fresh restricted token file.

If storage remains unavailable, report the endpoint and remaining results. The watchdog still stops an idle GPU session at its idle limit or wall-clock limit, so retrieve the only remaining copy before that deadline. Do not use an account-wide sweep to recover one job.

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
