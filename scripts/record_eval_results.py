#!/usr/bin/env python3
"""Record a Shuhari eval run's published numbers beside the skill it measured.

Shuhari writes every run into ``skills/<name>-workspace/``, which is gitignored
because it holds verbatim agent transcripts. The aggregate numbers are not in
that category: ``benchmark.json`` carries pass rates, token counts, timings, and
the assertion texts already committed in ``evals.json``. Nothing an agent said
appears in it.

This lifts those numbers into ``skills/<name>/evals/results.json``, which is
committed, so the documentation site can state what a skill measurably changes
without anyone re-running an evaluation to find out.

Usage:
    scripts/record_eval_results.py <skill-directory>...
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "1"
RESULTS_FILENAME = "results.json"


def latest_measured_iteration(workspace: Path) -> Path | None:
    """Return the newest ``iteration-N`` that actually produced a benchmark.

    Iterations are numbered rather than timestamped, so the highest number is
    the most recent run. The highest is not necessarily a measurement: a run
    that was interrupted, or that failed before grading, leaves a directory with
    no ``benchmark.json``. Taking the newest directory outright would let such a
    run shadow the last real result, so this takes the newest one that has
    numbers to publish.

    Trigger runs live under ``trigger-iteration-N``. They measure whether a
    skill engages, not what it changes, and are not considered here.
    """
    candidates = [
        path
        for path in workspace.glob("iteration-*")
        if path.is_dir()
        and re.fullmatch(r"iteration-\d+", path.name)
        and (path / "benchmark.json").is_file()
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda path: int(path.name.rsplit("-", 1)[1]))


def build_results(
    skill_name: str, manifest: dict[str, Any], benchmark: dict[str, Any]
) -> dict[str, Any]:
    """Assemble the published record from one run's manifest and benchmark."""
    config = manifest.get("config", {})
    summary = benchmark.get("run_summary", {})

    def arm(name: str, field: str) -> float | None:
        value = summary.get(name, {}).get(field, {}).get("mean")
        return round(value, 4) if isinstance(value, (int, float)) else None

    return {
        "schema_version": SCHEMA_VERSION,
        "skill_name": skill_name,
        "measured_at": manifest.get("created_at"),
        "agent": manifest.get("agent_identity", {}).get("agent"),
        "model": config.get("model"),
        "reasoning_effort": config.get("reasoning_effort"),
        "trials": config.get("trials"),
        "network": config.get("network"),
        "pass_rate": {
            "with_skill": arm("with_skill", "pass_rate"),
            "without_skill": arm("without_skill", "pass_rate"),
        },
        "tokens": {
            "with_skill": arm("with_skill", "tokens"),
            "without_skill": arm("without_skill", "tokens"),
        },
        "seconds": {
            "with_skill": arm("with_skill", "time_seconds"),
            "without_skill": arm("without_skill", "time_seconds"),
        },
        "assertions": [
            {
                "case_id": entry.get("case_id"),
                "assertion": entry.get("assertion"),
                "with_skill": entry.get("with_pass_rate"),
                "without_skill": entry.get("without_pass_rate"),
                "category": entry.get("category"),
            }
            for entry in benchmark.get("assertion_analysis", [])
        ],
    }


def record(skill_dir: Path) -> bool:
    """Write ``evals/results.json`` for one skill. Return whether it wrote."""
    name = skill_dir.name
    workspace = skill_dir.parent / f"{name}-workspace"
    iteration = latest_measured_iteration(workspace) if workspace.is_dir() else None
    if iteration is None:
        print(f"skip {name}: no completed evaluation to record", file=sys.stderr)
        return False

    manifest_path = iteration / "manifest.json"
    benchmark_path = iteration / "benchmark.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.is_file() else {}
    benchmark = json.loads(benchmark_path.read_text())
    results = build_results(name, manifest, benchmark)

    destination = skill_dir / "evals" / RESULTS_FILENAME
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
    print(f"recorded {name}: {iteration.name}")
    return True


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2

    for raw in argv:
        skill_dir = Path(raw).resolve()
        if not (skill_dir / "SKILL.md").is_file():
            print(f"not a skill directory: {raw}", file=sys.stderr)
            return 2
        record(skill_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
