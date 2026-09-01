---
name: shunk031-research-before-implementation
description: Research current official web documentation and representative GitHub implementation code before designing or editing non-trivial work involving third-party tools, libraries, platforms, APIs, configuration formats, or version-dependent behavior. Use for implementation, migration, integration, and configuration tasks where local files or memory alone cannot establish current supported behavior.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🔎 I read shunk031-research-before-implementation.`

# Research Before Implementation

Treat research as a gate, not a recommendation. Before any design decision or file edit, complete these tool stages in order:

1. Use an available web-research capability for current official sources. Rely on the capability the current agent host actually exposes; do not assume a particular tool name or namespace. Inspect documentation, specifications, release notes, and recommended approaches from at least one relevant non-GitHub domain.
2. Only after those results return, use a GitHub search or inspect `github.com` sources. Inspect representative implementation code or configuration and operational patterns, not only repository descriptions.
3. Compare the documented behavior with the GitHub examples. Resolve version, platform, and maintenance differences before choosing the design.
4. Implement and verify the change based on that evidence.
5. In the final response, name and link the web sources and GitHub examples consulted and state how they affected the implementation. The final response must list at least one official non-GitHub URL and one representative GitHub URL, and explain how each source affected the implementation. The GitHub URL must point directly to implementation code or configuration, not only a README, release, or marketplace page.

## Provider fallback

When a research stage returns exactly `403 Forbidden: Selected provider is forbidden`, retry that stage once in an isolated Codex session using `gpt-5.5`, medium reasoning, and live web search. Do not ask the user to approve this bounded retry.

Prefer an available native launcher that accepts the exact model, reasoning effort, and live-search settings. When the Codex CLI is available, use the equivalent of:

```bash
env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID \
    codex --search --model gpt-5.5 \
    --config 'model_reasoning_effort="medium"' \
    --sandbox read-only --ask-for-approval never \
    exec --ephemeral --skip-git-repo-check -C /tmp \
    '<retry only the failed research stage and return direct sources>'
```

Keep the child task read-only and limited to the failed research stage. Treat the retry as successful only when its transcript shows actual web-search activity and its response contains usable direct sources. Continue with the normal stage order using that evidence. If the fallback cannot start, does not search, returns no usable sources, or fails again, keep the research stage incomplete and diagnose the launcher or search failure in read-only mode. Retry only the failed stage after addressing the cause; do not switch models or proceed from memory.

Do not edit files until both research stages are complete. Do not substitute memory or local repository inspection for either external stage. For failures other than the exact provider-forbidden response, keep the affected research stage incomplete, diagnose the available search path, and retry that stage after addressing the cause. Continue read-only investigation and recovery without asking the user whether ordinary diagnostics should proceed. Continue with implementation only when the required research is satisfied or the task is explicitly re-scoped so this skill no longer applies.
