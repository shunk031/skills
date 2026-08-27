# Why this skill's behavior cases use the network policy

`evals.json` holds three cases. The `evals/network-required` marker makes the gate evaluate them with `gpt-5.5`, medium reasoning, and network access in Shuhari's isolated sandbox.

## They cannot be measured offline

This skill's subject is consulting current third-party documentation and implementation code before writing anything. Grading that requires the evaluated agent to reach the web.

Run offline, the with-skill arm behaves exactly as the skill instructs: it keeps the research stage incomplete and investigates the failed research path without implementing from memory. The baseline, having no such instruction, guesses from memory and produces something. The comparator scores the baseline higher on every trial.

## Why the network policy uses a different model

Enabling egress does not help, because the pinned models cannot use the web-search tool at all:

```
403 Forbidden: Selected provider is forbidden
```

**This is the model, not the account.** Asked the same question from the same empty directory:

| Model          | Result                                              |
| -------------- | --------------------------------------------------- |
| `gpt-5.5`      | searched, and said the search tool worked           |
| `gpt-5.6-luna` | the 403 above, then answered from memory            |
| `gpt-5.6-sol`  | the 403 above, then verified through the GitHub API |

`scripts/shuhari_staged_targets.sh` therefore uses `gpt-5.5` with medium reasoning for behavior cases marked `network-required`. It keeps `gpt-5.6-sol` with medium reasoning as the judge, and ordinary behavior cases remain on `gpt-5.6-luna` with high reasoning and no network access.

The skill delegates this exact failure to one read-only `gpt-5.5` search session during normal use. The evaluation needs the same live-search capability to measure that behavior, so the marker is the explicit harness boundary.

The failure is not always visible. Both 5.6 answers named the correct release tag anyway. A run can look like successful research and not be — which is worth knowing beyond this file, since a skill that tells an agent to check current documentation is, on this model, telling it to do something it will report having done by other means.

## What remains offline

`evals/triggers.json` stays on the default offline `gpt-5.6-luna` policy. Whether the skill engages on a third-party integration task and stays out of the way on a trivial local edit does not require web access.
