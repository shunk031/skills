# Clean up completed Herdr work

## Close collected worker panes

Close a worker's pane with `herdr pane close <pane-id>` as soon as you have collected and verified its result and will send it nothing more, not only after a merge; before ending a turn in which you collected results, close the pane of every worker whose result you collected unless you will still route it work. Closing a pane never removes its worktree or branch.

### Preview and close worker tabs

After collecting a worker result or confirming its pull request merged, preview local tabs with `~/.agents/skills/shunk031-herdr-orchestrate-workers/scripts/herdr-tab-cleanup.sh`.

For a finished worker tab with an unmerged pull request, include `--results-collected <tab-id>` in the preview command; otherwise the helper keeps it. To close reviewed tabs, pass each tab ID with `--apply --results-collected <tab-id>` and repeat the option for each tab.

The helper rechecks agent status and visible input immediately before closing. Tabs whose labels start with ⛔ stay open. The helper never removes worktrees or branches.

## Remove resources only after merge

A worker's worktree and branch live exactly as long as its pull request: once the PR merges they are spent, so clean them up as soon as you notice — check each worker's reported URL with `gh pr view <url>` whenever you revisit the session, wrap up other work, or are asked to tidy up; never run a polling loop for it. Close the tab if it is still open, then remove the worktree and delete the branch only if the worktree has no uncommitted changes and its local branch tip, `git rev-parse <branch>`, equals the pull request's final head commit, `headRefOid` from `gh pr view <url> --json headRefOid`.

## Check uncommitted and ignored data

Before removing, list its ignored files with `git status --ignored --short`, because `git worktree remove` deletes them with the directory. If they include results that cannot be regenerated, such as training outputs, checkpoints, or evaluation records, leave the worktree in place and ask the user. Regenerable files such as virtual environments, bytecode, and coverage files do not block removal.

Remove the worktree with `git worktree remove <path>` and never pass `--force`. Delete the local branch with `git branch -D <branch>`, because after a squash merge `git branch -d` refuses the branch unless its upstream branch still exists.

If the worktree still holds uncommitted work or its tip differs, leave it in place and tell the user. Touch only resources created through this protocol; leave unmerged, ⛔, and other people's tabs alone.
