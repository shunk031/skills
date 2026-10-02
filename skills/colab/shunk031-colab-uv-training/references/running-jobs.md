# Running long jobs

Use this reference when launching or monitoring a job. Keep the repository's own runner and approved storage when they already meet the task's needs. The example below uses the bundled Hub wrapper.

## Prepare durable storage

Use an approved private Hub repository and a unique prefix such as `<project>/<run-id>`. Give each segment a distinct `--job` name so its logs land in `<prefix>/logs/<job>`. Each `--sync-path` lands at `<prefix>/<basename>`; choose distinct basenames and include every required checkpoint and result directory.

Use a fine-grained token scoped to that repository. Write it to a local file with mode 0600, upload it to `/content/hf-token`, restrict the remote file to mode 0600, and remove the temporary local copy. The wrapper reads and deletes the remote copy before the job starts and passes that token only to the uploader. Do not separately export the Hub token into the job's environment.

For secrets the job itself needs, upload a restricted `--env-file`. The wrapper sources it as shell code, exports its variables, and deletes it before launching the command. Generate this file from trusted, shell-quoted assignments. Never use `colab exec --env` for credentials: the CLI records its values in local history. Colab notebook Secrets are not available through the CLI workflow observed here.

The wrapper expects `hf` on PATH or falls back to `uvx --from huggingface_hub hf`. Before spending GPU time, verify that the intended repository is private and writable. The wrapper passes `--private` to uploads; that flag does not replace checking an existing repository's visibility.

## Launch a busy kernel cell

Without background execution, keep the job in one busy kernel cell and keep the local client connected. The CLI keep-alive ping alone does not establish runtime liveness. A detached driver leaves the kernel idle, and its survival for a long unattended run has not been verified.

Upload `scripts/colab-job.sh` from this skill to `/content/colab-job.sh`. This example runs a new training job with a 10-hour command limit; replace the command, directories, and timeouts to fit the actual run. For a resumed run, first follow [recovery.md](recovery.md).

```bash
cat > /abs/path/launch.py << 'EOF_PY'
!bash /content/colab-job.sh --job fit-seg1 --hub-repo <user>/colab-jobs --hub-prefix <project>/<run-id> --hub-token-file /content/hf-token --sync-path /content/out/ckpt --sync-path /content/out/results --ttl 10h -- bash -c 'cd /content/repo && unset UV_SYSTEM_PYTHON PYTHONPATH && CUDA_VISIBLE_DEVICES=0 uv run --no-sync --package <member> python -m <module> fit --config <config>'
EOF_PY
timeout 38400 colab exec -s <name> --timeout 37800 -f /abs/path/launch.py > fit-seg1.out 2>&1
```

The local `timeout` must be available. Use an absolute path for `-f`. Run the client in a managed background process if the agent needs to continue monitoring, and keep the local machine awake and connected.

Set the client timeout above the job TTL with room for final uploads, and the outer timeout above the client timeout. The outer timeout bounds a known CLI hang; it does not cancel a remote cell. Choose the job TTL below the runtime limit with an upload margin. Colab's FAQ describes typical limits up to 12 hours and up to 24 hours for eligible Pro+ execution, with availability and balance constraints.

IPython expands `$name` in `!` lines before the shell sees it. Put shell commands needing variables in an uploaded script instead. A quoted heredoc also prevents local expansion while writing that script. Upload revisions under a new name rather than overwriting a script that Bash is executing.

Prefer `colab new` and `colab exec` for this workflow. The observed `colab run` implementation can release the VM after a websocket drop and can leave it assigned after local signal termination; recheck those behaviors before relying on it for a long job.

## Monitor and finish

Confirm that `/content/colab-jobs/<job>/logs/job.log` appears and progresses. Poll with `colab download` or `colab ls`, which use the contents API while the kernel is busy. The Hub copy is another view that survives the VM. Choose the polling interval for the job's expected progress rate; do not send a second `exec` into the busy kernel.

The wrapper first uploads logs and any existing sync paths, then runs the command under `timeout` and tees its output. It syncs every 15 minutes by default, writes `logs/<job>/exit_code`, uploads again, and requests self-release via `TBE_RUNTIME_ADDR`. `bash colab-job.sh --help` lists its options. Use `--no-release` when authorized post-job inspection requires the runtime to stay assigned.

Verify the expected artifacts in durable storage, not just the wrapper's return code. Periodic upload failures do not stop the job. A final upload failure retains the VM, while an initial upload failure aborts before the job and leaves release to the caller. Recover required results using [recovery.md](recovery.md) before manual teardown. If results are safe and automatic release failed, stop this named session and verify its endpoint is no longer assigned with `colab sessions`.

Self-release is best effort. Uploads and the release request can fail or stall; the command TTL does not bound those operations. If the client disconnects, inspect the current state rather than assuming either success or a stopped job.
