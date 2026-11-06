---
name: shunk031-agy-japanese
description: Use this skill whenever you prepare Japanese PR or issue bodies or comments, Markdown documents, report bodies, posts, or Japanese strings in code or HTML. It routes writing and mandatory review through separate agy agents in Herdr panes. Do not use it for chat replies or English deliverables.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🖋️ I read shunk031-agy-japanese.`

# Japanese deliverables with agy

Use this procedure only for Japanese deliverables: PR and issue bodies and comments, Markdown documents, report bodies, posts, and Japanese strings in code or HTML. It does not apply to chat replies. Keep English out of scope and decide whether to add it after one week of Japanese-only use.

## Write

1. Gather the source materials and target file path in the deliverable's workspace. Give the writer the facts, numbers, links, code, outline, or draft that it needs; do not ask it to invent missing information.
2. Start agy in a Herdr pane in that workspace, using a unique agent name and the required model:

   ```bash
   herdr pane split --current --direction right --cwd "$PWD" --no-focus
   herdr agent start <writer-name> --kind agy --pane <writer-pane-id> -- --model gemini-4-argon-high
   ```

3. Give agy the materials and target path. Have it write the Japanese deliverable to that file; it may ask questions when needed information is missing. Claude, Codex, and Gemini callers must not draft or rewrite the Japanese. For Japanese inside code or HTML, have the writer edit only the Japanese strings.

## Review

1. Start a new agy session in a separate Herdr pane in the same workspace. Never use the writer's session for review. Give the reviewer the source materials and target file path.

   ```bash
   herdr pane split --current --direction down --cwd "$PWD" --no-focus
   herdr agent start <reviewer-name> --kind agy --pane <reviewer-pane-id> -- --model gemini-4-argon-high
   ```

2. Ask the reviewer to judge the deliverable against the existing writing skills loaded from `~/.agents/skills` through `~/.gemini/config/skills.json`. It checks that facts, numbers, links, code, and `<!-- -->` placeholders match the materials; for code or HTML, it also checks that only Japanese strings changed. It must not request content absent from the materials or edit the file. Require `ACCEPT` or `REJECT` with findings.
3. On `REJECT`, send the findings and available source material to the writer for revision, then use another fresh reviewer session. Allow at most two reject-and-revise rounds. If the second review still rejects, stop and show the remaining findings to the user.
4. If agy is unavailable because it is not installed, unauthenticated, rate-limited, or offline, hold the deliverable and tell the user. Do not publish it without an `ACCEPT`.
5. After appending the acceptance record or holding the deliverable, close every writer and reviewer pane you opened with `herdr pane close <pane-id>`, including panes used for rejected review rounds. Never close panes you did not open.

## Record an acceptance

Only after a fresh reviewer returns `ACCEPT`, have that reviewer append one record line with this single shell command. Replace the file path with the absolute path to the accepted file:

```bash
(
  set -o pipefail
  FILE="/absolute/path/to/accepted-file"
  [[ -f "$FILE" && -r "$FILE" ]] || exit 1
  HASH="$(perl -0777 -e '$_ = <STDIN> // ""; s/\r\n/\n/g; s/\n*\z/\n/; print' < "$FILE" | shasum -a 256 | cut -d ' ' -f 1)" || exit 1
  [[ "$HASH" =~ ^[0-9a-f]{64}$ ]] || exit 1
  STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || exit 1
  mkdir -p "$HOME/.local/state/agy-japanese" || exit 1
  printf '%s\t%s\t%s\n' "$STAMP" "$HASH" "$FILE" >> "$HOME/.local/state/agy-japanese/accepted.tsv"
)
```

The per-user record file is `~/.local/state/agy-japanese/accepted.tsv`. Each tab-separated line contains the UTC timestamp, SHA-256, and accepted file path. Before hashing, normalize CRLF to LF, remove all trailing LF bytes, and add exactly one trailing LF. Use the accepted file's exact content for later `gh`, commit, or upload bodies; any edit requires a new review and record.
