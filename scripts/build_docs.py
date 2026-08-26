#!/usr/bin/env python3
"""Generate the documentation site's pages from the skills in this repository.

The site is generated rather than written because the source of truth is the
skill directory: its `SKILL.md`, whether it ships evals, and what those evals
measured. Hand-maintaining a second copy of that would drift.

Each skill gets a page carrying its frontmatter as a summary, its measured
effect when `evals/results.json` exists, and its `SKILL.md` body. The index
carries the table, which is the part that does not exist anywhere else: what
each skill changes, measured, in one view.

Usage:
    scripts/build_docs.py [--output docs]
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
SKILLS_ROOT = REPO_ROOT / "skills"

# Hand-written assets. `docs/` is generated and gitignored, so anything meant to
# be edited by a person lives here and is copied in.
ASSETS_ROOT = REPO_ROOT / "assets"
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)

# Every skill directory is prefixed with the owner. In the sidebar that prefix
# is on every entry, so it distinguishes nothing and costs the width that would
# otherwise show the part that differs.
NAME_PREFIX = "shunk031-"

# A page's icon in the navigation, from the Lucide set Zensical bundles. A skill
# with no entry here falls back to FALLBACK_ICON, which is correct rather than
# missing: an unfamiliar icon is worse than a consistent generic one.
FALLBACK_ICON = "lucide/file-text"
ICONS = {
    "shunk031-cgd-dev-identity": "lucide/id-card",
    "shunk031-codex-worker-prompting": "lucide/message-square-code",
    "shunk031-gh-comment-attach-files": "lucide/paperclip",
    "shunk031-herdr-tab-status": "lucide/tags",
    "shunk031-high-impact-journal-publishing": "lucide/graduation-cap",
    "shunk031-manage-agent-guidance": "lucide/book-marked",
    "shunk031-manage-public-private-dotfiles": "lucide/folder-git-2",
    "shunk031-manage-public-private-skills": "lucide/split",
    "shunk031-orchestrate-herdr-workers": "lucide/network",
    "shunk031-python-uv-workflow": "lucide/package-open",
    "shunk031-research-before-implementation": "lucide/search-check",
    "shunk031-shdoc-shell-docs": "lucide/square-terminal",
    "shunk031-transformers-convert": "lucide/repeat",
}


def meta_description(description: str) -> str:
    """Shorten a skill description to its first sentence for the meta tag.

    A skill's description is written for an agent deciding whether to load it,
    so it enumerates every triggering condition and runs several hundred
    characters. Search engines and link previews cut that off mid-clause. The
    first sentence says what the skill is, which is what a reader needs.
    """
    head = description.split(". ", 1)[0].strip()
    return head if head.endswith(".") else f"{head}."


def reference_title(stem: str) -> str:
    """Title a reference file from its name, keeping known initialisms upright."""
    words = stem.replace("_", "-").split("-")
    upper = {"ja", "ai", "uv", "cli", "api", "pr", "gh"}
    return " ".join(word.upper() if word.lower() in upper else word.capitalize() for word in words)


# Tags shown on each skill page. They name what a skill is actually about — the
# tool, the language, the subject — rather than sorting skills into a few broad
# buckets, which is what the alphabetical sidebar already does. Zensical does
# not build tag index pages yet, so these are labels rather than navigation.
TAGS = {
    "shunk031-cgd-dev-identity": ["GitHub", "Git"],
    "shunk031-codex-worker-prompting": ["Codex", "Agents", "Herdr"],
    "shunk031-gh-comment-attach-files": ["GitHub"],
    "shunk031-herdr-tab-status": ["Herdr", "Agents"],
    "shunk031-high-impact-journal-publishing": ["Research", "Writing"],
    "shunk031-manage-agent-guidance": ["Agents", "Claude Code", "Codex"],
    "shunk031-manage-public-private-dotfiles": ["chezmoi", "Dotfiles", "Git"],
    "shunk031-manage-public-private-skills": ["Agents", "Skills", "Evaluation"],
    "shunk031-orchestrate-herdr-workers": ["Herdr", "Codex", "Agents", "Git"],
    "shunk031-python-uv-workflow": ["Python", "uv"],
    "shunk031-research-before-implementation": ["Research"],
    "shunk031-shdoc-shell-docs": ["Shell", "Writing"],
    "shunk031-transformers-convert": ["Python", "PyTorch", "Transformers"],
}


def yaml_quote(value: str) -> str:
    """Quote a scalar for YAML frontmatter."""
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def frontmatter(tags: list[str] | None = None, **fields: str) -> list[str]:
    """Render a Zensical frontmatter block, skipping empty values."""
    lines = ["---"]
    lines += [f"{key}: {yaml_quote(value)}" for key, value in fields.items() if value]
    if tags:
        lines.append("tags:")
        lines += [f"  - {yaml_quote(tag)}" for tag in tags]
    lines += ["---", ""]
    return lines


def read_skill(skill_dir: Path) -> dict[str, Any] | None:
    """Collect one skill's published facts, or ``None`` if it has no SKILL.md."""
    source = skill_dir / "SKILL.md"
    if not source.is_file():
        return None

    text = source.read_text()
    match = FRONTMATTER.match(text)
    body = text[match.end() :] if match else text
    fields = {}
    if match:
        for line in match.group(1).splitlines():
            key, separator, value = line.partition(":")
            if separator:
                fields[key.strip()] = value.strip().strip("\"'")

    references = sorted((skill_dir / "references").glob("*.md")) if (skill_dir / "references").is_dir() else []

    results_path = skill_dir / "evals" / "results.json"
    results = json.loads(results_path.read_text()) if results_path.is_file() else None

    return {
        "name": skill_dir.name,
        "short_name": skill_dir.name.removeprefix(NAME_PREFIX),
        "title": fields.get("name", skill_dir.name),
        "description": fields.get("description", ""),
        "body": body.strip(),
        "has_evals": (skill_dir / "evals" / "evals.json").is_file(),
        "has_triggers": (skill_dir / "evals" / "triggers.json").is_file(),
        "references": references,
        "results": results,
    }


