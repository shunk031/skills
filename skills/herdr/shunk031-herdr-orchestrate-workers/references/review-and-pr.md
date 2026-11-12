# Independent review and PR lifecycle

## First-look review of reader-facing artifacts

Before handing any reader-facing artifact (a report, research note, or published HTML) to the user or posting/updating text for others (a pull request body, issue body, or issue/PR comment), obtain an ACCEPT from a first-look review.

When a worker will post or update text, require its dispatch to have the worker return that text as a draft file and wait for the ACCEPT before posting/updating it.

Use a FRESH reviewer with no prior involvement in the artifact — its empty context is what makes it a genuine first-time reader — and have it judge whether the opening of reports, research notes, published HTML, pull request bodies, and issue bodies conveys the question, method, result, and consequence in plain language, and whether every sentence in all of that text, including comments, gives its reader information they need.

Route a REJECT back to the owning worker like any review finding.

The user must never be the first reviewer to see the artifact.

This first-look review uses the same independent-review mechanism as DONE verification below.

### How to run one-shot reviews

Run every one-shot review — independent review, first-look review, and DONE verification — as an in-session subagent with a fresh context instead of a new Herdr pane, so nothing is left behind; if a review must run in a Herdr pane, close it with `herdr pane close <pane-id>` right after its verdict.

## Verify DONE against the original request

On DONE, dispatch the verification work to independent reviewers with no prior involvement in the work: have them rerun the applicable gates, reconstruct each claimed contract from its source of truth, inspect the diff and evidence, verify tests exercise the actual package or production path against an independently reconstructed reference, check citations, and recompute every numeric claim from raw data before the orchestrator accepts or relays the result.

For structural tasks, reviewers reject a dispatch lacking or contradicting the four-part `Design record:` or a delivered structure that misses its target, regardless of CI.

Verify each deliverable against the user's original words, not the dispatch text, because the dispatch itself can be the corrupted layer.

For repository artifacts, reviewers must check for user chat, instructions given to agents, approvals, and statements of who decided what, and reject any that contain them.

For validation and experiment plans, compare the plan with the linked issue, source design documents, and earlier experiment reports recorded in it, not the orchestrator's instructions.

Require every DONE report to include a per-item audit against the session's accumulated user-rulings checklist, and reject reports that omit the audit.

The orchestrator keeps receipt checks and state reconciliation, consolidates reviewer findings, makes accept/reject decisions, and routes results to owners or users.

Worker summaries, test names, pass counts, manifests, CI, and artifact hashes remain candidate evidence only, not acceptance; reviewer reports are findings for the orchestrator to consolidate, not decisions.

Reject and redispatch claims based on test-local reconstructions or runtime paths that do not exist or are not exercised.

## Resolve REJECT and preserve review/head identity

An actionable `REJECT` from an independent reviewer is non-terminal: before reporting or waiting, verify the live task/PR owner, consolidate the findings, and route them immediately to that owner with the existing quoted `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <owner> "$answer"` path; use the step-5 receipt contract, record the exact rejected head and `re-review pending`, and after the owner publishes a corrected head, or in a public repository commits it locally before pushing, have a fresh reviewer review that exact head.

## Re-check before handoff or merge

Before asking the user to merge and immediately before squash merging, verify the live PR head matches the head SHA recorded with the reviewer's `ACCEPT`, and check whether it is mergeable, behind, or conflicting.

If behind, route the branch update and CI follow-up to the owning worker; if conflicting, route conflict resolution and CI follow-up to that worker.

If the head differs or either repair changes it, withhold the handoff or merge and have a fresh reviewer review that exact head, even when only the base branch was merged or rebased in.

After a fresh `ACCEPT`, record the live head with it.

Once required checks pass, route the merge or enqueue of a pull request the user has already approved to the owning worker without asking the user again, under the merge-approval rule in Authority Boundaries of the user-level `AGENTS.md`, which also says when the user must be asked.
