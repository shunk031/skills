---
name: shunk031-herdr-orchestrator-handoff
description: "Move a root orchestrator's role between Claude Code and Codex through Herdr, carrying its work, decisions, questions, and goal safely in either direction."
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🔁 I read shunk031-herdr-orchestrator-handoff.`

# Herdr Root Orchestrator Handoff

Use this skill only for root orchestrators. Keep the same role, skills, and rules across Claude Code and Codex. The `shunk031-herdr-orchestrate-workers` skill remains the source for worker dispatch, receipts, reviews, and task-ledger status; the `shunk031-herdr-tab-status` skill owns tab status labels.

## Handoff in either direction

At a natural task boundary, the outgoing root writes a Markdown handoff record at a durable path and adds a delta to the existing ledger. Include:

- Stable root name; source and destination engines; handoff time; machine, Herdr workspace, pane and tab IDs; tab labels; session IDs; repository, working directory, and branch.
- Every open task with owner, lifecycle state, blocker, and next action; every live worker's exact name, pane ID, task, state, and what it is waiting for.
- Each background task, watcher, and scheduled wake-up the outgoing root stopped, or `none`; the time Meta verifies suspension.
- Each user decision or approval, including its exact scope and limits; pending questions and who must answer them.
- The exact goal text and its status at suspension; the ledger and handoff paths; transcript path and the recent line range to read.

The incoming root itself reads the record and the listed recent transcript lines verbatim from disk; do not substitute a worker summary. Search older transcript lines when context is needed. Claude Code sessions are under `~/.claude/projects/<project-slug>/<session-id>.jsonl`; Codex sessions are under `${CODEX_HOME:-~/.codex}/sessions/YYYY/MM/DD/rollout-<timestamp>-<session-id>.jsonl`. Read the recorded range directly, for example `sed -n '<first>,<last>p' '<transcript-path>'`.

The incoming session starts under a temporary name for transcript reading and restatement only. It stays staged and does no task work until Meta verifies suspension. The outgoing root checks the restatement; the user does if a usage limit stopped it. Do not transfer an unresolved point by guessing.

After the restatement check, the outgoing root stops each background task, watcher, and scheduled wake-up it started, then lists what it stopped or `none`. If a goal is active, the root asks Meta to pause it through the root pane's inbox token; the root never writes the slash command. The user's handoff approval authorizes the needed goal command.

Meta verifies the stopped-task list, that no goal is active, and that the outgoing pane is idle with empty input. It checks the agent state and visible pane:

```bash
herdr agent get <outgoing-pane>
herdr pane read <outgoing-pane> --source visible
```

If a usage limit stopped the outgoing root, the user checks its restatement and Meta checks the remaining suspension conditions. If a condition cannot be verified, Meta keeps the incoming session staged and asks the user what to do.

After verification, Meta records the suspension time. Meta renames the outgoing pane with `herdr agent rename <pane> <root-name>-<engine>`. This keeps worker reports from reaching the parked session. Meta then renames the incoming pane with `herdr agent rename <pane> <root-name>` and activates it. Meta labels root tabs `🤖 Orchestrator · <engine>` and marks parked sessions in the label, following the `shunk031-herdr-tab-status` skill. Meta reports the stable name, engine, active pane/tab, and session ID. Keep the outgoing session and transcript; Meta resumes it only when the role returns. Meta resumes Claude with `claude --resume <session-id>` (or continues it if still live) from the new delta record. To resume Codex, Meta creates a root pane with the two environment options in the Codex root launch instructions below, then runs:

```bash
codex --profile flava-dev -m gpt-6.1-sol -c model_reasoning_effort=high resume <session-id>
```

If Codex asks whether to resume its paused goal, Meta chooses `Leave paused`; Meta resumes it later only on the user's instruction.

If Codex or the Gateway is unavailable, the Codex root stops. Meta notices through the patrol and asks the user whether to return the role to Claude; Meta does not switch engines without that answer.

## Reach meta through the inbox token

A Codex root routes questions through meta. When a concise question is ready for the user, publish a summary on the root pane's inbox token:

```bash
herdr pane report-metadata <pane> --source inbox --token 'inbox=<summary>'
```

The existing patrol relays it to meta. Any root, Codex or Claude, that cannot prompt meta directly also publishes there the progress lines it forwards under the shunk031-herdr-orchestrate-workers skill. The token holds one value: keep every unanswered question or goal request in it and replace only its trailing status part, as in `inbox=<pending requests>; STATUS <root>: <task> <change>`. Keep the status part until a later status replaces it or a message from meta shows that meta has seen it; only then drop a status part whose task is done or dropped. Once an answer is recorded in the ledger or a status part is dropped, rewrite the token with what is still pending, and clear it when nothing remains:

```bash
herdr pane report-metadata <pane> --source inbox --clear-token inbox
```

## Codex root operation

Meta creates the root pane with both root-only variables, then starts the root with the model and effort here. `CODEX_ROOT_ORCHESTRATOR=1` enables the dotfiles Stop audit. `PONYTAIL_DEFAULT_MODE=off` makes Ponytail hooks emit nothing for the root; the tested per-launch plugin `-c` override does not work, and the Codex default stays unchanged.

```bash
herdr tab create --workspace <workspace> --cwd <repository> --label "🤖 Orchestrator · Codex handoff" --env CODEX_ROOT_ORCHESTRATOR=1 --env PONYTAIL_DEFAULT_MODE=off --no-focus
herdr agent start <root-name>-handoff --kind codex --pane <returned-pane-id> -- --profile flava-dev -m gpt-6.1-sol -c model_reasoning_effort=high
```

The `-handoff` name keeps the incoming session staged while the outgoing root retains the stable name. It can read and restate the record, but must not begin task work before Meta verifies suspension.

Herdr 0.9.5 applies `--env` to the created pane; it does not copy a root pane's environment into a separate tab. The Codex root creates every worker in its own tab without either `--env` option, then verifies both variables are absent before starting it:

```bash
test -z "$(printenv CODEX_ROOT_ORCHESTRATOR)" && test -z "$(printenv PONYTAIL_DEFAULT_MODE)"
```

If either is set, run `unset CODEX_ROOT_ORCHESTRATOR PONYTAIL_DEFAULT_MODE` in the worker pane and verify again. Leave both unset on Luna workers so Ponytail remains on. This was verified live: a scratch root created with both `--env` options had both variables, and a worker tab created from that root without `--env` had neither.

Do not start in-session subagents: they inherit the root model and are billed at its price. Delegate through Herdr workers using the existing worker skill and the model settings in its launch step (step 4).

For Codex roots, this rule overrides the worker skill's instruction to run one-shot reviews as in-session subagents; use a Herdr review worker with its investigation and review settings.

For every user-facing reply, begin with one fresh `date '+%Y-%m-%dT%H:%M:%S%z'` output line. Do not send timer-based interim progress lines.

An incoming Codex root starts with the exact goal text in its handoff record and no active Codex goal. While waiting on workers, keep its turn blocked on foreground lifecycle waits such as `herdr agent wait <worker-name>`. If no useful work remains, end the turn only when no goal is active; worker report prompts and observer nudges can wake it. If an active goal must pause for waiting, ask Meta through the inbox flow above and keep the turn blocked until Meta confirms. Do not create an active goal just to wait.

A root never runs a goal slash command in its own reply. If it needs a goal set, pause, resume, or clear, it asks Meta through the inbox token flow above. The user's instruction or approval of that handoff authorizes the needed command. Meta enters it as pane input and confirms both the response and the goal indicator:

```bash
herdr pane run <pane> '/goal <objective>'
herdr pane run <pane> '/goal pause'
herdr pane run <pane> '/goal resume'
herdr pane run <pane> '/goal clear'
herdr pane read <pane> --source visible
```

An outgoing active goal must be paused before suspension. Keep its text and paused state in the record; Meta resumes it only when the role returns and the user instruction authorizes that command. Do not resume a blocked or completed goal. A newly active goal is set only by Meta after the root asks through the inbox token flow and the user authorizes it.

## Drill and trial

- Run one round trip with `orch-radm`: Claude Code → Codex → the retained Claude session. Check each restatement and record tokens per day and the trial measures below.
- The user decides whether to run the one-week `orch-radm` and `orch264` trial. After that week, the user decides whether to move the remaining roots.
- Track user corrections (count and kind), user prompts needed only to make a root continue, handoff omissions, and stopped time. Also track finished-worker tabs left open per root, tokens per day, and whether the sampled original-objective audit fires.
- Do not add a limit-triggered automatic notification.
