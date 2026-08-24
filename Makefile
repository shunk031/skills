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