def percent(value: Any) -> str:
    """Render a 0..1 rate as a percentage, or an em dash when absent."""
    if not isinstance(value, (int, float)):
        return "—"
    return f"{value * 100:.0f}%"


def effect_row(skill: dict[str, Any]) -> str:
    """Render one skill's row for the index table."""
    results = skill["results"]
    link = f"[`{skill['short_name']}`]({skill['name']}/index.md)"
    if not results:
        measured = "not measured"
        return f"| {link} | — | — | {measured} |"

    with_rate = results.get("pass_rate", {}).get("with_skill")
    without_rate = results.get("pass_rate", {}).get("without_skill")
    if isinstance(with_rate, (int, float)) and isinstance(without_rate, (int, float)):
        delta = with_rate - without_rate
        measured = (
            "no measurable difference"
            if abs(delta) < 0.005
            else f"{delta * 100:+.0f} points"
        )
    else:
        measured = "—"
    return f"| {link} | {percent(with_rate)} | {percent(without_rate)} | {measured} |"


def render_skill_page(skill: dict[str, Any]) -> str:
    """Render one skill's page."""
    lines = frontmatter(
        # The sidebar shows the name without the owner prefix; the heading keeps
        # the full name, because that is the string you install and reference.
        title=skill["short_name"],
        description=meta_description(skill["description"]),
        icon=ICONS.get(skill["name"], FALLBACK_ICON),
        tags=TAGS.get(skill["name"]),
    )
    lines += [f"# `{skill['name']}`", "", skill["description"], ""]

    results = skill["results"]
    if results:
        lines += [
            "## Measured effect",
            "",
            f"Evaluated with `{results.get('model')}` at `{results.get('reasoning_effort')}` "
            f"reasoning over {results.get('trials')} trials, offline, on "
            f"{str(results.get('measured_at', ''))[:10]}.",
            "",
            "| | With the skill | Without it |",
            "| --- | --- | --- |",
            f"| Assertions passed | {percent(results.get('pass_rate', {}).get('with_skill'))} "
            f"| {percent(results.get('pass_rate', {}).get('without_skill'))} |",
            "",
        ]

        assertions = results.get("assertions") or []
        if assertions:
            lines += [
                "<details><summary>Per-assertion results</summary>",
                "",
                "| Case | Assertion | With | Without |",
                "| --- | --- | --- | --- |",
            ]
            for entry in assertions:
                assertion = str(entry.get("assertion", "")).replace("|", "\\|")
                lines.append(
                    f"| `{entry.get('case_id')}` | {assertion} "
                    f"| {percent(entry.get('with_skill'))} | {percent(entry.get('without_skill'))} |"
                )
            lines += ["", "</details>", ""]
    elif skill["has_evals"]:
        lines += ["No evaluation has been recorded for this skill yet.", ""]
    else:
        lines += [
            "This skill ships no evaluation cases, so its effect is unmeasured.",
            "",
        ]

    # The body is a quoted artifact, not this page's prose: it is written for
    # an agent deciding what to do, and it appears here verbatim. Wrapping it in
    # a card draws that line, so a reader can see where the page stops talking
    # and the skill starts.
    # The body opens with its own `# Title`, which lands at the top of the card
    # as a bare heading. The same icon the navigation uses goes in front of it,
    # so the card reads as this skill's card rather than as a second H1.
    # `/` becomes `-` in an icon shortcode.
    # The card title is bold text, not a heading, which is what the theme's
    # card is built around: its own example titles a card with `__Bold__`
    # followed by `---`. A heading here fights every margin the theme sets —
    # `h1` alone carries 1.25em below it, which collapses with the rule's own
    # margin and swallows the space the rule sits in — and leaves the page with
    # two H1s and a table of contents that skips the body.
    #
    # So the body's own `# Title` becomes the card's title line, and its `##`
    # sections become the top level inside the card.
    icon = ICONS.get(skill["name"], FALLBACK_ICON).replace("/", "-")
    body = skill["body"]
    if body.startswith("# "):
        heading, _, rest = body.partition("\n")
        title = heading[2:].strip()
        body = f":{icon}:{{ .lg .middle }} __{title}__\n\n---\n{rest}"

    # `.card` is only styled as `.grid > .card`, so the wrapper has to be the
    # grid and the body its single child. One child is a one-card grid.
    lines += [
        "## The skill",
        "",
        '<div class="grid" markdown>',
        "",
        '<div class="card" markdown>',
        "",
        body,
        "",
        "</div>",
        "",
        "</div>",
        "",
    ]
    return "\n".join(lines)


