TRIALS ?= 3
JOBS ?= 8
TIMEOUT ?= 600

# Keep in step with the `go` pin in mise.toml.
GO_VERSION ?= 1.26.5

# Keep in step with the `python` pin in mise.toml.
PYTHON_VERSION ?= 3.14.6

#
# Development
#

.PHONY: setup
setup:
	mise install
	mise exec -- prek install

# shuhari ships no git tags, so its module version list is empty and mise cannot
# resolve `latest`. mise.toml therefore pins the pseudo-version of a specific
# `main` commit. This re-resolves that pin against current `main`.
#
# `GOPROXY=direct` is required, not a preference: proxy.golang.org serves a
# cached `@latest` that can lag a merge by a long time, and bumping to a stale
# commit looks like success. Direct resolution reads the repository.
#
# `mise x go@...` runs only the Go toolchain, so this still works when the
# current shuhari pin is unresolvable. Do not route it through `mise exec`,
# which resolves every pinned tool first and would fail before the recipe runs.
.PHONY: bump-shuhari
bump-shuhari:
	@version="$$(GOPROXY=direct mise x go@$(GO_VERSION) -- \
	    go list -m -f '{{.Version}}' github.com/shunk031/shuhari@latest 2>/dev/null)"; \
	if [ -z "$$version" ]; then \
	    echo "failed to resolve a shuhari version from the module source" >&2; \
	    exit 1; \
	fi; \
	version="$${version#v}"; \
	sed -i.bak \
	    "s|^\"go:github.com/shunk031/shuhari/cmd/shuhari\" = .*|\"go:github.com/shunk031/shuhari/cmd/shuhari\" = \"$$version\"|" \
	    mise.toml; \
	rm -f mise.toml.bak; \
	echo "pinned shuhari to $$version"
	mise install

#
# Gates
#

# Offline: layout checks plus schema validation for every skill that ships evals.
.PHONY: validate
validate:
	./scripts/check_skill_layout.sh
	@set -e; \
	for dir in skills/*/; do \
	    if [ -f "$$dir/evals/evals.json" ]; then shuhari eval skill --validate-only "$$dir"; fi; \
	    if [ -f "$$dir/evals/triggers.json" ]; then shuhari check trigger --validate-only "$$dir"; fi; \
	done

# Live model calls against every skill. Deliberately a manual, occasional run;
# the pre-commit hooks gate incrementally.
.PHONY: eval
eval:
	@set -e; \
	for dir in skills/*/; do \
	    if [ -f "$$dir/evals/evals.json" ]; then \
	        ./scripts/shuhari_staged_targets.sh eval "$$dir/SKILL.md"; \
	    fi; \
	done

.PHONY: check-triggers
check-triggers:
	@set -e; \
	for dir in skills/*/; do \
	    if [ -f "$$dir/evals/triggers.json" ]; then \
	        shuhari check trigger --trials $(TRIALS) --jobs $(JOBS) --timeout $(TIMEOUT) "$$dir"; \
	    fi; \
	done

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

# The same offline hooks CI runs. The live gates are skipped here by design.
.PHONY: gate
gate:
	SKIP=shuhari-check-trigger,shuhari-eval-skill mise exec -- prek run --all-files

.PHONY: format
format:
	shfmt --indent 4 --space-redirects --diff .
