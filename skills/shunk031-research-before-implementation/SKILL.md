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

## Research retry

When a research stage fails before producing sources because the host's web-research capability errors, returns `403 Forbidden: Selected provider is forbidden`, or returns no sources, the agent itself immediately reruns that stage with the command below; this isolated `gpt-5.5` / medium session is the retry, not an optional extra.

```bash
env -u HERDR_ENV -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID \
    codex --search --model gpt-5.5 \
    --config 'model_reasoning_effort="medium"' \
    --sandbox read-only --ask-for-approval never \
    exec --ephemeral --skip-git-repo-check -C /tmp \
    '<retry only the failed research stage and return direct sources>' </dev/null
```

Run the command at most 3 times in total for one stage; between attempts, switch the Gateway endpoint according to the environment's private Gateway guidance in `~/.agents/AGENTS-private.md` when that file exists (prod and dev launch forms live there), keeping the stage, question, and arguments otherwise unchanged. Accept an attempt only when its transcript shows web-search activity and its answer contains usable direct source URLs. Only after 3 failed command attempts, stop, report `BLOCKED` to the orchestrator with the exact research question, and do not substitute memory or local files for the missing stage.
