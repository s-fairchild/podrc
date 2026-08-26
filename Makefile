.DEFAULT_GOAL := help

BATS := test/vendor/bats-core/bin/bats

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

.PHONY: lint
lint: ## Validate quadlet syntax (dry-run) and shellcheck the scripts
	@scripts/lint.sh

.PHONY: generate
generate: ## Materialize the systemd units quadlet would generate, into .generated/
	@scripts/generate.sh

.PHONY: install
install: lint ## Install quadlet units + env templates for the current user, enable services
	@scripts/install.sh

.PHONY: uninstall
uninstall: ## Stop, disable, and remove the installed quadlet units (keeps env secrets)
	@scripts/uninstall.sh

.PHONY: uninstall-purge
uninstall-purge: ## Like uninstall, but also deletes env files (secrets)
	@scripts/uninstall.sh --purge

.PHONY: test
test: submodules ## Run the bats test suite against the make targets
	@$(BATS) test/*.bats

.PHONY: submodules
submodules: ## Fetch vendored test dependencies (bats-core and helpers)
	@if [ ! -x "$(BATS)" ]; then \
		git submodule update --init --recursive; \
	fi

.PHONY: clean
clean: ## Remove generated/build artifacts (not installed units)
	rm -rf .generated

.PHONY: distclean
distclean: clean ## Also deinitialize vendored submodules
	git submodule deinit --all -f
