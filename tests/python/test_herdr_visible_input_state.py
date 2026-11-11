from __future__ import annotations

import os
from pathlib import Path
import subprocess
import unittest

from herdr_visible_input_state_reference import classify, generate_malformed_lines, generate_valid_lines


REPO_ROOT = Path(__file__).resolve().parents[2]
AWK_SCRIPT = (
    REPO_ROOT
    / "skills"
    / "herdr"
    / "shunk031-herdr-orchestrate-workers"
    / "scripts"
    / "herdr-visible-input-state.awk"
)
FIXTURE_DIRECTORY = REPO_ROOT / "tests" / "fixtures" / "herdr-visible-input-state"
AWK_ENVIRONMENT = dict(os.environ, LC_ALL="C")


def classify_with_awk(snapshot: str) -> str:
    result = subprocess.run(
        ["awk", "-f", str(AWK_SCRIPT)],
        input=snapshot,
        text=True,
        capture_output=True,
        check=True,
        env=AWK_ENVIRONMENT,
    )
    return result.stdout.strip()


CAPTURED_EXPECTATIONS = {
    "claude-live-suggestion.ansi": "empty",
    "claude-cursor-suggestion.ansi": "empty",
    "claude-cursor-then-normal.ansi": "occupied",
    "claude-lone-cursor.ansi": "occupied",
    "claude-normal-text.ansi": "occupied",
    "claude-leading-zero-reset-counterexample.ansi": "occupied",
    "claude-extended-color-argument-counterexample.ansi": "occupied",
    "claude-malformed-extended-color-counterexample.ansi": "occupied",
    "claude-zero-padded-reset-typed.ansi": "occupied",
    "claude-zero-padded-dim-reset-typed.ansi": "occupied",
}

EXISTING_CODEX_AND_AGY_EXPECTATIONS = {
    "Codex dim suggestion": ("› \x1b[2mAsk Codex to do anything\x1b[0m\n", "empty"),
    "Codex nested dim suggestion": (
        "\x1b[0m\x1b[1m\x1b[48;2;30;30;30m›\x1b[0m"
        "\x1b[48;2;30;30;30m \x1b[0m\x1b[2m\x1b[48;2;30;30;30m"
        "Ask Codex to do anything\x1b[0m\x1b[48;2;30;30;30m    \x1b[0m\r\n",
        "empty",
    ),
    "Codex text after dim suggestion": (
        "› \x1b[1;2mDraft suggestion\x1b[22m\x1b[48;2;30;30;30mtyped text\x1b[0m\r\n",
        "occupied",
    ),
    "agy gray suggestion": (
        "\x1b[0m\x1b[38;5;12m>\x1b[0m \x1b[0m\x1b[38;5;8m"
        "Accept-edits mode: file edits auto-approved (shift+tab to cycle)\x1b[0m\r\n",
        "empty",
    ),
    "agy typed text": ("\x1b[0m\x1b[38;5;12m>\x1b[0m typed text\r\n", "occupied"),
}


class HerdrVisibleInputStateTest(unittest.TestCase):
    def test_captured_claude_fixtures_and_counterexamples(self):
        self.assertEqual(set(CAPTURED_EXPECTATIONS), {path.name for path in FIXTURE_DIRECTORY.glob("*.ansi")})
        for filename, expected in CAPTURED_EXPECTATIONS.items():
            with self.subTest(fixture=filename):
                snapshot = (FIXTURE_DIRECTORY / filename).read_text(encoding="utf-8")
                self.assertEqual(expected, classify(snapshot))
                self.assertEqual(expected, classify_with_awk(snapshot))

    def test_existing_codex_and_agy_fixtures_keep_their_results(self):
        for name, (snapshot, expected) in EXISTING_CODEX_AND_AGY_EXPECTATIONS.items():
            with self.subTest(fixture=name):
                self.assertEqual(expected, classify(snapshot))
                self.assertEqual(expected, classify_with_awk(snapshot))

    def test_utf8_c1_control_sequence_is_occupied(self):
        snapshot = "❯ \x1b[2m\u009b0m\x1b[0m\n"
        self.assertEqual("occupied", classify(snapshot))
        self.assertEqual("occupied", classify_with_awk(snapshot))

    def test_generated_cases_match_the_independent_reference(self):
        malformed = list(generate_malformed_lines())
        valid = list(generate_valid_lines())
        cases = malformed + valid
        self.assertGreaterEqual(len(cases), 5000)

        disagreements = []
        for index, snapshot in enumerate(malformed):
            expected = classify(snapshot)
            actual = classify_with_awk(snapshot)
            if expected != "occupied" or actual != expected:
                disagreements.append((index, "malformed must be occupied", expected, actual))
        for index, snapshot in enumerate(valid, start=len(malformed)):
            expected = classify(snapshot)
            actual = classify_with_awk(snapshot)
            if actual != expected:
                disagreements.append((index, "reference mismatch", expected, actual))

        print(f"generated cases: {len(cases)}; disagreements: {len(disagreements)}")
        self.assertEqual(0, len(disagreements), f"first disagreements: {disagreements[:10]}")


if __name__ == "__main__":
    unittest.main()
