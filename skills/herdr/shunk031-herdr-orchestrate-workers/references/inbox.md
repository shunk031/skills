# Inbox-specific procedures

Use these procedures only when the Inbox tools are available. Without Inbox, keep decisions in the user-facing reply and unanswered blockers in the ledger's `User waiting` column, as described in [task and question tracking](task-and-question-tracking.md).

## Record user items

- Include each blocking user decision or action in the report that raises it or changes it. Record every open user decision as an Inbox question with `mcp__inbox__record` in the same turn it is raised or changed; do not rely on post-turn extraction.
- Use questions for choices that block continued work, and session-specific tasks only for actions the user can take that block continuing or finishing. Reserve Meta's user-only tasks for its active-items file.
- For first reports or Inbox entries, say what to decide or do, why it matters or blocks work, your recommendation, and what happens without an answer. Include an exact command or link when relevant.
- Use `mcp__inbox__record_finding` for out-of-scope issues or opportunities, not user decisions or actions that block progress.
- Do not mirror work or task rows maintained by Meta's active-items helper with Inbox `record` or `close` calls.

## Close user items

- Close an Inbox question only after the user answers it. Close a task only when its action is verified done or no longer applies.
- If a question closes without the user's answer, raise it again in your next reply and record it again.
- For session-specific Inbox questions, use `mcp__inbox__close` with the item's `id` and the user's answer; for tasks, use a short reason. Never close a question with your own answer.

## Reconcile Meta work

When Inbox is installed, its read-only `Untracked work` warning can surface mismatches between live Meta-prefixed workers or roots waiting on the user and the active-items file. The warning is read-only and creates or closes no entries. Do not create, update, restore, or close a paired Inbox finding. Continue reconciling your own workers against Herdr state, deliverables, and your durable ledger.
