---
name: shunk031-colab-uv-training
description: Run a uv-workspace repository's long GPU job — model training, fine-tuning, or a GPU parity or test suite — on a Google Colab runtime through the `colab` CLI, safely and resumably. Covers session lifecycle and guaranteed teardown, orphan and lease sweeps, keeping a busy runtime alive without background execution, syncing checkpoints and logs to a private Hugging Face Hub repository, resuming across the 12-hour runtime limit, passing secrets, VM self-release, flaky `colab exec` calls, and the uv, CUDA, and NCCL pitfalls of Colab's image. Use whenever an agent is about to start, babysit, resume, or clean up a multi-hour or GPU job on Colab, or when a Colab run leaked a VM, lost its checkpoints, hung in `colab exec`, or broke `uv sync` or `import torch`, even if the request only says "train this on Colab" or "run the tests on an A100". For one-off `colab` CLI commands, authentication, or short snippets, the colab-operator skill is enough.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🛰️ I read shunk031-colab-uv-training.`

# Colab uv Training

This skill is the operating procedure for running one long GPU job from a uv-workspace repository on a Google Colab runtime. It assumes the colab-operator skill for CLI basics (authentication, `colab new`, `colab exec`, file transfer) and adds what that skill does not cover: a job that outlives a short command, a runtime that is billed until released, and results that disappear with the VM.

Three facts drive every rule below. A Colab VM is billed until it is unassigned, so a leaked session costs compute units with nothing to show. A runtime lives for about 12 hours at most and can be reclaimed earlier, so a job must sync its state off the VM while it runs and resume from it. And Colab's image is set up for its own system Python, so a uv project needs a few environment corrections before `uv sync` targets the right place.

Requires google-colab-cli 0.7.4 or later (`colab version`; upgrade with `colab update` or your installer). Two defects rule out older versions. In 0.7.2, every kernel command (`colab exec`, `repl`, `run`) fails with `AttributeError: module 'jupyter_kernel_client' has no attribute 'JupyterSubprotocol'` once jupyter-kernel-client 0.8.0 is installed. And up to 0.7.2, the CLI dropped a session when its runtime token expired after about an hour while the VM stayed assigned, which produced orphaned, billed VMs.

## Lifecycle

Follow these steps in order. Steps 10 and 11 are not optional: run them on success, on failure, and when you abandon the job.

1. Check the account. `colab usage` must show a positive compute-unit balance that covers the planned run. Never buy compute units while a job is running: the purchase can replace the runtime and kill the job. If the balance is short, stop and ask the user.
2. Sweep before you start: run `scripts/colab-sweep --dry-run` from this skill, then `scripts/colab-sweep` to act on what it reported (see The sweeper).
3. Create a named session: `colab new -s <name> --gpu <A100|L4|T4|H100|G4>`. Always pass `-s`; later commands, the sweep, and teardown all key on the name.
4. Lease it immediately: `scripts/colab-sweep lease <name> <duration>`, with a duration a little longer than the job's hard limit. The lease lets a later sweep stop the session if this agent dies.
5. Prepare the environment on the VM (see uv on Colab).
6. Upload the Hub token file, the job wrapper `scripts/colab-job.sh`, and any script that needs shell variables (see Durable results and Secrets): `colab upload -s <name> <skill-dir>/scripts/colab-job.sh /content/colab-job.sh`.
7. On a resumed segment, download the last checkpoint from the Hub (see Durable results).
8. Launch the job as one busy kernel cell, confirm it started, and poll it (see Keeping the runtime alive).
9. Download only the small results you need locally.
10. Tear down: `colab stop -s <name>`, even when the wrapper already released the VM. Then run `scripts/colab-sweep --dry-run` and `scripts/colab-sweep`.
11. Verify with `colab sessions` that no session or `[?]` orphan remains, and report the result.

Never use `colab run` for a multi-hour job. It does not handle SIGTERM or SIGHUP, so killing the local process leaks the VM; it tears the VM down on any websocket drop, which a multi-hour connection will eventually hit; and its default `--timeout` is 30 seconds.

## Keeping the runtime alive

Without background execution, which only Colab Pro+ offers, the backend keeps a runtime by kernel activity and live connections. The CLI's keep-alive ping does not keep it alive on its own. So run the job as one long busy cell, and keep that connection open:

```bash
cat > /abs/path/launch.py << 'EOF'
!bash /content/colab-job.sh --job fit-seg1 --hub-repo <user>/colab-jobs --hub-prefix <project>/<run-id> --hub-token-file /content/hf-token --sync-path /content/out/ckpt --sync-path /content/out/results --ttl 10h -- bash -c 'cd /content/repo && unset UV_SYSTEM_PYTHON PYTHONPATH && CUDA_VISIBLE_DEVICES=0 uv run --no-sync --package <member> python -m <module> fit --config <config> --ckpt_path last'
EOF
timeout 38400 colab exec -s <name> --timeout 37800 -f /abs/path/launch.py > fit-seg1.out 2>&1
```

- Keep `$` out of the `!` line: IPython expands `$name` from the Python namespace before the shell sees it. Put shell that needs variables in a script, upload it, and run it with `!bash /content/<script>.sh`.
- Set `colab exec --timeout` above the wrapper's `--ttl` plus a margin for the final upload; 10 hours of job and 10.5 hours of `--timeout` is the shape. When `--timeout` is exceeded the local client can spin at 100% CPU instead of returning, so wrap the client in an outer `timeout` as well.
- Run that `colab exec` in the background of the agent's own environment, with output redirected to a local file, and keep the local machine awake and online for the whole job. An SSH or console connection held open is the alternative way to keep a live connection.
- If the local `colab exec` dies, the cell keeps running in the kernel. Check `colab status -s <name>` and poll the log instead of launching again.
- Poll progress without touching the busy kernel. `colab ls` and `colab download` use the contents API and work while the cell runs: `colab download -s <name> /content/colab-jobs/fit-seg1/logs/job.log ./fit-seg1.log`. The Hub copy under `<prefix>/logs/<job>/` is a second view that survives the VM.
- Plan for a maximum lifetime of about 12 hours (24 hours only on Pro+). Google does not publish the exact limits and they vary with load, so treat 12 hours as an upper bound, not a promise.

### Flaky `colab exec`

In an observed A100 run (2026-10-02), about one `colab exec` call in ten failed: a read timeout, or a hang in which the code never reached the kernel. Treat every call as unreliable:

- Wrap every `colab exec` in an outer `timeout`, sized to what the call should take.
- Make launches idempotent. Before relaunching, check for the job's log or exit-code file (`/content/colab-jobs/<job>/logs/`); if the job already started, poll it instead.
- After launching the long cell, confirm within a few minutes that `job.log` exists. If it does not, kill the stuck local client, then relaunch.
- Never run two `colab exec` clients against one kernel at the same time. Kill a stuck client before retrying, and poll with `colab download` or `colab ls`, not `exec`, while the long cell runs.

Other pitfalls from the same run:

- Pass `colab exec -f` an absolute local path; a relative path breaks as soon as a calling script changes directory.
- Quote heredoc delimiters (`<< 'EOF'`) when composing code to send. An unquoted heredoc expands `$?` and other variables on the local machine.
- Do not overwrite a bash script on the VM while it runs: bash reads scripts as it executes them. Upload a changed script under a new name.
- `pkill -f <script>` matches the command line of the shell that issued it and can kill that shell. Kill by PID instead.

### Multi-step suites

For a suite of many steps, such as a parity or test suite, a short `colab exec` can start a detached driver with `subprocess.Popen(..., start_new_session=True)` so a failed `exec` cannot kill it. Have the driver append one TSV line per step (name, exit code, seconds) and accept a `SKIP_UNTIL=<step>` variable that skips steps before the named one, so a relaunch resumes instead of repeating. Poll the TSV about every 60 seconds with `colab download`. A detached driver leaves the kernel idle between polls; whether that keeps a Pro runtime alive for hours is not yet confirmed, so prefer the busy cell for anything long.

When a suite reports numerical differences, run the same suite on the same VM at the merge-base commit. That control run cheaply separates tolerance drift from the hardware and software stack from a regression in the code.

## The job wrapper

`scripts/colab-job.sh` runs on the VM and makes one job safe to leave unattended. It:

- runs the command under `timeout <ttl>` (default `11h`) and tees its output to `/content/colab-jobs/<job>/logs/job.log`;
- uploads the log directory once before the job starts and aborts if that fails, so a wrong repository or token is caught before hours of compute;
- while the job runs, uploads the log directory to `<prefix>/logs/<job>` and each `--sync-path` to `<prefix>/<basename>` every `--sync-interval` (default `15m`), logging a failed upload without stopping the job;
- on every exit, success or failure, writes `exit_code` into the log directory and uploads everything once more;
- prints `<job> finished with exit code N`, so the local `colab exec` output records the outcome even after the VM is gone;
- then releases the VM itself with `POST http://${TBE_RUNTIME_ADDR}/unassign`, the call `google.colab.runtime.unassign()` makes. `TBE_RUNTIME_ADDR` is set in kernels started through the CLI (observed as `172.28.0.1:8011` with colab CLI 0.7.4), so the job stops billing the moment it ends, even if the agent is not watching.

