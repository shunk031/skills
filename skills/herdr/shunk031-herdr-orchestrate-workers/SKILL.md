---
name: shunk031-herdr-orchestrate-workers
description: "Orchestrate coding workers in Herdr: dispatch parallel worker agents into git worktree tabs, reconcile their state, validate their reports against raw results, and route task, review, and pull-request lifecycles. Use when a request mentions Herdr and asks to orchestrate, delegate to, or coordinate workers, or to audit their reports or where a constraint came from, or when a prompt says you are a Herdr worker reporting to an orchestrator. Not for single-pane or single-agent Herdr control, pane-output questions, general CLI questions, or parallel work and git worktrees without Herdr."
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🐑 I read shunk031-herdr-orchestrate-workers.`

# Orchestrate Herdr Workers

## Role and prerequisites

An orchestrator delegates independent tasks to worker agents, one git worktree tab each. Workers must report back by prompting the orchestrator for attribution and audit, but completion is collected from Herdr lifecycle state and the worker's deliverable and transcript. Read this skill file and the herdr skill first: the herdr skill owns all CLI mechanics, JSON responses, ID handling, and safety rules.

This skill adds only the orchestration protocol. When one session oversees multiple root orchestrators, pair this with the shunk031-herdr-meta-orchestrate skill for root inventory, status requests, and relays. When writing a Codex worker's task prompt, follow the shunk031-codex-worker-prompting skill.

## Core invariants

- **Guarded messaging:** Every prompt send in this skill follows [the send rule](references/send-rule.md); read it before your first send. Never send into occupied input.
- **Evidence over reports:** Verify live Herdr state, worker transcripts, deliverables, and git/PR state. A DONE report or green CI alone does not prove acceptance.
- **Worker ownership:** Route task-scoped implementation and GitHub actions to the live worker that owns them.
- **Independent review:** Verify completed work and reader-facing artifacts against the user's original requirements before acceptance or publication.
- **User authority:** Surface decisions about scope, resources, deletion, credentials, license, and settings; follow the merge-approval rule in the user's `AGENTS.md`.
- **Lifecycle and cleanup:** Reconcile outstanding workers, answer actionable BLOCKED reports, and remove only verified, protocol-owned resources.

## Workflow

Read each step's linked reference before performing it.

- **Plan and identify tasks:** [dispatch](references/dispatch.md#plan-and-identity) — establish the orchestrator identity, design record, and independent owners.
- **Create workspaces and launch:** [dispatch](references/dispatch.md#workspace-and-worker-startup) — create or reopen a deliverable workspace, start a named worker, and handle startup trust dialogs.
- **Dispatch and confirm receipt:** [dispatch](references/dispatch.md#dispatch-and-receipt) — guarded send, readable receipt, recorded direct dispatch, and lifecycle wait.
- **Collect and reconcile:** [reconciliation](references/reconciliation.md#collect-and-reconcile) — lifecycle state, transcripts, deliverables, missing reports, and worker recovery.
- **Verify and route:** [review and PR lifecycle](references/review-and-pr.md) — independent DONE and first-look review, REJECT handling, PR head SHA, and worker-owned merge.
- **Report:** [reconciliation](references/reconciliation.md#user-reporting-and-decisions) and [task/question tracking](references/task-and-question-tracking.md).
- **Clean up:** [cleanup](references/cleanup.md) — close collected panes, preview and close eligible tabs with the helper, and safely remove merged-PR worktrees/branches.

## Special cases

- **DONE, REJECT, first-look review, merge:** [review and PR lifecycle](references/review-and-pr.md).
- **BLOCKED, STATUS, failed worker, missing report, correction sweep:** [reconciliation](references/reconciliation.md).
- **Task/question tracking:** Always read [task and question tracking](references/task-and-question-tracking.md) for its waiting-list reporting rule.
- **Anonymous live pane:** [adopt-anonymous-pane](references/adopt-anonymous-pane.md).
- **Active observation:** Read [active observation](references/active-observation.md) only when the user explicitly requests it.
- **Health watchers:** Read [health watchers](references/health-watchers.md) when passive alerts would help; starting them is required for dispatched runs expected to last 30 minutes or longer.
- **Outbound prompts:** [send-rule](references/send-rule.md).

## Working as a dispatched worker

A dispatched worker follows [the worker protocol](references/worker-protocol.md).
