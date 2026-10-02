# Sources

Each entry names the fact in `SKILL.md` it supports. Facts marked as observed come from runs on Colab runtimes on 2026-10-02 and have no published source.

## colab CLI

- [googlecolab/google-colab-cli](https://github.com/googlecolab/google-colab-cli) and [google-colab-cli on PyPI](https://pypi.org/project/google-colab-cli/): the `colab` command, its subcommands, and the `colab exec --timeout` default of 30 seconds, also shown by `colab exec --help`.
- [googlecolab/google-colab-cli#147](https://github.com/googlecolab/google-colab-cli/issues/147): sessions were pruned as lost when the runtime-proxy token expired after about an hour while the VM stayed assigned, producing orphaned assignments. Fixed by [googlecolab/google-colab-cli#149](https://github.com/googlecolab/google-colab-cli/pull/149), released in 0.7.4.
- [googlecolab/google-colab-cli#144](https://github.com/googlecolab/google-colab-cli/pull/144) and the maintainer comment in [googlecolab/google-colab-cli#160](https://github.com/googlecolab/google-colab-cli/issues/160): without background execution, the backend keeps a runtime by kernel activity and live connections, and the client keep-alive ping does not extend it.
- [googlecolab/google-colab-cli#82](https://github.com/googlecolab/google-colab-cli/issues/82): a long `colab exec` timeout that is exceeded can spin a local CPU core indefinitely.
- `colab_cli/client.py` in the installed package: `Client.list_assignments()` reads `/tun/m/assignments`, and `Client.unassign(endpoint)` posts to `/tun/m/unassign/<endpoint>`; `colab_cli.common.state.client` is the authenticated client the CLI itself uses.
- With jupyter-kernel-client 0.8.0 installed, google-colab-cli 0.7.2 kernel commands fail with `AttributeError: module 'jupyter_kernel_client' has no attribute 'JupyterSubprotocol'`: observed.
- A live smoke test of `scripts/colab-job.sh` on a CPU runtime with colab CLI 0.7.4 and a fine-grained token for one Hub repository: the first upload, a 20-second sync loop, the final upload, and self-release worked, `list_assignments()` was empty about 20 seconds after release, and the wrapper's output from a `!` line sent with `colab exec -f` reached the local client. Afterwards the local session record and the sweeper lease remained until `colab sessions` printed `Pruned 1 stale local session(s).`: observed.
- About one `colab exec` call in ten failed with a read timeout or hung before reaching the kernel during an A100 run: observed.
- `colab run` signal handling and websocket teardown: observed behavior of the CLI, reported with the task that produced this skill.

## Colab runtime

- [Colab FAQ](https://research.google.com/colaboratory/faq.html): runtimes have a maximum lifetime, background execution is a Pro+ feature, and the usage limits are not published and vary.
- [google/colab/runtime.py](https://github.com/googlecolab/colabtools/blob/main/google/colab/runtime.py): `google.colab.runtime.unassign()` posts to `http://${TBE_RUNTIME_ADDR}/unassign`, which the job wrapper's self-release reproduces.
- `TBE_RUNTIME_ADDR` is set in a kernel started through colab CLI 0.7.4 (`172.28.0.1:8011` on a CPU runtime): observed.
- `colab drivemount` on a fresh session printed a new OAuth consent URL (redirecting to `/tun/m/authorize-for-drive-credentials-ephem`) and waited for Enter; without a human it did not mount: observed.
- Colab presets `UV_SYSTEM_PYTHON=true`, `UV_INSTALL_DIR=/usr/local/bin`, `PYTHONPATH=/env/python`, and empty `UV_CONSTRAINT` and `UV_BUILD_CONSTRAINT`; `uv run pytest` fell back to the system pytest when the project environment lacked it: observed.
- The A100 runtime was an A100-SXM4-40GB with driver 580.82.07 and CUDA 13.0 on Ubuntu 24.04, with 12 vCPUs, 83 GB of RAM, and about 194 GB free under `/content`; the first `uv sync` with torch took about 40 seconds: observed.
- CUDA 12 NVIDIA wheels from a TensorFlow install overwrote `libnccl.so.2` of CUDA 13 torch in the same environment: observed.

## Hugging Face Hub

- [Upload files to the Hub](https://huggingface.co/docs/huggingface_hub/guides/upload): `upload_folder` and `hf upload` split large folders into several commits, a re-run resumes an interrupted upload, `run_as_future` uploads in the background, and `delete_folder` removes a folder.
- [HfApi reference](https://huggingface.co/docs/huggingface_hub/package_reference/hf_api): `HfApi.delete_folder` and `HfApi.super_squash_history`.
- [Storage limits](https://huggingface.co/docs/hub/storage-limits): private storage is 100 GB on a free account and 1 TB on PRO, super-squash is destructive and reaches the quota within 36 hours, and overwritten LFS files keep using storage until history is rewritten.
- `hf upload --help` and `hf download --help` (huggingface_hub 2.1.1): `--repo-type`, `--private`, `--quiet`, `--include`, and `--local-dir`.

## uv

- [uv installation](https://docs.astral.sh/uv/getting-started/installation/): the official installer.
- [uv environment variables](https://docs.astral.sh/uv/reference/environment/): `UV_SYSTEM_PYTHON` makes uv use the system interpreter.

## Lightning

- [ModelCheckpoint](https://lightning.ai/docs/pytorch/stable/api/lightning.pytorch.callbacks.ModelCheckpoint.html): `save_last` and `train_time_interval`.
- [checkpoint_connector.py](https://github.com/Lightning-AI/pytorch-lightning/blob/master/src/lightning/pytorch/trainer/connectors/checkpoint_connector.py): `ckpt_path="last"` resumes from the newest last checkpoint and, when none exists, warns and starts without one.
