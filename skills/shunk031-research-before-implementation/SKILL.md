---
name: shunk031-research-before-implementation
description: Research current official web documentation and representative GitHub implementation code before designing or editing non-trivial work involving third-party tools, libraries, platforms, APIs, configuration formats, or version-dependent behavior. Use for implementation, migration, integration, and configuration tasks where local files or memory alone cannot establish current supported behavior.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🔎 I read shunk031-research-before-implementation.`

# Research Before Implementation

Treat research as a gate, not a recommendation. Before any design decision or file edit, complete these tool stages in order:

1. Use an available web-research capability for current official sources. Rely on the capability the current agent host actually exposes; do not assume a particular tool name or namespace. Inspect documentation, specifications, release notes, and recommended approaches from at least one relevant non-GitHub domain. When the project has a paper, read it for the behaviour you are about to measure: design intent and quantified results are routinely reported there and nowhere else, and a number the paper claims is a target to reproduce rather than a figure to discover.
2. Only after those results return, read the implementation — both what the project publishes and what it ships. Inspect representative code or configuration on `github.com`, not only repository descriptions. Then read the installed package itself, which frequently carries guidance that never reaches the documentation site: bundled skill or usage documents beside the code, the docstring of every function you intend to call, and the default value of every argument you do not intend to pass. A feature can be fully documented and still be inert unless a caller asks for it. In a Codex session, run the `github.com` part of this stage with the same command shown above, replacing its question with the stage-2 question.
3. Compare the documented behavior with the implementation you read. Resolve version, platform, and maintenance differences before choosing the design. Where the documentation describes a capability, confirm in the code what switches it on; a mechanism the project measures and reports may be inert under its own defaults.
4. Implement and verify the change based on that evidence.
5. In the final response, name and link the web sources and GitHub examples consulted and state how they affected the implementation. The final response must list at least one official non-GitHub URL and one representative GitHub URL, and explain how each source affected the implementation. The GitHub URL must point directly to implementation code or configuration, not only a README, release, or marketplace page.

## Research retry

If the research capability exits before producing sources because of a connection error, an HTTP 5xx response, or a stream disconnect, rerun it at most 3 times for one stage, following any applicable local launch guidance. Accept an attempt as soon as its answer contains at least one direct URL to a source it consulted; do not rerun for format, length, or wording reasons, and do not rerun when the answer states that the documentation does not specify something. After 3 failed attempts, stop, report `BLOCKED` to the orchestrator with the exact research question, and do not substitute memory or local files.
