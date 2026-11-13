# Adopt an anonymous pane

<!-- textlint-disable sentence-length -->

For an existing anonymous live pane adopted mid-task, assign it a unique agent name from current Herdr state with `herdr agent rename <pane-id> <unique-name>`, then build `handoff_prompt` in a quoted variable and send `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <worker-name> "$handoff_prompt"` with fixed worker, task, worktree, orchestrator, and report-target identities; verify that handoff with [the “Dispatch and receipt” section in `references/dispatch.md`](dispatch.md#dispatch-and-receipt), then require the worker's `STATUS <worker-name>: <state>` receipt through the literal command `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <orch-name> "$status"`. A tab-label change, ordinary task-channel output, PR creation, or CI state is not notification evidence by itself.

<!-- textlint-enable sentence-length -->
