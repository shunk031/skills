---
name: shunk031-codex-worker-prompting
description: Write task prompts and follow-ups for Codex-family workers with explicit scope, authorization, stop conditions, and verification.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🤖 I read shunk031-codex-worker-prompting.`

# Codex Worker Prompting

Write prompts that make worker decisions and stop conditions explicit.

**Premise.** Codex-family workers tend to over-engineer cross-cutting edits into bulk mechanical transforms such as `sed`, regex, or scripted rewrites, even when each occurrence requires individual judgment. When dispatching a judgment-bearing cross-cutting edit, explicitly forbid bulk find-and-replace and require editing one occurrence at a time with per-hunk diff review before committing.

**Skill paths.** When a dispatch relies on a skill, name each required skill with its readable path and say "read the file" when invocation is not intended. Do not rely on a worker guessing which skill applies, and omit unrelated skills from the dispatch.

**Premise.** When the user supplies a literal artifact—a format example, exact wording, a table, or a name—paste it into the dispatch unchanged and mark it as `verbatim`; never paraphrase it. A paraphrase silently drops load-bearing properties such as inline code formatting, punctuation, and casing, and the worker faithfully implements the degraded copy. Keep the user's original words and the orchestrator's interpretation visually separate so the worker can check against the source.

For public/private dotfiles or Codex configuration work, tell the worker to use the `shunk031-manage-public-private-dotfiles` skill. That skill requires reading `~/.agents/AGENTS-private.md` when it is readable, as well as the root `AGENTS.md` files in both dotfiles repositories. Refer to this stable private-instructions path instead of inventing a Codex-specific private `AGENTS.md`.

## Eight principles

1. **Write contracts, not vibes.** State machine-checkable acceptance and stop conditions when the task needs them. Use exact SHAs, commands, and pass/fail gates for stateful or high-risk work, and keep lightweight tasks lightweight. Have workers self-check against the gates and stop when a gate is impossible. Pair a gate with what it does not measure when that distinction affects the decision.
2. **Assume literal execution.** Expect every assertion to be executed as written, including mistakes. Add verification clauses such as read-backs, `ls-remote` comparisons, and precondition checks so workers halt on stale or wrong facts. State invariants explicitly, including numbers, claim strength, attribution, file scope, and section order; a literal executor treats every unstated property as mutable.
3. **Bound the loops, not the task count.** Let a dispatch carry a full lifecycle, but give every retryable step an explicit retry budget, wait duration, and terminal report state. For judgment tasks such as screening or review, state the decision rule, uncertain-case default, and cost asymmetry justifying that default. Encode authorization boundaries, including user-owned merges and destructive actions, as STOP conditions inside the prompt.
4. **Enumerate verified environment facts when relevant.** List only facts the task can hit, such as a proxy, push-URL pitfall, API field, sandbox variable, or auth fallback. Write unverified beliefs as hypotheses to verify and include the command that checks them. Repeat a standing authorization in each dispatch that can encounter it.
5. **Dispatch requirements and acceptance criteria, not implementations.** If you believe a tool or approach is unsuitable, state that belief as a hypothesis for worker verification and require research before implementation for tool choices. Workers execute solution framing literally and will build exactly the wrong thing well.
6. **Write the dispatch in the artifact's target register.** A worker mirrors dispatch vocabulary and constraints into deliverables. For reader-facing artifacts, keep internal codenames and audit constraints out of the prompt body, and state that compliance evidence belongs in the PR body, not the document.
   For a task whose deliverable is a reader-facing report, require the worker to read the `shunk031-writing-kosshi` skill first, then the `shunk031-writing-telegraph` skill, and apply both to the report body. Keep this requirement scoped to the report, not the dispatch or routine progress/final replies unless the user asks for that style.
7. **Fix the class, prove the sweep.** When a reviewer names defect instances, instruct the worker to remove the defect class. Require sweep evidence: an enumerate-and-classify table of every candidate, or a detector that reproduces the known-bad state before the fix and reports zero after it.
8. **Rotate on role and degradation, then on context.** Start a fresh session for every independent review verdict, retire sessions showing degraded output or anchoring to a failed approach, and rotate long-lived workers at natural boundaries before context runs out; a fixed remaining-context percentage is not a reliable trigger. When re-dispatching after a crash or rotation, enumerate on-disk state, including paths and whether each artifact is final, and state what must not be recomputed. Externalize handoff state in handoff documents and PR comments where repository policy allows; keep PR bodies reader-facing rather than a state ledger.

Transport mechanics such as dispatch delivery, report formats, and reconciliation belong to the `shunk031-herdr-orchestrate-workers` skill. This skill owns only prompt-writing guidance.
