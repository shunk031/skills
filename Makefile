# Keep in step with the `python` pin in mise.toml.
PYTHON_VERSION ?= 3.14.6

#
# Development
#

.PHONY: setup
setup:
	mise install
	mise exec -- prek install

#
# Gates
#

# Offline skill layout checks.
.PHONY: validate
validate:
	./scripts/check_skill_layout.sh

#
# Documentation
#

# Zensical is pinned on the command line rather than in mise.toml: it is a
# Python package, uv is already how this repository runs Python, and the pin
# stays visible next to the command that uses it. Zensical is pre-1.0 and cuts
# releases weekly, so an unpinned build would change under us.
ZENSICAL_VERSION ?= 0.0.56
ZENSICAL = uv run --python $(PYTHON_VERSION) --no-project --with zensical==$(ZENSICAL_VERSION) --

# `docs/` is generated from the skills, so it is gitignored and rebuilt rather
# than committed.
.PHONY: docs
docs:
	uv run --python $(PYTHON_VERSION) --no-project -- python scripts/build_docs.py

# `--strict` fails on a broken link. A skill body links to its own references by
# relative path, and those links only resolve because the generator publishes
# them beside the page.
.PHONY: docs-build
docs-build: docs
	$(ZENSICAL) zensical build --clean --strict

.PHONY: docs-serve
docs-serve: docs
	$(ZENSICAL) zensical serve

#
# Quality
#

# Unit tests for the shell scripts skills ship. Offline, no agent.
.PHONY: test-bats
test-bats:
	mise exec -- bats tests/bats

.PHONY: test
test: test-python test-bats

# Unit tests for the Python scripts skills ship. Offline, no agent.
#
# `--no-project` keeps this from adopting a pyproject.toml that does not exist,
# and naming the interpreter keeps a bare `python` on PATH — or an activated
# virtualenv from another checkout — from deciding which one runs.
.PHONY: test-python
test-python:
	uv run --python $(PYTHON_VERSION) --no-project -- python -m unittest discover -s tests/python

# The same offline hooks CI runs.
.PHONY: gate
gate:
	mise exec -- prek run --all-files

.PHONY: format
format:
	shfmt --indent 4 --space-redirects --diff .
