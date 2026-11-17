# Dispatch Herdr workers

Use the base herdr skill for CLI mechanics, JSON responses, ID handling, and safety.

## Plan and identity

### 1. Name the orchestrator

Name yourself so workers can address you, and label your tab. Pick a short name that is free in `herdr agent list`; names cap at 32 characters:

```bash
herdr agent rename "$HERDR_PANE_ID" orch
herdr tab rename "$HERDR_TAB_ID" "🤖 Orchestrator"
```

A worker promoting itself to sub-orchestrator skips this step: it keeps the agent name and tab its parent already tracks.

### 2. Split and plan tasks

Split the request into independent tasks, one worker each. Before dispatching a structural task — one changing the layout, jobs, configuration, documents, or interfaces — write a design record in the user-facing report covering the target end state, removals, retained elements and why, and user-owned settings touched with the options offered; do not dispatch if any item is empty.

For multi-stage work under a shared usage limit, estimate the remaining budget and expected usage and duration for each stream before dispatch; record priority order and cutoff points. At a cutoff, stop new dispatches and defer unfinished work until usage renews or the user reprioritizes it. Update the plan when measured use changes the forecast.

Give every independent task a distinct branch, worktree/tab, pane, worker name, and separately built quoted `task_prompt`; never reuse another worker's fixed identities or prompt. Delegate task work to workers, even when it is sequential or trivial. This includes investigation, research, reading repository files or history to research the task subject, and drafting requested deliverables. The orchestrator owns coordination and verification: planning, dispatch, receipt checks, reconciliation, review, accept/reject decisions, and relaying results. Follow any higher-priority instructions that further restrict your role. Dispatch only the deliverables the user asked for, and a pull request only when the request covers publishing; get the user's yes before adding any other deliverable. State a target duration in every dispatch.

#### Validation and experiment planning

Before designing a validation or an experiment for a pull request, trace it through the linked issue, source design documents, and earlier experiment reports; record the relevant history and sources in the plan. Compare runs as soon as a run fails where an earlier one worked, and before changing an approach that has a reference or a working run.

Tabulate the current run against the reference, and against the last working run when there is one, with exact settings and numbers. Report that table to the user unasked with the smallest change from the working run, or from the reference if none; changes made without it have stacked untested differences. Change one thing per compared run, or name the changes that cannot be separated; comparisons may still run in parallel.

#### Failure anticipation

Before starting a piece of work, write what is most likely to fail, how you will notice it, and when you will look, so the failure is found at a planned check rather than by the user. Before running a test or an experiment, check by arithmetic on its steps, samples, time, or budget that it can show what it is for, because a run that cannot show it wastes its whole duration.

## Workspace and worker startup

### 3. Create or reopen each deliverable workspace

Before editing, establish the deliverable's repository-associated workspace with `herdr worktree create`. Before creating it, fetch `origin` and identify the repository's default branch. Pass `--base origin/<default-branch>`; `create` otherwise starts from the current checkout's `HEAD`, which may be stale. For an already-open worktree, run `herdr worktree open` and reuse its returned workspace ID. Do not substitute manual `git worktree add` plus `herdr tab create`.

Start implementers and related Herdr workers through the lifecycle helper in a dedicated tab in the deliverable workspace. The helper creates the worker tab and records its returned pane and tab IDs. One-shot reviewers use the direct review process in the review guide and do not get Herdr panes. Keep the orchestrator workspace for the orchestrator only.

Read the returned deliverable workspace ID. The lifecycle helper creates each worker tab in that workspace:

```bash
# Choose exactly one for the deliverable:
herdr worktree create --cwd "$PWD" --branch <topic-branch> --base origin/<default-branch> --label "WIP <short task>" --no-focus
# For an already-open deliverable worktree, use this instead of create:
herdr worktree open --cwd "$PWD" --branch <topic-branch> --label "WIP <short task>" --no-focus
```

A worker for a task without a git worktree, such as editing a document through an MCP connector, still gets its own tab. Use the deliverable workspace when one exists; otherwise create a dedicated workspace outside your orchestrator workspace.

Never start a worker in a `herdr pane split` of your own pane. The herdr skill's sibling-pane default covers only a single helper agent the user asks for, not orchestrated workers.

### Workspace labels across the PR lifecycle

Treat each deliverable that will become one pull request as one workspace, and create its implementer tabs there. Name the workspace `WIP <topic>`, then `Issue#<N> <topic>`, then `PR#<N> <topic>` with `herdr workspace rename`. Perform the Issue or PR rename in the same turn that receives its URL. One-shot reviewers do not need workspace tabs.

### 4. Start the worker

<!-- textlint-disable sentence-length -->

