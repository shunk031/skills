# Clean up completed Herdr work

## Close collected worker panes

When launch reused the workspace's sole root pane, collection may close that workspace's last pane and close the workspace.

Once you have verified a result and will send the worker nothing more, run `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-worker-lifecycle.sh collect <worker-name>`. The helper closes only a recorded pane this orchestrator launched. It requires a settled agent and fresh safety checks. Before ending any turn in which you collected results, run its read-only `audit` command. This reports settled workers left uncollected and unrecorded live panes without closing them. Closing a pane never removes its worktree or branch.

### Preview and close worker tabs

After confirming its pull request merged, preview local tabs with `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-tab-cleanup.sh`.

For a finished worker tab with an unmerged pull request, include `--results-collected <tab-id>` in the preview command; otherwise the helper keeps it. To close reviewed tabs, pass each tab ID with `--apply --results-collected <tab-id>` and repeat the option for each tab.

The helper rechecks agent status and visible input immediately before closing. Tabs whose labels start with ⛔ stay open. The helper never removes worktrees or branches.

## Remove resources only after merge

Check each worker's reported URL with `gh pr view <url>` when revisiting the session, finishing other work, or asked to tidy up; do not poll. After merge, close the tab if it is still open. Remove the worktree and branch only when the worktree and each initialized submodule have no uncommitted changes and the worktree's local tip equals `headRefOid` or is an ancestor of it. Check ancestry with `git merge-base --is-ancestor <branch> <headRefOid>`; get `headRefOid` from `gh pr view <url> --json headRefOid`.

Before removing, run `git status --ignored --short` in the worktree and each initialized submodule. Ask the user before removing if any ignored result cannot be regenerated, such as training outputs, checkpoints, or evaluation records. Virtual environments, bytecode, and coverage files can be regenerated and do not block removal. If a submodule has commits or changes not on its remote, stop and report.

After all checks pass, resolve the worktree's git directory with `git -C <worktree> rev-parse --absolute-git-dir`. Before deinitializing each initialized submodule, record its actual git directory with `git -C <worktree>/<path> rev-parse --absolute-git-dir`; its configured name may differ from its checkout path. Run `git -C <worktree> submodule deinit -- <path>`. Remove only the recorded clone if it is under `<worktree-git-dir>/modules/`; never touch the main checkout's `.git/modules`. Then remove empty directories left under `<worktree-git-dir>/modules/` with `find <worktree-git-dir>/modules -depth -type d -empty -delete`. Run `git worktree remove <worktree>` without `--force`, then delete the local branch with `git branch -D <branch>`; after a squash merge, `git branch -d` may refuse if its upstream no longer exists.

If the worktree or any initialized submodule has uncommitted changes, or the worktree tip neither equals nor is an ancestor of `headRefOid`, leave the worktree in place and report. Touch only resources created through this protocol; leave unmerged, ⛔, and other people's tabs alone.
