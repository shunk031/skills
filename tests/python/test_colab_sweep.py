from __future__ import annotations

import argparse
import importlib.machinery
import importlib.util
import io
import sys
import types
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "skills/colab/shunk031-colab-uv-training/scripts/colab-sweep"


def load_module():
    # The script has no `.py` suffix, so it needs an explicit source loader.
    # Bytecode would otherwise land in the skill's own `scripts/` directory.
    sys.dont_write_bytecode = True
    loader = importlib.machinery.SourceFileLoader("colab_sweep", str(SCRIPT_PATH))
    spec = importlib.util.spec_from_loader("colab_sweep", loader)
    if spec is None:
        raise RuntimeError(f"Failed to load module from {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


colab_sweep = load_module()


def fake_colab_cli(
    endpoints: list[str],
) -> tuple[dict[str, types.ModuleType], mock.Mock]:
    """Return stub `colab_cli` modules whose client lists `endpoints`."""
    client = mock.Mock()
    client.list_assignments.return_value = [
        mock.Mock(endpoint=endpoint, accelerator=mock.Mock(value="A100"))
        for endpoint in endpoints
    ]
    common = types.ModuleType("colab_cli.common")
    common.state = mock.Mock(client=client)
    package = types.ModuleType("colab_cli")
    return {"colab_cli": package, "colab_cli.common": common}, client


class ColabSweepTest(unittest.TestCase):
    def test_parse_duration(self) -> None:
        self.assertEqual(colab_sweep.parse_duration("90m"), 5400)
        self.assertEqual(colab_sweep.parse_duration("2d"), 172800)
        with self.assertRaises(argparse.ArgumentTypeError):
            colab_sweep.parse_duration("1.5h")

    def test_due_orphans_waits_for_grace_and_skips_owned(self) -> None:
        due, seen = colab_sweep.due_orphans(
            ["owned", "old", "new"],
            {"owned"},
            {"old": 0.0, "gone": 0.0},
            now=1800.0,
            grace=1800,
        )

        self.assertEqual(due, ["old"])
        self.assertEqual(seen, {"old": 0.0, "new": 1800.0})

    def test_owned_sessions_include_registered_state_files(self) -> None:
        with TemporaryDirectory() as tmp:
            config = Path(tmp)
            (config / "states").mkdir()
            (config / "sessions.json").write_text('{"a": {"endpoint": "e1"}}')
            (config / "states" / "job.json").write_text('{"b": {"endpoint": "e2"}}')

            owned = {
                endpoint
                for path in colab_sweep.state_files(config)
                for endpoint in colab_sweep.read_sessions(path).values()
            }

        self.assertEqual(owned, {"e1", "e2"})

    def test_corrupt_state_file_raises_instead_of_reading_empty(self) -> None:
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "sessions.json"
            path.write_text("{not json")

            with self.assertRaises(ValueError):
                colab_sweep.read_sessions(path)

    def test_lease_rejects_path_names_and_records_expiry(self) -> None:
        with (
            TemporaryDirectory() as tmp,
            mock.patch.object(colab_sweep, "STATE_DIR", Path(tmp)),
            redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(colab_sweep.lease("../escape", 60), 2)
            self.assertEqual(colab_sweep.lease("job", 60), 0)

            expiry = int((Path(tmp) / "leases" / "job").read_text())

        self.assertGreater(expiry, 0)

    def test_dry_run_reports_orphans_without_unassigning_or_writing(self) -> None:
        modules, client = fake_colab_cli(["orphan"])
        with TemporaryDirectory() as tmp:
            state_dir = Path(tmp) / "state"
            state_dir.mkdir()
            (state_dir / "state.json").write_text('{"orphan": 0.0}')
            with (
                mock.patch.dict(sys.modules, modules),
                mock.patch.object(colab_sweep, "STATE_DIR", state_dir),
                mock.patch.object(
                    colab_sweep, "COLAB_CONFIG_DIR", Path(tmp) / "config"
                ),
                redirect_stdout(io.StringIO()) as out,
            ):
                status = colab_sweep.sweep(dry_run=True, grace=60)

            files = sorted(p.name for p in state_dir.iterdir())

        self.assertEqual(status, 0)
        self.assertIn("dry-run: would unassign orphan orphan", out.getvalue())
        client.unassign.assert_not_called()
        self.assertEqual(files, ["state.json"])

    def test_sweep_unassigns_only_orphans_past_grace(self) -> None:
        modules, client = fake_colab_cli(["owned", "old", "new"])
        with TemporaryDirectory() as tmp:
            config = Path(tmp) / "config"
            config.mkdir()
            (config / "sessions.json").write_text('{"job": {"endpoint": "owned"}}')
            state_dir = Path(tmp) / "state"
            state_dir.mkdir()
            (state_dir / "state.json").write_text('{"old": 0.0}')
            with (
                mock.patch.dict(sys.modules, modules),
                mock.patch.object(colab_sweep, "STATE_DIR", state_dir),
                mock.patch.object(colab_sweep, "COLAB_CONFIG_DIR", config),
                redirect_stdout(io.StringIO()),
            ):
                status = colab_sweep.sweep(dry_run=False, grace=60)

        self.assertEqual(status, 0)
        client.unassign.assert_called_once_with("old")

    def test_released_or_pruned_session_loses_its_lease(self) -> None:
        modules, client = fake_colab_cli(["live"])
        with TemporaryDirectory() as tmp:
            config = Path(tmp) / "config"
            config.mkdir()
            (config / "sessions.json").write_text(
                '{"gone": {"endpoint": "released"}, "job": {"endpoint": "live"}}'
            )
            leases = Path(tmp) / "state" / "leases"
            leases.mkdir(parents=True)
            (leases / "gone").write_text("9999999999\n")
            (leases / "job").write_text("9999999999\n")
            (leases / "pruned").write_text("9999999999\n")
            with mock.patch.dict(sys.modules, modules), mock.patch.object(
                colab_sweep, "STATE_DIR", leases.parent
            ), mock.patch.object(colab_sweep, "COLAB_CONFIG_DIR", config):
                with redirect_stdout(io.StringIO()) as dry:
                    dry_status = colab_sweep.sweep(dry_run=True, grace=60)
                dry_leases = sorted(p.name for p in leases.iterdir())
                with redirect_stdout(io.StringIO()) as real:
                    status = colab_sweep.sweep(dry_run=False, grace=60)
                remaining = sorted(p.name for p in leases.iterdir())
            state = (config / "sessions.json").read_text()

        self.assertEqual((dry_status, status), (0, 0))
        self.assertIn("stale released session=gone", dry.getvalue())
        self.assertIn("colab sessions", dry.getvalue())
        self.assertEqual(dry_leases, ["gone", "job", "pruned"])
        self.assertIn("lease gone: session no longer assigned; remove lease", real.getvalue())
        self.assertIn("lease pruned: session not recorded; remove lease", real.getvalue())
        self.assertEqual(remaining, ["job"])
        self.assertIn("released", state)
        client.unassign.assert_not_called()


if __name__ == "__main__":
    unittest.main()
