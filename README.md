# skills

Publicly shareable coding-agent skills, installed with the [`skills`](https://github.com/vercel-labs/skills) CLI and gated with [`shuhari`](https://github.com/shunk031/shuhari).

## Install

Install one skill for both Claude Code and Codex:

```bash
npx skills add shunk031/skills --skill <name> --agent claude-code --agent codex --global --yes
```

List what is available without installing anything:

```bash
npx skills add shunk031/skills --list
```

A global install keeps a single canonical copy at `~/.agents/skills/<name>` and symlinks `~/.claude/skills/<name>` and `~/.codex/skills/<name>` to it, so both agents read the same file.

## Layout

Each skill is a directory under `skills/`:

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

## Development

```bash
make setup            # install the pinned toolchain and the pre-commit hooks
make gate             # the offline checks CI runs
make validate         # layout checks and eval schema validation
make check-triggers   # live trigger checks for every skill that has them
make eval             # live with/without evaluation for every skill that has evals
```

`make check-triggers` and `make eval` make real model calls through Codex, so they run locally rather than in CI. See [`AGENTS.md`](AGENTS.md) for the evaluation policy and the authorized way to skip a gate.

## Related repositories

- [`shunk031/skills-private`](https://github.com/shunk031/skills-private) — skills that name internal hosts, credentials, endpoints, or org-internal processes.
- [`shunk031/dotfiles`](https://github.com/shunk031/dotfiles) — subscribes to these skills through a declarative allowlist reconciled on every `chezmoi apply`.

## License

[MIT](LICENSE)
