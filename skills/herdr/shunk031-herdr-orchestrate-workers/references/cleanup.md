# Clean up completed Herdr work

## Close collected worker panes

Close a worker's pane with `herdr pane close <pane-id>` as soon as you have collected and verified its result and will send it nothing more, not only after a merge; before ending a turn in which you collected results, close the pane of every worker whose result you collected unless you will still route it work. Closing a pane never removes its worktree or branch.

### Preview and close worker tabs

After collecting a worker result or confirming its pull request merged, preview local tabs with `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-tab-cleanup.sh`.

For a finished worker tab with an unmerged pull request, include `--results-collected <tab-id>` in the preview command; otherwise the helper keeps it. To close reviewed tabs, pass each tab ID with `--apply --results-collected <tab-id>` and repeat the option for each tab.

The helper rechecks agent status and visible input immediately before closing. Tabs whose labels start with ⛔ stay open. The helper never removes worktrees or branches.

## Remove resources only after merge

Check each worker's reported URL with `gh pr view <url>` when revisiting the session, finishing other work, or asked to tidy up; do not poll. After merge, close the tab if it is still open. Remove the worktree and branch only when the worktree and each initialized submodule have no uncommitted changes and the worktree's local tip equals `headRefOid` or is an ancestor of it. Check ancestry with `git merge-base --is-ancestor <branch> <headRefOid>`; get `headRefOid` from `gh pr view <url> --json headRefOid`.

Before removing, run `git status --ignored --short` in the worktree and each initialized submodule. Ask the user before removing if any ignored result cannot be regenerated, such as training outputs, checkpoints, or evaluation records. Virtual environments, bytecode, and coverage files can be regenerated and do not block removal. If a submodule has commits or changes not on its remote, stop and report.

After all checks pass, resolve the worktree's git directory with `git -C <worktree> rev-parse --absolute-git-dir`. For each initialized submodule, run `git -C <worktree> submodule deinit -- <path>`, then remove only `<worktree-git-dir>/modules/<path>`. Never touch the main checkout's `.git/modules`. Run `git worktree remove <worktree>` without `--force`, then delete the local branch with `git branch -D <branch>`; after a squash merge, `git branch -d` may refuse if its upstream no longer exists.

If the worktree or any initialized submodule has uncommitted changes, or the worktree tip neither equals nor is an ancestor of `headRefOid`, leave the worktree in place and report. Touch only resources created through this protocol; leave unmerged, ⛔, and other people's tabs alone.
