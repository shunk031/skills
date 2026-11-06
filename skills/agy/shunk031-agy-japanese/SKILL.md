---
name: shunk031-agy-japanese
description: >-
  Use this skill whenever a Japanese deliverable is drafted, rewritten, translated,
  or reviewed for publication, including Markdown prose, comments, UI strings, and
  Japanese text embedded in code or HTML. It makes agy the writer and fresh-session
  reviewer, preserves protected facts, records exact ACCEPT hashes, and provides a
  gate command for hooks. Japanese chat replies to the user are out of scope.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `📝 I read shunk031-agy-japanese.`

# Japanese deliverable workflow

Use agy as the only author of Japanese wording and as the mandatory reviewer before a Japanese deliverable is posted, committed, or handed off. The calling agent prepares the facts, evidence, structure, code, and non-Japanese content; it does not write or locally polish Japanese wording. This applies to Codex, Claude, and Gemini on every machine where agy is available. Do not use this workflow for Japanese chat replies to the user.

The calling agent selects the existing writing skill through `shunk031-writing-router`. agy already loads `~/.agents/skills` through its configured skills file. Review against those loaded skills only: `natural-japanese`, `shunk031-writing-kosshi`, `shunk031-writing-telegraph`, `tanteki`, and `yomiyasu`. Do not invent additional Japanese style rules.

## Choose the input form

For prose-first Markdown, call `rewrite`. agy rewrites the entire text and may delete, merge, or reorder it. The script asks for plain Markdown, checks protected facts, and rejects a JSON object returned in place of the body before writing the candidate to stdout or the requested target file.

For Japanese strings inside source code or HTML, call `pairs`. agy returns JSON replacement pairs with `old` and `new` strings. The script applies a pair only when `old` occurs exactly once; it rejects missing, duplicate, repeated, or overlapping matches before writing any output.

## Required review procedure

1. The calling agent supplies the complete source text to the appropriate writer command and keeps the source material needed to verify its meaning.
2. The script runs agy with model `gemini-4-argon-high`, `--mode plan`, `--sandbox`, JSON output and schema, and a bounded `600s` print timeout. Each call uses a fresh temporary directory. The session-only settings deny `write_file(*)`, `command(*)`, `mcp(*)`, and `execute_url(*)`; agy returns text or JSON, and the script writes files. The script strips leading agy greeting and read-receipt lines.
3. After a prose rewrite, the script requires the original numbers, URLs, inline code, fenced code, and `<!-- ... -->` placeholders to remain identical. After `pairs`, it permits only the exact requested target strings to change inside code; numbers, URLs, placeholders, and all other inline and fenced code must remain identical. Any mismatch rejects the candidate.
4. The calling agent sends the complete candidate to `review`. The script starts a fresh agy session for this call; never continue or reuse the writer session as reviewer. The review returns JSON containing `decision` (`ACCEPT` or `REJECT`) and `findings`. HTML comments such as `<!-- table:cases -->` are intentional render-time placeholders; do not ask to expand them or request content absent from the supplied source.
5. On `ACCEPT`, the review command appends the SHA-256 of the exact accepted bytes, timestamp, and source path to the ACCEPT file. A one-byte change requires a fresh review. `REJECT` never records an ACCEPT hash.
6. Allow at most two `REJECT`-triggered rewrites. Review attempts are numbered 1 through 3: if attempt 1 rejects, rewrite and review attempt 2; if attempt 2 rejects, rewrite once more and run the final review at attempt 3. If attempt 3 rejects, stop, hold the deliverable, and show the remaining findings to the user.
7. If agy is unavailable, hold the deliverable and tell the user. Never publish unreviewed Japanese without the user's per-case approval.

## Commands

Use the installed skill script at `~/.agents/skills/shunk031-agy-japanese/scripts/agy-japanese`. Each command reads UTF-8 from stdin by default or from `--file PATH`; writer commands print to stdout by default or write through the script with `--output PATH`.

```bash
python3 ~/.agents/skills/shunk031-agy-japanese/scripts/agy-japanese rewrite --file draft.md --output candidate.md
python3 ~/.agents/skills/shunk031-agy-japanese/scripts/agy-japanese pairs --file source.html --output candidate.html
python3 ~/.agents/skills/shunk031-agy-japanese/scripts/agy-japanese review --file candidate.md --round 1
python3 ~/.agents/skills/shunk031-agy-japanese/scripts/agy-japanese gate --file candidate.md
```

The hook interface is `~/.agents/skills/shunk031-agy-japanese/scripts/agy-japanese gate`, with text on stdin or `--file PATH`. It exits 0 when the text has fewer than 20 hiragana or katakana characters or its exact SHA-256 is in the ACCEPT file. Otherwise it exits nonzero and names the `agy-japanese review` command. This interface is ready for a dotfiles hook to call; this skill does not install or wire that hook.

The gate's prose detector is the single `requires_review()` function in the script. This skill handles Japanese deliverables only.

## Per-user state

The script appends state under `${XDG_STATE_HOME:-~/.local/state}/shunk031-agy-japanese/`. `accepted.jsonl` has one JSON object per accepted text with `timestamp`, `path`, and `sha256`.

`calls.jsonl` has one JSON object per agy call: `timestamp`, `operation`, `duration_seconds`, and `outcome`. Operations are `rewrite`, `pairs`, and `review`; outcomes are `ok`, `accept`, `reject`, `auth`, `limit`, `timeout`, or `error`. Review entries also include a one-based `round`. Both files are append-only. The orchestrator can summarize `calls.jsonl` after one week of use.

## Failures

The writer and reviewer commands use distinct exit codes for agy failures: 20 for authentication, 21 for a request limit, 22 for timeout, and 23 for another agy error. An unreadable or corrupt ACCEPT file also exits 23 and tells the caller to hold the deliverable and tell the user. Script validation failures and rejected protected facts also exit nonzero; do not use their output as a deliverable.
