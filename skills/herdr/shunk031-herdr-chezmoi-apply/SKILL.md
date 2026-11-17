---
name: shunk031-herdr-chezmoi-apply
description: Use this skill to update and apply public and private dotfiles through Herdr, including requests to run chezmoi apply and chezmoi-private apply across all environments or only specified machines and containers.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🏠 I read shunk031-herdr-chezmoi-apply.`

# Apply dotfiles through Herdr

Use the `herdr` skill for the environment check and CLI syntax. Select `Local` plus all profiles from `herdr machine list --json`, or only the user's specified targets. Use each profile's SSH `target` for direct SSH commands; use the local shell for `Local`. Do not select targets by pane activity. Skip disabled or unreachable profiles and avoid duplicate application to the same destination.

Process multiple targets in parallel: the orchestrator starts one Herdr worker in its own tab per target, following the `shunk031-herdr-orchestrate-workers` skill. Each worker handles only its assigned target and follows these steps independently. Run one command per tool call. Read its output and exit status before choosing the next command. When forwarding a tool result, retain its exit status alongside its output; for example, keep both `exit_code` and `output` from `exec_command`. If a command is still running, wait for its completion and inspect the final result. Missing exit status is an unverified outcome, not success. Do not combine a target's workflow into a shell chain, loop, or script. The orchestrator collects per-target reports into one summary table. Editing this skill does not authorize executing it.

## Git first

Locate both existing source repositories with each chezmoi invocation's `source-path` and, in a separate command, `git -C <source-path> rev-parse --show-toplevel`; `.chezmoiroot` can place source state below the repository root. Skip missing setups rather than initializing them.

1. Confirm each source is the normal `main` checkout, with an upstream and no unfinished Git operation. Inspect `git status --short --branch`, then review staged and unstaged diffs. Before discarding them, record each path, the affected settings or behavior, and what was added, removed, or changed. Redact secret values while retaining enough context to explain the change; do not mask every changed line. Paths, line counts, and hunk headers alone are not a change summary.
2. The user authorizes discarding all tracked, uncommitted changes in that checkout. Restore the reviewed paths with `git restore --source=HEAD --staged --worktree -- <path>`, then check status in a separate command. Preserve untracked/ignored files, local commits, and other worktrees; do not use `git clean` or stash. A specific user instruction to preserve a change takes precedence.
3. Pull public, inspect the result, then pull private. Use the following command separately for each repository; the flags prevent user Git settings from enabling rebase or autostash.

```sh
ssh <target> 'git -C <repository> pull --ff-only --no-rebase --no-autostash'
```

On non-interactive SSH, a private pull may return `Repository not found` when Git lacks credentials. Before retrying, check the helper's active `gh` account with `gh api user` without printing tokens. If it is not the private repository owner, stop and report; using another account requires the user's direction. Retry once with GitHub CLI's command-scoped credential helper and the same pull flags. Use `git -c credential.helper= -c 'credential.helper=!gh auth git-credential' -C <repository> pull --ff-only --no-rebase --no-autostash`. Never print tokens.

Both pulls must succeed. Inspect each resulting Git status before moving to apply. Stop that target if unexpected edits appear, a preserved untracked file would enter the applied source state, or updating requires changing local commit history.

## Apply separately

Run supported template-rendering commands through `chezmoi-github-auth` on the target, for both public and private sources. The wrapper allows `apply`, `diff`, `status`, `managed`, and `verify`. It reads the target's active GitHub CLI credential internally and scopes it to that chezmoi process. Use this form:

```sh
ssh <target> chezmoi-github-auth --source public -- <apply|diff|status|managed|verify> [options]
```

Before applying named targets, follow `shunk031-manage-public-private-dotfiles`: apply source-managed paths; skip symlinks into source checkouts, which are live after the source is pulled. Record intentionally unmanaged or ignored paths without treating them as errors, and verify each live consumer path, not only its source file.

Inspect each apply plan with `chezmoi-github-auth --source public -- status` or a redacted `chezmoi-github-auth --source public -- diff`. Stop on unexplained destination edits or a confirmation prompt; do not force an overwrite. Then run public apply first:

```sh
ssh <target> chezmoi-github-auth --source public -- apply
```

Only after public apply succeeds, run private apply through the wrapper:

```sh
ssh <target> chezmoi-github-auth --source private -- apply
```

For `Local`, call `chezmoi-github-auth` directly with the selected source and command. Token lookup runs inside the wrapper on the target, and the token is available only to its chezmoi process; do not copy tokens between machines, switch accounts, or print credential values. If the wrapper is unavailable or cannot read the active credential, stop and report the failure; do not fall back to an inline token command, log in, or switch accounts.

## Diagnose a stopped apply

Identify the failing command before retrying. If a template-rendering command reports an anonymous GitHub API 403 rate limit, rerun it once through `chezmoi-github-auth` instead of waiting for the rate limit to reset. If the wrapper cannot read the active credential or the retry still fails, stop and report the failure. Do not change the external template.

If `mise install` fails to download a pinned tool with a connection reset, test the reported URL directly and through the target's available proxy. When only the proxy works, scope `HTTP_PROXY` and `HTTPS_PROXY` to the failed `mise install`, then retry apply after the tool is installed. Keep the pinned tool and its installer.

If apply stops producing output during skill reconciliation, inspect its child process before interrupting it. When `skills update` is stuck cloning a private `git@github.com:` URL and SSH is unreachable, verify HTTPS access to that repository with the already active `gh` account. For the retry, run `chezmoi-github-auth --source private --rewrite-github-ssh -- apply`; the wrapper scopes the active credential and the Git URL rewrite to that apply invocation. Do not change global Git configuration or choose a different account without user direction; stop if HTTPS access is unavailable.

## Report

On failure, stop that target's remaining steps and continue with the others. For errors other than the anonymous GitHub API 403 described above, inspect the error and current state before retrying once after correcting the cause. Do not blindly repeat an interrupted apply.

Report public/private update and apply outcomes for each target, including failures and steps not run. Then give bullets from the summaries recorded before removal: `<target> / <public or private>: Discarded <change summary> in <path>`. Mention preserved paths and remaining actions. Never include secret values or raw private diffs.
