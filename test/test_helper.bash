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

#######################################
# Sandboxes HOME/XDG dirs plus a stubbed `systemctl`/`claude` on PATH, so
# install/uninstall tests never touch the real user systemd manager, the
# real ~/.config, or the real `claude mcp` config. Call from setup();
# pairs with teardown_sandbox.
# Globals:
#   FIXTURES_DIR
#   SANDBOX_DIR (set by this function)
#   SYSTEMCTL_STUB_LOG (set by this function)
#   CLAUDE_STUB_LOG (set by this function)
#   CLAUDE_STUB_STATE_DIR (set by this function)
#######################################
setup_sandbox() {
  SANDBOX_DIR="$(mktemp -d)"
  export SANDBOX_DIR
  export HOME="${SANDBOX_DIR}/home"
  export XDG_CONFIG_HOME="${HOME}/.config"
  mkdir -p "${HOME}"

  SYSTEMCTL_STUB_LOG="${SANDBOX_DIR}/systemctl.log"
  export SYSTEMCTL_STUB_LOG
  : >"${SYSTEMCTL_STUB_LOG}"

  CLAUDE_STUB_LOG="${SANDBOX_DIR}/claude.log"
  export CLAUDE_STUB_LOG
  : >"${CLAUDE_STUB_LOG}"
  CLAUDE_STUB_STATE_DIR="${SANDBOX_DIR}/claude-mcp-state"
  export CLAUDE_STUB_STATE_DIR
  mkdir -p "${CLAUDE_STUB_STATE_DIR}"

  export PATH="${FIXTURES_DIR}/bin:${PATH}"
}

#######################################
# Removes the sandbox directory setup_sandbox created. Call from teardown().
# Globals:
#   SANDBOX_DIR
#######################################
teardown_sandbox() {
  rm -rf "${SANDBOX_DIR}"
}
