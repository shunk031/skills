# AGENTS.md

> [!NOTE]
> After reading this `AGENTS.md`, say: `🤖 I read the AGENTS.md for shunk031/skills.`

## Repository Context

- Purpose: This repository is the source of truth for the publicly shareable coding-agent skills used across `shunk031`'s environments. It is consumed with the [`skills`](https://github.com/vercel-labs/skills) CLI, not by cloning it into place.
- Private counterpart: Skills that name an internal host, a credential, an internal endpoint, or an org-internal process live in `shunk031/skills-private` instead. Treat the two repositories as separate management domains.
- Dotfiles boundary: `shunk031/dotfiles` and `shunk031/dotfiles-private` subscribe to these skills through a declarative allowlist. They no longer hold skill content. Do not add chezmoi source state, `symlink_*.tmpl` adapters, or `home/` trees here.
- Coordination: Use the `shunk031-manage-public-private-skills` skill when a change spans this repository and either dotfiles repository, or when deciding which repository owns a skill.

## Skill Layout

- Location: Every skill is a directory at `skills/<name>/` containing `SKILL.md`. Optional siblings are `agents/`, `references/`, `scripts/`, and `evals/`.
- Naming: The `name` field in `SKILL.md` frontmatter must equal the directory name. Shuhari refuses to load a skill whose name and directory disagree, and the `skills` CLI installs by directory name.
- Never place a `SKILL.md` at the repository root. The `skills` CLI stops discovery at a root-level `SKILL.md` and returns only that one skill, which makes every other skill in this repository invisible to installers.
- Never nest a skill deeper than `skills/<name>/`. Discovery walks a bounded number of levels, and a deeper `SKILL.md` is not reliably found.
- Do not add `AGENTS.evals.json` to this repository. `shuhari eval instructions` resolves its eval file as `<file-without-extension>.evals.json`, so that file would create a second instructions gate here. The shared instructions gate belongs to `shunk031/dotfiles`.

## Evaluation Policy

- Harness: Quality gates run through [`shuhari`](https://github.com/shunk031/shuhari). This repository owns target selection and policy values; shuhari owns the evaluation mechanism.
- Behavior cases: `skills/<name>/evals/evals.json` holds cases that measure what the agent does when the skill applies. Each case requires `id`, `prompt`, and `expected_output`; `assertions`, `files`, and `required_actions` are optional.
- Trigger cases: `skills/<name>/evals/triggers.json` holds positive cases and near-miss negative controls. Shuhari requires at least one of each. An obviously irrelevant negative control tests nothing.
- Writing `expected_output`: State the correct outcome in one to three sentences, describing produced behavior rather than the wording of a reply. Do not restate the assertions. Shuhari runs a blind A/B comparator in addition to assertion grading, so assertion wording copied into `expected_output` biases that comparison.
- Order of work: Run `--validate-only` first, then `shuhari check trigger`, then `shuhari eval skill`. The first is instant and offline, the second runs one arm, and the third runs both arms plus a grader and a comparator.
- Artifacts: Shuhari writes `skills/<name>-workspace/` next to the evaluated skill. It holds verbatim agent transcripts and is gitignored. Never commit it and never paste its contents into an issue, a pull request, or a report.
- Skills without evals: A skill may ship without `evals/`. The gate wrapper skips it rather than failing. Adding evals to an existing skill is a welcome change on its own.

## Development Setup

- In every new clone or worktree, run `make setup` before editing or committing. It installs the pinned toolchain and the pre-commit hooks.
- `shuhari` must be on `PATH` for the gates to run. The wrapper exits with status 2 when it is missing, because a gate that cannot run is a failure rather than a pass.
- `shuhari` has no tagged release, so `mise.toml` pins the pseudo-version of a `main` commit rather than a semantic version. Run `make bump-shuhari` to move that pin to current `main`. Run it as plain `make`, never through `mise exec`: mise resolves every pinned tool before running a command, so a stale or unresolvable pin would fail before the recipe could replace it.
- Never install `shuhari` with a bare `go install`. That writes into the Go toolchain's own `bin` directory, which sits ahead of the pinned tool on `PATH`, so the gates silently run a build nobody pinned. Check with `mise which shuhari`: it must resolve under `installs/go-github-com-shunk031-shuhari-cmd-shuhari/<version>/`. If it resolves anywhere else, delete that binary and re-run `make setup`.
- The live gates make real model calls through Codex, so they run in pre-commit only. CI is limited to schema validation, layout checks, linting, and unit tests.
- `SKIP=shuhari-check-trigger,shuhari-eval-skill git commit` is the authorized escape hatch when the model path is unavailable. Report the skip in the pull request body; do not treat a skipped gate as a passing gate.

## Shell Policy

- Shell scripts a skill ships must run on Bash 3.2. macOS still ships it, and that is the machine an agent works on, so a Bash 4 feature — `declare -A`, `mapfile`, `${var,,}` — runs on Linux and dies where it matters.
- `tests/bats/` covers those scripts. `make test` runs it alongside the Python tests, and CI runs both on Linux and macOS so the 3.2 path is actually exercised.

## Documentation Site

- The site is generated from the skills by `scripts/build_docs.py` and built by Zensical. `docs/` and `site/` are gitignored: committing generated pages would make every skill edit carry a second, mechanical diff that can drift from its source.
- `make docs-serve` previews it locally; `make docs-build` is what CI runs, with `--strict` so a broken link fails.
- A skill page shows what its evaluation measured, from `skills/<name>/evals/results.json`. `scripts/record_eval_results.py` lifts those numbers out of a completed Shuhari run. That file is committed; the workspace it comes from is not, because the workspace holds transcripts and the numbers do not.

## Comment Policy

- When adding or updating comments for shell scripts or shell-based executables, write them in English using shdoc-compatible format.

## Prose Policy

- Markdown prose is checked by textlint with `@cffnpwr/textlint-rule-no-arbitrary-line-break`. Do not hard-wrap sentences; let each paragraph be one line.
