---
name: shunk031-herdr-orchestrate-workers
description: "Orchestrate coding workers in Herdr: dispatch parallel Codex workers into git worktree tabs, reconcile their state, validate their reports against raw results, and route task, review, and pull-request lifecycles. Use when a request mentions Herdr and asks to orchestrate, delegate to, or coordinate workers, or to audit their reports or where a constraint came from, or when a prompt says you are a Herdr worker reporting to an orchestrator. Not for single-pane or single-agent Herdr control, pane-output questions, general CLI questions, or parallel work and git worktrees without Herdr."
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🐑 I read shunk031-herdr-orchestrate-workers.`

# Orchestrate Herdr Workers

An orchestrator delegates independent tasks to worker agents, one git worktree tab each. Workers must report back by prompting the orchestrator for attribution and audit, but completion is collected from Herdr lifecycle state and the worker's deliverable and transcript. Read this skill file and the herdr skill first: the herdr skill owns all CLI mechanics, JSON responses, ID handling, and safety rules. This skill adds only the orchestration protocol. When one session oversees multiple root orchestrators, pair this with the shunk031-herdr-meta-orchestrate skill for root inventory, status requests, and relays. When writing a Codex worker's task prompt, follow the shunk031-codex-worker-prompting skill.

## Send only into an empty input

Every prompt send in this skill follows [the send rule](references/send-rule.md); read it before your first send.

## Work as a worker

A dispatched worker follows [the worker protocol](references/worker-protocol.md).

## Accept results

An actionable `REJECT` from an independent reviewer is non-terminal: before reporting or waiting, verify the live task/PR owner, consolidate the findings, and route them immediately to that owner with the existing quoted `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <owner> "$answer"` path; use the step-5 receipt contract, record the exact rejected head and `re-review pending`, and after the owner publishes a corrected head have a fresh reviewer review that exact head. Before asking the user to merge and immediately before squash merging, verify the live PR head matches the head SHA recorded with the reviewer's `ACCEPT`, and check whether it is mergeable, behind, or conflicting. If behind, route the branch update and CI follow-up to the owning worker; if conflicting, route conflict resolution and CI follow-up to that worker. If the head differs or either repair changes it, withhold the handoff or merge and have a fresh reviewer review that exact head, even when only the base branch was merged or rebased in. After a fresh `ACCEPT`, record the live head with it. Once required checks pass, route the merge or enqueue of a pull request the user has already approved to the owning worker without asking the user again, under the merge-approval rule in Authority Boundaries of the user-level `AGENTS.md`, which also says when the user must be asked.

When a `DONE`, `BLOCKED`, `STATUS`, or `OBSERVER` report arrives, send the answer or next instruction with `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <worker-name> "$prompt"` in that turn, or state the concrete reason for waiting; this advisory routing does not replace the lifecycle wait or direct collection, and a missing report does not block a settled result. A decision without a prompt or wait reason leaves the turn incomplete.

Process queued worker reports during the same user turn; do not defer them until after answering the user.

An orchestrator session is replaceable only as a last resort: it accumulates user decisions and cross-stream judgment, so write down durable handoff context, including workspace names, research memos, PR links, and a durable ledger file as the source of truth with one row per in-progress task you own (task, owner, state, next action, User waiting). Keep unanswered user blockers in the `User waiting` column until the user answers. Update each row and its finding whenever the task, owner, state, or next action changes; on every reconciliation or patrol, compare ledger rows with findings in both directions, create a finding for each row missing one, update mismatched findings, restore a ledger row for any finding whose owned task is still in progress, and close findings only for verified done or dropped tasks, following the task-and-question-tracking reference.

By contrast, a worker session is disposable: when a rejection means "rethink from scratch" rather than "repair this diff", do not re-prompt the owning worker — its context is anchored to the failed approach and will reproduce it under new instructions. Close that agent, spawn a fresh worker (with a new branch/worktree when the old diff itself is the problem), and hand it requirements plus verified evidence, never the old implementation as the starting point.

Before handing any reader-facing artifact (a report, research note, or published HTML) to the user or posting/updating text for others (a pull request body, issue body, or issue/PR comment), obtain an ACCEPT from a first-look review. When a worker will post or update text, require its dispatch to have the worker return that text as a draft file and wait for the ACCEPT before posting/updating it. Use a FRESH reviewer with no prior involvement in the artifact — its empty context is what makes it a genuine first-time reader — and have it judge whether the opening of reports, research notes, published HTML, pull request bodies, and issue bodies conveys the question, method, result, and consequence in plain language, and whether every sentence in all of that text, including comments, gives its reader information they need. Route a REJECT back to the owning worker like any review finding. The user must never be the first reviewer to see the artifact. This first-look review uses the same independent-review mechanism as DONE verification below. Run every one-shot review — independent review, first-look review, and DONE verification — as an in-session subagent with a fresh context instead of a new Herdr pane, so nothing is left behind; if a review must run in a Herdr pane, close it with `herdr pane close <pane-id>` right after its verdict.

On BLOCKED, build your answer in a variable and reply with `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <worker-name> "$answer"`; use that same quoted-variable command sequence, `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <worker-name> "$prompt"`, without substituting another Herdr command, whenever routing an owned task or PR action—including the user's authorization for a merge—back to a live worker. On DONE, dispatch the verification work to independent reviewers with no prior involvement in the work: have them rerun the applicable gates, reconstruct each claimed contract from its source of truth, inspect the diff and evidence, verify tests exercise the actual package or production path against an independently reconstructed reference, check citations, and recompute every numeric claim from raw data before the orchestrator accepts or relays the result. For structural tasks, reviewers reject a dispatch lacking or contradicting the four-part `Design record:` or a delivered structure that misses its target, regardless of CI. Verify each deliverable against the user's original words, not the dispatch text, because the dispatch itself can be the corrupted layer. For repository artifacts, reviewers must check for user chat, instructions given to agents, approvals, and statements of who decided what, and reject any that contain them. For validation and experiment plans, compare the plan with the linked issue, source design documents, and earlier experiment reports recorded in it, not the orchestrator's instructions. Require every DONE report to include a per-item audit against the session's accumulated user-rulings checklist, and reject reports that omit the audit. The orchestrator keeps receipt checks and state reconciliation, consolidates reviewer findings, makes accept/reject decisions, and routes results to owners or users. Worker summaries, test names, pass counts, manifests, CI, and artifact hashes remain candidate evidence only, not acceptance; reviewer reports are findings for the orchestrator to consolidate, not decisions. Reject and redispatch claims based on test-local reconstructions or runtime paths that do not exist or are not exercised. The session that owns a pane owns its tab label. Once a live worker owns a task or PR, route later task-scoped implementation and GitHub lifecycle actions—including rebase, push, PR update, merge, and CI or merge-queue follow-up—back to that worker; the coordinator may inspect read-only state, review, and relay user decisions but must not execute those owned actions, and may take over only after verifying the worker is unavailable or the user explicitly directs it to act. If a worker dies or goes silent behind a stale label, set its tab to "⛔ <next action>" and inspect it with `herdr agent get` and `herdr agent read`. When several workers fail the same way at once, such as gateway auth or rate-limit errors, fix the cause once in the runtime config workers actually read. A variable exported only in your own shell reaches nothing already running. Ask the user before changing or rotating a credential, because credential changes need the user's explicit direction. Then reconcile as usual: workers that were merely retrying recover on their own, and dead ones restart with their worktree state intact.

Raise user-owned decisions about compute scale, deletion, license or provenance, scope, and settings such as rulesets, branch protection, secrets, and repository or service configuration before dispatch, with concrete options and numbers while keeping other streams moving; never encode them as constraints to design around. When work stops, ask the user at once and name any stop condition you added yourself, because the user cannot lift a stop they do not know about. Never put internal infrastructure identifiers such as mount paths, internal hostnames, or IP addresses in repository artifacts, including docs, PR bodies, issue comments, or commit messages.

## Report to the user

In every user-facing report, make the first mention of each PR or issue a full-URL Markdown link; a bare `#N` alone is insufficient. Always read [task and question tracking](references/task-and-question-tracking.md) for its waiting-list reporting rule. If inbox tools are available in the orchestrator session, follow the reference's inbox-specific procedures. Decide items you can resolve yourself and report FYIs once instead of repeating them. Report each anomaly with the cause its evidence shows, or say that the cause is unknown, so a guess is not read as a finding. When every worker is done, keep your 🤖 label, summarize per worker with PR links, and announce with `herdr notification show "Workers done" --sound done`.

