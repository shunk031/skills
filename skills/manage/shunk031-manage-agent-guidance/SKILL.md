---
name: shunk031-manage-agent-guidance
description: Organize persistent coding-agent guidance by scope and source of truth. Use when creating, converting, reviewing, or reorganizing AGENTS.md, CLAUDE.md, custom-agent wrappers, or repo-local skills, or when preventing duplicated guidance across tools.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🧭 I read shunk031-manage-agent-guidance.`

# Manage Agent Guidance

Keep each durable instruction in one source of truth and expose it through thin adapters.

## Workflow

1. Read the applicable guidance before proposing a change.
2. Classify the requested rule as user-level, repository-level, subtree-level, task-only, custom-agent, or skill guidance. Treat a filename named in the request as a hypothesis until higher-level instructions, managed sources, symlinks, imports, wrappers, and adapters confirm it.
3. Inspect the affected consumers and search for an existing owner. Build a consumer map when ownership or overlap is ambiguous; for a self-contained edit, record only the sources and readers that can be affected.
4. Edit one authoritative source. Put shared behavioral rules at user scope, repository procedures at repository scope, subtree rules at subtree scope, and reusable specialized procedures in an existing skill. Keep adapters thin and do not duplicate a rule merely because wording matches.
5. Before editing, state the evidence for scope, source of truth, existing ownership, and any unresolved consumer. Create a skill only when no existing owner fits and the procedure is substantial and reusable.
6. Review the final diff for scope mismatch, duplicate ownership, secrets, transient facts, and adapter drift. Run the actual gates of the affected repository; do not invent a hook, skip variable, or model gate.

Do not draft or edit until scope, source of truth, existing ownership, and affected consumers are confirmed. When evidence is unavailable, report the missing sources and propose the investigation instead of defaulting to the named file.

## Persistence Quality

- Persist only concise, actionable prevention that generalizes beyond the incident and states a reusable root-cause safeguard.
- Exclude secrets, task-specific facts, transient state, incident narratives, and unverified assumptions.
- Persistent guidance never references issue/PR numbers, migration tracking status, or other facts that expire. Guidance files are loaded indefinitely, but these facts have deadlines: the issue closes, the migration finishes, and the bare number becomes unresolvable outside its tracker — leaving future readers a rule they can neither verify nor act on. Record expiring facts in the issue tracker or a dated research note instead.

## Instruction migrations

For an actual move or removal, inspect the source and its machine-enforced owners, record each affected rule's source, destination, adapter, or approved removal with a rationale, and review the consumers after the change. Do not create migration records for a routine edit, and do not delete an unmapped or unapproved rule.

## Repository Validation

- Inspect the affected repository's current `Makefile`, pre-commit configuration, and CI before naming a gate.
- Run its documented static gates and preserve required ownership checks; do not assume a hook ID or skip variable from another repository.
- Run live model evaluation only when the task and repository explicitly require it. Do not replace a missing gate with a new framework.

## Repository Wiring

- Keep repository conventions in the root `AGENTS.md`; do not repeat user-level rules there.
- Make root `CLAUDE.md` a relative symlink to `AGENTS.md`, not a copied file or an import stub.
- Keep repo-local skills at `.agents/skills/<name>/SKILL.md` and expose them to Claude with a relative `.claude/skills` symlink when required.
- Keep lengthy shared custom-agent instructions in `~/.agents/agents/<name>.md`. Preserve tool-specific metadata in thin Claude or Codex wrappers that direct the agent to the shared source.
- Keep private infrastructure, credentials, internal endpoints, and environment-specific launch configuration out of public guidance.
- Do not introduce a Markdown parser or generator to duplicate shared instructions into TOML or Markdown until that mechanism is explicitly needed.
