from __future__ import annotations

import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
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
            source.replace("https://example.test/v2", "[guide](docs/other.md)"),
        ]
        for candidate in changed:
            with self.subTest(candidate=candidate), self.assertRaises(agy_japanese.ScriptFailure):
                agy_japanese.preserve_rewrite_facts(source, candidate)

    def test_rewrite_preserves_kanji_numbers_without_blocking_common_words(self):
        source = "対象は三件、三名です。追加分は二つです。第三章を参照します。"
        agy_japanese.preserve_rewrite_facts(source, source)
        agy_japanese.preserve_rewrite_facts("一緒に説明します。", "ともに説明します。")
        agy_japanese.preserve_rewrite_facts(
            "十分な情報を一度確認し、一番の候補の数を記録する。",
            "必要な情報を確認し、最有力候補を記録する。",
        )
        for counter_source, candidate in (
            ("三分待つ。", "五分待つ。"),
            ("三番に並ぶ。", "五番に並ぶ。"),
            ("三度繰り返す。", "五度繰り返す。"),
        ):
            with self.subTest(source=counter_source, candidate=candidate), self.assertRaises(agy_japanese.ScriptFailure):
                agy_japanese.preserve_rewrite_facts(counter_source, candidate)
        for candidate in (
            source.replace("三件", "四件"),
            source.replace("三名", "二名"),
            source.replace("三名", "三件"),
            source.replace("二つ", "三つ"),
            source.replace("第三章", "第二章"),
            source.replace("第三章", "第三項"),
            source.replace("三件", "3人"),
            source.replace("三件", "三名"),
        ):
            with self.subTest(candidate=candidate), self.assertRaises(agy_japanese.ScriptFailure):
                agy_japanese.preserve_rewrite_facts(source, candidate)

    def test_rewrite_preserves_relative_markdown_and_html_urls(self):
        source = '[guide](docs/guide.md) <a href="/guide">guide</a>'
        for candidate in (
            source.replace("docs/guide.md", "docs/other.md"),
            source.replace('href="/guide"', 'href="/other"'),
        ):
            with self.subTest(candidate=candidate), self.assertRaises(agy_japanese.ScriptFailure):
                agy_japanese.preserve_rewrite_facts(source, candidate)

    def test_rewrite_preserves_bare_domain_urls(self):
        with self.assertRaises(agy_japanese.ScriptFailure):
            agy_japanese.preserve_rewrite_facts(
                "See example.com/report for details.",
                "See example.com/other for details.",
            )

    def test_rewrite_does_not_treat_japanese_url_suffix_or_version_as_a_url(self):
        agy_japanese.preserve_rewrite_facts(
            "詳細はhttps://example.test/reportを参照。example.comを確認。",
            "https://example.test/reportをご覧ください。example.comを参照。",
        )
        self.assertFalse(agy_japanese.fact_tokens("urls", "v1.2"))
        self.assertTrue(agy_japanese.fact_tokens("numbers", "v1.2"))
        with self.assertRaises(agy_japanese.ScriptFailure):
            agy_japanese.preserve_rewrite_facts(
                "https://example.test/report(old)",
                "https://example.test/report(new)",
            )

    def test_gate_cli_handles_file_stdin_and_recorded_sha(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state"
            env = os.environ.copy()
            env["XDG_STATE_HOME"] = str(state)
            short_file = root / "short.md"
            short_file.write_text("短い文章", encoding="utf-8")
            short = subprocess.run(
                [sys.executable, str(SCRIPT), "gate", "--file", str(short_file)],
                env=env, capture_output=True, check=False,
            )
            self.assertEqual(short.returncode, 0, short.stderr.decode())

            raw = ("あ" * 20).encode()
            unreviewed = subprocess.run(
                [sys.executable, str(SCRIPT), "gate"],
                input=raw, env=env, capture_output=True, check=False,
            )
            self.assertEqual(unreviewed.returncode, 1)
            self.assertIn(b"agy-japanese review", unreviewed.stderr)

            state_dir = state / "shunk031-agy-japanese"
            state_dir.mkdir(parents=True)
            accepted = state_dir / agy_japanese.ACCEPTED_FILE
            valid_record = {
                "timestamp": agy_japanese.timestamp(),
                "path": "<stdin>",
                "sha256": hashlib.sha256(raw).hexdigest(),
            }
            accepted.write_text(
                json.dumps(valid_record) + "\nnot JSON\n",
                encoding="utf-8",
            )
            corrupt = subprocess.run(
                [sys.executable, str(SCRIPT), "gate"],
                input=raw, env=env, capture_output=True, check=False,
            )
            self.assertEqual(corrupt.returncode, agy_japanese.EXIT_CODES["error"])
            self.assertIn(b"hold the deliverable and tell the user", corrupt.stderr)

            accepted.write_text("{}\n", encoding="utf-8")
            empty_record = subprocess.run(
                [sys.executable, str(SCRIPT), "gate"],
                input=raw, env=env, capture_output=True, check=False,
            )
            self.assertEqual(empty_record.returncode, agy_japanese.EXIT_CODES["error"])

            accepted.unlink()
            accepted.mkdir()
            unavailable = subprocess.run(
                [sys.executable, str(SCRIPT), "gate"],
                input=raw, env=env, capture_output=True, check=False,
            )
            self.assertEqual(unavailable.returncode, agy_japanese.EXIT_CODES["error"])
            self.assertIn(b"hold the deliverable and tell the user", unavailable.stderr)
            accepted.rmdir()

            accepted.write_text(json.dumps(valid_record) + "\n", encoding="utf-8")
            reviewed = subprocess.run(
                [sys.executable, str(SCRIPT), "gate"],
                input=raw, env=env, capture_output=True, check=False,
            )
            self.assertEqual(reviewed.returncode, 0, reviewed.stderr.decode())

    def test_rewrite_prompt_uses_plain_text_and_protects_facts_and_code(self):
        prompt = agy_japanese.content_prompt("rewrite", "本文")
        for protected in ("numbers", "URLs", "inline code", "fenced code", "HTML comments"):
            with self.subTest(protected=protected):
                self.assertIn(protected, prompt)
        self.assertIn("Input is plain text, not JSON:\n本文", prompt)
        self.assertNotIn('{"text": "本文"}', prompt)
        self.assertNotIn("LANGUAGE", prompt)

    def test_review_prompt_treats_html_comments_as_render_time_placeholders(self):
        prompt = agy_japanese.review_prompt("本文\n<!-- table:cases -->", 1)
        self.assertIn("intentional render-time placeholders", prompt)
        self.assertIn("Do not ask to expand placeholders", prompt)
        self.assertIn("content absent from the supplied source", prompt)

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
                {
                    "timestamp": agy_japanese.timestamp(),
                    "path": str(path),
                    "sha256": hashlib.sha256(raw).hexdigest(),
                },
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
                self.assertEqual(command[command.index("--print-timeout") + 1], "600s")
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

    def test_missing_agy_has_distinct_code_hold_message_and_log(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state"
            env = os.environ.copy()
            env["PATH"] = str(root)
            env["XDG_STATE_HOME"] = str(state)
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "rewrite"],
                input="これは20文字以上の日本語本文です。".encode(),
                env=env,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, agy_japanese.EXIT_CODES["error"])
            self.assertIn(b"hold the deliverable and tell the user", result.stderr)
            record = json.loads(
                (state / "shunk031-agy-japanese" / agy_japanese.CALLS_FILE).read_text()
            )
            self.assertEqual(record["operation"], "rewrite")
            self.assertEqual(record["outcome"], "error")

    def test_rewrite_cli_writes_plain_body_and_rejects_json_wrappers(self):
        body = "この日本語の本文は20件を確認します。"
        wrapped = json.dumps({"text": body}, ensure_ascii=False)
        cases = (
            ("plain body", body, 0),
            ("bare JSON object", wrapped, 1),
            ("fenced JSON object", f"```json\n{wrapped}\n```", 1),
        )
        for label, agy_text, exit_code in cases:
            with tempfile.TemporaryDirectory() as directory, self.subTest(response=label):
                root = Path(directory)
                bindir = root / "bin"
                bindir.mkdir()
                source = root / "source.md"
                output = root / "candidate.md"
                source.write_text(body, encoding="utf-8")
                envelope = {"status": "SUCCESS", "structured_output": {"text": agy_text}}
                fake_agy = bindir / "agy"
                fake_agy.write_text(
                    f"#!{sys.executable}\nprint({json.dumps(json.dumps(envelope, ensure_ascii=False))})\n",
                    encoding="utf-8",
                )
                fake_agy.chmod(0o755)
                env = os.environ.copy()
                env["PATH"] = str(bindir) + os.pathsep + os.defpath
                env["XDG_STATE_HOME"] = str(root / "state")

                result = subprocess.run(
                    [sys.executable, str(SCRIPT), "rewrite", "--file", str(source), "--output", str(output)],
                    env=env, capture_output=True, check=False,
                )

                self.assertEqual(result.returncode, exit_code, result.stderr.decode())
                if exit_code == 0:
                    self.assertEqual(output.read_text(encoding="utf-8"), body)
                else:
                    self.assertIn(b"serialized JSON object", result.stderr)
                    self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
