#!/usr/bin/env bash
# Shared setup loaded by every *.bats file via `load test_helper`.

load 'vendor/bats-support/load'
load 'vendor/bats-assert/load'

# -g: load() sources this file from inside a function, so plain `declare`
# would make these local to that call and invisible to setup()/the test body.
declare -g REPO_ROOT FIXTURES_DIR
# shellcheck disable=SC2034
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

    # Point install.sh's local-config overlay at a directory that doesn't
    # exist by default, instead of leaving it to fall back to this repo's
    # own real home/config/mcpod/ (git-ignored, may hold the
    # developer's real filled-in env/config files). install_local_config()
    # no-ops when its source dir is missing, so tests that don't care
    # about the overlay feature get a clean install; tests 3/4 in
    # install.bats that do exercise it override this per-command with
    # FIXTURES_DIR instead.
    export MCPOD_CONFIG_DIR="${SANDBOX_DIR}/unused-mcpod-config"
}

teardown_sandbox() {
    rm -rf "${SANDBOX_DIR}"
}
