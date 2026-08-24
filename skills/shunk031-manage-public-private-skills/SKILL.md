---
name: shunk031-manage-public-private-skills
description: Route and carry out work on coding-agent skills across shunk031/skills and shunk031/skills-private. Use when asked to add, edit, rename, split, or remove a skill; when deciding which repository owns one; when writing or converting eval and trigger cases; or when a skill change has to reach a machine through the dotfiles subscription. Also use when a request names a skill while you are working in a dotfiles repository, because skill content no longer lives there.
---

# Manage Public and Private Skills

Skill content lives in two dedicated repositories. Neither dotfiles repository holds it any more, so a request to change a skill is a request to change one of these, not the checkout you are probably standing in.

## Where a skill lives

| Repository                  | Holds                                                                                                    |
| --------------------------- | -------------------------------------------------------------------------------------------------------- |
| `shunk031/skills`           | Every publishable skill                                                                                  |
| `shunk031/skills-private`   | Skills whose body names an internal host, a credential, an internal endpoint, or an org-internal process |
| `shunk031/dotfiles`         | The subscription allowlist and the reconcile script. No skill content                                    |
| `shunk031/dotfiles-private` | No skill content                                                                                         |

The deciding test is that single question about the skill body. Being written for work does not make a skill private; naming an internal system does. When a skill is close to the line, prefer private and say why.

## Routing a request

1. Identify the skill by name. `~/.agents/skills/<name>` is the installed copy; it tells you the skill exists, not where its source is.
2. Decide the owning repository with the test above, or by checking which repository already contains it.
3. Work in a task worktree of that repository. Never edit the installed copy.
4. If the change spans both skill repositories, keep the worktrees, commits, and pull requests separate and state the ordering between them.

## Never edit the installed copy

`~/.agents/skills/<name>` is a real directory that the `skills` CLI writes. It is a copy, not a link to any source, so edits there are silently discarded by the next `skills update`.

This differs from the old arrangement, where the pool entry was a symlink into the chezmoi source tree and editing the live skill did edit the source.

## The loop from edit to running skill

```
edit in the skill repository worktree
  → gates pass locally
  → pull request
  → merge
  → chezmoi apply on the machine, which runs skills add/update
```

`chezmoi apply` throttles `skills update` to once a day so that a file-watch loop does not fetch on every save. Right after merging, force it:

```bash
DOTFILES_SKILLS_FORCE_UPDATE=1 chezmoi apply    # or: make skills-update
```

Adding or removing a skill from the allowlist is a change to `install/common/skills.sh` in `shunk031/dotfiles`, and it belongs in its own pull request there, separate from the skill's own.

## Layout rules that are easy to get wrong

- One directory per skill at `skills/<name>/`, holding `SKILL.md`. Frontmatter `name` must equal the directory name.
- Never put a `SKILL.md` at a repository root. The `skills` CLI stops discovery there and returns only that skill, hiding every other one from installers.
- Never nest a skill deeper than `skills/<name>/`.
- `evals/` is reserved: shuhari looks for `evals/evals.json` and `evals/triggers.json` at fixed paths.
- Never commit `skills/<name>-workspace/`. Those are shuhari run artifacts holding verbatim agent transcripts.
- Scripts a skill needs at runtime go inside the skill directory. The CLI copies the whole skill directory into the pool, so anything outside it will not be there when the skill runs.

## Writing evals

Behavior cases go in `evals/evals.json`, each with `id`, `prompt`, and `expected_output`; `assertions` and `files` are optional. Trigger cases go in `evals/triggers.json` and need at least one positive and one near-miss negative control.

Write `expected_output` as one to three sentences describing the behaviour that should result, not the wording of a good reply, and **do not restate the assertions**. Shuhari runs a blind A/B comparator between the with-skill and without-skill outputs alongside assertion grading, so `expected_output` that echoes assertion text biases that comparison.

Make negative controls near misses. A control that shares the skill's vocabulary while genuinely not calling for it measures the boundary; an unrelated prompt measures nothing.

Runs are offline by default. A skill whose subject is the live network cannot be graded offline: it correctly refuses to proceed and loses to a baseline that guesses. Declare the exception with an `evals/network-required` marker.

Order of work is `--validate-only`, then `shuhari check trigger`, then `shuhari eval skill`. The first is instant and offline; the last runs both arms plus a grader and a comparator.

## Authoring and reviewing a skill

Write one `SKILL.md`. Do not create per-agent variants: a global install keeps a single canonical copy at `~/.agents/skills/<name>` and points each agent at it.

Review the draft with both agents' skill-creation skills, because they disagree usefully:

- Claude Code: `/skill-creator`
- Codex: `$skill-creator` (its built-in, at `~/.codex/skills/.system/skill-creator`)

## Before finishing

Run the owning repository's gates and report which repository owns each change. Keep credential values out of command output, quoted diffs, and summaries — this matters in the private repository, where eval prompts are committed in plaintext and must use placeholders.

Creating or updating a pull request is part of ordinary work. Merging, running `chezmoi apply`, and changing runtime state are not: ask first.
