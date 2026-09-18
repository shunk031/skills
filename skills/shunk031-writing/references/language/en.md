# English

Run the `unslop` skill as the language pass. Define a technical term in plain English at first use, followed by its abbreviation or specialized name when the reader will need it later. Expand abbreviations at first use unless they are universally understood tokens such as URL, JSON, HTTP, PDF, API, CLI, README, and DOI, or are proper names and brands such as JSTOR, arXiv, and GitHub.

## Cite works and link resources

Use footnotes for published works and descriptive inline Markdown links for resources. Attach a GitHub-flavored footnote marker such as `[^n]` directly after the named work at first mention and at any later load-bearing mention. Define the marker with the authors or organization, title, venue, year, and a DOI, arXiv, or ACL URL. Link repositories, code and data files, documentation, dataset cards, and licenses inline; a named entity may carry both a footnote marker and a nearby resource link. Leave a URL bare only when its literal string is what readers must copy or type, such as in a command, an endpoint, or a DOI identifier in a bibliography entry.

Keep citation markers sparse but complete. Use one marker per cited entity per unit, where a unit is a paragraph, table row, or contiguous list. Re-mark an entity in a distant load-bearing section with the same number when needed. Give sibling entities that share one footnote a single group marker, ensure every cited entity has at least one marker somewhere, and do not add a `Paper:` entry that duplicates a marker already attached to the work in the same passage.

## Use lists and tables deliberately

Use bullets for separate decisions, claims, steps, or multi-word structure, with a lead-in grouping related items. For a short run of two to four briefly labeled links, name the shared entity once and use inline slash-separated links. For longer same-entity link runs or labels needing qualifiers, use a lead-in and a few sub-bullets, each with a category label and an inline link run. Do not put a single resource link on each line. Keep short atomic-token reference lists inline regardless of count. Summarize an enumeration with a source link only when the exact enumeration is not the claim; preserve exact schema keys and other load-bearing enumerations. Describe a procedure in prose with a descriptive source link when the reader is not executing it; reserve step lists for procedures the reader executes.

Use tables for atomic, comparable values. When a table cell must hold several entries, separate them with `<br>`. If a cell needs sentences or more than about two `<br>`-separated lines, move the content to per-item subsections or prose and keep at most a compact table of atomic-value summaries. Left-align text columns and right-align purely numeric columns. Keep fragment bullets free of trailing periods and punctuate sentence bullets. Keep each list internally consistent, and keep two-item enumerations in prose when a list adds no value.

## Make the document easy to scan

Open each major section with its takeaway. Use sentence-case headings without manual section numbers, and apply the 30-second-skim test: the headings, opening sentences, and tables should convey the answer and top caveats. Match the format to the content instead of forcing reasoning into bullets or enumerations into prose. Use bold lead-ins ending with a period for labeled prose groups, not colon pseudo-headers; keep colons for genuine lists and examples. Within a scope, omit an established name from child labels, cells after a row header, and sentences inside that entity's section. Keep only the differentiating part.

Expand abbreviations at first use unless they are universally understood tokens such as URL, JSON, HTTP, PDF, API, CLI, README, and DOI, or proper names and brands such as JSTOR, arXiv, and GitHub. Avoid pronoun subjects such as "It", "This", and "They" unless the referent is the immediately preceding subject and unambiguous; name the actor instead. Describe an artifact by its function, platform, support, or compatibility boundaries, not with self-assessed size or effort qualifiers such as "small", "thin", "simple", or "lightweight".

Keep evidence reader-facing. Do not leave bookkeeping labels or research-session narration in the artifact, such as `VERIFIED`, `HYPOTHESIS`, or `Unverified:`. Express uncertainty with plain-language hedges, retain caveats when the reader needs them, and give evaluative claims a criterion or a hedge.

Omit needless volatile external facts from durable prose. Prefer category statements with descriptive links to live sources, and anchor load-bearing volatile facts to repository artifacts or commit-pinned snapshots.

Use repo-relative paths for living in-repository references or commit-pinned URLs for snapshots. Turn bare in-repository file-path mentions into relative Markdown links computed from the mentioning file's location. Keep runtime or user-environment paths, ground-truth tokens, and copyable command paths as plain text. Never use branch-qualified URLs such as `blob/main`; a merged branch may disappear.

Owner-authored specimen: "The Landscape of Agentic Reinforcement Learning for LLMs: A Survey."

Source: https://speakerdeck.com/shunk031/the-landscape-of-agentic-reinforcement-learning-for-llms-a-survey

Style contract source: https://github.com/shunk031/agentic-cognitive-writing-process/blob/0db88f7/AGENTS.md
