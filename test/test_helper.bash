#!/usr/bin/env bash
# Shared setup loaded by every *.bats file via `load test_helper`.

load 'vendor/bats-support/load'
load 'vendor/bats-assert/load'

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"

# Sandbox HOME/XDG dirs plus a stubbed `systemctl` on PATH, so install/
# uninstall tests never touch the real user systemd manager or the
# real ~/.config. Call from setup(); pairs with teardown_sandbox.
setup_sandbox() {
	SANDBOX_DIR="$(mktemp -d)"
	export SANDBOX_DIR
	export HOME="${SANDBOX_DIR}/home"
	export XDG_CONFIG_HOME="${HOME}/.config"
	mkdir -p "${HOME}"

	SYSTEMCTL_STUB_LOG="${SANDBOX_DIR}/systemctl.log"
	export SYSTEMCTL_STUB_LOG
	: >"${SYSTEMCTL_STUB_LOG}"

	export PATH="${FIXTURES_DIR}/bin:${PATH}"
}

teardown_sandbox() {
	rm -rf "${SANDBOX_DIR}"
}
