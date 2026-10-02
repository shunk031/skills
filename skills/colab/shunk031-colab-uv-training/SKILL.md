---
name: shunk031-colab-uv-training
description: Run, monitor, or resume long GPU training and test jobs from uv repositories on Google Colab, with durable results and runtime teardown. Use for job lifecycle or recovery; use colab-operator for CLI basics and short snippets.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🛰️ I read shunk031-colab-uv-training.`

# Colab uv training

Complete the requested GPU job, preserve its results outside the runtime, and release the task's VM. Continue through monitoring, result retrieval, and teardown within the authorized run scope; launching a cell is not completion.

Use the repository's existing training command, checkpoint format, and approved artifact destination. The bundled wrapper supports Hugging Face Hub storage. Use it when that destination fits the task; keep a working repository-specific runner or storage integration when it already provides equivalent persistence and teardown.

## Before allocating a runtime

Resolve the target commit, job command, GPU, run limit, and artifact destination from the request and repository. Ask only for missing choices that affect cost, external writes, or the requested result. Reuse existing authorization for the task's allocation, uploads, and teardown. A job request does not authorize purchasing compute units, stopping unrelated sessions, or deleting stored artifacts.

Check `colab usage` against the run budget and `colab version` against the supported CLI baseline of 0.7.4. Use a named session and retain its endpoint so retries and cleanup stay tied to this task. If CLI basics or authentication are needed, consult the colab-operator skill when available, otherwise the relevant `colab --help` command.

## Read for the current operation

- For a fresh VM or an environment failure, read [environment.md](references/environment.md). It covers Colab's Python overrides and symptom-specific dependency repairs.
- To launch and monitor a long job, read [running-jobs.md](references/running-jobs.md). It covers the busy kernel cell, the Hub wrapper, credentials, and result verification.
- To resume, recover a disconnected client or failed upload, or clean up leaked runtimes, read [recovery.md](references/recovery.md). Account-wide sweeping is a separate operation with a broader scope than one job.
- To check a version-sensitive claim or its evidence, use [sources.md](references/sources.md). Dated observations are not guarantees about the current runtime.

## Constraints that apply throughout

- `/content` is ephemeral. Save checkpoints and logs off the VM during execution, and leave time for a final upload before the runtime or job limit. Runtime lifetime depends on plan, balance, and availability.
- A client timeout does not prove the cell stopped. Check task logs and runtime state before relaunching; do not submit duplicate work to a busy kernel.
- Keep secrets out of `colab exec --env`, command text, and logs. Use uploaded, restricted files as described in the launch reference.
- Recover the only copy of results before releasing a VM retained after an upload failure. A wrapper exit code alone proves neither durable storage nor successful unassignment.

## Completion

Verify the job outcome from its exit status and expected artifacts, retrieve the requested results, and confirm the task's endpoint is no longer assigned after self-release or `colab stop -s <name>`. Other sessions may legitimately remain. If the user requested that this runtime stay available, preserve that choice and report its ongoing allocation instead.

Report the tested commit, job outcome, durable artifact location, and runtime state. If recovery or release fails, report the remaining endpoint, available results, and next action. Do not declare the run complete while task-owned cleanup remains unresolved.
