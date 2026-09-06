#!/usr/bin/env bats

setup() {
  load 'test_helper'
  setup_sandbox
}

teardown() {
  teardown_sandbox
}

@test "install: copies quadlet units into XDG_CONFIG_HOME/containers/systemd" {
  run "${REPO_ROOT}/hack/install.sh"
  assert_success

  [[ ! -e "${XDG_CONFIG_HOME}/containers/systemd/github-mcp-server.container" ]]
  [[ -f "${XDG_CONFIG_HOME}/containers/systemd/kubernetes-mcp-server.container" ]]
  [[ -f "${XDG_CONFIG_HOME}/containers/systemd/mcp.network" ]]
  [[ -f "${XDG_CONFIG_HOME}/containers/systemd/github-mcp-server.image" ]]
  [[ -f "${XDG_CONFIG_HOME}/containers/systemd/kubernetes-mcp-server.image" ]]
}

@test "install: writes env templates without pre-existing secrets" {
  run "${REPO_ROOT}/hack/install.sh"
  assert_success

  [[ -f "${XDG_CONFIG_HOME}/mcpod/github-mcp-server.env" ]]
  run grep -q 'GITHUB_APP_PEM_PODMAN_SECRET="github-app-private-key"' "${XDG_CONFIG_HOME}/mcpod/github-mcp-server.env"
  assert_success
}

@test "install: recursively installs nested env templates, preserving directory structure" {
  run "${REPO_ROOT}/hack/install.sh"
  assert_success

  [[ -f "${XDG_CONFIG_HOME}/mcpod/etc/kubernetes-mcp-server/config.toml" ]]
  [[ -f "${XDG_CONFIG_HOME}/mcpod/etc/kubernetes-mcp-server/conf.d/00-base.toml" ]]
}

@test "install: never overwrites an existing nested config file" {
  "${REPO_ROOT}/hack/install.sh"
  dest="${XDG_CONFIG_HOME}/mcpod/etc/kubernetes-mcp-server/config.toml"
  echo "log_level = 1" >"${dest}"

  run "${REPO_ROOT}/hack/install.sh"
  assert_success

  run grep -q "log_level = 1" "${dest}"
  assert_success
}

@test "install: does not install env/environment.d templates under XDG_CONFIG_HOME/mcpod" {
  run "${REPO_ROOT}/hack/install.sh"
  assert_success

  [[ ! -e "${XDG_CONFIG_HOME}/mcpod/environment.d" ]]
}

@test "install: never overwrites an existing env file" {
  "${REPO_ROOT}/hack/install.sh"
  env_file="${XDG_CONFIG_HOME}/mcpod/github-mcp-server.env"
  echo 'GITHUB_APP_PEM_PODMAN_SECRET="real-secret-name"' >"${env_file}"

  run "${REPO_ROOT}/hack/install.sh"
  assert_success

  run grep -q "real-secret-name" "${env_file}"
  assert_success
}

@test "install: reloads the user systemd manager (quadlet auto-enables via its own [Install])" {
  run "${REPO_ROOT}/hack/install.sh"
  assert_success

  run grep -qx -- "--user daemon-reload" "${SYSTEMCTL_STUB_LOG}"
  assert_success
  # Quadlet-generated units are enabled by the systemd generator itself
  # (from each unit's own [Install] WantedBy=) at daemon-reload time, not
  # via `systemctl enable` -- that call fails against real quadlet units
  # ("is transient or generated"), so install.sh must not run it.
  run grep -q -- "--user enable" "${SYSTEMCTL_STUB_LOG}"
  assert_failure
}

@test "make install: works via the Makefile target" {
  run make -C "${REPO_ROOT}" install
  assert_success
}
