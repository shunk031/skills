---
name: shunk031-herdr-tab-status
description: Choose and update the current Herdr worker tab name with exact leading status emojis for active work, blocked work, user handoffs, and completion. Use whenever a Herdr tab label or its status meaning must be chosen or updated.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🚦 I read shunk031-herdr-tab-status.`

# Herdr Tab Status

The worker owns its current tab and follows the `herdr` skill to rename it whenever the progress state changes, including entering or leaving a retry. The leading emoji is the primary signal because the task label may be truncated. Put status only in the tab label; keep workspace and worktree labels emoji-free.

Before each rename of your own tab, resolve it from the current pane. A moved pane can keep a stale inherited `HERDR_TAB_ID`; `herdr pane current --current` returns the live ID as `.result.pane.tab_id`. Rename that tab and verify that Herdr returns the same tab ID and label:

```bash
label="🚧 <current step>"
rename_result=""
tab_id="$(herdr pane current --current | jq -er '.result.pane.tab_id')" &&
    rename_result="$(herdr tab rename "$tab_id" "$label")" &&
    printf '%s\n' "$rename_result" |
    jq -e --arg tab_id "$tab_id" --arg label "$label" \
        '.result.tab | .tab_id == $tab_id and .label == $label' >/dev/null ||
    { printf 'tab rename not verified: %s\n' "${rename_result:-no response}" >&2; false; }
```

On a nonzero exit, the label was not set on your tab. Do not report it as set.

`🚧`, `✅`, and `⛔` apply only to worker tabs. When the current agent is the orchestrator, preserve or set `🤖 Orchestrator` according to `shunk031-herdr-orchestrate-workers`; never replace it with a worker status while routing work.

Use exactly these states:

- `🚧 <current step>` means work is actively progressing, including a live retry or diagnostic run.
- `⛔ <next action>` means the worker cannot progress or close: it is waiting for an answer, review, approval, or merge; an external dependency blocks it; or it was stopped/superseded and awaits handoff or cleanup.
- `✅ <task> <PR number>` means worker work and the required handoff are complete, with no action remaining.

A published but open PR with DONE reported is still blocked while review or merge is user-only; keep the worker's `⛔` next-action label until that action resolves, then use completion only when no action remains. The worker renames its own tab. The orchestrator may set the blocked label only for a silent or dead worker, using the destination tab ID returned by its `pane move`; `pane current --current` resolves the orchestrator's own tab, so it cannot identify the worker tab for that rename. The orchestrator must not change another live worker's tab during normal work. A completion label always keeps a concise task and PR number, never a generic `DONE`.

When asked to choose a label, put the literal label on the first line, then explain it.

Before reporting BLOCKED, run the rename and report in one guarded sequence. The normal BLOCKED report is sent only after Herdr returns the requested tab ID and label. On failure, report that the rename was not verified:

```bash
label="⛔ <next action>"
report="BLOCKED <worker>: <reason>"
failure_report="BLOCKED <worker>: tab lookup or rename failed, so the label was not set. <reason>"
rename_result=""
if tab_id="$(herdr pane current --current | jq -er '.result.pane.tab_id')" &&
    rename_result="$(herdr tab rename "$tab_id" "$label")" &&
    printf '%s\n' "$rename_result" |
    jq -e --arg tab_id "$tab_id" --arg label "$label" \
        '.result.tab | .tab_id == $tab_id and .label == $label' >/dev/null; then
    herdr agent prompt <orchestrator> "$report"
else
    printf 'tab rename not verified: %s\n' "${rename_result:-no response}" >&2
    herdr agent prompt <orchestrator> "$failure_report"
    false
fi
```

The `BLOCKED` reason must state why the worker cannot progress or close, such as an unavailable external dependency or stopped/superseded handoff.

Follow the `herdr` skill's Herdr-environment and current-tab safety requirements before issuing tab commands.