def render_index(skills: list[dict[str, Any]]) -> str:
    """Render the index page, whose table is the site's reason to exist."""
    measured = [s for s in skills if s["results"]]
    lines = frontmatter(
        title="Overview",
        description=(
            "Coding-agent skills for Claude Code and Codex, with what each one "
            "measurably changes."
        ),
        icon="lucide/house",
    )
    lines += [
        "# Skills",
        "",
        "Coding-agent skills for Claude Code and Codex, installed with the "
        "[`skills`](https://github.com/vercel-labs/skills) CLI.",
        "",
        "```bash",
        "npx skills add shunk031/skills --skill <name> "
        "--agent claude-code --agent codex --global --yes",
        "```",
        "",
        "## What each skill changes",
        "",
        "Every skill that ships evaluation cases is measured the same way: the same task "
        "is run with the skill available and without it, and a judge grades both against "
        "the same written assertions. The columns below are the share of assertions that "
        "passed in each arm.",
        "",
        "A skill with no measurable difference is not a broken skill. It means the "
        "evaluated model already does that thing unprompted.",
        "",
        "| Skill | With | Without | Difference |",
        "| --- | --- | --- | --- |",
    ]
    lines += [effect_row(skill) for skill in skills]
    lines += [
        "",
        f"{len(measured)} of {len(skills)} skills carry a recorded evaluation.",
        "",
    ]
    return "\n".join(lines)


def render_nav(skills: list[dict[str, Any]]) -> str:
    """Render the navigation tree for mkdocs.yml to include.

    Without this, a section's label comes from its directory name, which turns
    `shunk031-python-uv-workflow` into "Shunk031 python uv workflow". A
    section is not a page, so no frontmatter can correct it — only an explicit
    entry can. Naming each section here also lets the section carry the skill's
    icon, and leaves the page inside it free to say what it is: `SKILL.md`.
    """
    lines = [
        "# Generated by scripts/build_docs.py. Do not edit.",
        "nav:",
        "  - Overview: index.md",
    ]
    for skill in skills:
        # The first child is a bare path, which makes it the section's index
        # page under `navigation.indexes`. That is what lets the section carry
        # the skill's icon: an icon comes from a page's frontmatter, and a nav
        # label is not rendered as Markdown, so a shortcode written here would
        # appear literally.
        lines.append(f"  - {skill['short_name']}:")
        lines.append(f"      - {skill['name']}/index.md")
        for reference in skill["references"]:
            title = reference_title(reference.stem)
            lines.append(f"      - {title}: {skill['name']}/references/{reference.name}")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", default="docs", help="directory to write pages into"
    )
    parser.add_argument(
        "--nav",
        default="docs/.nav.yml",
        help="file to write the generated navigation into",
    )
    args = parser.parse_args()

    output = (REPO_ROOT / args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)

    skills = []
    for skill_dir in sorted(SKILLS_ROOT.iterdir()):
        # Shuhari writes `<skill>-workspace/` beside the skill it evaluated.
        # Those are gitignored run artifacts, not skills.
        if not skill_dir.is_dir() or skill_dir.name.endswith("-workspace"):
            continue
        skill = read_skill(skill_dir)
        if skill:
            skills.append(skill)

    assets = sorted(ASSETS_ROOT.rglob("*")) if ASSETS_ROOT.is_dir() else []
    for asset in assets:
        if not asset.is_file():
            continue
        destination = output / asset.relative_to(ASSETS_ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(asset.read_text())

    (output / "index.md").write_text(render_index(skills) + "\n")
    pages = 1
    for skill in skills:
        # Each skill gets a directory, not a flat page. A skill body links to
        # its own `references/*.md` by relative path, and those links resolve
        # only if the page sits where the skill directory sits. Publishing the
        # references beside the page keeps every link in the body correct
        # without rewriting the body.
        page_dir = output / skill["name"]
        page_dir.mkdir(parents=True, exist_ok=True)
        (page_dir / "index.md").write_text(render_skill_page(skill) + "\n")
        pages += 1

        for reference in skill["references"]:
            destination = page_dir / "references" / reference.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            # A reference file carries no frontmatter of its own, so give it a
            # title. Without one the sidebar falls back to the first heading,
            # which several of these do not have.
            body = "\n".join(
                frontmatter(title=reference_title(reference.stem), icon="lucide/book-open")
            )
            destination.write_text(body + reference.read_text())
            pages += 1

    nav_path = (REPO_ROOT / args.nav).resolve()
    nav_path.parent.mkdir(parents=True, exist_ok=True)
    nav_path.write_text(render_nav(skills))

    print(f"wrote {pages} pages into {output.relative_to(REPO_ROOT)}/")
    print(f"wrote navigation into {nav_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
