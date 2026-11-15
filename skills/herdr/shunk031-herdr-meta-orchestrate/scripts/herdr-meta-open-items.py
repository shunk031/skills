#!/usr/bin/env python3
"""Maintain Meta's durable open-items file in the Inbox feed directory."""

import argparse
import fcntl
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path
from typing import NoReturn


SOURCE = "meta-open-items"
MAX_ENTRIES = 40
KEY = re.compile(r"^[A-Za-z0-9._/-]{1,100}$")
AGENT = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")


def fail(message: str) -> NoReturn:
    print(f"herdr-meta-open-items: {message}", file=sys.stderr)
    raise SystemExit(2)


def feed_paths(feed_dir: Path) -> tuple[Path, Path]:
    return feed_dir / "meta-open-items.json", feed_dir / ".meta-open-items.lock"


def read_items(path: Path) -> dict[str, object]:
    if not path.exists():
        return {"version": 1, "source": SOURCE, "writtenAt": 0, "entries": []}
    if path.stat().st_size > 256 * 1024:
        fail("active-items file is larger than 256 KiB")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"cannot read the active-items file: {error}")
    if (
        not isinstance(data, dict)
        or data.get("version") != 1
        or data.get("source") != SOURCE
        or not isinstance(data.get("writtenAt"), (int, float))
        or not isinstance(data.get("entries"), list)
        or len(data["entries"]) > MAX_ENTRIES
    ):
        fail("active-items file has an unsupported shape")
    keys: set[str] = set()
    for entry in data["entries"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("key"), str) or not KEY.fullmatch(entry["key"]):
            fail("active-items file has an invalid key")
        owner = entry.get("owner")
        if (
            entry.get("kind") not in ("work", "task")
            or entry.get("state") not in ("working", "blocked")
            or not isinstance(entry.get("title"), str)
            or not entry["title"].strip()
            or len(entry["title"]) > 120
            or not isinstance(entry.get("detail"), str)
            or len(entry["detail"]) > 600
            or not isinstance(entry.get("at"), (int, float))
            or not isinstance(owner, dict)
            or not isinstance(owner.get("machine"), str)
            or not isinstance(owner.get("agent"), str)
            or ("signalKey" in entry and (not isinstance(entry["signalKey"], str) or not KEY.fullmatch(entry["signalKey"])))
        ):
            fail("active-items file has an invalid entry")
        if entry["key"] in keys:
            fail("active-items file has duplicate keys")
        keys.add(entry["key"])
    return data


def write_items(path: Path, data: dict[str, object]) -> None:
    data["writtenAt"] = int(time.time() * 1000)
    fd, temporary = tempfile.mkstemp(prefix=".meta-open-items.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def open_item(args: argparse.Namespace, data: dict[str, object]) -> None:
    if not KEY.fullmatch(args.key):
        fail("key must use letters, digits, dot, underscore, slash or hyphen and be at most 100 characters")
    if not AGENT.fullmatch(args.owner_agent):
        fail("owner-agent is not a valid Herdr agent name")
    if len(args.owner_machine) > 80 or not args.owner_machine or any(c in args.owner_machine for c in "\t\r\n/"):
        fail("owner-machine must be a non-empty machine label without slashes or newlines")
    if not args.title.strip() or len(args.title) > 120 or len(args.detail) > 600:
        fail("title must be 1–120 characters and detail at most 600 characters")
    entries = data["entries"]
    assert isinstance(entries, list)
    entry = {
        "key": args.key,
        "kind": args.kind,
        "state": args.state,
        "title": args.title.strip(),
        "detail": args.detail.strip(),
        "at": int(time.time() * 1000),
        "owner": {"machine": args.owner_machine, "agent": args.owner_agent},
    }
    if args.signal_key:
        if not KEY.fullmatch(args.signal_key):
            fail("signal-key must use letters, digits, dot, underscore, slash or hyphen and be at most 100 characters")
        entry["signalKey"] = args.signal_key
    existing = next((i for i, old in enumerate(entries) if old["key"] == args.key), None)
    if existing is None:
        if len(entries) >= MAX_ENTRIES:
            fail(f"active-items file already has {MAX_ENTRIES} entries")
        entries.append(entry)
    else:
        entries[existing] = entry
    entries.sort(key=lambda item: item["key"])


def close_item(args: argparse.Namespace, data: dict[str, object]) -> None:
    if not KEY.fullmatch(args.key):
        fail("key must use letters, digits, dot, underscore, slash or hyphen and be at most 100 characters")
    entries = data["entries"]
    assert isinstance(entries, list)
    data["entries"] = [entry for entry in entries if entry["key"] != args.key]


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    default_feed_dir = os.environ.get("INBOX_FEED", str(Path.home() / ".local/state/inbox/feeds"))
    root.add_argument("--feed-dir", default=default_feed_dir, help="Inbox feed directory; defaults to INBOX_FEED or ~/.local/state/inbox/feeds")
    commands = root.add_subparsers(dest="command", required=True)
    open_parser = commands.add_parser("open", help="add or update one active work item")
    open_parser.add_argument("--key", required=True)
    open_parser.add_argument("--kind", choices=("work", "task"), required=True)
    open_parser.add_argument("--state", choices=("working", "blocked"), required=True)
    open_parser.add_argument("--owner-machine", default="local")
    open_parser.add_argument("--owner-agent", required=True)
    open_parser.add_argument("--signal-key")
    open_parser.add_argument("--title", required=True)
    open_parser.add_argument("--detail", default="")
    close_parser = commands.add_parser("close", help="remove a verified-complete or dropped item")
    close_parser.add_argument("--key", required=True)
    commands.add_parser("list", help="print the current active-items document")
    return root


def main() -> int:
    args = parser().parse_args()
    feed_dir = Path(args.feed_dir).expanduser()
    feed_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    path, lock_path = feed_paths(feed_dir)
    os.umask(0o077)
    with lock_path.open("a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        data = read_items(path)
        if args.command == "open":
            open_item(args, data)
            write_items(path, data)
        elif args.command == "close":
            close_item(args, data)
            write_items(path, data)
        else:
            print(json.dumps(data, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
