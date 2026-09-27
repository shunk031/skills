# Why `cross-stream-failure-synthesis` was removed

The case asked what an orchestrator does when two independent worker streams report the same failure signature. At five trials per arm the two arms were identical on every assertion: recognizing the cross-stream pattern passed 5/5 against 5/5, opening a generalized meta issue passed 5/5 against 5/5, and carrying the diagnosis across passed 4/5 against 4/5.

Its prompt opened with "Following the `shunk031-herdr-orchestrate-workers` skill", which names the skill to the arm that does not have it and was the obvious suspect for lifting the baseline. Removing that opening changed nothing: the baseline still passed every trial.

So the evaluated model already treats a repeated signature as one cause and already reaches for a shared follow-up. On this point the skill changes nothing, which is a finished measurement rather than a broken case. The case was removed instead of being sharpened, because tuning a case until a difference appears measures the tuning.

The guidance stays in `SKILL.md`, and the case is recoverable from this repository's history if a future model regresses.

# Why `queue-over-conversation` has four assertions instead of two

The case previously carried one assertion reading "performs or routes the DONE source-of-truth acceptance, answers or escalates the BLOCKED question, and answers the user's status question without deferring any of them". With the skill it passed 2/5; without it, 5/5.

The skill was not the problem. Its prompt says this is an offline dry run and that commands must not be executed, and the grader failed the skill arm for exactly that: acceptance was "not yet complete", no operational commands ran, and the GPU decision was still open. All three are what following the instruction produces. The skill arm had in fact escalated the GPU decision with both options named and answered the status question; it lost because its report stated plainly what remained undone, while the baseline left that vague.

The assertion also bundled three separate claims, so a miss on any one hid the other two.

It is now four assertions, one claim each, judging the disposition the response states rather than work it was forbidden to perform.

# What five trials showed that three did not

Merging the two case fixes above left three assertions where the skill scored *worse* than the baseline, each two-in-three against three-in-three. Re-measured at five trials per arm, two of the three were noise:

| Assertion | 3 trials | 5 trials |
| --- | --- | --- |
| `independent-done-acceptance` — sees the loader contract is unverified | 0.67 vs 1.00 | **1.0 vs 1.0** |
| `independent-done-acceptance` — reconstructs the contract from its source | 0.67 vs 1.00 | **1.0 vs 1.0** |
| `observer-scope-stale-moving-lifecycle` — forbids mutation and polling | 0.67 vs 1.00 | **0.8 vs 0.2** |

The third reversed outright: at three trials it read as the skill hurting, at five it is the skill's largest single gain. **At n=3 the sign is not reliable**, so a one-run difference of that size is not a finding. Treat it as a reason to re-measure, not as a result.

One is real. `redispatches the worker to implement and verify real loader parity` sits at 0.6 with the skill against 1.0 without, failing two trials in five.

Both arms write a Redispatch section, and the skill arm's is the more specific of the two — it names the worker, the corrective task, and records the dispatch as an offline prompt, while the baseline says to implement the loader and compare against a reference. That is the shape seen elsewhere in this repository: a dry-run prompt, an assertion phrased as an action, and the arm that states precisely what it did *not* execute losing to the arm that stays vague.

It is not confirmed. Only the last trial's transcript is retained, so the two failing runs cannot be read. The case passes on a majority and the gate is green at 0.93 against 0.70, so this is recorded rather than chased. Confirming it would mean re-running in a way that keeps the failing trials.
