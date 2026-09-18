#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["markdown-it-py"]
# ///
"""Keep per-task writing evidence and gate publication."""

from __future__ import annotations

import argparse
from collections import Counter
from contextlib import contextmanager
import fcntl
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Iterator
import uuid

from markdown_it import MarkdownIt


CONTRACT_FIELDS = ("Reader", "Purpose", "Main point", "Depth", "Language", "Medium")
RESULT_STATUSES = ("no-findings", "findings", "changed", "unavailable", "failed")
REVIEWERS = (
    ("structure-reviewer", "verify-global.md"),
    ("prose-reviewer", "verify-local.md"),
)
REVIEW_INPUT_LIMIT = 50_000
REVIEW_CONTEXT_TOKENS = 32_768
MARKDOWN = MarkdownIt("commonmark")


def text_hash(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def file_hash(path: Path) -> str:
    return text_hash(path.read_text(encoding="utf-8"))


def contract_template() -> str:
    return """# Writing contract

Reader:
Purpose:
Main point:
Depth:
Language:
Medium:

## Sections

| Heading | Reader need | Intended share |
| --- | --- | --- |
"""


@contextmanager
def task_lock(task_dir: Path) -> Iterator[None]:
    with (task_dir / "state.lock").open("a", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock_file, fcntl.LOCK_UN)


def task_dir_for(draft: Path) -> Path:
    draft = draft.expanduser().resolve()
    if draft.name != "draft.md" or not draft.with_name("state.json").is_file():
        raise ValueError(f"not a writing task draft: {draft}")
    return draft.parent


def read_state(task_dir: Path) -> dict:
    return json.loads((task_dir / "state.json").read_text(encoding="utf-8"))


def write_state(task_dir: Path, state: dict) -> None:
    (task_dir / "state.json").write_text(
        json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def start_task(
    workspace: Path, source: str, destination: str = "", resume: str | None = None
) -> Path:
    workspace = workspace.expanduser().resolve()
    tasks_root = workspace / ".writing"
    tasks_root.mkdir(parents=True, exist_ok=True)
    source_digest = text_hash(source)

    if resume:
        task_dir = tasks_root / resume
        if not task_dir.is_dir():
            raise ValueError(f"unknown task ID: {resume}")
        with task_lock(task_dir):
            state = read_state(task_dir)
            if state["source_hash"] != source_digest:
                raise ValueError("resume source does not match the task")
            if state["destination"] != destination:
                raise ValueError("resume destination does not match the task")
        return (task_dir / "draft.md").resolve()

    while True:
        task_id = uuid.uuid4().hex
        task_dir = tasks_root / task_id
        try:
            task_dir.mkdir()
            break
        except FileExistsError:
            continue

    with task_lock(task_dir):
        (task_dir / "draft.md").write_text(source, encoding="utf-8")
        (task_dir / "contract.md").write_text(contract_template(), encoding="utf-8")
        write_state(
            task_dir,
            {
                "task_id": task_id,
                "workspace": str(workspace),
                "destination": destination,
                "source_text": source,
                "source_hash": source_digest,
                "findings": [],
                "results": {},
                "reviews": {},
            },
        )
    return (task_dir / "draft.md").resolve()


def markdown_blocks(text: str) -> list[str]:
    lines = text.splitlines()
    tokens = MARKDOWN.parse(text)
    list_ranges = [token.map for token in tokens if token.type == "list_item_open" and token.map]
    blocks: list[tuple[int, int, str]] = []
    for token in tokens:
        if not token.map:
            continue
        start, end = token.map
        if token.type == "list_item_open":
            blocks.append((start, end, " ".join("\n".join(lines[start:end]).split())))
        elif token.type in {"fence", "code_block"}:
            blocks.append((start, end, " ".join("\n".join(lines[start:end]).split())))
        elif token.type == "paragraph_open" and not any(
            list_start <= start and end <= list_end
            for list_start, list_end in list_ranges
        ):
            blocks.append((start, end, " ".join("\n".join(lines[start:end]).split())))
    return [block for _, _, block in sorted(blocks) if block]


def changed_blocks(source: str, draft: str) -> list[dict[str, str]]:
    draft_counts = Counter(markdown_blocks(draft))
    seen: Counter[str] = Counter()
    findings = []
    for block in markdown_blocks(source):
        seen[block] += 1
        if seen[block] <= draft_counts[block]:
            continue
        excerpt = block if len(block) <= 120 else f"{block[:117]}..."
        findings.append(
            {
                "location": "Reviewing: reading",
                "message": f"Source block changed or disappeared: {excerpt}",
                "evidence": block,
            }
        )
    return findings


def add_finding(
    draft: Path,
    source: str,
    location: str,
    message: str,
    evidence: str = "",
    finding_id: str | None = None,
) -> str:
    task_dir = task_dir_for(draft)
    with task_lock(task_dir):
        state = read_state(task_dir)
        current_hash = file_hash(draft)
        existing = next(
            (
                item
                for item in state["findings"]
                if (finding_id and item["id"] == finding_id)
                or (
                    item["source"] == source
                    and item["location"] == location
                    and item["message"] == message
                )
            ),
            None,
        )
        if existing:
            if existing["draft_hash"] != current_hash:
                existing.update(
                    draft_hash=current_hash,
                    location=location,
                    message=message,
                    evidence=evidence,
                    decision=None,
                    reason=None,
                    decision_context_hash=None,
                )
            write_state(task_dir, state)
            return existing["id"]

        next_number = max(
            (int(item["id"].split("-")[1]) for item in state["findings"]),
            default=0,
        ) + 1
        new_id = f"F-{next_number:04d}"
        state["findings"].append(
            {
                "id": new_id,
                "source": source,
                "draft_hash": current_hash,
                "location": location,
                "message": message,
                "decision": None,
                "reason": None,
                "evidence": evidence,
                "decision_context_hash": None,
            }
        )
        write_state(task_dir, state)
        return new_id


def context_hash(draft: Path) -> str:
    contract = draft.with_name("contract.md")
    return text_hash(
        draft.read_text(encoding="utf-8") + "\0" + contract.read_text(encoding="utf-8")
    )


def decide_finding(draft: Path, finding_id: str, decision: str, reason: str) -> None:
    task_dir = task_dir_for(draft)
    with task_lock(task_dir):
        state = read_state(task_dir)
        finding = next(
            (item for item in state["findings"] if item["id"] == finding_id), None
        )
        if finding is None:
            raise ValueError(f"unknown finding: {finding_id}")
        finding["decision"] = decision
        finding["reason"] = reason
        finding["decision_context_hash"] = context_hash(draft)
        write_state(task_dir, state)


def record_result(
    draft: Path, source: str, status: str, draft_hash: str, reason: str = ""
) -> None:
    if status not in RESULT_STATUSES:
        raise ValueError(f"unknown result status: {status}")
    current_hash = file_hash(draft)
    if draft_hash != current_hash:
        raise ValueError("result draft hash does not match the current draft")
    task_dir = task_dir_for(draft)
    with task_lock(task_dir):
        state = read_state(task_dir)
        state["results"][source] = {
            "status": status,
            "draft_hash": draft_hash,
            "reason": reason,
        }
        write_state(task_dir, state)


def contract_values(contract: Path) -> dict[str, str]:
    values = {}
    text = contract.read_text(encoding="utf-8")
    for field in CONTRACT_FIELDS:
        match = re.search(rf"(?m)^{re.escape(field)}:\s*(.*?)\s*$", text)
        values[field] = match.group(1) if match else ""
    return values


def required_sources(state: dict, contract: dict[str, str]) -> list[str]:
    sources = ["language", "sanitize"]
    if state["source_text"]:
        sources.append("changed-block-detection")
    sources.append("check")
    if contract["Depth"].lower() == "full":
        sources.extend(source for source, _ in REVIEWERS)
    return sources


def status_for(draft: Path) -> dict:
    task_dir = task_dir_for(draft)
    state = read_state(task_dir)
    values = contract_values(draft.with_name("contract.md"))
    missing_fields = [field for field, value in values.items() if not value]
    current_hash = file_hash(draft)
    required = required_sources(state, values)
    missing_sources = []
    degraded_sources = []
    for source in required:
        result = state["results"].get(source)
        if not result or result["draft_hash"] != current_hash:
            missing_sources.append(source)
        elif result["status"] == "failed":
            missing_sources.append(source)
        elif result["status"] == "unavailable":
            if source in {name for name, _ in REVIEWERS}:
                missing_sources.append(source)
            else:
                degraded_sources.append(source)

    current_context_hash = context_hash(draft)
    unresolved = []
    for finding in state["findings"]:
        answered = bool(finding["decision"] and finding["reason"])
        kept_is_current = not (
            finding["decision"] == "kept"
            and finding["decision_context_hash"] != current_context_hash
        )
        if not answered or not kept_is_current:
            unresolved.append(finding["id"])

    return {
        "ready": not missing_fields and not missing_sources and not unresolved,
        "draft_hash": current_hash,
        "missing_contract_fields": missing_fields,
        "missing_sources": missing_sources,
        "unresolved_findings": unresolved,
        "degraded_sources": degraded_sources,
    }


def publish_text(draft: Path) -> str:
    status = status_for(draft)
    if not status["ready"]:
        raise ValueError(f"task is not ready: {json.dumps(status, ensure_ascii=False)}")
    return draft.read_text(encoding="utf-8")


def extract_elements(text: str) -> dict[str, list[str]]:
    return {
        "number": re.findall(r"(?<![\w.])[+-]?\d[\d,]*(?:\.\d+)?%?(?!\w)", text),
        "URL": [url.rstrip(".,;:") for url in re.findall(r"https?://[^\s)>]+", text)],
        "quotation": re.findall(r'[“\"]([^”\"\n]+)[”\"]', text),
        "citation": re.findall(r"\([A-Z][^()\n]{0,80},\s*\d{4}[a-z]?\)|\[\d+\]", text),
    }


def outline_diagnostics(text: str) -> list[str]:
    lines = text.splitlines()
    output = ["Outline and paragraph openings:"]
    for token in MARKDOWN.parse(text):
        if token.type == "heading_open" and token.map:
            output.append(f"  heading: {lines[token.map[0]].lstrip('#').strip()}")
        elif token.type == "paragraph_open" and token.map:
            paragraph = " ".join(lines[token.map[0] : token.map[1]]).strip()
            opening = re.split(r"(?<=[.!?。！？])\s+", paragraph, maxsplit=1)[0]
            sentence_count = len(
                [part for part in re.split(r"[.!?。！？]+", paragraph) if part.strip()]
            )
            output.append(f"  paragraph ({sentence_count} sentences): {opening}")
    return output


def visible_character_count(markdown: str) -> int:
    markdown = re.sub(r"\A---\n.*?\n---\n", "", markdown, count=1, flags=re.DOTALL)
    markdown = re.sub(r"<!--.*?-->", "", markdown, flags=re.DOTALL)
    rendered = MARKDOWN.render(markdown)
    visible = html.unescape(re.sub(r"<[^>]+>", "", rendered))
    return len(re.sub(r"\s", "", visible))


def share_diagnostics(draft: Path) -> list[str]:
    contract = draft.with_name("contract.md").read_text(encoding="utf-8")
    intended = {}
    for line in contract.splitlines():
        if not line.startswith("|") or "---" in line:
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) >= 3 and cells[0] != "Heading" and cells[2]:
            intended[cells[0]] = cells[2]
    if not intended:
        return []

    text = draft.read_text(encoding="utf-8")
    lines = text.splitlines()
    headings = [
        (token.map[0], lines[token.map[0]].lstrip("#").strip())
        for token in MARKDOWN.parse(text)
        if token.type == "heading_open" and token.map
    ]
    sections = []
    if headings:
        for index, (start, heading) in enumerate(headings):
            end = headings[index + 1][0] if index + 1 < len(headings) else len(lines)
            sections.append((heading, "\n".join(lines[start:end])))
    else:
        sections.append(("(whole document)", text))
    counts = [(heading, visible_character_count(body)) for heading, body in sections]
    total = sum(count for _, count in counts)
    output = ["Intended and actual visible-character shares:"]
    for heading, count in counts:
        if heading in intended:
            actual = f"{count / total:.0%}" if total else "0%"
            output.append(f"  {heading}: intended {intended[heading]}, actual {actual}")
    return output


def run_check(draft: Path) -> None:
    task_dir = task_dir_for(draft)
    state = read_state(task_dir)
    current = draft.read_text(encoding="utf-8")
    findings = []
    source_elements = extract_elements(state["source_text"])
    draft_elements = extract_elements(current)
    for kind, source_values in source_elements.items():
        remaining = Counter(draft_elements[kind])
        for value in source_values:
            if remaining[value]:
                remaining[value] -= 1
            else:
                findings.append(
                    (
                        "Reviewing: editing",
                        f"Source {kind} changed or disappeared: {value}",
                        value,
                    )
                )

    textlint = shutil.which("textlint")
    unavailable = not textlint
    if textlint:
        config = Path(__file__).with_name("textlint.config.json")
        result = subprocess.run(
            [textlint, "--config", str(config), str(draft)],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            message = (result.stdout or result.stderr).strip()
            findings.append(("Reviewing: editing", f"textlint: {message[:1000]}", message))

    for location, message, evidence in findings:
        add_finding(draft, "check", location, message, evidence)
    record_result(
        draft,
        "check",
        "unavailable" if unavailable else ("findings" if findings else "no-findings"),
        file_hash(draft),
        "Install textlint and rerun check." if unavailable else "",
    )
    print("\n".join(outline_diagnostics(current) + share_diagnostics(draft)))
    if unavailable:
        print("textlint: unavailable; install textlint and rerun check")


def run_changed_block_detection(draft: Path) -> None:
    state = read_state(task_dir_for(draft))
    findings = changed_blocks(state["source_text"], draft.read_text(encoding="utf-8"))
    for finding in findings:
        add_finding(draft, "changed-block-detection", **finding)
    record_result(
        draft,
        "changed-block-detection",
        "findings" if findings else "no-findings",
        file_hash(draft),
    )
    print(f"changed-block-detection: {len(findings)} finding(s)")


def run_review(draft: Path) -> None:
    task_dir = task_dir_for(draft)
    state = read_state(task_dir)
    values = contract_values(draft.with_name("contract.md"))
    if values["Depth"].lower() != "full":
        raise ValueError("independent reviewers run only at full depth")
    current_hash = file_hash(draft)
    reviewer = next(
        (
            item
            for item in REVIEWERS
            if state["results"].get(item[0], {}).get("draft_hash") != current_hash
        ),
        None,
    )
    if reviewer is None:
        print("review: all required reviewers reported")
        return
    source, checklist_name = reviewer
    if source == "prose-reviewer" and status_for(draft)["unresolved_findings"]:
        raise ValueError("resolve structure findings before the prose reviewer")
    codex = shutil.which("codex")
    if not codex:
        record_result(draft, source, "unavailable", current_hash, "Codex is unavailable.")
        with task_lock(task_dir):
            state = read_state(task_dir)
            state["reviews"][source] = {
                "status": "unavailable",
                "draft_hash": current_hash,
                "findings": [],
                "failure_reason": "Codex is unavailable.",
            }
            write_state(task_dir, state)
        raise ValueError("Codex is unavailable; full depth cannot publish")

    kept = [
        {key: finding[key] for key in ("id", "location", "message", "reason")}
        for finding in state["findings"]
        if finding["decision"] == "kept"
    ]
    checklist = (
        Path(__file__).parents[1] / "references" / "passes" / checklist_name
    ).read_text(encoding="utf-8")
    prompt = "\n\n".join(
        [
            "Review the supplied draft using the checklist. Return JSON only. Reuse a prior kept finding ID when the same finding recurs. Do not inspect files or use tools.",
            f"CONTRACT\n{draft.with_name('contract.md').read_text(encoding='utf-8')}",
            f"CHECKLIST\n{checklist}",
            f"PRIOR KEPT FINDINGS\n{json.dumps(kept, ensure_ascii=False)}",
            f"DRAFT\n{draft.read_text(encoding='utf-8')}",
        ]
    )
    if len(prompt) > REVIEW_INPUT_LIMIT:
        reason = f"Reviewer input exceeds {REVIEW_INPUT_LIMIT} characters."
        record_result(draft, source, "failed", current_hash, reason)
        with task_lock(task_dir):
            state = read_state(task_dir)
            state["reviews"][source] = {
                "status": "failed",
                "draft_hash": current_hash,
                "findings": [],
                "failure_reason": reason,
            }
            write_state(task_dir, state)
        raise ValueError(reason)
    schema = {
        "type": "object",
        "properties": {
            "findings": {
                "type": "array",
                "maxItems": 20,
                "items": {
                    "type": "object",
                    "properties": {
                        "id": {"type": ["string", "null"]},
                        "location": {"type": "string", "maxLength": 200},
                        "message": {"type": "string", "maxLength": 500},
                        "evidence": {"type": "string", "maxLength": 1000},
                    },
                    "required": ["id", "location", "message", "evidence"],
                    "additionalProperties": False,
                },
            }
        },
        "required": ["findings"],
        "additionalProperties": False,
    }
    with tempfile.TemporaryDirectory() as review_dir_name:
        review_dir = Path(review_dir_name)
        schema_path = review_dir / "schema.json"
        schema_path.write_text(json.dumps(schema), encoding="utf-8")
        command = [
            codex,
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--config",
            f"model_context_window={REVIEW_CONTEXT_TOKENS}",
            "--output-schema",
            str(schema_path),
            "-C",
            str(review_dir),
            "-",
        ]
        start_error = None
        for _ in range(2):
            try:
                result = subprocess.run(
                    command,
                    input=prompt,
                    check=False,
                    capture_output=True,
                    text=True,
                )
                break
            except OSError as error:
                start_error = error
        else:
            reason = f"Reviewer failed to start: {start_error}"
            record_result(draft, source, "failed", current_hash, reason)
            with task_lock(task_dir):
                state = read_state(task_dir)
                state["reviews"][source] = {
                    "status": "failed",
                    "draft_hash": current_hash,
                    "findings": [],
                    "failure_reason": reason,
                }
                write_state(task_dir, state)
            raise ValueError(reason)
    if result.returncode:
        reason = (result.stderr or result.stdout).strip()[:1000]
        record_result(draft, source, "failed", current_hash, reason)
        with task_lock(task_dir):
            state = read_state(task_dir)
            state["reviews"][source] = {
                "status": "failed",
                "draft_hash": current_hash,
                "findings": [],
                "failure_reason": reason,
            }
            write_state(task_dir, state)
        raise ValueError(f"{source} failed: {reason}")
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        record_result(draft, source, "failed", current_hash, "Reviewer returned invalid JSON.")
        with task_lock(task_dir):
            state = read_state(task_dir)
            state["reviews"][source] = {
                "status": "failed",
                "draft_hash": current_hash,
                "findings": [],
                "failure_reason": "Reviewer returned invalid JSON.",
            }
            write_state(task_dir, state)
        raise ValueError("reviewer returned invalid JSON") from error
    finding_ids = []
    for finding in response["findings"]:
        finding_ids.append(
            add_finding(
                draft,
                source,
                finding["location"],
                finding["message"],
                finding["evidence"],
                finding["id"],
            )
        )
    record_result(
        draft, source, "findings" if finding_ids else "no-findings", current_hash
    )
    with task_lock(task_dir):
        state = read_state(task_dir)
        state["reviews"][source] = {
            "status": "findings" if finding_ids else "no-findings",
            "draft_hash": current_hash,
            "findings": finding_ids,
            "failure_reason": "",
        }
        write_state(task_dir, state)
    print(f"{source}: {len(finding_ids)} finding(s)")


def run_next(draft: Path) -> None:
    run_check(draft)
    state = read_state(task_dir_for(draft))
    current_hash = file_hash(draft)
    if state["source_text"] and all(
        state["results"].get(source, {}).get("draft_hash") == current_hash
        for source in ("language", "sanitize")
    ):
        run_changed_block_detection(draft)
    status = status_for(draft)
    if status["missing_contract_fields"]:
        process = "Planning: goal-setting"
    elif status["unresolved_findings"]:
        findings = read_state(task_dir_for(draft))["findings"]
        unresolved = [
            item for item in findings if item["id"] in status["unresolved_findings"]
        ]
        if any("Planning" in item["location"] for item in unresolved):
            process = "Planning: organizing"
        elif any(
            word in f"{item['location']} {item['message']}".lower()
            for item in unresolved
            for word in ("proportion", "parallel")
        ):
            process = "Reviewing: reading"
        else:
            process = "Reviewing: editing"
    elif status["missing_sources"]:
        process = "Reviewing: added evaluation sub-processes"
    else:
        process = "finished"
    print(json.dumps(status, indent=2, ensure_ascii=False))
    print(f"next: {process}")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)
    start = commands.add_parser("start")
    start.add_argument("--workspace", type=Path, required=True)
    start.add_argument("--destination", default="")
    start.add_argument("--resume")
    for name in ("next", "check", "changed-block-detection", "review", "status", "publish"):
        command = commands.add_parser(name)
        command.add_argument("draft", type=Path)
    ledger = commands.add_parser("ledger")
    ledger.add_argument("draft", type=Path)
    ledger.add_argument("finding", nargs="?")
    action = ledger.add_mutually_exclusive_group()
    action.add_argument("--add", action="store_true")
    action.add_argument("--record-result", action="store_true")
    ledger.add_argument("--source")
    ledger.add_argument("--location")
    ledger.add_argument("--message")
    ledger.add_argument("--evidence", default="")
    ledger.add_argument("--status", choices=RESULT_STATUSES)
    ledger.add_argument("--draft-hash")
    ledger.add_argument("--decision", choices=("fixed", "kept"))
    ledger.add_argument("--reason")
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "start":
            draft = start_task(
                args.workspace, sys.stdin.read(), args.destination, args.resume
            )
            print(f"task: {draft.parent.name}")
            print(draft)
        elif args.command == "check":
            run_check(args.draft)
        elif args.command == "changed-block-detection":
            run_changed_block_detection(args.draft)
        elif args.command == "review":
            run_review(args.draft)
        elif args.command == "next":
            run_next(args.draft)
        elif args.command == "status":
            print(json.dumps(status_for(args.draft), indent=2, ensure_ascii=False))
        elif args.command == "publish":
            sys.stdout.write(publish_text(args.draft))
        elif args.add:
            if not all((args.source, args.location, args.message)):
                raise ValueError("ledger --add requires source, location, and message")
            print(
                add_finding(
                    args.draft,
                    args.source,
                    args.location,
                    args.message,
                    args.evidence,
                )
            )
        elif args.record_result:
            if not all((args.source, args.status, args.draft_hash)):
                raise ValueError(
                    "ledger --record-result requires source, status, and draft hash"
                )
            record_result(args.draft, args.source, args.status, args.draft_hash)
        elif args.finding and args.decision and args.reason:
            decide_finding(args.draft, args.finding, args.decision, args.reason)
        else:
            status = status_for(args.draft)
            print(json.dumps(status, indent=2, ensure_ascii=False))
            if status["unresolved_findings"]:
                return 1
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
