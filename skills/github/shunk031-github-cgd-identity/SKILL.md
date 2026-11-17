---
name: shunk031-github-cgd-identity
description: Use this skill for all GitHub write operations in creative-graphic-design organization repositories (such as design-generators), including git commits and pushes, PR creation and updates, issue and PR comments, labels, milestones, and user-requested merges. Perform them as the creative-graphic-design-dev machine user. Use it both when the user explicitly requests the bot or dev account and whenever beginning write work in a creative-graphic-design organization repository without an explicit request; never use it in repositories of any other organization or host.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🎨 I read shunk031-github-cgd-identity.`

# CGD Dev Identity

## Overview

Perform git and gh write operations for creative-graphic-design organization repositories as the `creative-graphic-design-dev` machine user (user ID 176740601), not a personal account. A bot-authored PR lets a human account formally review and approve it. Because GitHub does not permit users to approve their own PRs, creating a PR with a personal account would prevent the review flow from working.

## Setup

Before starting write operations, perform the following checks in the working shell and worktree. Run them as a starting procedure rather than investigating only after a failure.

1. For repository writes, confirm that `git remote get-url origin` points to `github.com/creative-graphic-design`.

   If it does not, this skill does not apply; use normal git identity and authentication.

2. Ensure that GitHub CLI has the bot account in its dedicated configuration directory. The user performs this interactive login once on each machine and authenticates in the browser as `creative-graphic-design-dev`:

   ```bash
   GH_CONFIG_DIR=$HOME/.config/gh-cgd gh auth login
   ```

   Agents must not run this login command. Do not use `gh auth switch`; it changes the account for the selected configuration directory and can race with concurrent sessions.

3. Prefix GitHub CLI commands with the dedicated config directory:

   ```bash
   GH_CONFIG_DIR="$HOME/.config/gh-cgd" gh pr create ...
   ```

   `gh` reads the bot credential from this directory. The credential stays in GitHub CLI's credential store and is not placed in command text or an environment variable.

4. Verify the GitHub identity and push permission for the organization repository. `gh api user` only confirms the logged-in account and cannot verify access to organization resources:

   ```bash
   GH_CONFIG_DIR="$HOME/.config/gh-cgd" gh api user --jq .login
   GH_CONFIG_DIR="$HOME/.config/gh-cgd" gh api repos/creative-graphic-design/<repo> --jq .permissions.push
   ```

   Do not start write operations unless the first command returns `creative-graphic-design-dev` and the second returns `true`.

5. Set the bot author for each commit without changing shared Git configuration:

   ```bash
   git -c user.name=creative-graphic-design-dev -c user.email=176740601+creative-graphic-design-dev@users.noreply.github.com commit ...
   ```

   Do not use `git config user.name/email` in a linked worktree. It writes shared configuration and changes the author for other worktrees too.

6. Push over HTTPS because SSH does not use the proxy in this environment. Set an explicit push URL, then use GitHub CLI's credential helper under the dedicated directory:

   ```bash
   git remote set-url --push origin https://github.com/creative-graphic-design/<repo>
   GH_CONFIG_DIR="$HOME/.config/gh-cgd" git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push
   ```

The identity and permission checks above verify the account before writes. The Git credential helper reads from the same dedicated configuration directory.

## Scope

- This skill applies only to creative-graphic-design organization repositories on github.com. Do not use the stored bot credential or the bot commit identity for other hosts, organizations, or personal repositories; use normal authentication and the normal git identity there.
- Attribute every coding-agent write to a creative-graphic-design organization repository to the bot. This includes commits, pushes, PR creation and updates, PR replies, issue comments, labels, milestones, and user-requested merges.
- If any Setup verification fails, abandon the bot identity entirely: do not apply it partially, such as setting the bot commit author while the credential check failed or pushing through another account. Stop and report instead.
- The human (`shunk031`) approves PRs in GitHub's UI. Approval is the merge decision for that PR, and it stays valid after later head changes under the merge-approval rule in Authority Boundaries of the user-level `AGENTS.md`. Do not approve PRs as the bot.

## Troubleshooting

- If the dedicated GitHub CLI credential is unavailable or GitHub rejects it, the user must log in again.
  Run `GH_CONFIG_DIR=$HOME/.config/gh-cgd gh auth login` interactively and authenticate as `creative-graphic-design-dev`.
- If the identity check succeeds but repository permission is `false`, grant `creative-graphic-design-dev` access to the target repository before retrying. Reauthentication is unnecessary when only repository membership changes.
