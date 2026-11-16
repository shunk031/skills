# Task and question tracking

Apply the reporting rule below in every user-facing reply. When the Inbox tools are available, also follow [Inbox-specific procedures](inbox.md).

## In-progress tasks

- Keep the durable ledger as the source of truth. Update an entry when its task, owner, state or next action changes; remove it only when the work is verified done or dropped.
- Workers report state changes to their owning root.
- Meta owns the central active-items file and tracks each worker's current task there.
- Close Meta's active-items entries with its helper only after their source task is verified complete or no longer applies.

## User decisions and actions

- End a user-facing reply with a short "Waiting on you" list of open user decisions and actions, one line each stating what the user should decide or do and the recommended option, if any. List an item only when it is new, its content has changed, or it still blocks work, including an expired item, and never one the user has acknowledged or deferred unless it has changed since. Omit the list when no item qualifies.
- Check each user-facing draft, question, option, and recommendation against accumulated user rulings before showing or relaying it; fix conflicts or name them.
- Include each blocking user decision or action in the report that raises it or changes it.
- Keep unanswered user decisions in the ledger's `User waiting` column until answered; keep blocking user actions there until complete or no longer applicable.