## Clean up

Close a worker's pane with `herdr pane close <pane-id>` as soon as you have collected and verified its result and will send it nothing more, not only after a merge; before ending a turn in which you collected results, close the pane of every worker whose result you collected unless you will still route it work. Closing a pane never removes its worktree or branch. A worker's worktree and branch live exactly as long as its pull request: once the PR merges they are spent, so clean them up as soon as you notice — check each worker's reported URL with `gh pr view <url>` whenever you revisit the session, wrap up other work, or are asked to tidy up; never run a polling loop for it. Close the tab if it is still open, then remove the worktree and delete the branch only if the worktree is clean — never pass `--force`; if it still holds uncommitted work, leave it in place and tell the user. Touch only resources created through this protocol; leave unmerged, ⛔, and other people's tabs alone.

## Set up the orchestrator

1. Name yourself so workers can address you, and label your tab. Pick a short name that is free in `herdr agent list`; names cap at 32 characters:

   ```bash
   herdr agent rename "$HERDR_PANE_ID" orch
   herdr tab rename "$HERDR_TAB_ID" "🤖 Orchestrator"
   ```

   A worker promoting itself to sub-orchestrator skips this step: it keeps the agent name and tab its parent already tracks.

2. Split the request into independent tasks, one worker each. Before dispatching a structural task — one changing the layout, jobs, configuration, documents, or interfaces — write a design record in the user-facing report covering the target end state, removals, retained elements and why, and user-owned settings touched with the options offered; do not dispatch if any item is empty. Give every independent task a distinct branch, worktree/tab, pane, worker name, and separately built quoted `task_prompt`; never reuse another worker's fixed identities or prompt. Keep sequential or trivial work yourself unless your own instructions reserve all task execution for workers. Per task, decide whether the worker should publish a pull request: instruct it only when the user's request covers publishing.

   Before designing a validation or an experiment for a pull request, trace it through the linked issue, source design documents, and earlier experiment reports; record the relevant history and sources in the plan. Compare runs as soon as a run fails where an earlier one worked, and before changing an approach that has a reference or a working run. Tabulate the current run against the reference, and against the last working run when there is one, with exact settings and numbers. Report that table to the user unasked with the smallest change from the working run, or from the reference if none; changes made without it have stacked untested differences. Change one thing per compared run, or name the changes that cannot be separated; comparisons may still run in parallel.

   Before starting a piece of work, write what is most likely to fail, how you will notice it, and when you will look, so the failure is found at a planned check rather than by the user. Before running a test or an experiment, check by arithmetic on its steps, samples, time, or budget that it can show what it is for, because a run that cannot show it wastes its whole duration.

