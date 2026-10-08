# Sources

Use these sources to check the operational references when a version-sensitive behavior matters. Facts marked as observed were reported from Colab runs on the dates shown; they have no published trace here and were not repeated during the instruction review. They do not establish a failure rate, lifetime, or teardown guarantee for a new runtime.

## colab CLI

- [googlecolab/google-colab-cli](https://github.com/googlecolab/google-colab-cli) and [google-colab-cli on PyPI](https://pypi.org/project/google-colab-cli/): the `colab` command, its subcommands, and the `colab exec --timeout` default of 30 seconds, also shown by `colab exec --help`.
- Installed Colab CLI 0.7.4 help and source checked on 2026-10-09: `colab version` is a subcommand; `colab status -s NAME` prints `[NAME] ENDPOINT | ... | Status: IDLE` or `Status: BUSY (<running>)`; `colab exec` sets and clears the local `running` field; and `colab stop -s NAME` resolves the stored session by name before unassigning its endpoint. `colab new` receives the assignment and endpoint before `StateStore.add()` writes local state; if that write fails, `colab sessions` shows the assignment as `[?]` and `colab stop` cannot resolve it by name. The launcher uses a temporary `sitecustomize` hook limited to the checked 0.7.4 process to preserve the full session record before that write, which lets its watchdog recover the exact name and endpoint. Status reflects the CLI's local execution marker rather than a server-side kernel query, so a disconnected client can leave an executing cell reported as idle. The watchdog verifies the endpoint in the status line before a stop and rechecks the unchanged local endpoint for this generated name before a wall-limit stop when status is unavailable. The job must sync checkpoints to durable storage.
- [Google Developers Blog: Introducing the Google Colab CLI](https://developers.googleblog.com/introducing-the-google-colab-cli/): describes CLI provisioning, remote execution, artifact recovery, and cleanup in one workflow.
- [googlecolab/google-colab-cli#147](https://github.com/googlecolab/google-colab-cli/issues/147): sessions were pruned as lost when the runtime-proxy token expired after about an hour while the VM stayed assigned, producing orphaned assignments. Fixed by [googlecolab/google-colab-cli#149](https://github.com/googlecolab/google-colab-cli/pull/149), released in 0.7.4.
- [googlecolab/google-colab-cli#144](https://github.com/googlecolab/google-colab-cli/pull/144) and the maintainer comment in [googlecolab/google-colab-cli#160](https://github.com/googlecolab/google-colab-cli/issues/160): without background execution, the backend keeps a runtime by kernel activity and live connections, and the client keep-alive ping does not extend it.
- [googlecolab/google-colab-cli#82](https://github.com/googlecolab/google-colab-cli/issues/82): a long `colab exec` timeout that is exceeded can spin a local CPU core indefinitely.
- [colab_cli/client.py](https://github.com/googlecolab/google-colab-cli/blob/main/src/colab_cli/client.py): `Client.list_assignments()` and `Client.unassign(endpoint)` access assignments for the account. Local CLI records do not prove ownership of every account assignment; the sweeper compares them with those assignments.
- With jupyter-kernel-client 0.8.0 installed, google-colab-cli 0.7.2 kernel commands fail with `AttributeError: module 'jupyter_kernel_client' has no attribute 'JupyterSubprotocol'`: observed.
- A live smoke test of `scripts/colab-job.sh` on a CPU runtime with colab CLI 0.7.4 and a fine-grained token for one Hub repository: the first upload, a 20-second sync loop, the final upload, and self-release worked, `list_assignments()` was empty about 20 seconds after release, and the wrapper's output from a `!` line sent with `colab exec -f` reached the local client. Afterwards the local session record and the sweeper lease remained until `colab sessions` printed `Pruned 1 stale local session(s).`: observed.
- On 2026-10-03 with Colab CLI 0.7.4, a separate post-wrapper `colab exec` call to list Hub artifacts failed because `/content/hf-token` had been consumed before the job started. The listing succeeded after uploading a fresh restricted token file from a temporary local file, deleting the local copy, and removing the VM copy afterward: observed.
- `colab exec` calls failed with read timeouts or hung before reaching the kernel during an A100 run: observed. No sample size or repeatable failure-rate measurement is available here.
- `colab run` signal handling and websocket teardown: observed behavior of the CLI, reported with the task that produced this skill.

## Colab runtime

- [Colab FAQ](https://research.google.com/colaboratory/faq.html): runtimes have a maximum lifetime, background execution is a Pro+ feature, and the usage limits are not published and vary.
- [google/colab/runtime.py](https://github.com/googlecolab/colabtools/blob/main/google/colab/runtime.py): `google.colab.runtime.unassign()` posts to `http://${TBE_RUNTIME_ADDR}/unassign`, which the job wrapper's self-release reproduces.
- `TBE_RUNTIME_ADDR` is set in a kernel started through colab CLI 0.7.4 (`172.28.0.1:8011` on a CPU runtime): observed.
- `colab drivemount` on a fresh session printed a new OAuth consent URL (redirecting to `/tun/m/authorize-for-drive-credentials-ephem`) and waited for Enter; without a human it did not mount: observed.
- Colab presets `UV_SYSTEM_PYTHON=true`, `UV_INSTALL_DIR=/usr/local/bin`, `PYTHONPATH=/env/python`, and empty `UV_CONSTRAINT` and `UV_BUILD_CONSTRAINT`; `uv run pytest` fell back to the system pytest when the project environment lacked it: observed.
- With Colab CLI 0.7.4, a project uv environment lacking `matplotlib_inline` inherited `MPLBACKEND=module://matplotlib_inline.backend_inline` and raised `ValueError` during a matplotlib import through Lightning on 2026-10-02 (CPU) and 2026-10-04 (A100): observed.
- On 2026-10-02 (CPU), setting `MPLBACKEND=Agg` was followed by a regenerated run that completed: observed.
- On 2026-10-04 (A100), unsetting `MPLBACKEND` was followed by a run that passed package import, the training loop, and the original validation/evaluate smoke: observed.
- The A100 runtime was an A100-SXM4-40GB with driver 580.82.07 and CUDA 13.0 on Ubuntu 24.04, with 12 vCPUs, 83 GB of RAM, and about 194 GB free under `/content`; the first `uv sync` with torch took about 40 seconds: observed.
- CUDA 12 NVIDIA wheels from a TensorFlow install overwrote `libnccl.so.2` of CUDA 13 torch in the same environment: observed.

## Hugging Face Hub

- [Upload files to the Hub](https://huggingface.co/docs/huggingface_hub/guides/upload): upload methods and their different retry, background, and commit behavior. The wrapper uses `hf upload`; do not assume every upload method has the same behavior.
- [HfApi reference](https://huggingface.co/docs/huggingface_hub/package_reference/hf_api): `HfApi.delete_folder` and `HfApi.super_squash_history`.
- [Storage limits](https://huggingface.co/docs/hub/storage-limits): private storage is 100 GB on a free account and 1 TB on PRO, super-squash is destructive and reaches the quota within 36 hours, and overwritten LFS files keep using storage until history is rewritten.
- `hf upload --help` and `hf download --help` (huggingface_hub 2.1.1): `--repo-type`, `--private`, `--quiet`, `--include`, and `--local-dir`.

## uv

- [uv installation](https://docs.astral.sh/uv/getting-started/installation/): the official installer.
- [uv environment variables](https://docs.astral.sh/uv/reference/environment/): `UV_SYSTEM_PYTHON` makes uv use the system interpreter.

## Lightning

- [ModelCheckpoint](https://lightning.ai/docs/pytorch/stable/api/lightning.pytorch.callbacks.ModelCheckpoint.html): `save_last` and `train_time_interval`.
- [checkpoint_connector.py](https://github.com/Lightning-AI/pytorch-lightning/blob/master/src/lightning/pytorch/trainer/connectors/checkpoint_connector.py): `ckpt_path="last"` resumes from the newest last checkpoint and, when none exists, warns and starts without one.

## Instruction design

- [Rethinking skills and prompts for GPT-6 Astra](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra): use a precise description, load operational details only when needed, retain concrete constraints, and define completion without imposing a fixed itinerary. The entrypoint applies these principles while the runtime-specific procedures remain in references.
