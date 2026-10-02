---
name: shunk031-colab-uv-training
description: Run a uv-workspace repository's long GPU job — model training, fine-tuning, or a GPU parity or test suite — on a Google Colab runtime through the `colab` CLI, safely and resumably. Covers session lifecycle and guaranteed teardown, keeping a busy runtime alive without background execution, persisting checkpoints and logs to Google Drive, resuming across the 12-hour runtime limit, passing secrets, VM self-release, orphaned-VM recovery, and the uv, CUDA, and NCCL pitfalls of Colab's image. Use whenever an agent is about to start, babysit, resume, or clean up a multi-hour or GPU job on Colab, or when a Colab run leaked a VM, lost its checkpoints, or broke `uv sync` or `import torch`, even if the request only says "train this on Colab" or "run the tests on an A100". For one-off `colab` CLI commands, authentication, or short snippets, the colab-operator skill is enough.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🛰️ I read shunk031-colab-uv-training.`

# Colab uv Training

This skill is the operating procedure for running one long GPU job from a uv-workspace repository on a Google Colab runtime. It assumes the colab-operator skill for CLI basics (authentication, `colab new`, `colab exec`, file transfer) and adds what that skill does not cover: a job that outlives a short command, a runtime that is billed until released, and results that disappear with the VM.

Three facts drive every rule below. A Colab VM is billed until it is unassigned, so a leaked session costs compute units with nothing to show. A runtime lives for about 12 hours at most and can be reclaimed earlier, so a job must persist its state outside the VM and resume from it. And Colab's image is set up for its own system Python, so a uv project needs a few environment corrections before `uv sync` targets the right place.

Requires google-colab-cli 0.7.4 or later (`colab version`; upgrade with `colab update` or your installer). Two defects rule out older versions. In 0.7.2, every kernel command (`colab exec`, `repl`, `run`) fails with `AttributeError: module 'jupyter_kernel_client' has no attribute 'JupyterSubprotocol'` once jupyter-kernel-client 0.8.0 is installed. And up to 0.7.2, the CLI dropped a session when its runtime token expired after about an hour while the VM stayed assigned, which produced orphaned, billed VMs.

## Lifecycle

Follow these steps in order. Steps 9 and 10 are not optional: run them on success, on failure, and when you abandon the job.

1. Check the account. `colab usage` must show a positive compute-unit balance that covers the planned run. Never buy compute units while a job is running: the purchase can replace the runtime and kill the job. If the balance is short, stop and ask the user.
2. Sweep before you start: run `scripts/colab-sweep --dry-run` from this skill, then `scripts/colab-sweep` to act on what it reported (see The sweeper).
3. Create a named session: `colab new -s <name> --gpu <A100|L4|T4|H100|G4>`. Always pass `-s`; later commands, the sweep, and teardown all key on the name.
4. Lease it immediately: `scripts/colab-sweep lease <name> <duration>`, with a duration a little longer than the job's hard limit. The lease lets a later sweep stop the session if this agent dies.
5. Mount Google Drive (see Durable results). The first consent is a human browser step.
6. Prepare the environment on the VM (see uv on Colab).
7. Upload the job wrapper, `scripts/colab-job.sh` from this skill, and any secret file: `colab upload -s <name> <skill-dir>/scripts/colab-job.sh /content/colab-job.sh`.
8. Launch the job as one busy kernel cell and poll it (see Keeping the runtime alive).
9. Tear down: `colab stop -s <name>`, even when the wrapper already released the VM. Then run `scripts/colab-sweep --dry-run` and `scripts/colab-sweep`.
10. Verify with `colab sessions` that no session or `[?]` orphan remains, and report the result.

Never use `colab run` for a multi-hour job. It does not handle SIGTERM or SIGHUP, so killing the local process leaks the VM; it tears the VM down on any websocket drop, which a multi-hour connection will eventually hit; and its default `--timeout` is 30 seconds.

## Keeping the runtime alive

Without background execution, which only Colab Pro+ offers, the backend keeps a runtime by kernel activity and live connections. The CLI's keep-alive ping does not keep it alive on its own. So run the job as one long busy cell, and keep that connection open:

```bash
cat > launch.py << 'EOF'
!bash /content/colab-job.sh --job fit-seg1 --ttl 10h --env-file /content/job.env --artifact /content/repo/outputs -- bash -c 'cd /content/repo && unset UV_SYSTEM_PYTHON PYTHONPATH && CUDA_VISIBLE_DEVICES=0 /root/.local/bin/uv run --no-sync --package <member> python -m <module> fit --config <config> --ckpt_path last'
EOF
colab exec -s <name> --timeout 37800 -f launch.py > fit-seg1.out 2>&1
```

- Keep `$` out of the `!` line: IPython expands `$name` from the Python namespace before the shell sees it, which is why the example calls uv by its absolute path.
- Set `colab exec --timeout` above the wrapper's `--ttl` plus a margin for copying results; 10 hours of job and 10.5 hours of `--timeout` is the shape. When `--timeout` is exceeded the local client can spin at 100% CPU instead of returning.
- Run that `colab exec` in the background of the agent's own environment, with output redirected to a local file, and keep the local machine awake and online for the whole job. An SSH or console connection held open is the alternative way to keep a live connection.
- If the local `colab exec` dies, the cell keeps running in the kernel. Do not launch it again. Check `colab status -s <name>` and poll the log instead.
- Poll progress without touching the busy kernel. `colab ls` and `colab download` use the contents API and work while the cell runs: `colab download -s <name> /content/colab-jobs/fit-seg1/job.log ./fit-seg1.log`.
- Plan for a maximum lifetime of about 12 hours (24 hours only on Pro+). Google does not publish the exact limits and they vary with load, so treat 12 hours as an upper bound, not a promise.

## The job wrapper

`scripts/colab-job.sh` runs on the VM and makes one job safe to leave unattended. It:

- runs the command under `timeout <ttl>` (default `11h`) and tees its output to `/content/colab-jobs/<job>/job.log`;
- on every exit, success or failure, copies each `--artifact` path, the log, and an `exit_code` file to the persistent directory, by default `/content/drive/MyDrive/colab-jobs/<job>`;
- refuses to start when that directory is under `/content/drive` and Drive is not mounted, instead of writing into a local directory that disappears with the VM;
- prints `<job> finished with exit code N` before releasing, so the local `colab exec` output records the outcome even after the VM is gone;
- then releases the VM itself with `POST http://${TBE_RUNTIME_ADDR}/unassign`, the call `google.colab.runtime.unassign()` makes. This stops billing the moment the job ends, even if the agent is not watching.

