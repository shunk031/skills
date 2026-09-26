---
name: shunk031-github-comment-attach-files
description: Attach local files to GitHub pull request descriptions or issue and pull request comments with the GitHub CLI. Use when you need GitHub-hosted image or document attachments on github.com or GitHub Enterprise Server.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `📎 I read shunk031-github-comment-attach-files.`

# GitHub Attach Files

Use this skill when local files need to become GitHub-hosted attachments on github.com or GitHub Enterprise Server.

Check the installed CLI with `gh pr edit --help` and `gh issue comment --help`; the installed CLI is the authority for attachment support and flags.

## Pull request descriptions

Use `gh pr edit <pr> --attach file#alt` to upload files and write their Markdown into a pull request description:

```bash
gh pr edit 123 \
  --body-file pr-body.md \
  --attach results/before.png#With mathclap \
  --attach results/after.png#Without mathclap
```

If the body does not reference an attached file, `gh pr edit` appends the attachment Markdown to the description. Include explicit image references in the body when their position or surrounding explanation matters.

## Issue and pull request comments

Use `gh issue comment <number-or-url> --attach file#alt` when the attachment belongs in a submitted issue or pull request comment:

```bash
gh issue comment 123 \
  --body 'Rendered comparison:' \
  --attach results/before.png#Before \
  --attach results/after.png#After
```

The CLI workflows mutate GitHub immediately; confirm the target and requested write before running them.

## Prerequisites

- `gh` must be installed and authenticated.
- If the CLI does not expose `--attach`, report that the installed version does not support direct attachments.
