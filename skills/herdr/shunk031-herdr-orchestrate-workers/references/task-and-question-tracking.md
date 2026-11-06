# Task and question tracking

Apply the reporting rule below in every user-facing reply. Use the inbox-specific procedures when the inbox mod is available.

## In-progress tasks

- Keep the durable ledger as the source of truth. Use `mcp__inbox__record_finding` to maintain exactly one finding per in-progress row, syncing its task, owner, state, and next action whenever the row changes. Findings mirror the ledger but do not own task state.
- Close a finding only when its task is verified done or dropped, using `mcp__inbox__close` with the finding's `id` and a short reason.
- Reserve inbox `task` entries for actions only the user can take; do not use them for worker-owned in-progress tasks.

## User decisions and actions

- End every user-facing reply with a short "Waiting on you" list of every open user decision and action, one line each stating what the user should decide or do and the recommended option, if any. Include expired items that still block work; repeat open items until answered or completed. Omit the list only when nothing is waiting.
- Include each blocking user decision or action in the report so the mod's post-turn update adds it to the `Needs you` list.
- Use questions for choices that block continued work, and tasks only for actions the user can take that block continuing or finishing.
- Include the exact command or link needed for the action when relevant.
- Use `mcp__inbox__record_finding` for out-of-scope issues or opportunities, not user decisions or actions that block progress.

## Close user items

- Close a question only after the user answers it. Close a task only when its action is verified done or no longer applies.
- Use `mcp__inbox__close` with the item's `id` and the user's answer or a short reason. Never close a question with your own answer.
