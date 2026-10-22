---
name: shunk031-herdr-meta-orchestrate
description: Coordinate root Herdr orchestrators across the local server and enabled saved machines. Ask for their current work and progress, relay messages verbatim, and route task execution through workers. Use when one session oversees multiple Herdr orchestrators; use the herdr skill for a single-pane or single-agent task.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🪆 I read shunk031-herdr-meta-orchestrate.`

# Meta-orchestrate Herdr sessions

Use this skill to keep track of root orchestrators, ask what they are doing, pass user decisions to the right orchestrator, and report their replies without paraphrasing them.

## Find and ask root orchestrators

Read the herdr skill before using Herdr commands. List local agents with `herdr agent list`; list saved machine profiles with `herdr machine list --json`, then list agents on each enabled profile with `herdr --machine <label-or-id> agent list`.

Track root orchestrators whose worker names are prefixed by their agent name. Ask each root for its current task, progress, blockers, and any decision it needs from the user. Do not make a separate inventory of individual worktree workers.

If a remote agent list fails because its Herdr server does not support machine API forwarding, check `herdr machine status <label-or-id> --json` and the reported server version. Report that machine's inventory as unavailable; do not guess its agents or progress.

Before relaying a reply, verify it against a fresh read or transcript. An agent name can move to another pane when its session is resumed or opened elsewhere, so re-identify the live agent by pane ID and transcript instead of relying on a stale name.

## Relay exactly

Quote each orchestrator's reply unchanged and identify which orchestrator it came from. Pass the user's instruction to its owning orchestrator unchanged, together with the question the instruction answers. Keep any interpretation of your own separate and label it as such.

## Delegate task work

Handle inventory, status requests, message relays, coordination, and pane focus after the user's explicit yes yourself. For implementation, task operations, or commits, use your own name-prefixed workers through the shunk031-herdr-orchestrate-workers skill; do not perform that work yourself. Follow that skill's lifecycle and the shunk031-codex-worker-prompting skill when writing Codex task prompts. Keep model and credential choices in the referenced launch guidance, not in this public skill.

Carry every user authorization forward only to its stated targets and count. If a dispatch would affect more targets than the user approved, stop and report the mismatch before acting. Never restore, checkout, stash, reset, or discard uncommitted changes without the user's explicit permission for that target.

## Ask before focusing a pane

If a pane needs the user's eyes or input, ask, “Would you like me to focus it?” Wait for an explicit yes. Then focus only the identified workspace and tab with `herdr workspace focus` and `herdr tab focus`; if the target changes, ask again. Follow the herdr skill for pane controls and handling sensitive input.

Keep your own tab status under the shunk031-herdr-tab-status skill. The herdr skill owns CLI mechanics, IDs, pane control, and remote-machine safety; the shunk031-herdr-orchestrate-workers skill owns worker dispatch, lifecycle, and reports.