Pass `--no-release` when you will inspect the VM after the job; then your own `colab stop` is the only release. When `TBE_RUNTIME_ADDR` is unset, or any copy fails, the wrapper keeps the VM and says why, and `colab stop` remains your job. Run `bash colab-job.sh --help` for the full option list.

## Durable results and resume

Everything under `/content` is lost when the runtime ends. Write checkpoints and logs to Google Drive.

- Mounting: `colab drivemount -s <name>` mounts Drive at `/content/drive`. The first mount needs an OAuth consent in a browser. Never run it from the agent, because it waits for a human at a terminal. Ask the user to run `colab drivemount -s <name>` in their own terminal and tell you when it is done. Whether later mounts on new sessions succeed without the browser step is not yet confirmed; ask the user again whenever a mount does not complete.
- Checkpoints: have the training code write directly under the Drive directory, not only through the wrapper's exit copy, which cannot run if the runtime is reclaimed mid-job. For Lightning, use `ModelCheckpoint(dirpath=<drive dir>, save_last=True, train_time_interval=timedelta(minutes=30))`.
- Resume: start every segment with `fit --ckpt_path last` (LightningCLI) or `trainer.fit(..., ckpt_path="last")`. Lightning resumes from `last.ckpt` in the checkpoint directory and starts fresh when none exists, so the first and later segments run the same command.
- Segments: split work into segments of 10 to 12 hours at most, one session per segment, each with its own `--job` name and the same checkpoint directory. Choose `--ttl` so the job stops cleanly before the runtime's lifetime ends.

## uv on Colab

Run these on the VM, through the busy-cell pattern or a short `colab exec` per step.

- Unset Colab's Python overrides first: `unset UV_SYSTEM_PYTHON PYTHONPATH`. Colab exports both, and with them uv installs into the system interpreter under `/usr` instead of the project environment. Put the `unset` in every command that runs uv, including the job command.
- Install uv with the official installer, `curl -LsSf https://astral.sh/uv/install.sh | sh`, then use `/root/.local/bin/uv` or add that directory to `PATH`.
- Let uv provide the Python version the repository pins. Colab's system Python (3.12 at the time of writing) may not match `requires-python` or `.python-version`, and `uv sync` downloads the right one.
- Clone exactly what you tested: `git clone <url> /content/repo`, `git checkout <sha>`, and `git submodule update --init <path>` only for the submodules the job needs.
- Match torch to the driver. Run `nvidia-smi` and read the CUDA version the driver supports; an A100 runtime had driver 580 with CUDA 13.0, which runs cu130 torch wheels. When the driver is older than the locked wheel needs, install a driver-compatible torch wheel in the VM environment only, never in the repository's lock, and launch with `uv run --no-sync` so a later sync does not undo it.
- Watch NCCL when TensorFlow shares the environment. A TensorFlow extra pulls CUDA 12 NVIDIA wheels; installed alongside CUDA 13 torch, they can overwrite `libnccl.so.2` and `import torch` then fails. After the sync that installs TensorFlow, run it again with `--reinstall-package nvidia-nccl-cu13` and confirm `uv run --no-sync python -c 'import torch; print(torch.cuda.is_available())'`.
- Install test tools explicitly when needed. A repository that gets pytest only through `uv sync --all-packages` or a dev group may lack it after a single-member sync; add it with `uv pip install pytest` in the VM environment.
- Use one GPU: set `CUDA_VISIBLE_DEVICES=0`.

## Secrets

- Colab Secrets (`google.colab.userdata`) work only in the notebook UI, not through the CLI.
- `colab exec --env KEY=VALUE` writes the value in plain text to `~/.config/colab-cli/history/*.jsonl`. Do not pass secrets with it.
- Write secrets to a local `KEY=VALUE` file with mode 0600, upload it with `colab upload`, and pass it as `--env-file`. The wrapper exports it to the job and deletes it from the VM before the job starts. Delete the local copy when the job no longer needs it, and never print its contents.

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

- Whether `TBE_RUNTIME_ADDR` is set in kernels started through the CLI, which the wrapper's self-release depends on.
- Whether `colab drivemount` on a later session completes without a new browser consent.
- Whether a busy kernel cell keeps a Colab Pro runtime alive after the local connection is lost.
- Whether `!` shell lines sent with `colab exec -f` stream their output to the local client as they would in a notebook.

## References

- [references/sources.md](references/sources.md) lists the sources behind each fact above.