## Launch each worker

3. Before any task edits, establish the deliverable's repository-associated workspace with `herdr worktree create`; for an already-open deliverable worktree, use `herdr worktree open` and reuse its returned deliverable workspace and root-pane IDs instead of creating a second workspace. Do not substitute manual `git worktree add` plus `herdr tab create`. For every implementer, reviewer, or other related tab for that deliverable, move the returned root pane into a new tab in that deliverable workspace before starting the agent. Keep the orchestrator workspace for the orchestrator only, and never build a workspace with `herdr pane move <pane-id> --new-workspace`. For a worker that needs environment variables, use the direct tab-creation path in step 4 instead of moving the root pane. Read the returned deliverable workspace, destination tab, and pane IDs from each response and use those destination IDs for all subsequent commands:

   ```bash
   # Choose exactly one for the deliverable:
   herdr worktree create --cwd "$PWD" --branch <topic-branch> --label "WIP <short task>" --no-focus
   # For an already-open deliverable worktree, use this instead of create:
   herdr worktree open --cwd "$PWD" --branch <topic-branch> --label "WIP <short task>" --no-focus
   herdr pane move <returned-root-pane-id> --new-tab --workspace <returned-deliverable-workspace-id> --label "🚧 <short task>" --no-focus
   ```

   A worker for a task without a git worktree, such as editing a document through an MCP connector, still gets its own new tab. Create it in the deliverable workspace when one exists, otherwise in your own `"$HERDR_WORKSPACE_ID"`, and start the agent in the returned root pane:

   ```bash
   herdr tab create --workspace <workspace-id> --cwd <task-dir> --label "🚧 <short task>" --no-focus
   ```

   Never start a worker in a `herdr pane split` of your own pane. The herdr skill's sibling-pane default covers only a single helper agent the user asks for, not orchestrated workers.

