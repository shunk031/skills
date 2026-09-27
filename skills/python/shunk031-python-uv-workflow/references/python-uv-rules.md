# Python UV Rules Reference

## Base Policy

- Use `uv` by default for Python projects.
- Write tests for behavior-impacting changes.
- Run scripts with `uv run <script>`.

## Project setup when requested

```bash
uv add --group dev <dependencies required by the project>
```

Install hooks only when the project or repository requires them:

```bash
pre-commit install
```

## Example `.pre-commit-config.yaml` template

Use this template for a new project or an explicit hook-configuration request. Do not create this file for an isolated script edit.

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-toml
      - id: check-added-large-files

  - repo: https://github.com/jendrikseipp/vulture
    hooks:
      - id: vulture

  - repo: local
    hooks:
      - id: ruff
        name: ruff (uv)
        entry: uv run ruff check --fix --exit-non-zero-on-fix
        language: system
        types_or: [python, pyi]

      - id: ruff-format
        name: ruff format (uv)
        entry: uv run ruff format
        language: system
        types_or: [python, pyi]

      - id: pytest
        name: pytest (uv)
        entry: uv run pytest -vsx
        language: system
        pass_filenames: false
```

## Example `Makefile` target

Add this target only when the project or repository asks for a Makefile-based setup command.

```make
setup:
	uv sync
	pre-commit install
```

## Exploratory Debugging

```bash
uv run python -c "..."
uv run --with <library> python -c "..."
```

## Refactoring from Original Implementation

1. Move workflow to `uv` if not already using it.
2. Add original dependencies as needed: `uv add --optional original-impl <module>`.
3. Add tests if missing and use the project's coverage tool when its policy requires one.
4. Match the repository's coverage target; do not impose a universal percentage.
5. Prefer small real datasets described in project docs.
6. Compare original and refactored outputs for parity.
