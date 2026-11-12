# Collect and reconcile Herdr workers

## Collect and reconcile

After dispatching all workers and verifying each receipt, keep one background lifecycle wait running per outstanding worker with the settled-state defaults.

Whenever you return from an interactive wait for user input, first reconcile every dispatched worker with `herdr agent get <worker-name>` and `herdr agent read <worker-name>` before other work; reports attempted during the wait may have been rejected as `agent_blocked`.

Let the lifecycle waits settle, then read each worker's deliverable and transcript directly to collect its result and reconcile it with state; each settled wait is a state signal, not a polling iteration.

Track outstanding workers by name and tab/pane ID, with their reported PR URLs — but treat that list as a cache.

Herdr state (tab labels, lifecycle state, transcripts, live agents), git, and PR state are the durable truth and the primary collection model; the list can always be rebuilt from that truth, even after your own restart.

Worker reports are required for attribution and audit, but they are advisory and do not gate progress.

Whenever you finish other work or wonder about progress, reconcile the cache against the truth and repair the difference: use `herdr agent get <worker-name>` and `herdr agent read <worker-name>` plus direct deliverable reads to collect a result even when its report is missing; resend a dispatch or BLOCKED answer that left no trace in the worker's transcript; read a dead worker's pane with `herdr pane read <pane-id>` and restart or take over its task (a dead sub-orchestrator's name-prefixed workers become yours); ignore reports from workers you already settled; and finish interrupted cleanup, such as a merged PR with a leftover worktree.

A missing report is not an error when the state wait and direct reads already collected and verified the result.

### Handle queued reports and active decisions

When a `DONE`, `BLOCKED`, `STATUS`, or `OBSERVER` report arrives, send the answer or next instruction with `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <worker-name> "$prompt"` in that turn, or state the concrete reason for waiting; this advisory routing does not replace the lifecycle wait or direct collection, and a missing report does not block a settled result.

A decision without a prompt or wait reason leaves the turn incomplete.

Process queued worker reports during the same user turn; do not defer them until after answering the user.

A confirmed-working STATUS ends reconciliation: send nothing; leave the worker's lifecycle wait running and collect its result from the settled state, deliverable, and transcript.

Do not wait for a DONE or BLOCKED report, and do not poll.

## Preserve orchestration context

An orchestrator session is replaceable only as a last resort: it accumulates user decisions and cross-stream judgment, so write down durable handoff context, including workspace names, research memos, PR links, and a durable ledger file as the source of truth with one row per in-progress task you own (task, owner, state, next action, User waiting).

Keep unanswered user blockers in the `User waiting` column until the user answers.

Update each row and its finding whenever the task, owner, state, or next action changes; on every reconciliation or patrol, compare ledger rows with findings in both directions, create a finding for each row missing one, update mismatched findings, restore a ledger row for any finding whose owned task is still in progress, and close findings only for verified done or dropped tasks, following the task-and-question-tracking reference.

By contrast, a worker session is disposable: when a rejection means "rethink from scratch" rather than "repair this diff", do not re-prompt the owning worker — its context is anchored to the failed approach and will reproduce it under new instructions.

Close that agent, spawn a fresh worker (with a new branch/worktree when the old diff itself is the problem), and hand it requirements plus verified evidence, never the old implementation as the starting point.

## Ownership and recovery

On BLOCKED, build your answer in a variable and reply with `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <worker-name> "$answer"`; use that same quoted-variable command sequence, `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <worker-name> "$prompt"`, without substituting another Herdr command, whenever routing an owned task or PR action—including the user's authorization for a merge—back to a live worker.

The session that owns a pane owns its tab label.

Once a live worker owns a task or PR, route later task-scoped implementation and GitHub lifecycle actions—including rebase, push, PR update, merge, and CI or merge-queue follow-up—back to that worker; the coordinator may inspect read-only state, review, and relay user decisions but must not execute those owned actions, and may take over only after verifying the worker is unavailable or the user explicitly directs it to act.

If a worker dies or goes silent behind a stale label, set its tab to "⛔ <next action>" and inspect it with `herdr agent get` and `herdr agent read`.

When several workers fail the same way at once, such as gateway auth or rate-limit errors, fix the cause once in the runtime config workers actually read.

A variable exported only in your own shell reaches nothing already running.

Ask the user before changing or rotating a credential, because credential changes need the user's explicit direction.

Then reconcile as usual: workers that were merely retrying recover on their own, and dead ones restart with their worktree state intact.

### Broadcast corrections and verify provenance

When a user states a style, content, or working-method rule, broadcast it to every worker whose deliverable it can affect, not only the worker for the artifact the user named.

Require each affected deliverable owner to return an audit sweep recording occurrences found and fixed, or an explicit zero-finding sweep, as evidence.

When a user flags one defective passage in a worker-owned deliverable, treat it as an instance of a class, not a spot-fix request.

The orchestrator defines the class, quotes the flagged passage as the model case, dispatches a sweep to every owner whose artifact can carry that class, and requires each report to include found and fixed counts.

When told that something looks wrong, check the raw results or live state before explaining it, because an explanation written first is a guess.

When explaining a constraint's provenance, check the transcript, distinguish the user instruction, worker prompt, and orchestrator addition, state only the observed origin, and do not infer motive.

### Scope observation and health monitoring

For an existing anonymous live pane adopted mid-task, follow [adopting an anonymous pane](references/adopt-anonymous-pane.md).

Only when the user explicitly requests active observation, read [active observation](references/active-observation.md).

Read [supplemental health watchers](references/health-watchers.md) when passive alerts would help with the active task, and whenever a dispatched task includes a run expected to take 30 minutes or longer.

## User reporting and decisions

Raise user-owned decisions about compute scale, deletion, license or provenance, scope, and settings such as rulesets, branch protection, secrets, and repository or service configuration before dispatch, with concrete options and numbers while keeping other streams moving; never encode them as constraints to design around.

When work stops, ask the user at once and name any stop condition you added yourself, because the user cannot lift a stop they do not know about.

Never put internal infrastructure identifiers such as mount paths, internal hostnames, or IP addresses in repository artifacts, including docs, PR bodies, issue comments, or commit messages.

In every user-facing report, make the first mention of each PR or issue a full-URL Markdown link; a bare `#N` alone is insufficient.

Always read [task and question tracking](references/task-and-question-tracking.md) for its waiting-list reporting rule.

If inbox tools are available in the orchestrator session, follow the reference's inbox-specific procedures.

Decide items you can resolve yourself and report FYIs once instead of repeating them.

Report each anomaly with the cause its evidence shows, or say that the cause is unknown, so a guess is not read as a finding.

When every worker is done, keep your 🤖 label, summarize per worker with PR links, and announce with `herdr notification show "Workers done" --sound done`.