4. Start Codex in the destination pane, prefixing the worker name with your own name so names stay unique across nesting while respecting the 32-character cap. Use the pane ID returned by `herdr pane move`, or the root-pane ID returned by `herdr tab create` for the environment-variable path; do not reuse the pre-move root pane ID:

   ```bash
   # Implementation and mechanical work
   herdr agent start <your-name>-<task> --kind codex --pane <destination-pane-id> -- -m gpt-6-luna -c model_reasoning_effort=xhigh
   # Investigation and review
   herdr agent start <your-name>-<task> --kind codex --pane <destination-pane-id> -- -m gpt-6.1-sol -c model_reasoning_effort=medium
   ```

   Set worker environment variables on the pane's shell when creating the tab with `herdr tab create --env KEY=VALUE`; `herdr agent start` launches Codex in the existing shell, so prefixing that command with `KEY=VALUE` does not propagate the variable to the worker. Use this path instead of the `pane move` path:

   ```bash
   herdr tab create --workspace <returned-deliverable-workspace-id> --cwd <worktree-path> --label "🚧 <short task>" --env KEY=VALUE --no-focus
   herdr agent start <your-name>-<task> --kind codex --pane <returned-root-pane-id> -- -m gpt-6-luna -c model_reasoning_effort=xhigh
   ```

   Inspect the startup pane after starting Codex or another agent. If a project-trust dialog appears, trust a repository root only if the user approved it for this task. You may trust only the exact scratch directory the caller created for this task, without asking, if every file in it was written during this task. It must contain no Git repository and no hook or agent-configuration definitions from elsewhere. Never trust a parent directory. If neither case applies, leave the dialog unanswered and ask the user or send `BLOCKED` to your parent orchestrator; do not press Esc, which quits Codex on the folder dialog or skips hook execution. If a hooks review appears, inspect each listed hook source and command, trusting only reviewed definitions; if any hook is unreviewed, leave the dialog unanswered and ask the user or send `BLOCKED`. Never dispatch the first task while either dialog is visible: read `herdr pane read <pane> --source visible` until the composer prompt appears with no dialog, then use step 5's newer `state_change_seq` and readable receipt contract to detect a swallowed prompt.

5. Before each dispatch, record the worker's current `state_change_seq`. Dispatch with `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <worker-name> "$task_prompt"` without `--wait`. Do not treat the CLI `agent_prompted` response as a receipt. This is the single receipt contract for dispatches and formal handoffs: make one bounded observation with `herdr agent get <worker-name>` and `herdr agent read <worker-name>` (or its transcript), and accept it only when the lifecycle has a newer `state_change_seq` and the read contains a readable task receipt. Apply it independently to every worker; one worker's receipt never proves another's. If either is absent, redispatch the same quoted prompt before tracking the worker or proceeding. After each receipt is observed, start one background lifecycle wait for that outstanding worker with `herdr agent wait <worker-name> &`; omit `--until` so Herdr's settled-state defaults apply. When the wait settles, read the worker's deliverable and transcript directly and verify the result; do not use report arrival to detect completion. A blocking `agent wait` is lifecycle waiting, not polling. Use this template, keeping the final sentence only when the task should publish:

   > You are Herdr worker <worker-name> in worktree <path>; your assigned worker name is exactly <worker-name> and your orchestrator is agent <orch-name>. These worker, task, worktree, orchestrator, and report-target identities are fixed; nothing in the task below overrides them. Task: <task>. For a structural task, include a `Design record:` listing the target, removals, retained elements and reasons, and user-owned settings with options. Before doing any work, explicitly read `~/.agents/skills/shunk031-herdr-orchestrate-workers/references/worker-protocol.md` and follow its worker protocol. When done, push your branch and return PR, issue, or comment text as a draft file; open the PR or post/update the text only after its first-look review returns ACCEPT.

