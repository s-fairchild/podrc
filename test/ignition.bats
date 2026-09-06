#!/usr/bin/env bats
# Exercises home/bin/ignition directly, not via install-local.sh (that
# just copies the file -- see install-local.bats).

setup() {
  load 'test_helper'
  setup_podman_sandbox

  SCRIPT="${REPO_ROOT}/home/bin/ignition"
  cd "${SANDBOX_DIR}"
}

teardown() {
  teardown_podman_sandbox
}

@test "ignition: runs podman with -i --rm --pull=missing against the ignition-validate image" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "-i --rm --pull=missing"
  assert_output --partial "quay.io/coreos/ignition-validate:release"
}

@test "ignition: mounts the current directory read-only at /data" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "-v=${SANDBOX_DIR}:/data:ro,rshared"
  assert_output --partial "--workdir=/data"
}

@test "ignition: runs rootless via --userns=keep-id with label confinement disabled" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--userns=keep-id"
  assert_output --partial "--security-opt=label=disable"
}

@test "ignition: forwards all arguments to the container, preserving embedded whitespace" {
  run "${SCRIPT}" alpha "beta   gamma" delta
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "alpha beta   gamma delta"
}

@test "ignition: omits --log-level by default" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  refute_output --partial "--log-level"
}

@test "ignition: honors a PODMAN_LOG_LEVEL override" {
  PODMAN_LOG_LEVEL="debug" run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--log-level=debug"
}

@test "ignition: propagates a podman failure instead of swallowing it" {
  export PODMAN_STUB_EXIT=3
  run "${SCRIPT}"
  assert_failure
  [[ "${status}" -eq 3 ]]
}
