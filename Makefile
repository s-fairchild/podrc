.DEFAULT_GOAL := help

BATS := test/vendor/bats-core/bin/bats
BASH_LOGGER := vendor/bash-logger/logging.sh

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

.PHONY: lint
lint: submodules ## Validate quadlet syntax (dry-run) and shellcheck the scripts
	@hack/lint.sh

.PHONY: generate
generate: submodules ## Materialize the systemd units quadlet would generate, into .generated/
	@hack/generate.sh

.PHONY: install
install: submodules lint ## Install quadlet units + env templates for the current user, enable services
	@hack/install.sh

.PHONY: install-local
install-local: submodules ## Install home/bin/* to ~/.local/bin (0744), home/lib/* to ~/.local/lib/mcpod (0644)
	@hack/install-local.sh

.PHONY: install-session-env
install-session-env: submodules ## Install the opt-in XDG_CONFIG_HOME environment.d template (session-wide, not just shells)
	@hack/install-session-env.sh

.PHONY: uninstall-session-env
uninstall-session-env: submodules ## Remove the environment.d template installed by install-session-env
	@hack/uninstall-session-env.sh

.PHONY: uninstall
uninstall: submodules ## Stop, disable, and remove the installed quadlet units (keeps env secrets)
	@hack/uninstall.sh

.PHONY: uninstall-purge
uninstall-purge: submodules ## Like uninstall, but also deletes env files (secrets) and this repo's podman containers/networks
	@hack/uninstall.sh --purge

.PHONY: test
test: submodules ## Run the bats test suite against the make targets
	@$(BATS) test/*.bats

.PHONY: coverage
coverage: submodules ## Run the bats suite under kcov, report HTML coverage into .generated/coverage/
	@hack/coverage.sh

.PHONY: submodules
submodules: ## Fetch vendored dependencies (bats-core/helpers, bash-logger)
	@if [ ! -x "$(BATS)" ] || [ ! -f "$(BASH_LOGGER)" ]; then \
		git submodule update --init --recursive; \
	fi

.PHONY: clean
clean: ## Remove generated/build artifacts (not installed units)
	rm -rf .generated .coverage

.PHONY: distclean
distclean: clean ## Also deinitialize vendored submodules
	git submodule deinit --all -f