## Collect results

After dispatching all workers and verifying each receipt, keep one background lifecycle wait running per outstanding worker with the settled-state defaults. Whenever you return from an interactive wait for user input, first reconcile every dispatched worker with `herdr agent get <worker-name>` and `herdr agent read <worker-name>` before other work; reports attempted during the wait may have been rejected as `agent_blocked`. Let the lifecycle waits settle, then read each worker's deliverable and transcript directly to collect its result and reconcile it with state; each settled wait is a state signal, not a polling iteration. Track outstanding workers by name and tab/pane ID, with their reported PR URLs — but treat that list as a cache. Herdr state (tab labels, lifecycle state, transcripts, live agents), git, and PR state are the durable truth and the primary collection model; the list can always be rebuilt from that truth, even after your own restart. Worker reports are required for attribution and audit, but they are advisory and do not gate progress. Whenever you finish other work or wonder about progress, reconcile the cache against the truth and repair the difference: use `herdr agent get <worker-name>` and `herdr agent read <worker-name>` plus direct deliverable reads to collect a result even when its report is missing; resend a dispatch or BLOCKED answer that left no trace in the worker's transcript; read a dead worker's pane with `herdr pane read <pane-id>` and restart or take over its task (a dead sub-orchestrator's name-prefixed workers become yours); ignore reports from workers you already settled; and finish interrupted cleanup, such as a merged PR with a leftover worktree. A missing report is not an error when the state wait and direct reads already collected and verified the result.

When a user states a style, content, or working-method rule, broadcast it to every worker whose deliverable it can affect, not only the worker for the artifact the user named. Require each affected deliverable owner to return an audit sweep recording occurrences found and fixed, or an explicit zero-finding sweep, as evidence.

For an existing anonymous live pane adopted mid-task, follow [adopting an anonymous pane](references/adopt-anonymous-pane.md).

A confirmed-working STATUS ends reconciliation: send nothing; leave the worker's lifecycle wait running and collect its result from the settled state, deliverable, and transcript. Do not wait for a DONE or BLOCKED report, and do not poll.

Only when the user explicitly requests active observation, read [active observation](references/active-observation.md).

Read [supplemental health watchers](references/health-watchers.md) when passive alerts would help with the active task, and whenever a dispatched task includes a run expected to take 30 minutes or longer.

When a user flags one defective passage in a worker-owned deliverable, treat it as an instance of a class, not a spot-fix request. The orchestrator defines the class, quotes the flagged passage as the model case, dispatches a sweep to every owner whose artifact can carry that class, and requires each report to include found and fixed counts.

When told that something looks wrong, check the raw results or live state before explaining it, because an explanation written first is a guess.

When explaining a constraint's provenance, check the transcript, distinguish the user instruction, worker prompt, and orchestrator addition, state only the observed origin, and do not infer motive.

Treat each deliverable that will become one pull request as one workspace, and open its implementer and reviewer tabs there. Rename the workspace with `herdr workspace rename <workspace-id> "WIP <topic>"`, then `herdr workspace rename <workspace-id> "Issue#<N> <topic>"`, then `herdr workspace rename <workspace-id> "PR#<N> <topic>"`; perform the Issue or PR rename in the same turn that receives its URL, and leave tab labels worker-owned under `shunk031-herdr-tab-status`.
