#!/usr/bin/env bash

# @file skills/herdr/shunk031-herdr-orchestrate-workers/scripts/herdr-run-failure-watch.sh
# @brief Alert when recent runner states fail or report a missing process.
# @description
#   Reads local state-file globs and optional SSH-host globs, ignoring files
#   older than 12 hours. Failed jobs are recent for three hours. Run with
#   --once for a foreground health check before backgrounding. Remote reads
#   use SSH, find, and cat on the remote host.
# @option --state-glob GLOB Local state-file glob; repeat to watch more paths.
# @option --remote-host HOST Optional SSH destination for remote state files.
# @option --remote-port PORT SSH port (default: 22).
# @option --remote-state-glob GLOB Remote state-file glob; requires --remote-host.
# @option --interval-seconds N Poll interval in seconds (default: 600).
# @option --once Check one cycle and exit.
# @option --help Show usage.

if ! command -v python3 > /dev/null; then
    printf '%s\n' 'runner failure watcher: python3 is required' >&2
    exit 127
fi

exec python3 - "$@" << 'PYTHON'
import argparse
import errno
import glob
import json
import os
import re
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone

STATE_FILE_MAX_AGE_SECONDS = 12 * 60 * 60
FAILED_JOB_MAX_AGE_SECONDS = 3 * 60 * 60


def parse_args():
    parser = argparse.ArgumentParser(
        description="Watch runner state files for recent failures and dead PIDs.",
        epilog="Remote state globs require SSH access and find/cat on the remote host.",
    )
    parser.add_argument("--state-glob", action="append", default=[], metavar="GLOB")
    parser.add_argument("--remote-host")
    parser.add_argument("--remote-port", type=int, default=22)
    parser.add_argument("--remote-state-glob", action="append", default=[], metavar="GLOB")
    parser.add_argument("--interval-seconds", type=int, default=600)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    if not args.state_glob and not args.remote_state_glob:
        parser.error("provide at least one --state-glob or --remote-state-glob")
    if args.remote_state_glob and not args.remote_host:
        parser.error("--remote-state-glob requires --remote-host")
    if args.remote_host and not args.remote_state_glob:
        parser.error("--remote-host requires at least one --remote-state-glob")
    if not args.remote_host and args.remote_port != 22:
        parser.error("--remote-port requires --remote-host")
    if args.remote_host and (args.remote_host.startswith("-") or any(ch.isspace() for ch in args.remote_host)):
        parser.error("--remote-host must be a single SSH destination")
    if not 1 <= args.remote_port <= 65535:
        parser.error("--remote-port must be between 1 and 65535")
    if args.interval_seconds < 1:
        parser.error("--interval-seconds must be a positive integer")
    for pattern in args.state_glob + args.remote_state_glob:
        if "\n" in pattern or "\r" in pattern:
            parser.error("state-file globs must not contain line breaks")
    return args


def recent_files(patterns, now_epoch):
    contents = []
    seen = set()
    for pattern in patterns:
        for path in glob.glob(os.path.expanduser(pattern), recursive=True):
            if path in seen:
                continue
            seen.add(path)
            try:
                if not os.path.isfile(path) or now_epoch - os.path.getmtime(path) > STATE_FILE_MAX_AGE_SECONDS:
                    continue
                with open(path, "r", encoding="utf-8") as source:
                    contents.append(source.read())
            except (OSError, UnicodeError):
                continue
    return contents


