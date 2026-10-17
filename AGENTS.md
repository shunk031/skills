# AGENTS.md

> [!NOTE]
> After reading this `AGENTS.md`, say: `🤖 I read the AGENTS.md for shunk031/skills.`

## Repository Context

- Purpose: This repository is the source of truth for the publicly shareable coding-agent skills used across `shunk031`'s environments. It is consumed with the [`skills`](https://github.com/vercel-labs/skills) CLI, not by cloning it into place.
- Format: Skills here follow the open Agent Skills format described at https://agentskills.io/home: a directory holding a `SKILL.md` whose frontmatter carries at least `name` and `description`, with bundled scripts and reference files optional. The Skill Layout rules below narrow that format for this repository; they do not replace it.
- Private counterpart: Skills that name an internal host, a credential, an internal endpoint, or an org-internal process live in `shunk031/skills-private` instead. Treat the two repositories as separate management domains.
- Dotfiles boundary: `shunk031/dotfiles` subscribes to this repository as a whole, while `shunk031/dotfiles-private` selects private skills individually. Neither repository holds skill content. Do not add chezmoi source state, `symlink_*.tmpl` adapters, or `home/` trees here.
- Coordination: Use the `shunk031-manage-public-private-skills` skill when a change spans this repository and either dotfiles repository, or when deciding which repository owns a skill.

## Skill Layout

- Location: Every skill is a directory at `skills/<category>/<name>/` containing `SKILL.md`. Optional siblings are `agents/`, `references/`, `scripts/`, and `evals/`.
- Naming: The `name` field in `SKILL.md` frontmatter must equal the directory name so skill discovery and installation use one stable name.
- Domain-first names: A skill owned here is named `shunk031-<domain>-<topic>`, where `<domain>` is one of the domains `scripts/check_skill_layout.sh` allows. Skills sort and read by the subject they belong to rather than by the verb that happens to start their name, so adding a domain means changing that allowlist deliberately rather than inventing a prefix at commit time.
- Read receipts: Immediately after the frontmatter and before the first heading, every `SKILL.md` opens with a NOTE block written in the skill body's language: an English skill says `` After reading this `SKILL.md`, say: `<emoji> I read <skill-name>.`  ``, while a Japanese skill says `` この `SKILL.md` を読んだら、`<emoji> 私は <skill-name> を読みました。` と言う。 ``; the emoji fits the skill's subject, `<skill-name>` matches the frontmatter name, and the receipt makes skill loading observable in the transcript.
- Never place a `SKILL.md` at the repository root. The `skills` CLI stops discovery at a root-level `SKILL.md` and returns only that one skill, which makes every other skill in this repository invisible to installers.
- Category layout: Keep each skill at `skills/<category>/<name>/`. The category is the domain encoded after `shunk031-`; the skill name itself remains unchanged.

## Evaluation Cases

- Behavior cases: `skills/<category>/<name>/evals/evals.json` follows Anthropic skill-creator's schema. It is optional and records prompts and expectations; this repository has no command to execute or grade the cases.
- Eval authoring: Read `skills/manage/shunk031-manage-public-private-skills/references/eval-authoring.md` when writing or revising cases.
- Results: Existing `evals/results.json` files are dated snapshots shown on the documentation site. Documentation builds do not update them.

## Development Setup

- In every new clone or worktree, run `make setup` before editing or committing. It installs the routine toolchain and pre-commit hooks.

## Shell Policy

- Shell scripts a skill ships must run on Bash 3.2. macOS still ships it, and that is the machine an agent works on, so a Bash 4 feature — `declare -A`, `mapfile`, `${var,,}` — runs on Linux and dies where it matters.
- `tests/bats/` covers those scripts. `make test` runs it alongside the Python tests, and CI runs both on Linux and macOS so the 3.2 path is actually exercised.

## Documentation Site

- The site is generated from the skills by `scripts/build_docs.py` and built by Zensical. `docs/` and `site/` are gitignored: committing generated pages would make every skill edit carry a second, mechanical diff that can drift from its source.
- `make docs-serve` previews it locally; `make docs-build` is what CI runs, with `--strict` so a broken link fails. `--strict` covers links and nothing else: a page whose code blocks render as headings still builds clean, which is how the site shipped for a while with a shebang as an H1.
- A skill's `SKILL.md` is shown verbatim inside a card, titled by the same icon the navigation uses. It is a quoted artifact written for an agent, not this site's prose, and the card is what draws that line. A card is only styled as `.grid > .card`, so it needs both wrappers; `.card` alone renders as plain text with a class nobody reads.
- The card's title is bold text followed by `---`, which is the shape the theme's card is built around. A heading there fights every margin the theme sets and leaves the page with two H1s. Hand-written CSS lives in `assets/` and is copied into the generated `docs/`.
- A skill page shows a dated evaluation snapshot when `skills/<category>/<name>/evals/results.json` exists. These snapshots are committed; documentation builds do not regenerate them.

## Comment Policy

- When adding or updating comments for shell scripts or shell-based executables, write them in English using shdoc-compatible format.

## Prose Policy

- Markdown prose is checked by textlint with `@cffnpwr/textlint-rule-no-arbitrary-line-break`. Do not hard-wrap sentences; let each paragraph be one line.
