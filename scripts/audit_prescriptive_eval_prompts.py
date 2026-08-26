#!/usr/bin/env python3
"""Audit the Issue #20 prescriptive-prompt cases in the current checkout."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


# The nine cases are the Issue #20 audit set at 816bf8d. Some disappeared when
# their skills were retired; keeping the manifest makes that scope correction
# visible instead of silently treating deleted cases as fixed.
AUDITED_CASES = {
    ("shunk031-codex-worker-prompting", "gate-contract-and-conflict"),
    ("shunk031-herdr-tab-status", "label-active-work"),
    ("shunk031-manage-agent-guidance", "approved-removal-and-root-skill-ownership"),
    ("shunk031-manage-agent-guidance", "concrete-migration-records"),
    ("shunk031-orchestrate-herdr-workers", "fan-out-parallel-workers"),
    ("shunk031-orchestrate-herdr-workers", "independent-done-acceptance"),
    ("shunk031-research-report-ja", "first-time-reader-report"),
    ("shunk031-structured-writing", "organize-operating-instructions"),
    ("shunk031-structured-writing", "pull-request-body-template"),
}

ORIGINAL_SURVIVORS = {
    ("shunk031-codex-worker-prompting", "gate-contract-and-conflict"),
    ("shunk031-manage-agent-guidance", "approved-removal-and-root-skill-ownership"),
    ("shunk031-manage-agent-guidance", "concrete-migration-records"),
    ("shunk031-orchestrate-herdr-workers", "fan-out-parallel-workers"),
    ("shunk031-orchestrate-herdr-workers", "independent-done-acceptance"),
}

# This case stays in the repository as a later generalization candidate: its
# prompt describes an active retry without prescribing the answer.
FOLLOW_UP_CASES = {
    ("shunk031-herdr-tab-status", "label-active-work"),
}

# These patterns cover direct instructions to the graded response, rather than
# merely mentioning a skill concept. The imperative check below catches a
# small set of answer-shaping verbs when their clause overlaps an assertion.
DIRECT_RESPONSE_DIRECTIVES = (
    ("must", re.compile(r"\bmust\b", re.IGNORECASE)),
    ("require", re.compile(r"\brequires?\b|\brequired\b", re.IGNORECASE)),
    (
        "explicitly-state",
        re.compile(r"\bexplicitly\s+(?:state|include|name|identify)\b", re.IGNORECASE),
    ),
    (
        "do-not",
        re.compile(
            r"\bdo\s+not\s+(?:call|accept|describe|claim|restate|refuse|use)\b",
            re.IGNORECASE,
        ),
    ),
    (
        "response-subject",
        re.compile(
            r"\bthe\s+(?:response|answer|output|reply)\s+"
            r"(?:must|should|needs?\s+to|has\s+to|is\s+required\s+to|"
            r"include|state|identify|reject|redispatch|treat|compare)\b",
            re.IGNORECASE,
        ),
    ),
)

IMPERATIVE_RESPONSE_VERBS = {
    "compare",
    "ensure",
    "explicitly",
    "include",
    "keep",
    "never",
    "redispatch",
    "refuse",
    "require",
    "state",
    "stop",
    "treat",
}

WORD = re.compile(r"[a-z][a-z0-9_-]*", re.IGNORECASE)
STOPWORDS = {
    "a",
    "an",
    "and",
    "as",
    "at",
    "be",
    "by",
    "for",
    "from",
    "in",
    "is",
    "it",
    "of",
    "on",
    "or",
    "that",
    "the",
    "their",
    "this",
    "to",
    "with",
}


def load_cases(path: Path) -> list[dict[str, object]]:
    data = json.loads(path.read_text())
    if isinstance(data, list):
        return data
    key = "evals" if path.name == "evals.json" else "cases"
    return data[key]


def normalized_words(text: str) -> set[str]:
    return {
        word.lower().rstrip("s")
        for word in WORD.findall(text)
        if word.lower() not in STOPWORDS
    }


def imperative_overlap(prompt: str, assertions: list[object]) -> bool:
    assertion_words = normalized_words(" ".join(str(item) for item in assertions))
    for sentence in re.split(r"(?<=[.!?])\s+", prompt):
        match = re.match(r"(?P<verb>[a-z]+)\b(?P<body>.*)", sentence.strip(), re.IGNORECASE)
        if not match or match.group("verb").lower() not in IMPERATIVE_RESPONSE_VERBS:
            continue
        body_words = normalized_words(match.group("body"))
        if len(body_words & assertion_words) >= 2:
            return True
    return False


def directive_reasons(case: dict[str, object]) -> list[str]:
    prompt = str(case["prompt"])
    reasons = [
        label
        for label, pattern in DIRECT_RESPONSE_DIRECTIVES
        if pattern.search(prompt)
    ]
    if imperative_overlap(prompt, list(case.get("assertions", []))):
        reasons.append("imperative-assertion-overlap")
    return reasons


def collect_cases(root: Path) -> dict[tuple[str, str], dict[str, object]]:
    cases: dict[tuple[str, str], dict[str, object]] = {}
    for filename in ("evals.json", "triggers.json"):
        for path in sorted((root / "skills").glob(f"*/evals/{filename}")):
            skill = path.parent.parent.name
            for case in load_cases(path):
                key = (skill, str(case["id"]))
                if key in AUDITED_CASES:
                    entry = cases.setdefault(key, {"assertions": [], "sources": {}})
                    entry["assertions"] = case.get("assertions", entry["assertions"])
                    entry["sources"][filename] = case
    return cases


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).parents[1])
    args = parser.parse_args()

    cases = collect_cases(args.root)
    found: dict[tuple[str, str], list[str]] = {}
    for key, entry in cases.items():
        reasons = set()
        for case in entry["sources"].values():
            reasons.update(directive_reasons(case))
        if reasons:
            found[key] = sorted(reasons)

    present = set(cases)
    missing = sorted(AUDITED_CASES - present)
    follow_up = sorted(present & FOLLOW_UP_CASES)
    additional = sorted(set(found) - ORIGINAL_SURVIVORS)
    print(f"Issue #20 audit baseline: {len(AUDITED_CASES)} cases")
    print(f"Prescriptive survivors: {len(found)}")
    print(f"Retired/out-of-scope cases: {len(missing)}")
    print(f"Present follow-up candidates: {len(follow_up)}")
    for skill, case_id in sorted(found):
        reasons = ",".join(found[(skill, case_id)])
        print(f"SURVIVES\t{skill}/{case_id}\treasons={reasons}")
    for skill, case_id in additional:
        print(f"ADDITIONAL\t{skill}/{case_id}")
    for skill, case_id in missing:
        print(f"OUT-OF-SCOPE\t{skill}/{case_id}")
    for skill, case_id in follow_up:
        print(f"FOLLOW-UP\t{skill}/{case_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
