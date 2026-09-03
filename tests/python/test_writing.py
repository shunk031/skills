from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "skills/shunk031-writing/scripts/writing.py"


def load_module():
    spec = importlib.util.spec_from_file_location("writing", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load module from {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


writing = load_module()


def complete_contract(draft: Path, depth: str = "quick") -> None:
    contract = draft.with_name("contract.md")
    contract.write_text(
        "\n".join(
            [
                "# Writing contract",
                "",
                "Reader: Maintainers.",
                "Purpose: Explain the change.",
                "Main point: The change is ready.",
                f"Depth: {depth}",
                "Language: English",
                "Medium: report",
                "",
                "## Sections",
                "",
                "| Heading | Reader need | Intended share |",
                "| --- | --- | --- |",
                "| (whole document) | Understand the result. | |",
                "",
            ]
        ),
        encoding="utf-8",
    )


class ChangedBlockDetectionTest(unittest.TestCase):
    def test_detects_changed_or_missing_occurrences_without_flagging_moves(self) -> None:
        source = """First paragraph.

Repeated paragraph.

Repeated paragraph.

- Keep this item.

```python
print("keep")
```
"""
        draft = """```python
print("keep")
```

- Keep this item.

Repeated paragraph.

First paragraph changed.
"""

        findings = writing.changed_blocks(source, draft)

        self.assertEqual(
            [finding["message"] for finding in findings],
            [
                "Source block changed or disappeared: First paragraph.",
                "Source block changed or disappeared: Repeated paragraph.",
            ],
        )


class FindingLedgerTest(unittest.TestCase):
    def test_duplicate_finding_reuses_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            draft = writing.start_task(Path(tmpdir), "Draft.\n", "issue:50")
            first = writing.add_finding(
                draft, "check", "Reviewing: reading", "Repeated claim."
            )
            second = writing.add_finding(
                draft, "check", "Reviewing: reading", "Repeated claim."
            )

            state = json.loads(draft.with_name("state.json").read_text())

        self.assertEqual(first, second)
        self.assertEqual(len(state["findings"]), 1)

    def test_status_requires_results_and_reopens_kept_decision_after_context_change(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            draft = writing.start_task(Path(tmpdir), "Draft.\n", "issue:50")
            complete_contract(draft)
            finding_id = writing.add_finding(
                draft, "user", "Planning: organizing", "Keep the short opening."
            )
            writing.decide_finding(draft, finding_id, "kept", "The reader knows it.")
            current_hash = writing.file_hash(draft)
            for source in ("language", "sanitize", "changed-block-detection", "check"):
                writing.record_result(draft, source, "no-findings", current_hash)

            self.assertTrue(writing.status_for(draft)["ready"])

            draft.with_name("contract.md").write_text(
                draft.with_name("contract.md").read_text().replace(
                    "Maintainers.", "First-time readers."
                )
            )
            status = writing.status_for(draft)

        self.assertFalse(status["ready"])
        self.assertEqual(status["unresolved_findings"], [finding_id])

    def test_full_depth_requires_structure_and_prose_reviews(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            draft = writing.start_task(Path(tmpdir), "", "issue:50")
            complete_contract(draft, depth="full")
            current_hash = writing.file_hash(draft)
            for source in ("language", "sanitize", "check"):
                writing.record_result(draft, source, "no-findings", current_hash)

            status = writing.status_for(draft)
            self.assertEqual(
                status["missing_sources"], ["structure-reviewer", "prose-reviewer"]
            )

            writing.record_result(
                draft, "structure-reviewer", "no-findings", current_hash
            )
            writing.record_result(draft, "prose-reviewer", "no-findings", current_hash)

            self.assertTrue(writing.status_for(draft)["ready"])


class TaskStateTest(unittest.TestCase):
    def test_tasks_are_distinct_and_resume_verifies_source_and_destination(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace = Path(tmpdir)
            first = writing.start_task(workspace, "Source.\n", "issue:50")
            second = writing.start_task(workspace, "Source.\n", "issue:50")
            task_id = first.parent.name

            self.assertNotEqual(first.parent, second.parent)
            self.assertEqual(
                writing.start_task(
                    workspace, "Source.\n", "issue:50", resume=task_id
                ),
                first,
            )
            with self.assertRaisesRegex(ValueError, "source does not match"):
                writing.start_task(
                    workspace, "Changed.\n", "issue:50", resume=task_id
                )
            with self.assertRaisesRegex(ValueError, "destination does not match"):
                writing.start_task(
                    workspace, "Source.\n", "issue:51", resume=task_id
                )


class PublishTest(unittest.TestCase):
    def test_publish_returns_completed_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            draft = writing.start_task(Path(tmpdir), "", "issue:50")
            draft.write_text("# Finished\n", encoding="utf-8")
            complete_contract(draft)
            current_hash = writing.file_hash(draft)
            for source in ("language", "sanitize", "check"):
                writing.record_result(draft, source, "no-findings", current_hash)

            self.assertEqual(writing.publish_text(draft), "# Finished\n")

    def test_publish_cli_refuses_incomplete_task_without_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            draft = writing.start_task(Path(tmpdir), "Draft.\n", "issue:50")
            complete_contract(draft)

            result = subprocess.run(
                [sys.executable, str(SCRIPT_PATH), "publish", str(draft)],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("not ready", result.stderr)


if __name__ == "__main__":
    unittest.main()
