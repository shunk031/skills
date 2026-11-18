# Task and question tracking

Apply the reporting rule below in every user-facing reply. When the Inbox tools are available, also follow [Inbox-specific procedures](inbox.md).

## In-progress tasks

- Keep the durable ledger as the source of truth. Update an entry when its task, owner, state or next action changes; remove it only when the work is verified done or dropped.
- Workers report state changes to their owning root.
- Meta owns the central active-items file and tracks each worker's current task there.
- Close Meta's active-items entries with its helper only after their source task is verified complete or no longer applies.

## User decisions and actions

- End a user-facing reply with a short "Waiting on you" list of open user decisions and actions, one line each stating what the user should decide or do and the recommended option, if any. List an item only when it is new, its content has changed, or it still blocks work, including an expired item, and never one the user has acknowledged or deferred unless it has changed since. Omit the list when no item qualifies.
- When relaying a worker's or root's question, option, or recommendation to the user, apply the shared user-level rule on settled rulings and requirements to it first; fix conflicts or name them.
- Before presenting options, a recommendation, or a plan, fetch the related SPEC or design record, its PR review threads, and the user's earlier Inbox answers. Check each answer against its original thread. Keep an internal note with binding decisions and source links, how the proposal relates to each, and what could not be checked. Present no conflicting option unless you name the binding decision and explain why it no longer holds. The orchestrator and reviewers judge semantic conflicts; do not claim a hook can detect re-proposals.
- Include each blocking user decision or action in the report that raises it or changes it.
- Keep unanswered user decisions in the ledger's `User waiting` column until answered; keep blocking user actions there until complete or no longer applicable.
