import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = (
    Path(__file__).parents[2]
    / "skills"
    / "herdr"
    / "shunk031-herdr-orchestrate-workers"
    / "scripts"
    / "herdr-worker-size-gate.py"
)


class WorkerSizeGateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.remote = self.root / "remote.git"
        self.home = self.root / "home"
        self.home.mkdir()
        self.run_git("init", "--bare", "--initial-branch=main", str(self.remote), cwd=self.root)
        self.repo.mkdir()
        self.run_git("init", "--initial-branch=main", cwd=self.repo)
        self.run_git("config", "user.name", "Test User", cwd=self.repo)
        self.run_git("config", "user.email", "test@example.invalid", cwd=self.repo)
        (self.repo / ".gitignore").write_text(".cache/\n", encoding="utf-8")
        (self.repo / "source.py").write_text("one\n", encoding="utf-8")
        self.run_git("add", ".gitignore", "source.py", cwd=self.repo)
        self.run_git("commit", "-m", "base", cwd=self.repo)
        self.run_git("remote", "add", "origin", str(self.remote), cwd=self.repo)
        self.run_git("push", "-u", "origin", "main", cwd=self.repo)
        self.run_git(
            "symbolic-ref",
            "HEAD",
            "refs/heads/main",
            cwd=self.remote,
        )
        self.run_git("fetch", "origin", cwd=self.repo)
        self.run_git(
            "symbolic-ref",
            "refs/remotes/origin/HEAD",
            "refs/remotes/origin/main",
            cwd=self.repo,
        )
        self.run_git("switch", "-c", "task/size-check", cwd=self.repo)
        self.env = {**os.environ, "HOME": str(self.home)}

    def tearDown(self):
        self.temp.cleanup()

    def run_git(self, *args, cwd, input_data=None):
        result = subprocess.run(
            ["git", *args],
            cwd=cwd,
            check=False,
            capture_output=True,
            text=True,
            input=input_data,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"git {' '.join(args)} failed: {result.stderr}",
        )
        return result.stdout.strip()

    def extend_base(self, contents):
        self.run_git("switch", "main", cwd=self.repo)
        (self.repo / "source.py").write_text(contents, encoding="utf-8")
        self.run_git("add", "source.py", cwd=self.repo)
        self.run_git("commit", "-m", "extend base fixture", cwd=self.repo)
        self.run_git("push", "origin", "main", cwd=self.repo)
        self.run_git("fetch", "origin", cwd=self.repo)
        self.run_git("switch", "task/size-check", cwd=self.repo)
        self.run_git("merge", "--ff-only", "main", cwd=self.repo)

    def invoke(self, *args, cwd=None, expected=0):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *map(str, args)],
            cwd=cwd or self.repo,
            env=self.env,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            result.returncode,
            expected,
            f"command {args!r} returned {result.returncode}: {result.stderr} {result.stdout}",
        )
        if result.stdout:
            return json.loads(result.stdout)
        return None

    def preflight(self, budget=400, expected=0):
        return self.invoke(
            "preflight",
            "--repo",
            self.repo,
            "--line-budget",
            budget,
            "--worker-name",
            "meta-size-test",
            "--task-key",
            "size-test",
            expected=expected,
        )

    def prepare(self, budget=400):
        result = self.invoke(
            "prepare",
            "--repo",
            self.repo,
            "--line-budget",
            budget,
            "--launch-id",
            "01234567-89ab-cdef-0123-456789abcdef",
            "--worker-name",
            "meta-size-test",
            "--task-key",
            "size-test",
            "--owner-name",
            "meta",
            "--owner-pane",
            "owner-pane",
            "--owner-terminal",
            "owner-terminal",
            "--worker-pane",
            "worker-pane",
            "--worker-tab",
            "worker-tab",
            "--worker-terminal",
            "worker-terminal",
        )
        self.invoke(
            "finish",
            "--launch-id",
            "01234567-89ab-cdef-0123-456789abcdef",
            "--worker-pane",
            "worker-pane",
            "--worker-tab",
            "worker-tab",
            "--worker-terminal",
            "worker-terminal",
        )
        return result

    def check(self, *, phase="pre", tool="apply_patch", command="", expected=0):
        return self.invoke(
            "check",
            "--launch-id",
            "01234567-89ab-cdef-0123-456789abcdef",
            "--cwd",
            self.repo,
            "--pane",
            "worker-pane",
            "--tab",
            "worker-tab",
            "--terminal",
            "worker-terminal",
            "--phase",
            phase,
            "--tool-name",
            tool,
            "--command",
            command,
            expected=expected,
        )

    def test_worktree_count_includes_committed_staged_unstaged_and_untracked(self):
        (self.repo / "source.py").write_text("one\ntwo\n", encoding="utf-8")
        self.run_git("add", "source.py", cwd=self.repo)
        self.run_git("commit", "-m", "committed change", cwd=self.repo)
        (self.repo / "source.py").write_text("one\ntwo\nthree\n", encoding="utf-8")
        (self.repo / "new.py").write_text("new\n", encoding="utf-8")

        result = self.preflight()

        self.assertEqual(result["additions"], 3)
        self.assertEqual(result["deletions"], 0)
        self.assertEqual(result["total"], 3)

    def test_staged_worktree_edit_counts_against_merge_base(self):
        (self.repo / "source.py").write_text("staged\n", encoding="utf-8")
        self.run_git("add", "source.py", cwd=self.repo)

        result = self.preflight()

        self.assertEqual((result["additions"], result["deletions"], result["total"]), (1, 1, 2))

    def test_399_400_and_401_lines_use_additions_plus_deletions(self):
        generated = self.repo / "generated.py"
        generated.write_text("x\n" * 399, encoding="utf-8")
        self.assertEqual(self.preflight()["total"], 399)
        generated.write_text("x\n" * 400, encoding="utf-8")
        self.assertEqual(self.preflight()["total"], 400)
        generated.write_text("x\n" * 401, encoding="utf-8")
        result = self.preflight(expected=2)
        self.assertIn("over budget 400", result["error"])

    def test_mixed_diff_budgets_additions_without_deletions(self):
        (self.repo / "source.py").unlink()
        (self.repo / "new.py").write_text("x\n" * 200, encoding="utf-8")

        result = self.preflight()

        self.assertEqual((result["additions"], result["deletions"], result["total"], result["budgeted"]), (200, 1, 201, 200))

    def test_deletions_over_budget_pass_preflight_and_push_gate(self):
        self.extend_base("one\ntwo\nthree\n")
        (self.repo / "source.py").unlink()

        result = self.preflight(budget=1)
        self.assertEqual((result["deletions"], result["budgeted"]), (3, 0))
        self.prepare(budget=1)
        result = self.check()
        self.assertFalse(result["over_budget"])
        self.assertFalse(result["deny"])

    def test_odd_filename_is_counted_without_path_splitting(self):
        name = "line\nbreak\tname.py"
        (self.repo / name).write_text("one\ntwo\n", encoding="utf-8")

        result = self.preflight()

        self.assertEqual(result["total"], 2)
        self.assertIn(name, result["changed_paths"])

    def test_untracked_files_are_counted_by_line(self):
        (self.repo / "untracked.py").write_text("one\ntwo\n", encoding="utf-8")

        result = self.preflight()

        self.assertEqual(result["total"], 2)
        self.assertIn("untracked.py", result["changed_paths"])

    def test_tests_docs_locks_and_test_named_files_count(self):
        for name in ("tests/case.py", "README.md", "uv.lock", "test_core.js", "src/tests/implementation.py"):
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("one\n", encoding="utf-8")

        result = self.preflight()

        self.assertEqual(result["total"], 5)
        self.assertEqual(len(result["changed_paths"]), 5)

    def test_binary_files_count_as_one_line(self):
        binary = self.repo / "binary.dat"
        binary.write_bytes(b"header\x00payload")
        self.run_git("add", "binary.dat", cwd=self.repo)
        self.run_git("commit", "-m", "add binary", cwd=self.repo)
        (self.repo / "untracked-binary.dat").write_bytes(b"other\x00payload")

        result = self.preflight()

        self.assertEqual((result["binary_files"], result["total"], result["budgeted"]), (2, 2, 2))

    def test_untracked_replacement_of_a_base_path_counts_its_contents(self):
        self.run_git("rm", "--cached", "source.py", cwd=self.repo)
        (self.repo / "source.py").write_text("x\n" * 401, encoding="utf-8")

        result = self.preflight(expected=2)

        self.assertIn("initial worktree diff 401 is over budget 400", result["error"])

    def test_override_is_bound_to_the_worker_and_task(self):
        override = self.home / ".local/state/herdr-worker-lifecycle/size-gates/overrides/meta-size-test/size-test.json"
        override.parent.mkdir(parents=True, mode=0o700)
        override.write_text(json.dumps({"budget": 401, "user_approval_reference": "approval-17", "task_key": "size-test", "worker_name": "meta-size-test"}), encoding="utf-8")
        override.chmod(0o600)
        (self.repo / "new.py").write_text("x\n" * 401, encoding="utf-8")

        result = self.preflight(budget=401)

        self.assertEqual(result["total"], 401)
        self.assertEqual(result["override"]["user_approval_reference"], "approval-17")
        override.write_text(json.dumps({"budget": 401, "user_approval_reference": "approval-17", "task_key": "other-task", "worker_name": "meta-size-test"}), encoding="utf-8")
        override.chmod(0o600)

        result = self.preflight(budget=401, expected=2)

        self.assertIn("different task or worker", result["error"])

    def test_stale_worker_identity_fails_closed(self):
        self.prepare()
        record = self.home / ".local/state/herdr-worker-lifecycle/size-gates/01234567-89ab-cdef-0123-456789abcdef.json"
        original = record.read_text(encoding="utf-8")
        for field, value, message in (("pane", "stale-pane", "pane identity"), ("terminal", "stale-terminal", "terminal identity")):
            with self.subTest(field=field):
                data = json.loads(original)
                data["worker"][field] = value
                record.write_text(json.dumps(data), encoding="utf-8")
                record.chmod(0o600)
                result = self.check(expected=2)
                self.assertIn(message, result["error"])

    def test_timed_out_git_check_fails_closed(self):
        self.prepare()
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        fake_git = fake_bin / "git"
        fake_git.write_text("#!/bin/sh\nsleep 20\n", encoding="utf-8")
        fake_git.chmod(0o755)
        self.env["PATH"] = f"{fake_bin}:{self.env['PATH']}"

        result = self.check(expected=2)

        self.assertIn("timed out", result["error"].lower())

    def test_publication_detection_matches_raw_command_regex(self):
        self.prepare()
        cases = (
            ("env prefix", "FOO=bar bash -lc 'git push origin task/size-check'", "absent", 0, None),
            ("bash -lc", 'bash -lc "git push origin task/size-check"', "absent", 0, None),
            ("nested sh -c", "bash -lc \"sh -c 'git push origin task/size-check'\"", "absent", 0, None),
            ("command substitution", "$(git push origin task/size-check)", "absent", 0, None),
            ("git -C", "git -C d push origin task/size-check", "absent", 0, None),
            ("git grep false positive", "git grep push", "absent", 0, None),
            ("git log false positive", "git log --grep push", "absent", 0, None),
            ("push with remote absent", "git push origin task/size-check", "absent", 0, None),
            (
                "push to another remote branch",
                "git push origin HEAD:refs/heads/other-branch",
                "absent",
                0,
                None,
            ),
            ("push with remote behind", "git push origin task/size-check", "behind", 0, None),
            (
                "PR create with remote behind",
                "gh pr create",
                "behind",
                2,
                "branch tip differs",
            ),
            ("PR create with matching remote and dirty worktree", "gh pr create", "matches", 0, None),
        )
        remote_state = "absent"
        for name, command, expected_remote, expected, error in cases:
            with self.subTest(case=name):
                if expected_remote == "behind" and remote_state == "absent":
                    base = self.run_git("rev-parse", "main", cwd=self.repo)
                    self.run_git("push", "origin", f"{base}:refs/heads/task/size-check", cwd=self.repo)
                    (self.repo / "local.py").write_text("local commit\n", encoding="utf-8")
                    self.run_git("add", "local.py", cwd=self.repo)
                    self.run_git("commit", "-m", "advance local task branch", cwd=self.repo)
                    remote_state = "behind"
                elif expected_remote == "matches" and remote_state == "behind":
                    self.run_git("push", "origin", "HEAD:refs/heads/task/size-check", cwd=self.repo)
                    (self.repo / "pending.py").write_text("uncommitted line\n", encoding="utf-8")
                    remote_state = "matches"

                result = self.check(tool="Bash", command=command, expected=expected)
                if error:
                    self.assertIn(error, result["error"])
                else:
                    self.assertFalse(result["deny"])

    def test_pull_request_creation_rejects_a_remote_branch_ahead_of_local_head(self):
        self.prepare()
        self.run_git("push", "-u", "origin", "task/size-check", cwd=self.repo)
        tree = self.run_git("write-tree", cwd=self.repo)
        remote_tip = self.run_git("commit-tree", tree, "-p", "HEAD", "-m", "remote-only commit", cwd=self.repo)
        self.run_git("push", "origin", f"{remote_tip}:refs/heads/task/size-check", cwd=self.repo)

        result = self.check(
            tool="Bash",
            command='/opt/homebrew/bin/gh pr create --title title --body-file /tmp/body.md',
            expected=2,
        )
        self.assertIn("branch tip differs", result["error"])

    def test_staged_and_unstaged_edits_to_one_line_are_not_double_counted(self):
        (self.repo / "source.py").write_text("staged\n", encoding="utf-8")
        self.run_git("add", "source.py", cwd=self.repo)
        (self.repo / "source.py").write_text("unstaged\n", encoding="utf-8")

        result = self.preflight()

        self.assertEqual((result["additions"], result["deletions"], result["total"]), (1, 1, 2))

    def test_deletions_and_new_files_all_count(self):
        (self.repo / "source.py").unlink()
        for name in ("tests/case.py", "README.md", "uv.lock"):
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("content\n", encoding="utf-8")

        result = self.preflight()

        self.assertEqual((result["additions"], result["deletions"], result["total"]), (3, 1, 4))
        self.assertIn("README.md", result["changed_paths"])
        self.assertIn("tests/case.py", result["changed_paths"])
        self.assertIn("uv.lock", result["changed_paths"])


    def test_initial_over_budget_tree_is_rejected_before_record_creation(self):
        (self.repo / "source.py").write_text("one\ntwo\nthree\n", encoding="utf-8")

        result = self.invoke(
            "prepare",
            "--repo",
            self.repo,
            "--line-budget",
            1,
            "--launch-id",
            "01234567-89ab-cdef-0123-456789abcdef",
            "--worker-name",
            "meta-size-test",
            "--task-key",
            "size-test",
            "--owner-name",
            "meta",
            "--owner-pane",
            "owner-pane",
            "--owner-terminal",
            "owner-terminal",
            "--worker-pane",
            "worker-pane",
            "--worker-tab",
            "worker-tab",
            "--worker-terminal",
            "worker-terminal",
            expected=2,
        )

        self.assertIn("over budget", result["error"].lower())
        self.assertFalse(
            (
                self.home
                / ".local"
                / "state"
                / "herdr-worker-lifecycle"
                / "size-gates"
                / "01234567-89ab-cdef-0123-456789abcdef.json"
            ).exists()
        )

    def test_pre_and_post_checks_share_the_same_over_budget_counter(self):
        self.prepare(budget=1)
        (self.repo / "source.py").write_text("one\ntwo\nthree\n", encoding="utf-8")

        post = self.check(phase="post", tool="apply_patch")
        pre = self.check(phase="pre", tool="apply_patch")

        self.assertTrue(post["over_budget"])
        self.assertTrue(pre["deny"])
        self.assertEqual(post["total"], pre["total"])
        self.assertIn("BLOCKED", pre["reason"])

    def test_over_budget_allows_only_literal_worker_report_command(self):
        self.prepare(budget=1)
        (self.repo / "source.py").write_text("one\ntwo\nthree\n", encoding="utf-8")
        report = 'herdr-meta-patrol-queue add --from meta-size-test "BLOCKED meta-size-test: over budget"'
        injected = report + "; touch marker"

        allowed = self.check(phase="pre", tool="Bash", command=report)
        denied = self.check(phase="pre", tool="Bash", command=injected)

        self.assertFalse(allowed["deny"])
        self.assertTrue(denied["deny"])

    def test_unresolved_merge_refuses_count(self):
        oid = self.run_git("hash-object", "-w", "--stdin", cwd=self.repo, input_data="conflict\n")
        self.run_git("update-index", "--force-remove", "--", "source.py", cwd=self.repo)
        self.run_git(
            "update-index",
            "--index-info",
            cwd=self.repo,
            input_data=f"100644 {oid} 1\tsource.py\n100644 {oid} 2\tsource.py\n",
        )
        self.assertIn("source.py", self.run_git("ls-files", "--unmerged", cwd=self.repo))
        result = self.invoke(
            "preflight",
            "--repo",
            self.repo,
            "--line-budget",
            400,
            "--worker-name",
            "meta-size-test",
            "--task-key",
            "size-test",
            expected=2,
        )
        self.assertIn("merge", result["error"].lower())


if __name__ == "__main__":
    unittest.main()
