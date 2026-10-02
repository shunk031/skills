# Sources

Each entry names the fact in `SKILL.md` it supports. Facts marked as observed come from a run on a Colab A100 runtime and have no published source.

## colab CLI

- [googlecolab/google-colab-cli](https://github.com/googlecolab/google-colab-cli) and [google-colab-cli on PyPI](https://pypi.org/project/google-colab-cli/): the `colab` command, its subcommands, and the `colab exec --timeout` default of 30 seconds, also shown by `colab exec --help`.
- [googlecolab/google-colab-cli#147](https://github.com/googlecolab/google-colab-cli/issues/147): sessions were pruned as lost when the runtime-proxy token expired after about an hour while the VM stayed assigned, producing orphaned assignments. Fixed by [googlecolab/google-colab-cli#149](https://github.com/googlecolab/google-colab-cli/pull/149), released in 0.7.4.
- [googlecolab/google-colab-cli#144](https://github.com/googlecolab/google-colab-cli/pull/144) and the maintainer comment in [googlecolab/google-colab-cli#160](https://github.com/googlecolab/google-colab-cli/issues/160): without background execution, the backend keeps a runtime by kernel activity and live connections, and the client keep-alive ping does not extend it.
- [googlecolab/google-colab-cli#82](https://github.com/googlecolab/google-colab-cli/issues/82): a long `colab exec` timeout that is exceeded can spin a local CPU core indefinitely.
- `colab_cli/client.py` in the installed package: `Client.list_assignments()` reads `/tun/m/assignments`, and `Client.unassign(endpoint)` posts to `/tun/m/unassign/<endpoint>`; `colab_cli.common.state.client` is the authenticated client the CLI itself uses.
- `colab run` signal handling and websocket teardown: observed behavior of the CLI, reported with the task that produced this skill.

## Colab runtime

- [Colab FAQ](https://research.google.com/colaboratory/faq.html): runtimes have a maximum lifetime, background execution is a Pro+ feature, and the usage limits are not published and vary.
- [google/colab/runtime.py](https://github.com/googlecolab/colabtools/blob/main/google/colab/runtime.py): `google.colab.runtime.unassign()` posts to `http://${TBE_RUNTIME_ADDR}/unassign`, which the job wrapper's self-release reproduces.
- Colab exports `UV_SYSTEM_PYTHON` and `PYTHONPATH`, and an A100 runtime reported driver 580 with CUDA 13.0 in `nvidia-smi`: observed.
- CUDA 12 NVIDIA wheels from a TensorFlow install overwrote `libnccl.so.2` of CUDA 13 torch in the same environment: observed.

## uv

- [uv installation](https://docs.astral.sh/uv/getting-started/installation/): the official installer.
- [uv environment variables](https://docs.astral.sh/uv/reference/environment/): `UV_SYSTEM_PYTHON` makes uv use the system interpreter.

## Lightning

- [ModelCheckpoint](https://lightning.ai/docs/pytorch/stable/api/lightning.pytorch.callbacks.ModelCheckpoint.html): `save_last` and `train_time_interval`.
- [checkpoint_connector.py](https://github.com/Lightning-AI/pytorch-lightning/blob/master/src/lightning/pytorch/trainer/connectors/checkpoint_connector.py): `ckpt_path="last"` resumes from the newest last checkpoint and, when none exists, warns and starts without one.
