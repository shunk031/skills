# Why `python-fixture-path-relocation` has no behavior case

The skill tells the agent to anchor paths to `Path(__file__)` rather than to a hard-coded absolute prefix. A behavior case for that rule passed on both arms in every trial, twice: once when the prompt restated the constraint, and again after the prompt was rewritten to ask only for the feature.

That is a measurement, not a measurement failure. It says the evaluated model already writes source-anchored paths without being told, so on this point the skill changes nothing.

The case was removed rather than made harder. Tuning a case until the skill looks necessary measures the tuning, not the skill.

The rule stays in `SKILL.md`. "The model usually gets this right" is not the same as "the rule is wrong", and the rule still tells a reader what this repository considers correct. If a future model regresses, the case is recoverable from this repository's history.

`evals/triggers.json` is unaffected: whether the skill engages on Python work at all is a separate question from whether this one rule changes an outcome.
