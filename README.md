# skills

[![CI](https://github.com/shunk031/skills/actions/workflows/ci.yaml/badge.svg)](https://github.com/shunk031/skills/actions/workflows/ci.yaml)
[![Docs](https://github.com/shunk031/skills/actions/workflows/docs.yaml/badge.svg)](https://github.com/shunk031/skills/actions/workflows/docs.yaml)
[![skills.sh](https://skills.sh/b/shunk031/skills)](https://skills.sh/shunk031/skills)

Coding-agent skills for Claude Code and Codex, installed with the [`skills`](https://github.com/vercel-labs/skills) CLI. Browsable at **[shunk031.me/skills](https://shunk031.me/skills/)**, where each skill's page shows what its evaluation measured. Each skill is a single `SKILL.md` that both agents read, and the ones that ship evaluation cases are gated with [`shuhari`](https://github.com/shunk031/shuhari) — a harness that measures whether a skill fires when it should and whether it changes what the agent produces.

## Install

Install one skill for both agents:

```bash
npx skills add shunk031/skills --skill <name> --agent claude-code --agent codex --global --yes
```

See what is available without installing anything:

```bash
npx skills add shunk031/skills --list
```

`--global` keeps one canonical copy at `~/.agents/skills/<name>` and points each agent at it, so Claude Code and Codex read the same file instead of drifting apart. `--yes` answers the prompts, which is what makes the command safe to run from a script.

### As a plugin

This repository is also a plugin for both agents, which installs every skill at once instead of naming them one at a time. For Claude Code:

```bash
claude plugin marketplace add shunk031/skills
claude plugin install shunk031-skills@shunk031
```

For Codex:

```bash
codex plugin marketplace add shunk031/skills
codex plugin add shunk031-skills@shunk031
```

Both read the same `skills/` directory, so the two channels deliver identical content — pick the plugin when you want all of it and the `skills` CLI when you want a few. Neither manifest lists the skills individually, so an installed plugin picks up whatever `skills/` currently holds; refresh with `claude plugin update shunk031-skills` or `codex plugin marketplace upgrade`.

## Skills

| Skill                                                                                                          | What it does                                                                                                                |
| -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| [`shunk031-codex-worker-prompting`](skills/shunk031-codex-worker-prompting/)                                   | Writes task prompts, follow-ups, and authorizations aimed at Codex-family worker models.                                    |
| [`shunk031-github-cgd-identity`](skills/shunk031-github-cgd-identity/)                                         | Performs GitHub writes in `creative-graphic-design` repositories as the machine user rather than the personal account.      |
| [`shunk031-github-comment-attach-files`](skills/shunk031-github-comment-attach-files/)                         | Uploads local files into a GitHub issue or pull request comment and returns the hosted URLs without posting the comment.    |
| [`shunk031-herdr-orchestrate-workers`](skills/shunk031-herdr-orchestrate-workers/)                             | Runs parallel Codex workers in Herdr worktree tabs and routes their reports, reviews, and pull-request lifecycles.          |
| [`shunk031-herdr-tab-status`](skills/shunk031-herdr-tab-status/)                                               | Chooses the leading status emoji and name for the current Herdr tab.                                                        |
| [`shunk031-manage-agent-guidance`](skills/shunk031-manage-agent-guidance/)                                     | Decides where a persistent agent rule belongs and keeps one source of truth behind thin adapters.                           |
| [`shunk031-manage-public-private-dotfiles`](skills/shunk031-manage-public-private-dotfiles/)                   | Works across the public and private dotfiles sources, changing only the repository that owns the setting.                   |
| [`shunk031-manage-public-private-skills`](skills/shunk031-manage-public-private-skills/)                       | Routes skill work between this repository and `shunk031/skills-private`, including evals and the dotfiles subscription.     |
| [`shunk031-python-transformers-convert`](skills/shunk031-python-transformers-convert/)                         | Converts a custom PyTorch model into Hugging Face Transformers format, through to Hub upload.                               |
| [`shunk031-python-uv-workflow`](skills/shunk031-python-uv-workflow/)                                           | Applies a uv-first, test-first Python workflow with pre-commit quality gates.                                               |
| [`shunk031-research-before-implementation`](skills/shunk031-research-before-implementation/)                   | Reads current official documentation and real implementations before designing anything that depends on a third-party tool. |
| [`shunk031-research-high-impact-journal-publishing`](skills/shunk031-research-high-impact-journal-publishing/) | Advises on study design, manuscript structure, journal selection, and peer review responses.                                |
| [`shunk031-shellscript-shdoc-docs`](skills/shunk031-shellscript-shdoc-docs/)                                   | Adds and repairs shdoc annotations in shell scripts and shell executables.                                                  |

## Layout

Each skill is one directory under `skills/`:

```text
skills/<name>/
├── SKILL.md            # required; frontmatter `name` must equal <name>
├── agents/             # optional per-agent wrappers
├── references/         # optional supporting documents
├── scripts/            # optional executables shipped with the skill
└── evals/
    ├── evals.json      # optional behavior cases
    └── triggers.json   # optional trigger cases and near-miss negatives
```

Nothing may sit deeper than `skills/<name>/SKILL.md`, and no `SKILL.md` may sit at the repository root: the CLI stops discovery at a root-level one and returns only that skill. Anything a skill needs at runtime belongs inside its own directory, because the CLI copies that directory and nothing else.

## Development

```bash
make setup            # install the pinned toolchain and the pre-commit hooks
make gate             # the offline checks CI runs
make validate         # layout checks and eval schema validation
make test             # unit tests for skills that ship executable scripts
make check-triggers   # live trigger checks for every skill that has them
make eval             # live with/without evaluation for every skill that has evals
make format           # shfmt diff for shell scripts
make bump-shuhari     # re-pin shuhari, which publishes no tagged releases
```

`make check-triggers` and `make eval` make real model calls through Codex, so they run locally rather than in CI, and both are whole-repository sweeps. Day to day the pre-commit hooks cover the same ground incrementally, evaluating only the skills a commit touches. See [`AGENTS.md`](AGENTS.md) for the evaluation policy and the authorized way to skip a gate.

## Related repositories

- [`shunk031/skills-private`](https://github.com/shunk031/skills-private) — skills whose body names an internal host, a credential, an internal endpoint, or an org-internal process.
- [`shunk031/dotfiles`](https://github.com/shunk031/dotfiles) — subscribes to these skills through a declarative allowlist reconciled on every `chezmoi apply`.

## License

[MIT](LICENSE)
