---
name: shunk031-manage-public-private-skills
description: Route coding-agent skill work between the public and private source repositories. Use when an installed skill change vanished, when adding, editing, renaming, splitting, or removing a skill, or when writing its evals and trigger cases.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🧰 I read shunk031-manage-public-private-skills.`

# Manage Public and Private Skills

Skill content lives in two dedicated repositories. Neither dotfiles repository holds it any more, so a request to change a skill is a request to change one of these, not the checkout you are probably standing in.

## Where a skill lives

| Repository | Holds |
| --- | --- |
| `shunk031/skills` | Every publishable skill |
| `shunk031/skills-private` | Skills whose body names an internal host, a credential, an internal endpoint, or an org-internal process |
| `shunk031/dotfiles` | The reconcile script and the public subscriptions. No skill content |
| `shunk031/dotfiles-private` | The private subscriptions. No skill content |

The deciding test is that single question about the skill body. Being written for work does not make a skill private; naming an internal system does. When a skill is close to the line, prefer private and say why.

## Routing a request

1. Identify the skill by name. `~/.agents/skills/<name>` is the installed copy; it tells you the skill exists, not where its source is.
2. Decide the owning repository with the test above, or by checking which repository already contains it.
3. Work in a task worktree of that repository. Never edit the installed copy.
4. If the change spans both skill repositories, keep the worktrees, commits, and pull requests separate and state the ordering between them.

## Never edit the installed copy

`~/.agents/skills/<name>` is a real directory that the `skills` CLI writes. It is a copy, not a link to any source, so edits there are silently discarded by the next `skills update`.

This differs from the old arrangement, where the pool entry was a symlink into the chezmoi source tree and editing the live skill did edit the source.

## Verify which version is running

When diagnosing a missing or ineffective skill update, compare GitHub's current content at the subscribed ref, the installed `~/.agents/skills/<name>` copy, and the content the target session actually read. Resolve the current GitHub commit or blob through the remote; a local checkout or `origin/main` may be stale even when it matches the installed copy. Check the target session's transcript or an authorized reread; an updated file alone does not prove the session loaded it. Mark any unavailable comparison as unverified. Distinguish an undeployed change from behavior that the current source no longer specifies before recommending a sync.

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

| Skill source | Subscription handling |
| --- | --- |
| `shunk031/skills` | The repository-wide subscription discovers additions; the reconciliation script removes names reported as upstream deletions, while renames or cases the warning does not cover add the old name to `SKILLS_RETIRED_NAMES` in `shunk031/dotfiles` |
| `shunk031/skills-private` | Add or remove its entry in `home/dot_config/agents/skills-private.allowlist` in `shunk031/dotfiles-private` |
| Third-party repository | Add or remove its selected entry in `install/common/skills.sh` in `shunk031/dotfiles` |

After merging a public skill change, use `DOTFILES_SKILLS_FORCE_UPDATE=1 chezmoi apply` or `make skills-update` to bypass the daily discovery throttle. Ordinary reconciliation discovers additions within one day and removes names reported by the `skills update` upstream-deletion warning. Keep `SKILLS_RETIRED_NAMES` for renames or deletions that the warning does not expose.

**Never write a private skill's name into `shunk031/dotfiles`.** It is a public repository, and the name alone discloses the internal host, service, or process that putting the skill in the private repository was meant to hide. The reconcile script is public and stays public; only the list of private names moves.

The reconciler reads the applied private file at reconcile time and appends its entries to its own public list, so both sets install through one pass. A machine that has only the public source has no such file, which is normal rather than an error.

In that file only a leading `#` starts a comment, because an entry may carry a `#<ref>` suffix pinning a branch or tag.

## Layout rules that are easy to get wrong

- One directory per skill at `skills/<name>/`, holding `SKILL.md`. Frontmatter `name` must equal the directory name.
- Never put a `SKILL.md` at a repository root. The `skills` CLI stops discovery there and returns only that skill, hiding every other one from installers.
- Never nest a skill deeper than `skills/<name>/`.
- `evals/` is reserved: shuhari looks for `evals/evals.json` and `evals/triggers.json` at fixed paths.
- Never commit `skills/<name>-workspace/`. Those are shuhari run artifacts holding verbatim agent transcripts.
- Scripts a skill needs at runtime go inside the skill directory. The CLI copies the whole skill directory into the pool, so anything outside it will not be there when the skill runs.

## Writing evals

Behavior cases go in `evals/evals.json`; trigger cases go in `evals/triggers.json`. Read [references/eval-authoring.md](references/eval-authoring.md) when adding or changing either file. It covers case scope, near-miss controls, trial variance, network-required cases, and gate order.

## Authoring and reviewing a skill

Write one `SKILL.md`. Do not create per-agent variants: a global install keeps a single canonical copy at `~/.agents/skills/<name>` and points each agent at it.

In shared skill prose, eval prompts, and cross-agent guidance, refer to another skill as `<skill-name> skill`. Do not use Codex's `$skill-name` or Claude Code's `/skill-name` invocation syntax as a general reference. Use those forms only when documenting invocation syntax for that specific agent.

Review the draft with both agents' skill-creation skills, because they disagree usefully:

- Claude Code: `/skill-creator`
- Codex: `$skill-creator` (its built-in, at `~/.codex/skills/.system/skill-creator`)

## Before finishing

Run the owning repository's gates and report which repository owns each change. Keep credential values out of command output, quoted diffs, and summaries — this matters in the private repository, where eval prompts are committed in plaintext and must use placeholders.

Creating or updating a pull request is part of ordinary work. Merging, running `chezmoi apply`, and changing runtime state are not: ask first.
