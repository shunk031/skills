---
name: shunk031-writing-tech-article
description: Use when planning, researching, briefing, or reviewing a technical article such as an engineering blog, Zenn post, or Advent Calendar entry. Follow the article method from reader and evidence research through structure, examples, Japanese prose handoff, and factual review. The Japanese writing skill remains responsible for producing and reviewing Japanese prose.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🔬 I read shunk031-writing-tech-article.`

# Technical article method

Follow this checklist-driven method from research through factual review. The orchestrator owns article framing, evidence preparation, structure, and quality checks. The Japanese writing skill owns Japanese prose and its single-reviewer workflow.

## Boundaries

- Use [`shunk031-research-before-implementation`](../../research/shunk031-research-before-implementation/) for general research that informs a non-trivial implementation or design. That skill establishes how to check external behavior before deciding; this skill owns the end-to-end method for researching, planning, and checking a technical article.
- Hand the prepared brief and evidence to [`shunk031-writing-gemini-japanese`](../shunk031-writing-gemini-japanese/) for Japanese drafting, editing, and the single factual review. Do not draft or edit Japanese prose yourself, add another reviewer, or create a second approval gate.
- Keep destination-specific publication rules with the destination. Use their official guidelines as input when relevant; do not treat one platform's conventions as universal article rules.

## Workflow

1. **Define reader and purpose.** Record reader role and prior knowledge, the gap to bridge, the promised outcome, dominant article type, scope, and exclusions. Choose the dominant Diátaxis need—tutorial, how-to, reference, or explanation—as a guide rather than a rigid category. See [Google's audience guidance](https://developers.google.com/tech-writing/one/audience) and [Diátaxis](https://diataxis.fr/).
2. **Research and position the article.** Read primary sources for consequential claims and relevant prior articles or alternatives. Record overlap, a useful contribution, search terms, sources read, and search limits. A bounded search that finds nothing does not prove that no prior work exists. Pin decisive source-code evidence to commit and line permalinks.
3. **Plan the structure.** Write a title that names the subject accurately. Make the opening state the payoff and prerequisites. Map each heading to a reader question and give each section one role. Make the conclusion answer the opening with limits and next steps. Keep sections within the promised scope. See [Google's document organization guidance](https://developers.google.com/tech-writing/two/large-docs) and the [Zenn community guideline](https://zenn.dev/guideline).
4. **Specify examples.** For each example, record purpose, prerequisites and versions, inputs, expected result, and what actually ran. Examples should be correct, minimal, understandable, and reusable; disclose unavailable or partial execution. See [Google's sample-code guidance](https://developers.google.com/tech-writing/two/sample-code).
5. **Check evidence, links, and attribution.** Keep a ledger for each consequential mechanism, default, guarantee, comparison, or number. Record claim, primary URL and location, version or date, status (`verified`, `inference`, or `unresolved`), and qualification. Make the source support the exact claim; use descriptive links and distinguish quotations from the author's contribution. See [Google's linking guidance](https://developers.google.com/style/cross-references) and the [Qiita article guideline](https://help.qiita.com/ja/articles/qiita-article-guideline).
6. **Hand off the brief.** Transfer the evidence packet to the orchestrator. Fill the Japanese writing skill's brief fields: reader, reader action or judgment, three to five directly supported requirements, exclusions, and structure. Fewer than three requirements are allowed only after the user agrees to omit a required point. Add article type, promise, positioning, title, and opening or conclusion intent when relevant. If a required claim lacks evidence, mark it unresolved and ask the user for a source or a decision to narrow or omit it. Do not update the brief or continue drafting until the user agrees.
7. **Check the returned draft and guide factual review.** Use the article-specific self-check and single-reviewer criteria in [the article checklist](references/article-checklist.md). The orchestrator checks scope and handoff fit; the factual reviewer checks substantive claims and reader misunderstandings under the Japanese writing skill's existing workflow.

## Packet contents

Return a concise packet with these sections. The orchestrator uses it to prepare the brief and carries the applicable evidence into the Japanese writing workflow.

- **Intent:** reader, prior knowledge, problem, gap, promised outcome, dominant article type, scope, and exclusions.
- **Positioning:** prior articles and alternatives read, overlap, contribution, search terms, and search limits.
- **Evidence ledger:** each consequential claim, primary URL and precise location, version or date, status, and qualification; include pinned commit and line permalinks for decisive code evidence.
- **Examples:** purpose, prerequisites, inputs, expected result, execution evidence, and limits.
- **Structure:** title and outline mapped to reader questions and supported claims; include opening and conclusion intent.
- **Review hints:** claim-to-source checks, comparison fairness, and likely misunderstandings.
- **Brief handoff:** the five brief fields the Japanese writing skill requires, with direct source support for each required point.

## References

- [Google Technical Writing One](https://developers.google.com/tech-writing/one/documents) covers audience, scope, and document purpose.
- [Google Technical Writing Two](https://developers.google.com/tech-writing/two/large-docs) covers large-document organization and sample code.
- [Microsoft's style and voice tips](https://learn.microsoft.com/en-us/style-guide/top-10-tips-style-voice) inform clarity and scannability.
- [Google developer documentation style](https://developers.google.com/style/highlights) informs clarity and scannability.
- Apply English style guidance to Japanese prose only where it remains appropriate.
- [Diátaxis explanation](https://diataxis.fr/explanation/) helps distinguish understanding-oriented articles from task-oriented or learning-oriented ones.
- The [Zenn community guideline](https://zenn.dev/guideline) and [Qiita article guideline](https://help.qiita.com/ja/articles/qiita-article-guideline) provide destination-specific guidance.
- [Martin Fowler's writing patterns](https://martinfowler.com/articles/writingPatterns.html) informs articles that explain a pattern's problem, context, tradeoffs, solution, and consequences.
