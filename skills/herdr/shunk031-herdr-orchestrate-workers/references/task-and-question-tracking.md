# Task and question tracking with the inbox mod

Use these procedures when the inbox mod is available.

## In-progress tasks

- Keep the durable ledger as the source of truth; an inbox finding mirrors a ledger row but does not own task state.
- Use `mcp__inbox__record_finding` to create one finding for each in-progress task.
- Close a finding only when its task is verified done or dropped, using `mcp__inbox__close` with the finding's `id` and a short reason.
- Reserve inbox `task` entries for actions only the user can take; do not use them for worker-owned in-progress tasks.

## User blockers

- Include each blocking user decision or action in the user-facing report so the mod's post-turn update adds it to the `Needs you` list. Do not repeat open inbox items in later reports.
- Use questions for choices that block continued work, and tasks only for actions the user can take that block continuing or finishing.
- Make each item stand alone: state what the user should decide or do, why it is needed or what it blocks, your recommendation, and what you will do if there is no answer. Include the exact command or link when relevant.
- Use `mcp__inbox__record_finding` for out-of-scope issues or opportunities, not user decisions or actions that block progress.

## Close user items

- Close a question only after the user answers it. Close a task only when its action is verified done or no longer applies.
- Use `mcp__inbox__close` with the item's `id` and the user's answer or a short reason. Never close a question with your own answer.
