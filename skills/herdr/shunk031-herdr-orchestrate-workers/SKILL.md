---
name: shunk031-herdr-orchestrate-workers
description: "Orchestrate coding workers in Herdr: dispatch parallel Codex workers into git worktree tabs, reconcile their state, validate their reports against raw results, and route task, review, and pull-request lifecycles. Use when a request mentions Herdr and asks to orchestrate, delegate to, or coordinate workers, or to audit their reports or where a constraint came from, or when a prompt says you are a Herdr worker reporting to an orchestrator. Not for single-pane or single-agent Herdr control, pane-output questions, general CLI questions, or parallel work and git worktrees without Herdr."
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🐑 I read shunk031-herdr-orchestrate-workers.`

# Orchestrate Herdr Workers

## Role and prerequisites

An orchestrator delegates independent tasks to worker agents, one git worktree tab each. Workers must report back by prompting the orchestrator for attribution and audit, but completion is collected from Herdr lifecycle state and the worker's deliverable and transcript. Read this skill file and the herdr skill first: the herdr skill owns all CLI mechanics, JSON responses, ID handling, and safety rules. This skill adds only the orchestration protocol. When one session oversees multiple root orchestrators, pair this with the shunk031-herdr-meta-orchestrate skill for root inventory, status requests, and relays. When writing a Codex worker's task prompt, follow the shunk031-codex-worker-prompting skill.

## Non-negotiable rules

- **Use the guarded sender for every prompt.** Follow [the send rule](references/send-rule.md) before the first send; never send to occupied input.

- **Treat Herdr state, the worker transcript, and deliverables as evidence.** A `DONE` report, CI pass, or reviewer summary alone is not acceptance.

- **Keep task and PR ownership with the live worker.** Route changes and approved merges to that worker rather than executing owned actions in the orchestrator.

- **Review independently before acceptance or publication.** Verify the user's original request and the actual artifact; use first-look review for reader-facing text.

- **Preserve user decision authority.** Ask about user-owned choices before dispatch, and use the merge-approval rules in the user's `AGENTS.md`.

- **Reconcile outstanding work, answer BLOCKED reports, and clean up only verified, protocol-owned resources.**

## Workflow

1. **Plan and identify owners:** [dispatch](references/dispatch.md#plan-and-identity) — identify the orchestrator, divide independent tasks, record structural design and experiment constraints.

2. **Launch:** [dispatch](references/dispatch.md#workspace-and-worker-startup) — create a dedicated worktree workspace and worker tab; handle startup trust prompts.

3. **Send and verify:** [dispatch](references/dispatch.md#dispatch-and-receipt) — use the guarded sender, confirm a readable receipt and newer `state_change_seq`, and start a lifecycle wait.

4. **Collect and reconcile:** [reconciliation](references/reconciliation.md#collect-and-reconcile) — settle lifecycle waits, read deliverables and transcripts, and handle missing reports or dead workers.

5. **Verify and route:** [review and PR lifecycle](references/review-and-pr.md) — independent DONE and first-look reviews, REJECT remediation, head-SHA checks, and worker-owned merge operations.

6. **Report:** [reconciliation](references/reconciliation.md#user-reporting-and-decisions) and [task/question tracking](references/task-and-question-tracking.md).

7. **Clean up:** [cleanup](references/cleanup.md) — close collected panes and remove eligible merged-PR worktrees/branches.

## Cases requiring special handling

- **REJECT, DONE, reader-facing drafts, PR merge:** [review and PR lifecycle](references/review-and-pr.md).

- **BLOCKED, STATUS, missing reports, worker failure, user corrections:** [reconciliation](references/reconciliation.md).

- **Anonymous panes:** [adopt an anonymous pane](references/adopt-anonymous-pane.md).

- **Explicit active observation:** [active observation](references/active-observation.md).

- **Passive health checks and long runs:** [supplemental health watchers](references/health-watchers.md).

- **Outbound messages:** [send rule](references/send-rule.md).

## Working as a dispatched worker

A dispatched worker follows [the worker protocol](references/worker-protocol.md).

All worker-specific obligations (report delivery, commit/push safety, and sub-orchestration) are in that protocol.
