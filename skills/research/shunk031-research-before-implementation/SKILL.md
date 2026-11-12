---
name: shunk031-research-before-implementation
description: Use by default before implementing, designing or deciding the content of any non-trivial deliverable, even when you think you already know the answer. It covers third-party tool, API, platform, paper or upstream behavior that local files do not show, such as matching an upstream script, setting, default or protocol, or relying on what another tool does with your output. It also covers established methods, practices and document types, such as setting goals or OKRs, designing an evaluation or experiment, reviewing code, or writing a design doc or postmortem. Reads the official docs, paper, upstream code or authoritative guide first instead of guessing from memory or asking the user. Not for spelling or wording fixes, local refactors, mechanical edits whose result the request and local files fully determine, or sources already verified in the session.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🔎 I read shunk031-research-before-implementation.`

# Research before implementation

Use this skill before implementing, designing, or deciding the content of a non-trivial deliverable. That includes work that depends on third-party behavior and work that follows an established method, practice, or document type; do not rely on memory of how a tool behaves or how a method is done well. Skip the research workflow for spelling or wording fixes, local refactors, mechanical edits whose result the request and local files fully determine, and sources already verified in the session, unless the user asks for research.

1. Follow explicit research routing in applicable environment guidance, then check current official documentation, specifications, release notes, recommended approaches, or, for a method or practice, its originating or authoritative guide through an available web-research capability. Read the relevant source content, not only a URL or search-result title. Use a relevant non-GitHub source when one exists. Read a paper when its reported behavior is the thing being measured.
2. Inspect representative implementation code or configuration on GitHub, or representative worked examples for a method or document type, after the official sources. Read installed documentation and source only for the APIs, defaults, or entrypoints the task will use.
3. Compare the documented behavior or guidance with the implementation or examples. Resolve version, platform, maintenance, and activation differences before choosing the design.
4. Implement, design, or write from that evidence, and verify the result. Scale the depth of research and verification to the risk and number of affected callers.
5. Report the sources that changed the decision. Link at least one official non-GitHub source and one direct implementation or configuration file when both were consulted.

## Research retry

If the research capability exits before producing sources because of a transient connection error, an HTTP 5xx response, or a stream disconnect, retry that stage at most 3 total attempts. A provider restriction or denied tool, including a 403, is stable: do not retry it, change credentials, or bypass the restriction. If the host exposes another permitted retrieval path, use that path; a research subprocess is permitted only when explicitly configured by the applicable environment guidance. Do not substitute memory. Accept an attempt only after reading the source content and recording its direct URL; do not rerun for format, length, or wording reasons, and do not rerun when the answer states that the documentation does not specify something. If no permitted research path succeeds, stop and report `BLOCKED` with the exact question and the failed paths.
