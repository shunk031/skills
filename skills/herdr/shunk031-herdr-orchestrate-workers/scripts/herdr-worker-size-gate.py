#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import tempfile


MAX_BUDGET = 400
SCHEMA = 1
STATE_ROOT = Path.home() / ".local" / "state" / "herdr-worker-lifecycle" / "size-gates"
TASK_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
WORKER_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
SHELL_META = re.compile(r"[\n\r;&|<>`$()\\]")

def git(repo, *args, env=None, input_data=None, check=True):
    process_env = {key: val for key, val in os.environ.items() if not key.startswith("GIT_")}
    process_env.update(env or {})
    result = subprocess.run(
        ["git", "-C", str(repo), *map(str, args)],
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=process_env,
        check=False,
        timeout=10,
    )
    if check and result.returncode:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise ValueError(detail or f"git {args[0]} failed")
    return result

def value(repo, *args):
    return git(repo, *args).stdout.decode("utf-8", "replace").strip()

def repo_info(repo):
    root = Path(value(repo, "rev-parse", "--show-toplevel")).resolve()
    common = Path(value(repo, "rev-parse", "--git-common-dir"))
    common = (root / common).resolve() if not common.is_absolute() else common.resolve()
    branch = value(root, "symbolic-ref", "--quiet", "--short", "HEAD")
    lines = git(root, "ls-remote", "--symref", "origin", "HEAD").stdout.decode("utf-8", "replace").splitlines()
    ref = next((line.split("\t", 1)[0][5:] for line in lines if line.startswith("ref:") and line.endswith("\tHEAD")), "")
    tip = next((line.split("\t", 1)[0] for line in lines if line.endswith("\tHEAD") and not line.startswith("ref:")), "")
    if not ref.startswith("refs/heads/") or not re.fullmatch(r"[0-9a-f]{40,64}", tip):
        raise ValueError("origin/HEAD did not identify one verified default branch and tip")
    bases = value(root, "merge-base", "--all", "HEAD", tip).splitlines()
    if len(bases) != 1:
        raise ValueError("origin default tip has missing or ambiguous ancestry")
    return {"worktree": str(root), "common_dir": str(common), "branch": branch, "default_ref": ref, "default_tip": tip, "base_sha": bases[0]}

def record_path(launch_id):
    if not re.fullmatch(r"[a-f0-9-]{16,40}", launch_id): raise ValueError("worker size-gate launch ID is invalid")
    return STATE_ROOT / f"{launch_id}.json"

def line_count(data):
    if b"\0" in data:
        return 1, True
    return data.count(b"\n") + int(bool(data) and not data.endswith(b"\n")), False

def count_diff(repo, base):
    if git(repo, "ls-files", "--unmerged", "-z").stdout: raise ValueError("unresolved merge entries prevent a trustworthy count")
    diff = git(repo, "diff", "--numstat", "-z", "--diff-algorithm=myers", "--no-ext-diff", "--no-textconv", base).stdout
    additions = deletions = binary_files = 0
    changed_paths = set()
    fields = diff.split(b"\0")
    cursor = 0
    while cursor < len(fields) and fields[cursor]:
        counts = fields[cursor].split(b"\t", 2)
        cursor += 1
        if len(counts) != 3: raise ValueError("Git returned an invalid NUL-delimited numstat record")
        paths = [os.fsdecode(counts[2])] if counts[2] else []
        if not counts[2]:
            if cursor + 1 >= len(fields):
                raise ValueError("Git returned an incomplete rename record")
            paths = list(map(os.fsdecode, fields[cursor : cursor + 2]))
            cursor += 2
        changed_paths.update(paths)
        if counts[0] == b"-" or counts[1] == b"-":
            binary_files += 1
        else:
            additions += int(counts[0])
            deletions += int(counts[1])

    untracked = git(repo, "ls-files", "--others", "--exclude-standard", "-z").stdout.split(b"\0")
    for raw_path in (path for path in untracked if path):
        path = Path(repo) / os.fsdecode(raw_path)
        try:
            mode = os.lstat(path).st_mode
            data = os.fsencode(os.readlink(path)) if stat.S_ISLNK(mode) else path.read_bytes() if stat.S_ISREG(mode) else b"\0"
        except OSError as error:
            raise ValueError(f"could not count untracked path {os.fsdecode(raw_path)}: {error}") from error
        lines, binary = line_count(data)
        if binary:
            binary_files += 1
        else:
            additions += lines
        changed_paths.add(os.fsdecode(raw_path))

    return {"additions": additions, "deletions": deletions, "binary_files": binary_files, "total": additions + deletions + binary_files, "changed_paths": sorted(changed_paths)}