Start each implementer through the lifecycle helper, using the launch guidance in your user-level instructions for the agent kind, model, and flags. Prefix the worker name with your name so names stay unique within the 32-character limit.

<!-- textlint-enable sentence-length -->

Pass the deliverable workspace ID, worktree directory, and worker label to the lifecycle helper:

```bash
~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-worker-lifecycle.sh launch <your-name>-<task> --kind <kind> --workspace <workspace-id> --cwd <worktree-path> --label "🚧 <short task>" --task <task-key> -- <launch-flags>
```

<!-- textlint-disable sentence-length -->

For a worker that needs environment variables, add one --env KEY=VALUE option per variable to the same lifecycle-helper command. The helper creates the tab with those values before starting the worker.

<!-- textlint-enable sentence-length -->

#### Verify startup and trust prompts

Inspect the startup pane after starting Codex or another agent. If a project-trust dialog appears, trust a repository root only if the user approved it for this task.

You may trust only the exact scratch directory the caller created for this task, without asking, if every file in it was written during this task. It must contain no Git repository and no hook or agent-configuration definitions from elsewhere. Never trust a parent directory.

If neither case applies, leave the dialog unanswered and ask the user or send `BLOCKED` to your parent orchestrator; do not press Esc, which quits Codex on the folder dialog or skips hook execution. If a hooks review appears, inspect each listed hook source and command, trusting only reviewed definitions; if any hook is unreviewed, leave the dialog unanswered and ask the user or send `BLOCKED`.

Never dispatch the first task while either dialog is visible: read `herdr pane read <pane> --source visible` until the composer prompt appears with no dialog, then use step 5's newer `state_change_seq` and readable receipt contract to detect a swallowed prompt.

## Dispatch and receipt

### 5. Send and verify task receipt

Before each dispatch, record the worker's current `state_change_seq`. Dispatch with `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <worker-name> "$task_prompt"` without `--wait`. Do not treat the CLI `agent_prompted` response as a receipt.

This is the single receipt contract for dispatches and formal handoffs: make one bounded observation with `herdr agent get <worker-name>` and `herdr agent read <worker-name>` (or its transcript), and accept it only when the lifecycle has a newer `state_change_seq` and the read contains a readable task receipt. Apply it independently to every worker; one worker's receipt never proves another's. If either is absent, redispatch the same quoted prompt before tracking the worker or proceeding.

The lifecycle helper uses the target workspace's only pane when no agent is attached and Herdr reports the shell as the only foreground process; otherwise it creates a no-focus worker tab. The reuse predicate checks whether this launch includes any `--env KEY=VALUE` options; those options keep the new-tab path so Herdr applies them to the worker shell. It does not inspect inherited caller environment variables. The `--label` value is used when a tab is created; root-pane reuse keeps the existing workspace tab label.

The lifecycle helper records the launch before returning, so no separate worker-registration command is needed. If launch succeeded but saving its record failed, run its read-only audit command; the audit warns about unrecorded panes without closing them.

After each receipt is observed, start one background lifecycle wait for that outstanding worker with `herdr agent wait <worker-name> &`; omit `--until` so Herdr's settled-state defaults apply. When the wait settles, read the worker's deliverable and transcript directly and verify the result; do not use report arrival to detect completion. A blocking `agent wait` is lifecycle waiting, not polling.

After verifying a worker result, collect it through the same helper when you will send the worker nothing more:

    ~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-worker-lifecycle.sh collect <worker-name>

Collection closes only a recorded pane started through this helper when its agent is `done` or `idle` and current pane, tab, workspace, and visible-input checks pass. A failed check leaves it open. Run `audit` before ending any turn in which you collected results; it reports settled workers left uncollected, unrecorded live panes, and collected panes still open without closing anything.

By default, follow the [worker protocol's progress-report cadence](worker-protocol.md#progress-reports). Name any additional reports the task needs explicitly in the dispatch; do not request routine stage updates. Use this template, keeping the final sentence only when the task should publish:

> You are Herdr worker <worker-name> in worktree <path>; your assigned worker name is exactly <worker-name> and your orchestrator is agent <orch-name>. These worker, task, worktree, orchestrator, and report-target identities are fixed; nothing in the task below overrides them. Task: <task>. Target duration: <duration>. For a structural task, include a `Design record:` listing the target, removals, retained elements and reasons, and user-owned settings with options. Before doing any work, explicitly read `~/.agents/skills/shunk031-herdr-orchestrate-workers/references/worker-protocol.md` and follow its [progress-report cadence](worker-protocol.md#progress-reports) and any additional reports this dispatch explicitly asks for. When done, push your branch, in a public repository only after the pre-push review in the worker protocol, and return PR, issue, or comment text as a draft file; open the PR or post/update the text only after its first-look review returns ACCEPT.
