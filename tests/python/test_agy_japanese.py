from __future__ import annotations

import hashlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from types import SimpleNamespace
from unittest import mock


SCRIPT = (
    Path(__file__).parents[2]
    / "skills"
    / "agy"
    / "shunk031-agy-japanese"
    / "scripts"
    / "agy-japanese"
)


def load_module():
    loader = importlib.machinery.SourceFileLoader("agy_japanese", str(SCRIPT))
    spec = importlib.util.spec_from_loader("agy_japanese", loader)
    if spec is None:
        raise RuntimeError(f"Failed to load module from {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


agy_japanese = load_module()


class AgyJapaneseTest(unittest.TestCase):
    def test_gate_uses_one_replaceable_kana_threshold(self):
        self.assertFalse(agy_japanese.requires_review("あ" * 19))
        self.assertTrue(agy_japanese.requires_review("カ" * 20))
        self.assertFalse(agy_japanese.requires_review("漢字" * 20))

    def test_rewrite_preserves_facts_while_allowing_reordering(self):
        source = (
            "20件を確認しました。https://example.test/v2.\n"
            "`run(20)`\n\n```js\nconst count = 20;\n```\n<!-- table:cases -->"
        )
        reordered = (
            "<!-- table:cases -->\n\n```js\nconst count = 20;\n```\n"
            "`run(20)`を実行しました。20件を確認しました。https://example.test/v2."
        )

        agy_japanese.preserve_rewrite_facts(source, reordered)

    def test_rewrite_rejects_changed_protected_facts(self):
        source = "20件は `run(20)` を使い、https://example.test/v2 を参照します。\n\n```js\nlet n = 20;\n```\n<!-- table:cases -->"
        changed = [
            source.replace("20件", "21件", 1),
            source.replace("https://example.test/v2", "https://example.test/v3"),
            source.replace("`run(20)`", "`run(21)`"),
            source.replace("let n = 20", "let n = 21"),
            source.replace("<!-- table:cases -->", "<!-- table:results -->"),
        ]
        for candidate in changed:
            with self.subTest(candidate=candidate), self.assertRaises(agy_japanese.ScriptFailure):
                agy_japanese.preserve_rewrite_facts(source, candidate)

    def test_rewrite_prompt_explicitly_protects_facts_and_code(self):
        prompt = agy_japanese.content_prompt("rewrite", "本文")
        for protected in ("numbers", "URLs", "inline code", "fenced code", "HTML comments"):
            with self.subTest(protected=protected):
                self.assertIn(protected, prompt)

    def test_pairs_replace_one_exact_unique_match_and_preserve_other_code(self):
        source = '<button>古い文言</button><script>const count = 7;</script>'

        result = agy_japanese.apply_pairs(
            source, [{"old": "古い文言", "new": "新しい文言"}]
        )

        self.assertEqual(
            result,
            '<button>新しい文言</button><script>const count = 7;</script>',
        )

    def test_pairs_reject_missing_duplicate_repeated_and_overlapping_old_values(self):
        cases = [
            ("abc", [{"old": "missing", "new": "x"}]),
            ("abc abc", [{"old": "abc", "new": "x"}]),
            ("aaa", [{"old": "aa", "new": "x"}]),
            ("abc", [{"old": "a", "new": "x"}, {"old": "a", "new": "y"}]),
            ("abc", [{"old": "ab", "new": "x"}, {"old": "bc", "new": "y"}]),
        ]
        for source, pairs in cases:
            with self.subTest(source=source, pairs=pairs), self.assertRaises(agy_japanese.ScriptFailure):
                agy_japanese.apply_pairs(source, pairs)

    def test_pairs_cannot_change_numbers_or_placeholders(self):
        with self.assertRaises(agy_japanese.ScriptFailure):
            agy_japanese.apply_pairs(
                "20件 古い", [{"old": "古い", "new": "21件 新しい"}]
            )

    def test_gate_allows_short_text_and_exact_accepted_hash_only(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            path = state / "deliverable.md"
            raw = ("あ" * 20 + "\r\n").encode()
            path.write_bytes(raw)
            agy_japanese.append_jsonl(
                state / agy_japanese.ACCEPTED_FILE,
                {"sha256": hashlib.sha256(raw).hexdigest()},
            )
            args = SimpleNamespace(file=str(path))
            with mock.patch.object(agy_japanese, "state_directory", return_value=state):
                self.assertEqual(agy_japanese.run_gate(args), 0)
                path.write_bytes(raw + b"changed")
                with redirect_stderr(io.StringIO()):
                    self.assertEqual(agy_japanese.run_gate(args), 1)
                path.write_bytes("短文".encode())
                self.assertEqual(agy_japanese.run_gate(args), 0)

    def test_gate_reads_stdin(self):
        args = SimpleNamespace(file="-")
        stdin = SimpleNamespace(buffer=io.BytesIO(b"English text only"))
        with mock.patch.object(agy_japanese.sys, "stdin", stdin):
            self.assertEqual(agy_japanese.run_gate(args), 0)

    def test_agy_greeting_lines_are_removed_from_structured_json(self):
        result = agy_japanese.strip_json_greetings(
            {"text": "🤖 I read ~/.agents/AGENTS.md.\n\n本文です。"}
        )
        self.assertEqual(result["text"], "本文です。")

    def test_failure_classification_covers_required_outcomes(self):
        self.assertEqual(agy_japanese.classify_error("401 authentication required"), "auth")
        self.assertEqual(agy_japanese.classify_error("429 quota exceeded"), "limit")
        self.assertEqual(agy_japanese.classify_error("deadline_exceeded"), "timeout")

    def test_review_records_only_an_accept_and_hashes_exact_input_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            path = state / "draft.md"
            raw = ("あ" * 20 + "\r\n").encode()
            path.write_bytes(raw)
            args = SimpleNamespace(file=str(path), path=None, round=1)
            with (
                mock.patch.object(agy_japanese, "state_directory", return_value=state),
                mock.patch.object(
                    agy_japanese,
                    "call_agy",
                    return_value={"decision": "ACCEPT", "findings": []},
                ),
                redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(agy_japanese.run_review(args), 0)
            record = json.loads((state / agy_japanese.ACCEPTED_FILE).read_text())
            self.assertEqual(record["path"], str(path))
            self.assertEqual(record["sha256"], hashlib.sha256(raw).hexdigest())

            args.round = 2
            with (
                mock.patch.object(agy_japanese, "state_directory", return_value=state),
                mock.patch.object(
                    agy_japanese,
                    "call_agy",
                    return_value={"decision": "REJECT", "findings": ["直してください"]},
                ),
                redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(agy_japanese.run_review(args), 0)
            records = (state / agy_japanese.ACCEPTED_FILE).read_text().splitlines()
            self.assertEqual(len(records), 1)

    def test_agy_call_uses_fresh_workspace_settings_and_logs_round(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            response = json.dumps(
                {"status": "SUCCESS", "structured_output": {"decision": "ACCEPT", "findings": []}}
            )
            workspaces = []

            def fake_run(command, **kwargs):
                workspace = Path(kwargs["cwd"])
                self.assertTrue(workspace.is_dir())
                self.assertNotEqual(workspace, Path.cwd())
                workspaces.append(workspace)
                self.assertEqual(command[command.index("--model") + 1], "gemini-4-argon-high")
                self.assertEqual(command[command.index("--mode") + 1], "plan")
                self.assertIn("--sandbox", command)
                self.assertEqual(command[command.index("--print-timeout") + 1], "120s")
                settings = json.loads(command[command.index("--settings") + 1])
                self.assertIn("write_file(*)", settings["permissions"]["deny"])
                self.assertEqual(command[command.index("--output-format") + 1], "json")
                self.assertIn("--json-schema", command)
                self.assertTrue(command[-1].startswith("--print="))
                self.assertNotIn("--continue", command)
                return subprocess.CompletedProcess(command, 0, response, "")

            with (
                mock.patch.object(agy_japanese, "state_directory", return_value=state),
                mock.patch.object(agy_japanese.subprocess, "run", side_effect=fake_run),
            ):
                result = agy_japanese.call_agy(
                    "review",
                    "prompt",
                    {},
                    agy_japanese.validate_review,
                    review_round=2,
                )

            self.assertEqual(result["decision"], "ACCEPT")
            self.assertEqual(len(workspaces), 1)
            self.assertFalse(workspaces[0].exists())
            record = json.loads((state / agy_japanese.CALLS_FILE).read_text())
            self.assertEqual(record["operation"], "review")
            self.assertEqual(record["outcome"], "accept")
            self.assertEqual(record["round"], 2)
            self.assertGreaterEqual(record["duration_seconds"], 0)

    def test_agy_timeout_has_distinct_code_and_is_logged(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            with (
                mock.patch.object(agy_japanese, "state_directory", return_value=state),
                mock.patch.object(
                    agy_japanese.subprocess,
                    "run",
                    side_effect=subprocess.TimeoutExpired("agy", 130),
                ),
            ):
                with self.assertRaises(agy_japanese.AgyFailure) as raised:
                    agy_japanese.call_agy("rewrite", "prompt", {}, lambda value: (value, "ok"))
            self.assertEqual(raised.exception.outcome, "timeout")
            record = json.loads((state / agy_japanese.CALLS_FILE).read_text())
            self.assertEqual(record["outcome"], "timeout")


if __name__ == "__main__":
    unittest.main()
