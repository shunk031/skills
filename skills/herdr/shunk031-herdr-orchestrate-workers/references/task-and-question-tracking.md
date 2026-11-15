# Task and question tracking

Apply the reporting rule below in every user-facing reply. Use the inbox-specific procedures when the inbox mod is available.

## In-progress tasks

- Keep the durable ledger as the source of truth. Meta maintains its open work and user-only tasks in the active-items file through the `shunk031-herdr-meta-orchestrate` helper; the Inbox reads that same file. Do not mirror these rows with Inbox `record` or `close` calls. Update an entry when its task, owner, state or next action changes. Remove it only when the work is verified done or dropped.
- Workers report state changes to their owning root. Meta owns the central active-items file and tracks each worker's current task there.
- Reserve session-specific Inbox `task` entries for actions only the user can take. Meta's user-only tasks belong in the active-items file.

## User decisions and actions

- End a user-facing reply with a short "Waiting on you" list of open user decisions and actions, one line each stating what the user should decide or do and the recommended option, if any. List an item only when it is new, its content has changed, or it still blocks work, including an expired item, and never one the user has acknowledged or deferred unless it has changed since. Omit the list when no item qualifies.
- Include each blocking user decision or action in the report that raises it or changes it, so the mod's post-turn update adds it to the `Needs you` list.
- Use questions for choices that block continued work, and tasks only for actions the user can take that block continuing or finishing.
- For first reports or inbox entries, make each item stand alone: say what to decide or do, why it matters or blocks work, your recommendation, and what happens without an answer.
- Include an exact command or link when relevant.
- Use `mcp__inbox__record_finding` for out-of-scope issues or opportunities, not user decisions or actions that block progress.

## Close user items

- Close a question only after the user answers it. Close a task only when its action is verified done or no longer applies.
- If a question closes without the user's answer, raise it again in your next reply and record it again.
- For session-specific items, use `mcp__inbox__close` with the item's `id` and the user's answer or a short reason. Never close a question with your own answer. Close Meta's active-items entries with its helper after their source task is verified complete or no longer applies.
