# Design record: Herdr tab cleanup helper

## Target

Add `scripts/herdr-tab-cleanup.sh` to the public `shunk031-herdr-orchestrate-workers` skill. It reads local Herdr tab, pane, and agent inventories and prints a `close` or `keep` verdict with evidence for every tab. The default mode is read-only. `--apply` rechecks each candidate immediately before calling `herdr tab close`; unmerged completed worker tabs additionally require the operator's `--results-collected` attestation. The helper uses local Git and `gh` evidence and does not target saved machines.

## Removals

The helper closes eligible tabs only. It never removes a worktree or branch, so it does not run `git worktree remove` or `git branch -D`. Worktree deletion remains governed by the existing cleanup rules for a clean status, matching `headRefOid`, and reviewed ignored files.

## Retained elements and why

Tabs remain open when ownership, lifecycle, pane inventory, visible input, worktree, or pull request state cannot be proven. The helper keeps the caller's tab, focused tabs, and primary checkouts. It also keeps tabs with panes lacking a uniquely named agent, agents outside the caller's name prefix, and agents not in `done` or `exited`. Tabs with extra agent rows that do not map to panes also stay open. Any pane with occupied or unknown visible input stays open. A completed caller-owned worker tab can close after result collection is attested; a matching branch with a merged pull request can establish that collection. At least one tab remains in each workspace because closing its last tab may close the workspace. The helper is local-only because its Git and GitHub evidence is tied to the local worktree context.

## User-owned settings touched

The required `make setup` installed the repository's pre-commit hook. The helper changes no Herdr profile, machine setting, shell setting, or user configuration.
