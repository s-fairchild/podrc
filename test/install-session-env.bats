#!/usr/bin/env bats

setup() {
  load 'test_helper'
  setup_sandbox
}

teardown() {
  teardown_sandbox
}

@test "install-session-env: writes the environment.d template without pre-existing edits" {
  run "${REPO_ROOT}/hack/install-session-env.sh"
  assert_success

  [[ -f "${XDG_CONFIG_HOME}/environment.d/mcpod.conf" ]]
  run grep -q '#XDG_CONFIG_HOME=%h/.config' "${XDG_CONFIG_HOME}/environment.d/mcpod.conf"
  assert_success
}

@test "install-session-env: never overwrites an existing conf file" {
  "${REPO_ROOT}/hack/install-session-env.sh"
  dest="${XDG_CONFIG_HOME}/environment.d/mcpod.conf"
  echo 'XDG_CONFIG_HOME=%h/.config-custom' >"${dest}"

  run "${REPO_ROOT}/hack/install-session-env.sh"
  assert_success

  run grep -q '.config-custom' "${dest}"
  assert_success
}

@test "make install-session-env: works via the Makefile target" {
  run make -C "${REPO_ROOT}" install-session-env
  assert_success
}

@test "uninstall-session-env: removes the installed conf file" {
  "${REPO_ROOT}/hack/install-session-env.sh"
  dest="${XDG_CONFIG_HOME}/environment.d/mcpod.conf"
  [[ -f "${dest}" ]]

  run "${REPO_ROOT}/hack/uninstall-session-env.sh"
  assert_success

  [[ ! -e "${dest}" ]]
}

@test "uninstall-session-env: succeeds even if nothing was installed" {
  run "${REPO_ROOT}/hack/uninstall-session-env.sh"
  assert_success
}

@test "make uninstall-session-env: works via the Makefile target" {
  "${REPO_ROOT}/hack/install-session-env.sh"

  run make -C "${REPO_ROOT}" uninstall-session-env
  assert_success

  [[ ! -e "${XDG_CONFIG_HOME}/environment.d/mcpod.conf" ]]
}
