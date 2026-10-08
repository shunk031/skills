import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


WATCHDOG = (
    Path(__file__).parents[2]
    / "skills"
    / "colab"
    / "shunk031-colab-uv-training"
    / "scripts"
    / "colab-gpu-watchdog.py"
)


class ColabGpuWatchdogTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.config = self.root / "sessions.json"
        self.session = "cgr-test"
        self.endpoint = "endpoint-test"
        self.config.write_text(
            json.dumps({self.session: {"name": self.session, "endpoint": self.endpoint}}), encoding="utf-8"
        )
        self.status = self.root / "status"
        self.status.write_text("idle", encoding="utf-8")
        self.stops = self.root / "stops"
        self.colab_log = self.root / "colab.log"
        self.ready = self.root / "ready"
        self.handoff = self.root / "handoff.json"
        self.recovery = self.root / "recovery.json"
        self.stub = self.bin / "colab"
        self.stub.write_text(
            """#!/usr/bin/env python3
import os
import sys
from pathlib import Path

args = sys.argv[1:]
if args[:1] != ['--config']:
    raise SystemExit(90)
config = args[1]
with open(os.environ['COLAB_LOG'], 'a', encoding='utf-8') as output:
    output.write(config + '\\n')
args = args[2:]
command = args.pop(0)
if command == 'status':
    name = args[args.index('-s') + 1]
    mode = Path(os.environ['COLAB_STATUS']).read_text().strip()
    if mode == 'gone':
        print(f\"[colab] Session '{name}' not found.\")
    elif mode == 'error':
        print('temporary status failure', file=sys.stderr)
        raise SystemExit(42)
    elif mode == 'wrong-endpoint':
        print(f'[{name}] other-endpoint | Hardware: A100 | Shape: Standard | Variant: GPU | Status: IDLE')
        print('[another-session] other-session-endpoint | Hardware: A100 | Shape: Standard | Variant: GPU | Status: IDLE')
    elif mode == 'wrong-endpoint-error':
        print(f'[{name}] other-endpoint | Hardware: A100 | Shape: Standard | Variant: GPU | Status: IDLE')
        raise SystemExit(42)
    else:
        state = 'BUSY (exec(job.py))' if mode == 'busy' else 'IDLE'
        print(f'[{name}] endpoint-test | Hardware: A100 | Shape: Standard | Variant: GPU | Status: {state}')
elif command == 'stop':
    name = args[args.index('-s') + 1]
    with open(os.environ['COLAB_STOPS'], 'a', encoding='utf-8') as stops:
        stops.write(name + '\\n')
    Path(os.environ['COLAB_STATUS']).write_text('gone')
else:
    raise SystemExit(91)
""",
            encoding="utf-8",
        )
        self.stub.chmod(0o755)
        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.bin}:{self.env['PATH']}"
        self.env["COLAB_STATUS"] = str(self.status)
        self.env["COLAB_STOPS"] = str(self.stops)
        self.env["COLAB_LOG"] = str(self.colab_log)

    def tearDown(self):
        self.temp.cleanup()

    def run_watchdog(self, idle, wall):
        return subprocess.run(
            [
                "python3",
                str(WATCHDOG),
                "--session",
                self.session,
                "--config",
                str(self.config),
                "--handoff-file",
                str(self.handoff),
                "--recovery-config",
                str(self.recovery),
                "--idle-timeout",
                str(idle),
                "--wall-timeout",
                str(wall),
                "--started-file",
                str(self.root / "started"),
                "--ready-file",
                str(self.ready),
                "--poll-interval",
                "0.01",
            ],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )

    def test_stops_exact_session_after_idle_limit(self):
        started = time.monotonic()
        result = self.run_watchdog(idle=0.08, wall=2)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertGreaterEqual(time.monotonic() - started, 0.08)
        self.assertEqual(self.stops.read_text(encoding="utf-8").splitlines(), [self.session])

    def test_stops_exact_session_at_wall_limit_even_when_busy(self):
        self.status.write_text("busy", encoding="utf-8")

        result = self.run_watchdog(idle=2, wall=0.08)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.stops.read_text(encoding="utf-8").splitlines(), [self.session])

    def test_stops_at_wall_limit_when_status_is_unavailable(self):
        self.status.write_text("error", encoding="utf-8")
        started = time.monotonic()

        result = self.run_watchdog(idle=0.03, wall=0.08)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertGreaterEqual(time.monotonic() - started, 0.08)
        self.assertEqual(self.stops.read_text(encoding="utf-8").splitlines(), [self.session])
        self.assertIn("wall timeout", result.stdout)

    def test_wrong_endpoint_is_never_stopped_when_status_exits_with_error(self):
        self.status.write_text("wrong-endpoint-error", encoding="utf-8")

        result = self.run_watchdog(idle=0.01, wall=0.08)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.stops.exists())
        self.assertIn("endpoint mismatch", result.stdout)

    def test_handoff_recovers_when_colab_did_not_write_its_session_state(self):
        self.config.write_text("{}", encoding="utf-8")
        session = {
            "name": self.session,
            "token": "runtime-token",
            "url": "https://runtime.example",
            "endpoint": self.endpoint,
            "variant": "GPU",
            "accelerator": "A100",
            "machine_shape": "STANDARD",
        }
        self.handoff.write_text(
            json.dumps({"name": self.session, "session": session}), encoding="utf-8"
        )

        result = self.run_watchdog(idle=0.08, wall=2)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.stops.read_text(encoding="utf-8").splitlines(), [self.session])
        self.assertIn(str(self.recovery), self.colab_log.read_text(encoding="utf-8"))
        self.assertFalse(self.handoff.exists())
        self.assertFalse(self.recovery.exists())

    def test_colab_state_write_records_handoff_before_original_write(self):
        helper = WATCHDOG.with_name("colab-gpu-sitecustomize.py")
        module_dir = self.root / "python"
        package = module_dir / "colab_cli"
        package.mkdir(parents=True)
        (package / "__init__.py").write_text("", encoding="utf-8")
        (package / "state.py").write_text(
            "class StateStore:\n"
            "    def add(self, session):\n"
            "        raise OSError('simulated local state failure')\n",
            encoding="utf-8",
        )
        (module_dir / "sitecustomize.py").write_text(
            helper.read_text(encoding="utf-8"), encoding="utf-8"
        )
        handoff = self.root / "captured-handoff.json"
        env = self.env.copy()
        env["PYTHONPATH"] = str(module_dir)
        env["COLAB_GPU_HANDOFF_FILE"] = str(handoff)
        env["COLAB_GPU_HANDOFF_SESSION"] = self.session
        result = subprocess.run(
            [
                "python3",
                "-c",
                "from colab_cli.state import StateStore\n"
                "class Session:\n"
                "    name = 'cgr-test'\n"
                "    def model_dump(self, mode):\n"
                "        return {'name': self.name, 'endpoint': 'endpoint-test'}\n"
                "try:\n"
                "    StateStore().add(Session())\n"
                "except OSError:\n"
                "    pass\n",
            ],
            env=env,
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(handoff.read_text(encoding="utf-8")),
            {"name": self.session, "session": {"name": self.session, "endpoint": self.endpoint}},
        )

    def test_endpoint_mismatch_never_stops_another_session(self):
        self.status.write_text("wrong-endpoint", encoding="utf-8")

        result = self.run_watchdog(idle=0.01, wall=2)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.stops.exists())
        self.assertIn("leaving the other session untouched", result.stdout)

    def test_exits_when_session_disappears(self):
        self.status.write_text("gone", encoding="utf-8")

        result = self.run_watchdog(idle=1, wall=2)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.stops.exists())
        self.assertIn("is gone", result.stdout)


if __name__ == "__main__":
    unittest.main()
