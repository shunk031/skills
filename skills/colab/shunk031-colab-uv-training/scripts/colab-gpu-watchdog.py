#!/usr/bin/env python3
"""Stop only the named Colab session whose recorded endpoint stays idle."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

POLL_SECONDS = 15
COMMAND_TIMEOUT_SECONDS = 30


def parse_status(output: str, name: str):
    """Return this session's endpoint and state, or gone/unknown."""
    if f"Session '{name}' not found." in output:
        return "gone", None
    prefix = f"[{name}] "
    for line in output.splitlines():
        if not line.startswith(prefix):
            continue
        details = line[len(prefix) :]
        if " | Status: " not in details:
            return "unknown", None
        endpoint, status = details.split(" | Status: ", 1)
        endpoint = endpoint.split(" | ", 1)[0]
        if status == "IDLE":
            return "idle", endpoint
        if status.startswith("BUSY (") and status.endswith(")"):
            return "busy", endpoint
        return "unknown", endpoint
    return "unknown", None


def session_endpoint(config: Path, name: str):
    """Read the endpoint recorded by colab new for this unique name."""
    try:
        with config.open(encoding="utf-8") as state_file:
            session = json.load(state_file).get(name)
    except (OSError, json.JSONDecodeError, AttributeError):
        return None
    if not isinstance(session, dict):
        return None
    endpoint = session.get("endpoint")
    return endpoint if isinstance(endpoint, str) and endpoint else None


def session_record(config: Path, name: str):
    try:
        with config.open(encoding="utf-8") as state_file:
            session = json.load(state_file).get(name)
    except (OSError, json.JSONDecodeError, AttributeError):
        return None
    return session if isinstance(session, dict) else None


def handoff_record(path: Path, name: str):
    try:
        with path.open(encoding="utf-8") as handoff_file:
            handoff = json.load(handoff_file)
    except (OSError, json.JSONDecodeError, AttributeError):
        return None
    if not isinstance(handoff, dict) or handoff.get("name") != name:
        return None
    session = handoff.get("session")
    return session if isinstance(session, dict) else None


def write_recovery_config(path: Path, name: str, session: dict):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as recovery_file:
        json.dump({name: session}, recovery_file)
        recovery_file.flush()
        os.fsync(recovery_file.fileno())
    temporary.chmod(0o600)
    os.replace(temporary, path)


def colab_command(config: Path, *args: str):
    return ["colab", "--config", str(config), *args]