It uses `hf` when it is on `PATH`, otherwise `uvx --from huggingface_hub hf`. When the final upload fails, the wrapper keeps the VM and says so, because the VM then holds the only copy; your `colab stop` remains the release after you recover the results. Pass `--no-release` when you will inspect the VM after the job. Run `bash colab-job.sh --help` for the full option list.

## Durable results and resume

Everything under `/content` is lost when the runtime ends, so the job syncs to a private Hugging Face Hub repository while it runs.

- Repository: one private repository for job artifacts, for example `<user>/colab-jobs`, with one folder per run: `<project>/<run-id>/{logs,ckpt,results}`. Pass `--hub-prefix <project>/<run-id>` and give each segment of the run its own `--job` name, so its logs land in `logs/<job>` beside the others.
- Token: a fine-grained Hugging Face token with write access to that one repository only, kept in the user's secret manager. Write it to a local file with mode 0600, `colab upload` it to `/content/hf-token`, and delete the local copy. The wrapper reads and deletes the VM copy before the job starts and passes the token only to the uploader. Never pass it with `colab exec --env`.
- Checkpoints: write them under a `--sync-path` directory, such as `/content/out/ckpt`. For Lightning, use `ModelCheckpoint(dirpath="/content/out/ckpt", save_last=True, train_time_interval=timedelta(minutes=15))`. `ckpt/last.ckpt` is overwritten on the Hub at each sync.
- Resume: before a later segment, download the checkpoint into the directory the checkpoint callback uses, from an uploaded script so the token stays out of the `!` line:

  ```bash
  export HF_TOKEN="$(cat /content/hf-token)"
  hf download <user>/colab-jobs --include '<project>/<run-id>/ckpt/last.ckpt' --local-dir /content/hub
  mkdir -p /content/out/ckpt
  cp /content/hub/<project>/<run-id>/ckpt/last.ckpt /content/out/ckpt/ 2> /dev/null || true
  ```

  Then run `fit --ckpt_path last` (LightningCLI) or `trainer.fit(..., ckpt_path="last")`. Lightning resumes from the newest last checkpoint and starts fresh when none exists, so the first and later segments run the same command. Passing the explicit path also works once a checkpoint exists.

