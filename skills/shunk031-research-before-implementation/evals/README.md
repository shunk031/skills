# Why this skill's behavior cases do not run

`evals.json` holds two cases. Neither is graded, and `evals/network-required` is what excludes them.

## They cannot be measured offline

This skill's subject is consulting current third-party documentation and implementation code before writing anything. Grading that requires the evaluated agent to reach the web.

Run offline, the with-skill arm behaves exactly as the skill instructs: it reports that the research gate cannot be satisfied and declines to implement. The baseline, having no such instruction, guesses from memory and produces something. The comparator scores the baseline higher on every trial.

## They cannot be measured online either

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

`scripts/shuhari_staged_targets.sh` pins `gpt-5.6-luna` for evaluated runs and `gpt-5.6-sol` for grading, so every run in this repository is on the side that cannot search.

The failure is not always visible. Both 5.6 answers named the correct release tag anyway. A run can look like successful research and not be — which is worth knowing beyond this file, since a skill that tells an agent to check current documentation is, on this model, telling it to do something it will report having done by other means.

## Why the cases stay

An earlier round deleted them, on the reasoning that a gate which always fails teaches everyone to ignore it. That part was right; deleting was not.

Deleting left the restore condition in prose — "put them back once the model can search" — with nothing that would ever notice the condition being met. The cases would have stayed missing after the constraint lifted, and nobody would have known to look.

Keeping them costs nothing: the wrapper skips them and prints why. Removing `evals/network-required` puts them back under the gate, and that is also how you check whether the constraint has lifted. If it has, they pass. If it has not, they fail with the 403 and the marker goes back.

`evals/triggers.json` was never affected. Whether the skill engages on a third-party integration task and stays out of the way on a trivial local edit is measurable offline, and it is the part most likely to regress.
