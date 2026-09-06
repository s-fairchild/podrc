#!/usr/bin/env bats
# Exercises home/bin/yq directly, not via install-local.sh (that just
# copies the file -- see install-local.bats).

setup() {
  load 'test_helper'
  setup_podman_sandbox

  SCRIPT="${REPO_ROOT}/home/bin/yq"
  cd "${SANDBOX_DIR}"
}

teardown() {
  teardown_podman_sandbox
}

@test "yq: runs podman with -i --rm --pull=missing against the yq image" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "-i --rm --pull=missing"
  assert_output --partial "docker.io/mikefarah/yq:4.53.2"
}

@test "yq: mounts the current directory read-write at /data" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "-v=${SANDBOX_DIR}:/data:rw,rshared"
  assert_output --partial "--workdir=/data"
}

@test "yq: runs rootless via --userns=keep-id with label confinement disabled" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--userns=keep-id"
  assert_output --partial "--security-opt=label=disable"
}

@test "yq: forwards the YQ_* environment pattern into the container" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--env=YQ_*"
}

@test "yq: always passes --exit-status=1 ahead of the caller's arguments" {
  run "${SCRIPT}" '.foo' file.yaml
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--exit-status=1 .foo file.yaml"
}

@test "yq: forwards all arguments to the container, preserving embedded whitespace" {
  run "${SCRIPT}" '.foo' "bar   baz"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial ".foo bar   baz"
}

@test "yq: omits --log-level by default" {
  run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  refute_output --partial "--log-level"
}

@test "yq: honors a PODMAN_LOG_LEVEL override" {
  PODMAN_LOG_LEVEL="debug" run "${SCRIPT}"
  assert_success

  run cat "${PODMAN_STUB_LOG}"
  assert_output --partial "--log-level=debug"
}

@test "yq: propagates a podman failure instead of swallowing it" {
  export PODMAN_STUB_EXIT=3
  run "${SCRIPT}"
  assert_failure
  [[ "${status}" -eq 3 ]]
}
