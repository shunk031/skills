# Why this skill has no `evals.json`

This skill has trigger cases but no behavior cases.

Its subject is consulting current third-party documentation and implementation code before writing anything. Grading that requires the evaluated agent to actually reach the web, and the model this repository evaluates with cannot:

```
http 403 Forbidden: Some("Selected provider is forbidden")
```

**This is the model, not the account.** Asked the same question from the same empty directory, `gpt-5.5` searched and said so; `gpt-5.6-luna` and `gpt-5.6-sol` both returned that 403 and fell back to reasoning from memory or to a direct API call. The gate wrapper pins `gpt-5.6-luna` for evaluated runs and `gpt-5.6-sol` for grading, so every run here is on the side that cannot search.

The models do not always announce it. Both 5.6 answers named the correct release tag anyway, one by calling the GitHub API and one from memory, so a run can look like successful research and not be. That is worth knowing outside this file: a skill that tells an agent to check current documentation is, on this model, telling it to do something it will report having done by other means.

The refusal is not specific to Shuhari — a plain `codex exec` asking for a web search fails the same way. Under it, the with-skill arm behaves exactly as the skill instructs: it reports that the research gate cannot be satisfied and declines to implement. The baseline arm, having no such instruction, guesses from memory and produces something. The comparator then scores the baseline higher on every trial.

So the eval measured the account's web-search entitlement, not the skill. A gate that always fails for a reason unrelated to its subject is worse than no gate,
because it trains everyone to ignore it.

`evals/triggers.json` stays. Whether the skill engages on a third-party integration task and stays out of the way on a trivial local edit is measurable here, and it is the part most likely to regress.

Restore behavior cases once the evaluated model can search — either because the 5.6 family gains the entitlement, or because the pins in `scripts/shuhari_staged_targets.sh` move to a family that has it. The removed file is recoverable from this repository's history, and `evals/network-required` already declares that this skill's cases need egress.
