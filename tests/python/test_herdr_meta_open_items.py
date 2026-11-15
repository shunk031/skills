import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[2] / "skills/herdr/shunk031-herdr-meta-orchestrate/scripts/herdr-meta-open-items.py"


class MetaOpenItemsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.feed = Path(self.temp.name) / "feed"
        self.env = {**os.environ, "INBOX_FEED": str(self.feed)}

    def tearDown(self):
        self.temp.cleanup()

    def run_script(self, *args, succeeds=True):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode == 0, succeeds, result.stderr)
        return result

    def open(self, title="Check a milestone", detail="Verify the exit criteria"):
        return self.run_script(
            "open",
            "--key",
            "root/milestone",
            "--kind",
            "task",
            "--state",
            "blocked",
            "--owner-agent",
            "meta",
            "--title",
            title,
            "--detail",
            detail,
        )

    def test_open_updates_one_durable_feed_item_and_close_removes_it(self):
        self.open()
        self.open(title="Check updated milestone")
        path = self.feed / "meta-open-items.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(data["source"], "meta-open-items")
        self.assertEqual(len(data["entries"]), 1)
        self.assertEqual(data["entries"][0]["title"], "Check updated milestone")
        self.assertEqual(data["entries"][0]["owner"], {"machine": "local", "agent": "meta"})
        self.run_script("close", "--key", "root/milestone")
        self.assertEqual(json.loads(path.read_text(encoding="utf-8"))["entries"], [])

    def test_invalid_input_fails_without_changing_the_source(self):
        self.open()
        before = (self.feed / "meta-open-items.json").read_bytes()
        self.run_script("open", "--key", "bad key", "--kind", "work", "--state", "working", "--owner-agent", "meta", "--title", "x", succeeds=False)
        self.assertEqual((self.feed / "meta-open-items.json").read_bytes(), before)

    def test_default_feed_dir_matches_the_patrol_feed_dir(self):
        self.env.pop("INBOX_FEED")
        self.env["HOME"] = str(Path(self.temp.name) / "home")
        self.open()
        path = Path(self.env["HOME"]) / ".local/state/inbox/feeds/meta-open-items.json"
        self.assertTrue(path.is_file())


if __name__ == "__main__":
    unittest.main()