- Segments: split work into segments of 10 to 12 hours at most, one session per segment. Choose `--ttl` so the job stops cleanly before the runtime's lifetime ends.
- Local copies: download only small results to the local machine, for example `hf download <user>/colab-jobs --include '<project>/<run-id>/results/*' --local-dir <dir>`. Leave checkpoints on the Hub.
- Cleanup: after the results are retrieved, and with the user's approval because both operations are destructive, delete the run's folder with `HfApi().delete_folder(path_in_repo="<project>/<run-id>", repo_id="<user>/colab-jobs")`, and periodically run `HfApi().super_squash_history(repo_id="<user>/colab-jobs")`. Overwritten checkpoints stay in the repository's git history and count against the account's private storage, which is capped by plan (100 GB on a free account); a squash shows up in the quota within 36 hours.

Google Drive is not a substitute. `colab drivemount` asks for a new OAuth consent in a browser on every session and waits for a human to press Enter; without one it does not mount. Use it only when the user is present to approve it, and never run it from the agent.

## uv on Colab

Run these on the VM, through the busy-cell pattern or a short `colab exec` per step. The facts were observed on an A100 runtime on 2026-10-02: an A100-SXM4-40GB, driver 580.82.07 with CUDA 13.0, Ubuntu 24.04, 12 vCPUs, 83 GB of RAM, and about 194 GB free under `/content`. The first `uv sync`, including torch, took about 40 seconds.

