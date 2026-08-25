# skills

Coding-agent skills for Claude Code and Codex, installed with the [`skills`](https://github.com/vercel-labs/skills) CLI. Each skill is a single `SKILL.md` that both agents read, and the ones that ship evaluation cases are gated with [`shuhari`](https://github.com/shunk031/shuhari) — a harness that measures whether a skill fires when it should and whether it changes what the agent produces.

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

## Skills

| Skill                                                                                        | What it does                                                                                                                      |
| -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| [`shunk031-ai-slop-checklist-ja`](skills/shunk031-ai-slop-checklist-ja/)                     | Reviews Japanese prose for AI-sounding writing and returns findings, a score, and concrete fixes.                                 |
| [`shunk031-cgd-dev-identity`](skills/shunk031-cgd-dev-identity/)                             | Performs GitHub writes in `creative-graphic-design` repositories as the machine user rather than the personal account.            |
| [`shunk031-codex-worker-prompting`](skills/shunk031-codex-worker-prompting/)                 | Writes task prompts, follow-ups, and authorizations aimed at Codex-family worker models.                                          |
| [`shunk031-doc-slop-review`](skills/shunk031-doc-slop-review/)                               | Gates a reader-facing draft with deterministic checks and one blind model judge, returning PASS or FAIL with each problem quoted. |
| [`shunk031-gh-comment-attach-files`](skills/shunk031-gh-comment-attach-files/)               | Uploads local files into a GitHub issue or pull request comment and returns the hosted URLs without posting the comment.          |
| [`shunk031-herdr-tab-status`](skills/shunk031-herdr-tab-status/)                             | Chooses the leading status emoji and name for the current Herdr tab.                                                              |
| [`shunk031-high-impact-journal-publishing`](skills/shunk031-high-impact-journal-publishing/) | Advises on study design, manuscript structure, journal selection, and peer review responses.                                      |
| [`shunk031-humanizer-ja`](skills/shunk031-humanizer-ja/)                                     | Rewrites AI-sounding Japanese into natural prose without flattening the intended tone.                                            |
| [`shunk031-manage-agent-guidance`](skills/shunk031-manage-agent-guidance/)                   | Decides where a persistent agent rule belongs and keeps one source of truth behind thin adapters.                                 |
| [`shunk031-manage-public-private-dotfiles`](skills/shunk031-manage-public-private-dotfiles/) | Works across the public and private dotfiles sources, changing only the repository that owns the setting.                         |
| [`shunk031-manage-public-private-skills`](skills/shunk031-manage-public-private-skills/)     | Routes skill work between this repository and `shunk031/skills-private`, including evals and the dotfiles subscription.           |
| [`shunk031-orchestrate-herdr-workers`](skills/shunk031-orchestrate-herdr-workers/)           | Runs parallel Codex workers in Herdr worktree tabs and routes their reports, reviews, and pull-request lifecycles.                |
| [`shunk031-python-uv-workflow`](skills/shunk031-python-uv-workflow/)                         | Applies a uv-first, test-first Python workflow with pre-commit quality gates.                                                     |
| [`shunk031-research-before-implementation`](skills/shunk031-research-before-implementation/) | Reads current official documentation and real implementations before designing anything that depends on a third-party tool.       |
| [`shunk031-research-report-ja`](skills/shunk031-research-report-ja/)                         | Writes Japanese research reports that give a first-time reader the question, method, findings, and resulting decision.            |
| [`shunk031-shdoc-shell-docs`](skills/shunk031-shdoc-shell-docs/)                             | Adds and repairs shdoc annotations in shell scripts and shell executables.                                                        |
| [`shunk031-structured-writing`](skills/shunk031-structured-writing/)                         | Organizes plans, reports, and documents so their hierarchy and relationships are visible.                                         |
| [`shunk031-transformers-convert`](skills/shunk031-transformers-convert/)                     | Converts a custom PyTorch model into Hugging Face Transformers format, through to Hub upload.                                     |

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
