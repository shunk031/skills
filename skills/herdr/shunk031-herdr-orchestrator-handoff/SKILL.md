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
- Each user decision or approval, including its exact scope and limits; pending questions and who must answer them.
- The exact goal objective and whether it is active, paused, blocked, or complete; the ledger and handoff paths; transcript path and the recent line range to read.

The incoming root itself reads the record and the listed recent transcript lines verbatim from disk; do not substitute a worker summary. Search older transcript lines when context is needed. Claude Code sessions are under `~/.claude/projects/<project-slug>/<session-id>.jsonl`; Codex sessions are under `${CODEX_HOME:-~/.codex}/sessions/YYYY/MM/DD/rollout-<timestamp>-<session-id>.jsonl`. Read the recorded range directly, for example `sed -n '<first>,<last>p' '<transcript-path>'`.

The incoming root restates the objective, open tasks, worker states and waits, decisions and approval scopes, pending questions, goal, and next action. The outgoing root checks that restatement before the role moves. If the outgoing root stopped at a usage limit, the user checks it. Do not transfer an unresolved point by guessing.

Keep the old session and its transcript. The Herdr agent name belongs to the active root. Start the incoming root with a temporary name. After the restatement is checked, rename the outgoing pane with `herdr agent rename <pane> <root-name>-<engine>`. Then rename the incoming pane with `herdr agent rename <pane> <root-name>`. Label root tabs `🤖 Orchestrator · <engine>` and mark parked sessions in the label, following the `shunk031-herdr-tab-status` skill. Report the stable name, engine, active pane/tab, and session ID to meta. On return, resume the retained Claude session with `claude --resume <session-id>` (or continue it if it is still live) from the new delta record. Keep Codex's prior session and resume it with `codex resume <session-id>` if the role later returns to that session.

If Codex or the Gateway is unavailable, stop the Codex root. Meta will notice through the patrol and ask the user whether to return the role to Claude; do not switch engines without that answer.

## Codex root operation

Create the root pane with both root-only variables, then start the root with the model and effort here. `CODEX_ROOT_ORCHESTRATOR=1` enables the dotfiles Stop audit. `PONYTAIL_DEFAULT_MODE=off` makes Ponytail hooks emit nothing for the root; the tested per-launch plugin `-c` override does not work, and the Codex default stays unchanged.

```bash
herdr tab create --workspace <workspace> --cwd <repository> --label "🤖 Orchestrator · Codex handoff" --env CODEX_ROOT_ORCHESTRATOR=1 --env PONYTAIL_DEFAULT_MODE=off --no-focus
herdr agent start <root-name>-handoff --kind codex --pane <returned-pane-id> -- --profile flava-dev -m gpt-6.1-sol -c model_reasoning_effort=high
```

The `-handoff` name is temporary so the outgoing root keeps the stable name until it checks the restatement.

Herdr 0.9.5 applies `--env` to the created pane; it does not copy a root pane's environment into a separate tab. Create every worker in its own tab without either `--env` option, then verify both variables are absent before starting it:

```bash
test -z "$(printenv CODEX_ROOT_ORCHESTRATOR)" && test -z "$(printenv PONYTAIL_DEFAULT_MODE)"
```

If either is set, run `unset CODEX_ROOT_ORCHESTRATOR PONYTAIL_DEFAULT_MODE` in the worker pane and verify again. Leave both unset on Luna workers so Ponytail remains on. This was verified live: a scratch root created with both `--env` options had both variables, and a worker tab created from that root without `--env` had neither.

Do not start in-session subagents: they inherit the root model and are billed at its price. Delegate through Herdr workers using the existing worker skill and these model settings:

```bash
# Implementation and mechanical work
herdr agent start <worker-name> --kind codex --pane <pane> -- -m gpt-6-luna -c model_reasoning_effort=xhigh
# Investigation and review
herdr agent start <worker-name> --kind codex --pane <pane> -- -m gpt-6.1-sol -c model_reasoning_effort=medium
```

For Codex roots, this rule overrides the worker skill's instruction to run one-shot reviews as in-session subagents; use a Herdr review worker with the investigation and review settings above.

For every user-facing reply, begin with one fresh `date '+%Y-%m-%dT%H:%M:%S%z'` output line. Do not send timer-based interim progress lines.

Route questions through meta. When a concise question is ready for the user, publish a summary on the root pane's inbox token:

```bash
herdr pane report-metadata <pane> --source inbox --token 'inbox=<summary>'
```

The existing patrol relays it to meta. Once the answer is recorded in the ledger, clear the token:

```bash
herdr pane report-metadata <pane> --source inbox --clear-token inbox
```

While waiting on workers, keep the Codex turn blocked on foreground lifecycle waits such as `herdr agent wait <worker-name>`; do not spin or rely on a background terminal's exit to wake Codex. If no useful work remains until a reply, the Codex root pauses an active goal with `/goal pause` and ends the turn. Carry the exact objective and state in the handoff record. The incoming Codex root issues goal commands in its own prompt. For an active goal, use `/goal <objective>`. For a paused goal, use `/goal <objective>` followed by `/goal pause`. Do not reactivate a blocked or completed goal. Resume a paused goal with `/goal resume` when work can continue. Worker report prompts and the observer's nudges can wake the root.

## Drill and trial

- Run one round trip with `orch-radm`: Claude Code → Codex → the retained Claude session. Check each restatement and record tokens per day and the D12 measures below.
- The user decides whether to run the one-week `orch-radm` and `orch264` trial. After that week, the user decides whether to move the remaining roots.
- Track user corrections (count and kind), user prompts needed only to make a root continue, handoff omissions, and stopped time. Also track finished-worker tabs left open per root, tokens per day, and whether the sampled original-objective audit fires.
- Do not add a limit-triggered automatic notification.
