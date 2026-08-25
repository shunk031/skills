TRIALS ?= 3
JOBS ?= 2
TIMEOUT ?= 600

#
# Development
#

.PHONY: setup
setup:
	mise install
	mise exec -- prek install

# shuhari ships no git tags, so its module proxy version list is empty and mise
# cannot resolve `latest`. mise.toml therefore pins the pseudo-version of a
# specific `main` commit. This re-resolves that pin against current `main`.
#
# Run it as `make bump-shuhari`, never through `mise exec`. mise resolves every
# pinned tool before running a command, so an unresolvable current pin would
# fail before this recipe could replace it. Run directly, this recovers.
.PHONY: bump-shuhari
bump-shuhari:
	@version="$$(curl -fsSL https://proxy.golang.org/github.com/shunk031/shuhari/@latest \
	    | sed -n 's/.*"Version":"\([^"]*\)".*/\1/p')"; \
	if [ -z "$$version" ]; then \
	    echo "failed to resolve a shuhari version from the Go module proxy" >&2; \
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
	        shuhari eval skill --trials $(TRIALS) --jobs $(JOBS) --timeout $(TIMEOUT) "$$dir"; \
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

# The same offline hooks CI runs. The live gates are skipped here by design.
.PHONY: gate
gate:
	SKIP=shuhari-check-trigger,shuhari-eval-skill mise exec -- prek run --all-files

.PHONY: format
format:
	shfmt --indent 4 --space-redirects --diff .
