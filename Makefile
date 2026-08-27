.DEFAULT_GOAL := help

BATS := test/vendor/bats-core/bin/bats
BASH_LOGGER := vendor/bash-logger/logging.sh

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

.PHONY: lint
lint: submodules ## Validate quadlet syntax (dry-run) and shellcheck the scripts
	@scripts/lint.sh

.PHONY: generate
generate: submodules ## Materialize the systemd units quadlet would generate, into .generated/
	@scripts/generate.sh

.PHONY: install
install: submodules lint ## Install quadlet units + env templates for the current user, enable services
	@scripts/install.sh

.PHONY: uninstall
uninstall: submodules ## Stop, disable, and remove the installed quadlet units (keeps env secrets)
	@scripts/uninstall.sh

.PHONY: uninstall-purge
uninstall-purge: submodules ## Like uninstall, but also deletes env files (secrets) and this repo's podman containers/networks
	@scripts/uninstall.sh --purge

.PHONY: test
test: submodules ## Run the bats test suite against the make targets
	@$(BATS) test/*.bats

.PHONY: submodules
submodules: ## Fetch vendored dependencies (bats-core/helpers, bash-logger)
	@if [ ! -x "$(BATS)" ] || [ ! -f "$(BASH_LOGGER)" ]; then \
		git submodule update --init --recursive; \
	fi

.PHONY: clean
clean: ## Remove generated/build artifacts (not installed units)
	rm -rf .generated

.PHONY: distclean
distclean: clean ## Also deinitialize vendored submodules
	git submodule deinit --all -f
