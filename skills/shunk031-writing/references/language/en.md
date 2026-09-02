# English

Run the `unslop` skill as the language pass. Define a technical term in plain English at first use, followed by its abbreviation or specialized name when the reader will need it later. Expand abbreviations at first use unless they are universally understood tokens such as URL, JSON, HTTP, PDF, API, CLI, README, and DOI, or are proper names and brands such as JSTOR, arXiv, and GitHub.

## Cite works and link resources

Use footnotes for published works and inline links for resources. Attach a GitHub-flavored footnote marker such as `[^n]` directly after the named work at first mention and at any later load-bearing mention. Define the marker with the authors or organization, title, venue, year, and a DOI, arXiv, or ACL URL. Link repositories, code and data files, documentation, dataset cards, and licenses inline; a named entity may carry both a footnote marker and a nearby resource link.

Keep citation markers sparse but complete. Use one marker per cited entity per unit, where a unit is a paragraph, table row, or contiguous list. Give sibling entities that share one footnote a single group marker, ensure every cited entity has at least one marker somewhere, and do not add a `Paper:` entry that duplicates a marker already attached to the work in the same passage.

## Use lists and tables deliberately

Use bullets for separate decisions, steps, claims, or runs of labeled links, with a lead-in grouping related items. Keep short atomic-token reference lists inline regardless of count. Summarize an enumeration with a source link only when the exact enumeration is not the claim; preserve exact schema keys and other load-bearing enumerations. Put separate lines in table cells with `<br>`, left-align text columns, and right-align purely numeric columns.

Keep fragment bullets free of trailing periods and punctuate sentence bullets. Keep each list internally consistent, and keep two-item enumerations in prose when a list adds no value.

## Make the document easy to scan

Open each major section with its takeaway. Use sentence-case headings without manual section numbers, and apply the 30-second-skim test: the headings, opening sentences, and tables should convey the answer and top caveats. Match the format to the content instead of forcing reasoning into bullets or enumerations into prose.

Keep evidence reader-facing. Do not leave bookkeeping labels or research-session narration in the artifact, such as `VERIFIED`, `HYPOTHESIS`, or `Unverified:`. Express uncertainty with plain-language hedges, retain caveats when the reader needs them, and give evaluative claims a criterion or a hedge.

Use relative paths or commit-pinned URLs for in-repository references. Never use branch-qualified URLs such as `blob/main`; a merged branch may disappear.

Owner-authored specimen: "The Landscape of Agentic Reinforcement Learning for LLMs: A Survey."

Source: https://speakerdeck.com/shunk031/the-landscape-of-agentic-reinforcement-learning-for-llms-a-survey

Style contract source: https://github.com/shunk031/agentic-cognitive-writing/blob/8c8e9f0557e743969a32fddca718008c498c0fd8/AGENTS.md
