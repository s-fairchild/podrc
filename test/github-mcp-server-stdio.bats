#!/usr/bin/env bats
# Exercises home/bin/github-mcp-server-stdio directly, not via
# install-local.sh (that just copies the file -- see install-local.bats).
# Uses its own sandbox rather than test_helper's
# setup_sandbox/teardown_sandbox: this script never touches systemctl,
# only $XDG_CONFIG_HOME/podrc (or its $HOME/.config fallback) and podman,
# so it stubs only podman (test/fixtures/podman-bin/) on top of a
# sandboxed HOME/XDG_CONFIG_HOME.
#
# The script `exec`s into podman as its very last step, so a successful
# run's exit status and stdout/stderr are the stub's, not the script's --
# assertions below check the stub's argv log instead of relying on
# anything the script itself would have printed after that point.
#
# NOTE: the GitHub App secret's default-name fallback
# (GITHUB_APP_PEM_PODMAN_SECRET_DEFAULT) isn't covered here -- its
# parameter expansion looks broken (never actually applies the default
# when the var is unset) and that block still carries a `# TODO add file
# mode` in the script, so these tests only exercise the always-set path
# the real template ships with instead of locking in behavior that may
# still change.

setup() {
  load 'test_helper'

  SCRIPT="${REPO_ROOT}/home/bin/github-mcp-server-stdio"
  ENV_FIXTURES_DIR="${FIXTURES_DIR}/github-mcp-server-env"

  SANDBOX_DIR="$(mktemp -d)"
  export SANDBOX_DIR
  export HOME="${SANDBOX_DIR}/home"
  export XDG_CONFIG_HOME="${HOME}/.config"
  mkdir -p "${HOME}"

  PODMAN_STUB_LOG="${SANDBOX_DIR}/podman.log"
  export PODMAN_STUB_LOG
  : >"${PODMAN_STUB_LOG}"

  export PATH="${FIXTURES_DIR}/podman-bin:${PATH}"

  unset GITHUB_MCP_SERVER_STDIO_CONTAINER_IMAGE_TAG PODMAN_STUB_EXIT
}

teardown() {
  rm -rf "${SANDBOX_DIR}"
}

#######################################
# Prints the sandboxed podrc config dir.
# Globals:
#   XDG_CONFIG_HOME
#######################################
mcpod_config_dir() {
  echo "${XDG_CONFIG_HOME}/podrc"
}

#######################################
# Copies the fixture env file into the sandboxed podrc config dir.
#######################################
write_env_file() {
  mkdir -p "$(mcpod_config_dir)"
  cp "${ENV_FIXTURES_DIR}/github-mcp-server.env" "$(mcpod_config_dir)/github-mcp-server.env"
}

@test "github-mcp-server-stdio: dies when the env file is missing" {
  run "${SCRIPT}"
  assert_failure
  [[ "${status}" -eq 1 ]]
  assert_output --partial "$(mcpod_config_dir)/github-mcp-server.env"
  assert_output --partial "make install"
}

@test "github-mcp-server-stdio: never invokes podman when the env file is missing" {
  run "${SCRIPT}"
  assert_failure

  [[ ! -s "${PODMAN_STUB_LOG}" ]]
}

@test "github-mcp-server-stdio: runs podman with -i --rm against the github-mcp-server image" {
  write_env_file

  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "run -i --rm"
  assert_output --partial "ghcr.io/github/github-mcp-server:latest"
}

@test "github-mcp-server-stdio: mounts the podman secret named in the env file" {
  write_env_file

  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--secret=test-github-app-private-key,target=test-github-app-private-key.key"
}

@test "github-mcp-server-stdio: passes GitHub App auth values as explicit --env flags" {
  write_env_file

  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--env=GITHUB_APP_PRIVATE_KEY_PATH=/run/secrets/test-github-app-private-key.key"
  assert_output --partial "--env=GITHUB_APP_ID=12345"
  assert_output --partial "--env=GITHUB_APP_INSTALLATION_ID=67890"
}

@test "github-mcp-server-stdio: runs the image in stdio mode with command logging enabled" {
  write_env_file

  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "stdio --enable-command-logging"
}

@test "github-mcp-server-stdio: defaults the image tag to latest" {
  write_env_file

  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "ghcr.io/github/github-mcp-server:latest"
}

@test "github-mcp-server-stdio: honors a GITHUB_MCP_SERVER_STDIO_CONTAINER_IMAGE_TAG override" {
  write_env_file

  GITHUB_MCP_SERVER_STDIO_CONTAINER_IMAGE_TAG="v1.2.3" run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "ghcr.io/github/github-mcp-server:v1.2.3"
  refute_output --partial "github-mcp-server:latest"
}

@test "github-mcp-server-stdio: falls back to \$HOME/.config when XDG_CONFIG_HOME is unset" {
  unset XDG_CONFIG_HOME
  mkdir -p "${HOME}/.config/podrc"
  cp "${ENV_FIXTURES_DIR}/github-mcp-server.env" "${HOME}/.config/podrc/github-mcp-server.env"

  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--env=GITHUB_APP_ID=12345"
}

@test "github-mcp-server-stdio: propagates a podman failure instead of swallowing it" {
  write_env_file

  export PODMAN_STUB_EXIT=3
  run "${SCRIPT}"
  assert_failure
  [[ "${status}" -eq 3 ]]
}