def ssh(host, port, command):
    result = subprocess.run(
        [
            "ssh", "-T", "-p", str(port), "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=2", "-o", "LogLevel=ERROR", host, command,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        detail = result.stderr.strip() or "SSH command failed"
        raise RuntimeError(detail)
    return result.stdout


def remote_find_command(pattern):
    normalized = pattern
    if not normalized.startswith(("/", "./")):
        normalized = "./" + normalized
    match = re.search(r"[*?\[]", normalized)
    literal_prefix = normalized[: match.start()] if match else normalized
    if literal_prefix.endswith(os.sep):
        root = literal_prefix.rstrip(os.sep) or os.sep
    else:
        root = os.path.dirname(literal_prefix) or "."
    find = (
        "find {} -type f -path {} -mmin -720 -exec sh -c {} sh {{}} + 2>/dev/null"
    ).format(
        shlex.quote(root),
        shlex.quote(normalized),
        shlex.quote('for f do printf "\\000"; cat "$f"; done'),
    )
    return "sh -c " + shlex.quote(find)


def remote_files(host, port, patterns):
    contents = []
    for pattern in patterns:
        output = ssh(host, port, remote_find_command(pattern))
        contents.extend(output.split("\0")[1:])
    return contents


def json_values(text):
    decoder = json.JSONDecoder()
    index = 0
    while index < len(text):
        while index < len(text) and text[index] not in "{[":
            index += 1
        if index >= len(text):
            return
        try:
            value, next_index = decoder.raw_decode(text, index)
        except json.JSONDecodeError:
            index += 1
            continue
        index = next_index
        yield value


def failed_recently(job, now):
    for key in ("finished_at_utc", "finished_at"):
        value = job.get(key)
        if not value:
            continue
        try:
            timestamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if timestamp.tzinfo is None:
                timestamp = timestamp.replace(tzinfo=timezone.utc)
            age = (now - timestamp.astimezone(timezone.utc)).total_seconds()
            return 0 <= age < FAILED_JOB_MAX_AGE_SECONDS
        except (AttributeError, TypeError, ValueError):
            return False
    return False


def inspect_states(source, contents, ignored, now):
    alerts = []
    running = []
    for content in contents:
        for document in json_values(content):
            if not isinstance(document, dict):
                continue
            jobs = document.get("jobs", document)
            if not isinstance(jobs, dict):
                continue
            for name, job in jobs.items():
                if not isinstance(name, str) or name in ignored or not isinstance(job, dict):
                    continue
                status = job.get("status", "")
                if status == "failed" and failed_recently(job, now):
                    alerts.append("ALERT {} {} status=failed exit={}".format(source, name, job.get("exit_code")))
                elif status == "running":
                    pid = job.get("pid")
                    if isinstance(pid, bool) or not (
                        isinstance(pid, int) or (isinstance(pid, str) and re.fullmatch(r"[0-9]+", pid))
                    ):
                        continue
                    try:
                        pid = str(int(pid))
                    except (OverflowError, ValueError):
                        continue
                    if int(pid) > 0:
                        running.append((name, pid))
    return alerts, running


def pid_exists(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError as error:
        return error.errno != errno.ESRCH
    except OverflowError:
        return False


def remote_alive_pids(host, port, pids):
    if not pids:
        return set()
    check = (
        "for p in " + " ".join(pids)
        + '; do if kill -0 "$p" 2>/dev/null; then printf \'%s\\n\' "$p"; fi; done'
    )
    return set(ssh(host, port, "sh -c " + shlex.quote(check)).split())


def sample(args, ignored):
    now_epoch = time.time()
    now = datetime.now(timezone.utc)
    local_contents = recent_files(args.state_glob, now_epoch)
    remote_contents = remote_files(args.remote_host, args.remote_port, args.remote_state_glob) if args.remote_host else []

    alerts, local_running = inspect_states("LOCAL", local_contents, ignored, now)
    remote_alerts, remote_running = inspect_states("REMOTE", remote_contents, ignored, now)
    alerts.extend(remote_alerts)

    for name, pid in local_running:
        if not pid_exists(pid):
            alerts.append("ALERT LOCAL {} marked running but PID {} is gone".format(name, pid))

    if args.remote_host and remote_running:
        remote_pids = sorted({pid for name, pid in remote_running})
        alive = remote_alive_pids(args.remote_host, args.remote_port, remote_pids)
        for name, pid in remote_running:
            if pid not in alive:
                alerts.append("ALERT REMOTE {} marked running but PID {} is gone".format(name, pid))

    return alerts, len(local_contents), len(remote_contents)


def main():
    args = parse_args()
    ignored = {name.strip() for name in os.environ.get("WATCH_IGNORE", "").split(",") if name.strip()}
    while True:
        try:
            alerts, local_file_count, remote_file_count = sample(args, ignored)
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            print("runner failure watcher: {}".format(error), file=sys.stderr)
            return 1
        if alerts:
            print(datetime.now().astimezone().isoformat(timespec="seconds"), flush=True)
            for alert in alerts:
                print(alert, flush=True)
            return 3 if args.once else 0
        if args.once:
            if args.state_glob and local_file_count == 0:
                print("runner failure watcher: no recent local state files matched the configured globs", file=sys.stderr)
                return 1
            if args.remote_host and remote_file_count == 0:
                print("runner failure watcher: no recent remote state files matched the configured globs", file=sys.stderr)
                return 1
            print(
                "OK: checked {} local and {} remote recent state file(s); no recent failures or dead PIDs.".format(
                    local_file_count, remote_file_count
                ),
                flush=True,
            )
            return 0
        time.sleep(args.interval_seconds)


if __name__ == "__main__":
    raise SystemExit(main())
PYTHON