def budget_for(budget, task, worker, override=None):
    if not isinstance(budget, int) or budget <= 0:
        raise ValueError("line budget must be a positive integer")
    if budget <= MAX_BUDGET and not override:
        return budget, None
    path = STATE_ROOT / "overrides" / worker / f"{task}.json"
    if not override and path.exists():
        if not path.is_file() or path.stat().st_mode & 0o077 or path.stat().st_uid != os.getuid():
            raise ValueError("budget override is not a protected regular file")
        override = json.loads(path.read_text(encoding="utf-8"))
    if not override or override.get("budget") != budget or override["budget"] <= MAX_BUDGET or not override.get("user_approval_reference") or override.get("task_key") != task or override.get("worker_name") != worker:
        raise ValueError("budget override is missing, invalid, or belongs to a different task or worker")
    return budget, {key: override[key] for key in ("budget", "user_approval_reference", "task_key", "worker_name")}

def preflight(args):
    if not WORKER_RE.fullmatch(args.worker_name) or not TASK_RE.fullmatch(args.task_key):
        raise ValueError("worker name or task key is invalid")
    budget, override = budget_for(args.line_budget, args.task_key, args.worker_name)
    info = repo_info(Path(args.repo))
    info.update(count_diff(info["worktree"], info["base_sha"]))
    info.update(line_budget=budget, override=override)
    if info["total"] > budget: raise ValueError(f"initial worktree diff {info['total']} is over budget {budget}")
    return info

def atomic_json(path, data):
    home = Path.home()
    managed_dirs = (STATE_ROOT.parent, path.parent)
    for parent in (home / ".local", home / ".local" / "state", *managed_dirs):
        if parent.is_symlink():
            raise ValueError("size-gate state path must not contain symlinks")
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    for directory in managed_dirs:
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError("size-gate state directory must be a real directory")
        os.chmod(directory, 0o700)
    fd, temp = tempfile.mkstemp(prefix=".size-gate-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, sort_keys=True)
            stream.write("\n")
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)

def prepare(args):
    path = record_path(args.launch_id)
    if path.exists() or path.is_symlink():
        raise ValueError("size-gate launch ID already exists")
    result = preflight(args)
    record = {
        "schema": SCHEMA,
        "launch_id": args.launch_id,
        "task_key": args.task_key,
        "worker_name": args.worker_name,
        "owner": {"name": args.owner_name, "pane": args.owner_pane, "terminal": args.owner_terminal},
        "worker": {"pane": args.worker_pane, "tab": args.worker_tab, "terminal": args.worker_terminal},
        "status": "pending",
        **{key: result[key] for key in ("worktree", "common_dir", "branch", "default_ref", "default_tip", "base_sha")},
        "line_budget": result["line_budget"],
        "override": result["override"],
    }
    atomic_json(path, record)
    return {"launch_id": args.launch_id, "record_path": str(path), "total": result["total"], "line_budget": result["line_budget"]}

def finish(args):
    path = record_path(args.launch_id)
    if path.is_symlink() or not path.is_file() or path.stat().st_mode & 0o077:
        raise ValueError("pending size-gate record is missing or not protected")
    record = json.loads(path.read_text(encoding="utf-8"))
    if tuple(record.get("worker", {}).get(key) for key in ("pane", "tab", "terminal")) != (args.worker_pane, args.worker_tab, args.worker_terminal):
        raise ValueError("live worker identity does not match its pending size-gate record")
    if record.get("status") != "pending": raise ValueError("only a pending size-gate record can be finalized")
    record["status"] = "started"
    atomic_json(path, record)
    return {"launch_id": args.launch_id, "status": record["status"]}

def load_record(launch_id, cwd, pane, tab):
    path = record_path(launch_id)
    if any(parent.is_symlink() for parent in (Path.home() / ".local", Path.home() / ".local" / "state", STATE_ROOT.parent, STATE_ROOT)):
        raise ValueError("worker size-gate state path must not contain symlinks")
    if path.is_symlink() or not path.is_file() or path.stat().st_mode & 0o077 or path.stat().st_uid != os.getuid():
        raise ValueError("worker size-gate record is missing or not protected")
    record = json.loads(path.read_text(encoding="utf-8"))
    if record.get("schema") != SCHEMA or record.get("launch_id") != launch_id or record.get("status") not in {"pending", "started"}:
        raise ValueError("worker size-gate record is malformed")
    if Path(cwd).resolve() != Path(record["worktree"]).resolve():
        raise ValueError("worker cwd does not match its registered worktree")
    identity = record.get("worker", {})
    if identity.get("pane") != pane or identity.get("tab") != tab:
        raise ValueError("worker pane identity does not match its registered launch")
    if value(cwd, "rev-parse", "--show-toplevel") != record["worktree"]:
        raise ValueError("Git worktree root changed after worker launch")
    common = Path(value(cwd, "rev-parse", "--git-common-dir"))
    common = (Path(cwd).resolve() / common).resolve() if not common.is_absolute() else common.resolve()
    if common != Path(record["common_dir"]).resolve():
        raise ValueError("Git common directory changed after worker launch")
    if value(cwd, "symbolic-ref", "--short", "HEAD") != record["branch"]:
        raise ValueError("task branch changed; ask meta to rebind the worker baseline")
    bases = value(cwd, "merge-base", "--all", "HEAD", record["default_tip"]).splitlines()
    if bases != [record["base_sha"]]:
        raise ValueError("task ancestry changed; ask meta to rebind the worker baseline")
    if git(cwd, "cat-file", "-e", f"{record['base_sha']}^{{commit}}", check=False).returncode:
        raise ValueError("recorded base commit is unavailable")
    return record