- Unset Colab's Python overrides first: `unset UV_SYSTEM_PYTHON PYTHONPATH`. Colab presets `UV_SYSTEM_PYTHON=true` and `PYTHONPATH=/env/python`, and with them uv installs into the system interpreter instead of the project environment. Put the `unset` in every command that runs uv, including the job command. Colab also presets `UV_INSTALL_DIR=/usr/local/bin` and empty `UV_CONSTRAINT` and `UV_BUILD_CONSTRAINT`.
- Check `uv --version`. If uv is missing, install it with the official installer, `curl -LsSf https://astral.sh/uv/install.sh | sh`; with Colab's `UV_INSTALL_DIR` it lands in `/usr/local/bin`, already on `PATH`.
- Let uv provide the Python version the repository pins. Colab's system Python (3.12 at the time of writing) may not match `requires-python` or `.python-version`, and `uv sync` downloads the right one.
- Clone exactly what you tested: `git clone <url> /content/repo`, `git checkout <sha>`, and `git submodule update --init <path>` only for the submodules the job needs.
- Match torch to the driver. Run `nvidia-smi` and read the CUDA version the driver supports; CUDA 13.0 runs cu130 torch wheels. When the driver is older than the locked wheel needs, install a driver-compatible torch wheel in the VM environment only, never in the repository's lock, and launch with `uv run --no-sync` so a later sync does not undo it.
- Watch NCCL when TensorFlow shares the environment. A TensorFlow extra pulls CUDA 12 NVIDIA wheels; installed alongside CUDA 13 torch, they can overwrite `libnccl.so.2` and `import torch` then fails. After the sync that installs TensorFlow, run it again with `--reinstall-package nvidia-nccl-cu13` and confirm `uv run --no-sync python -c 'import torch; print(torch.cuda.is_available())'`.
- Install test tools explicitly. A repository that gets pytest only through `uv sync --all-packages` or a dev group may lack it after a single-member sync, and `uv run pytest` then silently runs the system pytest instead of failing. Add it with `uv pip install pytest` and check that `uv run --no-sync which pytest` points into `.venv`.
- Use one GPU: set `CUDA_VISIBLE_DEVICES=0`.

## Secrets

- Colab Secrets (`google.colab.userdata`) work only in the notebook UI, not through the CLI.
- `colab exec --env KEY=VALUE` writes the value in plain text to `~/.config/colab-cli/history/*.jsonl`. Do not pass secrets with it.
- Pass the Hub token as `--hub-token-file` (see Durable results). Pass other secrets the job itself needs, such as an experiment-tracker key, as a 0600 `KEY=VALUE` file uploaded with `colab upload` and given as `--env-file`; the wrapper exports it to the job and deletes it from the VM before the job starts. Delete local copies when the job no longer needs them, and never print their contents.

## The sweeper

`scripts/colab-sweep` stops leaked and expired Colab runtimes. Nothing schedules it: run it before and after every job, as the lifecycle says.

- Owned sessions are the endpoints recorded in `~/.config/colab-cli/sessions.json` and in every `~/.config/colab-cli/states/*.json`. When you isolate a run with `colab --config <file>`, put that file in `~/.config/colab-cli/states/`, or the sweep treats your live session as an orphan.
- An orphan is an assigned runtime that no state file records; `colab sessions` shows it as `[?]`, and it bills like any other. The sweep unassigns an orphan only after it has stayed an orphan for the grace period (`--grace`, default `30m`, or `COLAB_SWEEP_GRACE`), which protects a session that another `colab new` is still creating. First-seen times live in `$XDG_STATE_HOME/colab-sweep` (default `~/.local/state/colab-sweep`), with an action log beside them.
- `colab-sweep lease <name> <duration>` gives a recorded session an expiry, such as `11h`; the first sweep after it runs `colab stop` on that session. Sessions without a lease are only reported.
- `--dry-run` reports what a sweep would do and writes nothing.
- A state file that does not parse aborts the sweep instead of reading as empty, so a corrupt file never turns owned sessions into orphans. Any API or state error makes it exit with status 1; report that rather than retrying blindly.
- It needs the `colab_cli` package. When the current `python3` cannot import it, the script re-executes itself under the interpreter of a mise pipx install, `$(mise where pipx:google-colab-cli)/google-colab-cli/bin/python`. With any other install method, run it with the CLI's interpreter directly, the one in the shebang of `command -v colab`.

Because nothing runs the sweep on a timer, a runtime left behind by a crashed agent is caught in two ways: the job wrapper's hard `--ttl` ends the job and the wrapper unassigns the VM, and the next sweep, by any agent, stops an expired lease or unassigns the orphan.

## To verify

These are not yet confirmed. Treat them as open, and record what you observe when a run settles one.

- Whether a busy kernel cell keeps a Colab Pro runtime alive after the local connection is lost, and whether a detached driver with an idle kernel survives between polls.
- Whether `!` shell lines sent with `colab exec -f` stream their output to the local client as they would in a notebook.

## References

- [references/sources.md](references/sources.md) lists the sources behind each fact above.
