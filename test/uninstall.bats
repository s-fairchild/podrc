#!/usr/bin/env bats

setup() {
  load 'test_helper'
  setup_sandbox
  "${REPO_ROOT}/hack/install.sh" >/dev/null
}

teardown() {
  teardown_sandbox
}

@test "uninstall: removes quadlet units but keeps env files" {
  run "${REPO_ROOT}/hack/uninstall.sh"
  assert_success

  [[ ! -e "${XDG_CONFIG_HOME}/containers/systemd/kubernetes-mcp-server.container" ]]
  [[ -f "${XDG_CONFIG_HOME}/podrc/github-mcp-server.env" ]]
}

@test "uninstall: removes each quadlet unit via podman quadlet rm --force" {
  run "${REPO_ROOT}/hack/uninstall.sh"
  assert_success

  run grep -q -- "quadlet rm --force kubernetes-mcp-server.container" "${PODMAN_STUB_LOG}"
  assert_success
}

@test "uninstall --purge: also removes env files" {
  run "${REPO_ROOT}/hack/uninstall.sh" --purge
  assert_success

  [[ ! -e "${XDG_CONFIG_HOME}/podrc" ]]
}

@test "uninstall: succeeds without removing anything when QUADLET_SRC_DIR has no quadlet units" {
  QUADLET_SRC_DIR="${FIXTURES_DIR}/empty-quadlets" run "${REPO_ROOT}/hack/uninstall.sh"
  assert_success

  run grep -q -- "quadlet rm" "${PODMAN_STUB_LOG}"
  assert_failure
}

@test "uninstall --purge: skips stopping network units when QUADLET_SRC_DIR has no *.network units" {
  QUADLET_SRC_DIR="${FIXTURES_DIR}/empty-quadlets" run "${REPO_ROOT}/hack/uninstall.sh" --purge
  assert_success

  run grep -q -- "--user stop" "${SYSTEMCTL_STUB_LOG}"
  assert_failure
}

@test "make uninstall: works via the Makefile target" {
  run make -C "${REPO_ROOT}" uninstall
  assert_success
}