def literal_report(command, worker):
    if SHELL_META.search(command):
        return False
    try:
        parts = shlex.split(command, posix=True)
    except ValueError:
        return False
    prefix = (f"STATUS {worker}:", f"BLOCKED {worker}:", f"DONE {worker}:")
    return len(parts) == 5 and parts[:4] == ["herdr-meta-patrol-queue", "add", "--from", worker] and parts[4].startswith(prefix)

def publication(command):
    try:
        words = shlex.split(command, posix=True)
    except ValueError:
        words = []
    is_git_push = "git" in words and "push" in words
    is_gh_pr_create = "gh" in words and any(words[index : index + 2] == ["pr", "create"] for index in range(len(words) - 1))
    if not is_git_push and not is_gh_pr_create:
        return None
    if SHELL_META.search(command) or not words:
        raise ValueError("compound or indirect publication command is not supported; use literal git push or gh pr create")
    if words[:2] == ["git", "push"] and len(words) == 4 and words[2] == "origin":
        return ("push", words[3], None)
    if words[:3] == ["gh", "pr", "create"]:
        options = dict(zip(words[3::2], words[4::2]))
        if len(words[3:]) % 2 or set(options) != {"--base", "--head", "--title", "--body-file"}:
            raise ValueError("unsupported gh pr create form; provide --base, --head, --title, and --body-file")
        return ("pr", options["--head"], options["--base"])
    raise ValueError("unsupported publication form; use literal git push origin <task-branch> or gh pr create with explicit --base and --head")

def publish_check(repo, record, form):
    kind, branch, base_branch = form
    if branch != record["branch"] or value(repo, "symbolic-ref", "--short", "HEAD") != record["branch"]:
        raise ValueError("publication head is not the registered task branch")
    status = git(repo, "status", "--porcelain=v1", "--untracked-files=all").stdout
    if status:
        raise ValueError("publication requires a clean committed worktree")
    if kind == "pr" and base_branch != record["default_ref"][len("refs/heads/"):]:
        raise ValueError("pull request base is not the registered origin default branch")

def check(args):
    record = load_record(args.launch_id, args.cwd, args.pane, args.tab)
    budget, override = budget_for(record.get("line_budget"), record["task_key"], record["worker_name"], record.get("override"))
    form = publication(args.command) if args.tool_name == "Bash" else None
    if form:
        publish_check(args.cwd, record, form)
    count = count_diff(args.cwd, record["base_sha"])
    over = count["total"] > budget
    reason = f"BLOCKED: worktree diff {count['total']} > budget {budget}. Stop editing and report BLOCKED with a smaller design." if over else ""
    deny = args.phase == "pre" and over and not (args.tool_name == "Bash" and literal_report(args.command, record["worker_name"]))
    return {**count, "line_budget": budget, "over_budget": over, "deny": deny, "reason": reason}

def parser():
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command_name", required=True)
    for name in ("preflight", "prepare"):
        cmd = commands.add_parser(name)
        cmd.add_argument("--repo", required=True)
        cmd.add_argument("--line-budget", required=True, type=int)
        cmd.add_argument("--worker-name", required=True)
        cmd.add_argument("--task-key", required=True)
        if name == "prepare":
            for option in ("launch-id", "owner-name", "owner-pane", "owner-terminal", "worker-pane", "worker-tab", "worker-terminal"):
                cmd.add_argument(f"--{option}", required=True)
    cmd = commands.add_parser("finish")
    for option in ("launch-id", "worker-pane", "worker-tab", "worker-terminal"):
        cmd.add_argument(f"--{option}", required=True)
    cmd = commands.add_parser("check")
    for option in ("launch-id", "cwd", "pane", "tab", "phase", "tool-name"):
        cmd.add_argument(f"--{option}", required=True)
    cmd.add_argument("--command", default="")
    return root

def main():
    args = parser().parse_args()
    try:
        result = preflight(args) if args.command_name == "preflight" else prepare(args) if args.command_name == "prepare" else finish(args) if args.command_name == "finish" else check(args)
        print(json.dumps(result, sort_keys=True))
    except (ValueError, OSError, KeyError, TypeError, AttributeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"error": str(error), "deny": True}), file=sys.stdout)
        return 2
    return 0

if __name__ == "__main__":
    sys.exit(main())
