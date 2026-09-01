---
name: shunk031-research-structured-bullet-writing
description: Create or rewrite arbitrary-domain content as a structured bullet outline, also called 骨子箇条書き. Use when the user asks for 骨子を書いて, 箇条書きで論点整理, structured bullet outline, スライド風に箇条書き, or asks to turn supplied material into concise topic bullets with nested support. Do not use for simple shopping lists, task checklists, or requests that only format existing Markdown without changing structure.
---

# Structured Bullet Outline

Create Markdown outlines that carry an argument or explanation through top-level topic sentences and nested support. Support both new composition from supplied material and rewriting existing prose or notes.

## Output contract

- Output Markdown.
- Use headings only when they make the outline easier to scan.
- Start with 3 or 4 top-level bullet items when the material supports that shape.
- Make each top-level bullet a topic sentence for its local group, not a label. Taken together, the top-level bullets should summarize the whole piece.
- Add roughly 2 or 3 nested support bullets under a top-level item when the local group needs evidence, examples, causes, tradeoffs, or next actions.
- Keep one topic per local group. Split a crowded group rather than hiding two claims under one bullet.
- Add a local conclusion only when the reasoning needs one. Do not invent a closing bullet just to fill a pattern.

## Source fidelity

- Preserve source facts. Reorder, split, and compress, but do not add unsupported claims, facts, numbers, causal links, recommendations, or conclusions.
- Keep evidence and numbers close to the claim they support.
- Preserve every citation and source URL supplied in the input.
- Preserve an existing citation style. Normalize only otherwise bare URLs to Markdown links.
- Place each citation immediately after the smallest textual unit it supports. For a cited term or entity, write `- 対象A [出典] は ...`; for a cited number or clause, put `[出典]` immediately after that number or clause; for multiple supported items, attach each source to its own item; for a whole bullet supported by one source, and only then, place the citation at the bullet end.
- Use footnotes only when a long URL or source note would disrupt the bullet, and keep the note directly under the relevant block.
- Use standalone reference bullets only when the user asks for a references section or bibliographic detail must be preserved.
- Use only user-supplied sources unless the user explicitly asks for web research.
- Never invent, upgrade, or silently drop a source. If the output needs evidence that the supplied material lacks, state the gap instead of fabricating a citation.
- Distinguish source-backed claims from the writer's inference when both appear in the material. Label non-source-backed interpretation as `推論:` or `示唆:`.
- If the user asks for a conclusion that the material does not support, qualify the conclusion or state that the evidence is missing.
- Ask a question only when missing information would materially change the result. Otherwise, produce the best outline from the supplied material and mark gaps briefly.

## Wording

- Use concise, deck-derived wording where it reads naturally.
- Keep local bullets grammatically parallel when that improves scan speed.
- Prefer concrete verbs and plain nouns. Do not force noun endings, equal line lengths, sentence fragments, or slogan-like phrasing when clarity suffers.
- Do not copy deck-specific wording or reproduce source corpus excerpts.

## Provenance

This skill's structure is based on the public outline-writing article at https://shunk031.hatenablog.com/entry/lets-write-outline. Its style constraints are informed by the public Speaker Deck corpus at https://speakerdeck.com/shunk031, cited as provenance only. Do not reproduce the corpus or large excerpts from it.
