# Technical article checklist

Use this checklist to prepare the article brief and inspect the returned draft. The Japanese writing skill remains responsible for Japanese prose and its single factual review.

## Before prose

### Reader and purpose

- Name the reader by role and relevant prior knowledge. State the problem or knowledge gap and the outcome the article promises.
- Choose the dominant reader need: tutorial for guided learning, how-to for completing a task, reference for lookup, or explanation for understanding. Articles can combine needs; choose the one that should shape the structure. See [Diátaxis](https://diataxis.fr/), [tutorials](https://diataxis.fr/tutorials/), and [explanation](https://diataxis.fr/explanation/).
- State the scope, exclusions, and prerequisites that affect whether the promise is realistic. Google's [audience guidance](https://developers.google.com/tech-writing/one/audience) and [document guidance](https://developers.google.com/tech-writing/one/documents) emphasize audience, purpose, and scope.

### Research and positioning

- Read primary documentation, specifications, release notes, and source code that support consequential claims. Read relevant prior articles and alternatives instead of inferring their content from titles or snippets.
- Keep search terms, places searched, date, languages, prior work read, and access limits. Report only what the bounded search establishes; no result is not proof that no prior work exists.
- Compare like with like. Describe the overlap and possible contribution in terms of audience, problem, context, and approach. Avoid unsupported claims such as "first," "only," or "best."
- For pattern articles, compare the problem, context, forces, solution, and consequences. See [Martin Fowler's writing patterns](https://martinfowler.com/articles/writingPatterns.html).
- For each consequential mechanism, default, guarantee, comparison, or number, record the claim and its primary URL with a precise location.
- Also record its version or date, status (`verified`, `inference`, or `unresolved`), and qualification.
- Pin decisive source-code evidence to a commit permalink with line numbers. Record a documentation version or date when behavior can change; prefer versioned sources where available.
- Mark an unresolved required claim explicitly. Narrow it to what the evidence supports or ask the user for the missing source or decision. Do not invent evidence or silently remove a required point.

### Structure

- Write a title that accurately names the subject and does not promise a result the article cannot support.
- Make the opening state the reader payoff and any prerequisites. Answer the key reader questions early enough to orient them.
- Map each heading to a reader question and supported claims. Give each section one job, group related points, and order them so the reader can follow the explanation or task.
- Make the conclusion answer the opening promise. State material limits and useful next steps, and remove topics that do not serve the promised outcome.
- Use descriptive, parallel headings and a clear hierarchy. See [Google's organization guidance](https://developers.google.com/tech-writing/two/large-docs) and [heading guidance](https://developers.google.com/style/headings).

### Examples and code

- For each example, record purpose, prerequisites, environment and versions, inputs, expected result, and what actually ran.
- Check that code is correct, minimal, understandable, and reusable. Explain behavior that readers need to adapt it safely; avoid surrounding a small point with unrelated setup.
- State whether the example was run, where, and under what conditions. If execution was partial or unavailable, disclose the limit and do not describe an expected result as observed. See [Google's sample-code guidance](https://developers.google.com/tech-writing/two/sample-code) and the [Qiita article guideline](https://help.qiita.com/ja/articles/qiita-article-guideline).

### Links, citations, and attribution

- Link the exact source that supports a factual sentence or example. Check that the linked passage supports the same scope, version, and certainty as the sentence.
- Use descriptive link text that identifies the destination or purpose. Avoid links whose text merely says "here" or whose destination does not support the nearby claim. See [Google's link-text guidance](https://developers.google.com/style/link-text) and [cross-reference guidance](https://developers.google.com/style/cross-references).
- Identify quotations and attribute them to their source. Separate quoted material, sourced facts, and the author's analysis or contribution; a citation does not make another author's contribution the article's own.
- Follow the destination's publication guidance where it applies. The [Zenn guideline](https://zenn.dev/guideline) and [Qiita guideline](https://help.qiita.com/ja/articles/qiita-article-guideline) are context-specific, not universal style rules.

### Brief handoff

Give the orchestrator the evidence packet and these fields for the Japanese writing skill:

- Reader and the reader's intended action or judgment.
- Three to five directly supported requirements, with a source for each; group related facts when necessary.
- Exclusions and the article structure. Include the dominant article type, promised outcome, positioning, title, and opening or conclusion intent when relevant.
- The evidence ledger and example conditions so the writer can preserve versions, qualifications, and execution limits.

## After prose

### Orchestrator self-check

Check workflow and requested scope without independently reviewing article facts or rereading the draft to find content issues:

- Confirm the Japanese writing skill received the working brief, evidence packet, and intended output path.
- Confirm the returned deliverable matches the requested format and scope at a high level. Route any scope change or dropped required point through the existing user decision process.
- Confirm the final draft received the single factual review required by the Japanese writing skill, and that any blocking findings were returned to the writer for correction.
- Check the required machine validation results. Leave factual accuracy, source support, comparison fairness, and reader misunderstandings to the factual reviewer.

This self-check tracks handoff and completion. It does not add a content-review pass or approval gate.

### Single factual reviewer

Give the existing factual reviewer the brief, draft, and evidence packet. Ask the reviewer to:

- Check consequential claims against the cited primary source, including the exact location, version or date, conditions, and qualification.
- Identify comparisons that use unlike criteria, omit a relevant limitation, or overstate what the alternatives establish.
- Point to concrete wording likely to make a reader misunderstand a mechanism, guarantee, number, example result, or boundary.
- Describe each blocking finding with the affected passage and why it is a substantive factual error or a concrete reader misunderstanding.

Follow the Japanese writing skill's review contract. Do not add a second reviewer or an extra approval gate; unsupported evidence without a demonstrated factual error remains subject to that skill's existing criteria.
