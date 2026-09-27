---
name: shunk031-research-before-implementation
description: Research current official documentation and representative implementation code before non-trivial work that depends on third-party tools, APIs, platforms, or versioned behavior.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🔎 I read shunk031-research-before-implementation.`

# Research before implementation

Use this skill when local files or stable knowledge cannot establish behavior that matters to the task. Skip the research workflow for self-contained edits and routine wording fixes unless the user asks for research.

1. Follow explicit research routing in applicable environment guidance, then check current official documentation, specifications, release notes, or recommended approaches through an available web-research capability. Read the relevant source content, not only a URL or search-result title. Use a relevant non-GitHub source when one exists. Read a paper when its reported behavior is the thing being measured.
2. Inspect representative implementation code or configuration on GitHub after the official sources. Read installed documentation and source only for the APIs, defaults, or entrypoints the task will use.
3. Compare the documented behavior with the implementation. Resolve version, platform, maintenance, and activation differences before choosing the design.
4. Implement and verify the change from that evidence. Scale the depth of research and verification to the risk and number of affected callers.
5. Report the sources that changed the decision. Link at least one official non-GitHub source and one direct implementation or configuration file when both were consulted.

## Research retry

If the research capability exits before producing sources because of a transient connection error, an HTTP 5xx response, or a stream disconnect, retry that stage at most 3 total attempts. A provider restriction or denied tool, including a 403, is stable: do not retry it, change credentials, or bypass the restriction. If the host exposes another permitted retrieval path, use that path; a research subprocess is permitted only when explicitly configured by the applicable environment guidance. Do not substitute memory. Accept an attempt only after reading the source content and recording its direct URL; do not rerun for format, length, or wording reasons, and do not rerun when the answer states that the documentation does not specify something. If no permitted research path succeeds, stop and report `BLOCKED` with the exact question and the failed paths.
