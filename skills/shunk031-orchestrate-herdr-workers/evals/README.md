# Why `cross-stream-failure-synthesis` was removed

The case asked what an orchestrator does when two independent worker streams report the same failure signature. At five trials per arm the two arms were identical on every assertion: recognizing the cross-stream pattern passed 5/5 against 5/5, opening a generalized meta issue passed 5/5 against 5/5, and carrying the diagnosis across passed 4/5 against 4/5.

Its prompt opened with "Following the `shunk031-orchestrate-herdr-workers` skill", which names the skill to the arm that does not have it and was the obvious suspect for lifting the baseline. Removing that opening changed nothing: the baseline still passed every trial.

So the evaluated model already treats a repeated signature as one cause and already reaches for a shared follow-up. On this point the skill changes nothing, which is a finished measurement rather than a broken case. The case was removed instead of being sharpened, because tuning a case until a difference appears measures the tuning.

The guidance stays in `SKILL.md`, and the case is recoverable from this repository's history if a future model regresses.

# Why `queue-over-conversation` has four assertions instead of two

The case previously carried one assertion reading "performs or routes the DONE source-of-truth acceptance, answers or escalates the BLOCKED question, and answers the user's status question without deferring any of them". With the skill it passed 2/5; without it, 5/5.

The skill was not the problem. Its prompt says this is an offline dry run and that commands must not be executed, and the grader failed the skill arm for exactly that: acceptance was "not yet complete", no operational commands ran, and the GPU decision was still open. All three are what following the instruction produces. The skill arm had in fact escalated the GPU decision with both options named and answered the status question; it lost because its report stated plainly what remained undone, while the baseline left that vague.

The assertion also bundled three separate claims, so a miss on any one hid the other two.

It is now four assertions, one claim each, judging the disposition the response states rather than work it was forbidden to perform.
