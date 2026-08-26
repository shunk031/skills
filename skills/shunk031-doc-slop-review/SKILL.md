---
name: shunk031-doc-slop-review
description: Review reader-facing text with a two-tier slop review before publishing it. Use when writing or editing documentation, README or TRAINING files, issue bodies and comments, pull request bodies and descriptions, or status reports that another person will read. Runs deterministic checks and one blind model judge over the draft, quotes each problem, and produces a PASS or FAIL to attach to the publish report; an unavailable review is a failed gate, not a PASS.
---

# Document Slop Review

## 読了時の応答

- この skill を読んだら、`🧹 私は shunk031-doc-slop-review を読みました。` と応答する。

## The command

The script ships with this skill. Run it by its path relative to this skill's own directory, naming the kind of document you are reviewing:

```bash
uv run --python 3.14.6 --no-project python scripts/doc_slop_review.py \
  --profile repo-doc DRAFT.md
```

Give this command to the user when you report the work. Do not paraphrase it and do not ask the reader to reconstruct it from a description.

The script works from any working directory and needs no repository checkout.
`node` and `npx` must be available, and the first run downloads the pinned textlint packages.

## Which profile

`--profile` is required, because a check is only sound for the artifact it was written for. Choose by what the draft is, not by what it is about.

| Profile | Use it for | The reader it assumes |
| --- | --- | --- |
| `change` | Pull request bodies, issue bodies, change descriptions | A maintainer of the target repository, who knows its tools and conventions but not this change |
| `repo-doc` | `README.md`, `TRAINING.md`, `SKILL.md`, other repository documentation | Someone who has just arrived and needs to use what the document describes |
| `report-ja` | Japanese research reports, experiment notes, published HTML reports | A researcher reading it for the first time, with no project context |

The reader is what makes the difference. `main` is an undefined identifier to a stranger and shared vocabulary to a maintainer; `## Verification` is an uninformative heading in a research report and the expected form in a pull request body. Picking the wrong profile produces confident findings that are wrong for the document you actually have.

The `report-ja` checks are `shunk031-research-report-ja` expressed as pass/fail questions. That skill owns them: change the rules there first, then mirror them here.

## When to use

Run this before publishing any text a person will read: repository documentation, `README.md` and `TRAINING.md` style files, issue bodies and comments, pull request bodies, and status or completion reports.

Skip it for code-only changes, machine-readable data, and ordinary conversational replies. A commit message body is optional; review it when it carries the explanation a reader depends on.

## Flow

1. Write the draft to a file, or pipe it in. Do not publish first and review after.
2. Run the review on the draft with the command above.
3. Address every finding, or state why a finding does not apply. A finding you disagree with is answered in the report, not ignored silently.
4. Re-run until the complete two-tier review reports PASS, then attach that verdict to the publish report. A deterministic-only PASS (including `--skip-model`) is not a complete review and is not permission to publish.
5. Treat exit code `2` as a failed review that blocks publication. This includes a model-judge timeout, an unavailable judge, an invalid judge response, a missing reviewable draft, and textlint failing to load its rules. Stop and report the failure instead of publishing. Retry only when the review can be run again; two timeouts do not become a PASS.
6. Publish after a PASS, or only after an explicit user waiver. A waiver for a FAIL or an unavailable review must name the failed gate and record the user's reason in the same publish report; the worker must not infer or silently grant the waiver.

## What the skill ships

Everything the review needs sits in this skill's `scripts/` directory:

- `doc_slop_review.py` — the review itself.
- `codex_runner.py` — the isolated Codex call behind the model judge.
- `doc_slop_rubric.json` — the bilingual rubric the judge is given.
- `textlint.config.json` — the Markdown rules of the deterministic tier.

## More command shapes

Review a pull request body before creating or editing it:

```bash
gh pr view 123 --json body --jq .body | \
  uv run --python 3.14.6 --no-project python scripts/doc_slop_review.py \
    --profile change
```

Review only the prose a change adds:

```bash
git diff -- '*.md' | \
  uv run --python 3.14.6 --no-project python scripts/doc_slop_review.py \
    --profile repo-doc --diff
```

Useful flags: `--json` for machine-readable output, `--skip-model` for the deterministic tier alone when no model call is available. On a host without unprivileged user namespaces, export `DOC_SLOP_REVIEW_SANDBOX=danger-full-access` first.

Exit codes are `0` for PASS, `1` for FAIL, and `2` when the review could not run. A `2` is not a PASS; report it as a failed review.

## Reading the output

Each finding names its rubric category, quotes the offending text, explains the problem, and proposes a fix. Findings marked `regex` come from the deterministic tier; findings marked `model` come from the judge.

- A clean deterministic tier does not prove that every technical term, abbreviation, or unit is defined. Regex cannot know whether `24行` means lines, queries, or records, or whether `final` has been introduced. Manually inspect terminology and reader context even when the deterministic tier reports no findings; the Japanese vocabulary owner is `shunk031-ai-slop-checklist-ja`.

A model finding is discarded when its quoted excerpt does not appear in the document, which keeps the output specific. The report counts those in `discarded_model_findings`; a nonzero count means the judge saw something it could not quote, so read the draft again rather than treating it as noise.

YAML frontmatter is removed before either tier runs. It is machine-readable metadata, so a finding about it would be a finding about the wrong audience.

## A finding that is wrong for this artifact

A finding can be correct about the text and still wrong for the document. Asking a pull request body to open with a research question is the standard case: true of a report, false here.

Answer such a finding rather than applying it:

1. Confirm the profile matches the artifact. A finding that belongs to another artifact is usually the wrong profile, not a bad judge. Re-run with the right one.
2. If the profile is right and the finding still misreads the artifact, reject it in the report and say which convention of this artifact it contradicts. A rejection is recorded, not silent.
3. If the same wrong finding recurs across drafts of the same artifact, the profile is missing a convention. Fix the profile instead of rejecting the finding again; when the rule belongs to another skill, fix it there first.

Do not reshape a document to satisfy a finding that its own form contradicts. A pull request body that has become a research report has failed the reader the review exists to protect.

## Related skills

- `shunk031-research-report-ja` owns the `report-ja` profile's checks. That profile mechanizes its rules; change them there first.
- `shunk031-ai-slop-checklist-ja` owns the Japanese review criteria and the five-axis scoring. The rubric this script uses is derived from it; consult that skill for the detailed criteria and for manual Japanese review.
- `shunk031-structured-writing` owns how to compose and organize the text. Use it while drafting; use this skill to check the draft before publishing.
- `shunk031-humanizer-ja` owns rewriting Japanese prose once a problem is found.
