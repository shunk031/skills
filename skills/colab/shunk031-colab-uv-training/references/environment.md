# Preparing a uv repository on Colab

Use this reference for a fresh runtime or a matching environment failure. The image and driver can change, so inspect the current VM before applying a repair from an earlier run.

Clone the requested repository and check out the exact commit. Initialize only the submodules the job needs. Let uv use the repository's Python pin and install the dependency groups or workspace members needed by the actual command.

Colab images have been observed to set `UV_SYSTEM_PYTHON=true`, `PYTHONPATH=/env/python`, and `MPLBACKEND=module://matplotlib_inline.backend_inline`. For direct project commands, clear them first with `unset UV_SYSTEM_PYTHON PYTHONPATH MPLBACKEND` because the `matplotlib_inline` backend exists only in Colab's system Python and can break imports in a uv environment. The bundled `colab-job.sh` wrapper clears them before loading its optional `--env-file`; the GPU launcher does not expose that wrapper option, so set job-specific values in the uploaded job script. Verify the interpreter and imports resolve to the project environment. Check `uv --version`; if uv is absent, use the environment's supported installer or the [official uv installer](https://docs.astral.sh/uv/getting-started/installation/). Inspect `UV_INSTALL_DIR` when choosing its destination.

## Repairs for observed failures

- If torch cannot use the GPU, inspect `nvidia-smi` and the installed torch build. The driver must support that build's CUDA runtime. Use a compatible wheel in the VM when necessary, without silently changing the repository's lockfile, and launch with `uv run --no-sync` after a deliberate environment override.
- If `import torch` fails after installing TensorFlow, inspect the NVIDIA package versions. CUDA 12 packages from TensorFlow have been observed to overwrite NCCL used by CUDA 13 torch. Reinstall the NCCL package matching the selected torch build and verify the import; do not prescribe `nvidia-nccl-cu13` for every image.
- If tests use the system pytest, install the repository's test dependency group or declared pytest version in the project environment. Prefer `uv run --no-sync python -m pytest` so a missing project installation fails visibly instead of resolving a system `pytest` executable.

For a single-GPU job, select its device with `CUDA_VISIBLE_DEVICES=0`. Use the repository's own accelerator and distributed settings when the requested job differs.

Version evidence and the dated image observations are in [sources.md](sources.md).
