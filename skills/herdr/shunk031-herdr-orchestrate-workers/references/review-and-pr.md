# Independent review and PR lifecycle

## First-look review of reader-facing artifacts

Before handing a public reader-facing artifact to the user, or posting text for others, obtain an ACCEPT from content verification on the final document. This includes reports, research notes, published HTML, PR bodies, issue bodies, and comments. Internal messages between agents or to orchestrators, including meta/root status reports, skip editorial confirmation and approval gates. When a worker will post text externally, require a draft file and wait for the ACCEPT before posting it.

Public reader-facing artifacts, including Japanese deliverables, get exactly one content reviewer and automated machine checks. Briefs are internal drafting materials; they do not need a separate review or ACCEPT. Tooling checks and corrects formatting, links, syntax, sentence length, and neighbor length. Content review blocks only on material factual errors, unsupported essential facts, or concrete reader misunderstandings. The reviewer states what is wrong and why. Style preferences and nits are advisory and never trigger REJECT. Google guidance treats nits as non-blocking and asks for clear what/why comments; the Codex rubric scopes code review to concrete diff-introduced issues and excludes nits. Copilot docs show PR title/body and repository instructions in review context. These code-review sources shape review scope but do not establish claims about prose quality; this follows the primary sources in the review practice report.

After a finding, route it to the author. The initial reviewer checks only whether their own findings are resolved. Do not dispatch another reviewer or reread the full text to find new issues. Rerun machine checks. This matches `shunk031-writing-gemini-japanese` and `shunk031-writing-router`: one reviewer, fixed scope, targeted follow-up, and no gate for internal reports.

For a document written in someone's name, style, tone, or resemblance alone is advisory. Block only on factual errors or concrete misunderstandings, including distorted facts. Report the exact line. Before handoff, the orchestrator checks scope and machine results only. Do not reread every line, add a reviewer, or create a separate final gate.

### Run one-shot reviews

Run every one-shot review — independent review, initial first-look review, and DONE verification — in a new, read-only review session using the launch guidance in your user-level instructions. For PR code reviews, run the packet runner from the clean checkout under review:

```bash
~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/review_pr.py <PR-number-or-URL> --acceptance-criteria <file> [--verification-evidence <file>]
```

The caller supplies the required criteria file. Use the optional evidence file for local test and check results; the packet keeps it separate from criteria. If omitted, the packet states that no separate verification evidence was supplied. The runner reads these with the PR title and body, base and head SHAs, `git diff`, changed files, and CI status. It refuses to launch if any specified input is unreadable or the worktree is dirty. It also stops when local `HEAD` differs from the live PR head. A preflight failure consumes no review round. Never type a SHA into the review command or prompt.

The reviewer returns one JSON object with a verdict and structured findings. Each finding has a severity, location, concrete impact, evidence, and an `introduced_by_diff` value. A blocker must identify its location, impact, evidence, and show that the diff introduced it. The reviewer considers only concrete defects introduced by the diff and materially false factual claims in the PR body. Style, nits, duplicates, unsupported findings, pre-existing problems, and PR-body wording are advisory and never block. PR-body review is limited to factual consistency with the diff and verification evidence.

Keep deterministic checks in tooling: formatting, links, PR metadata and head consistency, tests, and required CI. The AI reviewer does not replace those checks; required CI must still pass before merge.

## Verify DONE against the user's original request

On DONE, dispatch the verification work to independent reviewers with no prior involvement in the work: have them rerun the applicable gates, reconstruct each claimed contract from its source of truth, inspect the diff and evidence, verify tests exercise the actual package or production path against an independently reconstructed reference, check citations, and recompute every numeric claim from raw data before the orchestrator accepts or relays the result. For structural tasks, reviewers reject a dispatch lacking or contradicting the four-part `Design record:` or a delivered structure that misses its target, regardless of CI. Verify each deliverable against the user's original words, not the dispatch text, because the dispatch itself can be the corrupted layer.

For repository artifacts, reviewers must check for user chat, instructions given to agents, approvals, and statements of who decided what, and reject any that contain them. For validation and experiment plans, compare the plan with the linked issue, source design documents, and earlier experiment reports recorded in it, not the orchestrator's instructions. Require every DONE report to include a per-item audit against the session's accumulated user-rulings checklist, and reject reports that omit the audit.

The orchestrator keeps receipt checks and state reconciliation, consolidates reviewer findings, makes accept/reject decisions, and routes results to owners or users. Worker summaries, test names, pass counts, manifests, CI, and artifact hashes remain candidate evidence only, not acceptance; reviewer reports are findings for the orchestrator to consolidate, not decisions. Reject and redispatch claims based on test-local reconstructions or runtime paths that do not exist or are not exercised.

The same checklist applies to the one-shot independent review permitted while meta is usage-limited.

## Process actionable REJECT

<!-- textlint-disable sentence-length -->

An actionable `REJECT` from an independent reviewer is non-terminal: before reporting or waiting, verify the live task/PR owner, consolidate the findings, and route them immediately to that owner with the existing quoted `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-agent-prompt-if-input-empty.sh <owner> "$answer"` path; use the [step-5 receipt contract in `dispatch.md`](dispatch.md#dispatch-and-receipt), record the exact rejected head, `re-review pending`, and the review round in the task's ledger row, and after the owner publishes a corrected head, or in a public repository commits it locally before pushing, have a fresh reviewer review that exact head.

<!-- textlint-enable sentence-length -->

The round count belongs to the deliverable, so a replacement worker inherits it. Keep the content-review cap at two rounds per deliverable. Correct review-setup failures and fixable PR-body presentation without asking the user; these do not consume a content round. After the cap, triage findings against the reviewer contract. Drop advisory findings. Route each verified blocker to its owner for a local fix, then review the corrected head. An incomplete or undecidable finding is not an ACCEPT; keep merge stopped and route it to the owner for evidence or clarification. Ask the user only when a genuinely user-owned decision remains, never because the cap was reached.

## Verify the PR head before handoff or merge

Before asking the user to merge and immediately before squash merging, verify the live PR head matches the head SHA recorded with the reviewer's `ACCEPT`, and check whether it is mergeable, behind, or conflicting. If behind, route the branch update and CI follow-up to the owning worker; if conflicting, route conflict resolution and CI follow-up to that worker.

If the head differs or either repair changes it, fetch the old and new base and head commits. Run `git range-diff <old-base>..<old-head> <new-base>..<new-head>` without whitespace-ignoring options. Keep the existing review only when range-diff shows the PR's commits unchanged. Any changed patch requires a fresh review of the exact live head. Whitespace-only changes and conflict resolution also require a fresh review. Do not use patch-ID comparisons that may normalize whitespace. Record the independent reviewer's `ACCEPT` with the head it covers. Merge only after an `ACCEPT` covers the current head, directly or through a verified base-only update, and all required checks pass. Keep GitHub branch protection and required human approvals intact. Then route the authorized merge or enqueue to the owning worker under the merge-approval rule in Authority Boundaries of the user-level `AGENTS.md`.
