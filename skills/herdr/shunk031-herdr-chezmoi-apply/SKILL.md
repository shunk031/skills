---
name: shunk031-herdr-chezmoi-apply
description: Use this skill to update and apply public and private dotfiles through Herdr, including requests to run chezmoi apply and chezmoi-private apply across all environments or only specified machines and containers.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🏠 I read shunk031-herdr-chezmoi-apply.`

# Apply dotfiles through Herdr

Use the `herdr` skill for the environment check and CLI syntax. Select `Local` plus all profiles from `herdr machine list --json`, or only the user's specified targets. Use each profile's SSH `target` for direct SSH commands; use the local shell for `Local`. Do not select targets by pane activity. Skip disabled or unreachable profiles and avoid duplicate application to the same destination.

Run one command per tool call. Read its output and exit status before choosing the next command. When forwarding a tool result, retain its exit status alongside its output; for example, keep both `exit_code` and `output` from `exec_command`. If the command is still running, wait for its completion and inspect the final result. Missing exit status is an unverified outcome, not success. Process targets sequentially; do not combine the workflow into a shell chain, loop, or script. Editing this skill does not authorize executing it.

## Git first

Locate both existing source repositories with each chezmoi invocation's `source-path` and, in a separate command, `git -C <source-path> rev-parse --show-toplevel`; `.chezmoiroot` can place source state below the repository root. Skip missing setups rather than initializing them.

1. Confirm each source is the normal `main` checkout, with an upstream and no unfinished Git operation. Inspect `git status --short --branch`, then review staged and unstaged diffs. Before discarding them, record each path, the affected settings or behavior, and what was added, removed, or changed. Redact secret values while retaining enough context to explain the change; do not mask every changed line. Paths, line counts, and hunk headers alone are not a change summary.
2. The user authorizes discarding all tracked, uncommitted changes in that checkout. Restore the reviewed paths with `git restore --source=HEAD --staged --worktree -- <path>`, then check status in a separate command. Preserve untracked/ignored files, local commits, and other worktrees; do not use `git clean` or stash. A specific user instruction to preserve a change takes precedence.
3. Pull public, inspect the result, then pull private. Use the following command separately for each repository; the flags prevent user Git settings from enabling rebase or autostash.

```sh
ssh <target> 'git -C <repository> pull --ff-only --no-rebase --no-autostash'
```

Both pulls must succeed. Inspect each resulting Git status before moving to apply. Stop that target if unexpected edits appear, a preserved untracked file would enter the applied source state, or updating requires changing local commit history.

## Apply separately

Inspect each apply plan with `chezmoi status` or a redacted diff. Stop on unexplained destination edits or a confirmation prompt; do not force an overwrite.

Confirm the target's existing `gh` authentication is available without printing its token. Run public apply:

```sh
ssh <target> 'GITHUB_TOKEN="$(gh auth token)" chezmoi apply'
```

Read the result. Only after success, run private apply. `chezmoi-private` may be an alias unavailable over non-interactive SSH; resolve its configured source/config and use the explicit equivalent. With the conventional paths:

```sh
ssh <target> 'GITHUB_TOKEN="$(gh auth token)" chezmoi --source "$HOME/.local/share/chezmoi-private" --config "$HOME/.config/chezmoi-private/chezmoi.yaml" apply'
```

For `Local`, run the command inside the quotes directly. Token lookup happens on the target and is scoped to that invocation; do not copy tokens between machines, switch accounts automatically, or print credential values.

## Report

On failure, stop that target's remaining steps and continue with the others. Inspect the error and current state before any retry; retry once only after correcting the cause. Do not blindly repeat an interrupted apply.

Report public/private update and apply outcomes for each target, including failures and steps not run. Then give bullets from the summaries recorded before removal: `<target> / <public or private>: Discarded <change summary> in <path>`. Mention preserved paths and remaining actions. Never include secret values or raw private diffs.
