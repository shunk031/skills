"""Invoke Codex in an isolated temporary home and parse the resulting trace.

`doc_slop_review.py` needs one blind Codex call per document, and that call must
not be influenced by the caller's environment: not by the caller's installed
skills, not by the repository the caller happens to be standing in, and not by
the caller's git state. This module owns exactly that concern.

It lives inside the skill rather than in a shared toolbox because the `skills`
CLI copies a skill's directory into the runtime pool as-is. Anything the review
script imports has to be a sibling of that script, or the installed copy is
broken.

The isolation has three parts:

- an empty temporary git repository as the working directory, so Codex sees no
  caller source;
- a temporary `CODEX_HOME` holding only the caller's credentials and model
  configuration, so no cached state or history leaks in;
- an explicit override that disables every skill installed under the caller's
  home, so the judge reads only the prompt it was given.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import TypeVar

T = TypeVar("T")

# Failures worth one retry: the request never reached a verdict, so repeating it
# is not a second opinion on the same evidence.
TRANSIENT_PATTERN = re.compile(
    r"(?:429|too many requests|timed? ?out|timeout|connection|network|tls|"
    r"status\s*5\d\d|http\s*5\d\d)",
    re.IGNORECASE,
)


class CodexError(RuntimeError):
    """Report a permanent Codex execution failure."""


class TransientCodexError(CodexError):
    """Report a Codex failure that may succeed on one retry."""


@dataclass(frozen=True)
class ParsedTrace:
    """The agent's final message, extracted from a Codex JSON event stream."""

    output: str


def codex_executable() -> str:
    return os.environ.get("DOC_SLOP_REVIEW_CODEX", "codex")


def parse_trace(trace: str) -> ParsedTrace:
    """Return the last agent message in a Codex `--json` event stream.

    Codex emits one JSON object per line and interleaves reasoning, tool calls,
    and messages. Only the final `agent_message` carries the structured verdict,
    and unparsable lines are skipped rather than raised on, because the stream
    may carry progress output that is not an event.
    """
    messages: list[str] = []
    for line in trace.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        item = event.get("item") if isinstance(event, dict) else None
        if not isinstance(item, dict):
            continue
        if item.get("type") == "agent_message" and isinstance(item.get("text"), str):
            messages.append(item["text"])
    return ParsedTrace(output=messages[-1] if messages else "")


def retry_transient(operation: Callable[[], T], retries: int = 1) -> T:
    for attempt in range(retries + 1):
        try:
            return operation()
        except TransientCodexError:
            if attempt == retries:
                raise
    raise AssertionError("unreachable")


def disabled_skill_override() -> str | None:
    """Build a config override that disables every skill installed for the user.

    The judge must read the document with no project context. A skill installed
    in the caller's home would otherwise load into the judge's session and give
    it exactly the context the review is trying to withhold.
    """
    paths: set[Path] = set()
    home = Path.home()
    for root in (home / ".agents/skills", home / ".codex/skills"):
        if not root.is_dir():
            continue
        paths.update(path.resolve() for path in root.glob("*/SKILL.md"))
    if not paths:
        return None
    entries = ",".join(
        f"{{path={json.dumps(str(path))},enabled=false}}" for path in sorted(paths)
    )
    return f"skills.config=[{entries}]"


def codex_model_arguments(model: str | None, reasoning_effort: str | None) -> list[str]:
    arguments: list[str] = []
    if model is not None:
        arguments.extend(["--model", model])
    if reasoning_effort is not None:
        arguments.extend(["-c", f'model_reasoning_effort="{reasoning_effort}"'])
    return arguments


def codex_settings_kwargs(
    model: str | None, reasoning_effort: str | None
) -> dict[str, str]:
    """Drop unset model settings so `invoke_codex` keeps its own defaults."""
    settings: dict[str, str] = {}
    if model is not None:
        settings["model"] = model
    if reasoning_effort is not None:
        settings["reasoning_effort"] = reasoning_effort
    return settings


def git_environment_without_local_variables() -> dict[str, str]:
    """Copy the environment minus the variables git scopes to one repository.

    A caller invoked from a git hook inherits `GIT_DIR`, `GIT_INDEX_FILE`, and
    friends. Left in place they would point the temporary repository at the
    caller's repository, which is the opposite of isolation.
    """
    local_env_vars = subprocess.run(
        ["git", "rev-parse", "--local-env-vars"],
        check=True,
        text=True,
        capture_output=True,
    ).stdout.split()
    environment = os.environ.copy()
    for name in local_env_vars:
        environment.pop(name, None)
    return environment


def initialize_temp_repo(path: Path) -> None:
    """Create the empty git repository Codex is pointed at as its workspace."""
    subprocess.run(
        ["git", "init", "-q", str(path)],
        check=True,
        capture_output=True,
        env=git_environment_without_local_variables(),
    )


def initialize_codex_home(path: Path) -> None:
    """Stage a throwaway `CODEX_HOME` with only credentials and configuration.

    Copying just `config.toml` and `auth.json` is deliberate: the caller's real
    Codex home also holds session history, logs, and local state, none of which
    the judge should see. Source permissions are preserved so the copied
    credentials are no more readable than the originals.
    """
    path.mkdir()
    source = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    for name in ("config.toml", "auth.json"):
        candidate = source / name
        if candidate.exists():
            destination = path / name
            shutil.copy2(candidate, destination)
            destination.chmod(candidate.stat().st_mode & 0o777)


def invoke_codex(
    repo: Path,
    prompt: str,
    timeout: int,
    schema: Path | None = None,
    *,
    sandbox: str = "read-only",
    codex_home: Path | None = None,
    model: str | None = None,
    reasoning_effort: str | None = None,
) -> str:
    """Run one `codex exec` and return its raw JSON event stream.

    Raises `TransientCodexError` when the call may succeed on a retry and
    `CodexError` when it will not.
    """
    # Hosts without unprivileged user namespaces cannot run Codex's bwrap
    # sandbox at all; DOC_SLOP_REVIEW_SANDBOX lets such hosts pick the sandbox
    # mode explicitly (for example danger-full-access).
    sandbox = os.environ.get("DOC_SLOP_REVIEW_SANDBOX", sandbox)
    command = [codex_executable(), "--disable", "plugins", "exec"]
    command.extend(codex_model_arguments(model, reasoning_effort))
    override = disabled_skill_override()
    if override:
        command.extend(["-c", override])
    command.extend(
        [
            "--ephemeral",
            "--json",
            "--sandbox",
            sandbox,
            "--cd",
            str(repo),
        ]
    )
    if schema is not None:
        command.extend(["--output-schema", str(schema)])
    command.append("-")
    try:
        environment = git_environment_without_local_variables()
        # Drop Herdr caller context so the judge cannot control the caller's
        # live Herdr session through the herdr CLI.
        for name in [key for key in environment if key.startswith("HERDR_")]:
            del environment[name]
        if codex_home is not None:
            environment["CODEX_HOME"] = str(codex_home)
        completed = subprocess.run(
            command,
            input=prompt,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
            env=environment,
        )
    except subprocess.TimeoutExpired as error:
        raise TransientCodexError(f"Codex timed out after {timeout}s") from error
    except OSError as error:
        raise CodexError(f"{codex_executable()} could not be run: {error}") from error
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip()
        error_type = (
            TransientCodexError if TRANSIENT_PATTERN.search(message) else CodexError
        )
        raise error_type(message or f"Codex exited with status {completed.returncode}")
    return completed.stdout
