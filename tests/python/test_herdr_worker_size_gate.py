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

    def test_preflight_does_not_write_to_the_real_object_store(self):
        objects = Path(self.run_git("rev-parse", "--git-path", "objects", cwd=self.repo))
        if not objects.is_absolute():
            objects = self.repo / objects
        before = {path.relative_to(objects) for path in objects.rglob("*") if path.is_file()}

        self.preflight()

        after = {path.relative_to(objects) for path in objects.rglob("*") if path.is_file()}
        self.assertEqual(after, before)

    def test_399_400_and_401_lines_use_additions_plus_deletions(self):
        generated = self.repo / "generated.py"
        generated.write_text("x\n" * 399, encoding="utf-8")
        self.assertEqual(self.preflight()["total"], 399)
        generated.write_text("x\n" * 400, encoding="utf-8")
        self.assertEqual(self.preflight()["total"], 400)
        generated.write_text("x\n" * 401, encoding="utf-8")
        result = self.preflight(expected=2)
        self.assertIn("over budget 400", result["error"])

    def test_200_additions_and_201_deletions_are_not_netted(self):
        (self.repo / "source.py").unlink()
        (self.repo / "new.py").write_text("x\n" * 200, encoding="utf-8")

        result = self.preflight()

        self.assertEqual((result["additions"], result["deletions"], result["total"]), (200, 1, 201))

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
