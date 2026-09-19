---
name: shunk031-python-uv-workflow
description: Apply Python development policy using uv-first execution, test-first behavior validation, and pre-commit quality gates. Use when implementing or refactoring Python code.
---

> [!NOTE]
> After reading this `SKILL.md`, say: `🐍 I read shunk031-python-uv-workflow.`

# Python UV Workflow

## Overview

Use this workflow to keep Python implementation and refactoring aligned with repository policy.

## Workflow

1. Use `uv` as the default toolchain for Python projects.
2. Run scripts with `uv run <script>`.
3. Write tests when behavior changes and verify expected behavior.
4. Add standard dev dependencies with `uv`.
5. Follow the existing project's setup and quality gates. Install pre-commit hooks after dependency setup when the project or repository requires them.
6. For a new project or an explicit setup request, add only the project configuration the request or repository policy needs; do not create `.pre-commit-config.yaml` or a `Makefile` for an isolated script edit.
7. For refactoring from non-`uv` originals, align dependencies and verify output parity. Match the repository's coverage target; raise coverage toward 90% only when the refactor or repository requires that target.
8. Construct Python paths from a source-file anchor, and keep every path component in its own operand:
   - Forbidden: `Path("/path/to") / "hoge"` and `REPO_ROOT / "home/dot_codex/hooks/session_start_gateway.py"`
   - Required: `Path(__file__).parents[N] / "path" / "to" / "hoge"`
     Never put multiple path components separated by `/` or `\` in a string literal passed to `Path` or used as an operand to `/`. Anchoring paths to the source file keeps them working after relocation and across worktrees without coupling them to a host layout. Explicit roots supplied through a CLI argument or environment variable are allowed; hard-coded absolute path strings remain forbidden.
     Before finalizing Python changes, inspect every changed `Path(...)` and `/` expression for path-separator-containing string operands.
9. Name variables for their semantic role. When the same concept has multiple representations, add a qualifier such as `_path`, `_text`, or `_data` only to distinguish them; do not add type suffixes mechanically when the role is already clear.

## Testing Expectations

- Add tests before refactoring when behavior changes.
- Prefer real data over mocks and monkeypatches when feasible.
- Follow the project's stated coverage target; do not impose a universal percentage.

Use [python-uv-rules.md](references/python-uv-rules.md) for exact commands and canonical hook configuration.
