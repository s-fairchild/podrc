#!/usr/bin/env bats
# Exercises home/bin/busybox directly, not via install-local.sh (that just
# copies the file -- see install-local.bats). The script `exec`s nothing
# itself (it calls podman as a plain command, not exec), so a successful
# run's exit status/output are the stub's, propagated through the
# script's own set -e.

setup() {
  load 'test_helper'
  setup_podman_sandbox

  SCRIPT="${REPO_ROOT}/home/bin/busybox"
  cd "${SANDBOX_DIR}" || return 1
}

teardown() {
  teardown_podman_sandbox
}

@test "busybox: runs podman with -i --rm against the busybox image" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "-i --rm"
  assert_output --partial "docker.io/busybox:stable-glibc"
}

@test "busybox: mounts the current directory read-only at /data" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "-v=${SANDBOX_DIR}:/data:ro,rshared"
  assert_output --partial "--workdir=/data"
}

@test "busybox: runs rootless via --userns=keep-id with label confinement disabled" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--userns=keep-id"
  assert_output --partial "--security-opt=label=disable"
}

@test "busybox: forwards all arguments to the container, preserving embedded whitespace" {
  run "${SCRIPT}" alpha "beta   gamma" delta
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "alpha beta   gamma delta"
}

@test "busybox: omits --log-level by default" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  refute_output --partial "--log-level"
}

@test "busybox: honors a PODMAN_LOG_LEVEL override" {
  PODMAN_LOG_LEVEL="debug" run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--log-level=debug"
}

@test "busybox: propagates a podman failure instead of swallowing it" {
  export PODMAN_STUB_EXIT=3
  run "${SCRIPT}"
  assert_failure
  [[ "${status}" -eq 3 ]]
}
