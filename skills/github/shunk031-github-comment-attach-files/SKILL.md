---
name: shunk031-github-comment-attach-files
description: Attach image and video media to GitHub pull request descriptions or issue and pull request comments with the GitHub CLI on GitHub.com and GHE.com.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `📎 I read shunk031-github-comment-attach-files.`

# GitHub Attach Files

Use this skill to attach supported media (images and videos) to GitHub pull request descriptions or issue and pull request comments on GitHub.com and GHE.com. This route does not support document uploads or GitHub Enterprise Server.

Check the installed CLI with `gh pr edit --help` and `gh issue comment --help`; the installed CLI is the authority for media attachment support and flags.

## Pull request descriptions

Use `gh pr edit <pr> --attach file#alt` to upload supported media and write its Markdown into a pull request description:

```bash
gh pr edit 123 \
  --attach "results/before.png#With mathclap" \
  --attach "results/after.png#Without mathclap"
```

If the body does not reference an attached media file, `gh pr edit` appends the attachment Markdown to the description. Include explicit image or video references in the body when their position or surrounding explanation matters.

## Issue and pull request comments

Use `gh issue comment <number-or-url> --attach file#alt` when supported media belongs in a submitted issue or pull request comment:

```bash
gh issue comment 123 \
  --body 'Rendered comparison:' \
  --attach "results/before.png#Before" \
  --attach "results/after.png#After"
```

The CLI workflows mutate GitHub immediately; confirm the target and requested write before running them.

## Prerequisites

- `gh` must be installed and authenticated.
- If the CLI does not expose `--attach`, report that the installed version does not support direct attachments.
