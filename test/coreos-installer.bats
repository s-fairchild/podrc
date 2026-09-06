#!/usr/bin/env bats
# Exercises home/bin/coreos-installer directly, not via install-local.sh
# (that just copies the file -- see install-local.bats).

setup() {
  load 'test_helper'
  setup_podman_sandbox

  SCRIPT="${REPO_ROOT}/home/bin/coreos-installer"
  cd "${SANDBOX_DIR}" || return 1
}

teardown() {
  teardown_podman_sandbox
}

@test "coreos-installer: runs podman with -i --rm --pull=missing against the coreos-installer image" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "-i --rm --pull=missing"
  assert_output --partial "quay.io/coreos/coreos-installer:release"
}

@test "coreos-installer: mounts the current directory read-only at /data" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "-v=${SANDBOX_DIR}:/data:ro,rshared"
  assert_output --partial "--workdir=/data"
}

@test "coreos-installer: runs rootless via --userns=keep-id with label confinement disabled" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--userns=keep-id"
  assert_output --partial "--security-opt=label=disable"
}

@test "coreos-installer: forwards all arguments to the container, preserving embedded whitespace" {
  run "${SCRIPT}" alpha "beta   gamma" delta
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "alpha beta   gamma delta"
}

@test "coreos-installer: omits --log-level by default" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  refute_output --partial "--log-level"
}

@test "coreos-installer: honors a PODMAN_LOG_LEVEL override" {
  PODMAN_LOG_LEVEL="debug" run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--log-level=debug"
}

@test "coreos-installer: propagates a podman failure instead of swallowing it" {
  export PODMAN_STUB_EXIT=3
  run "${SCRIPT}"
  assert_failure
  [[ "${status}" -eq 3 ]]
}
