# Why this skill has no `evals.json`

This skill has trigger cases but no behavior cases.

Its subject is consulting current third-party documentation and implementation code before writing anything. Grading that requires the evaluated agent to actually reach the web. On this account the model provider refuses:

```
http 403 Forbidden: Some("Selected provider is forbidden")
```

That refusal is not specific to Shuhari — a plain `codex exec` asking for a web search fails the same way. Under it, the with-skill arm behaves exactly as the skill instructs: it reports that the research gate cannot be satisfied and declines to implement. The baseline arm, having no such instruction, guesses from memory and produces something. The comparator then scores the baseline higher on every trial.

So the eval measured the account's web-search entitlement, not the skill. A gate that always fails for a reason unrelated to its subject is worse than no gate,
because it trains everyone to ignore it.

`evals/triggers.json` stays. Whether the skill engages on a third-party integration task and stays out of the way on a trivial local edit is measurable here, and it is the part most likely to regress.

Restore behavior cases once the provider permits web search. The removed file is recoverable from this repository's history, and `evals/network-required` already declares that this skill's cases need egress.