def read_status(config: Path, name: str):
    try:
        result = subprocess.run(
            colab_command(config, "status", "-s", name),
            check=False,
            capture_output=True,
            text=True,
            timeout=COMMAND_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return "unknown", None, str(error)
    state, endpoint = parse_status(result.stdout + result.stderr, name)
    if result.returncode and state != "gone":
        return "unknown", endpoint, f"colab status exited {result.returncode}"
    return state, endpoint, ""


def stop_session(config: Path, name: str):
    try:
        result = subprocess.run(
            colab_command(config, "stop", "-s", name),
            check=False,
            capture_output=True,
            text=True,
            timeout=COMMAND_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return False, str(error)
    return result.returncode == 0, result.stderr.strip()


def log(message: str):
    print(f"colab-gpu-watchdog: {message}", flush=True)


def remove_file(path: Path):
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def run(args):
    config = Path(args.config).expanduser()
    started_at = time.monotonic()
    idle_since = None
    endpoint = None
    active_config = config
    stop_requested = False
    Path(args.started_file).touch(mode=0o600, exist_ok=True)
    log(f"started for {args.session}; waiting for its local endpoint record")

    while True:
        now = time.monotonic()
        if endpoint is None:
            session = session_record(config, args.session)
            if session is None:
                session = handoff_record(Path(args.handoff_file), args.session)
                if session:
                    active_config = Path(args.recovery_config).expanduser()
                    write_recovery_config(active_config, args.session, session)
            else:
                active_config = config
            endpoint = session.get("endpoint") if session else None
            if session and (session.get("name") != args.session or not isinstance(endpoint, str) or not endpoint):
                session = None
                endpoint = None
            if endpoint:
                Path(args.ready_file).touch(mode=0o600, exist_ok=True)
                log(f"watching {args.session} at its recorded endpoint")

        if endpoint is None:
            log(f"waiting for the local endpoint record for {args.session}")
            time.sleep(args.poll_interval)
            continue

        state, observed_endpoint, error = read_status(active_config, args.session)
        if state == "gone":
            log(f"{args.session} is gone")
            remove_file(Path(args.handoff_file))
            if active_config != config:
                remove_file(active_config)
            return 0
        if error:
            idle_since = None
            log(f"status check failed: {error}")
        elif observed_endpoint != endpoint:
            log(f"endpoint mismatch for {args.session}; leaving the other session untouched")
            return 0
        elif state == "idle":
            if idle_since is None:
                idle_since = now
        elif state == "busy":
            idle_since = None
        else:
            idle_since = None
            log(f"unrecognized status for {args.session}; leaving the session running")

        elapsed = now - started_at
        reason = None
        if elapsed >= args.wall_timeout:
            reason = f"wall timeout ({args.wall_timeout}s)"
        elif idle_since is not None and now - idle_since >= args.idle_timeout:
            reason = f"idle timeout ({args.idle_timeout}s)"

        if reason and not stop_requested:
            confirm_state, confirm_endpoint, confirm_error = read_status(active_config, args.session)
            if confirm_state == "gone":
                log(f"{args.session} is gone")
                remove_file(Path(args.handoff_file))
                if active_config != config:
                    remove_file(active_config)
                return 0
            if confirm_endpoint is not None and confirm_endpoint != endpoint:
                log(f"endpoint mismatch for {args.session}; leaving the other session untouched")
                return 0
            if confirm_error:
                if reason.startswith("idle timeout"):
                    log(f"cannot verify idle stop target: {confirm_error}")
                elif session_endpoint(active_config, args.session) == endpoint:
                    log(f"status is unavailable at the wall limit; using the unchanged local session identity: {confirm_error}")
                    stopped, stop_error = stop_session(active_config, args.session)
                    if stopped:
                        stop_requested = True
                        log(f"requested stop for {args.session} at its verified endpoint: {reason}")
                    else:
                        log(f"stop failed for {args.session}: {stop_error or 'unknown error'}")
                else:
                    log(f"local endpoint changed for {args.session}; leaving the other session untouched")
                    return 0
            elif confirm_endpoint != endpoint:
                log(f"endpoint mismatch for {args.session}; leaving the other session untouched")
                return 0
            elif reason.startswith("idle timeout") and confirm_state != "idle":
                idle_since = None
            elif session_endpoint(active_config, args.session) != endpoint:
                log(f"local endpoint changed for {args.session}; leaving the other session untouched")
                return 0
            else:
                stopped, stop_error = stop_session(active_config, args.session)
                if stopped:
                    stop_requested = True
                    log(f"requested stop for {args.session} at its verified endpoint: {reason}")
                else:
                    log(f"stop failed for {args.session}: {stop_error or 'unknown error'}")

        time.sleep(args.poll_interval)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--handoff-file", required=True)
    parser.add_argument("--recovery-config", required=True)
    parser.add_argument("--idle-timeout", type=float, required=True)
    parser.add_argument("--wall-timeout", type=float, required=True)
    parser.add_argument("--started-file", required=True)
    parser.add_argument("--ready-file", required=True)
    parser.add_argument("--poll-interval", type=float, default=POLL_SECONDS)
    args = parser.parse_args()
    if args.idle_timeout <= 0 or args.wall_timeout <= 0 or args.poll_interval <= 0:
        parser.error("timeouts and polling interval must be positive")
    os.umask(0o077)
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
