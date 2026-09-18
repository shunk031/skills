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
5. Install pre-commit hooks after dependency setup.
6. Create `.pre-commit-config.yaml` when missing.
7. Create `Makefile` with `setup` target when missing.
8. For refactoring from non-`uv` originals, align dependencies, raise coverage, and verify output parity.
9. Construct Python paths from a source-file anchor, and keep every path component in its own operand:
   - Forbidden: `Path("/path/to") / "hoge"` and `REPO_ROOT / "home/dot_codex/hooks/session_start_gateway.py"`
   - Required: `Path(__file__).parents[N] / "path" / "to" / "hoge"`
     Never put multiple path components separated by `/` or `\` in a string literal passed to `Path` or used as an operand to `/`. Anchoring paths to the source file keeps them working after relocation and across worktrees without coupling them to a host layout. Explicit roots supplied through a CLI argument or environment variable are allowed; hard-coded absolute path strings remain forbidden.
     Before finalizing Python changes, inspect every changed `Path(...)` and `/` expression for path-separator-containing string operands.
10. Name variables for their semantic role. When the same concept has multiple representations, add a qualifier such as `_path`, `_text`, or `_data` only to distinguish them; do not add type suffixes mechanically when the role is already clear.

## Testing Expectations

- Add tests before refactoring.
- Prefer real data over mocks and monkeypatches when feasible.
- Target coverage expansion toward 90%+ for refactoring tasks.

Use [python-uv-rules.md](references/python-uv-rules.md) for exact commands and canonical hook configuration.
