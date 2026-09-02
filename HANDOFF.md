# Flaky trigger repair handoff

Audience and value: This note is for the successor worker continuing the trigger repair. It preserves the measured rates, the accumulated diagnosis, the current draft, and the remaining work so completed model trials are not repeated.

## State

The branch is `fix/orchestrate-workers-flaky-triggers`. Before the uncommitted changes, `HEAD` was `786d09a`, equal to the current `origin/main`. The coherent work in this WIP consists of the description change in `skills/shunk031-herdr-orchestrate-workers/SKILL.md` and the four positive prompt rewrites in `skills/shunk031-herdr-orchestrate-workers/evals/triggers.json`; negative controls were not changed.

## Baseline on unmodified main

The full trigger suite was run at five trials with four jobs on unmodified `origin/main`.

| Case | target_read | target_applied |
| --- | ---: | ---: |
| status-reconciliation-before-waiting | 5/5 | 5/5 |
| orchestrator-provenance | 5/5 | 5/5 |
| queue-over-conversation | 4/5 | 4/5 |
| cross-stream-failure-synthesis | 4/5 | 4/5 |

Baseline negative controls remained valid: `parallel-worktrees-without-herdr` had 0/5 applied, and `plain-herdr-cli-question` had 2/5 applied, which satisfies the majority-false negative-control rule.

## Accumulated diagnosis and draft

The four cases measure real duties in the skill body, and none was identified as a case that measures nothing. The accumulated diagnosis was a combination of routing coverage and case design: the description did not name the newer duties in routing language, while the original prompts used synthetic protocol framing and, in places, bundled several facts or leaked the full skill name. The expected behaviors are grounded in explicit body rules; no separate semantic ambiguity was found. The prompts were therefore rewritten as natural, single-question dry-run requests without skill-name leakage, and the description was extended only with routing clauses for duties already present in the body.

| Case | Diagnosis recorded before handoff | Current fix draft |
| --- | --- | --- |
| status-reconciliation-before-waiting | Missing explicit description route for reconciling state before waiting; original prompt was a synthetic multi-state decision. | Route “reconcile state before waiting”; ask whether to prompt or keep the lifecycle wait after the worker remains active. |
| orchestrator-provenance | Missing explicit description route for transcript-based provenance; original prompt leaked the skill name and mixed provenance with motive. | Route checking whether a constraint came from the user, worker prompt, or orchestrator addition; ask what motive, if any, the transcript supports. |
| queue-over-conversation | Missing explicit description route for processing queued reports; original prompt was protocol-heavy and combined queue handling with a user-status question. | Route processing queued reports before answering; ask for the same-turn routing sequence. |
| cross-stream-failure-synthesis | Missing explicit description route for correlating matching failures across streams; original prompt leaked the skill name. | Route cross-stream failure correlation; ask for the shared-incident workflow and durable follow-up. |

The description remains under the Agent Skills character limit and the near-miss negative controls remain unchanged.

## Post-fix measurements already available

Completed post-fix iteration 16 recorded these five-trial outcomes. Its `plain-herdr-cli-question` negative control was invalid (5/5 applied), so do not treat that run as a valid full-suite result.

| Case | target_read / applied |
| --- | ---: |
| status-reconciliation-before-waiting | 1/5 / 1/5 |
| orchestrator-provenance | 1/5 / 1/5 |
| queue-over-conversation | 3/5 / 3/5 |
| cross-stream-failure-synthesis | 5/5 / 5/5 |
| plain-herdr-cli-question (negative) | 5/5 / 5/5; invalid control |

Completed post-fix iteration 17 was run after compressing the description under the character limit. Its finished `trigger.json` records:

| Case | target_read / applied | Policy status |
| --- | ---: | --- |
| status-reconciliation-before-waiting | 2/5 / 2/5 | failing |
| orchestrator-provenance | 1/5 / 1/5 | failing |
| queue-over-conversation | 4/5 / 4/5 | passing |
| cross-stream-failure-synthesis | 4/5 / 4/5 | passing |
| plain-herdr-cli-question (negative) | 0/5 / 0/5 | valid negative control |

## Remaining work

Do not recompute the unmodified-main baseline or completed post-fix iterations 1–16. Inspect the already-completed iteration-17 artifact if needed for gate bookkeeping, then continue with the original workflow: repair or remeasure the two still-failing positive cases, give any borderline result another five trials, run `shuhari check trigger --validate-only`, run the full trigger suite at five trials, run the pre-commit hooks with no `SKIP`, commit the final results, push, and open the pull request to the default branch. Do not merge. The eventual PR body needs the reader-facing per-case before/after table, diagnosis, and fix.

No case deletion was proposed; deletion would require user approval.
