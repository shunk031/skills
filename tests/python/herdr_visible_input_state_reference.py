"""Small independent reference for Herdr's visible input-state rules."""

from __future__ import annotations

import re
import unicodedata
from itertools import product


ESC = "\x1b"
_CANONICAL_NUMBER = re.compile(r"(?:0|[1-9][0-9]*)\Z")
_PLAIN_ATTRIBUTES = {"0", "1", "2", "7", "22", "27", "36"}


def _parse_sgr(parameters: str) -> list[tuple[str, ...]] | None:
    values = parameters.split(";")
    if not values or any(not _CANONICAL_NUMBER.fullmatch(value) for value in values):
        return None

    groups = []
    index = 0
    while index < len(values):
        code = values[index]
        if code in {"38", "48"}:
            if index + 1 >= len(values):
                return None
            mode = values[index + 1]
            if code == "38" and mode == "5":
                if index + 2 >= len(values) or int(values[index + 2]) > 255:
                    return None
                groups.append((code, mode, values[index + 2]))
                index += 3
            elif mode == "2":
                channels = values[index + 2 : index + 5]
                if len(channels) != 3 or any(int(channel) > 255 for channel in channels):
                    return None
                groups.append((code, mode, *channels))
                index += 5
            else:
                return None
        elif code in _PLAIN_ATTRIBUTES:
            groups.append((code,))
            index += 1
        else:
            return None
    return groups


def _apply_sgr(state: dict[str, bool], groups: list[tuple[str, ...]]) -> None:
    for group in groups:
        code = group[0]
        if code == "0":
            state.update(dim=False, gray=False, reverse=False)
        elif code == "2":
            state["dim"] = True
        elif code == "7":
            state["reverse"] = True
        elif code == "22":
            state["dim"] = False
        elif code == "27":
            state["reverse"] = False
        elif code == "36":
            state["gray"] = False
        elif code == "38":
            state["gray"] = group[1:] == ("5", "8")


def _prompt_end(plain: str) -> int | None:
    match = re.match(r"^[ \t\v\f\r]*(?:❯|›)", plain)
    if match:
        return match.end()
    match = re.match(r"^ {0,2}>(?: |$)", plain)
    return match.end() if match else None


def _line_state(line: str) -> str | None:
    line = line.replace("\u00a0", " ")
    if line.endswith("\r"):
        line = line[:-1]

    plain: list[str] = []
    styles: list[tuple[bool, bool, bool]] = []
    bad_offsets: list[int] = []
    state = {"dim": False, "gray": False, "reverse": False}
    index = 0

    while index < len(line):
        char = line[index]
        if char == ESC:
            if index + 1 < len(line) and line[index + 1] == "[":
                end = index + 2
                while end < len(line) and not "@" <= line[end] <= "~":
                    end += 1
                if end == len(line):
                    bad_offsets.append(len(plain))
                    break
                if line[end] != "m":
                    bad_offsets.append(len(plain))
                else:
                    groups = _parse_sgr(line[index + 2 : end])
                    if groups is None:
                        bad_offsets.append(len(plain))
                    else:
                        _apply_sgr(state, groups)
                index = end + 1
                continue

            bad_offsets.append(len(plain))
            if index + 1 < len(line) and line[index + 1] in "]P^_":
                index += 2
                while index < len(line):
                    if line[index] == "\x07":
                        index += 1
                        break
                    if line.startswith(ESC + "\\", index):
                        index += 2
                        break
                    index += 1
            else:
                index = min(len(line), index + 2)
            continue

        if unicodedata.category(char) == "Cc":
            bad_offsets.append(len(plain))
            index += 1
            continue

        plain.append(char)
        styles.append((state["dim"], state["gray"], state["reverse"]))
        index += 1

    text = "".join(plain)
    prompt_end = _prompt_end(text)
    if prompt_end is None:
        return None
    if any(offset >= prompt_end for offset in bad_offsets):
        return "occupied"

    non_dim = [
        index
        for index in range(prompt_end, len(text))
        if text[index] not in " \t\v\f\r" and not (styles[index][0] or styles[index][1])
    ]
    if not non_dim:
        return "empty"
    if len(non_dim) != 1 or not styles[non_dim[0]][2]:
        return "occupied"

    following = non_dim[0] + 1
    if following == len(text) or text[following] in " \t\v\f\r" or not (styles[following][0] or styles[following][1]):
        return "occupied"
    return "empty"


def classify(snapshot: str) -> str:
    """Classify the last prompt input line, matching the shared detector API."""
    result = None
    for line in snapshot.split("\n"):
        current = _line_state(line)
        if current is not None:
            result = current
    return result or "unknown"


_PROMPTS = ("❯ ", "› ", "> ")
_SHAPES = ("cursor", "dim", "typed", "cursor_only")
_TEXTS = ("Suggested completion", "Ask Codex", "Accept-edits mode", "typed text")
_PREFIXES = (
    "",
    ESC + "[0m",
    ESC + "[1;2m",
    ESC + "[48;2;30;30;30m",
    ESC + "[38;5;8m",
    ESC + "[38;5;12m",
    ESC + "[38;2;153;153;153m",
    ESC + "[36m",
    ESC + "[0m" + ESC + "[1m",
)
_MALFORMED = (
    ESC + "[00m",
    ESC + "[2:1m",
    ESC + "[999m",
    ESC + "[2;m",
    ESC + "[38;5m",
    ESC + "[38;x;8m",
    ESC + "[38;5;08m",
    ESC + "[7",
    ESC + "[2K",
    ESC + "]title\x07",
    "\u009b0m",
    ESC + "[38;2;1;2m",
    ESC + "[38;5;256m",
    ESC + "[38:5:8m",
)
_MALFORMED_POSITIONS = ("before_cursor", "after_cursor", "after_reset", "after_text")


def _shape_parts(shape: str, text: str) -> tuple[str, str]:
    if shape == "cursor":
        return ESC + "[7mP", ESC + "[27m" + ESC + "[2m" + text + ESC + "[0m"
    if shape == "dim":
        return "", ESC + "[2m" + text + ESC + "[0m"
    if shape == "typed":
        return "", text
    return ESC + "[7mP", ESC + "[27m" + ESC + "[0m"


def generate_malformed_lines():
    """Generate malformed SGR/control sequences at each meaningful input position."""
    for position, malformed, prompt, shape, text, prefix in product(
        _MALFORMED_POSITIONS,
        _MALFORMED,
        _PROMPTS,
        _SHAPES,
        _TEXTS,
        ("", ESC + "[1;2m"),
    ):
        before, after = _shape_parts(shape, text)
        if position == "before_cursor":
            body = prefix + malformed + before + after
        elif position == "after_cursor":
            body = prefix + before + malformed + after
        elif position == "after_reset":
            body = prefix + before + ESC + "[0m" + malformed + ESC + "[2m" + text + ESC + "[0m"
        else:
            body = prefix + before + after + malformed
        yield prompt + body


def generate_valid_lines():
    """Generate recognized SGR combinations with dim, cursor, and typed text."""
    for prompt, shape, text, prefix in product(_PROMPTS, _SHAPES, _TEXTS, _PREFIXES):
        before, after = _shape_parts(shape, text)
        yield prompt + prefix + before + after
