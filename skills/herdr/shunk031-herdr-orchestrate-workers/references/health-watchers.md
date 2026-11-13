# Supplemental health watchers

Use the worker stall and runner failure watchers when passive alerts would help with the active task. After workers and state sources are available, run each script once in the foreground with `--once`; continue only when it exits successfully and prints `OK`. Resolve any alert or startup error before starting a background copy. Set the worker prefix, state-file globs, and optional SSH destination from the current task; repeat `--state-glob` or `--remote-state-glob` for additional patterns. Do not persist machine-specific values in this skill.

```bash
worker_watch_args=(--agent-prefix "$WORKER_PREFIX" --interval-seconds 900)
if [[ -n "${ORCHESTRATOR_NAME:-}" ]]; then
    worker_watch_args+=(--exclude-agent "$ORCHESTRATOR_NAME")
fi
runner_watch_args=(--state-glob "$STATE_GLOB" --interval-seconds 600)
if [[ -n "${REMOTE_HOST:-}" ]]; then
    runner_watch_args+=(--remote-host "$REMOTE_HOST" --remote-port "${REMOTE_PORT:-22}" --remote-state-glob "$REMOTE_STATE_GLOB")
fi

if ! HERDR_ENV=1 ~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-worker-stall-watch.sh "${worker_watch_args[@]}" --once; then
    printf '%s\n' 'Check the worker watcher output and resolve any alert or startup error before backgrounding.' >&2
    exit 1
fi
if ! ~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-run-failure-watch.sh "${runner_watch_args[@]}" --once; then
    printf '%s\n' 'Check the runner watcher output and resolve any alert or startup error before backgrounding.' >&2
    exit 1
fi

watch_runtime="$(mktemp -d "${TMPDIR:-/tmp}/herdr-watchers.XXXXXX")"
HERDR_ENV=1 ~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-worker-stall-watch.sh "${worker_watch_args[@]}" >"$watch_runtime/workers.log" 2>&1 &
worker_watch_pid=$!
~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-run-failure-watch.sh "${runner_watch_args[@]}" >"$watch_runtime/runners.log" 2>&1 &
runner_watch_pid=$!
if ! kill -0 "$worker_watch_pid" || ! kill -0 "$runner_watch_pid"; then
    kill "$worker_watch_pid" "$runner_watch_pid" 2>/dev/null || true
    printf 'Watcher startup failed; inspect %s/*.log.\n' "$watch_runtime" >&2
    exit 1
fi
```

Stop both watcher processes after reconciling the scoped work. These scripts are backstops; keep one lifecycle wait per worker and use the launcher's own self-watch for its process. Watcher output does not establish completion or replace direct state and transcript reads.

<!-- textlint-disable sentence-length -->

When a dispatched task includes a run expected to take 30 minutes or longer, these watchers are required rather than optional, and they still do not keep the user informed. This is the one exception to the no-polling rule in [Collect and reconcile](reconciliation.md#collect-and-reconcile): the orchestrator also starts its own background progress watch on the run's output artifacts that exits when the expected count is reached, when the output stops growing for 15 minutes while the producing process is alive, or when that process exits, and it handles each exit and re-arms the watch. At each stage end, and at least hourly during an otherwise silent run, it reports to the user the counts done and expected, the elapsed time from the original request, and an ETA computed from observed throughput. Worker milestone reports and lifecycle waits do not replace these checks or updates, because a worker can end its turn without continuing or keep running without reporting.

<!-- textlint-enable sentence-length -->
