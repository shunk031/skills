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

## Publish the root's next due action

Every root orchestrator, whether Claude or Codex and whether or not Inbox is installed, owns the due time for its next action. Publish it on the root's own pane with `herdr pane report-metadata`, using the same stable source ID for every update and the dedicated `due` token with a timezone-qualified RFC3339 timestamp:

```bash
herdr pane report-metadata --source root-due --token 'due=2026-11-16T13:30:00+09:00' "$HERDR_PANE_ID"
```

Update the token with the same command and source ID whenever the next action or its due time changes. Clear it when no due action remains:

```bash
herdr pane report-metadata --source root-due --clear-token due "$HERDR_PANE_ID"
```

Use this metadata for due times; do not encode them in freeform inbox text. Keep the existing inbox behavior for reports, questions, and other messages. A due time triggers a later live check by Meta; it does not authorize Meta to infer, move, reassign, or perform the work.

## Workflow

Read each step's linked reference before performing it.

- **Plan and identify tasks:** [dispatch](references/dispatch.md#plan-and-identity) — establish the orchestrator identity, design record, and independent owners.
- **Create workspaces and launch:** [dispatch](references/dispatch.md#workspace-and-worker-startup) — create or reopen a deliverable workspace, start a named worker, and handle startup trust dialogs.
- **Dispatch and confirm receipt:** [dispatch](references/dispatch.md#dispatch-and-receipt) — guarded send, readable receipt, recorded direct dispatch, and lifecycle wait.
- **Collect and reconcile:** [reconciliation](references/reconciliation.md#collect-and-reconcile) — lifecycle state, transcripts, deliverables, missing reports, and worker recovery.
- **Verify and route:** [review and PR lifecycle](references/review-and-pr.md) — independent DONE and first-look review, REJECT handling, PR head SHA, and worker-owned merge.
- **Report:** [reconciliation](references/reconciliation.md#user-reporting-and-decisions) and [task/question tracking](references/task-and-question-tracking.md).
- **Clean up:** [cleanup](references/cleanup.md) — close collected panes and eligible tabs with the helper. After merge, remove a clean worktree and branch only when its local tip equals or is an ancestor of the PR's final head.

## Special cases

- **DONE, REJECT, first-look review, merge:** [review and PR lifecycle](references/review-and-pr.md).
- **BLOCKED, STATUS, failed worker, missing report, correction sweep:** [reconciliation](references/reconciliation.md).
- **Task/question tracking:** Always read [task and question tracking](references/task-and-question-tracking.md) for its waiting-list reporting rule.
- **Inbox procedures:** Read [Inbox-specific procedures](references/inbox.md) only when the Inbox tools are available.
- **Anonymous live pane:** [adopt-anonymous-pane](references/adopt-anonymous-pane.md).
- **Active observation:** Read [active observation](references/active-observation.md) only when the user explicitly requests it.
- **Health watchers:** Read [health watchers](references/health-watchers.md) when passive alerts would help; starting them is required for dispatched runs expected to last 30 minutes or longer.
- **Outbound prompts:** [send-rule](references/send-rule.md).

Run PR code reviews with the packet runner and review contract in [review and PR lifecycle](references/review-and-pr.md). The caller supplies a task-specific acceptance-criteria file. Add `--verification-evidence <file>` for local check results; the runner keeps them separate from criteria and reads them with live PR metadata, the committed diff, changed files, and CI status.

## Working as a dispatched worker

A dispatched worker follows [the worker protocol](references/worker-protocol.md).
