---
name: shunk031-github-agent-identity
description: Use for GitHub API writes by coding agents in shunk031-owned repositories, including PRs, issues, comments, reviews, labels and merges. Use the shunk031-agent-bot GitHub App user access token so operations are attributed to shunk031 with App attribution; never apply to creative-graphic-design repositories, which use their dedicated machine-user skill.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🤖 I read shunk031-github-agent-identity.`

# GitHub App Agent Identity

## Scope

Use this skill for GitHub API writes in `github.com/shunk031/*` repositories. The goal is to attribute writes to **shunk031** through the **shunk031-agent-bot** GitHub App, using a **user-to-server access token** (not an installation token or a separate machine user). GitHub may show an App badge, but does not guarantee the literal text `shunk031 with shunk031-agent-bot` on every UI surface.

**Do not use this skill for `creative-graphic-design/*`.** Those repositories use `shunk031-github-cgd-identity` and its separate machine-user workflow. For other organizations and hosts, follow their own identity policy.

## Before a write

1. Confirm the intended owner/repository and worktree using `git remote get-url origin` and `git status --short --branch`. Use `-R shunk031/<repo>` where appropriate to pin `gh` to the target.
2. Run `agent-github status` and require `GitHub user: shunk031`. The CLI validates the actual GitHub user through the API and remembers the Client ID used in Device Flow.
3. If it is not configured, ask the user to authorize the App once with `agent-github login --client-id <CLIENT_ID>`; do not switch the machine's selected `gh` account. Check App installation and permissions for the target repository before writing.

## API writes

Use `agent-github gh` for **every GitHub API write**, including creation or modification of PRs, issues, comments, reviews, labels, milestones, GraphQL mutations, and user-authorized merges. For example:

```bash
agent-github gh pr create -R shunk031/<repo> --fill
agent-github gh pr comment -R shunk031/<repo> 123 --body-file /tmp/comment.md
agent-github gh issue create -R shunk031/<repo> --title 'Title' --body-file /tmp/issue.md
agent-github gh api graphql -f query='mutation { ... }'
```

`agent-github gh` supplies and refreshes a GitHub App `ghu_` token only for that `gh` invocation; normal interactive `gh` authentication stays unchanged. Never print `agent-github token`, export a token for an entire agent session, call bare `gh` for a write, or use `gh auth switch`.

**Fail closed:** if the wrapper, App authorization, or repository permission fails, stop and report the error. Do not retry the write using a personal token, SSH account, `curl`, another GitHub API client, or an App installation token. This is an agent instruction, not a hard security boundary.

After each API write, read the resource back using `agent-github gh` and follow the existing PR/CI verification workflow. A `/user` API result of `shunk031` is not proof of the visible App badge; verify the GitHub UI on a separately authorized test write once during setup.

## Git commits and pushes

`git commit` and `git push` are **not GitHub API writes**. Preserve repository-local author, committer, signing, co-author, and push conventions. This skill does not alter Git credentials or claim that a Git push carries the App badge. If App-authenticated Git transport is required, design it explicitly rather than silently changing SSH or HTTPS settings.

## Troubleshooting

On expired or invalid App authorization, request a new `agent-github login --client-id <CLIENT_ID>` from the user. Never fall back to the user's personal GitHub identity.
